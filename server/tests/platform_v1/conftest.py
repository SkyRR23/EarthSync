import json
import os
from datetime import datetime
from pathlib import Path

import pytest

from earthsync.platform_v1.models import ClimateQuery, FarmInput, Point
from earthsync.platform_v1.providers.power_daily import read_daily
from earthsync.platform_v1.providers.transport import Capture
from earthsync.platform_v1.store import Store

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture
def query():
    return ClimateQuery(
        point=Point(latitude=42.03, longitude=-93.62),
        start="2024-02-01",
        end="2024-02-29",
    )


@pytest.fixture
def farm_input():
    return FarmInput(
        name="Test farm (no ground truth)",
        confirmed_point=Point(latitude=42.03, longitude=-93.62),
        confirmed_on="2026-11-14",
        production_system="rainfed",
    )


@pytest.fixture
def store(tmp_path):
    return Store(tmp_path / "private")


def captured(name):
    suffix = {"T2M_MIN": "T2M_MIN", "T2M_MAX": "T2M_MAX", "PRECTOTCORR": "PREC"}[name]
    return Capture(
        (FIXTURES / f"power_iowa_202402_{suffix}.real.json").read_bytes(),
        datetime.fromisoformat(
            json.loads(
                (
                    Path(__file__).parents[2]
                    / "docs/platform_v1/nasa-source-review.json"
                ).read_text()
            )["capture_completion_times"][f"power_iowa_202402_{suffix}.real.json"]
        ),
        {"content-type": "application/json"},
    )


@pytest.fixture
def records(query):
    return [
        read_daily(captured(name), query, name)
        for name in ("T2M_MIN", "T2M_MAX", "PRECTOTCORR")
    ]


@pytest.fixture
def compat_sources():
    """Explicit independent PR source trees; no production import-path mutation."""
    root = os.getenv("EARTHSYNC_COMPAT_ROOT")
    if not root:
        pytest.skip(
            "Set EARTHSYNC_COMPAT_ROOT to explicitly test audited PR #15/#16 sources"
        )
    return Path(root)
