"""Historical mechanics: cached real source captures and explicit synthetic faults."""

import hashlib
import os
from datetime import date, datetime, timezone
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from earthsync.platform_v1.api import PREFIX, create_app
from earthsync.platform_v1.catalog import Catalog
from earthsync.platform_v1.engine import RustEngine
from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.historical import (
    ArchiveInput,
    Historical,
    Period,
    contextual_baseline,
    monthly,
    summary,
)
from earthsync.platform_v1.models import FarmLinkInput
from earthsync.platform_v1.orchestrate import Orchestrator
from earthsync.platform_v1.reference_v2 import ReferenceCatalog
from earthsync.platform_v1.store import Store
from test_water_intelligence import CachedReal, capture, water_query  # noqa: F401

REVISION = "2026-11-14T00:00:00Z"
PROFILE = "rice.mm.calendar-5-sessions-0@1"


class Sources(CachedReal):
    def __init__(self):
        self.calls = 0

    async def get(self, url, params):
        self.calls += 1
        if params["parameters"] == "T2M":
            raise PlatformError("UNSUPPORTED_SOURCE_LINEAGE", 502)
        return await super().get(url, params)


@pytest.fixture
def engine():
    p = os.environ.get("EARTHSYNC_TEST_V03")
    if not p:
        pytest.skip("Set EARTHSYNC_TEST_V03 for actual Rust historical tests")
    return RustEngine(p, hashlib.sha256(Path(p).read_bytes()).hexdigest())


def link(store, owner="alice"):
    return store.link_farm(
        owner,
        FarmLinkInput(
            local_profile_id="synthetic-historical-test",
            revision=REVISION,
            farm={
                "name": "Synthetic software-test farm",
                "confirmed_point": {"latitude": 42.0308, "longitude": -93.6319},
                "confirmed_on": "2026-11-14",
                "production_system": "rainfed",
            },
        ),
    )["farm"]


@pytest.fixture
def lab(store, engine):
    return Historical(
        store,
        Sources(),
        engine,
        Orchestrator(store, engine, Catalog(), ReferenceCatalog()),
    )


def archive_request(farm):
    return {
        "farm_id": str(farm.id),
        "revision": REVISION,
        "start": "2024-07-01",
        "end": "2024-07-07",
    }


def scenario(farm, archive):
    return {
        "id": str(uuid4()),
        "farm_id": str(farm.id),
        "revision": REVISION,
        "name": "Hypothetical mechanics test",
        "archive_ids": [archive["id"]],
        "periods": [{"start": "2024-07-01", "end": "2024-07-07"}],
        "strategies": [
            {
                "identity": k,
                "plans": [
                    {
                        "profile_id": PROFILE,
                        "reference_region": "MM-FAO-AEZ-001",
                        "start": "2024-07-01",
                        "end": "2024-07-03",
                    },
                    {
                        "profile_id": PROFILE,
                        "reference_region": "MM-FAO-AEZ-001",
                        "start": "2024-07-05",
                        "end": "2024-07-07",
                    },
                ],
            }
            for k in ("baseline", "alternative_a", "alternative_b")
        ],
    }


async def test_archive_reuse_missingness_and_restart(lab, store, engine):
    farm = link(store)
    a = await lab.retrieve("alice", archive_request(farm))
    assert lab.transport.calls == 8
    assert a["summary"]["metrics"]["rainfall"]["value"] == pytest.approx(59.97)
    et = a["summary"]["metrics"]["et0"]
    assert et["valid_days"] == 6 and et["missing_days"] == 1
    assert et["value"] > 0 and et["complete_value"] is None
    assert a["summary"]["metrics"]["temperature"]["value"] is None
    b = await lab.retrieve("alice", archive_request(farm))
    assert b["id"] == a["id"] and b["source_mode"] == "cached_real"
    assert b["retrieved_at"] == a["retrieved_at"] and lab.transport.calls == 8
    restarted = Historical(
        Store(store.path.parent), Sources(), engine, lab.orchestrator
    )
    assert (
        restarted.replay("alice", farm.id, a["id"])["source_hashes"]
        == a["source_hashes"]
    )
    with pytest.raises(PlatformError, match="NOT_FOUND"):
        restarted.get("bob", farm.id, a["id"])
    wrong = {**archive_request(farm), "revision": "2026-11-13T00:00:00Z"}
    with pytest.raises(PlatformError, match="CONFIRMED_FARM_REVISION_REQUIRED"):
        await lab.retrieve("alice", wrong)


async def test_actual_rust_changes_immutable_results_reproducibility(lab, store):
    farm = link(store)
    archive = await lab.retrieve("alice", archive_request(farm))
    raw = scenario(farm, archive)
    first = await lab.simulate("alice", raw)
    second = await lab.simulate(
        "alice", {**raw, "id": str(uuid4()), "parent_id": first["id"]}
    )
    assert second["calculation_sha256"] == first["calculation_sha256"]
    assert (await lab.simulate("alice", raw)) == first
    changed = scenario(farm, archive)
    changed["parent_id"] = first["id"]
    changed["strategies"][0]["plans"][0]["end"] = "2024-07-02"
    changed["strategies"][0]["assumptions"] = {
        "irrigation": "regular",
        "drainage": "poor",
    }
    result = await lab.simulate("alice", changed)
    a = first["periods"][0]["strategies"][0]
    b = result["periods"][0]["strategies"][0]
    assert a["plans"][0]["duration_days"] == 3 and b["plans"][0]["duration_days"] == 2
    assert a["plans"][0]["environment"] != b["plans"][0]["environment"]
    assert a["assumption_review"] != b["assumption_review"]
    assert b["water_quantities"]["gross_irrigation"]["value"] is None
    assert not result["recommendation_eligible"]
    assert lab.get("alice", farm.id, first["id"], "historical_simulations") == first
    changed["id"] = first["id"]
    with pytest.raises(PlatformError, match="IMMUTABLE_SIMULATION_CONFLICT"):
        await lab.simulate("alice", changed)
    for decision in store.decisions("alice", farm.id):
        for profile in decision["assessment"]["result"]["data"]["context"]["catalog"]:
            assert profile["rules"] == [] and not profile["approved_for_candidates"]


async def test_as_of_no_future_archive_or_history_leakage(lab, store):
    farm = link(store)
    archive = await lab.retrieve("alice", archive_request(farm))
    from earthsync.platform_v1.models import HistoryInput

    store.save_history(
        "alice",
        farm.id,
        HistoryInput(start="2024-01-01", end="2024-01-02", fallow=True),
    )
    raw = scenario(farm, archive)
    raw.update(mode="as_of_date", decision_at="2024-06-30T00:00:00Z")
    result = await lab.simulate("alice", raw)
    p = result["periods"][0]
    assert all(m["value"] is None for m in p["metrics"].values())
    assert p["excluded_evidence"]
    for strategy in p["strategies"]:
        assert strategy["crop_references"] == []
        decision = next(
            d
            for d in store.decisions("alice", farm.id)
            if d["id"] == strategy["decision_id"]
        )
        context = decision["assessment"]["result"]["data"]["context"]
        assert context["history"] == [] and context["climate"] == []


def test_leap_cross_year_partial_baseline_and_bounds(records):
    feb = summary(records, date(2024, 2, 1), date(2024, 2, 29))
    assert feb["metrics"]["rainfall"]["expected_days"] == 29
    parts = monthly([], date(2024, 11, 1), date(2025, 2, 28))
    assert [p["metrics"]["rainfall"]["expected_days"] for p in parts] == [
        30,
        31,
        31,
        28,
    ]
    assert all(p["metrics"]["rainfall"]["value"] is None for p in parts)
    assert contextual_baseline(parts)["rainfall"]["sample_count"] == 0
    assert contextual_baseline([feb])["rainfall"]["sample_count"] == 1
    with pytest.raises(ValidationError):
        Period(start="2015-01-01", end="2025-12-31")
    with pytest.raises(ValidationError):
        ArchiveInput(
            farm_id=uuid4(),
            revision=REVISION,
            start="2024-01-01",
            end="2024-12-31",
            time_standard="UTC",
        )


async def test_daily_mean_semantics_and_rejection(water_query):  # noqa: F811
    from earthsync.platform_v1.historical import MEAN_CONTRACT
    from earthsync.platform_v1.providers.power_daily import read_daily
    from earthsync.platform_v1.providers.transport import Capture
    import json

    # Explicit synthetic parameter/header mutation checks parser only. This is
    # never presented as a real T2M capture or scientific source validation.
    d = capture("T2M_MIN").json()
    d["parameters"] = {"T2M": d["parameters"]["T2M_MIN"]}
    d["properties"]["parameter"] = {"T2M": d["properties"]["parameter"]["T2M_MIN"]}
    d["header"]["sources"] = ["MERRA2"]
    r = read_daily(
        Capture(json.dumps(d).encode(), datetime.now(timezone.utc), {}),
        water_query,
        "T2M",
        contract=MEAN_CONTRACT,
    )
    assert r.measurements[0].variable == "temperature"
    d["header"]["time_standard"] = "UTC"
    with pytest.raises(PlatformError, match="TEMPORAL_MISMATCH"):
        read_daily(
            Capture(json.dumps(d).encode(), datetime.now(timezone.utc), {}),
            water_query,
            "T2M",
            contract=MEAN_CONTRACT,
        )


def test_api_ownership_migrations_and_strict_inputs(store, engine):
    farm = link(store, "local-single-user")
    app = create_app(
        store=store, engine=engine, transport=Sources(), local_enabled=True
    )
    with TestClient(
        app, base_url="http://127.0.0.1", client=("127.0.0.1", 10000)
    ) as client:
        assert client.get(PREFIX + f"/farms/{farm.id}/historical").json() == []
        assert client.get(PREFIX + f"/farms/{uuid4()}/simulations").status_code == 404
        assert (
            client.post(
                PREFIX + "/historical/jobs",
                json={**archive_request(farm), "revision": "2024-01-01T00:00:00Z"},
            ).status_code
            == 409
        )
        assert (
            client.post(
                PREFIX + "/simulations/jobs", json={"id": str(uuid4())}
            ).status_code
            == 422
        )
    Store(store.path.parent).ready()


def test_gibs_time_dimension_is_required_and_acquisition_not_inferred():
    from earthsync.platform_v1.historical_imagery import dimensions, supported

    xml = b"""<Capabilities xmlns="http://www.opengis.net/wmts/1.0" xmlns:o="http://www.opengis.net/ows/1.1"><Contents><Layer><o:Identifier>MODIS_Terra_CorrectedReflectance_TrueColor</o:Identifier><Dimension><o:Identifier>Time</o:Identifier><Value>2000-02-24/2025-12-31/P1D</Value></Dimension></Layer></Contents></Capabilities>"""
    values = dimensions(xml)
    assert supported(date(2024, 2, 29), values)
    assert not supported(date(1999, 1, 1), values)
    assert not supported(date(2024, 1, 1), ["2000-01-01/2025-12-31/P8D"])
    with pytest.raises(PlatformError, match="IMAGERY_CAPABILITIES_INVALID"):
        dimensions(b"not XML")


async def test_unavailable_provider_never_fills_or_caches_fake_evidence(lab, store):
    class Outage:
        async def get(self, url, params):
            raise PlatformError("RATE_LIMIT", 429, True)

    farm = link(store)
    lab.transport = Outage()
    lab.water.transport = lab.transport
    with pytest.raises(PlatformError, match="NO_VALID_HISTORICAL_EVIDENCE"):
        await lab.retrieve("alice", archive_request(farm))
    assert store.farm_records("alice", farm.id) == []
    assert lab.list("alice", farm.id, "historical_windows") == []


async def test_assistant_uses_saved_historical_source_summaries(lab, store):
    from earthsync.platform_v1.context import assistant_context
    from earthsync.assistant.models import ChatRequest
    from earthsync.assistant.service import explain

    farm = link(store)
    await lab.retrieve("alice", archive_request(farm))
    context = assistant_context(store, "alice", farm.id)
    request = ChatRequest(
        question="What historical information do we have?", context=context
    )
    result = explain(request)
    assert any("59.97" in c.text and "2024-07-01" in c.text for c in result.claims)
    assert any(c.source_ids for c in result.claims if "59.97" in c.text)


async def test_as_of_observation_day_and_retrieval_timezone_are_conservative(
    lab, store
):
    farm = link(store)
    archive = await lab.retrieve("alice", archive_request(farm))
    records = lab.records("alice", farm.id, archive)
    records = [
        r.model_copy(
            update={
                "temporal": r.temporal.model_copy(
                    update={
                        "retrieved_at": datetime.fromisoformat(
                            "2024-07-02T00:00:00+00:00"
                        )
                    }
                )
            }
        )
        for r in records
    ]
    result = summary(
        records,
        date(2024, 7, 1),
        date(2024, 7, 7),
        as_of=datetime.fromisoformat("2024-07-02T06:30:00+06:30"),
    )
    assert result["metrics"]["rainfall"]["valid_days"] == 1
    assert result["metrics"]["rainfall"]["missing_days"] == 6
    assert not result["excluded_evidence"]
