from copy import deepcopy

import httpx
import pytest
from pydantic import ValidationError

from earthsync.evidence.app import PREFIX, create_app
from earthsync.evidence.images import sanitize_image
from earthsync.evidence.models import PhotoInput, SatelliteRecord, TimelineQuery
from earthsync.evidence.satellite import HlsAdapter, ProviderResult, RtcS1Adapter
from earthsync.evidence.timeline import build_timeline

from test_photos import META, TOKEN, png

FIELD = {
    "farm_id": "synthetic-confirmed-farm",
    "confirmed_by_farmer": True,
    "point": {"latitude": 16.8, "longitude": 96.15, "uncertainty_m": None},
}
QUERY = {"field": FIELD, "start": "2026-11-01", "end": "2026-11-14"}


def record(identifier="synthetic-1", **changes):
    return SatelliteRecord.model_validate(
        {
            "id": identifier,
            "modality": "radar",
            "evidence_kind": "synthetic",
            "source_url": "https://example.org/synthetic-not-provider-data",
            "product": "synthetic-rtc",
            "product_version": "test-only",
            "acquired_at": "2026-11-01T10:00:00Z",
            "retrieved_at": "2026-11-14T00:00:00Z",
            "field": FIELD,
            "spatial_support": "confirmed_point_pixel",
            "pixel_bbox": [96.149, 16.799, 96.151, 16.801],
            "resolution_m": 30,
            "pixel_count": 1,
            "valid_pixel_count": 1,
            "qa": "usable",
            "qa_method": "synthetic-test-mask",
            "limitations": ["Synthetic test sample, not a real acquisition"],
            "metric": "gamma0_backscatter",
            "units": "dB",
            "value": -12.0,
            "platform": "synthetic-S1",
            "geometry_id": "synthetic-geometry-1",
            "relative_orbit": 12,
            "orbit_direction": "ascending",
            "polarization": "VV",
            "incidence_angle_deg": 35.0,
            **changes,
        }
    )


class SuppliedAdapter:
    provider = "synthetic-test-provider"
    modality = "radar"
    source_url = "https://example.org/synthetic-not-provider-data"

    def __init__(self, records, modality="radar"):
        self.records, self.modality = records, modality

    async def observe(self, query):
        return ProviderResult(
            provider=self.provider,
            status="available" if self.records else "no_observations",
            reason="synthetic_fixture",
            source_url=self.source_url,
            limitations=["Synthetic test provider"],
            records=self.records,
        )


async def test_default_adapters_report_unavailable_without_fabricated_data():
    query = TimelineQuery(**QUERY)
    result = await build_timeline(query, [], [HlsAdapter(), RtcS1Adapter()])
    assert result["events"] == []
    assert result["differences"] == []
    assert len(result["providers"]) == 2
    for provider in result["providers"]:
        assert provider["status"] == "unavailable"
        assert provider["reason"] == "access_unverified"
        assert provider["missing_state"] == "unavailable"


async def test_numeric_differences_preserve_units_kind_dates_and_limitations():
    records = [
        record(),
        record("synthetic-2", value=-10, acquired_at="2026-11-10T10:00:00Z"),
    ]
    result = await build_timeline(
        TimelineQuery(**QUERY), [], [SuppliedAdapter(records)]
    )
    assert len(result["events"]) == 2
    change = result["differences"][0]
    assert change["difference"] == 2
    assert change["units"] == "dB"
    assert change["evidence_kind"] == "synthetic"
    assert change["interpretation"] == "numeric_difference_only"
    assert change["spatial_support"] == "confirmed_point_pixel"
    assert change["limitations"]
    assert (
        result["providers"][0]["missing_state"]
        == "observations_only_at_listed_acquisitions"
    )


@pytest.mark.parametrize(
    "changes",
    [
        {"relative_orbit": 13},
        {"polarization": "VH"},
        {"orbit_direction": "descending"},
        {"incidence_angle_deg": 35.1},
        {"product_version": "other"},
        {"geometry_id": None},
        {"relative_orbit": None},
        {"resolution_m": 10},
        {"evidence_kind": "observed"},
        {"qa": "unknown"},
        {"qa": "rejected", "value": None, "valid_pixel_count": 0},
        {"pixel_bbox": [96.148, 16.799, 96.152, 16.801]},
    ],
)
async def test_incompatible_geometry_qa_support_and_kinds_never_compared(changes):
    records = [
        record(),
        record("second", acquired_at="2026-11-10T10:00:00Z", **changes),
    ]
    result = await build_timeline(
        TimelineQuery(**QUERY), [], [SuppliedAdapter(records)]
    )
    assert len(result["events"]) == 2
    assert result["differences"] == []


@pytest.mark.parametrize(
    "changes,reason",
    [
        ({"field": {**FIELD, "farm_id": "another-farm"}}, "confirmed_field_mismatch"),
        (
            {"field": {**FIELD, "point": {"latitude": 16.9, "longitude": 96.15}}},
            "confirmed_field_mismatch",
        ),
        ({"acquired_at": "2026-10-31T23:59:59Z"}, "outside_date_interval"),
        ({"pixel_bbox": [90, 10, 91, 11]}, "pixel_does_not_cover_confirmed_point"),
    ],
)
async def test_unmatched_records_rejected_with_reason(changes, reason):
    result = await build_timeline(
        TimelineQuery(**QUERY), [], [SuppliedAdapter([record(**changes)])]
    )
    assert result["events"] == []
    assert result["rejected_records"][0]["reason"] == reason
    assert result["providers"][0]["missing_state"] == "no_matching_observations"


@pytest.mark.parametrize(
    "point",
    [
        {"latitude": 16.8, "longitude": 96.15},
        {"latitude": 42.0, "longitude": -93.5},
        {"latitude": -33.9, "longitude": 151.2},
        {"latitude": 0.0, "longitude": 0.0},
    ],
)
async def test_confirmed_field_queries_are_global(point):
    result = await build_timeline(
        TimelineQuery(**{**QUERY, "field": {**FIELD, "point": point}}),
        [],
        [HlsAdapter(), RtcS1Adapter()],
    )
    assert result["query"].field.point.latitude == point["latitude"]
    assert all(provider["status"] == "unavailable" for provider in result["providers"])


async def test_optical_contract_and_no_disease_label():
    changes = {
        "modality": "optical",
        "metric": "ndvi",
        "units": "1",
        "value": 0.6,
        "product": "synthetic-hls",
        "polarization": None,
        "relative_orbit": None,
        "incidence_angle_deg": None,
        "orbit_direction": None,
    }
    records = [
        record(**changes),
        record(
            "second", **{**changes, "value": 0.3}, acquired_at="2026-11-10T10:00:00Z"
        ),
    ]
    result = await build_timeline(
        TimelineQuery(**QUERY), [], [SuppliedAdapter(records, "optical")]
    )
    assert result["differences"][0]["difference"] == pytest.approx(-0.3)
    assert result["differences"][0]["units"] == "1"
    assert result["differences"][0]["interpretation"] == "numeric_difference_only"


@pytest.mark.parametrize(
    "changes",
    [
        {"units": "1"},
        {"metric": "ndvi"},
        {"value": float("nan")},
        {"value": float("inf")},
        {"value": None},
        {"valid_pixel_count": 0},
        {"valid_pixel_count": 2},
        {"spatial_support": "regional_context"},
        {"acquired_at": "2026-11-01T10:00:00"},
        {"modality": "optical", "metric": "ndvi", "units": "1", "value": 1.1},
    ],
)
def test_invalid_scientific_records_fail_validation(changes):
    with pytest.raises(ValidationError):
        record(**changes)


async def test_provider_failure_is_unavailable_not_no_observations():
    class Broken(SuppliedAdapter):
        async def observe(self, query):
            raise TimeoutError("private provider credential must not leak")

    result = await build_timeline(TimelineQuery(**QUERY), [], [Broken([])])
    assert result["providers"][0]["status"] == "unavailable"
    assert result["providers"][0]["reason"] == "provider_error_or_invalid_response"
    assert result["events"] == []


async def test_photos_match_only_explicit_farm_and_capture_date(store):
    image = sanitize_image(png(), "image/png")
    metadata = {
        **META,
        "farm": {"farm_id": FIELD["farm_id"], "confirmed_by_farmer": True},
    }
    unknown = store.save(PhotoInput(**metadata), image)
    known = store.save(
        PhotoInput(
            **metadata,
            captured_date="2026-11-05",
            capture_time_source="farmer_reported",
        ),
        image,
    )
    store.save(PhotoInput(**META), image)  # Unlocated photo is not a field observation.
    store.save(
        PhotoInput(
            **{**metadata, "farm": {"farm_id": "other", "confirmed_by_farmer": True}}
        ),
        image,
    )
    result = await build_timeline(TimelineQuery(**QUERY), store.list(), [HlsAdapter()])
    assert [event["photo"].id for event in result["events"]] == [known.id]
    assert [event["photo"].id for event in result["undated_photos"]] == [unknown.id]
    assert result["differences"] == []


async def test_api_field_confirmation_required_and_unavailable_states(store):
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=create_app(store=store, token=TOKEN)),
        base_url="http://test",
    ) as client:
        headers = {"Authorization": f"Bearer {TOKEN}"}
        response = await client.post(f"{PREFIX}/timeline", headers=headers, json=QUERY)
        assert response.status_code == 200
        assert all(p["status"] == "unavailable" for p in response.json()["providers"])
        unconfirmed = deepcopy(QUERY)
        unconfirmed["field"]["confirmed_by_farmer"] = False
        response = await client.post(
            f"{PREFIX}/timeline", headers=headers, json=unconfirmed
        )
        assert response.status_code == 422
        assert "input" not in response.json()


def test_invalid_dates_and_unknown_contract_rejected():
    for changes in [
        {"start": "2026-12-01"},
        {"end": "2030-01-01"},
        {"schema_version": "evidence.v2"},
        {"field": {"farm_id": "f", "confirmed_by_farmer": True}},
    ]:
        with pytest.raises(ValidationError):
            TimelineQuery(**{**QUERY, **changes})


async def test_duplicate_ids_and_same_acquisition_do_not_create_differences():
    records = [record(), record(), record("other-id", value=-9)]
    result = await build_timeline(
        TimelineQuery(**QUERY), [], [SuppliedAdapter(records)]
    )
    assert len(result["events"]) == 2
    assert result["rejected_records"][0]["reason"] == "duplicate_record"
    assert result["differences"] == []
