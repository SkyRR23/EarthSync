"""Recent days at a farm, for Field Shift's Today tasks (NASA POWER daily).

Rain over the last 7 days, root-zone soil wetness and the heaviest recent rain
day. Each is compared only with the same time of year at the same place over
the past years, so no agronomic threshold is invented: "less / usual / more"
are thirds of the place's own record, and "unusual" rain is a day heavier than
90% of days at this time of year. Values are modeled (reanalysis), not farm
measurements; missing days stay unknown and are never filled.
"""

from __future__ import annotations

import asyncio
import json
import math
import time
from collections import OrderedDict
from datetime import date, datetime, timedelta, timezone
from typing import Optional, Protocol

import httpx
from fastapi import APIRouter, Query, Request

from .power import DOCS, ENDPOINT, ProviderError

PAST_YEARS = 10
RAIN = "PRECTOTCORR"
WET = "GWETROOT"
UNITS = {RAIN: "mm/day", WET: "1"}

router = APIRouter()


class RecentProvider(Protocol):
    def today(self) -> date: ...

    async def daily(
        self, latitude: float, longitude: float, start: date, end: date
    ) -> dict: ...


class PowerRecentProvider:
    """One NASA POWER daily request covering the past years and recent days."""

    def __init__(self, client: httpx.AsyncClient, sleep=asyncio.sleep):
        self.client, self.sleep = client, sleep

    def today(self) -> date:
        return datetime.now(timezone.utc).date()

    async def daily(self, latitude, longitude, start, end):
        params = {
            "parameters": f"{RAIN},{WET}",
            "community": "AG",
            "latitude": latitude,
            "longitude": longitude,
            "start": start.strftime("%Y%m%d"),
            "end": end.strftime("%Y%m%d"),
            "format": "JSON",
            "time-standard": "LST",
        }
        error = ProviderError("UPSTREAM_UNAVAILABLE", True)
        for attempt in range(3):
            try:
                response = await self.client.get(ENDPOINT, params=params)
                if response.status_code in (429, 500, 502, 503, 504):
                    raise ProviderError("UPSTREAM_UNAVAILABLE", True)
                if response.status_code != 200:
                    raise ProviderError("UPSTREAM_REJECTED")
                if len(response.content) > 4_000_000:
                    raise ProviderError()
                payload = json.loads(response.content)
                if not isinstance(payload, dict):
                    raise ProviderError()
                return payload
            except (httpx.TimeoutException, httpx.TransportError):
                error = ProviderError("UPSTREAM_UNAVAILABLE", True)
            except ProviderError as exc:
                if not exc.retryable:
                    raise
                error = exc
            except (ValueError, UnicodeError) as exc:
                raise ProviderError() from exc
            if attempt < 2:
                await self.sleep(0.25 * 2**attempt)
        raise error


def _parse(payload: dict) -> tuple[dict, dict, list]:
    """Daily values by date (None when missing/invalid), plus header sources."""
    try:
        units = {k: payload["parameters"][k]["units"] for k in UNITS}
        if units != UNITS:
            raise ProviderError("UPSTREAM_UNITS_CHANGED")
        header = payload["header"]
        fill = header["fill_value"]
        if type(fill) not in (int, float) or not math.isfinite(fill):
            raise ProviderError()
        if header.get("time_standard") != "LST":
            raise ProviderError("UPSTREAM_TIME_STANDARD_CHANGED")
        out = {}
        for key in UNITS:
            values = payload["properties"]["parameter"][key]
            if not isinstance(values, dict):
                raise ProviderError()
            series = {}
            for day, v in values.items():
                ok = (
                    type(v) in (int, float)
                    and math.isfinite(v)
                    and v != fill
                    and v >= 0
                    and (key != WET or v <= 1)
                )
                series[datetime.strptime(day, "%Y%m%d").date()] = v if ok else None
            out[key] = series
        return out[RAIN], out[WET], list(header.get("sources") or [])
    except (KeyError, TypeError, AttributeError, ValueError) as exc:
        raise ProviderError() from exc


def _years_back(d: date, years: int) -> date:
    try:
        return d.replace(year=d.year - years)
    except ValueError:  # 29 Feb in a non-leap year
        return d.replace(year=d.year - years, day=28)


def _thirds(value: Optional[float], past: list[float], low: str, high: str):
    """Where value sits among the place's own past values, in thirds.

    Same rule as the app's month rain thirds: at or below the top of the
    lowest third is `low`, at or above the bottom of the highest third is
    `high`. Fewer than 6 past values is too few to compare.
    """
    if value is None or len(past) < 6:
        return "unknown"
    s = sorted(past)
    third = len(s) // 3
    if value <= s[third - 1]:
        return low
    if value >= s[len(s) - third]:
        return high
    return "usual"


def summarize(rain: dict, wet: dict, today: date) -> dict:
    # Newest day with both values (NASA POWER lags a few days).
    as_of = None
    for back in range(1, 21):
        d = today - timedelta(days=back)
        if rain.get(d) is not None and wet.get(d) is not None:
            as_of = d
            break
    result = {
        "as_of": as_of.isoformat() if as_of else None,
        "past_years": PAST_YEARS,
        "rain_7d_mm": None,
        "rain_7d_vs_past": "unknown",
        "root_wetness": None,
        "root_wetness_vs_past": "unknown",
        "heaviest_day": None,
        "days": [],
    }
    if as_of is None:
        return result

    week = [as_of - timedelta(days=i) for i in range(6, -1, -1)]
    result["days"] = [
        {"date": d.isoformat(), "rain_mm": rain.get(d), "root_wetness": wet.get(d)}
        for d in week
    ]

    def week_rain(end: date) -> Optional[float]:
        vals = [rain.get(end - timedelta(days=i)) for i in range(7)]
        return None if any(v is None for v in vals) else round(math.fsum(vals), 2)

    r7 = week_rain(as_of)
    past_r7 = [
        v
        for y in range(1, PAST_YEARS + 1)
        if (v := week_rain(_years_back(as_of, y))) is not None
    ]
    result["rain_7d_mm"] = r7
    result["rain_7d_vs_past"] = _thirds(r7, past_r7, "less", "more")

    w = wet[as_of]
    past_w = [
        v
        for y in range(1, PAST_YEARS + 1)
        for k in range(-3, 4)
        if (v := wet.get(_years_back(as_of, y) + timedelta(days=k))) is not None
    ]
    result["root_wetness"] = w
    result["root_wetness_vs_past"] = _thirds(w, past_w, "drier", "wetter")

    known = [(d, rain[d]) for d in week if rain.get(d) is not None]
    if known:
        day, mm = max(known, key=lambda t: t[1])
        past_days = [
            v
            for y in range(1, PAST_YEARS + 1)
            for k in range(-15, 16)
            if (v := rain.get(_years_back(day, y) + timedelta(days=k))) is not None
        ]
        heavier_than = (
            round(100 * sum(v < mm for v in past_days) / len(past_days))
            if len(past_days) >= 30
            else None
        )
        result["heaviest_day"] = {
            "date": day.isoformat(),
            "rain_mm": mm,
            "heavier_than_percent": heavier_than,
            "unusual": heavier_than is not None and heavier_than >= 90 and mm > 0,
        }
    return result


class RecentCache:
    """Per-process cache (NASA POWER updates daily); one lock bounds load."""

    def __init__(self, ttl=6 * 3600, capacity=256, clock=time.monotonic):
        self.ttl, self.capacity, self.clock = ttl, capacity, clock
        self.entries: OrderedDict = OrderedDict()
        self.lock = asyncio.Lock()

    async def get(self, key, make):
        async with self.lock:
            now = self.clock()
            hit = self.entries.get(key)
            if hit and hit[0] > now:
                self.entries.move_to_end(key)
                return {**hit[1], "cache": {"hit": True, "ttl_seconds": self.ttl}}
            value = await make()
            self.entries[key] = (self.clock() + self.ttl, value)
            while len(self.entries) > self.capacity:
                self.entries.popitem(last=False)
            return {**value, "cache": {"hit": False, "ttl_seconds": self.ttl}}


@router.get("/api/v1/environment/recent")
async def recent(
    request: Request,
    latitude: float = Query(ge=-90, le=90, allow_inf_nan=False),
    longitude: float = Query(ge=-180, le=180, allow_inf_nan=False),
):
    provider: RecentProvider = request.app.state.recent_provider
    cache: RecentCache = request.app.state.recent_cache
    today = provider.today()

    async def make():
        start = _years_back(today, PAST_YEARS) - timedelta(days=40)
        payload = await provider.daily(
            latitude, longitude, start, today - timedelta(days=1)
        )
        rain, wet, sources = _parse(payload)
        return {
            "status": "success",
            **summarize(rain, wet, today),
            "provenance": {
                "provider": "NASA POWER",
                "product": "Daily point: PRECTOTCORR (rain), GWETROOT (root-zone soil wetness, 0-1)",
                "sources": sources,
                "data_kind": "modeled",
                "spatial_support": "Gridded model data, about 50 km; not a farm measurement.",
                "comparison": f"Same time of year at this place over the past {PAST_YEARS} years: thirds for rain and wetness; 'unusual' rain is heavier than 90% of days within 15 days of that date.",
                "documentation": DOCS,
                "retrieved_at": datetime.now(timezone.utc).isoformat(),
            },
        }

    key = (round(latitude, 4), round(longitude, 4), today.isoformat())
    return await cache.get(key, make)
