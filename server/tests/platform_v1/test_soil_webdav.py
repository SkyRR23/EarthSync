"""Synthetic raster QA plus cached real ISRIC extraction; not field lab truth."""

from datetime import datetime, timezone
from types import SimpleNamespace
from pathlib import Path

import numpy as np
import pytest
from rasterio.io import MemoryFile
from rasterio.transform import from_origin
from rasterio.warp import transform

from earthsync.platform_v1.models import Point
from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.providers.soil_webdav import (
    read_cells,
    select_tile,
    MANIFEST_SHA256,
)
from earthsync.platform_v1.providers.soil_wcs import NATIVE_CRS
from earthsync.platform_v1.providers.transport import Capture


def fixture_capture(values, *, nodata=-32768, crs=NATIVE_CRS):
    affine = from_origin(0, 1000, 250, 250)
    with MemoryFile() as mem:
        with mem.open(
            driver="GTiff",
            width=600,
            height=600,
            count=1,
            dtype="int16",
            crs=crs,
            transform=affine,
            nodata=nodata,
        ) as ds:
            ds.write(values, 1)
        data = mem.read()
    return Capture(
        data,
        datetime.now(timezone.utc),
        {"source_url": "https://example.invalid/synthetic.tif"},
    ), affine


def point_at(affine):
    x, y = affine * (3.5, 3.5)
    lon, lat = transform(NATIVE_CRS, "EPSG:4326", [x], [y])
    return Point(latitude=lat[0], longitude=lon[0])


def descriptor():
    return SimpleNamespace(
        sha256=MANIFEST_SHA256, retrieved_at=datetime.now(timezone.utc)
    )


def test_raw_scale_nodata_and_native_cell_support():
    values = np.full((600, 600), 67, dtype="int16")
    values[3, 3] = -32768
    capture, affine = fixture_capture(values)
    result = read_cells(capture, point_at(affine), affine, descriptor())
    assert len(result["cells"]) == 25
    center = next(c for c in result["cells"] if c["at_query_point"])
    assert (
        center["raw"] is None
        and center["value"] is None
        and center["quality"] == "nodata"
    )
    assert result["cells"][0]["raw"] == 67 and result["cells"][0]["value"] == 6.7
    assert result["uncertainty"] is None and result["usable_for_assessment"] is False
    assert result["display_crs"] == "EPSG:4326" and result["depth_cm"] == [0, 5]


@pytest.mark.parametrize("kwargs", [{"nodata": None}, {"crs": "EPSG:3857"}])
def test_no_guessing_nodata_or_crs(kwargs):
    capture, affine = fixture_capture(np.full((600, 600), 67, dtype="int16"), **kwargs)
    with pytest.raises(PlatformError):
        read_cells(capture, point_at(affine), affine, descriptor())


def test_unaccepted_manifest_and_invalid_values_fail_closed():
    with pytest.raises(PlatformError, match="SOIL_MANIFEST_REVISION_UNACCEPTED"):
        select_tile(
            Capture(b"<VRTDataset/>", datetime.now(timezone.utc), {}),
            Point(latitude=0, longitude=0),
        )
    capture, affine = fixture_capture(np.full((600, 600), 141, dtype="int16"))
    with pytest.raises(PlatformError, match="SCIENTIFIC_QUALITY_REJECTION"):
        read_cells(capture, point_at(affine), affine, descriptor())


def test_cached_real_isric_native_nodata_and_scale():
    from rasterio.transform import Affine

    file = Path(__file__).parent / "fixtures/7g/isric-phh2o-0-5cm-mean.real.tif"
    capture = Capture(
        file.read_bytes(),
        datetime(2026, 11, 14, 17, 35, tzinfo=timezone.utc),
        {
            "source_url": "https://files.isric.org/soilgrids/latest/data/phh2o/phh2o_0-5cm_mean/tileSG-008-020/tileSG-008-020_3-3.tif"
        },
    )
    r = read_cells(
        capture,
        Point(latitude=42.0308, longitude=-93.6319),
        Affine(250, 0, -10737500, 0, -250, 4700750),
        descriptor(),
    )
    at_point = next(c for c in r["cells"] if c["at_query_point"])
    assert at_point["raw"] == 66 and at_point["value"] == 6.6
    assert any(c["value"] is None for c in r["cells"])
