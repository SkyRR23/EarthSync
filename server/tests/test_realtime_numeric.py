"""Synthetic QA/byte-budget faults, plus one explicitly cached-real GRIB fixture."""

from datetime import datetime, timezone
from pathlib import Path
import io

import h5py
import numpy as np
import pytest
from rasterio.io import MemoryFile
from rasterio.transform import from_origin
from rasterio.warp import transform

from earthsync.platform_v1.models import Point
from earthsync.platform_v1.providers.transport import Capture
from earthsync.realtime.gfs import read_weather
from earthsync.realtime.http import SourceError
from earthsync.realtime.nasa_assets import RangeFile
from earthsync.realtime.nasa_numeric import hls_pixel, imerg_cell, scalar
from earthsync.realtime.nws_grid import interval

NOW = datetime(2026, 11, 15, 0, tzinfo=timezone.utc)
LOCATION = {"lat": 42.0308, "lon": -93.6319}


class SyntheticRanges:
    def __init__(self, files):
        self.files, self.calls, self.downloaded = files, [], 0

    def range(self, url, start, end, resolved=None):
        self.calls.append((url, start, end))
        raw = self.files[url]
        value = raw[start : end + 1]
        self.downloaded += len(value)
        return value, len(raw), url


def test_range_reader_seek_and_budget_never_full_download():
    payload = bytes(range(256)) * 20000
    session = SyntheticRanges({"asset": payload})
    with RangeFile(session, "asset", budget=2 * 1048576) as f:
        f.seek(2 * 1048576 + 123)
        assert f.read(10) == payload[2 * 1048576 + 123 : 2 * 1048576 + 133]
        f.seek(1, 2)
        assert f.read(5) == b""
        with pytest.raises(SourceError, match="UNBOUNDED"):
            f.read()
        f.seek(1048576)
        with pytest.raises(SourceError, match="ASSET_BYTE_LIMIT"):
            f.read(10)
    assert session.downloaded == 2 * 1048576


def tiff(value, *, qa=False, nodata=None, scale=None):
    x, y = transform("EPSG:4326", "EPSG:32615", [LOCATION["lon"]], [LOCATION["lat"]])
    with MemoryFile() as memory:
        with memory.open(
            driver="GTiff",
            width=3,
            height=3,
            count=1,
            dtype="uint8" if qa else "int16",
            crs="EPSG:32615",
            transform=from_origin(x[0] - 45, y[0] + 45, 30, 30),
            nodata=nodata if nodata is not None else 255 if qa else -19999,
        ) as ds:
            ds.write(np.full((3, 3), value, dtype="uint8" if qa else "int16"), 1)
            ds.scales = (scale if scale is not None else 1 if qa else 0.0001,)
            ds.update_tags(SENSING_TIME=NOW.isoformat())
        return memory.read()


@pytest.mark.parametrize("qa", [1, 2, 4, 8, 16, 32, 192, 255])
def test_hls_native_qa_never_becomes_vegetation_decline(qa):
    files = {
        "https://example/scene.Fmask.tif": tiff(qa, qa=True),
        "https://example/scene.NDVI.tif": tiff(-19999),
    }
    ranges = SyntheticRanges(files)
    with pytest.raises(SourceError, match="SCIENTIFIC_QA_REJECTION"):
        hls_pixel(
            {"assets": list(files), "acquired_start": NOW.isoformat()}, LOCATION, ranges
        )
    assert len(ranges.calls) == 1  # QA rejects before downloading NDVI.


def test_official_vi_scale_fill_native_grid_and_nonpercentage_value():
    files = {
        "https://example/scene.Fmask.tif": tiff(64, qa=True),
        "https://example/scene.NDVI.tif": tiff(5390),
    }
    data = hls_pixel(
        {"assets": list(files), "acquired_start": NOW.isoformat()},
        LOCATION,
        SyntheticRanges(files),
    )
    assert data["value"] == 0.539
    assert data["qa_value"] == 64
    assert "percentage" not in data["unit"]
    assert data["grid"][2] == [3, 3]
    files["https://example/scene.NDVI.tif"] = tiff(5390, nodata=-9999)
    with pytest.raises(SourceError, match="RASTER_ENCODING_MISMATCH"):
        hls_pixel(
            {"assets": list(files), "acquired_start": NOW.isoformat()},
            LOCATION,
            SyntheticRanges(files),
        )


def test_imerg_half_hour_rate_and_amount_and_fill():
    stream = io.BytesIO()
    with h5py.File(stream, "w") as f:
        grid = f.create_group("Grid")
        grid.create_dataset("lat", data=np.arange(1800) * 0.1 - 89.95)
        grid.create_dataset("lon", data=np.arange(3600) * 0.1 - 179.95)
        row = int(np.argmin(abs(grid["lat"][:] - LOCATION["lat"])))
        col = int(np.argmin(abs(grid["lon"][:] - LOCATION["lon"])))
        for name, value in (("precipitation", 4), ("precipitationQualityIndex", 0.8)):
            ds = grid.create_dataset(
                name,
                (1, 3600, 1800),
                chunks=(1, 100, 100),
                dtype="f4",
                fillvalue=-9999.9,
            )
            ds.attrs["_FillValue"] = np.float32(-9999.9)
            ds[0, col, row] = value
            if name == "precipitation":
                ds.attrs["units"] = b"mm/hr"
        epoch = datetime(1980, 1, 6, tzinfo=timezone.utc)
        begin = int((NOW - epoch).total_seconds())
        time = grid.create_dataset("time_bnds", data=[[begin, begin + 1800]])
        time.attrs["units"] = b"seconds since 1980-01-06 00:00:00 UTC"
    url = "https://example/synthetic.HDF5"
    from datetime import timedelta

    product = {
        "assets": [url],
        "acquired_start": NOW.isoformat(),
        "acquired_end": (NOW + timedelta(minutes=30)).isoformat(),
    }
    data = imerg_cell(product, LOCATION, SyntheticRanges({url: stream.getvalue()}))
    assert [r["value"] for r in data["measurements"]] == [4, 2]
    assert data["quality_index"] == pytest.approx(0.8)


def test_hdf_native_units_fill_and_unreviewed_scaling_rejected():
    with h5py.File(io.BytesIO(), "w") as f:
        ds = f.create_dataset("value", data=[-9999.0, 0.3])
        ds.attrs.update(
            units="m3 m-3", _FillValue=-9999.0, valid_min=0.0, valid_max=0.9
        )
        with pytest.raises(SourceError, match="SCIENTIFIC_QA_REJECTION"):
            scalar(ds, 0, units="m3 m-3")
        assert scalar(ds, 1, units="m3 m-3") == 0.3
        with pytest.raises(SourceError, match="INVALID_UNITS"):
            scalar(ds, 1, units="percent")
        ds.attrs["scale_factor"] = 2
        with pytest.raises(SourceError, match="UNREVIEWED_DATA_SCALING"):
            scalar(ds, 1)


def test_nws_native_accumulation_interval_not_hourly_rainfall():
    start, end = interval("2026-11-15T00:00:00Z/PT6H")
    assert (end - start).total_seconds() == 21600
    with pytest.raises(SourceError, match="INVALID_FORECAST_INTERVAL"):
        interval("2026-11-15T00:00:00Z/P1M")


def test_cached_real_gfs_multivariable_native_accumulation():
    path = (
        Path(__file__).parent
        / "platform_v1/fixtures/7g/noaa-gfs-weather-20261114-18-f006.real.grib2"
    )
    run = datetime(2026, 11, 14, 18, tzinfo=timezone.utc)
    capture = Capture(path.read_bytes(), NOW, {})
    data = read_weather(
        capture, Point(latitude=LOCATION["lat"], longitude=LOCATION["lon"]), run, 6
    )
    assert data["temperature_c"] == pytest.approx(2.8049255371)
    assert data["relative_humidity_pct"] == pytest.approx(61.9)
    assert data["precipitation_mm"] == 0
    assert data["precipitation_start"] == run.isoformat()
    assert data["wind_speed_ms"] == pytest.approx(2.5679479332)
    assert (
        data["sha256"]
        == "f1ae4ad7725f0370b71d5ea66b3c65772c810e8c7546762d24db7c7fcab955d4"
    )
    with pytest.raises(SourceError, match="FORECAST_TIME"):
        read_weather(
            capture, Point(latitude=LOCATION["lat"], longitude=LOCATION["lon"]), run, 12
        )


def test_corrupt_raster_never_yields_numeric_forecast():
    with pytest.raises(SourceError, match="FORECAST_ENCODING_MISMATCH"):
        read_weather(
            Capture(b"<html>provider failure</html>", NOW, {}),
            Point(latitude=42, longitude=-93),
            NOW,
            6,
        )
