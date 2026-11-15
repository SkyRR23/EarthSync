"""Official source adapters. Unknown measurements and publication times stay null."""

import csv
import io
import math
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode
from zoneinfo import ZoneInfo

from .http import SourceError

UTC = timezone.utc
IEM = "https://mesonet.agron.iastate.edu"
NWS = "https://api.weather.gov"


def timestamp(value):
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if result.tzinfo is None:
            raise ValueError("Timezone required")
        return result.astimezone(UTC)
    except (ValueError, TypeError, AttributeError) as exc:
        raise SourceError("INVALID_TIMESTAMP") from exc


def number(value, low, high):
    try:
        value = float(value)
        return value if math.isfinite(value) and low <= value <= high else None
    except (ValueError, TypeError):
        return None


def distance(lat, lon, other_lat, other_lon):
    a, b = math.radians(lat), math.radians(other_lat)
    v = (
        math.sin((b - a) / 2) ** 2
        + math.cos(a) * math.cos(b) * math.sin(math.radians(other_lon - lon) / 2) ** 2
    )
    return round(6371 * 2 * math.asin(min(1, math.sqrt(v))), 2)


def provenance(receipt):
    return {
        key: receipt[key]
        for key in ("url", "sha256", "retrieved_at", "http_status", "request_ms")
    }


def measurement(
    variable,
    value,
    unit,
    valid,
    *,
    depth_cm=None,
    flag=None,
    station=None,
    interval_seconds=None,
):
    return {
        "variable": variable,
        "value": value,
        "unit": unit,
        "observed_at": valid,
        "depth_cm": depth_cm,
        "quality_flag": flag,
        "station_id": station,
        "interval_seconds": interval_seconds,
    }


class IowaStation:
    kind = "LIVE_STATION_OBSERVATION"
    interval = 60
    stale_after = 900
    limitations = "Nearby station sensors, never measurements inside the selected field. Only returned QC-accepted variables are shown; frozen-sensor diagnosis is unavailable without provider flags."

    def __init__(self, http):
        self.http = http

    async def fetch(self, location, old, now):
        if not (40.3 <= location["lat"] <= 43.6 and -96.7 <= location["lon"] <= -90.1):
            raise SourceError("GEOGRAPHIC_NON_COVERAGE")
        metadata, meta_receipt = await self.http.json(
            IEM + "/geojson/network.py?network=ISUSM&only_online=1", ttl=86400
        )
        stations = []
        for feature in metadata.get("features", []):
            p = feature["properties"]
            lon, lat = feature["geometry"]["coordinates"][:2]
            km = distance(location["lat"], location["lon"], lat, lon)
            if p.get("online") is True and km <= 100:
                stations.append(
                    {
                        "id": feature["id"],
                        "name": p["sname"],
                        "lat": lat,
                        "lon": lon,
                        "distance_km": km,
                        "online": True,
                        "attributes": p.get("attributes", {}),
                    }
                )
        stations.sort(
            key=lambda s: (
                s["id"] != "AMFI4" if location["id"] == "ames" else False,
                s["distance_km"],
            )
        )
        stations = stations[:3]
        if not stations:
            raise SourceError("MISSING_SENSOR")
        previous = old.get("records", []) if old else []
        # At most two recent hours at startup; overlap catches late QC corrections.
        start = now - timedelta(hours=2)
        if previous:
            start = max(
                start,
                timestamp(max(r["observed_at"] for r in previous))
                - timedelta(minutes=5),
            )
        params = {
            "station": ",".join(s["id"] for s in stations),
            "mode": "hourly",
            "timeres": "minute",
            "format": "comma",
            "tz": "UTC",
            "qcflags": "1",
            "missing": "M",
            "vars": "tmpf,relh,precip,speed,drct,soil04t,soil12t,soil24t,soil50t,soil12vwc,soil24vwc,soil50vwc,sv",
            "sts": start.replace(second=0, microsecond=0).isoformat(),
            "ets": now.replace(second=0, microsecond=0).isoformat(),
        }
        receipt = await self.http.get(
            IEM + "/cgi-bin/request/isusm.py?" + urlencode(params), ttl=60
        )
        rows = list(csv.DictReader(io.StringIO(receipt["text"])))
        if not rows or "valid" not in rows[0] or "station" not in rows[0]:
            raise SourceError("DATASET_NOT_PUBLISHED")
        records = {
            (r["station_id"], r["variable"], r["depth_cm"], r["observed_at"]): r
            for r in previous
            if timestamp(r["observed_at"]) >= now - timedelta(hours=2)
            and r["station_id"] in {s["id"] for s in stations}
        }
        specs = {
            "tmpf": (
                "air_temperature",
                "°C",
                -80,
                65,
                lambda v: (v - 32) * 5 / 9,
                None,
            ),
            "relh": ("relative_humidity", "%", 0, 100, lambda v: v, None),
            "precip": ("rainfall", "mm", 0, 200, lambda v: v * 25.4, None),
            "speed": ("wind_speed", "m/s", 0, 150, lambda v: v * 0.44704, None),
            "drct": ("wind_direction", "°", 0, 360, lambda v: v, None),
        }
        for depth in (4, 12, 24, 50):
            specs[f"soil{depth:02d}t"] = (
                "soil_temperature",
                "°C",
                -60,
                70,
                lambda v: (v - 32) * 5 / 9,
                depth * 2.54,
            )
            if depth != 4:
                specs[f"soil{depth}vwc"] = (
                    "soil_moisture",
                    "m³/m³",
                    0,
                    1,
                    lambda v: v / 100,
                    depth * 2.54,
                )
        for depth in (2, 4, 8, 12, 14, 16, 20, 24, 28, 30, 32, 36, 40, 42, 52):
            specs[f"sv_vwc{depth}"] = (
                "soil_moisture_soilvue",
                "m³/m³",
                0,
                1,
                lambda v: v,
                depth * 2.54,
            )
        rejected = 0
        for row in rows:
            if row["station"] not in {s["id"] for s in stations}:
                raise SourceError("INVALID_DATA")
            valid = timestamp(row["valid"])
            if valid > now + timedelta(minutes=2) or valid < now - timedelta(hours=2):
                continue
            for column, (variable, unit, low, high, convert, depth) in specs.items():
                key = (row["station"], variable, depth, valid.isoformat())
                station_metadata = next(
                    s for s in stations if s["id"] == row["station"]
                )
                if (
                    column == "soil04t"
                    and station_metadata["attributes"].get("NO_4INCH") == "1"
                ):
                    records.pop(key, None)
                    continue
                flag = row.get(column + "_f", "")
                raw = number(row.get(column), -200, 10000)
                value = (
                    number(convert(raw), low, high)
                    if raw is not None and raw != -99
                    else None
                )
                # Nonempty flags are conservatively withheld; never infer frozen sensors.
                if value is None or flag not in ("", "0", "0.0", "M"):
                    records.pop(key, None)
                    rejected += 1
                    continue
                records[key] = measurement(
                    variable,
                    value,
                    unit,
                    valid.isoformat(),
                    depth_cm=depth,
                    flag=flag,
                    station=row["station"],
                    interval_seconds=None,
                )
                records[key].update(
                    source_column=column,
                    original_value=raw,
                    original_unit="°F"
                    if variable in ("air_temperature", "soil_temperature")
                    else "inch"
                    if column == "precip"
                    else "mph"
                    if column == "speed"
                    else "%"
                    if column.endswith("vwc") or column == "relh"
                    else unit,
                    nominal_table_resolution_seconds=60,
                    quality_status="Provider QC value; no additional flag supplied"
                    if flag in ("", "M")
                    else "Provider QC value; zero flag",
                )
        accepted = sorted(records.values(), key=lambda r: r["observed_at"])[-2880:]
        if not accepted:
            raise SourceError("SCIENTIFIC_QA_REJECTION")
        # Latest per sensor, retain individual times rather than relabeling old sensors.
        latest = {}
        for record in accepted:
            latest[(record["station_id"], record["variable"], record["depth_cm"])] = (
                record
            )
        return {
            "records": accepted,
            "measurements": sorted(
                latest.values(),
                key=lambda r: (
                    next(
                        i for i, s in enumerate(stations) if s["id"] == r["station_id"]
                    ),
                    {
                        "air_temperature": 0,
                        "rainfall": 1,
                        "relative_humidity": 2,
                        "wind_speed": 3,
                        "wind_direction": 4,
                    }.get(r["variable"], 5),
                    r["depth_cm"] or 0,
                ),
            ),
            "stations": stations,
            "observed_at": max(r["observed_at"] for r in accepted),
            "publication_at": None,
            "resolution": "Station point; nominal 1 minute (some stations report 5 minutes)",
            "rejected_or_missing_cells": rejected,
            "next_check": receipt["next_check"],
            "checked_at": receipt["retrieved_at"],
            "provenance": [provenance(meta_receipt), provenance(receipt)],
        }


class NwsForecast:
    kind = "OFFICIAL_FORECAST"
    interval = 900
    stale_after = 7200
    limitations = "Official forecast, not an observed measurement. Precipitation probability is not rainfall amount. Grid support differs from field boundaries."

    def __init__(self, http):
        self.http = http

    async def fetch(self, location, old, now):
        point, receipt = await self.http.json(
            f"{NWS}/points/{location['lat']:.4f},{location['lon']:.4f}", ttl=86400
        )
        p = point.get("properties", {})
        if not p.get("forecast") or not p.get("forecastHourly"):
            raise SourceError("GEOGRAPHIC_NON_COVERAGE")
        daily, dr = await self.http.json(p["forecast"], ttl=900)
        hourly, hr = await self.http.json(p["forecastHourly"], ttl=900)
        output = {"daily": [], "hourly": []}
        for name, data in (("daily", daily), ("hourly", hourly)):
            for period in data.get("properties", {}).get("periods", [])[:168]:
                start, end = (
                    timestamp(period["startTime"]),
                    timestamp(period["endTime"]),
                )
                if end <= start:
                    raise SourceError("INVALID_DATA")
                if end <= now or start > now + timedelta(days=7):
                    continue
                value = number(period.get("temperature"), -150, 150)
                unit = period.get("temperatureUnit")
                if value is None or unit not in ("F", "C"):
                    raise SourceError("INVALID_DATA")
                output[name].append(
                    {
                        "start": start.isoformat(),
                        "end": end.isoformat(),
                        "name": period.get("name"),
                        "temperature_c": (value - 32) * 5 / 9 if unit == "F" else value,
                        "original_temperature": value,
                        "original_temperature_unit": unit,
                        "precipitation_probability_pct": number(
                            (period.get("probabilityOfPrecipitation") or {}).get(
                                "value"
                            ),
                            0,
                            100,
                        ),
                        "relative_humidity_pct": number(
                            (period.get("relativeHumidity") or {}).get("value"), 0, 100
                        ),
                        "wind": period.get("windSpeed"),
                        "wind_direction": period.get("windDirection"),
                        "summary": period.get("shortForecast"),
                        "description": period.get("detailedForecast"),
                    }
                )
        if not output["daily"] or not output["hourly"]:
            raise SourceError("EXPIRED_DATA")
        return {
            **output,
            "issued_at": daily["properties"].get("generatedAt"),
            "updated_at": daily["properties"].get("updateTime"),
            "valid_until": max(r["end"] for r in output["hourly"]),
            "office": p.get("forecastOffice"),
            "grid_id": p.get("gridId"),
            "grid_x": p.get("gridX"),
            "grid_y": p.get("gridY"),
            "grid_data_url": p.get("forecastGridData"),
            "observation_stations_url": p.get("observationStations"),
            "forecast_zone": p.get("forecastZone"),
            "timezone": p.get("timeZone"),
            "publication_at": None,
            "resolution": "NWS forecast grid",
            "next_check": max(dr["next_check"], hr["next_check"]),
            "checked_at": min(dr["retrieved_at"], hr["retrieved_at"]),
            "provenance": [provenance(r) for r in (receipt, dr, hr)],
        }


class NwsAlerts:
    kind = "OFFICIAL_CURRENT_ALERT"
    interval = 60
    stale_after = 180
    limitations = "Only official NWS coverage. An unsuccessful or stale check cannot establish an all-clear. Expired messages are retained separately from active messages."

    def __init__(self, http):
        self.http = http

    async def fetch(self, location, old, now):
        if location.get("country") != "US":
            raise SourceError("GEOGRAPHIC_NON_COVERAGE")
        data, receipt = await self.http.json(
            f"{NWS}/alerts/active?point={location['lat']:.4f},{location['lon']:.4f}",
            ttl=60,
        )
        if data.get("type") != "FeatureCollection" or not isinstance(
            data.get("features"), list
        ):
            raise SourceError("INVALID_DATA")
        if len(data["features"]) > 200:
            raise SourceError("ALERT_RESPONSE_LIMIT")
        active, expired = [], []
        superseded = set()
        for feature in data["features"][:200]:
            p = feature["properties"]
            if not p.get("id") or not p.get("expires"):
                raise SourceError("INVALID_DATA")
            if p.get("status") not in {
                "Actual",
                "Exercise",
                "System",
                "Test",
                "Draft",
            } or p.get("messageType") not in {
                "Alert",
                "Update",
                "Cancel",
                "Ack",
                "Error",
            }:
                raise SourceError("INVALID_DATA")
            if p["messageType"] in ("Update", "Cancel"):
                for ref in p.get("references") or []:
                    superseded.update(
                        v for v in (ref.get("identifier"), ref.get("@id")) if v
                    )
            expiry = timestamp(p["expires"])
            if p.get("ends"):
                expiry = min(expiry, timestamp(p["ends"]))
            alert = {
                k: p.get(k)
                for k in (
                    "id",
                    "sender",
                    "senderName",
                    "event",
                    "severity",
                    "urgency",
                    "certainty",
                    "sent",
                    "effective",
                    "onset",
                    "expires",
                    "ends",
                    "headline",
                    "description",
                    "instruction",
                    "areaDesc",
                    "affectedZones",
                    "status",
                    "messageType",
                    "references",
                    "web",
                )
            }
            alert["source_url"] = feature.get("id") or p["id"]
            (
                expired
                if expiry <= now
                or p.get("messageType") not in ("Alert", "Update")
                or p.get("status") != "Actual"
                else active
            ).append(alert)
        for alert in active[:]:
            if alert["id"] in superseded or alert["source_url"] in superseded:
                active.remove(alert)
                expired.append({**alert, "superseded_in_feed": True})
        return {
            "alerts": active,
            "expired_or_cancelled": expired,
            "publication_at": None,
            "resolution": "Official affected areas",
            "next_check": receipt["next_check"],
            "provenance": [provenance(receipt)],
        }


class OpenMeteo:
    kind = "MODEL_FORECAST"
    interval = 1800
    stale_after = 7200
    limitations = "Open-Meteo CC BY 4.0; free API is for non-commercial use within published quotas. Automatic model blend; model initialization/publication times are unknown in this response. Soil moisture is modeled. Models may overlap NOAA; this is not independent station evidence."

    def __init__(self, http):
        self.http = http

    async def fetch(self, location, old, now):
        variables = "temperature_2m,relative_humidity_2m,precipitation,precipitation_probability,wind_speed_10m,soil_moisture_0_to_1cm"
        url = "https://api.open-meteo.com/v1/forecast?" + urlencode(
            {
                "latitude": location["lat"],
                "longitude": location["lon"],
                "hourly": variables,
                "forecast_days": 7,
                "timezone": "UTC",
                "timeformat": "unixtime",
                "wind_speed_unit": "ms",
            }
        )
        data, receipt = await self.http.json(url, ttl=1800)
        hourly, units = data.get("hourly", {}), data.get("hourly_units", {})
        expected = {
            "temperature_2m": "°C",
            "relative_humidity_2m": "%",
            "precipitation": "mm",
            "precipitation_probability": "%",
            "wind_speed_10m": "m/s",
            "soil_moisture_0_to_1cm": "m³/m³",
        }
        for key, unit in expected.items():
            if units.get(key) != unit or len(hourly.get(key, [])) != len(
                hourly.get("time", [])
            ):
                raise SourceError("INVALID_UNITS_OR_DATA")
        rows = []
        for i, epoch in enumerate(hourly.get("time", [])[:168]):
            valid = datetime.fromtimestamp(epoch, UTC)
            if valid + timedelta(hours=1) <= now:
                continue
            row = {
                key: number(
                    hourly[key][i],
                    -90 if key == "temperature_2m" else 0,
                    1
                    if "soil_moisture" in key
                    else 1000
                    if key == "precipitation"
                    else 100,
                )
                for key in expected
            }
            rows.append(
                {
                    "start": valid.isoformat(),
                    "end": (valid + timedelta(hours=1)).isoformat(),
                    "precipitation_interval_start": (
                        valid - timedelta(hours=1)
                    ).isoformat(),
                    "precipitation_interval_end": valid.isoformat(),
                    **row,
                }
            )
        if not rows or not any(r["temperature_2m"] is not None for r in rows):
            raise SourceError("EMPTY_RESPONSE")
        return {
            "hourly": rows,
            "units": units,
            "valid_until": rows[-1]["end"],
            "model": "Open-Meteo automatic model selection (underlying model not identified by response)",
            "model_initialization_at": None,
            "publication_at": None,
            "grid_point": {
                "lat": data.get("latitude"),
                "lon": data.get("longitude"),
                "elevation_m": data.get("elevation"),
            },
            "resolution": "Model-dependent; hourly output is not model update cadence",
            "next_check": receipt["next_check"],
            "provenance": [provenance(receipt)],
        }


def local_time(value, zone):
    return timestamp(value).astimezone(ZoneInfo(zone)).isoformat() if value else None
