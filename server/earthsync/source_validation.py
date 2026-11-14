"""Conservative validation at the NASA response boundary, before aggregation."""

import math
from datetime import timedelta

# Reviewed POWER v2.10.3 captures serialize coordinates to three decimal places.
# Allow only half of that quantization step, plus floating-point roundoff;
# this is response-point association, never proof of a native grid footprint.
POWER_POINT_TOLERANCE_DEGREES = 0.0005 + 1e-12


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
        and -180 <= coordinates[0] <= 180
        and -90 <= coordinates[1] <= 90
        and abs(coordinates[0] - longitude) <= POWER_POINT_TOLERANCE_DEGREES
        and abs(coordinates[1] - latitude) <= POWER_POINT_TOLERANCE_DEGREES
    )


def daily_keys(start, end):
    return {
        (start + timedelta(days=i)).strftime("%Y%m%d")
        for i in range((end - start).days + 1)
    }
