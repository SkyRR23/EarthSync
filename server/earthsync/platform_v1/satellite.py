"""Local bounded raster processing; only trusted operator-provided files.

Discovery metadata is never a numerical observation. HTTP never accepts paths,
asset URLs, Earthdata credentials or arbitrary raster uploads.
"""

import hashlib
from contextlib import ExitStack
from datetime import datetime
from pathlib import Path
from typing import Literal

import numpy as np
import rasterio
from pydantic import AwareDatetime, Field
from rasterio.features import geometry_window
from rasterio.warp import transform_geom
from rasterio.windows import Window
from shapely import box as boxes, covers
from shapely.geometry import Point as GeoPoint
from shapely.geometry import box, mapping, shape

from .errors import PlatformError
from .models import Contract, FarmInput


class HlsMetadata(Contract):
    product: Literal["HLSL30", "HLSS30"]
    version: Literal["2.0"]
    granule_id: str = Field(min_length=1, max_length=200)
    acquired_at: AwareDatetime
    source_url: str = Field(pattern=r"^https://", max_length=2000)
    red_band: Literal["B04"] = "B04"
    nir_band: Literal["B05", "B8A"]
    scale: Literal[0.0001] = 0.0001
    offset: Literal[0.0] = 0.0


class RadarMetadata(Contract):
    product: Literal["OPERA_L2_RTC-S1"]
    version: str = Field(min_length=1, max_length=80)
    granule_id: str = Field(min_length=1, max_length=200)
    acquired_at: AwareDatetime
    source_url: str = Field(pattern=r"^https://", max_length=2000)
    polarization: Literal["VV", "VH", "HH", "HV"]
    orbit_direction: Literal["ascending", "descending"]
    relative_orbit: int = Field(ge=1, le=175)
    burst_id: str = Field(min_length=1, max_length=100)
    geometry_id: str = Field(min_length=1, max_length=200)
    processing_id: str = Field(min_length=1, max_length=200)
    unit: Literal["gamma0_linear_power"]
    # Explicit reviewed native QA schema; no inferred mask values.
    mask_convention: Literal[
        "opera_layover_shadow_v1:0=valid,1=shadow,2=layover,3=both,255=fill"
    ]


def local_tiff(path):
    path = Path(path)
    if (
        not path.is_absolute()
        or path.resolve() != path
        or not path.is_file()
        or path.suffix.lower() not in (".tif", ".tiff")
        or path.stat().st_size > 256_000_000
    ):
        raise PlatformError("INVALID_LOCAL_RASTER")
    return path


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        while block := stream.read(1024 * 1024):
            h.update(block)
    return h.hexdigest()


def _open(stack, paths):
    stack.enter_context(
        rasterio.Env(
            GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
            GDAL_PAM_ENABLED="NO",
            GDAL_CACHEMAX=32_000_000,
        )
    )
    datasets = [
        stack.enter_context(rasterio.open(local_tiff(p), allowed_drivers=["GTiff"]))
        for p in paths
    ]
    first = datasets[0]
    if (
        not first.crs
        or not first.crs.is_projected
        or first.crs.linear_units != "metre"
        or first.count != 1
    ):
        raise PlatformError("RASTER_GRID_MISMATCH")
    if (
        first.transform.b != 0
        or first.transform.d != 0
        or not all(
            abs(abs(v) - 30) < 1e-6 for v in (first.transform.a, first.transform.e)
        )
    ):
        raise PlatformError("RASTER_RESOLUTION_MISMATCH")
    for dataset in datasets[1:]:
        if (dataset.crs, dataset.transform, dataset.shape, dataset.count) != (
            first.crs,
            first.transform,
            first.shape,
            1,
        ):
            raise PlatformError("RASTER_GRID_MISMATCH")
    return datasets


def _support(dataset, farm: FarmInput):
    if farm.confirmed_polygon:
        geometry = transform_geom(
            "EPSG:4326", dataset.crs, farm.confirmed_polygon.model_dump()
        )
        polygon = shape(geometry)
        if not polygon.intersects(box(*dataset.bounds)):
            raise PlatformError("SPATIAL_MISMATCH")
        try:
            window = geometry_window(dataset, [geometry])
        except rasterio.errors.WindowError as exc:
            raise PlatformError("SPATIAL_MISMATCH") from exc
        if window.width * window.height > 65536:
            raise PlatformError("RASTER_WINDOW_LIMIT", 413)
        transform = dataset.window_transform(window)
        rows, cols = np.indices((int(window.height), int(window.width)))
        x1 = transform.c + cols * transform.a
        y1 = transform.f + rows * transform.e
        x2, y2 = x1 + transform.a, y1 + transform.e
        included = covers(
            polygon,
            boxes(
                np.minimum(x1, x2),
                np.minimum(y1, y2),
                np.maximum(x1, x2),
                np.maximum(y1, y2),
            ),
        )
        support = {
            "kind": "confirmed_polygon_interior_pixels",
            "polygon_area_m2": polygon.area,
            "coverage_fraction": float(included.sum()) * 900 / polygon.area,
            "full_polygon_inside_raster": box(*dataset.bounds).covers(polygon),
            "limitation": "Only wholly contained 30 m pixels; boundary and uncovered area are excluded. No field-wide mean inferred.",
        }
    else:
        pt = farm.confirmed_point
        projected = shape(
            transform_geom(
                "EPSG:4326", dataset.crs, mapping(GeoPoint(pt.longitude, pt.latitude))
            )
        )
        row, col = dataset.index(projected.x, projected.y)
        if not 0 <= row < dataset.height or not 0 <= col < dataset.width:
            raise PlatformError("SPATIAL_MISMATCH")
        window, included = Window(col, row, 1, 1), np.ones((1, 1), dtype=bool)
        support = {
            "kind": "representative_point_context",
            "coverage_fraction": None,
            "limitation": "One grid cell at the confirmed point; not a field average.",
        }
    return window, included, support


def process_hls(red_path, nir_path, qa_path, farm, metadata: HlsMetadata):
    expected_nir = "B05" if metadata.product == "HLSL30" else "B8A"
    if metadata.nir_band != expected_nir:
        raise PlatformError("BAND_MISMATCH")
    paths = [red_path, nir_path, qa_path]
    try:
        with ExitStack() as stack:
            red, nir, qa = _open(stack, paths)
            if (
                red.dtypes != ("int16",)
                or nir.dtypes != ("int16",)
                or qa.dtypes != ("uint8",)
            ):
                raise PlatformError("RASTER_ENCODING_MISMATCH")
            if red.nodata != -9999 or nir.nodata != -9999 or qa.nodata != 255:
                raise PlatformError("RASTER_NODATA_MISMATCH")
            for dataset in (red, nir):
                tags = dataset.tags()
                if (
                    "scale_factor" in tags
                    and float(tags["scale_factor"]) != metadata.scale
                ):
                    raise PlatformError("UNIT_MISMATCH")
                if (
                    "add_offset" in tags
                    and float(tags["add_offset"]) != metadata.offset
                ):
                    raise PlatformError("UNIT_MISMATCH")
                if (
                    dataset.scales[0] not in (1, metadata.scale)
                    or dataset.offsets[0] != metadata.offset
                ):
                    raise PlatformError("UNIT_MISMATCH")
            window, included, support = _support(red, farm)
            r, n, q = [d.read(1, window=window, masked=True) for d in (red, nir, qa)]
            rv = r.data.astype(np.float64) * metadata.scale
            nv = n.data.astype(np.float64) * metadata.scale
            # Exclude cirrus/cloud/adjacency/shadow/snow/water and high aerosol.
            # Policy is deliberately conservative and retained in each output.
            mask = np.ma.getmaskarray(r) | np.ma.getmaskarray(n) | np.ma.getmaskarray(q)
            clean_qa = ((q.data & 0b00111111) == 0) & (((q.data >> 6) & 3) != 3)
            valid = (
                included
                & ~mask
                & clean_qa
                & np.isfinite(rv)
                & np.isfinite(nv)
                & (rv >= 0)
                & (nv >= 0)
                & (rv + nv > 0)
            )
            ndvi = np.full(rv.shape, np.nan)
            np.divide(nv - rv, nv + rv, out=ndvi, where=valid)
            count = int(valid.sum())
            support.update(
                total_supported_pixels=int(included.sum()),
                valid_pixels=count,
                valid_coverage_fraction=(count * 900 / support["polygon_area_m2"])
                if "polygon_area_m2" in support
                else None,
            )
            result = {
                "schema_version": "earthsync.local-raster-processing.v1",
                "usable_for_assessment": False,
                "status": "available"
                if count
                else "spatially_insufficient"
                if not included.any()
                else "no_valid_pixels",
                "metadata": metadata.model_dump(mode="json"),
                "support": support,
                "covered_pixel_mean_ndvi": float(ndvi[valid].mean()) if count else None,
                "unit": "dimensionless",
                "qa_policy": "hls-v2-conservative.v1; reject bits0..5/high-aerosol/fill/negative-reflectance/zero-denominator",
                "source_sha256": [digest(p) for p in paths],
                "grid": {
                    "crs": red.crs.to_string(),
                    "transform": list(red.transform),
                    "pixel_spacing_m": 30,
                    "effective_spatial_resolution_m": None,
                },
                "limitations": [
                    "Operator manifest and local files require provenance acceptance; no live product ingestion is claimed.",
                    "Negative reflectance excluded conservatively; no vegetation-health threshold or disease diagnosis.",
                ],
            }
            return result
    except (rasterio.errors.RasterioError, ValueError) as exc:
        raise PlatformError("INVALID_LOCAL_RASTER") from exc


def process_radar(power_path, mask_path, farm, metadata: RadarMetadata):
    paths = [power_path, mask_path]
    try:
        with ExitStack() as stack:
            power, mask = _open(stack, paths)
            if power.dtypes[0] not in ("float32", "float64") or mask.dtypes != (
                "uint8",
            ):
                raise PlatformError("RASTER_ENCODING_MISMATCH")
            window, included, support = _support(power, farm)
            values = power.read(1, window=window, masked=True)
            qa = mask.read(1, window=window, masked=True)
            if not np.isin(qa.data, [0, 1, 2, 3, 255]).all():
                raise PlatformError("QA_SCHEMA_MISMATCH")
            valid = (
                included
                & ~np.ma.getmaskarray(values)
                & ~np.ma.getmaskarray(qa)
                & (qa.data == 0)
                & np.isfinite(values.data)
                & (values.data > 0)
            )
            count = int(valid.sum())
            support.update(
                total_supported_pixels=int(included.sum()), valid_pixels=count
            )
            return {
                "schema_version": "earthsync.local-raster-processing.v1",
                "usable_for_assessment": False,
                "status": "available" if count else "no_valid_pixels",
                "metadata": metadata.model_dump(mode="json"),
                "support": support,
                "covered_pixel_mean_power": float(values.data[valid].mean())
                if count
                else None,
                "source_sha256": [digest(p) for p in paths],
                "grid": {
                    "crs": power.crs.to_string(),
                    "transform": list(power.transform),
                    "pixel_spacing_m": 30,
                    "effective_spatial_resolution_m": None,
                },
                "limitations": [
                    "Gamma0 linear power is not soil moisture, crop health or flood evidence.",
                    "No live retrieval or interpretation method validated.",
                ],
            }
    except rasterio.errors.RasterioError as exc:
        raise PlatformError("INVALID_LOCAL_RASTER") from exc


def radar_change(before, after):
    keys = [
        "product",
        "version",
        "polarization",
        "orbit_direction",
        "relative_orbit",
        "burst_id",
        "geometry_id",
        "processing_id",
        "unit",
        "mask_convention",
    ]
    if (
        any(before["metadata"][k] != after["metadata"][k] for k in keys)
        or before["grid"] != after["grid"]
        or before["support"] != after["support"]
    ):
        raise PlatformError("INCOMPATIBLE_RADAR_ACQUISITIONS")
    # Aggregate means are not paired common pixels. Do not subtract them even
    # when counts happen to match; a native common-pixel mask is still required.
    if datetime.fromisoformat(
        after["metadata"]["acquired_at"].replace("Z", "+00:00")
    ) <= datetime.fromisoformat(
        before["metadata"]["acquired_at"].replace("Z", "+00:00")
    ):
        raise PlatformError("TEMPORAL_MISMATCH")
    return {
        "status": "unavailable",
        "reason": "COMMON_VALID_PIXEL_MASK_REQUIRED",
        "change": None,
    }
