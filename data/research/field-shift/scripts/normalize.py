"""Offline audit and research fixtures from the immutable contributed CSVs.

No network, collection-script imports, interpolation, agronomic rules or writes
to raw/. Outputs retain unknown metadata and are not production adapter inputs.
"""

import argparse
import csv
import hashlib
import json
import math
from collections import Counter
from datetime import date, timedelta
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "raw" / "original" / "data-pack"
LOCATIONS = {"hlegu": (16.87, 96.20), "bago": (17.33, 96.48), "magway": (20.15, 94.93)}
SOIL_DOC = "https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_01.html"
SOIL = {
    "phh2o": ("pH*10", 0.1, "pH"),
    "clay": ("g/kg", 0.1, "% by mass"),
    "sand": ("g/kg", 0.1, "% by mass"),
    "silt": ("g/kg", 0.1, "% by mass"),
    "soc": ("dg/kg", 0.1, "g/kg"),
    "nitrogen": ("cg/kg", 0.01, "g/kg"),
    "cec": ("mmol(c)/kg", 1.0, "mmol(c)/kg"),
    "bdod": ("cg/cm³", 0.01, "g/cm3"),
}
FORECAST = {
    "tmax_c": ("temperature_2m_max", "deg_c"),
    "tmin_c": ("temperature_2m_min", "deg_c"),
    "precip_mm": ("precipitation_sum", "mm"),
    "precip_prob_pct": ("precipitation_probability_max", "%"),
    "rh_pct": ("relative_humidity_2m_mean", "%"),
    "wind_max_kmh": ("wind_speed_10m_max", "km/h"),
    "gust_max_kmh": ("wind_gusts_10m_max", "km/h"),
    "et0_mm": ("et0_fao_evapotranspiration", "mm"),
    "srad_mj_m2": ("shortwave_radiation_sum", "MJ/m2"),
    "sm_0_7_m3m3": ("soil_moisture_0_to_7cm_mean", "m3/m3"),
    "sm_7_28_m3m3": ("soil_moisture_7_to_28cm_mean", "m3/m3"),
    "soil_temp_0_7_c": ("soil_temperature_0_to_7cm_mean", "deg_c"),
}


def read_csv(path):
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def number(value):
    if value == "":
        return None
    result = float(value)
    if not math.isfinite(result):
        raise ValueError("Nonfinite number in contributed data")
    return result


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")


def source(path):
    return {"path": path.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def log_records():
    return [{"csv_row": i, **row} for i, row in enumerate(read_csv(RAW / "_meta" / "fetch_log.csv"), 2)]


def matching_logs(logs, location, product=None, band=None, target=None, layer=None):
    """Candidate retrievals only: the contributed log has no response hashes."""
    lat, lon = LOCATIONS[location]
    result = []
    for row in logs:
        query = parse_qs(urlparse(row["url"]).query)
        if row["outcome"] != "ok":
            continue
        if target is not None and row["target"] != target:
            continue
        if layer is not None and query.get("LAYERS") != [layer]:
            continue
        if product is not None:
            if f"/{product}/subset" not in row["url"] or query.get("band") != [band]:
                continue
            if query.get("latitude") != [f"{lat:.4f}"] or query.get("longitude") != [f"{lon:.4f}"]:
                continue
        result.append(row["csv_row"])
    return result


def soil_fixture(location, logs):
    path = RAW / "csv" / f"soilgrids_{location}.csv"
    records = []
    for row_number, row in enumerate(read_csv(path), 2):
        prop = row["property"]
        unit, factor, normalized_unit = SOIL[prop]
        lat, lon = LOCATIONS[location]
        if (row["location"], float(row["lat"]), float(row["lon"])) != (location, lat, lon):
            raise ValueError("Soil query location mismatch")
        if row["unit"] != unit:
            raise ValueError("Unexpected SoilGrids unit")
        original = number(row["value"])
        converted = None if original is None else round(original * factor, 8)
        # Check contributed conversion separately; its unit_si label is preserved in raw.
        if converted is not None and not math.isclose(converted, number(row["value_si"]), abs_tol=0.005):
            raise ValueError("SoilGrids contributed conversion mismatch")
        top, bottom = map(int, row["depth"].removesuffix("cm").split("-"))
        records.append({
            "source_csv_row": row_number, "property": prop,
            "data_type": "modeled" if converted is not None else "unavailable",
            "depth_cm": {"top": top, "bottom": bottom}, "statistic": "mean",
            "original": {"value": original, "unit": unit},
            "normalized": {"value": converted, "unit": normalized_unit},
            "transformation": {"multiply_by": factor, "documentation": SOIL_DOC},
            "prediction_interval_90": None, "uncertainty_status": "not_contributed",
            "candidate_fetch_log_rows": matching_logs(logs, location, target=path.name, layer=f"{prop}_{row['depth']}_mean"),
        })
    return {
        "provider": "ISRIC SoilGrids WMS", "data_type": "modeled", "source": source(path),
        "nominal_native_resolution_m": 250, "query_support": "WMS EPSG:4326, 0.5-degree bbox, 101x101 display pixels, X=Y=50; native cell footprint not retained",
        "release": None, "retrieved_at": None, "measurement_date": None,
        "temporal_support": "Static modeled soil context; no acquisition date per property",
        "provided_depths_cm": [[0, 5], [5, 15], [15, 30], [30, 60]],
        "missing_standard_depths_cm": [[60, 100], [100, 200]],
        "drainage": {"value": None, "data_type": "unavailable", "reason": "No validated drainage method or measurement"},
        "integration_ready": False, "records": records,
        "limitations": ["Predictions are not farm samples.", "No quantiles, pinned release, response bodies or native cell geometry contributed.", "Fetch log rows are candidate retrievals, not a hash-bound response-to-CSV chain.", "value_si in the original is a convenience label, not uniformly SI units."],
    }


def expected_composites(start_year, end_year, step):
    dates = []
    for year in range(start_year, end_year + 1):
        day = date(year, 1, 1)
        while day.year == year:
            dates.append(day.isoformat())
            day += timedelta(days=step)
    return dates


def vegetation_fixture(location, logs):
    series = {}
    for label in ("ndvi", "evi", "lst_day", "lst_night"):
        path = RAW / "csv" / f"modis_{label}_{location}.csv"
        rows = read_csv(path)
        is_lst = label.startswith("lst")
        product = "MOD11A2" if is_lst else "MOD13Q1"
        band = ("LST_Day_1km" if label == "lst_day" else "LST_Night_1km") if is_lst else f"250m_16_days_{label.upper()}"
        scale = 0.02 if is_lst else 0.0001
        source_unit = "Kelvin" if is_lst else f"{label.upper()} ratio - No units"
        records = []
        for row_number, row in enumerate(rows, 2):
            if (
                row["product"] != product
                or row["band"] != band
                or number(row["scale"]) != scale
                or row["source_unit"] != source_unit
            ):
                raise ValueError("Unexpected MODIS product, band, scale or unit")
            original = number(row["raw_value"])
            valid = original is not None and original.is_integer() and ((7500 <= original <= 65535) if is_lst else (-2000 <= original <= 10000))
            value = round(original * scale - (273.15 if is_lst else 0), 8) if valid else None
            if valid and not math.isclose(value, number(row["value"]), abs_tol=0.005):
                raise ValueError("MODIS contributed conversion mismatch")
            records.append({
                "source_csv_row": row_number, "composite_start_date": row["date"],
                "data_type": "observed" if valid else "unavailable",
                "original_value": original, "normalized_value": value,
                "status": "units_and_range_valid_qa_unknown" if valid else "missing_or_invalid",
                "missing_reason": None if valid else "Contributed blank or invalid; original fill code and cause not recoverable",
                "quality_flags": None, "usable_for_analysis": False,
            })
        dates = [r["date"] for r in rows]
        expected = expected_composites(2024, 2025, 8 if is_lst else 16)
        if len(set(dates)) != len(dates) or dates != sorted(dates):
            raise ValueError("Duplicate or unordered MODIS composite dates")
        series[label] = {
            "provider": "NASA MODIS via ORNL DAAC point API", "product": product,
            "collection_version": None, "band": band, "data_type": "observed",
            "observation_method": "Satellite-derived retrieval/index, not direct farm or canopy measurement",
            "source": source(path), "retrieved_at": None,
            "candidate_fetch_log_rows": matching_logs(logs, location, product=product, band=band),
            "nominal_native_resolution_m": 1000 if is_lst else 250,
            "spatial_support": "Requested single-pixel subset; pixel centre, footprint and extraction response absent",
            "nominal_composite_days": 8 if is_lst else 16,
            "time_coverage": {"first_start": min(dates), "last_start": max(dates), "expected_composites": len(expected), "present_composites": len(dates), "missing_composite_starts": sorted(set(expected) - set(dates)), "unexpected_composite_starts": sorted(set(dates) - set(expected)), "missing_or_invalid_values": sum(r["normalized_value"] is None for r in records)},
            "original_unit": "K after scaling" if is_lst else "dimensionless after scaling",
            "normalized_unit": "deg_c" if is_lst else "dimensionless",
            "transformation": {"multiply_by": scale, "add": -273.15 if is_lst else 0},
            "integration_ready": False, "records": records,
        }
    return {"series": series, "limitations": ["QA bands absent: numeric values cannot be certified cloud-free or scientifically usable.", "Two historical years do not validate a current anomaly baseline or disease diagnosis.", "LST is surface skin temperature, not POWER T2M air temperature.", "Collection version must be recovered from original subset metadata; CMR granules do not prove subset version."]}


def forecast_fixture(location):
    path = RAW / "csv" / f"forecast16_{location}.csv"
    rows = read_csv(path)
    records = []
    for row_number, row in enumerate(rows, 2):
        records.append({"source_csv_row": row_number, "local_date": row["date"], "variables": {
            key: {"value": number(row[key]), "unit": unit, "provider_variable": variable,
                  "data_type": "forecast" if row[key] != "" else "unavailable",
                  "status": "metadata_unverified" if row[key] != "" else "missing_in_contribution"}
            for key, (variable, unit) in FORECAST.items()
        }})
    dates = [r["date"] for r in rows]
    return {
        "provider": "Open-Meteo", "endpoint": "https://api.open-meteo.com/v1/forecast",
        "source": source(path), "data_type": "forecast", "integration_ready": False,
        "issue_at": None, "retrieved_at": None, "expires_at": None,
        "freshness_status": "unverifiable_do_not_serve_as_live",
        "requested_model": "default Best Match (per contributed collector)", "resolved_models": None,
        "spatial_resolution": None, "response_grid_coordinates": None,
        "time_coverage": {"first_local_date": min(dates), "last_local_date": max(dates), "timezone": None, "expected_days_from_contributed_request": 16, "present_days": len(dates), "missing_by_variable": {key: sum(row[key] == "" for row in rows) for key in FORECAST}},
        "unit_validation": "Column and request semantics match provider documentation; original daily_units response absent, so no runtime unit assertion is possible",
        "transformation": "No numerical conversion; blank CSV cells become null. Column aliases mapped to documented variables.",
        "records": records,
        "limitations": ["No forecast/current-weather fetch log entries, raw provider response, UTC offset, issue time or response units contributed.", "Local-date range does not establish freshness. API processing duration generationtime_ms would not establish issue time either.", "Model/provider mix and resolution cannot be inferred from an ERA5-Land/IFS comment.", "Soil forecast variables are absent on the last two days; do not fill them or treat the whole row as complete."],
    }


def audit_inventory(logs):
    tables = []
    for path in sorted((RAW / "csv").glob("*.csv")):
        rows = read_csv(path)
        columns = {}
        for key in rows[0]:
            values = [r[key] for r in rows]
            nonempty = [v for v in values if v != ""]
            try:
                nums = [number(v) for v in nonempty]
                kind = "number" if nums else "unknown"
            except ValueError:
                nums = []
                kind = "string"
            columns[key] = {"type": kind, "blank_cells": values.count("")}
            if nums:
                columns[key].update(min=min(nums), max=max(nums))
        dates = [r["date"] for r in rows if "date" in r]
        date_coverage = None
        if dates:
            date_coverage = {"first": min(dates), "last": max(dates), "duplicate_dates": len(dates) - len(set(dates))}
        tables.append({**source(path), "rows": len(rows), "date_coverage": date_coverage, "columns": columns,
                       "fetch_log_rows_with_matching_target": [r["csv_row"] for r in logs if r["target"] == path.name]})
    return {"audit_date": "2026-11-14", "tables": tables,
            "fetch_log": {"source": source(RAW / "_meta" / "fetch_log.csv"), "records": len(logs), "by_source": dict(sorted(Counter(r["source"] for r in logs).items())), "by_outcome": dict(Counter(r["outcome"] for r in logs)), "first_recorded_at": min(r["fetched_at_utc"] for r in logs), "last_recorded_at": max(r["fetched_at_utc"] for r in logs), "failed_csv_rows": [r["csv_row"] for r in logs if r["outcome"] != "ok"]},
            "note": "CSV blank cells include absent optional text; counts are not automatically missing scientific measurements. Log matching by target alone misses synthetic MODIS target names; normalized series instead link URL coordinates/product/band. No original provider response bodies contributed."}


def build(output):
    if output.resolve().is_relative_to((ROOT / "raw").resolve()):
        raise ValueError("Output must be outside raw/")
    output.mkdir(parents=True, exist_ok=True)
    logs = log_records()
    dump(output / "audit_inventory.json", audit_inventory(logs))
    for location, (lat, lon) in LOCATIONS.items():
        dump(output / f"{location}.json", {
            "schema_version": "research-fixture-v1", "fixture_status": "reference_only_not_production_input",
            "location": {"id": location, "country": "Myanmar", "query_latitude": lat, "query_longitude": lon, "crs": "EPSG:4326", "coordinate_source": "raw/original/data-pack/scripts/fetch_sources.py LOCATIONS, corroborated by soil CSVs; not surveyed field boundaries"},
            "data_type_vocabulary": ["observed", "modeled", "forecast", "hypothetical", "farmer_reported", "unavailable"],
            "fetch_log_source": source(RAW / "_meta" / "fetch_log.csv"),
            "soil_context": soil_fixture(location, logs),
            "vegetation_context": vegetation_fixture(location, logs),
            "weather_outlook": forecast_fixture(location),
        })


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "normalized")
    args = parser.parse_args()
    if args.output.resolve().is_relative_to((ROOT / "raw").resolve()):
        parser.error("Output must be outside raw/")
    build(args.output)
