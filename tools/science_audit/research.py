"""Offline research safeguards. No archive record becomes a live crop rule."""

import copy
import math
from calendar import monthrange

MONTH_NAMES = "JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC".split()


def validate_month_labels(rows):
    seen = set()
    for row in rows:
        month = int(row["month"])
        identity = (row.get("parameter"), row.get("year"), month)
        if not 1 <= month <= 12 or row["month_name"] != MONTH_NAMES[month - 1]:
            raise ValueError("Month ordinal/name mismatch or annual slot")
        if identity in seen:
            raise ValueError("Duplicate or conflicting source month")
        seen.add(identity)


def rainfall_normals(document, first_year, last_year):
    """Complete monthly rate-to-total arithmetic; reference-only, no gap filling.

    Each calendar month's rate is multiplied by its actual year's day count
    before averaging totals. An absent/fill/invalid year-month makes that normal
    unknown. Original metadata is retained; this is not provider authentication.
    """
    if not 1 <= first_year <= last_year <= 9999:
        raise ValueError("Invalid year interval")
    header = document["header"]
    if header.get("sources") not in (["MERRA2"], ["MERRA2", "POWER"]):
        raise ValueError("Unsupported source lineage")
    if document["parameters"]["PRECTOTCORR"]["units"] != "mm/day":
        raise ValueError("Rainfall rate unit mismatch")
    if (
        header.get("start") != f"{first_year:04}0101"
        or header.get("end") != f"{last_year:04}1231"
    ):
        raise ValueError("Requested and declared interval differ")
    values = document["properties"]["parameter"]["PRECTOTCORR"]
    expected = {
        f"{y:04}{m:02}" for y in range(first_year, last_year + 1) for m in range(1, 14)
    }
    if set(values) - expected:
        raise ValueError("Unexpected source month")
    out = []
    for month in range(1, 13):
        totals, missing = [], []
        for year in range(first_year, last_year + 1):
            key = f"{year:04}{month:02}"
            value = values.get(key)
            if (
                type(value) not in (int, float)
                or not math.isfinite(value)
                or value == header["fill_value"]
                or value < 0
            ):
                missing.append(key)
            else:
                totals.append(value * monthrange(year, month)[1])
        out.append(
            {
                "month": month,
                "rainfall_mm": None if missing else math.fsum(totals) / len(totals),
                "expected_years": last_year - first_year + 1,
                "usable_years": len(totals),
                "missing_year_months": missing,
            }
        )
    return {
        "classification": "model_derived_environmental_estimate",
        "data_kind": "modeled",
        "recommendation_eligible": False,
        "source_header": copy.deepcopy(header),
        "source_geometry": copy.deepcopy(document.get("geometry")),
        "source_parameters": copy.deepcopy(document["parameters"]),
        "months": out,
        "limitations": [
            "Research arithmetic only; source retrieval and local applicability remain separate acceptance requirements."
        ],
    }


def validate_temperature_statistic(parameter, temporal_resolution, claimed_statistic):
    expected = {
        ("T2M", "daily"): "daily_mean",
        ("T2M_MIN", "daily"): "daily_minimum",
        ("T2M_MAX", "daily"): "daily_maximum",
        ("T2M_MIN", "monthly"): "monthly_minimum",
        ("T2M_MAX", "monthly"): "monthly_maximum",
        ("T2M_MIN_AVG", "monthly"): "mean_daily_minimum",
        ("T2M_MAX_AVG", "monthly"): "mean_daily_maximum",
    }
    if expected.get((parameter, temporal_resolution)) != claimed_statistic:
        raise ValueError("Unsupported temperature statistic transformation")


def quarantine_profile(profile, source_path, archive_sha256, source_review):
    """Retain contributed assertions with an explicit non-executable boundary."""
    reference_limitation = {
        "source_reviewed_reference_fact": "A matching ECOCROP numeric reference is not a verified Myanmar field rule.",
        "cached_source_reference_only": "Indexed original-source reference matches; direct retrieval failed. No fresh source availability or executable applicability accepted.",
    }.get(
        source_review,
        "Original source unavailable; contributed values remain unverified.",
    )
    return {
        "profile_id": profile["crop_id"],
        "archive_sha256": archive_sha256,
        "original_member": source_path,
        "source_assertion": copy.deepcopy(profile),
        "recommendation_eligible": False,
        "approved_for_candidates": False,
        "executable_rules": [],
        "temperature_reference_class": source_review,
        "executable_temperature_rule": False,
        "other_agronomic_assertions_class": "unverified_assertion",
        "production_system_acceptance": None,
        "region_acceptance": None,
        "independent_agronomist_acceptance": None,
        "limitations": [
            reference_limitation,
            "Team duration, seasonal water, N fixation, pest benefits, root depth, residue and calendars require parameter-specific evidence.",
            "No source-review status or caller-supplied confidence promotes a crop recommendation.",
        ],
    }


def validate_quarantine(record):
    if (
        record["recommendation_eligible"] is not False
        or record["approved_for_candidates"] is not False
        or record["executable_rules"] != []
        or record["executable_temperature_rule"] is not False
    ):
        raise ValueError("Research assertion promoted into executable crop rules")
