# ruff: noqa: E402  # Isolated harness resolves the unchanged baseline modules.
"""Validation harness contracts; synthetic fixtures never become field evidence."""

import hashlib
import json
import math
import os
from pathlib import Path
import sys

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from reference import metrics, reference_et0, match_observations


def weather(**changes):
    return dict(
        date={"year": 2024, "month": 7, "day": 6},
        tmin_c=12.3,
        tmax_c=21.5,
        dewpoint_c=237.3
        * math.log(1.409 / 0.6108)
        / (17.27 - math.log(1.409 / 0.6108)),
        wind_2m_m_s=2.078,
        pressure_kpa=100.1,
        solar_mj_m2_day=22.07,
        rainfall_mm=None,
        **changes,
    )


def test_independent_fao_published_example_and_metric_sign():
    assert abs(reference_et0(50.8, 100, weather()) - 3.88) < 0.03
    r = metrics([(2, 1), (4, 2)])
    assert r["mae"] == r["bias"] == 1.5 and r["rmse"] == pytest.approx(math.sqrt(2.5))
    assert metrics([])["mae"] is None
    with pytest.raises(ValueError):
        metrics([(float("nan"), 1)])


def test_reference_matcher_excludes_timezone_and_training_leakage():
    m = dict(
        site_id="synthetic",
        variable="tmin",
        start="2024-01-01",
        end="2024-01-01",
        unit="celsius",
        time_standard="NASA_POWER_LST",
        value=10,
    )
    r = {
        **m,
        "value": 9,
        "quality": "accepted",
        "independence": "held_out_verified",
        "source_url": "https://example.invalid/synthetic",
        "license": "software fixture",
    }
    assert match_observations([m], [r])[0]["mae"] == 1
    assert match_observations([m], [{**r, "time_standard": "UTC"}])[0]["n"] == 0
    assert match_observations([m], [{**r, "independence": "unknown"}])[0]["n"] == 0
    with pytest.raises(ValueError):
        match_observations([m], [r, r])
    ph = {
        **m,
        "variable": "ph",
        "unit": "pH",
        "top_cm": 0,
        "bottom_cm": 5,
        "measurement_method": "water",
    }
    soil = {**r, **ph, "bottom_cm": 20}
    assert match_observations([ph], [soil])[0]["n"] == 0


def test_preregistered_sites_and_production_source_are_immutable():
    sites = json.loads((HERE / "sites.json").read_text())
    protocol = json.loads((HERE / "protocol.json").read_text())
    assert (
        hashlib.sha256((HERE / "sites.json").read_bytes()).hexdigest()
        == protocol["site_manifest_sha256"]
    )
    assert (
        len(sites["sites"]) >= 12 and len({s["continent"] for s in sites["sites"]}) >= 4
    )
    assert sum(s["country"] == "Myanmar" for s in sites["sites"]) >= 4
    assert all(
        -90 <= s["latitude"] <= 90
        and -180 <= s["longitude"] <= 180
        and s["coordinate_source"].startswith("https://")
        for s in sites["sites"]
    )


@pytest.mark.asyncio
async def test_actual_native_independent_numeric_matrix_and_rejected_inputs():
    sys.path.insert(0, str(HERE.parents[1] / "server"))
    from earthsync.platform_v1.engine import RustEngine

    path = os.getenv("EARTHSYNC_TEST_V03")
    if not path:
        pytest.skip("Explicit baseline native binary required")
    engine = RustEngine(path, hashlib.sha256(Path(path).read_bytes()).hexdigest())
    count = 0
    for lat in [-36.65, -1.25, 0, 20.68, 41.1651, 50.8931]:
        for month in [1, 7]:
            for radiation in [5, 12, 20]:
                day = weather()
                day["date"]["month"] = month
                day["solar_mj_m2_day"] = radiation
                request = dict(
                    method="fao56-daily-pm.v1",
                    latitude=lat,
                    elevation_m=100,
                    day_basis="NASA_POWER_LST",
                    days=[day],
                )
                actual = (await engine.water(request))["days"][0]
                if actual["et0_mm"] is not None:
                    assert actual["et0_mm"] == pytest.approx(
                        reference_et0(lat, 100, day), abs=1e-8, rel=1e-8
                    )
                    count += 1
    assert count >= 20
    for changes, reason in [
        ({"pressure_kpa": None}, "MISSING_DAILY_PM_INPUT_OR_PROVIDER_ELEVATION"),
        ({"dewpoint_c": -2}, "FROST_POINT_CONVERSION_UNVALIDATED"),
        ({"solar_mj_m2_day": 0}, "RADIATION_METHOD_OUTSIDE_SUPPORTED_DOMAIN"),
        ({"tmax_c": -30}, "INCOMPATIBLE_OR_OUT_OF_DOMAIN_PM_INPUT"),
    ]:
        day = weather()
        day.update(changes)
        result = await engine.water(
            dict(
                method="fao56-daily-pm.v1",
                latitude=20,
                elevation_m=100,
                day_basis="NASA_POWER_LST",
                days=[day],
            )
        )
        assert (
            result["days"][0]["et0_mm"] is None
            and result["days"][0]["missing_reason"] == reason
        )


def test_station_parser_rejects_html_and_bad_quality():
    from weather_agreement import station_rows

    with pytest.raises(ValueError, match="non-station CSV"):
        station_rows(b"<html><body>Service moved</body></html>")
    rows = station_rows(
        b'STATION,DATE,TMP\nTEST,2024-01-01T12:00:00,"+0123,1"\nTEST,2024-01-01T13:00:00,"+9999,1"\nTEST,2024-01-01T14:00:00,"+0140,3"\n'
    )
    assert len(rows) == 1 and rows[0][1] == 12.3
