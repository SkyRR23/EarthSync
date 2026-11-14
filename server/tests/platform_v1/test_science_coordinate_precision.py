"""NASA point serialization checks; not field accuracy or crop advice."""

import pytest

from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.providers.power_daily import read_daily

from conftest import captured


def test_power_point_serialization_preserves_high_precision_queries(query):
    # Captured response point is [-93.62, 42.03]; model query precision must
    # tolerate its documented-in-the-audit three-decimal serialization.
    query.point.latitude = 42.030234
    query.point.longitude = -93.620234
    record = read_daily(captured("T2M_MIN"), query, "T2M_MIN")
    assert record.spatial.query_point == query.point
    assert record.spatial.original_geometry["coordinates"][:2] == [-93.62, 42.03]


def test_neighboring_returned_point_is_not_rounding(query):
    query.point.latitude = 42.031
    with pytest.raises(PlatformError, match="SPATIAL_MISMATCH"):
        read_daily(captured("T2M_MIN"), query, "T2M_MIN")


def test_serialization_tolerance_does_not_accept_out_of_domain_response(query):
    import json
    from earthsync.platform_v1.providers.transport import Capture

    original = captured("T2M_MIN")
    data = json.loads(original.body)
    data["geometry"]["coordinates"] = [180.0001, 90, 0]
    query.point.latitude = 90
    query.point.longitude = 180
    changed = Capture(
        json.dumps(data).encode(), original.retrieved_at, original.headers
    )
    with pytest.raises(PlatformError, match="SPATIAL_MISMATCH"):
        read_daily(changed, query, "T2M_MIN")
