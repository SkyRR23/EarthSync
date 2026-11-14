from uuid import uuid4

import pytest

from earthsync.platform_v1.journal import Journal, JournalInput
from earthsync.platform_v1.journal_projection import selected_reports
from earthsync.platform_v1.models import AssessmentInput
from earthsync.platform_v1.orchestrate import Orchestrator
from earthsync.platform_v1.catalog import Catalog
from earthsync.platform_v1.errors import PlatformError
from test_api_engine import rust_engine


@pytest.mark.asyncio
async def test_explicit_reports_reach_real_rust_as_unreviewed_without_rules(
    store, farm_input
):
    farm = store.create_farm("alice", farm_input)
    report = Journal(store).save(
        "alice",
        farm.id,
        JournalInput(
            id=uuid4(),
            kind="soil_test",
            occurred_on="2024-02-01",
            irrigation="limited",
            drainage="poor",
            priorities=["nitrogen_potential", "less_water"],
            resources="Reported labor limit",
            soil_test={
                "property": "ph",
                "value": 6.0,
                "unit": "pH",
                "top_cm": 0,
                "bottom_cm": 20,
                "source": "Farmer-supplied report",
            },
        ),
    )
    engine = rust_engine()
    orchestrator = Orchestrator(store, engine, Catalog())
    base = dict(farm_id=farm.id, start="2024-02-01", end="2024-02-29")
    unselected = await orchestrator.assess("alice", AssessmentInput(**base))
    assert unselected["result"]["data"]["context"]["observations"] == []
    result = await orchestrator.assess(
        "alice", AssessmentInput(**base, farmer_report_ids=[report["id"]])
    )
    assert result["result"]["status"] == "success"
    observations = result["result"]["data"]["context"]["observations"]
    assert {o["property"] for o in observations} == {"drainage", "ph"}
    assert all(o["provenance"]["kind"] == "farmer_reported" for o in observations)
    assert all(
        o["provenance"]["uncertainty"].startswith("Unverified") for o in observations
    )
    assert result["farmer_reports"][0]["priorities"] == [
        "nitrogen_potential",
        "less_water",
    ]
    assert result["recommendation_eligible"] is False
    assert all(
        s["review"] == "unreviewed"
        for s in result["result"]["data"]["context"]["sources"]
    )
    with pytest.raises(PlatformError, match="REPORT_NOT_OWNED_BY_FARM"):
        selected_reports(store, "alice", farm.id, [uuid4()])


@pytest.mark.asyncio
async def test_each_crop_reference_keeps_explicit_scope_without_locating_the_farm(
    store, farm_input
):
    from earthsync.platform_v1.reference_v2 import ReferenceCatalog

    farm = store.create_farm("alice", farm_input)
    orchestrator = Orchestrator(store, rust_engine(), Catalog(), ReferenceCatalog())
    value = AssessmentInput(
        farm_id=farm.id,
        catalog_version="v2",
        sequential_field=True,
        start="2024-07-03",
        end="2024-07-07",
        plans=[
            {
                "profile_id": "rice.mm.calendar-5-sessions-0@1",
                "reference_region": "MM-FAO-AEZ-001",
                "start": "2024-07-03",
                "end": "2024-07-04",
            },
            {
                "profile_id": "mung_bean.mm.rainfed-research@1",
                "reference_region": "MM-research-target",
                "start": "2024-07-05",
                "end": "2024-07-07",
            },
        ],
    )
    response = await orchestrator.assess("alice", value)
    data = response["result"]["data"]
    assert response["result"]["status"] == "success"
    assert data["context"]["region_id"] is None
    assert len(data["context"]["scenarios"][0]["plans"]) == 2
    assert {p["profile"]["region_id"] for p in response["catalog_projection"]} == {
        "MM-FAO-AEZ-001",
        "MM-research-target",
    }
    assert all(p["rules"] == [] for p in data["context"]["catalog"])
    assert response["recommendation_eligible"] is False
    invalid = value.model_copy(deep=True)
    invalid.plans[1].reference_region = "MM-FAO-AEZ-001"
    with pytest.raises(PlatformError, match="PROFILE_SCOPE_MISMATCH"):
        await orchestrator.assess("alice", invalid)


@pytest.mark.asyncio
async def test_exact_long_decimal_boundary_survives_actual_rust_assessment(
    store, farm_input
):
    from earthsync.platform_v1.models import Polygon

    farm_input.confirmed_polygon = Polygon(
        coordinates=[
            [
                (-93.64, 42.02),
                (-93.61675015869141, 42.02),
                (-93.61675015869141, 42.04),
                (-93.64, 42.04),
                (-93.64, 42.02),
            ]
        ]
    )
    farm = store.create_farm("alice", farm_input)
    response = await Orchestrator(store, rust_engine(), Catalog()).assess(
        "alice", AssessmentInput(farm_id=farm.id, start="2024-02-01", end="2024-02-29")
    )
    assert response["result"]["status"] == "success"
    assert (
        response["result"]["data"]["context"]["farm"]["boundary"][1]["longitude"]
        == -93.61675015869141
    )
