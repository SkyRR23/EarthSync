"""Conservative validation at the NASA response boundary, before aggregation."""

import math
from datetime import timedelta


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate provider JSON key")
        result[key] = value
    return result


def matches_point(geometry, latitude, longitude):
    if not isinstance(geometry, dict) or geometry.get("type") != "Point":
        return False
    coordinates = geometry.get("coordinates")
    return (
        isinstance(coordinates, list)
        and len(coordinates) in (2, 3)
        and all(type(v) in (int, float) and math.isfinite(v) for v in coordinates)
        and abs(coordinates[0] - longitude) <= 1e-6
        and abs(coordinates[1] - latitude) <= 1e-6
    )


def daily_keys(start, end):
    return {
        (start + timedelta(days=i)).strftime("%Y%m%d")
        for i in range((end - start).days + 1)
    }
