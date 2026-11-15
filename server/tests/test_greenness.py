from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from earthsync.api import create_app
from earthsync.greenness import (
    farm_greenness,
    parse_farm,
    pixel_ndvi,
    point_in_polygon,
)

FARM = "16.8506,96.1494;16.8506,96.1509;16.8493,96.1509;16.8493,96.1494"
NOW = datetime(2026, 11, 15, tzinfo=timezone.utc)


def item(day, collection="HLSS30_2.0", cloud=20):
    return {
        "id": f"HLS.{day}",
        "collection": collection,
        "properties": {"datetime": f"2026-{day}T04:00:00Z", "eo:cloud_cover": cloud},
        "assets": {},
    }


def cells(values):
    sq = [[16.85, 96.15], [16.85, 96.1503], [16.8497, 96.1503], [16.8497, 96.15]]
    return [{"ndvi": v, "corners": sq} for v in values]


class FakeSearch:
    def __init__(self, items):
        self._items = items

    async def items(self, farm, since):
        assert since == datetime(2026, 9, 1, tzinfo=timezone.utc)
        return self._items


class FakeReader:
    def __init__(self, by_id):
        self.by_id, self.reads = by_id, []

    def read(self, it, farm):
        self.reads.append(it["id"])
        v = self.by_id[it["id"]]
        if isinstance(v, Exception):
            raise v
        return v


def test_polygon_and_pixel_rules():
    sq = [(0, 0), (10, 0), (10, 10), (0, 10)]
    assert point_in_polygon(5, 5, sq)
    assert not point_in_polygon(15, 5, sq)
    assert pixel_ndvi(500, 3500, 0) == pytest.approx(0.75)
    assert pixel_ndvi(500, 3500, 0b10) is None  # cloud
    assert pixel_ndvi(500, 3500, 0b100000) is None  # water
    assert pixel_ndvi(500, 3500, 0b1) == pytest.approx(0.75)  # cirrus alone ok
    assert pixel_ndvi(-9999, 3500, 0) is None  # fill
    assert pixel_ndvi(500, 3500, 255) is None  # no mask


def test_farm_input_is_checked():
    assert len(parse_farm(FARM)) == 4
    assert parse_farm(FARM.replace(";", ",")) == parse_farm(FARM)
    for bad in [
        "1,2;3,4",
        "x,1;2,3;4,5",
        "16,96;16.2,96;16.2,96.2",
        "91,1;1,1;1,2",
        "16.85,96.15,16.85",
    ]:
        try:
            parse_farm(bad)
        except ValueError:
            continue
        raise AssertionError(bad)


async def test_newest_clear_image_and_the_one_before():
    import asyncio  # noqa: F401

    items = [
        item("11-12", cloud=95),  # skipped: almost all cloud
        item("11-10"),  # read, but mostly cloudy over the farm
        item("11-07", "HLSL30_2.0"),
        item("11-02"),
        item("10-28"),
    ]
    reader = FakeReader(
        {
            "HLS.11-10": cells([0.6, None, None, None]),
            "HLS.11-07": RuntimeError("timeout"),
            "HLS.11-02": cells([0.62, 0.64, 0.6, None]),
            "HLS.10-28": cells([0.5, 0.52, 0.54, 0.5]),
        }
    )
    out = await farm_greenness(parse_farm(FARM), FakeSearch(items), reader, NOW)
    assert reader.reads == ["HLS.11-10", "HLS.11-07", "HLS.11-02", "HLS.10-28"]
    latest, prev = out["latest"], out["previous"]
    assert latest["date"] == "2026-11-02"
    assert latest["sensor"] == "Sentinel-2"
    assert (latest["pixels_inside"], latest["pixels_clear"]) == (4, 3)
    assert latest["ndvi_mean"] == 0.62
    assert latest["ndvi_median"] == 0.62
    assert len(latest["cells"]) == 4
    assert prev["date"] == "2026-10-28" and "cells" not in prev
    assert prev["ndvi_mean"] == 0.515


def get(monkeypatch, token, reader=None, items=()):
    if token:
        monkeypatch.setenv("EARTHDATA_TOKEN", token)
    else:
        monkeypatch.delenv("EARTHDATA_TOKEN", raising=False)
    app = create_app(
        greenness_search=FakeSearchAny(list(items)), greenness_reader=reader
    )
    with TestClient(app) as c:
        return c.get(f"/api/v1/environment/greenness?farm={FARM}")


class FakeSearchAny(FakeSearch):
    async def items(self, farm, since):
        return self._items


def test_no_token_means_not_set_up(monkeypatch):
    r = get(monkeypatch, None)
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "not_configured"


def test_endpoint_returns_scene_and_provenance(monkeypatch):
    reader = FakeReader({"HLS.11-02": cells([0.7, 0.72])})
    r = get(monkeypatch, "t", reader, [item("11-02")])
    body = r.json()
    assert r.status_code == 200
    assert body["latest"]["ndvi_mean"] == 0.71
    assert body["previous"] is None
    assert body["provenance"]["data_kind"] == "observed"


def test_no_clear_image_is_said_plainly(monkeypatch):
    reader = FakeReader({"HLS.11-02": cells([None, None, 0.5])})
    body = get(monkeypatch, "t", reader, [item("11-02")]).json()
    assert body["status"] == "success"
    assert body["latest"] is None


def test_bad_farm_rejected(monkeypatch):
    monkeypatch.setenv("EARTHDATA_TOKEN", "t")
    with TestClient(create_app(greenness_search=FakeSearchAny([]))) as c:
        r = c.get("/api/v1/environment/greenness?farm=1,2;3,4")
    assert r.status_code == 422
