"""Small official NOAA GFS temperature subsets with native forecast reference time.

This is modeled context, not observed current weather or an issued warning feed.
Publication time is unknown; GRIB model initialization is retained separately.
"""

import asyncio
import math
import time
from datetime import datetime, timedelta, timezone

import numpy as np
import rasterio
from rasterio.io import MemoryFile

from ..errors import PlatformError

ENDPOINT = "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl"
POLICY = "noaa-gfs-quarter-degree-temperature.v1"
HOURS = (0, 6, 12, 24)


def read_temperature(capture, point, run, hour):
    try:
        if not capture.body.startswith(b"GRIB") or len(capture.body) > 100000:
            raise PlatformError("FORECAST_ENCODING_MISMATCH", 502)
        with rasterio.Env(
            GDAL_PAM_ENABLED="NO",
            GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
            GRIB_NORMALIZE_UNITS="NO",
        ):
            with MemoryFile(capture.body) as mem, mem.open(driver="GRIB") as ds:
                if (
                    ds.count != 1
                    or ds.width * ds.height > 16
                    or not ds.crs
                    or not ds.crs.is_geographic
                    or ds.res != (0.25, 0.25)
                ):
                    raise PlatformError("FORECAST_GRID_MISMATCH", 502)
                tags = ds.tags(1)
                reference = datetime.fromtimestamp(
                    int(tags["GRIB_REF_TIME"]), timezone.utc
                )
                valid = datetime.fromtimestamp(
                    int(tags["GRIB_VALID_TIME"]), timezone.utc
                )
                if (
                    reference != run
                    or valid != run + timedelta(hours=hour)
                    or int(tags["GRIB_FORECAST_SECONDS"]) != hour * 3600
                ):
                    raise PlatformError("FORECAST_TIME_MISMATCH", 502)
                if (
                    tags["GRIB_ELEMENT"] != "TMP"
                    or tags["GRIB_SHORT_NAME"] != "2-HTGL"
                    or tags["GRIB_UNIT"] != "[K]"
                    or "CENTER=7(US-NCEP)" not in tags["GRIB_IDS"]
                    or "PROD_STATUS=0(Operational)" not in tags["GRIB_IDS"]
                ):
                    raise PlatformError("FORECAST_PRODUCT_MISMATCH", 502)
                row, col = ds.index(point.longitude, point.latitude)
                if not 0 <= row < ds.height or not 0 <= col < ds.width:
                    raise PlatformError("SPATIAL_MISMATCH", 502)
                data = ds.read(1, masked=True)
                raw = data[row, col]
                value = (
                    None
                    if np.ma.is_masked(raw) or not math.isfinite(float(raw))
                    else float(raw) - 273.15
                )
                if value is not None and not -150 <= value <= 100:
                    raise PlatformError("SCIENTIFIC_QUALITY_REJECTION", 502)
                lon, lat = ds.xy(row, col)
                return {
                    "valid_at": valid.isoformat(),
                    "model_initialized_at": reference.isoformat(),
                    "forecast_hour": hour,
                    "temperature_c": value,
                    "quality": "missing" if value is None else "modeled",
                    "grid_point": {"latitude": lat, "longitude": lon},
                    "unit": "°C",
                    "native_unit": tags["GRIB_UNIT"],
                    "raw_temperature_k": None if value is None else float(raw),
                    "conversion": "GRIB Kelvin minus 273.15 = Celsius",
                    "grib_metadata": tags,
                    "crs": ds.crs.to_wkt(),
                    "transform": list(ds.transform),
                    "source_url": capture.headers.get("source_url"),
                    "source_sha256": capture.sha256,
                    "retrieved_at": capture.retrieved_at.isoformat(),
                }
    except PlatformError:
        raise
    except (rasterio.errors.RasterioError, KeyError, ValueError, TypeError) as exc:
        raise PlatformError("FORECAST_ENCODING_MISMATCH", 502) from exc


class GfsForecast:
    def __init__(self, transport, store):
        self.transport, self.store = transport, store
        self.slots = asyncio.Semaphore(1)
        self.last_attempt = None
        self.last_grib_request = None

    async def request_subset(self, params):
        # Caller holds slots across the entire subset loop.
        if self.last_grib_request is not None:
            await asyncio.sleep(
                max(0, 10 - (time.monotonic() - self.last_grib_request))
            )
        self.last_grib_request = time.monotonic()
        return await self.transport.get(ENDPOINT, params)

    async def retrieve(self, point, now=None):
        from .transport import Capture
        from ..store import cache_key
        from urllib.parse import urlencode

        now = now or datetime.now(timezone.utc)
        # A conservative delivery lag; no inference of successful publication.
        latest = now - timedelta(hours=6)
        run = latest.replace(
            hour=(latest.hour // 6) * 6, minute=0, second=0, microsecond=0
        )
        key = cache_key(
            "NOAA", "GFS", POLICY, {"point": point.model_dump(), "run": run.isoformat()}
        )
        async with self.slots:
            cached = self.store.cache_get(key)
            if cached:
                return {**cached, "cache_hit": True}
            attempt = time.monotonic()
            if self.last_attempt is not None and attempt - self.last_attempt < 30:
                raise PlatformError("LOCAL_PROVIDER_RATE_LIMIT", 429, True)
            self.last_attempt = attempt
            lon = (round(point.longitude * 4) / 4) % 360
            lat = min(89.75, max(-89.75, round(point.latitude * 4) / 4))
            records = []
            for hour in HOURS:
                params = {
                    "file": f"gfs.t{run.hour:02d}z.pgrb2.0p25.f{hour:03d}",
                    "lev_2_m_above_ground": "on",
                    "var_TMP": "on",
                    "subregion": "",
                    "leftlon": str(max(0, lon - 0.25)),
                    "rightlon": str(min(359.75, lon + 0.25)),
                    "toplat": str(min(90, lat + 0.25)),
                    "bottomlat": str(max(-90, lat - 0.25)),
                    "dir": f"/gfs.{run:%Y%m%d}/{run.hour:02d}/atmos",
                }
                # NOMADS GRIB Filter asks scripted request loops to leave at
                # least ten seconds between requests, even for small subsets.
                cap = await self.request_subset(params)
                cap = Capture(
                    cap.body,
                    cap.retrieved_at,
                    {**cap.headers, "source_url": ENDPOINT + "?" + urlencode(params)},
                )
                records.append(
                    await asyncio.to_thread(read_temperature, cap, point, run, hour)
                )
            future = [r for r in records if datetime.fromisoformat(r["valid_at"]) > now]
            temperatures = [
                r["temperature_c"] for r in future if r["temperature_c"] is not None
            ]
            result = {
                "schema_version": "earthsync.forecast.v1",
                "status": "partial",
                "provider": "NOAA NCEP GFS",
                "dataset": "GFS 0.25 degree operational 2 m temperature",
                "license": "US government data; NOAA attribution",
                "model_initialized_at": run.isoformat(),
                "issued_at": None,
                "issuance_basis": "GRIB forecast reference/model initialization verified; publication/issuance timestamp not supplied",
                "retrieved_at": datetime.now(timezone.utc).isoformat(),
                "timezone": "UTC",
                "forecast_horizon_hours": 24,
                "grid_spacing_degrees": 0.25,
                "unit": "°C",
                "records": records,
                "official_warnings": None,
                "current_observed_weather": None,
                "derived_indicators": [
                    {
                        "kind": "derived_forecast_condition",
                        "name": "Temperature at or below 0 °C in sampled future forecast times",
                        "threshold_c": 0,
                        "basis": "Physical freezing reference only; not a crop-specific damage threshold",
                        "value": any(v <= 0 for v in temperatures)
                        if len(temperatures) == len(future) and temperatures
                        else None,
                    }
                ],
                "limitations": [
                    "Sparse forecast times, not daily minima/maxima or continuous monitoring.",
                    "Current observed weather, precipitation and official warnings are unavailable.",
                    "Regional model grid; no exact field measurement, frost event or crop injury inferred.",
                    "GRIB reference time is model initialization, not independently verified publication time.",
                    "No automatic refresh or background scheduler; retrieve a new snapshot explicitly.",
                ],
                "usable_for_assessment": False,
                "policy": POLICY,
            }
            self.store.cache_put(key, result, ttl=1800)
            return {**result, "cache_hit": False}
