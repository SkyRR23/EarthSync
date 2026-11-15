"""5-day weather forecast for EarthSync's Weather screen (Open-Meteo).

A model forecast, not a measurement: the response says so. Phones reach it
through this backend (the web.app address), never the provider directly.
Units are checked and the request fails closed if they change.
"""

from __future__ import annotations

import asyncio
import json
import math
import time
from collections import OrderedDict
from datetime import datetime, timezone
from typing import Optional, Protocol

import httpx
from fastapi import APIRouter, Query, Request

from .power import ProviderError

ENDPOINT = "https://api.open-meteo.com/v1/forecast"
CURRENT = (
    "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,precipitation"
)
DAILY = "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max"
UNITS = {
    "temperature_2m": "°C",
    "apparent_temperature": "°C",
    "wind_speed_10m": "km/h",
    "precipitation": "mm",
}
DAILY_UNITS = {
    "temperature_2m_max": "°C",
    "temperature_2m_min": "°C",
    "precipitation_sum": "mm",
    "precipitation_probability_max": "%",
}

router = APIRouter()


class ForecastProvider(Protocol):
    async def forecast(self, latitude: float, longitude: float) -> dict: ...


class OpenMeteoProvider:
    def __init__(self, client: httpx.AsyncClient, sleep=asyncio.sleep):
        self.client, self.sleep = client, sleep

    async def forecast(self, latitude, longitude):
        params = {
            "latitude": latitude,
            "longitude": longitude,
            "current": CURRENT,
            "daily": DAILY,
            "timezone": "auto",
            "forecast_days": 5,
        }
        error = ProviderError("UPSTREAM_UNAVAILABLE", True)
        for attempt in range(3):
            try:
                r = await self.client.get(ENDPOINT, params=params)
                if r.status_code in (429, 500, 502, 503, 504):
                    raise ProviderError("UPSTREAM_UNAVAILABLE", True)
                if r.status_code != 200 or len(r.content) > 1_000_000:
                    raise ProviderError("UPSTREAM_REJECTED")
                payload = json.loads(r.content)
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


def _num(v) -> Optional[float]:
    return float(v) if type(v) in (int, float) and math.isfinite(v) else None


def normalize(payload: dict) -> dict:
    try:
        cu, du = payload["current_units"], payload["daily_units"]
        if any(cu.get(k) != u for k, u in UNITS.items()) or any(
            du.get(k) != u for k, u in DAILY_UNITS.items()
        ):
            raise ProviderError("UPSTREAM_UNITS_CHANGED")
        c, d = payload["current"], payload["daily"]
        code = c.get("weather_code")
        current = {
            "time": c["time"],
            "temp_c": _num(c.get("temperature_2m")),
            "feels_like_c": _num(c.get("apparent_temperature")),
            "weather_code": code if type(code) is int else None,
            "wind_kmh": _num(c.get("wind_speed_10m")),
            "rain_mm": _num(c.get("precipitation")),
        }
        days = []
        for i, day in enumerate(d["time"]):
            code = d["weather_code"][i]
            chance = _num(d["precipitation_probability_max"][i])
            days.append(
                {
                    "date": day,
                    "weather_code": code if type(code) is int else None,
                    "max_c": _num(d["temperature_2m_max"][i]),
                    "min_c": _num(d["temperature_2m_min"][i]),
                    "rain_mm": _num(d["precipitation_sum"][i]),
                    "rain_chance": None if chance is None else round(chance),
                }
            )
        return {
            "current": current,
            "days": days,
            "timezone": payload.get("timezone"),
        }
    except (KeyError, TypeError, IndexError, AttributeError) as exc:
        raise ProviderError() from exc


class ForecastCache:
    """Per-process cache: forecasts change hourly at most."""

    def __init__(self, ttl=1800, capacity=256, clock=time.monotonic):
        self.ttl, self.capacity, self.clock = ttl, capacity, clock
        self.entries: OrderedDict = OrderedDict()
        self.lock = asyncio.Lock()

    async def get(self, key, make):
        async with self.lock:
            hit = self.entries.get(key)
            if hit and hit[0] > self.clock():
                return {**hit[1], "cache": {"hit": True, "ttl_seconds": self.ttl}}
            value = await make()
            self.entries[key] = (self.clock() + self.ttl, value)
            while len(self.entries) > self.capacity:
                self.entries.popitem(last=False)
            return {**value, "cache": {"hit": False, "ttl_seconds": self.ttl}}


@router.get("/api/v1/environment/forecast")
async def forecast(
    request: Request,
    latitude: float = Query(ge=-90, le=90, allow_inf_nan=False),
    longitude: float = Query(ge=-180, le=180, allow_inf_nan=False),
):
    provider: ForecastProvider = request.app.state.forecast_provider
    cache: ForecastCache = request.app.state.forecast_cache

    async def make():
        data = normalize(await provider.forecast(latitude, longitude))
        return {
            "status": "success",
            **data,
            "provenance": {
                "provider": "Open-Meteo",
                "data_kind": "forecast",
                "note": "Model forecast for about 10 km around the point; not a local sensor reading.",
                "license": "CC BY 4.0, https://open-meteo.com/",
                "retrieved_at": datetime.now(timezone.utc).isoformat(),
            },
        }

    return await cache.get((round(latitude, 3), round(longitude, 3)), make)
