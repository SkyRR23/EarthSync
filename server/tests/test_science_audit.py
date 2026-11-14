"""Adversarial source-contract tests; all generated values are synthetic."""

import hashlib
import json
from datetime import date, timedelta

import httpx
import pytest

from earthsync.models import SeasonQuery
from earthsync.power import PowerProvider, ProviderError


QUERY = SeasonQuery(
    latitude=16.85,
    longitude=96.15,
    start_year=2024,
    start_month=1,
    end_year=2024,
    end_month=2,
)


def payload():
    days = [date(2024, 1, 1) + timedelta(days=i) for i in range(60)]
    return {
        "header": {
            "start": "20240101",
            "end": "20240229",
            "sources": ["MERRA2"],
            "fill_value": -999,
            "time_standard": "LST",
        },
        "parameters": {"T2M": {"units": "C"}, "PRECTOTCORR": {"units": "mm/day"}},
        "geometry": {"type": "Point", "coordinates": [96.15, 16.85, 0]},
        "properties": {
            "parameter": {
                "T2M": {d.strftime("%Y%m%d"): d.month * 10 for d in days},
                "PRECTOTCORR": {d.strftime("%Y%m%d"): d.month for d in days},
            }
        },
    }


async def normalize(body):
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda req: httpx.Response(200, content=body))
    ) as client:
        return await PowerProvider(client).season(QUERY)


async def test_january_february_rates_and_exact_response_identity():
    raw = json.dumps(payload()).encode()
    result = await normalize(raw)
    rows = result.environment.seasonal.observations
    assert [(r.period.month, r.rainfall_mm, r.mean_temperature_c) for r in rows] == [
        (1, 31, 10),
        (2, 58, 20),
    ]
    assert [c["expected_days"] for c in result.provenance["coverage"]] == [31, 29]
    assert result.provenance["data_kind"] == "modeled"
    source = result.provenance["source_requests"][0]
    assert source["response_sha256"] == hashlib.sha256(raw).hexdigest()
    assert source["header"] == payload()["header"]
    assert source["source_geometry"] == payload()["geometry"]


@pytest.mark.parametrize(
    "geometry",
    [
        None,
        {},
        {"type": "Polygon", "coordinates": [96.15, 16.85]},
        {"type": "Point", "coordinates": [16.85, 96.15]},
        {"type": "Point", "coordinates": [-93.62, 42.03]},
        {"type": "Point", "coordinates": [96.15]},
        {"type": "Point", "coordinates": [True, 16.85]},
        {"type": "Point", "coordinates": [96.15, 16.85, float("nan")]},
    ],
    ids=[
        "missing",
        "empty",
        "polygon",
        "swapped",
        "other_farm",
        "short",
        "bool",
        "nan",
    ],
)
async def test_geometry_must_bind_provider_response_to_requested_point(geometry):
    data = payload()
    data["geometry"] = geometry
    with pytest.raises(ProviderError):
        await normalize(json.dumps(data).encode())


@pytest.mark.parametrize("value", ["20240230", "20241301", "20231231", "ANN"])
async def test_invalid_or_outside_dates_cannot_hide_beside_complete_months(value):
    data = payload()
    data["properties"]["parameter"]["PRECTOTCORR"][value] = 999
    with pytest.raises(ProviderError):
        await normalize(json.dumps(data).encode())


@pytest.mark.parametrize(
    "replacement", ['"20240101":99,"20240101":1', '"20240101":1,"20240101":1']
)
async def test_conflicting_and_identical_duplicate_daily_keys_are_rejected(replacement):
    raw = json.dumps(payload(), separators=(",", ":")).replace(
        '"20240101":1,', replacement + ","
    )
    with pytest.raises(ProviderError):
        await normalize(raw.encode())


async def test_missing_day_is_not_zero_rain_or_complete_coverage():
    data = payload()
    del data["properties"]["parameter"]["PRECTOTCORR"]["20240229"]
    result = await normalize(json.dumps(data).encode())
    february = result.environment.seasonal.observations[1]
    assert february.rainfall_mm is None and not february.rainfall_complete
    assert february.mean_temperature_c == 20 and february.temperature_complete
    assert result.provenance["coverage"][1]["missing_or_invalid_dates"][
        "PRECTOTCORR"
    ] == ["20240229"]
