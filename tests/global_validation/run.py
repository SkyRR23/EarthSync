# ruff: noqa: E402  # Isolated harness resolves the unchanged baseline modules.
"""Opt-in validation of an immutable release through its real production paths.

Raw source captures/test stores remain outside Git. Only public-site summaries
and numerical results are exported. No provider or Rust algorithm is replaced.
"""

import argparse
import asyncio
import csv
from datetime import datetime, timezone, timedelta
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
from reference import reference_et0
from earthsync.platform_v1.engine import RustEngine
from earthsync.platform_v1.models import (
    ClimateQuery,
    Point,
    FarmInput,
    Evidence,
    AssessmentInput,
    HistoryInput,
)
from earthsync.platform_v1.providers.transport import Transport, Capture
from earthsync.platform_v1.providers.soil_webdav import SoilWebdav
from earthsync.platform_v1.providers.gfs import GfsForecast
from earthsync.platform_v1.water import WaterPipeline
from earthsync.platform_v1.store import Store
from earthsync.platform_v1.catalog import Catalog
from earthsync.platform_v1.reference_v2 import ReferenceCatalog
from earthsync.platform_v1.orchestrate import Orchestrator
from earthsync.platform_v1.comparisons import Comparisons, ComparisonInput
from earthsync.platform_v1.context import assistant_context
from earthsync.assistant.models import ChatRequest
from earthsync.assistant.service import explain
import httpx


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, allow_nan=False, default=str) + "\n")


class RecordedTransport:
    def __init__(self, client, cache, budget):
        self.live = Transport(client, concurrency=2)
        self.cache, self.budget = cache, budget
        self.requests, self.hits, self.receipts = 0, 0, []
        self.lock = asyncio.Lock()

    async def get(self, url, params):
        key = hashlib.sha256(
            json.dumps([url, params], sort_keys=True).encode()
        ).hexdigest()
        body, meta = self.cache / (key + ".body"), self.cache / (key + ".json")
        # Serialize cache admission so common VRT metadata is never refetched.
        async with self.lock:
            if body.exists() and meta.exists():
                m = json.loads(meta.read_text())
                raw = body.read_bytes()
                assert hashlib.sha256(raw).hexdigest() == m["sha256"]
                self.hits += 1
                return Capture(
                    raw, datetime.fromisoformat(m["retrieved_at"]), m["headers"]
                )
            if self.requests >= self.budget:
                raise RuntimeError("Bounded provider-request budget exhausted")
            self.requests += 1
            started = time.perf_counter()
            try:
                cap = await self.live.get(url, params)
                body.write_bytes(cap.body)
                m = {
                    "url": url,
                    "params": params,
                    "sha256": cap.sha256,
                    "retrieved_at": cap.retrieved_at.isoformat(),
                    "headers": cap.headers,
                    "bytes": len(cap.body),
                    "elapsed_seconds": time.perf_counter() - started,
                    "classification": "REAL",
                }
                save(meta, m)
                self.receipts.append(m)
                return cap
            except Exception as exc:
                self.receipts.append(
                    {
                        "url": url,
                        "params": params,
                        "error": getattr(exc, "code", type(exc).__name__),
                        "elapsed_seconds": time.perf_counter() - started,
                        "classification": "UNAVAILABLE",
                    }
                )
                raise


async def rotation(
    store, engine, site, records, period, owner="global-validation-synthetic", farm=None
):
    lat, lon = site["latitude"], site["longitude"]
    polygon = {
        "type": "Polygon",
        "coordinates": [
            [
                [lon - 0.0001, lat - 0.0001],
                [lon + 0.0001, lat - 0.0001],
                [lon + 0.0001, lat + 0.0001],
                [lon - 0.0001, lat + 0.0001],
                [lon - 0.0001, lat - 0.0001],
            ]
        ],
    }
    farm = farm or store.create_farm(
        owner,
        FarmInput(
            name="SYNTHETIC validation " + site["id"],
            confirmed_point={"latitude": lat, "longitude": lon},
            confirmed_polygon=polygon,
            confirmed_on="2026-11-14",
            production_system="rainfed",
        ),
    )
    for r in records:
        store.save_evidence(owner, Evidence.model_validate(r), farm.id)
    # Synthetic dates test chronology only; not plausible crop maturity or site history.
    store.save_history(
        owner,
        farm.id,
        HistoryInput(
            crop_id="ecocrop.1574@1", fallow=False, start="2024-06-01", end="2024-06-20"
        ),
    )
    native = Orchestrator(store, engine, Catalog(), ReferenceCatalog())
    alternatives = [
        ("mung_bean.mm.rainfed-research@1", "MM-research-target"),
        ("sesame.mm.calendar-75-sessions-0@1", "MM-FAO-AEZ-001"),
        ("groundnut.mm.calendar-65-sessions-0@1", "MM-FAO-AEZ-001"),
    ]
    ids = []
    findings = []
    for index, (ident, scope) in enumerate(alternatives):
        query = AssessmentInput(
            farm_id=farm.id,
            catalog_version="v2",
            evidence_ids=[r["id"] for r in records],
            start=period[0],
            end=period[1],
            sequential_field=True,
            plans=[
                {
                    "profile_id": "rice.mm.calendar-5-sessions-0@1",
                    "reference_region": "MM-FAO-AEZ-001",
                    "start": period[0],
                    "end": period[0][:8] + "03",
                },
                {
                    "profile_id": ident,
                    "reference_region": scope,
                    "start": period[0][:8] + ("03" if index == 2 else "04"),
                    "end": period[1],
                },
            ],
        )
        result = await native.assess(owner, query)
        assert result["recommendation_eligible"] is False
        assert not result["result"]["data"]["candidates"]
        assert all(
            not p["rules"] for p in result["result"]["data"]["context"]["catalog"]
        )
        assert result["result"]["data"]["context"]["region_id"] is None
        ids.append(result["decision_id"])
        findings.append(result["result"]["data"]["findings"])
    saved = Comparisons(store).save(
        owner,
        farm.id,
        ComparisonInput(
            id=uuid4(),
            name="SYNTHETIC baseline/A/B " + site["id"],
            baseline_decision_id=ids[0],
            alternative_decision_ids=ids[1:],
            baseline_declared_existing_plan=True,
            priorities=["less_water", "soil", "less_labor"],
            exploration_reason="Hypothetical software chronology test; no real practice or agricultural suitability claim",
            practical_constraints="Irrigation, drainage, budget and market access unknown",
        ),
    )
    assert saved in Comparisons(Store(store.path.parent)).list(owner, farm.id)
    answer = explain(
        ChatRequest(
            schema_version="assistant.v1-proposal",
            context=assistant_context(store, owner, farm.id),
            question="Explain my crop rotation and saved comparison",
            language="en",
            expanded=True,
        )
    )
    assert len(answer.decisions) >= 3 and answer.citations
    assert any("Alternative B" in c.text for c in answer.claims)
    assert any(f["status"] == "conflicts_with_supplied_evidence" for f in findings[2])
    try:
        store.farm("another-owner", farm.id)
    except Exception:
        pass
    else:
        raise AssertionError("Cross-owner farm access accepted")
    return {
        "status": "PASS",
        "strategies": 3,
        "native_decisions": 3,
        "reopened": True,
        "assistant_citations": len(answer.citations),
        "reference_scope": "Myanmar source profiles retained as references globally, never farm applicability",
        "classification": "SYNTHETIC farmer scenario + REAL/CACHED REAL climate; actual Rust and SQLite",
    }


async def main(args):
    manifest = json.loads((ROOT / "tests/global_validation/sites.json").read_text())
    protocol = json.loads((ROOT / "tests/global_validation/protocol.json").read_text())
    subject = manifest["release_sha"]
    assert (
        hashlib.sha256(
            (ROOT / "tests/global_validation/sites.json").read_bytes()
        ).hexdigest()
        == protocol["site_manifest_sha256"]
    )
    # Validation files may change; all production/review bytes must remain the baseline.
    assert (
        subprocess.check_output(
            [
                "git",
                "-C",
                str(ROOT),
                "diff",
                subject,
                "--",
                "app",
                "engine",
                "server",
                "data",
            ]
        )
        == b""
    )
    private = args.private.absolute()
    out = args.output.absolute()
    assert (
        private.resolve() == private and ROOT not in private.parents and private != ROOT
    )
    private.mkdir(parents=True, exist_ok=True, mode=0o700)
    private.chmod(0o700)
    cache = private / "captures"
    cache.mkdir(exist_ok=True, mode=0o700)
    executable = args.engine.absolute()
    engine = RustEngine(str(executable), args.engine_sha)
    store = Store(private / "store")
    headers = {
        "User-Agent": "EarthSync-reproducible-validation/1.0 (bounded public research; no load testing)"
    }
    summary = {
        "release_sha": subject,
        "site_manifest_sha256": protocol["site_manifest_sha256"],
        "started_at": datetime.now(timezone.utc).isoformat(),
        "native_sha256": engine.sha256,
        "hardware": {
            "system": platform.platform(),
            "python": platform.python_version(),
            "cpu_count": os.cpu_count(),
        },
        "sites": [],
        "et0": [],
    }
    async with httpx.AsyncClient(timeout=30, headers=headers) as client:
        transport = RecordedTransport(client, cache, protocol["provider_max_requests"])
        pipeline = WaterPipeline(transport, engine)
        for site in manifest["sites"]:
            row = {"site_id": site["id"], "release_sha": subject, "periods": []}
            july = []
            for period in protocol["periods"]:
                query = ClimateQuery(
                    point={
                        "latitude": site["latitude"],
                        "longitude": site["longitude"],
                    },
                    start=period[0],
                    end=period[1],
                )
                start = time.perf_counter()
                try:
                    result = await pipeline.retrieve(query)
                    calculation = await pipeline.calculate(result["records"], query)
                    original = calculation.source_metadata["calculation"]
                    request = original["input"]
                    for index, computed in enumerate(original["days"]):
                        expected = None
                        difference = None
                        relative = None
                        status = "WITHHELD"
                        if computed["et0_mm"] is not None:
                            expected = reference_et0(
                                request["latitude"],
                                request["elevation_m"],
                                request["days"][index],
                            )
                            difference = abs(expected - computed["et0_mm"])
                            relative = difference / max(abs(expected), 1e-12)
                            status = (
                                "PASS"
                                if difference
                                <= protocol["et0_absolute_tolerance_mm"]
                                + protocol["et0_relative_tolerance"] * abs(expected)
                                else "FAILED"
                            )
                        summary["et0"].append(
                            {
                                "release_sha": subject,
                                "site_id": site["id"],
                                "date": str(query.start + timedelta(days=index)),
                                "rust_et0_mm": computed["et0_mm"],
                                "reference_et0_mm": expected,
                                "absolute_difference_mm": difference,
                                "relative_difference": relative,
                                "status": status,
                                "withheld_reason": computed.get("missing_reason"),
                                "classification": "NUMERICALLY VERIFIED from real provider inputs"
                                if status == "PASS"
                                else status,
                            }
                        )
                    row["periods"].append(
                        {
                            "start": period[0],
                            "end": period[1],
                            "time_standard": "NASA_POWER_LST",
                            "status": "PASS" if not result["gaps"] else "PARTIAL",
                            "records": len(result["records"]),
                            "gaps": result["gaps"],
                            "et0_usable_days": original["et0_usable_days"],
                            "expected_days": original["expected_days"],
                            "elapsed_seconds": time.perf_counter() - start,
                            "source_hashes": [
                                r["response_sha256"] for r in result["records"]
                            ],
                        }
                    )
                    save(
                        private / site["id"] / (period[0] + ".json"),
                        {
                            "production_result": result,
                            "rust_calculation": calculation.model_dump(mode="json"),
                        },
                    )
                    if query.start.month == 7:
                        july = [*result["records"], calculation.model_dump(mode="json")]
                except Exception as exc:
                    row["periods"].append(
                        {
                            "start": period[0],
                            "end": period[1],
                            "status": "FAILED",
                            "error": getattr(exc, "code", type(exc).__name__),
                        }
                    )
                    save(
                        private / site["id"] / (period[0] + "-error.json"),
                        {"error": str(exc)},
                    )
            point = Point(latitude=site["latitude"], longitude=site["longitude"])
            try:
                soil = await SoilWebdav(transport, store).retrieve(point)
                cell = next(c for c in soil["cells"] if c["at_query_point"])
                assert cell["value"] is None or math.isclose(
                    cell["value"], cell["raw"] / 10
                )
                assert soil["depth_cm"] == [0, 5] and soil["resolution_m"] == 250
                save(private / site["id"] / "soil.json", soil)
                row["soil"] = {
                    "status": soil["status"],
                    "raw": cell["raw"],
                    "ph": cell["value"],
                    "depth_cm": [0, 5],
                    "resolution_m": 250,
                    "source_sha256": soil["source_sha256"],
                    "classification": "SOURCE-CONSISTENT; not independently field-validated",
                }
            except Exception as exc:
                row["soil"] = {
                    "status": "UNAVAILABLE",
                    "error": getattr(exc, "code", type(exc).__name__),
                }
            try:
                row["rotation"] = await rotation(
                    store, engine, site, july, protocol["periods"][1]
                )
            except Exception as exc:
                row["rotation"] = {
                    "status": "FAILED",
                    "error": getattr(exc, "code", type(exc).__name__),
                }
                save(private / site["id"] / "rotation-error.json", {"error": str(exc)})
            summary["sites"].append(row)
            summary["provider"] = {
                "network_attempts": transport.requests,
                "disk_cache_hits": transport.hits,
            }
            save(out / "evidence/results.json", summary)
            print(
                site["id"],
                [p["status"] for p in row["periods"]],
                row["soil"]["status"],
                row["rotation"]["status"],
                flush=True,
            )
        # A bounded reference-only forecast probe at two contrasting public sites.
        summary["forecasts"] = []
        for site in [manifest["sites"][0], manifest["sites"][6]]:
            try:
                result = await GfsForecast(transport, store).retrieve(
                    Point(latitude=site["latitude"], longitude=site["longitude"])
                )
                assert all(
                    math.isclose(
                        r["temperature_c"],
                        r["raw_temperature_k"] - 273.15,
                        abs_tol=1e-10,
                    )
                    for r in result["records"]
                    if r["temperature_c"] is not None
                )
                save(private / site["id"] / "forecast.json", result)
                summary["forecasts"].append(
                    {
                        "site_id": site["id"],
                        "status": "PASS",
                        "records": len(result["records"]),
                        "model_initialized_at": result["model_initialized_at"],
                        "issued_at": result["issued_at"],
                        "classification": "SOFTWARE/SOURCE CONSISTENCY; forecast errors not measurable without matched later station observations",
                    }
                )
            except Exception as exc:
                summary["forecasts"].append(
                    {
                        "site_id": site["id"],
                        "status": "UNAVAILABLE",
                        "error": getattr(exc, "code", type(exc).__name__),
                    }
                )
        summary["finished_at"] = datetime.now(timezone.utc).isoformat()
        summary["provider"] = {
            "network_attempts": transport.requests,
            "disk_cache_hits": transport.hits,
            "successful_network_responses": sum(
                "sha256" in r for r in transport.receipts
            ),
        }
        save(out / "evidence/provider-receipts.json", transport.receipts)
        save(out / "evidence/results.json", summary)
    for filename, key in [("ET0_NUMERICAL_VALIDATION.csv", "et0")]:
        rows = summary[key]
        if rows:
            with (out / filename).open("w", newline="") as stream:
                writer = csv.DictWriter(
                    stream, fieldnames=list(rows[0]), lineterminator="\n"
                )
                writer.writeheader()
                writer.writerows(rows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--private", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/validation")
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--engine-sha", required=True)
    args = parser.parse_args()
    if not args.live:
        parser.error("Explicit --live required; no provider requests by default")
    asyncio.run(main(args))
