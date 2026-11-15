"""Bounded SoilGrids RUN05 pH cells from an explicitly accepted WebDAV manifest.

This is separate from WCS; its nodata contract is never assigned to WCS pixels.
Only one 600x600 tile is retrieved. No global raster is opened or downloaded.
"""

import asyncio
import math
import time
import re
from xml.etree import ElementTree as ET

import numpy as np
import rasterio
from rasterio.io import MemoryFile
from rasterio.transform import Affine
from rasterio.warp import transform, transform_geom
from shapely.geometry import box, mapping

from ..errors import PlatformError

BASE = "https://files.isric.org/soilgrids/latest/data/phh2o/"
MANIFEST = BASE + "phh2o_0-5cm_mean.vrt"
MANIFEST_SHA256 = "28bf9ceef0ee29a2d29926929b1760eddb6749b4f31ed212e8d536a226892f0d"
ASSET_PATTERN = (
    r"phh2o_0-5cm_mean/tileSG-\d{3}-\d{3}/tileSG-\d{3}-\d{3}_[1-3]-[1-3]\.tif"
)
POLICY = "soilgrids-webdav-ph-run05.v1"


def select_tile(capture, point):
    if capture.sha256 != MANIFEST_SHA256:
        raise PlatformError("SOIL_MANIFEST_REVISION_UNACCEPTED", 502)
    root = ET.fromstring(capture.body)
    band = root.find("VRTRasterBand")
    if (
        band is None
        or band.attrib != {"dataType": "Int16", "band": "1"}
        or band.findtext("NoDataValue") != "-32768"
    ):
        raise PlatformError("SOIL_ENCODING_MISMATCH", 502)
    crs = rasterio.crs.CRS.from_wkt(root.findtext("SRS"))
    affine = Affine.from_gdal(
        *[float(v) for v in root.findtext("GeoTransform").split(",")]
    )
    x, y = transform("EPSG:4326", crs, [point.longitude], [point.latitude])
    col, row = ~affine * (x[0], y[0])
    matches = []
    for source in band.findall("ComplexSource"):
        rect = {k: float(v) for k, v in source.find("DstRect").attrib.items()}
        if (
            rect["xOff"] <= col < rect["xOff"] + rect["xSize"]
            and rect["yOff"] <= row < rect["yOff"] + rect["ySize"]
        ):
            path = source.findtext("SourceFilename").removeprefix("./")
            if (
                not re.fullmatch(ASSET_PATTERN, path)
                or rect["xSize"] != 600
                or rect["ySize"] != 600
                or source.findtext("NODATA") != "-32768"
            ):
                raise PlatformError("SOIL_GRID_MISMATCH", 502)
            matches.append(
                (BASE + path, affine * Affine.translation(rect["xOff"], rect["yOff"]))
            )
    if len(matches) != 1:
        raise PlatformError("SOIL_NO_COVERAGE", 404)
    return matches[0]


def read_cells(capture, point, expected_transform, manifest_capture):
    try:
        with rasterio.Env(
            GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", GDAL_PAM_ENABLED="NO"
        ):
            with MemoryFile(capture.body) as mem, mem.open(driver="GTiff") as ds:
                # The TIFF's datum is named "unknown", but its projection and
                # WGS84 ellipsoid are explicit. Compare those, retain full WKT.
                proj = ds.crs.to_dict() if ds.crs else {}
                if (
                    proj.get("proj") != "igh"
                    or (proj.get("ellps") != "WGS84" and proj.get("datum") != "WGS84")
                    or proj.get("units") != "m"
                    or any(proj.get(k, 0) != 0 for k in ("lon_0", "x_0", "y_0"))
                ):
                    raise PlatformError("SOIL_GRID_MISMATCH", 502)
                if (
                    ds.shape != (600, 600)
                    or ds.count != 1
                    or ds.transform != expected_transform
                    or ds.dtypes != ("int16",)
                    or ds.nodata != -32768
                ):
                    raise PlatformError("SOIL_ENCODING_MISMATCH", 502)
                x, y = transform(
                    "EPSG:4326", ds.crs, [point.longitude], [point.latitude]
                )
                row, col = ds.index(x[0], y[0])
                if not (0 <= row < ds.height and 0 <= col < ds.width):
                    raise PlatformError("SPATIAL_MISMATCH", 502)
                win = rasterio.windows.Window(
                    max(0, col - 2),
                    max(0, row - 2),
                    min(5, ds.width - max(0, col - 2)),
                    min(5, ds.height - max(0, row - 2)),
                )
                data = ds.read(1, window=win, masked=True)
                cells = []
                for r, c in np.ndindex(data.shape):
                    raw = (
                        None if np.ma.getmaskarray(data)[r, c] else int(data.data[r, c])
                    )
                    if raw is not None and not 0 <= raw <= 140:
                        raise PlatformError("SCIENTIFIC_QUALITY_REJECTION", 502)
                    native_row, native_col = int(win.row_off) + r, int(win.col_off) + c
                    left, top = ds.transform * (native_col, native_row)
                    geometry = transform_geom(
                        ds.crs,
                        "EPSG:4326",
                        mapping(box(left, top - 250, left + 250, top)),
                    )
                    # Reject discontinuous footprints near Homolosine seams.
                    coords = geometry["coordinates"][0]
                    if max(v[0] for v in coords) - min(
                        v[0] for v in coords
                    ) > 180 or not all(math.isfinite(v) for p in coords for v in p):
                        raise PlatformError("SPATIAL_MISMATCH", 502)
                    cells.append(
                        {
                            "geometry": geometry,
                            "raw": raw,
                            "value": None if raw is None else raw / 10,
                            "quality": "nodata" if raw is None else "modeled",
                            "row": native_row,
                            "column": native_col,
                            "at_query_point": native_row == row and native_col == col,
                        }
                    )
                return {
                    "schema_version": "earthsync.soil-map.v1",
                    "status": "available"
                    if any(c["value"] is not None for c in cells)
                    else "no_valid_pixels",
                    "provider": "ISRIC SoilGrids",
                    "dataset": "SoilGrids 2.0 / RUN05 / March 2020 model snapshot",
                    "property": "phh2o",
                    "depth_cm": [0, 5],
                    "statistic": "mean",
                    "unit": "pH",
                    "raw_unit": "pH × 10",
                    "scale": 0.1,
                    "offset": 0,
                    "nodata": -32768,
                    "resolution_m": 250,
                    "crs": ds.crs.to_wkt(),
                    "transform": list(ds.transform),
                    "display_crs": "EPSG:4326",
                    "cells": cells,
                    "source_url": capture.headers.get("source_url"),
                    "source_sha256": capture.sha256,
                    "manifest_url": MANIFEST,
                    "manifest_sha256": manifest_capture.sha256,
                    "retrieved_at": capture.retrieved_at.isoformat(),
                    "manifest_retrieved_at": manifest_capture.retrieved_at.isoformat(),
                    "license": "CC BY 4.0 · ISRIC SoilGrids",
                    "policy": POLICY,
                    "usable_for_assessment": False,
                    "uncertainty": None,
                    "observation_time": None,
                    "limitations": [
                        "Modeled mean pH, not a field laboratory measurement or crop suitability.",
                        "No prediction quantiles retrieved; numerical uncertainty is unavailable.",
                        "March 2020 describes model metadata, not a field sampling date.",
                        "Only up to 25 native cells around the point from one source tile; no field-wide average.",
                        "Latest alias is mutable: exact accepted VRT hash and retrieved tile hash pin this capture.",
                        "The TIFF names its datum unknown; projection, WGS84 ellipsoid and manifest registration are checked explicitly.",
                    ],
                }
    except PlatformError:
        raise
    except (rasterio.errors.RasterioError, ValueError, TypeError) as exc:
        raise PlatformError("SOIL_ENCODING_MISMATCH", 502) from exc


class SoilWebdav:
    def __init__(self, transport, store):
        self.transport, self.store = transport, store
        self.slots = asyncio.Semaphore(1)
        self.last_attempt = None

    async def retrieve(self, point):
        from .transport import Capture
        from ..store import cache_key

        async with self.slots:
            key = cache_key("ISRIC", "WebDAV", POLICY, point.model_dump())
            cached = self.store.cache_get(key)
            if cached:
                return {**cached, "cache_hit": True}
            attempt = time.monotonic()
            if self.last_attempt is not None and attempt - self.last_attempt < 30:
                raise PlatformError("LOCAL_PROVIDER_RATE_LIMIT", 429, True)
            self.last_attempt = attempt
            manifest = await self.transport.get(MANIFEST, {})
            url, affine = await asyncio.to_thread(select_tile, manifest, point)
            tile = await self.transport.get(url, {})
            tile = Capture(
                tile.body, tile.retrieved_at, {**tile.headers, "source_url": url}
            )
            result = await asyncio.to_thread(read_cells, tile, point, affine, manifest)
            self.store.cache_put(key, result, ttl=86400)
            return {**result, "cache_hit": False}
