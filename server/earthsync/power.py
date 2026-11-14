"""NASA POWER daily point transport and conservative full-month normalization."""

import asyncio
import json
import math
from calendar import monthrange
from datetime import date, datetime, timezone
from typing import Protocol

import httpx

from .models import (
    Environment,
    Observation,
    SeasonQuery,
    SeasonResponse,
    SeasonalRequest,
    Window,
    YearMonth,
)

ENDPOINT = "https://power.larc.nasa.gov/api/temporal/daily/point"
DOCS = [
    "https://power.larc.nasa.gov/docs/services/api/temporal/daily/",
    "https://power.larc.nasa.gov/docs/methodology/data/sources_meteorology/",
]


class ProviderError(Exception):
    def __init__(self, code="UPSTREAM_INVALID_RESPONSE", retryable=False):
        self.code = code
        self.retryable = retryable


class ClimateProvider(Protocol):
    async def season(self, query: SeasonQuery) -> SeasonResponse: ...


class PowerProvider:
    def __init__(self, client: httpx.AsyncClient, sleep=asyncio.sleep):
        self.client = client
        self.sleep = sleep

    async def fetch(self, query, start, end):
        params = {
            "parameters": "T2M,PRECTOTCORR",
            "community": "AG",
            "latitude": query.latitude,
            "longitude": query.longitude,
            "start": start.strftime("%Y%m%d"),
            "end": end.strftime("%Y%m%d"),
            "format": "JSON",
            "time-standard": "LST",
        }
        for attempt in range(3):
            try:
                async with self.client.stream(
                    "GET", ENDPOINT, params=params
                ) as response:
                    if response.status_code in (429, 500, 502, 503, 504):
                        raise ProviderError("UPSTREAM_UNAVAILABLE", True)
                    if response.status_code != 200:
                        raise ProviderError("UPSTREAM_REJECTED")
                    content = bytearray()
                    async for chunk in response.aiter_bytes():
                        content.extend(chunk)
                        if len(content) > 4_000_000:
                            raise ProviderError()
                    payload = json.loads(content)
                    if not isinstance(payload, dict):
                        raise ProviderError()
                    return payload, params, datetime.now(timezone.utc).isoformat()
            except httpx.TimeoutException:
                error = ProviderError("UPSTREAM_TIMEOUT", True)
            except httpx.TransportError:
                error = ProviderError("UPSTREAM_NETWORK_UNAVAILABLE", True)
            except ProviderError as exc:
                if not exc.retryable:
                    raise
                error = exc
            except (ValueError, UnicodeError, RecursionError) as exc:
                raise ProviderError() from exc
            if attempt == 2:
                raise error
            await self.sleep(0.25 * 2**attempt)

    async def season(self, query):
        # Bound the whole multi-year operation, including retries and body streaming.
        # Individual HTTP timeouts alone reset for every read and annual request.
        try:
            async with asyncio.timeout(70):
                return await self._season(query)
        except TimeoutError:
            raise ProviderError("UPSTREAM_TIMEOUT", True) from None

    async def _season(self, query):
        daily = {"T2M": {}, "PRECTOTCORR": {}}
        sources = []
        for year in range(query.start_year, query.end_year + 1):
            start = max(query.start, date(year, 1, 1))
            end = min(query.end, date(year, 12, 31))
            payload, params, retrieved = await self.fetch(query, start, end)
            try:
                units = {key: payload["parameters"][key]["units"] for key in daily}
                # Fail closed rather than guessing a conversion after provider drift.
                if units != {"T2M": "C", "PRECTOTCORR": "mm/day"}:
                    raise ProviderError("UPSTREAM_UNITS_CHANGED")
                header = payload["header"]
                fill = header["fill_value"]
                if type(fill) not in (int, float) or not math.isfinite(fill):
                    raise ProviderError()
                if header.get("time_standard") != "LST":
                    raise ProviderError("UPSTREAM_TIME_STANDARD_CHANGED")
                # Recent POWER records can include GEOS-IT. This P0 adapter claims
                # one MERRA-2 series; reject mixed/changed lineage instead of mislabeling.
                if header.get("sources") != ["MERRA2"]:
                    raise ProviderError("UPSTREAM_SOURCE_CHANGED")
                if (
                    header.get("start") != params["start"]
                    or header.get("end") != params["end"]
                ):
                    raise ProviderError("UPSTREAM_INTERVAL_CHANGED")
                for key in daily:
                    values = payload["properties"]["parameter"][key]
                    if not isinstance(values, dict):
                        raise ProviderError()
                    # Retain invalid/missing daily values as unknown; never use fill as rain.
                    for day, value in values.items():
                        if start.strftime("%Y%m%d") <= day <= end.strftime("%Y%m%d"):
                            valid = (
                                type(value) in (int, float)
                                and math.isfinite(value)
                                and value != fill
                                and (key != "PRECTOTCORR" or value >= 0)
                            )
                            daily[key][day] = value if valid else None
                sources.append(
                    {
                        "endpoint": ENDPOINT,
                        "query": params,
                        "retrieved_at": retrieved,
                        "header": header,
                        "parameters": payload["parameters"],
                        "source_geometry": payload.get("geometry"),
                        "source_messages": payload.get("messages", []),
                    }
                )
            except (KeyError, TypeError, AttributeError) as exc:
                raise ProviderError() from exc
        observations, coverage = [], []
        for year, month in query.months():
            count = monthrange(year, month)[1]
            keys = [f"{year:04}{month:02}{day:02}" for day in range(1, count + 1)]
            missing = {
                var: [key for key in keys if daily[var].get(key) is None]
                for var in daily
            }
            try:
                rain = (
                    None
                    if missing["PRECTOTCORR"]
                    else math.fsum(daily["PRECTOTCORR"][key] for key in keys)
                )
                temp = (
                    None
                    if missing["T2M"]
                    else math.fsum(daily["T2M"][key] / count for key in keys)
                )
            except OverflowError as exc:
                raise ProviderError() from exc
            if any(
                value is not None and not math.isfinite(value) for value in (rain, temp)
            ):
                raise ProviderError()
            period = YearMonth(year=year, month=month)
            observations.append(
                Observation(
                    period=period,
                    rainfall_mm=rain,
                    mean_temperature_c=temp,
                    rainfall_complete=rain is not None,
                    temperature_complete=temp is not None,
                )
            )
            coverage.append(
                {
                    "period": period.model_dump(),
                    "expected_days": count,
                    "missing_or_invalid_dates": missing,
                    "reason": "Complete only when every calendar day has a finite valid value; no gap filling.",
                }
            )
        return SeasonResponse(
            environment=Environment(
                latitude=query.latitude,
                longitude=query.longitude,
                seasonal=SeasonalRequest(
                    window=Window(
                        start=YearMonth(year=query.start_year, month=query.start_month),
                        end=YearMonth(year=query.end_year, month=query.end_month),
                    ),
                    observations=observations,
                ),
            ),
            provenance={
                "provider": "NASA POWER",
                "product": "Daily point meteorology / MERRA-2",
                "data_kind": "modeled",
                "query_coordinates": {
                    "latitude": query.latitude,
                    "longitude": query.longitude,
                },
                "interval": {
                    "start": query.start.isoformat(),
                    "end": query.end.isoformat(),
                },
                "time_standard": "LST",
                "original_units": {"T2M": "C", "PRECTOTCORR": "mm/day"},
                "normalized_units": {
                    "mean_temperature_c": "deg_c",
                    "rainfall_mm": "mm",
                },
                "spatial_support": "Gridded meteorology, nominal MERRA-2 0.5 degree latitude x 0.625 degree longitude; query point is not a farm measurement or grid centroid.",
                "aggregation": "Sum daily PRECTOTCORR rates multiplied by one day; arithmetic mean of daily T2M means over all calendar days in LST.",
                "coverage": coverage,
                "source_requests": sources,
                "documentation": DOCS,
                "limitations": [
                    "Model/reanalysis context, not direct farm observations or crop suitability.",
                    "Completeness means daily record coverage, not independently verified scientific quality.",
                    "Retain this envelope beside Rust inputs: the Rust schema cannot carry all provenance.",
                ],
            },
            cache={"hit": False, "ttl_seconds": 3600},
        )
