from datetime import timedelta

import pytest

from earthsync.environmental.common import SourceError
from earthsync.environmental.weather import FreshnessPolicy, read_weather

from conftest import NOW, capture


def test_metadata_missing_run_and_half_hour_timezone(query, weather_payload):
    result = read_weather(capture(weather_payload), query, NOW)
    assert result.availability == "unavailable"
    assert result.reason == "ISSUE_TIME_UNAVAILABLE"
    assert result.temporal_support.issue_time is None
    assert result.temporal_support.freshness == "unknown"
    assert result.temporal_support.expires_at is None
    assert (
        result.temporal_support.valid_start.isoformat() == "2026-11-13T17:30:00+00:00"
    )
    assert result.source.model == "gfs_global"
    assert result.values[-1].data_kind == "modeled"
    assert result.values[6].value == 0
    assert result.values[7].value is None
    assert result.values[7].reason == "NULL_VALUE"
    assert all(not v.usable_for_analysis for v in result.values)


def test_replay_is_stale_and_never_relabelled_observed(query, weather_payload):
    result = read_weather(capture(weather_payload), query, NOW + timedelta(hours=1))
    assert result.reason == "STALE_FORECAST"
    assert result.temporal_support.freshness == "stale"
    assert all(v.data_kind == "forecast" for v in result.values[:9])
    assert result.retrieval.retrieved_at == NOW


def test_exact_freshness_boundaries_and_missing_issue():
    policy = FreshnessPolicy()
    end = NOW + timedelta(days=1)
    assert policy.assess(NOW, NOW, end, NOW)[0] == "fresh"
    assert policy.assess(NOW, NOW, end, NOW + timedelta(hours=1))[0] == "stale"
    assert policy.assess(NOW, NOW - timedelta(hours=12), end, NOW)[0] == "stale"
    assert policy.assess(NOW, NOW, NOW, NOW)[0] == "stale"
    assert policy.assess(NOW, None, end, NOW)[0] == "unknown"
    assert policy.assess(None, None, end, NOW)[0] == "unknown"
    assert (
        policy.assess(NOW + timedelta(seconds=1), None, end, NOW)[2]
        == "INVALID_RETRIEVAL_OR_ISSUE_TIME"
    )
    assert policy.assess(NOW, NOW + timedelta(seconds=1), end, NOW)[0] == "unknown"


@pytest.mark.parametrize(
    "field,value,code",
    [
        ("latitude", 42, "SPATIAL_MISMATCH"),
        ("timezone", "UTC", "TIMEZONE_MISMATCH"),
        ("utc_offset_seconds", 0, "TIMEZONE_MISMATCH"),
    ],
)
def test_metadata_mismatch(query, weather_payload, field, value, code):
    weather_payload[field] = value
    with pytest.raises(SourceError, match=code):
        read_weather(capture(weather_payload), query, NOW)


def test_unit_revision(query, weather_payload):
    weather_payload["daily_units"]["precipitation_sum"] = "inch"
    with pytest.raises(SourceError, match="UNIT_REVISION_MISMATCH"):
        read_weather(capture(weather_payload), query, NOW)


def test_absent_variable_null_array_and_truncated_series(query, weather_payload):
    del weather_payload["daily"]["precipitation_sum"]
    result = read_weather(capture(weather_payload), query, NOW)
    assert all(
        v.value is None and v.reason == "ABSENT_VARIABLE" for v in result.values[6:9]
    )
    weather_payload["daily"]["precipitation_sum"] = None
    result = read_weather(capture(weather_payload), query, NOW)
    assert all(v.value is None for v in result.values[6:9])
    weather_payload["daily"]["temperature_2m_min"].pop()
    with pytest.raises(SourceError, match="VARIABLE_LENGTH_MISMATCH"):
        read_weather(capture(weather_payload), query, NOW)


def test_conflicting_period_and_current_metadata(query, weather_payload):
    weather_payload["daily"]["time"][1] = "2026-11-14"
    with pytest.raises(SourceError, match="INTERVAL_MISMATCH"):
        read_weather(capture(weather_payload), query, NOW)
    weather_payload["daily"]["time"][1] = "2026-11-15"
    weather_payload["current"]["interval"] = 0
    with pytest.raises(SourceError, match="CURRENT_TIME_MISMATCH"):
        read_weather(capture(weather_payload), query, NOW)


def test_invalid_values_and_reversed_extrema(query, weather_payload):
    weather_payload["daily"]["temperature_2m_min"][0] = 40
    weather_payload["daily"]["precipitation_sum"][0] = -9999
    weather_payload["current"]["relative_humidity_2m"] = 101
    result = read_weather(capture(weather_payload), query, NOW)
    assert result.values[0].reason == result.values[3].reason == "MIN_MAX_ORDER"
    assert result.values[6].quality == result.values[-1].quality == "rejected"
    assert result.values[6].value is None
