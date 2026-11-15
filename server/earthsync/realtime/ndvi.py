"""Bounded HLS-VI v2 extraction and a nearest-neighbour Web Mercator display.

The native int16 values, QA and grid remain authoritative. The PNG is only a
colour view of accepted cells from one acquisition; it never fills missing data.
"""

import asyncio
import base64
from datetime import datetime, timezone
import hashlib
import io
import json
import math
import os
import threading
import time

import numpy as np
from PIL import Image
import rasterio
from rasterio.features import geometry_mask
from rasterio.transform import Affine, array_bounds, from_bounds
from rasterio.warp import (
    Resampling,
    reproject,
    transform,
    transform_bounds,
    transform_geom,
)
from rasterio.windows import Window
from shapely.geometry import box, mapping, shape

from earthsync.platform_v1.models import Polygon
from .http import SourceError
from .nasa_assets import AssetSession, RangeFile
from .providers import timestamp

MAX_CELLS = 131072
POLICY = "hls-v2-conservative.v1"


def geometry(location, polygon=None):
    if polygon is None:
        # A public viewport, explicitly distinct from a farmer-confirmed field.
        lon, lat = location["lon"], location["lat"]
        polygon = mapping(box(lon - 0.006, lat - 0.006, lon + 0.006, lat + 0.006))
    validated = Polygon.model_validate(polygon).model_dump(mode="json")
    geom = shape(validated)
    west, south, east, north = geom.bounds
    if not (-80 < south < north < 80) or east - west > 0.2 or north - south > 0.2:
        raise SourceError("NDVI_AREA_TOO_LARGE")
    return validated


def viewport_bbox(value):
    try:
        west, south, east, north = map(float, value.split(","))
    except (TypeError, ValueError):
        raise SourceError("INVALID_MAP_BOUNDS") from None
    if (
        not all(math.isfinite(v) for v in (west, south, east, north))
        or not -180 <= west < east <= 180
        or not -80 < south < north < 80
    ):
        raise SourceError("INVALID_MAP_BOUNDS")
    polygon = geometry({}, mapping(box(west, south, east, north)))
    return {"lon": (west + east) / 2, "lat": (south + north) / 2}, polygon


def _read(product, polygon, session, url, qa):
    name = "qa.tif" if qa else "ndvi.tif"
    with RangeFile(session, url) as reader:

        def opener(path, mode="rb"):
            if path != name or mode not in ("r", "rb"):
                raise FileNotFoundError(path)
            reader.seek(0)
            return reader

        with rasterio.Env(
            GDAL_PAM_ENABLED="NO", GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR"
        ):
            with rasterio.open(name, opener=opener, allowed_drivers=["GTiff"]) as ds:
                if (
                    ds.count != 1
                    or not ds.crs
                    or not ds.crs.is_projected
                    or ds.crs.linear_units != "metre"
                    or ds.res != (30, 30)
                    or ds.transform.b != 0
                    or ds.transform.d != 0
                    or ds.transform.a != 30
                    or ds.transform.e != -30
                ):
                    raise SourceError("RASTER_GRID_MISMATCH")
                if (qa and (ds.dtypes != ("uint8",) or ds.nodata != 255)) or (
                    not qa
                    and (
                        ds.dtypes != ("int16",)
                        or ds.nodata != -19999
                        or ds.scales != (0.0001,)
                        or ds.offsets != (0.0,)
                    )
                ):
                    raise SourceError("RASTER_ENCODING_MISMATCH")
                tags = ds.tags()
                if (
                    abs(
                        (
                            timestamp(tags.get("SENSING_TIME"))
                            - timestamp(product["acquired_start"])
                        ).total_seconds()
                    )
                    > 2
                ):
                    raise SourceError("TEMPORAL_MISMATCH")
                projected = transform_geom("EPSG:4326", ds.crs, polygon)
                west, south, east, north = shape(projected).bounds
                fractional = rasterio.windows.from_bounds(
                    west, south, east, north, ds.transform
                )
                col, row = (
                    math.floor(fractional.col_off),
                    math.floor(fractional.row_off),
                )
                width = math.ceil(fractional.col_off + fractional.width) - col
                height = math.ceil(fractional.row_off + fractional.height) - row
                if (
                    width < 1
                    or height < 1
                    or width * height > MAX_CELLS
                    or max(width, height) > 512
                ):
                    raise SourceError("NDVI_AREA_TOO_LARGE")
                window = Window(col, row, width, height)
                native_transform = ds.window_transform(window)
                inside = geometry_mask(
                    [projected], (height, width), native_transform, invert=True
                )
                if not inside.any():
                    raise SourceError("NO_NATIVE_PIXEL_CENTRES_IN_POLYGON")
                # Read only the intersection, then place it on the bounded native
                # grid. Outside-raster cells stay masked and count as uncovered.
                data = np.ma.masked_all(
                    (height, width), dtype="uint8" if qa else "int16"
                )
                c0, r0 = max(0, col), max(0, row)
                c1, r1 = min(ds.width, col + width), min(ds.height, row + height)
                if c1 > c0 and r1 > r0:
                    data[r0 - row : r1 - row, c0 - col : c1 - col] = ds.read(
                        1, window=Window(c0, r0, c1 - c0, r1 - r0), masked=True
                    )
                grid = {
                    "crs": ds.crs.to_string(),
                    "transform": list(native_transform)[:6],
                    "width": width,
                    "height": height,
                    "column_offset": col,
                    "row_offset": row,
                    "source_transform": list(ds.transform)[:6],
                    "source_shape": list(ds.shape),
                }
                return (
                    data,
                    inside,
                    grid,
                    {
                        k: tags.get(k)
                        for k in (
                            "SENSING_TIME",
                            "MGRS_TILE_ID",
                            "HLS_VI_PROCESSING_TIME",
                        )
                    },
                )


def render(raw, valid, grid):
    native = Affine(*grid["transform"])
    height, width = raw.shape
    bounds = array_bounds(height, width, native)
    projected = transform_bounds(grid["crs"], "EPSG:3857", *bounds, densify_pts=21)
    # Nearest-neighbour display, with no interpolation of vegetation values or QA.
    display_transform = from_bounds(*projected, width, height)
    source = np.where(valid, raw, -19999).astype("int16")
    display = np.full((height, width), -19999, dtype="int16")
    reproject(
        source,
        display,
        src_transform=native,
        src_crs=grid["crs"],
        dst_transform=display_transform,
        dst_crs="EPSG:3857",
        src_nodata=-19999,
        dst_nodata=-19999,
        resampling=Resampling.nearest,
    )
    stops = np.array([-1.0, 0.0, 0.25, 0.5, 0.75, 1.0])
    colours = np.array(
        [
            [120, 72, 37],
            [184, 99, 45],
            [225, 173, 60],
            [213, 218, 95],
            [94, 157, 64],
            [20, 99, 55],
        ]
    )
    rgba = np.zeros((height, width, 4), dtype="uint8")
    values = display * 0.0001
    for channel in range(3):
        rgba[:, :, channel] = np.interp(values, stops, colours[:, channel]).astype(
            "uint8"
        )
    rgba[:, :, 3] = np.where(display == -19999, 0, 255)
    output = io.BytesIO()
    Image.fromarray(rgba).save(output, format="PNG", optimize=True)
    geographic = transform_bounds("EPSG:3857", "EPSG:4326", *projected)
    return base64.b64encode(output.getvalue()).decode("ascii"), list(geographic)


def hls_window(product, polygon, session, *, reject_empty_qa=False):
    receipt_start = len(getattr(session, "receipts", []))
    downloaded_start = session.downloaded
    if (
        product.get("product") not in {"HLSL30_VI", "HLSS30_VI"}
        or product.get("version") != "2.0"
    ):
        raise SourceError("UNSUPPORTED_PRODUCT_VERSION")
    polygon = geometry({}, polygon)
    assets = product["assets"]
    ndvi = next((u for u in assets if u.endswith(".NDVI.tif")), None)
    fmask = next((u for u in assets if u.endswith(".Fmask.tif")), None)
    if not ndvi or not fmask:
        raise SourceError("MISSING_SCIENTIFIC_ASSET")
    qa, inside, grid, qa_tags = _read(product, polygon, session, fmask, True)
    if reject_empty_qa:
        q = qa.filled(255)
        accepted = (
            inside
            & ~np.ma.getmaskarray(qa)
            & ((q & 0b00111111) == 0)
            & (((q >> 6) & 3) != 3)
        )
        if not accepted.any():
            raise SourceError("SCIENTIFIC_QA_REJECTION")
    raw, _, ndvi_grid, tags = _read(product, polygon, session, ndvi, False)
    # Fmask retains upstream HLS processing tags; VI files add a separate VI
    # processing time and tile tag. Only acquisition/support must agree.
    if grid != ndvi_grid or timestamp(qa_tags["SENSING_TIME"]) != timestamp(
        tags["SENSING_TIME"]
    ):
        raise SourceError("RASTER_GRID_MISMATCH")
    if (
        qa_tags.get("MGRS_TILE_ID")
        and tags.get("MGRS_TILE_ID")
        and qa_tags["MGRS_TILE_ID"] != tags["MGRS_TILE_ID"]
    ):
        raise SourceError("RASTER_GRID_MISMATCH")
    q = qa.filled(255)
    values = raw.filled(-19999)
    valid = (
        inside
        & ~np.ma.getmaskarray(qa)
        & ~np.ma.getmaskarray(raw)
        & ((q & 0b00111111) == 0)
        & (((q >> 6) & 3) != 3)
        & (values >= -10000)
        & (values <= 10000)
    )
    count, total = int(valid.sum()), int(inside.sum())
    png, bounds = render(values, valid, grid)
    native_values = np.where(valid, values, -19999)
    return {
        "schema_version": "earthsync.ndvi-overlay.v1",
        "provider": "NASA LP DAAC",
        "product": product["product"],
        "version": product["version"],
        "granule_id": product["granule_id"],
        "acquired_at": product["acquired_start"],
        "catalog_revision_at": product.get("catalog_revision_at"),
        "retrieved_at": datetime.now(timezone.utc).isoformat(),
        "resolution_m": 30,
        "scale": 0.0001,
        "offset": 0,
        "nodata": -19999,
        "qa_policy": POLICY + "; reject bits 0..5, high aerosol, fill, invalid NDVI",
        "valid_pixels": count,
        "polygon_pixels": total,
        "coverage_pct": round(100 * count / total, 2),
        "coverage_definition": "Accepted native cell centres inside polygon / all native cell centres inside polygon, including uncovered cells",
        "quality": "unavailable"
        if count == 0
        else "complete"
        if count == total
        else "partial",
        "geometry": polygon,
        "grid": grid,
        "native_metadata": {"ndvi": tags, "fmask": qa_tags},
        "native_raw": native_values.tolist(),
        "native_qa": q.tolist(),
        "png_base64": png,
        "bounds": bounds,
        "display_crs": "EPSG:3857",
        "display_resampling": "nearest; no temporal mosaic or gap filling",
        "bytes_downloaded": session.downloaded - downloaded_start,
        "source_range_receipts": list(getattr(session, "receipts", []))[receipt_start:],
        "limitations": "NDVI numerical scale only; no crop suitability, diagnosis, yield estimate or field mean. One acquisition, no temporal composite.",
    }


def inspect_pixel(data, lat, lon):
    if (
        not math.isfinite(lat)
        or not math.isfinite(lon)
        or not -90 <= lat <= 90
        or not -180 <= lon <= 180
    ):
        raise SourceError("INVALID_COORDINATES")
    grid = data["grid"]
    x, y = transform("EPSG:4326", grid["crs"], [lon], [lat])
    col, row = (~Affine(*grid["transform"])) * (x[0], y[0])
    row, col = math.floor(row), math.floor(col)
    if not (0 <= row < grid["height"] and 0 <= col < grid["width"]):
        return {"status": "outside_window", "value": None}
    raw, qa = data["native_raw"][row][col], data["native_qa"][row][col]
    return {
        "status": "accepted" if raw != -19999 else "masked_or_outside_polygon",
        "value": round(raw * 0.0001, 4) if raw != -19999 else None,
        "raw_value": raw if raw != -19999 else None,
        "qa_value": qa,
        "row": row + grid["row_offset"],
        "column": col + grid["column_offset"],
        "acquired_at": data["acquired_at"],
        "granule_id": data["granule_id"],
    }


class NdviOverlays:
    def __init__(self, realtime):
        self.realtime = realtime
        self.repository = realtime.repository
        self.tasks = {}
        self.errors = {}
        self.checked = {}
        self.cancel = threading.Event()

    def key(self, location, polygon=None, preference="latest"):
        geom = geometry(location, polygon)
        selection = [POLICY, geom]
        if preference == "clearest":
            selection.append(preference)
        elif preference != "latest":
            raise SourceError("INVALID_ACQUISITION_PREFERENCE")
        return "ndvi:" + hashlib.sha256(
            json.dumps(selection, sort_keys=True).encode()
        ).hexdigest(), geom

    def snapshot(self, location, polygon=None, preference="latest"):
        key, _ = self.key(location, polygon, preference)
        data = self.repository.get(key)
        task = self.tasks.get(key)
        result = {
            "status": "loading"
            if task and not task.done()
            else "cached"
            if data
            else "unavailable",
            "error": self.errors.get(key),
            "data": data,
            "cached": data is not None,
            "source": "NASA HLS-VI v2; no synthetic substitute",
        }
        if data:
            result["data_age_days"] = round(
                (
                    datetime.now(timezone.utc) - timestamp(data["acquired_at"])
                ).total_seconds()
                / 86400,
                2,
            )
            result["stale"] = bool(self.errors.get(key)) or result["data_age_days"] > 16
        return result

    def request(self, location, polygon=None, preference="latest"):
        key, geom = self.key(location, polygon, preference)
        if key in self.tasks and not self.tasks[key].done():
            return
        if time.monotonic() - self.checked.get(key, -1000) < 60:
            return
        self.checked[key] = time.monotonic()
        # Completed task handles carry no image payload. Bound selection churn.
        self.tasks = {k: t for k, t in self.tasks.items() if not t.done()}
        if len(self.tasks) >= 2:
            self.errors[key] = "OVERLAY_BUSY_RETRY_LATER"
            return
        self.tasks[key] = asyncio.create_task(
            self._refresh(key, location, geom, preference)
        )

    async def _refresh(self, key, location, geom, preference="latest"):
        try:
            if not os.getenv("EARTHDATA_TOKEN"):
                raise SourceError("AUTHENTICATION_REQUIRED")
            adapter = self.realtime.adapters["hls_ndvi"]
            catalog = await adapter.catalog.fetch(
                location, None, datetime.now(timezone.utc)
            )
            products = sorted(
                [
                    p
                    for p in catalog["products"]
                    if p["product"] in {"HLSL30_VI", "HLSS30_VI"} and p.get("assets")
                ],
                key=lambda p: p["acquired_start"],
                reverse=True,
            )
            if not products:
                raise SourceError("DATASET_NOT_PUBLISHED")
            signature = [
                [p["granule_id"], p.get("catalog_revision_at")] for p in products
            ]
            cached = self.repository.get(key)
            if cached and cached.get("checked_candidate_ids") == signature:
                self.errors.pop(key, None)
                return
            # Reuse the point-reader semaphore and official authenticated range transport.
            async with adapter.lock:
                result = await asyncio.to_thread(
                    self._extract, products, geom, preference
                )
            self.repository.put(key, result)
            with self.repository.store.connection() as db:
                db.execute(
                    "DELETE FROM realtime_state WHERE key IN (SELECT key FROM realtime_state WHERE key LIKE 'ndvi:%' ORDER BY rowid DESC LIMIT -1 OFFSET 12)"
                )
            self.errors.pop(key, None)
        except SourceError as error:
            self.errors[key] = error.code
        except Exception:
            self.errors[key] = "OVERLAY_EXTRACTION_UNAVAILABLE"

    def _extract(self, products, geom, preference="latest"):
        session = AssetSession(self.cancel)
        best = None
        rejected = []
        examined = []
        try:
            for product in products:
                examined.append(product["granule_id"])
                try:
                    result = hls_window(product, geom, session, reject_empty_qa=True)
                except SourceError as error:
                    if error.code == "SCIENTIFIC_QA_REJECTION":
                        rejected.append(
                            {
                                "granule_id": product["granule_id"],
                                "acquired_at": product["acquired_start"],
                                "reason": error.code,
                            }
                        )
                        continue
                    if (
                        best
                        and preference == "clearest"
                        and error.code in {"PROVIDER_TIMEOUT", "ASSET_BYTE_LIMIT"}
                    ):
                        best["selection_note"] = (
                            "Bounded search stopped; best verified acquisition examined is shown."
                        )
                        break
                    raise
                result["checked_candidate_ids"] = [
                    [p["granule_id"], p.get("catalog_revision_at")] for p in products
                ]
                result["rejected_candidates"] = list(rejected)
                result["total_bytes_downloaded"] = session.downloaded
                result["selection_preference"] = preference
                result["selection_policy"] = (
                    "One acquisition: first with at least 90% QA coverage, otherwise highest coverage among bounded candidates examined."
                    if preference == "clearest"
                    else "Newest acquisition with at least one QA-accepted cell."
                )
                if best is None or result["coverage_pct"] > best["coverage_pct"]:
                    best = result
                if result["valid_pixels"] and (
                    preference == "latest" or result["coverage_pct"] >= 90
                ):
                    result["examined_candidate_ids"] = list(examined)
                    return result
            if best:
                best["examined_candidate_ids"] = list(examined)
                best["rejected_candidates"] = list(rejected)
                best["total_bytes_downloaded"] = session.downloaded
                return best
            raise SourceError("SCIENTIFIC_QA_REJECTION")
        finally:
            session.close()

    async def close(self):
        self.cancel.set()
        for task in self.tasks.values():
            task.cancel()
        await asyncio.gather(*self.tasks.values(), return_exceptions=True)
