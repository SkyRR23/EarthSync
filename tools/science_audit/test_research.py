"""Fictional fixtures test rejection and missingness, never farming advice."""

import copy
import json
from pathlib import Path

import pytest

from research import (
    quarantine_profile,
    rainfall_normals,
    validate_month_labels,
    validate_quarantine,
    validate_temperature_statistic,
)


def raw():
    return {
        "header": {
            "sources": ["MERRA2"],
            "fill_value": -999,
            "start": "20230101",
            "end": "20241231",
        },
        "geometry": {"type": "Point", "coordinates": [96.2, 16.87]},
        "parameters": {"PRECTOTCORR": {"units": "mm/day"}},
        "properties": {
            "parameter": {
                "PRECTOTCORR": {
                    f"{y}{m:02}": 2 for y in (2023, 2024) for m in range(1, 14)
                }
            }
        },
    }


@pytest.mark.parametrize(
    "month,name", [(1, "FEB"), (12, "ANN"), (0, "JAN"), (13, "ANN")]
)
def test_shifted_and_annual_month_labels_are_rejected(month, name):
    with pytest.raises(ValueError):
        validate_month_labels(
            [{"parameter": "T2M", "month": month, "month_name": name}]
        )


def test_duplicate_or_conflicting_reference_months_rejected():
    row = {"parameter": "T2M", "month": 1, "month_name": "JAN", "value": 10}
    validate_month_labels([row])
    for value in (10, 20):
        with pytest.raises(ValueError):
            validate_month_labels([row, dict(row, value=value)])


def test_rate_conversion_uses_exact_calendar_before_averaging():
    data = raw()
    before = copy.deepcopy(data)
    result = rainfall_normals(data, 2023, 2024)
    assert result["months"][1]["rainfall_mm"] == 57  # (28*2 + 29*2)/2
    assert result["months"][0]["rainfall_mm"] == 62
    assert result["data_kind"] == "modeled"
    assert result["source_geometry"] == data["geometry"]
    assert data == before


@pytest.mark.parametrize("bad", [None, -999, -1, True, "2", float("nan")])
def test_invalid_or_missing_month_does_not_become_complete_normal(bad):
    data = raw()
    data["properties"]["parameter"]["PRECTOTCORR"]["202402"] = bad
    month = rainfall_normals(data, 2023, 2024)["months"][1]
    assert month["rainfall_mm"] is None and month["usable_years"] == 1
    assert month["missing_year_months"] == ["202402"]


def test_absent_date_and_wrong_unit_scale_are_rejected_or_unknown():
    data = raw()
    del data["properties"]["parameter"]["PRECTOTCORR"]["202402"]
    assert rainfall_normals(data, 2023, 2024)["months"][1]["rainfall_mm"] is None
    data["parameters"]["PRECTOTCORR"]["units"] = "mm"
    with pytest.raises(ValueError):
        rainfall_normals(data, 2023, 2024)


@pytest.mark.parametrize(
    "parameter,temporal,claimed",
    [
        ("T2M_MAX", "monthly", "mean_daily_maximum"),
        ("T2M_MIN", "monthly", "mean_daily_minimum"),
        ("LST_Day_1km", "daily", "daily_maximum"),
        ("T2M", "daily", "daily_minimum"),
    ],
)
def test_temperature_statistics_are_not_interchangeable(parameter, temporal, claimed):
    with pytest.raises(ValueError):
        validate_temperature_statistic(parameter, temporal, claimed)
    validate_temperature_statistic("T2M_MAX_AVG", "monthly", "mean_daily_maximum")


@pytest.mark.parametrize(
    "review", ["source_reviewed_reference_fact", "source_unavailable"]
)
def test_source_review_never_promotes_a_contributed_crop(review):
    original = {
        "crop_id": "synthetic",
        "unverified": [],
        "evidence": [{"confidence": "sourced"}],
    }
    record = quarantine_profile(original, "synthetic.json", "0" * 64, review)
    validate_quarantine(record)
    assert record["source_assertion"] == original
    record["recommendation_eligible"] = True
    with pytest.raises(ValueError):
        validate_quarantine(record)


def test_committed_myanmar_research_fixture_is_non_executable():
    root = Path(__file__).resolve().parents[2]
    fixture = json.loads(
        (root / "data/research/science-audit-v1/myanmar-reference-only.json").read_text(
            encoding="utf-8"
        )
    )
    assert fixture["schema_version"] == "earthsync.research-quarantine.v1"
    assert fixture["classification"] == "research_only"
    assert fixture["recommendation_eligible"] is False
    assert len(fixture["profiles"]) == 12
    for profile in fixture["profiles"]:
        validate_quarantine(profile)
    for normal in fixture["rainfall_normals_reference_only"].values():
        assert normal["data_kind"] == "modeled"
        assert normal["recommendation_eligible"] is False
