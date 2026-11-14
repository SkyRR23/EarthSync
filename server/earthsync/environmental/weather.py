"""Open-Meteo current/forecast probe with explicit identity and freshness gates."""

import math
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from .common import (
    SourceCache,
    SourceError,
    fetch,
    number,
    quality,
    unavailable,
    utcnow,
)
from .models import Evidence, Point, Source, SpatialSupport, TemporalSupport, Value

ENDPOINT = "https://api.open-meteo.com/v1/forecast"
MODEL = "gfs_global"
SOURCE = Source(
    provider="Open-Meteo / NOAA",
    dataset="Open-Meteo current conditions and daily forecast",
    api_version="v1",
    model=MODEL,
    model_identity_basis="Explicit request selector; run/initialization not supplied by generic endpoint.",
    documentation=[
        "https://open-meteo.com/en/docs",
        "https://open-meteo.com/en/docs/gfs-api",
        "https://open-meteo.com/en/terms",
    ],
    license="CC BY 4.0; free API access is noncommercial only",
    attribution="Weather data by Open-Meteo, underlying GFS model by NOAA.",
)
CURRENT = {"temperature_2m": "°C", "relative_humidity_2m": "%"}
DAILY = {
    "temperature_2m_min": "°C",
    "temperature_2m_max": "°C",
    "precipitation_sum": "mm",
}


@dataclass(frozen=True)
class FreshnessPolicy:
    # Application verification policy, not a forecast-skill or safety claim.
    policy_id: str = "weather-probe/1; retrieval<1h; issue<12h; valid-horizon"
    retrieval_age: timedelta = timedelta(hours=1)
    issue_age: timedelta = timedelta(hours=12)

    def assess(self, retrieved, issue, valid_end, as_of):
        if retrieved is None or retrieved > as_of or (issue and issue > retrieved):
            return "unknown", None, "INVALID_RETRIEVAL_OR_ISSUE_TIME"
        deadline = min(retrieved + self.retrieval_age, valid_end)
        if issue is not None:
            deadline = min(deadline, issue + self.issue_age)
        if as_of >= deadline:
            return "stale", deadline, "STALE_FORECAST"
        if issue is None:
            return "unknown", None, "ISSUE_TIME_UNAVAILABLE"
        return "fresh", deadline, None


def distance_m(a, b):
    lat1, lat2 = math.radians(a.latitude), math.radians(b.latitude)
    dlat = lat2 - lat1
    dlon = math.radians(b.longitude - a.longitude)
    h = (
        math.sin(dlat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    )
    return 2 * 6371008.8 * math.asin(min(1, math.sqrt(h)))


def weather_value(variable, raw, unit, start, end, *, current=False, absent=False):
    valid = number(raw)
    if valid and variable == "relative_humidity_2m":
        valid = 0 <= raw <= 100
    if valid and variable == "precipitation_sum":
        valid = raw >= 0
    return Value(
        variable=variable,
        data_kind="modeled" if current else "forecast",
        statistic="instant"
        if current
        else "daily_sum"
        if variable == "precipitation_sum"
        else "daily_min"
        if variable.endswith("_min")
        else "daily_max",
        start=start,
        end=end,
        original_value=raw if number(raw) else None,
        original_unit=None if absent else unit,
        value=raw if valid else None,
        unit=unit,
        scale=1,
        quality="present" if valid else "missing" if raw is None else "rejected",
        reason=None
        if valid
        else "ABSENT_VARIABLE"
        if absent
        else "NULL_VALUE"
        if raw is None
        else "INVALID_VALUE",
    )


def read_weather(capture, query, as_of, policy=FreshnessPolicy()):
    payload = capture.json()
    try:
        returned = Point(latitude=payload["latitude"], longitude=payload["longitude"])
        # Deliberately loose association guard for the documented ~13 km GFS grid.
        # It is not a verified native footprint or evidence of field representativeness.
        if distance_m(query.point, returned) > 50_000:
            raise SourceError("SPATIAL_MISMATCH")
        if payload["timezone"] != query.timezone:
            raise SourceError("TIMEZONE_MISMATCH")
        offset = payload["utc_offset_seconds"]
        retrieved = capture.retrieval.retrieved_at
        zone = ZoneInfo(query.timezone)
        if (
            type(offset) is not int
            or retrieved is None
            or offset != int(retrieved.astimezone(zone).utcoffset().total_seconds())
        ):
            raise SourceError("TIMEZONE_MISMATCH")
        # Provider ISO daily boundaries use a fixed returned offset across DST.
        # Never silently reinterpret these as DST-aware local midnights.
        fixed_zone = timezone(timedelta(seconds=offset))
        daily = payload.get("daily", {})
        daily_units = payload.get("daily_units", {})
        dates = daily.get("time", [])
        if not isinstance(dates, list) or len(dates) != 3:
            raise SourceError("INTERVAL_MISMATCH")
        starts = [
            datetime.strptime(d, "%Y-%m-%d")
            .replace(tzinfo=fixed_zone)
            .astimezone(timezone.utc)
            for d in dates
        ]
        expected_date = retrieved.astimezone(fixed_zone).date()
        if starts[0].astimezone(fixed_zone).date() != expected_date or any(
            b - a != timedelta(days=1) for a, b in zip(starts, starts[1:])
        ):
            raise SourceError("INTERVAL_MISMATCH")
        if daily_units.get("time") != "iso8601":
            raise SourceError("TIME_FORMAT_MISMATCH")
        values = []
        for variable, unit in DAILY.items():
            series = daily.get(variable)
            if series is not None and (
                not isinstance(series, list) or len(series) != len(dates)
            ):
                raise SourceError("VARIABLE_LENGTH_MISMATCH")
            if variable in daily and daily_units.get(variable) != unit:
                raise SourceError("UNIT_REVISION_MISMATCH")
            for i, start in enumerate(starts):
                values.append(
                    weather_value(
                        variable,
                        series[i] if series else None,
                        unit,
                        start,
                        start + timedelta(days=1),
                        absent=variable not in daily,
                    )
                )
        current, units = payload.get("current", {}), payload.get("current_units", {})
        if current:
            if units.get("time") != "iso8601" or units.get("interval") != "seconds":
                raise SourceError("TIME_FORMAT_MISMATCH")
            instant = (
                datetime.strptime(current["time"], "%Y-%m-%dT%H:%M")
                .replace(tzinfo=fixed_zone)
                .astimezone(timezone.utc)
            )
            interval = current["interval"]
            if (
                type(interval) is not int
                or not 0 < interval <= 3600
                or not (retrieved - timedelta(hours=1) <= instant <= retrieved)
            ):
                raise SourceError("CURRENT_TIME_MISMATCH")
        else:
            instant = None
            interval = None
        for variable, unit in CURRENT.items():
            if variable in current and units.get(variable) != unit:
                raise SourceError("UNIT_REVISION_MISMATCH")
            values.append(
                weather_value(
                    variable,
                    current.get(variable),
                    unit,
                    instant,
                    instant,
                    current=True,
                    absent=variable not in current,
                )
            )
        for i in range(3):
            low, high = values[i], values[3 + i]
            if (
                low.value is not None
                and high.value is not None
                and low.value > high.value
            ):
                for v in (low, high):
                    v.value, v.quality, v.reason = None, "rejected", "MIN_MAX_ORDER"
        # No documented issue/run timestamp in the generic response. In
        # particular, generationtime_ms is processing duration, never issue time.
        freshness, expires, reason = policy.assess(
            retrieved, None, starts[-1] + timedelta(days=1), as_of
        )
        return Evidence(
            context_kind="weather",
            availability="unavailable",
            reason=reason,
            source=SOURCE.model_copy(deep=True),
            retrieval=capture.retrieval,
            spatial_support=SpatialSupport(
                query_point=query.point,
                returned_point=returned,
                method="provider_nearest_grid_point; downscaling_disabled",
                nominal_resolution_m=13000,
            ),
            temporal_support=TemporalSupport(
                kind="weather",
                timezone=query.timezone,
                utc_offset_seconds=offset,
                current_interval_seconds=interval,
                valid_start=starts[0],
                valid_end=starts[-1] + timedelta(days=1),
                retrieved_at=retrieved,
                expires_at=expires,
                freshness_policy=policy.policy_id,
                freshness=freshness,
            ),
            values=values,
            quality=quality(
                values,
                [reason, "MODEL_RUN_UNVERIFIED", "NATIVE_FOOTPRINT_UNKNOWN"],
                "unverified",
            ),
            limitations=[
                "Current conditions are modeled; forecast dates never become observations.",
                "Model selector is explicit; generic endpoint supplies no verified initialization/run identity.",
                "Live use is unavailable without run timing and independent source verification.",
                "ISO daily periods use the provider's fixed UTC offset, including across DST changes.",
                "No farm-scale accuracy, safe forecast, flood, disease or crop advice is inferred.",
            ],
        )
    except SourceError as exc:
        exc.retrieval = capture.retrieval
        raise
    except (KeyError, TypeError, ValueError, AttributeError, OverflowError) as exc:
        raise SourceError("INVALID_RESPONSE", capture.retrieval) from exc


class WeatherAdapter:
    def __init__(self, client, *, probe=False, now=utcnow, cache=None):
        self.client, self.probe, self.now = client, probe, now
        self.policy = FreshnessPolicy()
        self.cache = cache or SourceCache(ttl=900)

    async def context(self, query):
        if not self.probe:
            return unavailable("weather", SOURCE, query.point, "LIVE_SOURCE_UNVERIFIED")
        key = (
            ENDPOINT,
            MODEL,
            self.policy.policy_id,
            query.point.latitude,
            query.point.longitude,
            query.timezone,
            tuple(CURRENT),
            tuple(DAILY),
        )

        async def load():
            params = {
                "latitude": query.point.latitude,
                "longitude": query.point.longitude,
                "timezone": query.timezone,
                "models": MODEL,
                "current": ",".join(CURRENT),
                "daily": ",".join(DAILY),
                "forecast_days": 3,
                "timeformat": "iso8601",
                "temperature_unit": "celsius",
                "precipitation_unit": "mm",
                "cell_selection": "nearest",
                "elevation": "nan",
            }
            try:
                capture = await fetch(self.client, ENDPOINT, params, self.now)
                return read_weather(capture, query, self.now(), self.policy)
            except SourceError as exc:
                return unavailable(
                    "weather", SOURCE, query.point, exc.code, exc.retrieval
                )

        return await self.cache.get(key, load, self.now)
