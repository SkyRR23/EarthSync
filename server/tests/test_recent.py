import json
from datetime import date, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from earthsync.api import create_app

TODAY = date(2026, 11, 15)
URL = "/api/v1/environment/recent?latitude=16.85&longitude=96.15"


def payload(rain_fn, wet_fn, today=TODAY, units=None, fill=-999.0):
    rain, wet = {}, {}
    d = today - timedelta(days=11 * 366)
    while d < today:
        k = d.strftime("%Y%m%d")
        rain[k], wet[k] = rain_fn(d), wet_fn(d)
        d += timedelta(days=1)
    return {
        "header": {
            "fill_value": fill,
            "time_standard": "LST",
            "sources": ["MERRA2", "GEOSIT"],
        },
        "parameters": units
        or {"PRECTOTCORR": {"units": "mm/day"}, "GWETROOT": {"units": "1"}},
        "properties": {"parameter": {"PRECTOTCORR": rain, "GWETROOT": wet}},
    }


ET0_REAL = json.loads(
    (
        Path(__file__).parent / "fixtures/nasa_power_et0_inputs_yangon_20261115.json"
    ).read_text()
)


class Fake:
    def __init__(self, data, today=TODAY, et0=ET0_REAL):
        self.data, self._today, self.calls, self.et0 = data, today, 0, et0

    def today(self):
        return self._today

    async def daily(self, latitude, longitude, start, end, parameters=None):
        assert end == self._today - timedelta(days=1)
        if parameters and "T2M_MIN" in parameters:
            if isinstance(self.et0, Exception):
                raise self.et0
            return self.et0
        self.calls += 1
        assert start <= date(self._today.year - 10, 10, 6)  # 10 years + margin
        return self.data


def get(data, today=TODAY):
    fake = Fake(data, today)
    with TestClient(create_app(recent_provider=fake)) as c:
        return c.get(URL), fake


def recent_week(d, days=7, lag=4):
    """True for the 7 days that end `lag` days before TODAY (NASA delay)."""
    end = TODAY - timedelta(days=lag)
    return end - timedelta(days=days - 1) <= d <= end


def past_year_rain(d):
    return float(d.year % 10)  # differs year to year, so thirds mean something


def test_wet_week_is_more_than_usual_and_heavy_rain_is_unusual():
    def rain(d):
        if d >= TODAY - timedelta(days=3):
            return -999.0  # NASA lag: newest days not published yet
        return 30.0 if recent_week(d) else past_year_rain(d)

    def wet(d):
        if d >= TODAY - timedelta(days=3):
            return -999.0
        return 0.9 if recent_week(d) else 0.4 + (d.year % 5) / 50

    r, _ = get(payload(rain, wet))
    body = r.json()
    assert r.status_code == 200
    assert body["as_of"] == "2026-11-11"
    assert body["rain_7d_mm"] == 210.0
    assert body["rain_7d_vs_past"] == "more"
    assert body["root_wetness"] == 0.9
    assert body["root_wetness_vs_past"] == "wetter"
    assert body["heaviest_day"]["rain_mm"] == 30.0
    assert body["heaviest_day"]["unusual"] is True
    assert [d["date"] for d in body["days"]][-1] == "2026-11-11"
    assert body["provenance"]["data_kind"] == "modeled"
    assert body["provenance"]["sources"] == ["MERRA2", "GEOSIT"]


def test_dry_week_is_less_and_drier_and_no_heavy_rain():
    def rain(d):
        if d >= TODAY - timedelta(days=3):
            return -999.0
        return 0.0 if recent_week(d) else 1.0 + past_year_rain(d)

    def wet(d):
        if d >= TODAY - timedelta(days=3):
            return -999.0
        return 0.2 if recent_week(d) else 0.5 + (d.year % 5) / 50

    body = get(payload(rain, wet))[0].json()
    assert body["rain_7d_mm"] == 0.0
    assert body["rain_7d_vs_past"] == "less"
    assert body["root_wetness_vs_past"] == "drier"
    assert body["heaviest_day"]["rain_mm"] == 0.0
    assert body["heaviest_day"]["unusual"] is False


def test_usual_week():
    def rain(d):
        if d >= TODAY - timedelta(days=3):
            return -999.0
        return 4.5 if recent_week(d) else past_year_rain(d)

    body = get(payload(rain, lambda d: 0.5))[0].json()
    assert body["rain_7d_vs_past"] == "usual"


def test_missing_day_keeps_week_rain_unknown_never_filled():
    def rain(d):
        if d >= TODAY - timedelta(days=3) or d == TODAY - timedelta(days=6):
            return -999.0
        return 2.0

    body = get(payload(rain, lambda d: 0.5))[0].json()
    assert body["as_of"] == "2026-11-11"
    assert body["rain_7d_mm"] is None
    assert body["rain_7d_vs_past"] == "unknown"
    assert body["heaviest_day"]["rain_mm"] == 2.0  # from the known days only


def test_no_recent_data_is_all_unknown():
    body = get(payload(lambda d: -999.0, lambda d: -999.0))[0].json()
    assert body["as_of"] is None
    assert body["rain_7d_vs_past"] == "unknown"
    assert body["root_wetness_vs_past"] == "unknown"
    assert body["heaviest_day"] is None


def test_unit_change_fails_closed():
    bad = {"PRECTOTCORR": {"units": "mm/hour"}, "GWETROOT": {"units": "1"}}
    r, _ = get(payload(lambda d: 1.0, lambda d: 0.5, units=bad))
    assert r.status_code == 502
    assert r.json()["error"]["code"] == "UPSTREAM_UNITS_CHANGED"


def test_cached_per_place_and_day():
    fake = Fake(payload(lambda d: 1.0, lambda d: 0.5))
    with TestClient(create_app(recent_provider=fake)) as c:
        assert c.get(URL).json()["cache"]["hit"] is False
        assert c.get(URL).json()["cache"]["hit"] is True
    assert fake.calls == 1


@pytest.mark.parametrize(
    "query", ["latitude=91&longitude=96", "latitude=16.85", "latitude=x&longitude=1"]
)
def test_bad_coordinates_are_rejected(query):
    with TestClient(create_app(recent_provider=Fake({}))) as c:
        assert c.get(f"/api/v1/environment/recent?{query}").status_code == 422


def test_real_yangon_capture():
    """Real NASA POWER response for Yangon fetched on 15 Nov 2026."""
    data = json.loads(
        (
            Path(__file__).parent / "fixtures/nasa_power_recent_yangon_20261115.json"
        ).read_text()
    )
    body = get(data)[0].json()
    assert body["as_of"] == "2026-11-11"
    assert body["rain_7d_mm"] == pytest.approx(57.97)
    assert body["root_wetness"] == 0.74
    assert body["heaviest_day"]["date"] == "2026-11-11"
    assert body["heaviest_day"]["rain_mm"] == 16.35
    assert body["rain_7d_vs_past"] in {"less", "usual", "more"}
    assert body["root_wetness_vs_past"] in {"drier", "usual", "wetter"}


def test_et0_request_for_the_engine_from_real_nasa_days():
    """The 7 days of the rain week, exactly as the engine's v03::water wants."""
    data = json.loads(
        (
            Path(__file__).parent / "fixtures/nasa_power_recent_yangon_20261115.json"
        ).read_text()
    )
    req = get(data)[0].json()["et0_request"]
    assert req["method"] == "fao56-daily-pm.v1"
    assert req["day_basis"] == "NASA_POWER_LST"
    assert req["latitude"] == 16.85
    assert req["elevation_m"] == 10.91
    days = req["days"]
    assert [d["date"] for d in (days[0], days[-1])] == [
        {"year": 2026, "month": 11, "day": 5},
        {"year": 2026, "month": 11, "day": 11},
    ]
    assert days[0] == {
        "date": {"year": 2026, "month": 11, "day": 5},
        "tmin_c": 24.94,
        "tmax_c": 33.13,
        "dewpoint_c": 24.72,
        "wind_2m_m_s": 0.8,
        "pressure_kpa": 101.03,
        "solar_mj_m2_day": 14.95,
        "rainfall_mm": 4.95,
    }
    assert days[-1]["solar_mj_m2_day"] is None  # NASA sunlight not in yet


def test_et0_inputs_failing_never_fails_the_answer():
    from earthsync.power import ProviderError

    fake = Fake(payload(lambda d: 1.0, lambda d: 0.5), et0=ProviderError())
    with TestClient(create_app(recent_provider=fake)) as c:
        body = c.get(URL).json()
    assert body["status"] == "success"
    assert body["et0_request"] is None
