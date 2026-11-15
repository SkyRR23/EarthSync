"""Synthetic geometries only: storage/validation, never real field boundaries."""

from datetime import datetime, timezone
import pytest
from pydantic import ValidationError
from earthsync.platform_v1.models import FarmInput, FarmLinkInput, Polygon
from earthsync.platform_v1.store import Store

RING = [
    (-93.632, 42.030),
    (-93.631, 42.030),
    (-93.631, 42.031),
    (-93.632, 42.031),
    (-93.632, 42.030),
]


def test_boundary_immutable_revisions_survive_restart(store):
    value = FarmInput(
        name="Synthetic geometry test",
        confirmed_point={"latitude": 42.0305, "longitude": -93.6315},
        confirmed_polygon={"coordinates": [RING]},
        confirmed_on="2026-11-14",
        production_system="rainfed",
    )
    link = FarmLinkInput(
        local_profile_id="software-test-7g",
        revision=datetime(2026, 11, 14, tzinfo=timezone.utc),
        farm=value,
    )
    original = store.link_farm("owner", link)
    restarted = Store(store.path.parent)
    assert (
        restarted.farm_link("owner", link.local_profile_id, link.revision) == original
    )
    point_only = value.model_copy(update={"confirmed_polygon": None})
    second = restarted.link_farm(
        "owner",
        link.model_copy(
            update={
                "revision": datetime(2026, 11, 14, 1, tzinfo=timezone.utc),
                "farm": point_only,
            }
        ),
    )
    assert second["farm"].id != original["farm"].id
    assert (
        restarted.farm("owner", original["farm"].id).confirmed_polygon.coordinates[0]
        == RING
    )
    assert restarted.farm("owner", second["farm"].id).confirmed_polygon is None


@pytest.mark.parametrize(
    "ring",
    [
        [(0, 0), (1, 1), (0, 1), (1, 0), (0, 0)],
        [(179, 0), (-179, 0), (-179, 1), (179, 1), (179, 0)],
        [(0, 0), (1, 1), (2, 2), (0, 0)],
        [(0, 0), (1, 0), (1, 1)],
    ],
)
def test_invalid_boundaries_rejected(ring):
    with pytest.raises(ValidationError):
        Polygon(coordinates=[ring])


def test_point_outside_boundary_rejected():
    with pytest.raises(ValidationError):
        FarmInput(
            name="Outside",
            confirmed_point={"latitude": 0, "longitude": 0},
            confirmed_polygon={"coordinates": [RING]},
            confirmed_on="2026-11-14",
            production_system="rainfed",
        )


def test_farmer_report_dates_ownership_and_restart(store, farm_input):
    from earthsync.platform_v1.models import ObservationInput
    from earthsync.platform_v1.errors import PlatformError

    farm = store.create_farm("alice", farm_input)
    report = ObservationInput(
        observed_on="2026-11-14",
        planting_on="2026-10-01",
        crop_name="Farmer-reported sesame",
        growth_stage="unknown",
        notes="Synthetic software-test report; no observed field fact.",
    )
    saved = store.save_observation("alice", farm.id, report)
    assert (
        not saved["independently_verified"] and saved["data_type"] == "farmer_reported"
    )
    with pytest.raises(PlatformError, match="NOT_FOUND"):
        store.observations("bob", farm.id)
    assert Store(store.path.parent).observations("alice", farm.id) == [saved]
    with pytest.raises(ValidationError):
        ObservationInput(
            observed_on="2026-10-01",
            planting_on="2026-11-14",
            notes="Future planting relative to report",
        )


def test_new_api_jobs_outage_and_ownership_boundary(store, farm_input):
    import time
    from fastapi.testclient import TestClient
    from earthsync.platform_v1.api import create_app, PREFIX
    from earthsync.platform_v1.errors import PlatformError

    class Offline:
        async def get(self, *args):
            raise PlatformError("PROVIDER_UNAVAILABLE", 503, True)

    app = create_app(store=store, transport=Offline(), local_enabled=True)
    with TestClient(
        app, base_url="http://127.0.0.1", client=("127.0.0.1", 10001)
    ) as client:
        farm = client.post(
            PREFIX + "/farms", json=farm_input.model_dump(mode="json")
        ).json()
        id = farm["id"]
        assert (
            client.post(
                PREFIX + f"/farms/{id}/observations",
                json={"observed_on": "2026-11-14", "notes": "Synthetic test report"},
            ).status_code
            == 201
        )
        assert (
            client.get(PREFIX + f"/farms/{id}/observations").json()[0]["data_type"]
            == "farmer_reported"
        )
        for kind in ("soil-map", "forecast"):
            job = client.post(
                PREFIX + f"/{kind}/jobs",
                json={"farm_id": id, "point": farm["confirmed_point"]},
            )
            assert job.status_code == 202
            for _ in range(30):
                saved = client.get(PREFIX + "/jobs/" + job.json()["id"]).json()
                if saved["status"] == "failed":
                    break
                time.sleep(0.01)
            assert saved["error"] == "PROVIDER_UNAVAILABLE" and saved["result"] is None
        timeline = client.get(PREFIX + f"/farms/{id}/intelligence").json()
        assert len(timeline) == 2 and all(j["status"] == "failed" for j in timeline)
        assert (
            client.post(
                PREFIX + "/forecast/jobs",
                json={"farm_id": id, "point": {"latitude": 0, "longitude": 0}},
            ).status_code
            == 422
        )
        assert (
            client.get(PREFIX + "/crop-identities?q=sesame").json()[
                "recommendation_eligible"
            ]
            is False
        )


def test_cached_real_cmr_entry_title_requires_pinned_concept(farm_input):
    import json
    from pathlib import Path
    from earthsync.platform_v1.providers.discovery import (
        DiscoveryQuery,
        read_candidates,
    )
    from earthsync.platform_v1.providers.transport import Capture
    from earthsync.platform_v1.errors import PlatformError

    raw = (
        Path(__file__).parents[3]
        / "docs/integration/7g/evidence/hls-cmr-response.real.json"
    ).read_bytes()
    query = DiscoveryQuery(
        farm=farm_input,
        start="2024-07-01T00:00:00Z",
        end="2024-07-31T23:59:59Z",
        limit=3,
    )
    capture = Capture(raw, datetime.now(timezone.utc), {})
    assert len(read_candidates(capture, query)["records"]) == 3
    value = json.loads(raw)
    value["items"][0]["meta"]["collection-concept-id"] = "unverified"
    with pytest.raises(PlatformError, match="UNSUPPORTED_PRODUCT"):
        read_candidates(
            Capture(json.dumps(value).encode(), datetime.now(timezone.utc), {}), query
        )
