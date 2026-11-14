import copy
import json
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from jsonschema import validate
from pydantic import ValidationError

from earthsync.platform_v1.availability import forecast_freshness
from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.models import (
    ClimateQuery,
    Evidence,
    FarmInput,
    Measurement,
    Polygon,
    Temporal,
)
from earthsync.platform_v1.providers.power_daily import PowerDaily, read_daily
from earthsync.platform_v1.providers.transport import Capture, Transport

from conftest import captured


def changed(capture, mutate):
    data = copy.deepcopy(capture.json())
    mutate(data)
    return Capture(json.dumps(data).encode(), capture.retrieved_at, {})


def test_real_capture_and_schema(records):
    for record in records:
        assert len(record.measurements) == 29
        assert record.temporal.day_basis == "NASA_POWER_LST"
        assert record.spatial.role == "regional_context"
        validate(record.model_dump(mode="json"), Evidence.model_json_schema())
    rain = records[2]
    assert sum(v.value for v in rain.measurements) == pytest.approx(5.04)
    assert records[0].measurements[0].value == -0.18
    assert records[1].source_metadata["header"]["sources"] == ["MERRA2", "POWER"]
    assert rain.measurements[0].original_unit == "mm/day"


@pytest.mark.parametrize(
    "sources",
    [["GEOSIT"], ["MERRA2", "GEOSIT"], [], ["POWER"], ["MERRA2", "POWER", "GEOSIT"]],
)
def test_unresolved_lineage_rejected(query, sources):
    cap = changed(captured("T2M_MIN"), lambda d: d["header"].update(sources=sources))
    with pytest.raises(PlatformError, match="UNSUPPORTED_SOURCE_LINEAGE"):
        read_daily(cap, query, "T2M_MIN")


@pytest.mark.parametrize(
    "mutate,code",
    [
        (lambda d: d["header"].update(time_standard="UTC"), "TEMPORAL_MISMATCH"),
        (lambda d: d["header"].update(end="20240228"), "TEMPORAL_MISMATCH"),
        (lambda d: d["parameters"]["PRECTOTCORR"].update(units="mm"), "UNIT_MISMATCH"),
        (lambda d: d["geometry"].update(coordinates=[0, 0]), "SPATIAL_MISMATCH"),
        (
            lambda d: d["properties"]["parameter"]["PRECTOTCORR"].update(
                {"20240301": 2}
            ),
            "TEMPORAL_MISMATCH",
        ),
    ],
)
def test_metadata_drift(query, mutate, code):
    with pytest.raises(PlatformError, match=code):
        read_daily(changed(captured("PRECTOTCORR"), mutate), query, "PRECTOTCORR")


def test_missing_days_null_not_zero(query):
    def mutate(data):
        values = data["properties"]["parameter"]["PRECTOTCORR"]
        values.pop("20240201")
        values["20240229"] = -999
        values["20240202"] = True

    record = read_daily(changed(captured("PRECTOTCORR"), mutate), query, "PRECTOTCORR")
    assert len(record.measurements) == 29
    assert [record.measurements[i].value for i in (0, 1, 28)] == [None, None, None]
    assert record.measurements[2].value == 0


def test_nonleap_cross_year_order(query):
    with pytest.raises(ValidationError):
        ClimateQuery(point=query.point, start="2023-02-29", end="2023-03-01")
    assert ClimateQuery(point=query.point, start="2023-12-31", end="2024-02-29")
    with pytest.raises(ValidationError):
        ClimateQuery(point=query.point, start="2024-03-01", end="2024-02-01")


def test_evidence_cannot_promote_synthetic(records):
    value = records[0].model_dump()
    value["data_type"] = "synthetic"
    with pytest.raises(ValidationError):
        Evidence.model_validate(value)
    value["data_type"] = "forecast"
    with pytest.raises(ValidationError):
        Evidence.model_validate(value)


def test_unknown_time_and_missing_reason():
    with pytest.raises(ValidationError):
        Temporal(retrieved_at=datetime.now(timezone.utc))
    with pytest.raises(ValidationError):
        Measurement(
            variable="x",
            original_value=None,
            original_unit="pH",
            value=None,
            unit="pH",
            conversion="identity",
            quality="missing",
        )


@pytest.mark.parametrize(
    "coordinates",
    [
        [[(0, 0), (1, 1), (0, 1), (1, 0), (0, 0)]],
        [[(0, 0), (0, 0), (0, 0), (0, 0)]],
        [[(179, 0), (-179, 0), (-179, 1), (179, 0)]],
    ],
)
def test_invalid_polygon(coordinates):
    with pytest.raises(ValidationError):
        Polygon(coordinates=coordinates)


def test_device_location_never_farm(farm_input):
    with pytest.raises(ValidationError):
        FarmInput(
            name="area",
            approximate_user_location={"latitude": 1, "longitude": 2},
            confirmed_on="2026-11-14",
            production_system="rainfed",
        )
    values = farm_input.model_dump()
    values["confirmed_polygon"] = {"coordinates": [[(0, 0), (1, 0), (1, 1), (0, 0)]]}
    with pytest.raises(ValidationError):
        FarmInput.model_validate(values)


@pytest.mark.parametrize(
    "status,code",
    [
        (403, "PROVIDER_ACCESS_DENIED"),
        (429, "RATE_LIMIT"),
        (503, "PROVIDER_UNAVAILABLE"),
        (302, "PROVIDER_UNAVAILABLE"),
    ],
)
async def test_transport_states(status, code):
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda req: httpx.Response(status))
    ) as client:
        with pytest.raises(PlatformError, match=code):
            await Transport(client).get(
                "https://power.larc.nasa.gov/api/temporal/daily/point", {}
            )


async def test_transport_size_and_ssrf():
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(
            lambda req: httpx.Response(200, content=b"a" * 100)
        )
    ) as client:
        source = Transport(client, max_bytes=10)
        with pytest.raises(PlatformError, match="UNSUPPORTED_PRODUCT"):
            await source.get("http://169.254.169.254/latest/meta-data", {})
        with pytest.raises(PlatformError, match="PROVIDER_RESPONSE_TOO_LARGE"):
            await source.get("https://power.larc.nasa.gov/api/temporal/daily/point", {})


async def test_outage_never_synthetic(query):
    class Offline:
        async def get(self, *args):
            raise PlatformError("OUTBOUND_PROXY_BLOCKED", 503)

    result = await PowerDaily(Offline()).retrieve(query)
    assert result["records"] == []
    assert len(result["gaps"]) == 3
    assert all(v["code"] == "OUTBOUND_PROXY_BLOCKED" for v in result["gaps"])


def test_freshness():
    now = datetime.now(timezone.utc)
    args = (now, now - timedelta(hours=2), now, now + timedelta(days=1))
    assert forecast_freshness(*args, now) == "fresh"
    assert (
        forecast_freshness(now, None, now, now + timedelta(days=1), now)
        == "issue_time_unknown"
    )
    assert forecast_freshness(*args, now + timedelta(hours=2)) == "stale"
    assert (
        forecast_freshness(
            now, now + timedelta(hours=1), now, now + timedelta(days=1), now
        )
        == "invalid"
    )


@pytest.mark.parametrize("body", [b'{"key":1,"key":2}', b'{"value":NaN}', b"[]"])
def test_malformed_provider_json_is_rejected(body):
    with pytest.raises(PlatformError, match="SCHEMA_MISMATCH"):
        Capture(body, datetime.now(timezone.utc), {}).json()


def test_committed_schema_compatibility():
    from pathlib import Path
    from earthsync.platform_v1.models import AssessmentInput

    root = Path(__file__).parents[2] / "docs/platform_v1/schemas"
    for model in (Evidence, FarmInput, AssessmentInput, ClimateQuery):
        assert (
            json.loads((root / f"{model.__name__}.json").read_text())
            == model.model_json_schema()
        )


@pytest.mark.parametrize("index", range(12))
def test_four_pilot_real_capture_regressions(index):
    import hashlib
    from pathlib import Path
    from earthsync.platform_v1.models import Point

    directory = Path(__file__).parent / "fixtures/pilots"
    receipt = json.loads((directory / "receipt.json").read_text())[index]
    raw = (directory / receipt["file"]).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == receipt["response_sha256"]
    query = ClimateQuery(
        point=Point.model_validate(receipt["query_point"]),
        start="2024-02-01",
        end="2024-02-29",
    )
    record = read_daily(
        Capture(raw, datetime.fromisoformat(receipt["retrieved_at"]), {}),
        query,
        receipt["parameter"],
    )
    assert len(record.measurements) == 29
    assert all(m.value is not None for m in record.measurements)
    assert record.spatial.role == "regional_context"


def test_combined_parameter_capture_is_not_per_parameter_lineage(query):
    from pathlib import Path

    raw = (
        Path(__file__).parent / "fixtures/power_iowa_202402_daily.real.json"
    ).read_bytes()
    with pytest.raises(PlatformError, match="SCHEMA_MISMATCH"):
        read_daily(Capture(raw, datetime.now(timezone.utc), {}), query, "T2M_MIN")
