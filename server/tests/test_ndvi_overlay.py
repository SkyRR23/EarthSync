"""Synthetic rasters test geometry, QA and rendering; never live NASA evidence."""

import base64
import io

from fastapi.testclient import TestClient
import numpy as np
from PIL import Image
import pytest
from rasterio.io import MemoryFile
from rasterio.transform import from_origin
from rasterio.warp import transform

from earthsync.platform_v1.api import create_app, PREFIX
from earthsync.platform_v1.store import Store
from earthsync.realtime.http import SourceError
from earthsync.realtime.ndvi import (
    geometry,
    hls_window,
    inspect_pixel,
    viewport_bbox,
)

DATE = "2026-10-22T16:45:00+00:00"
LOCATION = {"lat": 42.0308, "lon": -93.6319}
X, Y = transform("EPSG:4326", "EPSG:32615", [LOCATION["lon"]], [LOCATION["lat"]])
GRID = from_origin(X[0] - 60, Y[0] + 60, 30, 30)


def polygon(left=0, top=0, right=4, bottom=4):
    xy = [
        GRID * (left, top),
        GRID * (right, top),
        GRID * (right, bottom),
        GRID * (left, bottom),
        GRID * (left, top),
    ]
    lon, lat = transform(
        "EPSG:32615", "EPSG:4326", [p[0] for p in xy], [p[1] for p in xy]
    )
    return {"type": "Polygon", "coordinates": [list(map(list, zip(lon, lat)))]}


class Ranges:
    def __init__(self, files):
        self.files, self.downloaded, self.receipts = files, 0, []

    def range(self, url, start, end, resolved=None):
        data = self.files[url][start : end + 1]
        self.downloaded += len(data)
        return data, len(self.files[url]), url


def tiff(
    array,
    *,
    qa=False,
    grid=GRID,
    acquired=DATE,
    scale=0.0001,
    crs="EPSG:32615",
    tile="SYNTHETIC_TEST",
):
    with MemoryFile() as memory:
        with memory.open(
            driver="GTiff",
            width=4,
            height=4,
            count=1,
            dtype="uint8" if qa else "int16",
            crs=crs,
            transform=grid,
            nodata=255 if qa else -19999,
        ) as ds:
            ds.write(np.asarray(array, dtype="uint8" if qa else "int16"), 1)
            ds.scales = (1 if qa else scale,)
            ds.update_tags(SENSING_TIME=acquired)
            if tile:
                ds.update_tags(MGRS_TILE_ID=tile)
            if not qa:
                ds.update_tags(HLS_VI_PROCESSING_TIME="2026-10-24T01:43:35Z")
        return memory.read()


def extract(raw=None, qa=None, *, geom=None, ndvi_options=None, qa_options=None):
    urls = [
        "https://data.lpdaac.earthdatacloud.nasa.gov/synthetic.NDVI.tif",
        "https://data.lpdaac.earthdatacloud.nasa.gov/synthetic.Fmask.tif",
    ]
    files = {
        urls[0]: tiff(
            np.full((4, 4), 5390) if raw is None else raw, **(ndvi_options or {})
        ),
        urls[1]: tiff(
            np.zeros((4, 4)) if qa is None else qa, qa=True, **(qa_options or {})
        ),
    }
    product = {
        "product": "HLSL30_VI",
        "version": "2.0",
        "granule_id": "SYNTHETIC_UNIT_TEST",
        "assets": urls,
        "acquired_start": DATE,
    }
    return hls_window(product, geom or polygon(), Ranges(files))


def test_native_scaling_masked_png_alignment_and_pixel_inspection():
    raw = np.full((4, 4), 5390)
    qa = np.zeros((4, 4), dtype="uint8")
    raw[0, 0] = -19999
    raw[0, 1] = 10001
    raw[0, 2] = -4000
    qa[1, :] = [1, 8, 16, 192]
    data = extract(raw, qa)
    assert data["polygon_pixels"] == 16
    assert data["valid_pixels"] == 10
    assert data["coverage_pct"] == 62.5
    assert data["quality"] == "partial"
    assert data["display_crs"] == "EPSG:3857"
    assert data["acquired_at"] == DATE
    assert Image.open(io.BytesIO(base64.b64decode(data["png_base64"]))).mode == "RGBA"
    for row in range(4):
        for col in range(4):
            x, y = GRID * (col + 0.5, row + 0.5)
            lon, lat = transform("EPSG:32615", "EPSG:4326", [x], [y])
            inspected = inspect_pixel(data, lat[0], lon[0])
            assert inspected["row"] == row
            assert inspected["column"] == col
            expected = (
                None
                if row == 1 or (row == 0 and col in (0, 1))
                else raw[row, col] * 0.0001
            )
            assert (
                inspected["value"] == pytest.approx(expected)
                if expected is not None
                else inspected["value"] is None
            )
    west, south, east, north = data["bounds"]
    assert west < LOCATION["lon"] < east and south < LOCATION["lat"] < north


@pytest.mark.parametrize("bit", [1, 2, 4, 8, 16, 32, 192, 255])
def test_every_conservative_fmask_rejection_is_transparent(bit):
    data = extract(qa=np.full((4, 4), bit))
    assert data["valid_pixels"] == 0
    assert data["quality"] == "unavailable"
    pixels = np.asarray(Image.open(io.BytesIO(base64.b64decode(data["png_base64"]))))
    assert not pixels[:, :, 3].any()


def test_clipping_and_partial_tile_do_not_fill_uncovered_cells():
    clipped = extract(geom=polygon(0, 0, 2, 4))
    assert clipped["polygon_pixels"] == clipped["valid_pixels"] == 8
    partial = extract(geom=polygon(-2, 0, 2, 4))
    assert partial["polygon_pixels"] == 16
    assert partial["valid_pixels"] == 8
    assert partial["coverage_pct"] == 50


def test_upstream_fmask_can_lack_vi_only_tags_but_known_tile_mismatch_fails():
    assert extract(qa_options={"tile": None})["valid_pixels"] == 16
    with pytest.raises(SourceError, match="GRID_MISMATCH"):
        extract(qa_options={"tile": "DIFFERENT_TILE"})


@pytest.mark.parametrize(
    "options,code",
    [
        ({"grid": from_origin(X[0] - 59, Y[0] + 60, 30, 30)}, "GRID_MISMATCH"),
        ({"scale": 1}, "ENCODING_MISMATCH"),
        ({"acquired": "2026-10-23T16:45:00+00:00"}, "TEMPORAL_MISMATCH"),
        ({"crs": "EPSG:4326"}, "GRID_MISMATCH"),
    ],
)
def test_wrong_native_grid_encoding_time_and_crs_fail_closed(options, code):
    with pytest.raises(SourceError, match=code):
        extract(ndvi_options=options)


def test_invalid_or_oversized_geometry_rejected_before_raster_access():
    with pytest.raises(ValueError):
        geometry(
            LOCATION,
            {
                "type": "Polygon",
                "coordinates": [[[0, 0], [1, 1], [1, 0], [0, 1], [0, 0]]],
            },
        )
    with pytest.raises(SourceError, match="AREA_TOO_LARGE"):
        geometry(
            LOCATION,
            {
                "type": "Polygon",
                "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]],
            },
        )
    with pytest.raises(SourceError, match="AREA_TOO_LARGE"):
        extract(geom=polygon(0, 0, 500, 300))


def test_larger_bounded_window_counts_missing_cells_without_inventing_values():
    data = extract(geom=polygon(0, 0, 300, 300))
    assert data["polygon_pixels"] == 90000
    assert data["valid_pixels"] == 16
    assert data["quality"] == "partial"


@pytest.mark.parametrize(
    "bbox",
    [
        "nan,42,-93,43",
        "-94,42,-93",
        "-93,42,-94,43",
        "-190,42,-189,43",
        "-94,42,-93,43",
    ],
)
def test_map_bounds_validation(bbox):
    with pytest.raises(SourceError):
        viewport_bbox(bbox)


def test_viewport_api_uses_its_own_cached_geometry_and_original_pixel(
    tmp_path, monkeypatch
):
    monkeypatch.delenv("EARTHDATA_TOKEN", raising=False)
    app = create_app(store=Store(tmp_path), local_enabled=True)
    bbox = "-93.65,42.02,-93.61,42.04"
    location, geom = viewport_bbox(bbox)
    key, _ = app.state.ndvi.key(location, geom, "clearest")
    app.state.realtime.repository.put(key, extract())
    route = PREFIX + "/realtime/ames/ndvi-overlay"
    with TestClient(
        app, base_url="http://127.0.0.1", client=("127.0.0.1", 12345)
    ) as client:
        assert client.get(route).json()["data"] is None
        result = client.get(route, params={"bbox": bbox}).json()
        assert result["data"]["valid_pixels"] == 16
        pixel = client.get(
            route, params={"bbox": bbox, "lat": LOCATION["lat"], "lon": LOCATION["lon"]}
        ).json()["pixel"]
        assert pixel["value"] == 0.539
        assert client.get(route, params={"bbox": "nan,1,2,3"}).status_code == 422
        assert (
            client.post(route + "/refresh", params={"bbox": "nan,1,2,3"}).status_code
            == 422
        )


def test_missing_auth_does_not_break_api_and_cached_acquisition_reopens(
    tmp_path, monkeypatch
):
    monkeypatch.delenv("EARTHDATA_TOKEN", raising=False)
    directory = tmp_path / "demo"
    store = Store(directory)
    app = create_app(store=store, local_enabled=True)
    route = PREFIX + "/realtime/ames/ndvi-overlay"
    with TestClient(
        app, base_url="http://127.0.0.1", client=("127.0.0.1", 12345)
    ) as client:
        assert client.post(route + "/refresh").status_code == 202
        result = client.get(route).json()
        assert result["status"] == "unavailable"
        assert result["error"] == "AUTHENTICATION_REQUIRED"
        assert client.get(PREFIX + "/health").status_code == 200
        data = extract()
        key, _ = app.state.ndvi.key(LOCATION)
        app.state.realtime.repository.put(key, data)
    reopened = create_app(store=Store(directory), local_enabled=True)
    with TestClient(
        reopened, base_url="http://127.0.0.1", client=("127.0.0.1", 12345)
    ) as client:
        result = client.get(route).json()
        assert result["status"] == "cached"
        assert result["data"]["acquired_at"] == DATE
        assert result["stale"] is True
        assert (
            client.get(route + "?lat=42.0308&lon=-93.6319").json()["pixel"]["value"]
            == 0.539
        )
