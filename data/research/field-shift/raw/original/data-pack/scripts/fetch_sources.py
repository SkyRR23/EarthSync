#!/usr/bin/env python3
"""Field Shift - collect real farm-decision data from public NASA + partner APIs.

Every source here is key-less and public. Anything that needs an Earthdata
Login (SMAP granules, IMERG granules, ECOSTRESS, GEDI, Landsat, GLDAS) is
listed in ../api.txt with its access route but is NOT pulled here: this
script never pretends to have data it could not authenticate for.

Outputs
  ../csv/*.csv          tidy tables, one header row, ISO dates, units in the
                        column name (tmax_c, precip_mm, sm_0_7_m3m3, ...)
  ../tiles/*.jpg        NASA GIBS map tiles around each field (no key needed)
  ../_meta/fetch_log.csv  one row per HTTP request: url, status, bytes, outcome

Usage
  python3 data-pack/scripts/fetch_sources.py             # fetch what is missing
  python3 data-pack/scripts/fetch_sources.py --force     # refetch everything
  python3 data-pack/scripts/fetch_sources.py --only soil # substring filter

Only the Python standard library is used on purpose: the data owner can run
this on a clean laptop with no pip install.
"""

import argparse
import csv
import json
import math
import os
import re
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.dirname(HERE)
CSV_DIR = os.path.join(PACK, "csv")
TILE_DIR = os.path.join(PACK, "tiles")
META_DIR = os.path.join(PACK, "_meta")

UA = "field-shift-data-pack/1.0 (NASA Space Apps 2026; contact: data owner)"
TIMEOUT = 60
RETRIES = 3

TODAY = datetime.now(timezone.utc).date()

LOCATIONS = {
    "hlegu": {"name": "Hlegu, Yangon Region", "lat": 16.87, "lon": 96.20},
    "bago": {"name": "Bago, Bago Region", "lat": 17.33, "lon": 96.48},
    "magway": {"name": "Magway, Magway Region", "lat": 20.15, "lon": 94.93},
}

# A US reference point for the challenge's own example (Nevada alfalfa).
# It proves the US-only USDA paths (SSURGO, CDL, EPQS) work, while Myanmar
# uses SoilGrids + POWER instead.
US_REF = {"id": "us_nv_fallon", "name": "Fallon, Nevada (challenge reference)", "lat": 39.50, "lon": -118.80}

POWER_PARAMS = [
    "T2M", "T2M_MAX", "T2M_MIN", "PRECTOTCORR", "RH2M", "WS2M", "WD2M",
    "ALLSKY_SFC_SW_DWN", "GWETTOP", "GWETROOT",
]

# SoilGrids property -> (map file, unit as the WMS reports it)
SOILGRIDS = [
    ("phh2o", "pH*10"),
    ("clay", "g/100g"),
    ("sand", "g/100g"),
    ("silt", "g/100g"),
    ("soc", "dg/kg"),
    ("nitrogen", "cg/kg"),
    ("cec", "mmol(c)/kg"),
    ("bdod", "cg/cm3"),
]
SOIL_DEPTHS = ["0-5cm", "5-15cm", "15-30cm", "30-60cm"]

# Provider unit -> (factor to SI, SI unit). SoilGrids ships pH x 10 and
# texture in g/kg; a spreadsheet reader will otherwise see "pH 63".
SOIL_SI = {
    "phh2o": (0.1, "pH"),
    "clay": (0.1, "% by weight"),
    "sand": (0.1, "% by weight"),
    "silt": (0.1, "% by weight"),
    "soc": (0.1, "g/kg"),
    "nitrogen": (0.01, "g/kg"),
    "cec": (1.0, "mmol(c)/kg"),
    "bdod": (0.01, "g/cm3"),
}

MODIS_JOBS = [
    # product, band, first, last, label
    ("MOD13Q1", "250m_16_days_NDVI", "A2024001", "A2025365", "ndvi"),
    ("MOD13Q1", "250m_16_days_EVI", "A2024001", "A2025365", "evi"),
    ("MOD11A2", "LST_Day_1km", "A2024001", "A2025365", "lst_day"),
    ("MOD11A2", "LST_Night_1km", "A2024001", "A2025365", "lst_night"),
    ("MCD12Q1", "LC_Type1", "A2015001", "A2024365", "landcover"),
]

IGBP = {
    1: "evergreen_needleleaf", 2: "evergreen_broadleaf", 3: "deciduous_needleleaf",
    4: "deciduous_broadleaf", 5: "mixed_forest", 6: "closed_shrubland",
    7: "open_shrubland", 8: "woody_savanna", 9: "savanna", 10: "grassland",
    11: "permanent_wetland", 12: "cropland", 13: "urban", 14: "cropland_natural_mosaic",
    15: "snow_ice", 16: "barren", 17: "water",
}

CMR_JOBS = [
    ("surface_soil_moisture_smap_9km", "SPL3SMP_E", "SMAP L3 Enhanced 9 km surface soil moisture", "NSIDC DAAC", "Earthdata Login (earthaccess)"),
    ("rootzone_soil_moisture_smap_l4", "SPL4SMGP", "SMAP L4 9 km root-zone soil moisture + ET", "NSIDC DAAC", "Earthdata Login (earthaccess)"),
    ("precipitation_imerg_daily", "GPM_3IMERGDF", "GPM IMERG Final 0.1 deg daily precipitation", "GES DISC", "Earthdata Login (earthaccess)"),
    ("precipitation_imerg_halfhourly", "GPM_3IMERGHH", "GPM IMERG 0.1 deg half-hourly precipitation", "GES DISC", "Earthdata Login (earthaccess)"),
    ("vegetation_modis_ndvi", "MOD13Q1", "MODIS 250 m 16-day NDVI/EVI", "LP DAAC", "earthaccess or ORNL point API"),
    ("vegetation_viirs_ndvi", "VNP13A1", "VIIRS 500 m 16-day NDVI/EVI", "LP DAAC", "earthaccess"),
    ("land_surface_temp_modis", "MOD11A2", "MODIS 1 km 8-day land surface temperature", "LP DAAC", "earthaccess or ORNL point API"),
    ("land_cover_modis", "MCD12Q1", "MODIS 500 m yearly land cover", "LP DAAC", "earthaccess or ORNL point API"),
    ("land_surface_temp_ecostress", "ECO2LSTE", "ECOSTRESS 70 m land surface temperature", "LP DAAC", "Earthdata Login (earthaccess)"),
    ("biomass_gedi", "GEDI04_A", "GEDI L4A above-ground biomass", "ORNL DAAC", "Earthdata Login (earthaccess)"),
]

GIBS_TILES = [
    # layer id, label, zoom (8 is ~600 m/px at this latitude)
    ("VIIRS_SNPP_NDVI_8Day", "ndvi", 8),
    ("MODIS_Terra_L3_Land_Surface_Temp_8Day_Day", "lst_day", 8),
    ("IMERG_Precipitation_Rate", "imerg", 8),
    ("MODIS_Terra_CorrectedReflectance_TrueColor", "truecolor", 8),
]

_log_lock = threading.Lock()
_log_rows = []
LOG_PATH = os.path.join(META_DIR, "fetch_log.csv")


# ---------------------------------------------------------------- http helpers

def _ssl_ctx():
    return ssl.create_default_context()


def http_get(url, timeout=TIMEOUT, tries=RETRIES):
    """GET with retries. Returns (bytes, content_type). Raises on final failure."""
    last = None
    for attempt in range(1, tries + 1):
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=_ssl_ctx()) as resp:
                return resp.read(), resp.headers.get("Content-Type", "")
        except urllib.error.HTTPError as exc:
            body = b""
            try:
                body = exc.read()[:400]
            except Exception:
                pass
            last = "HTTP %s %s" % (exc.code, body.decode("utf-8", "replace").replace("\n", " ")[:200])
            if exc.code in (400, 401, 403, 404):
                break  # retrying a client error will not help
        except Exception as exc:  # DNS, timeout, TLS, connection reset
            last = "%s: %s" % (type(exc).__name__, exc)
        if attempt < tries:
            time.sleep(2 * attempt)
    raise RuntimeError(last or "request failed")


def http_get_logged(url, source, target, note=""):
    started = time.time()
    try:
        payload, ctype = http_get(url)
        _log(source, target, url, "200", len(payload), "ok", note)
        return payload, ctype
    except Exception as exc:
        _log(source, target, url, "-", 0, "failed", "%s | %s" % (exc, note)[:400])
        print("  ! %-42s %s" % (target, exc))
        return None, None


def _log(source, target, url, status, size, outcome, note):
    # Written immediately, one row per request: a killed run still leaves a
    # truthful provenance trail instead of losing it in memory.
    row = {
        "fetched_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": source,
        "target": os.path.basename(target),
        "url": url,
        "http_status": status,
        "bytes": size,
        "outcome": outcome,
        "note": note,
        "seconds": round(time.time() - _started_at, 1),
    }
    with _log_lock:
        _log_rows.append(row)
        os.makedirs(META_DIR, exist_ok=True)
        fresh = not os.path.exists(LOG_PATH) or os.path.getsize(LOG_PATH) == 0
        with open(LOG_PATH, "a", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(row.keys()))
            if fresh:
                writer.writeheader()
            writer.writerow(row)


_started_at = time.time()


# ---------------------------------------------------------------- csv helpers

def write_csv(path, header, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(header)
        writer.writerows(rows)
    print("  + %-46s %5d rows  %6.1f KB" % (os.path.basename(path), len(rows), os.path.getsize(path) / 1024))


def exists(path, force):
    return os.path.exists(path) and not force


def num(value, digits=None):
    """Parse a provider number, treating the POWER fill value as missing."""
    if value is None:
        return None
    try:
        f = float(value)
    except (TypeError, ValueError):
        return None
    if f <= -998.0:  # POWER uses -999
        return None
    return round(f, digits) if digits is not None else f


def iso_from_doy(year, doy):
    try:
        return (date(int(year), 1, 1) + timedelta(days=int(doy) - 1)).isoformat()
    except Exception:
        return ""


# ---------------------------------------------------------------- NASA POWER

def fetch_power_daily(loc, meta, force):
    out = os.path.join(CSV_DIR, "power_daily_%s.csv" % loc)
    if exists(out, force):
        return
    end = TODAY - timedelta(days=2)
    start = end - timedelta(days=120)
    url = ("https://power.larc.nasa.gov/api/temporal/daily/point"
           "?parameters=%s&community=AG&latitude=%.4f&longitude=%.4f"
           "&start=%s&end=%s&format=CSV"
           % (",".join(POWER_PARAMS), meta["lat"], meta["lon"],
              start.strftime("%Y%m%d"), end.strftime("%Y%m%d")))
    payload, _ = http_get_logged(url, "NASA POWER daily", out, "120 days, 0.5x0.625 deg MERRA-2 cell")
    if payload is None:
        return
    text = payload.decode("utf-8", "replace").replace("\r", "")
    lines = text.split("\n")
    header_idx = next((i for i, line in enumerate(lines) if line.startswith("YEAR,DOY")), None)
    if header_idx is None:
        _log("NASA POWER daily", out, url, "200", len(payload), "failed", "no YEAR,DOY header")
        return
    reader = list(csv.reader(lines[header_idx:]))
    header = ["date"] + ["%s_%s" % (p.lower(), UNIT_HINT.get(p, "")) for p in reader[0][2:]]
    header = [h.rstrip("_") for h in header]
    rows = []
    for raw in reader[1:]:
        if len(raw) < 3 or not raw[0].isdigit():
            continue
        rows.append([iso_from_doy(raw[0], raw[1])] + [num(v) for v in raw[2:]])
    write_csv(out, header, rows)


UNIT_HINT = {
    "T2M": "c", "T2M_MAX": "c", "T2M_MIN": "c", "PRECTOTCORR": "mm_day",
    "RH2M": "pct", "WS2M": "m_s", "WD2M": "deg", "ALLSKY_SFC_SW_DWN": "mj_m2_day",
    "GWETTOP": "frac", "GWETROOT": "frac",
}


def fetch_power_monthly(loc, meta, force):
    out = os.path.join(CSV_DIR, "power_monthly_%s.csv" % loc)
    if exists(out, force):
        return
    url = ("https://power.larc.nasa.gov/api/temporal/monthly/point"
           "?parameters=%s&community=AG&latitude=%.4f&longitude=%.4f"
           "&start=2016&end=2025&format=CSV"
           % (",".join(POWER_PARAMS), meta["lat"], meta["lon"]))
    payload, _ = http_get_logged(url, "NASA POWER monthly", out, "2016-2025 monthly means (product era used by the engine)")
    if payload is None:
        return
    text = payload.decode("utf-8", "replace").replace("\r", "")
    lines = text.split("\n")
    header_idx = next((i for i, line in enumerate(lines) if line.startswith("PARAMETER,")), None)
    if header_idx is None:
        return
    reader = list(csv.reader(lines[header_idx:]))
    months = reader[0][2:14]
    data = {}
    for raw in reader[1:]:
        if len(raw) < 14:
            continue
        param, year = raw[0], raw[1]
        data.setdefault(year, {})[param] = raw[2:14]
    rows = []
    for year in sorted(data):
        if not year.isdigit():
            continue
        for m_idx, month in enumerate(months):
            row = [year, m_idx + 1, month]
            for param in POWER_PARAMS:
                vals = data[year].get(param)
                row.append(num(vals[m_idx]) if vals else None)
            rows.append(row)
    write_csv(out, ["year", "month", "month_name"] + ["%s_%s" % (p.lower(), UNIT_HINT.get(p, "")) for p in POWER_PARAMS], rows)


def fetch_power_climatology(loc, meta, force):
    out = os.path.join(CSV_DIR, "power_climatology_%s.csv" % loc)
    if exists(out, force):
        return
    url = ("https://power.larc.nasa.gov/api/temporal/climatology/point"
           "?parameters=%s&community=AG&latitude=%.4f&longitude=%.4f&format=CSV"
           % (",".join(POWER_PARAMS), meta["lat"], meta["lon"]))
    payload, _ = http_get_logged(url, "NASA POWER climatology", out, "2001-2025 monthly normals")
    if payload is None:
        return
    text = payload.decode("utf-8", "replace").replace("\r", "")
    lines = text.split("\n")
    header_idx = next((i for i, line in enumerate(lines) if line.startswith("PARAMETER,")), None)
    if header_idx is None:
        return
    reader = list(csv.reader(lines[header_idx:]))
    months = reader[0][2:14]
    rows = []
    for raw in reader[1:]:
        if len(raw) < 14:
            continue
        for m_idx, month in enumerate(months):
            rows.append([raw[0], m_idx + 1, month, num(raw[2 + m_idx])])
    write_csv(out, ["parameter", "month", "month_name", "value"], rows)


# ---------------------------------------------------------------- Open-Meteo

OPENMETEO_DAILY = {
    "temperature_2m_max": "tmax_c",
    "temperature_2m_min": "tmin_c",
    "precipitation_sum": "precip_mm",
    "precipitation_probability_max": "precip_prob_pct",
    "relative_humidity_2m_mean": "rh_pct",
    "wind_speed_10m_max": "wind_max_kmh",
    "wind_gusts_10m_max": "gust_max_kmh",
    "et0_fao_evapotranspiration": "et0_mm",
    "shortwave_radiation_sum": "srad_mj_m2",
    "soil_moisture_0_to_7cm_mean": "sm_0_7_m3m3",
    "soil_moisture_7_to_28cm_mean": "sm_7_28_m3m3",
    "soil_temperature_0_to_7cm_mean": "soil_temp_0_7_c",
}


def _openmeteo_daily(payload, out):
    doc = json.loads(payload.decode("utf-8", "replace"))
    daily = doc.get("daily") or {}
    times = daily.get("time") or []
    keys = [k for k in OPENMETEO_DAILY if k in daily]
    rows = []
    for i, day in enumerate(times):
        rows.append([day] + [daily[k][i] if i < len(daily[k]) else None for k in keys])
    write_csv(out, ["date"] + [OPENMETEO_DAILY[k] for k in keys], rows)


def fetch_openmeteo_forecast(loc, meta, force):
    out = os.path.join(CSV_DIR, "forecast16_%s.csv" % loc)
    if exists(out, force):
        return
    params = "temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max," \
             "relative_humidity_2m_mean,wind_speed_10m_max,wind_gusts_10m_max,et0_fao_evapotranspiration," \
             "shortwave_radiation_sum,soil_moisture_0_to_7cm_mean,soil_moisture_7_to_28cm_mean,soil_temperature_0_to_7cm_mean"
    url = ("https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f"
           "&daily=%s&forecast_days=16&timezone=auto" % (meta["lat"], meta["lon"], params))
    payload, _ = http_get_logged(url, "Open-Meteo forecast", out, "16-day daily forecast + soil moisture (ERA5-Land/IFS)")
    if payload is None:
        return
    _openmeteo_daily(payload, out)


def fetch_openmeteo_archive(loc, meta, force):
    out = os.path.join(CSV_DIR, "era5land_daily_%s.csv" % loc)
    if exists(out, force):
        return
    start = TODAY - timedelta(days=365)
    end = TODAY - timedelta(days=2)
    params = "temperature_2m_max,temperature_2m_min,precipitation_sum,et0_fao_evapotranspiration," \
             "soil_moisture_0_to_7cm_mean,soil_moisture_7_to_28cm_mean"
    url = ("https://archive-api.open-meteo.com/v1/archive?latitude=%.4f&longitude=%.4f"
           "&start_date=%s&end_date=%s&daily=%s&timezone=auto"
           % (meta["lat"], meta["lon"], start.isoformat(), end.isoformat(), params))
    payload, _ = http_get_logged(url, "Open-Meteo archive (ERA5-Land)", out, "365 days daily history")
    if payload is None:
        return
    _openmeteo_daily(payload, out)


def fetch_openmeteo_current(loc, meta, force):
    out = os.path.join(CSV_DIR, "current_%s.csv" % loc)
    if exists(out, force):
        return
    url = ("https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f"
           "&current=temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m,"
           "wind_direction_10m,soil_moisture_0_to_7cm,is_day&timezone=auto"
           % (meta["lat"], meta["lon"]))
    payload, _ = http_get_logged(url, "Open-Meteo current", out, "real-time conditions at the field")
    if payload is None:
        return
    doc = json.loads(payload.decode("utf-8", "replace"))
    cur = doc.get("current") or {}
    order = ["time", "temperature_2m", "relative_humidity_2m", "precipitation",
             "wind_speed_10m", "wind_direction_10m", "soil_moisture_0_to_7cm", "is_day"]
    header = ["observed_at_local", "t2m_c", "rh_pct", "precip_mm", "wind_kmh", "wind_dir_deg", "sm_0_7_m3m3", "is_day"]
    write_csv(out, header, [[cur.get(k) for k in order]])


def fetch_flood(loc, meta, force):
    out = os.path.join(CSV_DIR, "river_discharge_%s.csv" % loc)
    if exists(out, force):
        return
    url = ("https://flood-api.open-meteo.com/v1/flood?latitude=%.4f&longitude=%.4f"
           "&daily=river_discharge,river_discharge_max&forecast_days=16" % (meta["lat"], meta["lon"]))
    payload, _ = http_get_logged(url, "Open-Meteo flood (GloFAS)", out, "16-day river discharge forecast")
    if payload is None:
        return
    doc = json.loads(payload.decode("utf-8", "replace"))
    daily = doc.get("daily") or {}
    times = daily.get("time") or []
    rows = [[t, daily.get("river_discharge", [None] * len(times))[i],
             daily.get("river_discharge_max", [None] * len(times))[i]] for i, t in enumerate(times)]
    write_csv(out, ["date", "river_discharge_m3s", "river_discharge_max_m3s"], rows)


# ---------------------------------------------------------------- SoilGrids

SG_RE = re.compile(r'id="value">([^<]*)</span>')
SG_UNIT_RE = re.compile(r"<b>Unit: </b>([^<]*)")


def _soilgrids_point(prop, depth, lat, lon):
    """One WMS GetFeatureInfo call. The public REST API is often unreachable;
    the ISRIC map server answers the same 250 m grid as a point query."""
    d = 0.25
    bbox = "%.4f,%.4f,%.4f,%.4f" % (lon - d, lat - d, lon + d, lat + d)
    url = ("https://maps.isric.org/mapserv?map=/map/%s.map"
           "&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetFeatureInfo"
           "&LAYERS=%s_%s_mean&QUERY_LAYERS=%s_%s_mean&STYLES=&FORMAT=image/png"
           "&INFO_FORMAT=text/html&SRS=EPSG:4326&BBOX=%s&WIDTH=101&HEIGHT=101&X=50&Y=50"
           % (prop, prop, depth, prop, depth, bbox))
    payload, _ = http_get(url)
    text = payload.decode("utf-8", "replace")
    values = SG_RE.findall(text)
    unit = SG_UNIT_RE.search(text)
    if not values:
        raise RuntimeError("no value in WMS answer")
    raw = values[0].strip()
    try:
        val = float(raw)
    except ValueError:
        val = None
    return val, (unit.group(1).strip() if unit else ""), url


def fetch_soilgrids(loc, meta, force):
    out = os.path.join(CSV_DIR, "soilgrids_%s.csv" % loc)
    if exists(out, force):
        return
    rows = []

    def job(prop, depth):
        try:
            val, unit, url = _soilgrids_point(prop, depth, meta["lat"], meta["lon"])
            _log("ISRIC SoilGrids WMS", out, url, "200", 0, "ok", "%s %s" % (prop, depth))
            return prop, depth, val, unit, ""
        except Exception as exc:
            _log("ISRIC SoilGrids WMS", out, "map=%s depth=%s" % (prop, depth), "-", 0, "failed", str(exc))
            return prop, depth, None, "", str(exc)[:120]

    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = [pool.submit(job, prop, depth) for prop, _ in SOILGRIDS for depth in SOIL_DEPTHS]
        for fut in as_completed(futures):
            rows.append(fut.result())
    rows.sort(key=lambda r: ([p for p, _ in SOILGRIDS].index(r[0]), SOIL_DEPTHS.index(r[1])))

    def si(prop, value):
        if value is None:
            return None, ""
        factor, unit = SOIL_SI.get(prop, (1.0, ""))
        return round(value * factor, 2), unit

    write_csv(out, ["location", "lat", "lon", "property", "depth", "value", "unit",
                    "value_si", "unit_si", "note"],
              [[loc, meta["lat"], meta["lon"], p, d, v, u,
                si(p, v)[0], si(p, v)[1], note] for p, d, v, u, note in rows])


# ---------------------------------------------------------------- MODIS point API

def _a_date(a):
    """A2024001 -> date(2024,1,1)."""
    return date(int(a[1:5]), 1, 1) + timedelta(days=int(a[5:]) - 1)


def _a_stamp(d):
    return "A%d%03d" % (d.year, d.timetuple().tm_yday)


def _modis_chunk(product, band, lat, lon, first, last):
    url = ("https://modis.ornl.gov/rst/api/v1/%s/subset?latitude=%.4f&longitude=%.4f"
           "&startDate=%s&endDate=%s&band=%s&kmAboveBelow=0&kmLeftRight=0"
           % (product, lat, lon, first, last, band))
    payload, _ = http_get_logged(url, "MODIS ORNL point API", "modis_%s_%s.csv" % (band, product),
                                 "%s %s" % (product, band))
    if payload is None:
        return []
    try:
        doc = json.loads(payload.decode("utf-8", "replace"))
    except ValueError:
        _log("MODIS ORNL point API", "modis_%s.csv" % product, url, "200", len(payload), "failed", "not JSON")
        return []
    scale = doc.get("scale")
    unit = doc.get("units", "")
    out = []
    for point in doc.get("subset", []):
        data = point.get("data") or []
        out.append([point.get("calendar_date"), product, band,
                    data[0] if data else None, scale, unit])
    return out


def fetch_modis(loc, meta, force):
    # The ORNL point API refuses a request covering more than ~10 composites
    # ("exceeds maximum subset tiles support of 10"), so the ranges are split
    # (140 days for 16-day MOD13Q1, 70 days for 8-day MOD11A2). Chunks for all
    # fields run two at a time: a full refetch is ~66 calls, too slow serially.
    tasks = []
    for product, band, first, last, label in MODIS_JOBS:
        out = os.path.join(CSV_DIR, "modis_%s_%s.csv" % (label, loc))
        if exists(out, force):
            continue
        span = 70 if product == "MOD11A2" else 139
        cursor = _a_date(first)
        end = _a_date(last)
        while cursor <= end:
            chunk_end = min(end, cursor + timedelta(days=span))
            tasks.append((out, product, band, label, _a_stamp(cursor), _a_stamp(chunk_end)))
            cursor = chunk_end + timedelta(days=1)

    gathered = {}
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = {
            pool.submit(_modis_chunk, product, band, meta["lat"], meta["lon"], c_first, c_last): (out, product, band, label)
            for out, product, band, label, c_first, c_last in tasks
        }
        for fut in as_completed(futures):
            out, product, band, label = futures[fut]
            gathered.setdefault(out, []).extend(fut.result())

    for out, rows in gathered.items():
        if not rows:
            continue
        product, band, label = rows[0][1], rows[0][2], os.path.basename(out)
        label = "lst" if "lst_" in label else ("landcover" if "landcover" in label else label.split("_")[1])
        scale = rows[0][4]
        try:
            scale_f = float(scale)
        except (TypeError, ValueError):
            scale_f = None
        merged = {}
        for day, prod, bnd, raw, sc, un in rows:
            if day is None:
                continue
            # MODIS fill values are sentinels, not measurements: LST uses 0 and
            # 65535 for "not produced", NDVI/EVI use <= -3000, land cover 255.
            # Left alone they turn into -273 C and -0.3 NDVI in the CSV.
            if raw is not None:
                try:
                    raw_i = int(raw)
                except (TypeError, ValueError):
                    raw_i = None
                if raw_i is not None:
                    if band.startswith("LST") and raw_i in (0, 65535):
                        raw = None
                    elif "NDVI" in band or "EVI" in band:
                        if raw_i <= -3000:
                            raw = None
                    elif band == "LC_Type1" and raw_i == 255:
                        raw = None
            value = raw
            if raw is not None and scale_f is not None:
                value = round(raw * scale_f, 4)
            note = ""
            if band.startswith("LST") and value is not None:
                value = round(value - 273.15, 2)
                note = "converted from Kelvin"
            elif band == "LC_Type1" and raw is not None:
                value = IGBP.get(int(raw), "class_%s" % raw)
                note = "IGBP class"
            merged[day] = [day, prod, bnd, raw, sc, value, un, note]
        write_csv(out, ["date", "product", "band", "raw_value", "scale", "value", "source_unit", "note"],
                  [merged[k] for k in sorted(merged)])


# ---------------------------------------------------------------- terrain

def fetch_terrain(loc, meta, force):
    out = os.path.join(CSV_DIR, "terrain_grid_%s.csv" % loc)
    if exists(out, force):
        return
    step = 0.02  # ~2.2 km north-south
    pts = []
    for dy in (-2, -1, 0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            pts.append((round(meta["lat"] + dy * step, 4), round(meta["lon"] + dx * step, 4)))
    lats = ",".join("%.4f" % p[0] for p in pts)
    lons = ",".join("%.4f" % p[1] for p in pts)
    url = "https://api.open-meteo.com/v1/elevation?latitude=%s&longitude=%s" % (lats, lons)
    payload, _ = http_get_logged(url, "Open-Meteo elevation (Copernicus DEM 90 m)", out, "5x5 terrain grid, 0.02 deg spacing")
    if payload is None:
        return
    doc = json.loads(payload.decode("utf-8", "replace"))
    elev = doc.get("elevation") or []
    rows = []
    for i, (lat, lon) in enumerate(pts):
        rows.append([i // 5 - 2, i % 5 - 2, lat, lon, elev[i] if i < len(elev) else None])
    write_csv(out, ["north_km_offset", "east_km_offset", "lat", "lon", "elevation_m"], rows)


def build_terrain_summary(force):
    out = os.path.join(CSV_DIR, "terrain_summary.csv")
    if exists(out, force):
        return
    rows = []
    for loc, meta in LOCATIONS.items():
        path = os.path.join(CSV_DIR, "terrain_grid_%s.csv" % loc)
        if not os.path.exists(path):
            continue
        with open(path, newline="", encoding="utf-8") as fh:
            grid = list(csv.DictReader(fh))
        vals = {}
        for r in grid:
            if r["elevation_m"] not in ("", "None"):
                vals[(int(r["north_km_offset"]), int(r["east_km_offset"]))] = float(r["elevation_m"])
        if not vals:
            continue
        elevations = list(vals.values())
        centre = vals.get((0, 0))
        # slope in percent = rise (m) / run (m) * 100, using the two cardinal
        # neighbours 2 steps away. Earlier this divided by km, which inflated
        # every slope by 1000x; the values in terrain_summary.csv are metres.
        dz_dy = (vals.get((1, 0), centre) - vals.get((-1, 0), centre)) / (2 * 2.22 * 1000.0) if centre is not None else None
        dz_dx = (vals.get((0, 1), centre) - vals.get((0, -1), centre)) / (2 * 2.13 * 1000.0) if centre is not None else None
        slope_pct = None
        if dz_dx is not None and dz_dy is not None:
            slope_pct = round(math.hypot(dz_dx, dz_dy) * 100, 3)
        rows.append([loc, round(min(elevations), 1), round(max(elevations), 1),
                     round(max(elevations) - min(elevations), 1), round(sum(elevations) / len(elevations), 1),
                     round(centre, 1) if centre is not None else None, slope_pct])
    write_csv(out, ["location", "elev_min_m", "elev_max_m", "relief_m", "elev_mean_m",
                    "elev_center_m", "slope_to_center_pct"], rows)


# ---------------------------------------------------------------- CMR catalogue

def fetch_cmr(force):
    out = os.path.join(CSV_DIR, "satellite_availability_cmr.csv")
    if exists(out, force):
        return
    bbox = "95.8,16.7,96.6,17.5"  # covers all three pilot townships
    window = "2025-01-01T00:00:00Z,2025-12-31T23:59:59Z"
    rows = []

    def job(label, short_name, title, provider, access):
        url = ("https://cmr.earthdata.nasa.gov/search/granules.json?short_name=%s"
               "&bounding_box=%s&temporal=%s&sort_key=-start_date&page_size=1"
               % (short_name, bbox, window))
        try:
            payload, _ = http_get(url)
            doc = json.loads(payload.decode("utf-8", "replace"))
            entry = (doc.get("feed") or {}).get("entry") or []
            latest = entry[0]["time_start"][:10] if entry else ""
            granule = entry[0]["title"] if entry else ""
            outcome = "available" if entry else "no granule over this bbox in 2025"
            _log("NASA CMR", out, url, "200", len(payload), "ok", "%s: %s" % (short_name, outcome))
            return [label, short_name, title, provider, access, outcome, latest, granule]
        except Exception as exc:
            _log("NASA CMR", out, url, "-", 0, "failed", "%s: %s" % (short_name, exc))
            return [label, short_name, title, provider, access, "query failed", "", ""]

    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(job, *j) for j in CMR_JOBS]
        for fut in as_completed(futures):
            rows.append(fut.result())
    order = [j[0] for j in CMR_JOBS]
    rows.sort(key=lambda r: order.index(r[0]))
    write_csv(out, ["layer", "short_name", "title", "provider", "access", "coverage_2025", "latest_granule", "example_granule"], rows)


# ---------------------------------------------------------------- GIBS tiles

def _load_gibs_capabilities():
    url = "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/1.0.0/WMTSCapabilities.xml"
    payload, _ = http_get(url, timeout=90)
    root = ET.fromstring(payload)
    layers = {}
    for layer in root.iter():
        if not layer.tag.endswith("Layer"):
            continue
        ident = None
        default_time = None
        tile_sets = []
        for child in layer:
            tag = child.tag.split("}")[-1]
            if tag == "Identifier" and ident is None:
                ident = (child.text or "").strip()
            elif tag == "Dimension":
                for sub in child:
                    if sub.tag.split("}")[-1] == "Default" and default_time is None:
                        default_time = (sub.text or "").strip()
            elif tag == "TileMatrixSetLink":
                for sub in child:
                    if sub.tag.split("}")[-1] == "TileMatrixSet":
                        tile_sets.append((sub.text or "").strip())
        if ident:
            levels = []
            for ts in tile_sets:
                m = re.search(r"Level(\d+)$", ts)
                if m:
                    levels.append(int(m.group(1)))
            layers[ident] = {"default_time": default_time, "tile_sets": tile_sets,
                             "max_level": max(levels) if levels else 9}
    return layers


def _tile_xy(lat, lon, z):
    n = 2 ** z
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.log(math.tan(lat_rad) + 1.0 / math.cos(lat_rad)) / math.pi) / 2.0 * n)
    return max(0, min(n - 1, x)), max(0, min(n - 1, y))


def fetch_gibs(force):
    layers = None
    try:
        layers = _load_gibs_capabilities()
        _log("NASA GIBS", "capabilities", "WMTSCapabilities.xml", "200", 0, "ok", "%d layers" % len(layers))
    except Exception as exc:
        _log("NASA GIBS", "capabilities", "WMTSCapabilities.xml", "-", 0, "failed", str(exc))
        return

    for loc, meta in LOCATIONS.items():
        for layer_id, label, z in GIBS_TILES:
            out = os.path.join(TILE_DIR, "%s_%s.jpg" % (label, loc))
            if exists(out, force):
                continue
            info = layers.get(layer_id) or {}
            when = info.get("default_time") or (TODAY - timedelta(days=2)).isoformat()
            tile_set = (info.get("tile_sets") or ["GoogleMapsCompatible_Level9"])[0]
            max_level = info.get("max_level", 9)
            ok = False
            # Each GIBS layer advertises its own tile matrix set (IMERG stops at
            # Level6, LST at 7, NDVI at 8, true colour at 9). Asking Level9 for
            # an IMERG tile is a 400, not a missing image.
            for zoom in [z] + [z - k for k in (1, 2, 3)]:
                zoom = min(zoom, max_level)
                if zoom < 0:
                    continue
                xx, yy = _tile_xy(meta["lat"], meta["lon"], zoom)
                url = ("https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/%s/default/%s/"
                       "%s/%d/%d/%d.jpg" % (layer_id, when, tile_set, zoom, yy, xx))
                try:
                    payload, ctype = http_get(url, timeout=45, tries=1)
                except Exception as exc:
                    _log("NASA GIBS tile", out, url, "-", 0, "failed", str(exc))
                    continue
                if payload[:3] == b"\xff\xd8\xff" or "image" in (ctype or ""):
                    os.makedirs(TILE_DIR, exist_ok=True)
                    with open(out, "wb") as fh:
                        fh.write(payload)
                    _log("NASA GIBS tile", out, url, "200", len(payload), "ok",
                         "%s z=%d %s" % (layer_id, zoom, when))
                    print("  + %-46s %6.1f KB  %s z=%d" % (os.path.basename(out), len(payload) / 1024, layer_id, zoom))
                    ok = True
                    break
                _log("NASA GIBS tile", out, url, "200", len(payload), "failed", "not an image")
            if not ok:
                print("  ! tile %s %s unavailable" % (label, loc))


# ---------------------------------------------------------------- US reference path

def fetch_us_reference(force):
    soil_out = os.path.join(CSV_DIR, "us_nv_ssurgo_components.csv")
    if not exists(soil_out, force):
        sql = ("SELECT TOP 10 mu.mukey, mu.muname, c.compname, c.comppct_r, c.drainagecl, "
               "c.hydgrp, c.taxorder, c.slope_r "
               "FROM mapunit mu INNER JOIN component c ON c.mukey = mu.mukey "
               "WHERE mu.mukey IN (SELECT mukey FROM "
               "SDA_Get_Mukey_from_intersection_with_WktWgs84('POINT(%.4f %.4f)')) "
               "ORDER BY c.comppct_r DESC" % (US_REF["lon"], US_REF["lat"]))
        body = json.dumps({"query": sql, "format": "JSON"}).encode()
        url = "https://sdmdataaccess.sc.egov.usda.gov/Tabular/post.rest"
        try:
            req = urllib.request.Request(url, data=body, headers={
                "User-Agent": UA, "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=90, context=_ssl_ctx()) as resp:
                payload = resp.read()
            doc = json.loads(payload.decode("utf-8", "replace"))
            table = doc.get("Table") or []
            _log("USDA Soil Data Access", soil_out, url, "200", len(payload), "ok", "SSURGO components at %s" % US_REF["id"])
            write_csv(soil_out, ["mukey", "map_unit", "component", "component_pct", "drainage_class",
                                 "hydrologic_group", "tax_order", "slope_pct"], table)
        except Exception as exc:
            _log("USDA Soil Data Access", soil_out, url, "-", 0, "failed", str(exc))

    elev_out = os.path.join(CSV_DIR, "us_nv_elevation.csv")
    if not exists(elev_out, force):
        url = ("https://epqs.nationalmap.gov/v1/json?x=%.4f&y=%.4f&units=Meters&wkid=4326"
               % (US_REF["lon"], US_REF["lat"]))
        payload, _ = http_get_logged(url, "USGS EPQS (3DEP)", elev_out, "elevation, US reference point")
        if payload is not None:
            try:
                doc = json.loads(payload.decode("utf-8", "replace"))
                write_csv(elev_out, ["location", "lat", "lon", "elevation_m", "source"],
                          [[US_REF["id"], US_REF["lat"], US_REF["lon"], doc.get("value"), "USGS 3DEP via EPQS"]])
            except ValueError:
                pass


# ---------------------------------------------------------------- driver

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--force", action="store_true", help="refetch files that already exist")
    parser.add_argument("--only", default="", help="only run jobs whose target contains this text")
    args = parser.parse_args()
    force = args.force

    for d in (CSV_DIR, TILE_DIR, META_DIR):
        os.makedirs(d, exist_ok=True)

    print("Field Shift data pack -> %s" % PACK)
    print("Locations: %s" % ", ".join(LOCATIONS))
    print("\n[1/7] NASA POWER (weather + climate normals + soil wetness)")
    for loc, meta in LOCATIONS.items():
        if "power" in args.only or not args.only:
            fetch_power_daily(loc, meta, force)
            fetch_power_monthly(loc, meta, force)
            fetch_power_climatology(loc, meta, force)

    print("\n[2/7] Open-Meteo (real-time, 16-day forecast, ERA5-Land, GloFAS flood)")
    for loc, meta in LOCATIONS.items():
        if "meteo" in args.only or not args.only:
            fetch_openmeteo_current(loc, meta, force)
            fetch_openmeteo_forecast(loc, meta, force)
            fetch_openmeteo_archive(loc, meta, force)
            fetch_flood(loc, meta, force)

    print("\n[3/7] ISRIC SoilGrids (pH, texture, SOC, N, CEC, Ksat to 60 cm)")
    for loc, meta in LOCATIONS.items():
        if "soil" in args.only or not args.only:
            fetch_soilgrids(loc, meta, force)

    print("\n[4/7] MODIS point time series (NDVI/EVI, LST, land cover)")
    for loc, meta in LOCATIONS.items():
        if "modis" in args.only or not args.only:
            fetch_modis(loc, meta, force)

    print("\n[5/7] Terrain (5x5 elevation grid + slope)")
    for loc, meta in LOCATIONS.items():
        if "terrain" in args.only or not args.only:
            fetch_terrain(loc, meta, force)
    if "terrain" in args.only or not args.only:
        build_terrain_summary(force)

    print("\n[6/7] NASA CMR (which satellite products actually cover the fields)")
    if "cmr" in args.only or not args.only:
        fetch_cmr(force)

    print("\n[7/7] NASA GIBS map tiles + US reference path (SSURGO, EPQS)")
    if "gibs" in args.only or not args.only:
        fetch_gibs(force)
    if "us" in args.only or not args.only:
        fetch_us_reference(force)

    ok = sum(1 for r in _log_rows if r["outcome"] == "ok")
    bad = len(_log_rows) - ok
    print("\nDone in %.0fs: %d requests ok, %d failed. Log: %s" % (time.time() - _started_at, ok, bad, LOG_PATH))
    if bad:
        print("Failed requests are listed in the log with their HTTP status; nothing is filled in with a guess.")


if __name__ == "__main__":
    main()
