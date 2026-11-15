"""Bounded GFS weather subsets with native GRIB time/accumulation validation."""

import asyncio
from datetime import datetime, timedelta, timezone
import math
from urllib.parse import urlencode

import numpy as np
import rasterio
from rasterio.io import MemoryFile

from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.models import Point
from earthsync.platform_v1.providers.gfs import ENDPOINT
from earthsync.platform_v1.providers.transport import Capture
from earthsync.platform_v1.store import cache_key

from .http import SourceError


def read_weather(capture, point, run, hour):
    """Accept only reviewed levels/units; never infer accumulation from lead time."""
    if not capture.body.startswith(b"GRIB") or len(capture.body) > 100000:
        raise SourceError("FORECAST_ENCODING_MISMATCH")
    specs = {
        ("TMP", "2-HTGL"): ("temperature_c", "[K]", -150, 100),
        ("RH", "2-HTGL"): ("relative_humidity_pct", "[%]", 0, 100),
        ("UGRD", "10-HTGL"): ("wind_u_ms", "[m/s]", -150, 150),
        ("VGRD", "10-HTGL"): ("wind_v_ms", "[m/s]", -150, 150),
    }
    result, selected_tags, precipitation = {}, [], {}
    try:
        with rasterio.Env(
            GDAL_PAM_ENABLED="NO",
            GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
            GRIB_NORMALIZE_UNITS="NO",
        ):
            with MemoryFile(capture.body) as mem, mem.open(driver="GRIB") as ds:
                if (
                    not ds.crs
                    or not ds.crs.is_geographic
                    or ds.res != (0.25, 0.25)
                    or ds.width * ds.height > 16
                    or ds.count > 12
                ):
                    raise SourceError("FORECAST_GRID_MISMATCH")
                row, col = ds.index(point.longitude, point.latitude)
                if not 0 <= row < ds.height or not 0 <= col < ds.width:
                    raise SourceError("SPATIAL_MISMATCH")
                for band in range(1, ds.count + 1):
                    tags = ds.tags(band)
                    element, level = tags["GRIB_ELEMENT"], tags["GRIB_SHORT_NAME"]
                    is_precip = element.startswith("APCP") and level == "0-SFC"
                    if (element, level) not in specs and not is_precip:
                        continue
                    reference = datetime.fromtimestamp(
                        int(tags["GRIB_REF_TIME"]), timezone.utc
                    )
                    valid = datetime.fromtimestamp(
                        int(tags["GRIB_VALID_TIME"]), timezone.utc
                    )
                    if (
                        reference != run
                        or valid != run + timedelta(hours=hour)
                        or "CENTER=7(US-NCEP)" not in tags["GRIB_IDS"]
                        or "PROD_STATUS=0(Operational)" not in tags["GRIB_IDS"]
                    ):
                        raise SourceError("FORECAST_TIME_OR_PRODUCT_MISMATCH")
                    raw = ds.read(band, masked=True)[row, col]
                    value = (
                        None
                        if np.ma.is_masked(raw) or not math.isfinite(float(raw))
                        else float(raw)
                    )
                    if is_precip:
                        # WMO Product Definition Template 4.8: accumulation,
                        # one time range, hours, forecast start and interval length.
                        pds = [
                            int(v)
                            for v in tags["GRIB_PDS_TEMPLATE_ASSEMBLED_VALUES"].split()
                        ]
                        if (
                            tags["GRIB_PDS_PDTN"] != "8"
                            or len(pds) != 29
                            or pds[7] != 1
                            or pds[21] != 1
                            or pds[23:26] != [1, 2, 1]
                            or tags["GRIB_UNIT"] != "[kg/(m^2)]"
                        ):
                            raise SourceError("UNSUPPORTED_PRECIPITATION_ACCUMULATION")
                        start = run + timedelta(hours=pds[8])
                        end = datetime(*pds[15:21], tzinfo=timezone.utc)
                        if (
                            start + timedelta(hours=pds[26]) != valid
                            or end != valid
                            or not 0 < pds[26] <= hour
                            or pds[8] < 0
                        ):
                            raise SourceError("FORECAST_ACCUMULATION_TIME_MISMATCH")
                        if value is not None and not 0 <= value <= 3000:
                            raise SourceError("SCIENTIFIC_QA_REJECTION")
                        key = (start.isoformat(), end.isoformat())
                        if (
                            key in precipitation
                            and precipitation[key]["value_mm"] != value
                        ):
                            raise SourceError("AMBIGUOUS_FORECAST_ACCUMULATION")
                        precipitation[key] = {
                            "start": key[0],
                            "end": key[1],
                            "value_mm": value,
                        }
                        selected_tags.append({"band": band, **tags})
                        continue
                    else:
                        name, unit, low, high = specs[(element, level)]
                        if (
                            tags["GRIB_UNIT"] != unit
                            or int(tags["GRIB_FORECAST_SECONDS"]) != hour * 3600
                        ):
                            raise SourceError("FORECAST_UNIT_OR_TIME_MISMATCH")
                        if name == "temperature_c" and value is not None:
                            value -= 273.15
                    if value is not None and not low <= value <= high:
                        raise SourceError("SCIENTIFIC_QA_REJECTION")
                    if name in result and result[name] != value:
                        raise SourceError("AMBIGUOUS_FORECAST_FIELD")
                    result[name] = value
                    selected_tags.append({"band": band, **tags})
                if not precipitation:
                    raise SourceError("MISSING_FORECAST_VARIABLE")
                intervals = sorted(precipitation.values(), key=lambda r: r["start"])
                latest = intervals[-1]
                result.update(
                    precipitation_intervals=intervals,
                    precipitation_start=latest["start"],
                    precipitation_end=latest["end"],
                    precipitation_mm=latest["value_mm"],
                    precipitation_conversion="1 kg/m² liquid water equivalent = 1 mm. Summary uses the shortest ending interval; all native intervals retained without addition or redistribution.",
                )
                if not all(
                    name in result
                    for name in (
                        "temperature_c",
                        "relative_humidity_pct",
                        "wind_u_ms",
                        "wind_v_ms",
                        "precipitation_mm",
                    )
                ):
                    raise SourceError("MISSING_FORECAST_VARIABLE")
                if result["wind_u_ms"] is not None and result["wind_v_ms"] is not None:
                    result["wind_speed_ms"] = math.hypot(
                        result["wind_u_ms"], result["wind_v_ms"]
                    )
                return {
                    **result,
                    "model_initialized_at": run.isoformat(),
                    "valid_at": valid.isoformat(),
                    "forecast_hour": hour,
                    "grid_point": list(ds.xy(row, col)),
                    "crs": ds.crs.to_wkt(),
                    "grib_metadata": selected_tags,
                    "sha256": capture.sha256,
                    "retrieved_at": capture.retrieved_at.isoformat(),
                    "source_url": capture.headers.get("source_url"),
                }
    except (rasterio.errors.RasterioError, ValueError, KeyError, TypeError) as exc:
        raise SourceError("FORECAST_ENCODING_MISMATCH") from exc


class GfsWeather:
    kind = "MODEL_FORECAST"
    interval = 1800
    stale_after = 21600
    limitations = "NOAA GFS regional 0.25° grid. Model initialization is not publication time. Sparse 12/24/48/72-hour samples and native accumulation intervals; never daily totals or observed rainfall. May share the underlying model with Open-Meteo."

    def __init__(self, source):
        self.source = source

    async def fetch(self, location, old, now):
        point = Point(latitude=location["lat"], longitude=location["lon"])
        run = now.replace(hour=now.hour // 6 * 6, minute=0, second=0, microsecond=0)
        async with self.source.slots:
            # Try the current cycle once; if not yet published, the prior cycle.
            for attempt in range(2):
                candidate = run - timedelta(hours=6 * attempt)
                key = cache_key(
                    "NOAA",
                    "GFS-weather",
                    "realtime.v1",
                    {"run": candidate.isoformat(), "point": point.model_dump()},
                )
                cached = self.source.store.cache_get(key)
                if cached:
                    return cached
                records = []
                try:
                    for hour in (12, 24, 48, 72):
                        lon = round(point.longitude * 4) / 4 % 360
                        lat = min(89.75, max(-89.75, round(point.latitude * 4) / 4))
                        params = {
                            "file": f"gfs.t{candidate.hour:02d}z.pgrb2.0p25.f{hour:03d}",
                            "lev_2_m_above_ground": "on",
                            "lev_10_m_above_ground": "on",
                            "lev_surface": "on",
                            **{
                                f"var_{v}": "on"
                                for v in ("TMP", "RH", "UGRD", "VGRD", "APCP")
                            },
                            "subregion": "",
                            "leftlon": str(max(0, lon - 0.25)),
                            "rightlon": str(min(359.75, lon + 0.25)),
                            "toplat": str(min(90, lat + 0.25)),
                            "bottomlat": str(max(-90, lat - 0.25)),
                            "dir": f"/gfs.{candidate:%Y%m%d}/{candidate.hour:02d}/atmos",
                        }
                        cap = await self.source.request_subset(params)
                        cap = Capture(
                            cap.body,
                            cap.retrieved_at,
                            {
                                **cap.headers,
                                "source_url": ENDPOINT + "?" + urlencode(params),
                            },
                        )
                        records.append(
                            await asyncio.to_thread(
                                read_weather, cap, point, candidate, hour
                            )
                        )
                except PlatformError as exc:
                    if attempt == 0 and exc.code == "PROVIDER_UNAVAILABLE":
                        continue
                    raise SourceError(exc.code) from exc
                result = {
                    "records": records,
                    "model_initialized_at": candidate.isoformat(),
                    "publication_at": None,
                    "resolution": "0.25° regional GFS grid",
                    "valid_until": records[-1]["valid_at"],
                    "provenance": [
                        {
                            "url": r["source_url"],
                            "sha256": r["sha256"],
                            "retrieved_at": r["retrieved_at"],
                            "http_status": 200,
                            "request_ms": None,
                        }
                        for r in records
                    ],
                }
                self.source.store.cache_put(key, result, ttl=21600)
                return result
        raise SourceError("DATASET_NOT_PUBLISHED")
