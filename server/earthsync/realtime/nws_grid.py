"""NWS native forecast intervals; precipitation amounts are never interpolated."""

import re
from datetime import timedelta

from .http import SourceError
from .providers import NWS, number, provenance, timestamp


def interval(value):
    start, duration = value.split("/", 1)
    match = re.fullmatch(
        r"P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", duration
    )
    if not match:
        raise SourceError("INVALID_FORECAST_INTERVAL")
    days, hours, minutes, seconds = [int(v or 0) for v in match.groups()]
    begin = timestamp(start)
    end = begin + timedelta(days=days, hours=hours, minutes=minutes, seconds=seconds)
    if end <= begin or end - begin > timedelta(days=10):
        raise SourceError("INVALID_FORECAST_INTERVAL")
    return begin, end


class NwsGrid:
    kind = "OFFICIAL_FORECAST"
    interval = 900
    stale_after = 7200
    limitations = "NWS grid precipitation is the total over each original validity interval, not an hourly amount or a rain gauge observation. No hourly redistribution, crop thresholds or irrigation prescription."

    def __init__(self, http):
        self.http = http

    async def fetch(self, location, old, now):
        point, _ = await self.http.json(
            f"{NWS}/points/{location['lat']:.4f},{location['lon']:.4f}", ttl=86400
        )
        url = point.get("properties", {}).get("forecastGridData")
        if not url:
            raise SourceError("GEOGRAPHIC_NON_COVERAGE")
        raw, receipt = await self.http.json(url, ttl=900)
        props = raw["properties"]
        variables = {}
        for name, unit, low, high in (
            ("quantitativePrecipitation", "wmoUnit:mm", 0, 3000),
            ("relativeHumidity", "wmoUnit:percent", 0, 100),
            ("windSpeed", "wmoUnit:km_h-1", 0, 500),
        ):
            data = props.get(name, {})
            if data.get("uom") != unit:
                raise SourceError("INVALID_UNITS_OR_DATA")
            records = []
            for row in data.get("values", [])[:300]:
                start, end = interval(row["validTime"])
                if end <= now:
                    continue
                records.append(
                    {
                        "start": start.isoformat(),
                        "end": end.isoformat(),
                        "value": number(row.get("value"), low, high),
                        "unit": unit,
                        "original_valid_time": row["validTime"],
                    }
                )
            variables[name] = records
        if not variables["quantitativePrecipitation"]:
            raise SourceError("EXPIRED_DATA")
        return {
            "variables": variables,
            "updated_at": props.get("updateTime"),
            "office": point["properties"].get("forecastOffice"),
            "valid_until": max(
                row["end"] for row in variables["quantitativePrecipitation"]
            ),
            "resolution": "NWS forecast grid; original variable-specific validity intervals",
            "publication_at": None,
            "checked_at": receipt["retrieved_at"],
            "next_check": receipt["next_check"],
            "provenance": [provenance(receipt)],
        }
