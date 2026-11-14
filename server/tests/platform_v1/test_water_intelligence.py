"""Cached real provider bytes plus labeled fault mutations; actual compiled Rust."""

import hashlib
import json
import os
from datetime import datetime
from pathlib import Path
import time

import pytest
from fastapi.testclient import TestClient

from earthsync.assistant.models import ChatRequest
from earthsync.assistant.service import explain
from earthsync.platform_v1.api import PREFIX, create_app
from earthsync.platform_v1.catalog import Catalog
from earthsync.platform_v1.context import assistant_context
from earthsync.platform_v1.engine import RustEngine
from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.maintenance import backup, restore
from earthsync.platform_v1.models import AssessmentInput, ClimateQuery, FarmInput
from earthsync.platform_v1.orchestrate import Orchestrator
from earthsync.platform_v1.providers.power_daily import read_daily
from earthsync.platform_v1.providers.transport import Capture
from earthsync.platform_v1.reference_v2 import ReferenceCatalog
from earthsync.platform_v1.water import CONTRACT, PARAMS, WaterPipeline

ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "docs/integration/7w/evidence"


@pytest.fixture
def water_query():
    return ClimateQuery(
        point={"latitude": 42.0308, "longitude": -93.6319},
        start="2024-07-01",
        end="2024-07-07",
    )


@pytest.fixture
def engine():
    path = os.getenv("EARTHSYNC_TEST_V03")
    if not path:
        pytest.skip("Set EARTHSYNC_TEST_V03 to current integrated v03_demo")
    p = Path(path)
    return RustEngine(str(p), hashlib.sha256(p.read_bytes()).hexdigest())


def capture(parameter, mutation=None):
    receipt = next(
        r
        for r in json.loads((FIXTURES / "power-probe-receipts.json").read_text())
        if r["parameter"] == parameter
    )
    body = (FIXTURES / f"power-{parameter}.real.json").read_bytes()
    assert hashlib.sha256(body).hexdigest() == receipt["sha256"]
    if mutation:
        d = json.loads(body)
        mutation(d)
        body = json.dumps(d).encode()
    return Capture(
        body,
        datetime.fromisoformat(receipt["retrieved_at"]),
        {"content-type": "application/json"},
    )


class CachedReal:
    async def get(self, url, params):
        return capture(params["parameters"])


@pytest.fixture
def references():
    return ReferenceCatalog()


@pytest.mark.parametrize("parameter", list(PARAMS))
def test_parameter_contracts_and_faults(water_query, parameter):
    read_daily(capture(parameter), water_query, parameter, contract=CONTRACT)
    for mutate in [
        lambda d: d["header"].update(sources=["GEOSIT"]),
        lambda d: d["header"].update(time_standard="UTC"),
        lambda d: d["parameters"][parameter].update(units="invented"),
        lambda d: d["geometry"].update(coordinates=[0, 0, 0]),
    ]:
        with pytest.raises(PlatformError):
            read_daily(
                capture(parameter, mutate), water_query, parameter, contract=CONTRACT
            )


async def test_real_calculation_persistence_rust_reference_assistant_restore(
    store, engine, references, water_query, tmp_path
):
    owner = "alice"
    farm = store.create_farm(
        owner,
        FarmInput(
            name="Software-test farm, not field ground truth",
            confirmed_point=water_query.point,
            confirmed_on="2026-11-14",
            production_system="rainfed",
        ),
    )
    pipeline = WaterPipeline(CachedReal(), engine)
    result = await pipeline.retrieve(water_query)
    assert not result["gaps"] and len(result["records"]) == 7
    calculated = await pipeline.calculate(result["records"], water_query)
    c = calculated.source_metadata["calculation"]
    assert c["rainfall_total_mm"] == pytest.approx(59.97)
    assert c["et0_usable_days"] == 6 and c["et0_total_mm"] is None
    assert c["days"][1]["missing_reason"] == "RADIATION_METHOD_OUTSIDE_SUPPORTED_DOMAIN"
    for r in [*result["records"], calculated]:
        from earthsync.platform_v1.models import Evidence

        store.save_evidence(owner, Evidence.model_validate(r), farm.id)
    selection = references.project(
        "rice.mm.calendar-5-sessions-0@1", "MM-FAO-AEZ-001", "rainfed"
    )
    assert selection[0]["rules"] == [] and not selection[0]["approved_for_candidates"]
    query = AssessmentInput(
        farm_id=farm.id,
        catalog_version="v2",
        evidence_ids=[r["id"] for r in result["records"]] + [calculated.id],
        pilot_id="MM-FAO-AEZ-001",
        profile_ids=["rice.mm.calendar-5-sessions-0@1"],
        start=water_query.start,
        end=water_query.end,
    )
    decision = await Orchestrator(store, engine, Catalog(), references).assess(
        owner, query
    )
    context = decision["result"]["data"]["context"]
    assert len(context["climate"]) == 4 and context["catalog"] == [selection[0]]
    assert not decision["result"]["data"]["candidates"]
    assert decision["catalog_projection"][0]["sources"]
    assert decision["environmental_metrics"][0] == c
    assert decision["water_findings"]["net_irrigation"]["value"] is None
    ctx = assistant_context(store, owner, farm.id)
    answer = explain(
        ChatRequest(
            schema_version="assistant.v1-proposal",
            context=ctx,
            question="How much rainfall did this area receive?",
            language="en",
            expanded=True,
        )
    )
    assert any(
        "59.97" in claim.text and claim.category == "deterministic_calculation"
        for claim in answer.claims
    )
    answer = explain(
        ChatRequest(
            schema_version="assistant.v1-proposal",
            context=ctx,
            question="What does ET0 mean?",
            language="en",
            expanded=True,
        )
    )
    assert answer.intent == "water" and not any(
        "27.4137" in claim.text for claim in answer.claims
    )
    backup(store, tmp_path / "backup")
    recovered = restore(tmp_path / "backup", tmp_path / "restored")
    assert recovered.decisions(owner, farm.id) == store.decisions(owner, farm.id)
    assert recovered.evidence(owner, calculated.id, farm.id) == calculated
    with pytest.raises(PlatformError):
        store.evidence("other", calculated.id, farm.id)


async def test_outage_and_absent_day_are_not_zero(engine, water_query):
    class Outage:
        async def get(self, *args):
            raise PlatformError("PROVIDER_UNAVAILABLE", 503, True)

    pipeline = WaterPipeline(Outage(), engine)
    result = await pipeline.retrieve(water_query)
    assert len(result["gaps"]) == 7 and result["records"] == []
    c = (await pipeline.calculate([], water_query)).source_metadata["calculation"]
    assert c["rainfall_total_mm"] is None and c["et0_partial_sum_mm"] is None
    missing = read_daily(
        capture(
            "T2M_MIN", lambda d: d["properties"]["parameter"]["T2M_MIN"].pop("20240701")
        ),
        water_query,
        "T2M_MIN",
        contract=CONTRACT,
    )
    assert (
        missing.measurements[0].value is None
        and missing.measurements[0].missing_reason == "ABSENT_DAY"
    )


def test_lookup_ambiguity_gates_and_v1_is_unchanged(references):
    assert references.lookup("corn")["status"] == "ambiguous"
    result = references.lookup("rice")
    assert len(result["rule_review"]["candidates"]) == 12
    assert result["rule_review"]["executable_rule_count"] == 0
    assert all(
        c["execution_status"] == "blocked" for c in result["rule_review"]["candidates"]
    )
    assert "linear" in result["rule_review"]["method_findings"]["kc_curve"]
    assert result["sources"] and result["claims"]
    result["profiles"][0]["parameters"].clear()
    assert references.lookup("rice")["profiles"][0]["parameters"]
    with pytest.raises(PlatformError):
        references.project("rice.global.ecology@1", None, "rainfed")
    v1 = ROOT / "data/crop-knowledge/v1/catalog.json"
    assert (
        hashlib.sha256(v1.read_bytes()).hexdigest()
        == "2926584bce3693dff7433afe9c05c535a6d5d1e609fb502d4e2f6017f398fb0e"
    )


def test_http_water_job_and_source_outage(store, engine, water_query):
    with TestClient(
        create_app(
            store=store, engine=engine, transport=CachedReal(), local_enabled=True
        ),
        base_url="http://127.0.0.1",
        client=("127.0.0.1", 10000),
    ) as client:
        farm = client.post(
            PREFIX + "/farms",
            json={
                "name": "Software test",
                "confirmed_point": water_query.point.model_dump(),
                "confirmed_on": "2026-11-14",
                "production_system": "rainfed",
            },
        ).json()
        response = client.post(
            PREFIX + "/water/jobs",
            json={"farm_id": farm["id"], "query": water_query.model_dump(mode="json")},
        )
        assert response.status_code == 202
        for _ in range(200):
            job = client.get(PREFIX + "/jobs/" + response.json()["id"]).json()
            if job["status"] not in ("queued", "running"):
                break
            time.sleep(0.01)
        assert job["status"] == "succeeded", job
        assert len(job["result"]["records"]) == 8 and not job["result"]["cache_hit"]
        assert (
            client.get(PREFIX + "/crop-references?q=rice").json()["status"]
            == "reference_only"
        )
        assert (
            len(
                client.get(PREFIX + "/farms/" + farm["id"] + "/context").json()[
                    "evidence"
                ]
            )
            == 8
        )
