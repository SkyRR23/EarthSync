"""Farm greenness (NDVI) from NASA HLS, 30 m pixels, inside the farm border.

HLS = Harmonized Landsat and Sentinel-2 (LP DAAC, collections HLSS30/HLSL30
v2.0). Reading the images needs an Earthdata Login token (EARTHDATA_TOKEN,
from Secret Manager). Only pixels whose centre is inside the farm and that
NASA's own Fmask marks clear count. NDVI is a measured index of green cover
(-1..1), not a crop-health verdict; the app shows it with its date and the
number of clear pixels. Nothing is filled or guessed.
"""

from __future__ import annotations

import asyncio
import math
import os
import time
from collections import OrderedDict
from datetime import datetime, timedelta, timezone
from typing import Optional, Protocol

import httpx
from fastapi import APIRouter, Query, Request
from fastapi.responses import JSONResponse

STAC = "https://cmr.earthdata.nasa.gov/stac/LPCLOUD/search"
COLLECTIONS = {"HLSS30_2.0": ("Sentinel-2", "B8A"), "HLSL30_2.0": ("Landsat", "B05")}
# Fmask bits: 1 cloud, 2 next to cloud/shadow, 3 cloud shadow, 4 snow/ice,
# 5 water. Any of them set = not a clear land pixel.
FMASK_NOT_CLEAR = 0b0011_1110
SCALE, FILL = 0.0001, -9999
PIXEL_M = 30.0
DAYS_BACK = 75
MAX_READS = 8

router = APIRouter()


class NotConfigured(Exception):
    pass


def point_in_polygon(x: float, y: float, poly: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def pixel_ndvi(red: float, nir: float, fmask: int) -> Optional[float]:
    """NDVI of one pixel, or None when it is not a clear, valid land pixel."""
    if fmask == 255 or fmask & FMASK_NOT_CLEAR:
        return None
    if red == FILL or nir == FILL:
        return None
    r, n = red * SCALE, nir * SCALE
    if not (0 <= r <= 1.2 and 0 <= n <= 1.2) or r + n <= 0:
        return None
    return (n - r) / (n + r)


def summarize(pixels: list[dict]) -> dict:
    """pixels: [{"ndvi": float|None, "corners": [[lat, lon] x4]}] inside the farm."""
    values = sorted(p["ndvi"] for p in pixels if p["ndvi"] is not None)
    mid = len(values) // 2
    median = (
        None
        if not values
        else values[mid]
        if len(values) % 2
        else (values[mid - 1] + values[mid]) / 2
    )
    return {
        "pixels_inside": len(pixels),
        "pixels_clear": len(values),
        "ndvi_mean": round(sum(values) / len(values), 3) if values else None,
        "ndvi_median": round(median, 3) if median is not None else None,
    }


class SceneReader(Protocol):
    def read(self, item: dict, farm: list[tuple[float, float]]) -> list[dict]: ...


class HlsReader:
    """Reads only the small window around the farm from the cloud-optimised
    GeoTIFFs (HTTP range requests), with the Earthdata token."""

    def __init__(self, token: str):
        self.token = token

    def read(self, item: dict, farm: list[tuple[float, float]]) -> list[dict]:
        import rasterio
        from rasterio.warp import transform
        from rasterio.windows import from_bounds

        _, nir_band = COLLECTIONS[item["collection"]]
        hrefs = {k: item["assets"][k]["href"] for k in ("B04", nir_band, "Fmask")}
        env = rasterio.Env(
            GDAL_HTTP_HEADERS=f"Authorization: Bearer {self.token}",
            GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
            CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif",
            GDAL_HTTP_MAX_RETRY="2",
            GDAL_HTTP_RETRY_DELAY="1",
        )
        with env, rasterio.open(hrefs["B04"]) as red_ds:
            lats = [p[0] for p in farm]
            lons = [p[1] for p in farm]
            xs, ys = transform("EPSG:4326", red_ds.crs, lons, lats)
            poly = list(zip(xs, ys))
            pad = PIXEL_M
            win = (
                from_bounds(
                    min(xs) - pad,
                    min(ys) - pad,
                    max(xs) + pad,
                    max(ys) + pad,
                    red_ds.transform,
                )
                .round_offsets()
                .round_lengths()
            )
            red = red_ds.read(1, window=win, boundless=True, fill_value=FILL)
            win_tf = red_ds.window_transform(win)
            crs = red_ds.crs
            with rasterio.open(hrefs[nir_band]) as ds:
                nir = ds.read(1, window=win, boundless=True, fill_value=FILL)
            with rasterio.open(hrefs["Fmask"]) as ds:
                fmask = ds.read(1, window=win, boundless=True, fill_value=255)

        cells, centres = [], []
        for row in range(red.shape[0]):
            for col in range(red.shape[1]):
                x, y = win_tf * (col + 0.5, row + 0.5)
                if not point_in_polygon(x, y, poly):
                    continue
                v = pixel_ndvi(
                    float(red[row, col]), float(nir[row, col]), int(fmask[row, col])
                )
                h = PIXEL_M / 2
                corner_xy = [
                    (x - h, y + h),
                    (x + h, y + h),
                    (x + h, y - h),
                    (x - h, y - h),
                ]
                cells.append(v)
                centres.append(corner_xy)
        if not cells:
            return []
        flat_x = [c[0] for cs in centres for c in cs]
        flat_y = [c[1] for cs in centres for c in cs]
        lon, lat = transform(crs, "EPSG:4326", flat_x, flat_y)
        out = []
        for i, v in enumerate(cells):
            corners = [
                [round(lat[4 * i + k], 6), round(lon[4 * i + k], 6)] for k in range(4)
            ]
            out.append({"ndvi": None if v is None else round(v, 3), "corners": corners})
        return out


class Search(Protocol):
    async def items(
        self, farm: list[tuple[float, float]], since: datetime
    ) -> list[dict]: ...


class StacSearch:
    def __init__(self, client: httpx.AsyncClient):
        self.client = client

    async def items(self, farm, since):
        lats = [p[0] for p in farm]
        lons = [p[1] for p in farm]
        body = {
            "collections": list(COLLECTIONS),
            "bbox": [min(lons), min(lats), max(lons), max(lats)],
            "datetime": f"{since:%Y-%m-%dT00:00:00Z}/..",
            "limit": 60,
        }
        r = await self.client.post(STAC, json=body)
        if r.status_code != 200:
            raise RuntimeError(f"stac {r.status_code}")
        feats = r.json().get("features", [])
        return sorted(feats, key=lambda f: f["properties"]["datetime"], reverse=True)


def parse_farm(raw: str) -> list[tuple[float, float]]:
    # "lat,lon,lat,lon,..." (web.app keeps commas; a raw ";" is mangled by
    # Firebase Hosting) or "lat,lon;lat,lon;...".
    nums = [float(v) for v in raw.replace(";", ",").split(",")]
    if len(nums) % 2:
        raise ValueError
    pts = []
    for lat, lon in zip(nums[0::2], nums[1::2]):
        if not (math.isfinite(lat) and math.isfinite(lon)):
            raise ValueError
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError
        pts.append((lat, lon))
    if not 3 <= len(pts) <= 8:
        raise ValueError
    lats = [p[0] for p in pts]
    lons = [p[1] for p in pts]
    # A farm, not a district: about 5 km across at most.
    if max(lats) - min(lats) > 0.05 or max(lons) - min(lons) > 0.05:
        raise ValueError
    return pts


async def farm_greenness(
    farm: list[tuple[float, float]],
    search: Search,
    reader: SceneReader,
    now: datetime,
) -> dict:
    """Newest clear image (at least half the farm's pixels clear), and the
    clear image before it for comparison."""
    items = await search.items(farm, now - timedelta(days=DAYS_BACK))
    found: list[dict] = []
    reads = 0
    for item in items:
        if reads >= MAX_READS or len(found) == 2:
            break
        cloud = item["properties"].get("eo:cloud_cover")
        if isinstance(cloud, (int, float)) and cloud > 90:
            continue
        if found and found[0]["date"] == item["properties"]["datetime"][:10]:
            continue
        reads += 1
        try:
            pixels = await asyncio.to_thread(reader.read, item, farm)
        except Exception:
            continue  # one unreadable image never fails the answer
        s = summarize(pixels)
        if s["pixels_inside"] == 0 or s["pixels_clear"] * 2 < s["pixels_inside"]:
            continue
        sensor, _ = COLLECTIONS[item["collection"]]
        scene = {
            "date": item["properties"]["datetime"][:10],
            "sensor": sensor,
            "granule": item["id"],
            **s,
        }
        if not found:
            scene["cells"] = pixels
        found.append(scene)
    return {
        "latest": found[0] if found else None,
        "previous": found[1] if len(found) > 1 else None,
        "searched_days": DAYS_BACK,
    }


class GreennessCache:
    def __init__(self, ttl=12 * 3600, capacity=256, clock=time.monotonic):
        self.ttl, self.capacity, self.clock = ttl, capacity, clock
        self.entries: OrderedDict = OrderedDict()
        self.lock = asyncio.Lock()

    async def get(self, key, make):
        async with self.lock:
            hit = self.entries.get(key)
            if hit and hit[0] > self.clock():
                return {**hit[1], "cache": {"hit": True}}
            value = await make()
            self.entries[key] = (self.clock() + self.ttl, value)
            while len(self.entries) > self.capacity:
                self.entries.popitem(last=False)
            return {**value, "cache": {"hit": False}}


def _error(status: int, code: str, message: str, retryable: bool) -> JSONResponse:
    return JSONResponse(
        status_code=status,
        content={
            "status": "error",
            "error": {"code": code, "message": message, "retryable": retryable},
        },
    )


@router.get("/api/v1/environment/greenness")
async def greenness(
    request: Request,
    farm: str = Query(max_length=400, description="farm corners: lat,lon,lat,lon,…"),
):
    try:
        pts = parse_farm(farm)
    except (ValueError, TypeError):
        return _error(
            422, "INVALID_INPUT", "Send 3 to 8 farm corners as lat,lon;lat,lon.", False
        )
    state = request.app.state
    reader = getattr(state, "greenness_reader", None)
    if reader is None:
        token = os.environ.get("EARTHDATA_TOKEN")
        if not token:
            return _error(
                503, "not_configured", "Plant health images are not set up yet.", False
            )
        reader = HlsReader(token)
    search = state.greenness_search
    now = datetime.now(timezone.utc)

    async def make():
        result = await farm_greenness(pts, search, reader, now)
        return {
            "status": "success",
            **result,
            "provenance": {
                "provider": "NASA LP DAAC",
                "product": "HLS v2.0 (HLSS30 Sentinel-2, HLSL30 Landsat), 30 m surface reflectance",
                "index": "NDVI = (NIR - Red) / (NIR + Red); NIR B8A (Sentinel-2) or B05 (Landsat), Red B04",
                "mask": "Only pixels NASA Fmask marks clear (no cloud, shadow, snow or water); pixel centre inside the farm",
                "data_kind": "observed",
                "note": "A satellite index of green cover, not a crop-health verdict. 30 m pixels near the border also see the land next to it.",
            },
        }

    key = (tuple((round(a, 5), round(b, 5)) for a, b in pts), now.date().isoformat())
    try:
        return await state.greenness_cache.get(key, make)
    except Exception:
        return _error(
            503,
            "UPSTREAM_UNAVAILABLE",
            "NASA images could not be read right now.",
            True,
        )
