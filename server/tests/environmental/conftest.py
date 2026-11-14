"""Synthetic provider-shaped software fixtures, never scientific validation."""

import hashlib
import json
from datetime import datetime, timezone

import pytest

from earthsync.environmental.common import Capture
from earthsync.environmental.models import ContextQuery, Retrieval
from earthsync.environmental.soil import PROPERTIES

NOW = datetime(2026, 11, 14, 6, 0, tzinfo=timezone.utc)


@pytest.fixture
def query():
    return ContextQuery.model_validate(
        {
            "schema_version": "environmental-context/1.0-proposal",
            "target": {
                "kind": "confirmed_farm",
                "field_id": "test-field",
                "farmer_confirmed": True,
                "point": {"latitude": 16.87, "longitude": 96.20},
            },
            "timezone": "Asia/Yangon",
        }
    )


@pytest.fixture
def soil_payload(query):
    examples = {
        "phh2o": 63,
        "clay": 334,
        "sand": 201,
        "silt": 465,
        "soc": 120,
        "nitrogen": 274,
        "cec": 155,
        "bdod": 126,
    }
    targets = {
        "phh2o": "pH",
        "clay": "%",
        "sand": "%",
        "silt": "%",
        "soc": "g/kg",
        "nitrogen": "g/kg",
        "cec": "cmol(c)/kg",
        "bdod": "kg/dm³",
    }
    return {
        "type": "Feature",
        "geometry": {
            "type": "Point",
            "coordinates": [query.point.longitude, query.point.latitude],
        },
        "properties": {
            "layers": [
                {
                    "name": name,
                    "unit_measure": {
                        "mapped_units": unit,
                        "target_units": targets[name],
                        "d_factor": divisor,
                    },
                    "depths": [
                        {
                            "label": "0-5cm",
                            "range": {
                                "top_depth": 0,
                                "bottom_depth": 5,
                                "unit_depth": "cm",
                            },
                            "values": {
                                "mean": examples[name],
                                "Q0.05": 0,
                                "Q0.5": examples[name],
                                "Q0.95": examples[name] + 1,
                            },
                        }
                    ],
                }
                for name, (unit, divisor, _) in PROPERTIES.items()
            ]
        },
    }


@pytest.fixture
def weather_payload(query):
    return {
        "latitude": query.point.latitude,
        "longitude": query.point.longitude,
        "timezone": "Asia/Yangon",
        "utc_offset_seconds": 23400,
        "generationtime_ms": 1.1,
        "current": {
            "time": "2026-11-14T12:30",
            "interval": 900,
            "temperature_2m": 28,
            "relative_humidity_2m": 70,
        },
        "current_units": {
            "time": "iso8601",
            "interval": "seconds",
            "temperature_2m": "°C",
            "relative_humidity_2m": "%",
        },
        "daily": {
            "time": ["2026-11-14", "2026-11-15", "2026-11-16"],
            "temperature_2m_min": [20, 21, 22],
            "temperature_2m_max": [30, 31, 32],
            "precipitation_sum": [0, None, 5],
        },
        "daily_units": {
            "time": "iso8601",
            "temperature_2m_min": "°C",
            "temperature_2m_max": "°C",
            "precipitation_sum": "mm",
        },
    }


def capture(payload, retrieved=NOW):
    body = json.dumps(payload, allow_nan=False).encode()
    return Capture(
        body,
        Retrieval(
            requested_at=retrieved,
            retrieved_at=retrieved,
            endpoint="https://synthetic.invalid/test",
            query={},
            http_status=200,
            response_sha256=hashlib.sha256(body).hexdigest(),
        ),
    )
