"""Source-format readers. Preserve source meaning; no suitability computation."""

import csv
from datetime import date
from html.parser import HTMLParser
from html import unescape
import io
import math
import re


class TableReader(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.rows, self.row, self.cell, self.title = [], None, None, ""
        self.in_title = False

    def handle_starttag(self, tag, attrs):
        if tag == "h2":
            self.in_title = True
        elif tag == "tr":
            self.row = []
        elif tag in {"th", "td"} and self.row is not None:
            self.cell = ""

    def handle_data(self, data):
        if self.in_title:
            self.title += data
        if self.cell is not None:
            self.cell += data

    def handle_endtag(self, tag):
        if tag == "h2":
            self.in_title = False
        elif tag in {"th", "td"} and self.cell is not None:
            self.row.append(" ".join(self.cell.split()))
            self.cell = None
        elif tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None


def number(text):
    if text.strip() in {"", "NA", "-", "---", "no input"}:
        return None
    value = float(text)
    if not math.isfinite(value):
        raise ValueError("nonfinite source number")
    return value


def bounds(low, high):
    result = {"min": number(low), "max": number(high)}
    if all(v is not None for v in result.values()) and result["min"] > result["max"]:
        raise ValueError("reversed source bounds")
    return result


def ecocrop_sheet(raw, expected_name):
    reader = TableReader()
    reader.feed(raw.decode("utf-8"))
    if reader.title.strip() != expected_name:
        raise ValueError("ECOCROP species identity mismatch")
    rows = {r[0]: r for r in reader.rows if r}
    required = {
        "Temperat. requir.",
        "Rainfall (annual)",
        "Soil PH",
        "Altitude",
        "Product. system",
    }
    if not required <= rows.keys():
        raise ValueError("incomplete ECOCROP sheet")
    result = {}
    for label, key in [
        ("Temperat. requir.", "ecological_temperature"),
        ("Rainfall (annual)", "annual_precipitation"),
        ("Soil PH", "ecological_soil_ph"),
    ]:
        r = rows[label]
        if len(r) != 8:
            raise ValueError("ECOCROP table layout changed")
        result[key] = {"optimal": bounds(r[1], r[2]), "absolute": bounds(r[3], r[4])}
    result["altitude"] = bounds(rows["Altitude"][3], rows["Altitude"][4])
    r = rows["Product. system"]
    if len(r) != 5 or r[2] != "Crop cycle":
        raise ValueError("ECOCROP cycle layout changed")
    result["ecological_crop_cycle"] = bounds(r[3], r[4])
    for label, key in [
        ("Soil depth", "ecological_soil_depth"),
        ("Soil texture", "soil_texture"),
        ("Soil drainage", "soil_drainage"),
    ]:
        matches = [r for r in reader.rows if label in r]
        if len(matches) != 1:
            raise ValueError("ambiguous ECOCROP category")
        r = matches[0]
        i = r.index(label)
        result[key] = {"optimal": r[i + 1] or None, "absolute": r[i + 2] or None}
    result["climate_zone"] = rows["Climate zone"][1] or None
    return result


def grin_identity(raw, expected_name, expected_family):
    text = raw.decode("utf-8")
    match = re.search(r'<h1 class="title">Taxon:&nbsp;\s*(.*?)</h1>', text, re.S)
    if match is None:
        raise ValueError("unrecognized GRIN taxon layout")
    name = unescape(re.sub(r"<[^>]+>", "", match[1])).strip()
    plain = unescape(re.sub(r"<[^>]+>", " ", text))
    plain = " ".join(plain.split())
    if (
        not name.startswith(expected_name + " ")
        or "Family: " + expected_family not in plain
    ):
        raise ValueError("GRIN taxon/family identity mismatch")
    return {
        "scientific_name": expected_name,
        "family": expected_family,
        "provider_name": name,
    }


COLUMNS = "EcoPortCode ScientificName AUTH FAMNAME SYNO COMNAME LIFO HABI LISPA PHYS CAT PLAT TOPMN TOPMX TMIN TMAX ROPMN ROPMX RMIN RMAX PHOPMN PHOPMX PHMIN PHMAX LATOPMN LATOPMX LATMN LATMX ALTMX LIOPMN LIOPMX LIMN LIMX DEP DEPR TEXT TEXTR FER FERR TOX TOXR SAL SALR DRA DRAR KTMPR KTMP PHOTO CLIZ ABITOL ABISUS INTRI PROSY GMIN GMAX".split()
AGRICULTURAL_CATEGORIES = {
    "cereals & pseudocereals": "cereals_grains",
    "pulses (grain legumes)": "legumes_pulses",
    "roots/tubers": "roots_tubers",
    "vegetables": "vegetables",
    "fruits & nuts": "fruits_nuts",
    "forage/pasture": "forage_fodder",
}


def ecocrop_csv(raw, expected_count):
    if not raw.endswith(b"\n"):
        raise ValueError("unterminated provider CSV")
    reader = csv.DictReader(io.StringIO(raw.decode("cp1252")), strict=True)
    if reader.fieldnames != COLUMNS:
        raise ValueError("unsupported ECOCROP CSV schema")
    rows = list(reader)
    if len(rows) != expected_count or any(
        None in r or None in r.values() for r in rows
    ):
        raise ValueError("truncated CSV or wrong field/record count")
    ids, names = set(), set()
    for row in rows:
        if not row["EcoPortCode"].isdigit() or not row["ScientificName"]:
            raise ValueError("invalid provider identity")
        if row["EcoPortCode"] in ids or row["ScientificName"].casefold() in names:
            raise ValueError("duplicate source identity")
        ids.add(row["EcoPortCode"])
        names.add(row["ScientificName"].casefold())
    return rows


def agricultural_categories(row):
    """Positive cultivated attribute AND explicit agricultural category required.

    Generic materials, environmental, ornamentals, forests and wild-only records
    cannot enter the agricultural crop catalog. This is a conservative subset.
    """
    if not {"grown on large scale", "grown on small scale"} & set(
        row["PLAT"].split(", ")
    ):
        return []
    categories = set(row["CAT"].split(", "))
    return sorted(v for k, v in AGRICULTURAL_CATEGORIES.items() if k in categories)


def calendar_window(first, last):
    def mmdd(value):
        m, d = int(value["month"]), int(value["day"])
        date(2000, m, d)  # leap-year validation; no arbitrary crop year assigned
        return m * 100 + d

    start, end = mmdd(first), mmdd(last)
    return {
        "first_mmdd": start,
        "last_mmdd": end,
        "wraps_year": start > end,
        "advisory": True,
    }


def calendar_sessions(records, crop_codes=None, country="MM"):
    """Selected factual fields only; original indexing survives for exact locators."""
    if not isinstance(records, list):
        raise ValueError("calendar must be a list")
    result = []
    for i, record in enumerate(records):
        if record["id_country"] != country:
            raise ValueError("calendar country mismatch")
        if crop_codes is not None and record["crop"]["id"] not in crop_codes:
            continue
        updated = (
            __import__("datetime")
            .datetime.strptime(record["lastUpdated"], "%d/%m/%Y")
            .date()
            .isoformat()
        )
        for j, session in enumerate(record["sessions"]):
            duration = session["growing_period"]
            match = re.fullmatch(r"(\d+)\s*-\s*(\d+)", duration["value"])
            if duration["period"] != "days" or not match:
                raise ValueError("unsupported calendar duration")
            span = bounds(*match.groups())
            if span["min"] <= 0:
                raise ValueError("nonpositive crop duration")
            result.append(
                {
                    "locator": f"/{i}/sessions/{j}",
                    "crop_code": record["crop"]["id"],
                    "provider_crop_name": record["crop"]["name"],
                    "region_id": country + "-FAO-AEZ-" + record["aez"]["id"],
                    "provider_region_name": record["aez"]["name"],
                    "updated_on": updated,
                    "season": session["additional_information"],
                    "comments": session["comments"],
                    "planting_window": calendar_window(
                        session["early_sowing"], session["later_sowing"]
                    ),
                    "harvest_window": calendar_window(
                        session["early_harvest"], session["late_harvest"]
                    ),
                    "growing_duration": span,
                }
            )
    return result


SOIL_UNITS = {
    "phh2o": (10, "pH x 10", "pH"),
    "soc": (10, "dg/kg", "g/kg"),
    "clay": (10, "g/kg", "percent_mass"),
    "sand": (10, "g/kg", "percent_mass"),
    "silt": (10, "g/kg", "percent_mass"),
    "bdod": (100, "cg/cm3", "kg/dm3"),
    "cfvo": (10, "cm3/dm3", "volumetric_percent"),
    "nitrogen": (100, "cg/kg", "g/kg"),
}
SOIL_DEPTHS = {(0, 5), (5, 15), (15, 30), (30, 60), (60, 100), (100, 200)}


def soil_value(property_id, raw, top_cm, bottom_cm, quantile, nodata=None):
    """A decoded native sample, never an engine observation or laboratory result."""
    divisor, native, conventional = SOIL_UNITS[property_id]
    if (top_cm, bottom_cm) not in SOIL_DEPTHS or quantile not in {
        "mean",
        "Q05",
        "Q50",
        "Q95",
    }:
        raise ValueError("unsupported SoilGrids depth/statistic")
    if raw is not None and raw != nodata and (not math.isfinite(raw) or raw < 0):
        raise ValueError("invalid native soil value")
    missing = raw is None or raw == nodata
    return {
        "original_value": raw,
        "original_unit": native,
        "value": None if missing else raw / divisor,
        "unit": conventional,
        "conversion": f"native / {divisor}",
        "depth_cm": {"top": top_cm, "bottom": bottom_cm},
        "statistic": quantile,
        "kind": "modeled",
        "quality": "missing" if missing else "reference_only",
        "missing_reason": "source_nodata" if missing else None,
        "usable_for_assessment": False,
    }
