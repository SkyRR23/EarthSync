"""Cached real NOAA bytes; no live provider is contacted by these tests."""

from datetime import datetime, timezone
from pathlib import Path

import pytest
from earthsync.platform_v1.providers.gfs import read_temperature
from earthsync.platform_v1.providers.transport import Capture
from earthsync.platform_v1.models import Point
from earthsync.platform_v1.errors import PlatformError

DATA = Path(__file__).parent / "fixtures/7g/noaa-gfs-20261114-12-f006.real.grib2"
RUN = datetime(2026, 11, 14, 12, tzinfo=timezone.utc)
POINT = Point(latitude=42.0308, longitude=-93.6319)


def capture():
    return Capture(
        DATA.read_bytes(), datetime(2026, 11, 14, 17, 36, tzinfo=timezone.utc), {}
    )


def test_cached_real_grib_reference_valid_time_unit_and_grid():
    r = read_temperature(capture(), POINT, RUN, 6)
    assert r["model_initialized_at"] == "2026-11-14T12:00:00+00:00"
    assert r["valid_at"] == "2026-11-14T18:00:00+00:00"
    assert r["temperature_c"] == pytest.approx(5.46410522, abs=1e-7)
    assert r["raw_temperature_k"] - 273.15 == r["temperature_c"]
    assert r["native_unit"] == "[K]" and r["unit"] == "°C"
    assert r["grid_point"] == {"latitude": 42.0, "longitude": -93.75}


@pytest.mark.parametrize(
    "run,hour,point",
    [
        (RUN, 12, POINT),
        (RUN.replace(hour=6), 6, POINT),
        (RUN, 6, Point(latitude=0, longitude=0)),
    ],
)
def test_wrong_run_lead_or_spatial_support_rejected(run, hour, point):
    with pytest.raises(PlatformError):
        read_temperature(capture(), point, run, hour)


def test_html_provider_error_never_becomes_weather():
    with pytest.raises(PlatformError, match="FORECAST_ENCODING_MISMATCH"):
        read_temperature(Capture(b"<html>unavailable</html>", RUN, {}), POINT, RUN, 6)
