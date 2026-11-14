import json
from datetime import datetime, timezone

import numpy as np
import pytest
import rasterio
from rasterio.io import MemoryFile
from rasterio.transform import from_origin
from rasterio.warp import transform, transform_geom

from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.models import FarmInput, Point, Polygon
from earthsync.platform_v1.providers.discovery import DiscoveryQuery, read_candidates
from earthsync.platform_v1.providers.soil_wcs import (
    NATIVE_CRS,
    SoilQuery,
    read_ph_raster,
)
from earthsync.platform_v1.providers.transport import Capture
from earthsync.platform_v1.satellite import (
    HlsMetadata,
    RadarMetadata,
    process_hls,
    process_radar,
    radar_change,
)


@pytest.fixture
def rasters(tmp_path):
    transform = from_origin(500000, 4650000, 30, 30)

    def write(name, array, nodata):
        path = tmp_path / name
        with rasterio.open(
            path,
            "w",
            driver="GTiff",
            width=array.shape[1],
            height=array.shape[0],
            count=1,
            dtype=array.dtype,
            crs="EPSG:32615",
            transform=transform,
            nodata=nodata,
        ) as ds:
            ds.write(array, 1)
        return path

    x, y = transform * (1.5, 1.5)
    lon, lat = rasterio.warp.transform("EPSG:32615", "EPSG:4326", [x], [y])
    farm = FarmInput(
        name="Synthetic raster support",
        confirmed_point=Point(latitude=lat[0], longitude=lon[0]),
        confirmed_on="2026-11-14",
        production_system="rainfed",
    )
    return write, farm, transform


def hls_metadata():
    return HlsMetadata(
        product="HLSS30",
        version="2.0",
        granule_id="synthetic-qa-test",
        acquired_at="2024-07-01T12:00:00Z",
        source_url="https://hls.gsfc.nasa.gov/",
        nir_band="B8A",
    )


def test_scaled_point_ndvi_and_fill(rasters):
    write, farm, _ = rasters
    red = write("red.tif", np.full((3, 3), 2000, dtype="int16"), -9999)
    nir = write("nir.tif", np.full((3, 3), 6000, dtype="int16"), -9999)
    qa = write("qa.tif", np.zeros((3, 3), dtype="uint8"), 255)
    result = process_hls(red, nir, qa, farm, hls_metadata())
    assert result["covered_pixel_mean_ndvi"] == pytest.approx(0.5)
    assert result["support"]["kind"] == "representative_point_context"
    assert result["support"]["valid_pixels"] == 1
    assert len(result["source_sha256"]) == 3


@pytest.mark.parametrize("qa_value", [1, 2, 4, 8, 16, 32, 192, 255])
def test_all_qa_flags_excluded(rasters, qa_value):
    write, farm, _ = rasters
    red = write("red.tif", np.full((3, 3), 2000, dtype="int16"), -9999)
    nir = write("nir.tif", np.full((3, 3), 6000, dtype="int16"), -9999)
    qa = write("qa.tif", np.full((3, 3), qa_value, dtype="uint8"), 255)
    result = process_hls(red, nir, qa, farm, hls_metadata())
    assert result["covered_pixel_mean_ndvi"] is None
    assert result["support"]["valid_pixels"] == 0


def test_tiny_polygon_not_field_average(rasters):
    write, farm, tf = rasters
    # Subpixel polygon containing the confirmed point, no wholly interior pixels.
    x, y = tf * (1.5, 1.5)
    ring = [
        (x - 3, y - 3),
        (x + 3, y - 3),
        (x + 3, y + 3),
        (x - 3, y + 3),
        (x - 3, y - 3),
    ]
    geometry = transform_geom(
        "EPSG:32615", "EPSG:4326", {"type": "Polygon", "coordinates": [ring]}
    )
    farm.confirmed_polygon = Polygon.model_validate(geometry)
    red = write("red.tif", np.full((3, 3), 2000, dtype="int16"), -9999)
    nir = write("nir.tif", np.full((3, 3), 6000, dtype="int16"), -9999)
    qa = write("qa.tif", np.zeros((3, 3), dtype="uint8"), 255)
    result = process_hls(red, nir, qa, farm, hls_metadata())
    assert result["status"] == "spatially_insufficient"
    assert result["covered_pixel_mean_ndvi"] is None


def test_band_and_grid_rejection(rasters):
    write, farm, _ = rasters
    path = write("red.tif", np.ones((3, 3), dtype="int16"), -9999)
    metadata = hls_metadata().model_copy(update={"nir_band": "B05"})
    with pytest.raises(PlatformError, match="BAND_MISMATCH"):
        process_hls(path, path, path, farm, metadata)
    with pytest.raises(PlatformError, match="INVALID_LOCAL_RASTER"):
        process_hls("https://evil.example/raster.tif", path, path, farm, hls_metadata())


def radar_metadata():
    return RadarMetadata(
        product="OPERA_L2_RTC-S1",
        version="1.0",
        granule_id="synthetic-radar-test",
        acquired_at="2024-07-01T12:00:00Z",
        source_url="https://asf.alaska.edu/",
        polarization="VV",
        orbit_direction="ascending",
        relative_orbit=10,
        burst_id="test-burst",
        geometry_id="synthetic-static-v1",
        processing_id="synthetic-processing-v1",
        unit="gamma0_linear_power",
        mask_convention="opera_layover_shadow_v1:0=valid,1=shadow,2=layover,3=both,255=fill",
    )


def test_radar_units_and_compatibility(rasters):
    write, farm, _ = rasters
    power = write("power.tif", np.full((3, 3), 0.1, dtype="float32"), -9999)
    qa = write("qa.tif", np.zeros((3, 3), dtype="uint8"), 255)
    result = process_radar(power, qa, farm, radar_metadata())
    assert result["covered_pixel_mean_power"] == pytest.approx(0.1)
    after = {
        **result,
        "metadata": {**result["metadata"], "acquired_at": "2024-07-13T12:00:00Z"},
    }
    assert radar_change(result, after)["reason"] == "COMMON_VALID_PIXEL_MASK_REQUIRED"
    after["metadata"]["relative_orbit"] = 20
    with pytest.raises(PlatformError, match="INCOMPATIBLE_RADAR_ACQUISITIONS"):
        radar_change(result, after)


def test_soil_native_units_depth_and_missing():
    point = Point(latitude=42.03, longitude=-93.62)
    xs, ys = transform("EPSG:4326", NATIVE_CRS, [point.longitude], [point.latitude])
    tf = from_origin(xs[0] - 250, ys[0] + 250, 250, 250)
    with MemoryFile() as mem:
        with mem.open(
            driver="GTiff",
            width=2,
            height=2,
            count=1,
            dtype="int16",
            crs=NATIVE_CRS,
            transform=tf,
            nodata=-32768,
        ) as ds:
            ds.write(np.full((2, 2), 65, dtype="int16"), 1)
        raw = mem.read()
    now = datetime.now(timezone.utc)
    descriptor = Capture(
        b"<CoverageDescriptions><CoverageId>phh2o_0-5cm_mean</CoverageId></CoverageDescriptions>",
        now,
        {},
    )
    result = read_ph_raster(Capture(raw, now, {}), SoilQuery(point=point), descriptor)
    assert result.measurements[0].original_value == 65
    assert result.measurements[0].value == 6.5
    assert (
        result.measurements[0].depth.top_cm == 0
        and result.measurements[0].depth.bottom_cm == 5
    )
    assert not result.usable_for_assessment
    with pytest.raises(PlatformError, match="SOIL_COVERAGE_MISMATCH"):
        read_ph_raster(
            Capture(raw, now, {}),
            SoilQuery(point=point),
            Capture(descriptor.body.replace(b"0-5", b"5-15"), now, {}),
        )


def test_discovery_metadata_is_not_observation(farm_input):
    query = DiscoveryQuery(
        farm=farm_input, start="2024-07-01T00:00:00Z", end="2024-07-31T23:59:59Z"
    )
    umm = {
        "GranuleUR": "synthetic-catalog-test",
        "CollectionReference": {"ShortName": "HLSS30", "Version": "2.0"},
        "TemporalExtent": {"SingleDateTime": "2024-07-10T12:00:00Z"},
        "SpatialExtent": {
            "HorizontalSpatialDomain": {
                "Geometry": {
                    "GPolygons": [
                        {
                            "Boundary": {
                                "Points": [
                                    {"Longitude": x, "Latitude": y}
                                    for x, y in [
                                        (-94, 41),
                                        (-93, 41),
                                        (-93, 43),
                                        (-94, 43),
                                        (-94, 41),
                                    ]
                                ]
                            }
                        }
                    ]
                }
            }
        },
    }
    capture = Capture(
        json.dumps({"items": [{"umm": umm}], "hits": 5}).encode(),
        datetime.now(timezone.utc),
        {},
    )
    result = read_candidates(capture, query)
    assert result["truncated"]
    assert not result["records"][0]["numeric_observation"]
    umm["CollectionReference"]["Version"] = "1.4"
    with pytest.raises(PlatformError, match="UNSUPPORTED_PRODUCT"):
        read_candidates(
            Capture(
                json.dumps({"items": [{"umm": umm}]}).encode(), capture.retrieved_at, {}
            ),
            query,
        )
