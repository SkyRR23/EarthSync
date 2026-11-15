import json
from pathlib import Path

from fastapi.testclient import TestClient

from earthsync.api import create_app

URL = "/api/v1/environment/forecast?latitude=16.85&longitude=96.15"
REAL = json.loads(
    (Path(__file__).parent / "fixtures/open_meteo_yangon_20261115.json").read_text()
)


class Fake:
    def __init__(self, data):
        self.data, self.calls = data, 0

    async def forecast(self, latitude, longitude):
        self.calls += 1
        return self.data


def get(data):
    fake = Fake(data)
    with TestClient(create_app(forecast_provider=fake)) as c:
        return c.get(URL), fake


def test_real_yangon_forecast_is_normalized_and_labeled():
    r, _ = get(REAL)
    body = r.json()
    assert r.status_code == 200
    assert body["current"]["temp_c"] == 30.4
    assert body["current"]["feels_like_c"] == 36.9
    assert body["current"]["weather_code"] == 2
    assert [d["date"] for d in body["days"]][0] == "2026-11-15"
    assert len(body["days"]) == 5
    assert body["days"][2] == {
        "date": "2026-11-17",
        "weather_code": 81,
        "max_c": 31.2,
        "min_c": 24.9,
        "rain_mm": 6.3,
        "rain_chance": 66,
    }
    assert body["provenance"]["data_kind"] == "forecast"
    assert "not a local sensor" in body["provenance"]["note"]


def test_missing_values_stay_unknown():
    data = json.loads(json.dumps(REAL))
    data["current"]["temperature_2m"] = None
    data["daily"]["precipitation_probability_max"][0] = None
    body = get(data)[0].json()
    assert body["current"]["temp_c"] is None
    assert body["days"][0]["rain_chance"] is None


def test_unit_change_fails_closed():
    data = json.loads(json.dumps(REAL))
    data["current_units"]["temperature_2m"] = "°F"
    r, _ = get(data)
    assert r.status_code == 502
    assert r.json()["error"]["code"] == "UPSTREAM_UNITS_CHANGED"


def test_cached():
    fake = Fake(REAL)
    with TestClient(create_app(forecast_provider=fake)) as c:
        c.get(URL)
        assert c.get(URL).json()["cache"]["hit"] is True
    assert fake.calls == 1


def test_bad_coordinates():
    with TestClient(create_app(forecast_provider=Fake(REAL))) as c:
        assert (
            c.get("/api/v1/environment/forecast?latitude=99&longitude=1").status_code
            == 422
        )
