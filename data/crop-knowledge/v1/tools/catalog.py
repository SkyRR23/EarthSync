"""Offline crop reference catalog: strict validation and exact-scope lookup only."""

import argparse
import hashlib
import json
from datetime import date, datetime
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
VERSION = "earthsync.crop-knowledge.v1-proposal"
INPUTS = ("sources.json", "evidence/claims.json", "profiles.json", "pilots.json")


def read_json(path):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"Duplicate JSON key: {key}")
            result[key] = value
        return result

    def invalid(value):
        raise ValueError(f"Non-finite JSON number: {value}")

    return json.loads(
        Path(path).read_text(encoding="utf-8"),
        object_pairs_hook=pairs,
        parse_constant=invalid,
    )


def encoded(value):
    return (
        json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    ).encode()


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def index(records, label):
    result = {record["id"]: record for record in records}
    if len(result) != len(records):
        raise ValueError(f"Duplicate {label} IDs")
    return result


def month_day(value):
    # Leap-day guidance is permitted, without inventing a non-leap-year date.
    return date.fromisoformat(f"2000-{value}")


def validate(catalog, root=ROOT):
    schema = read_json(root / "catalog.schema.json")
    Draft202012Validator.check_schema(schema)
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(catalog)
    sources = index(catalog["sources"], "source")
    claims = index(catalog["claims"], "claim")
    profiles = index(catalog["profiles"], "profile")
    pilots = index(catalog["pilots"], "pilot")
    captures = index(read_json(root / "evidence/captures.json"), "capture")
    if captures.keys() != sources.keys():
        raise ValueError("Capture/source inventory mismatch")
    for source in sources.values():
        capture = captures.get(source["id"])
        if capture is None or capture["url"] != source["url"]:
            raise ValueError(f"Missing/mismatched source capture: {source['id']}")
        if len(capture["excerpt"].split()) > 25:
            raise ValueError("Source excerpt exceeds the short quotation budget")
        retrieved = datetime.fromisoformat(
            capture["retrieved_at"].replace("Z", "+00:00")
        )
        if retrieved.utcoffset() is None:
            raise ValueError("Capture needs a timezone")
        published = source["publication_date"]
        precision = source["publication_date_precision"]
        lengths = {"year": 4, "month": 7, "day": 10}
        if precision == "unknown":
            if published is not None:
                raise ValueError("Unknown publication date must be null")
        elif published is None or len(published) != lengths[precision]:
            raise ValueError("Publication date precision mismatch")
        elif precision == "year":
            date.fromisoformat(published + "-01-01")
        elif precision == "month":
            date.fromisoformat(published + "-01")
        else:
            date.fromisoformat(published)
        if published and published > retrieved.date().isoformat()[: len(published)]:
            raise ValueError("Source publication is after retrieval")
        if (
            capture["method"] != "web_tool_excerpt"
            or capture["provider_response_sha256"] is not None
        ):
            raise ValueError("Web excerpts cannot claim original-response integrity")
    for claim in claims.values():
        if claim["source_id"] not in sources:
            raise ValueError(f"Unresolved source: {claim['id']}")
        if any(p not in pilots for p in claim["pilot_ids"]):
            raise ValueError(f"Unresolved pilot: {claim['id']}")
        start, end = (
            claim["temporal_support"]["start"],
            claim["temporal_support"]["end"],
        )
        if start and end and start > end:
            raise ValueError("Reversed claim interval")
    selectors = set()
    for profile in profiles.values():
        if profile["pilot_id"] not in pilots:
            raise ValueError("Unresolved profile pilot")
        selector = (
            profile["pilot_id"],
            profile["crop_id"],
            profile["production_system"],
        )
        if selector in selectors:
            raise ValueError("Ambiguous profile selector")
        selectors.add(selector)
        if (profile["kind"] == "fallow") != (profile["crop_id"] is None):
            raise ValueError("Fallow must remain distinct from a crop")
        if (
            profile["review_status"] == "reviewed"
            and profile["review"]["method"] != "source_desk_review"
        ):
            raise ValueError("Reviewed profile requires a source desk review")
        unknown = []
        for name, fact in profile["parameters"].items():
            if fact["state"] == "unavailable":
                unknown.append(name)
            if fact["state"] == "not_applicable" and not (
                profile["kind"] == "fallow"
                and name in ("scientific_name", "crop_family")
            ):
                raise ValueError(
                    "No not-applicable semantics agreed for this parameter"
                )
            for claim_id in fact["claim_ids"]:
                if claim_id not in claims:
                    raise ValueError(f"Unresolved claim: {claim_id}")
                claim = claims[claim_id]
                if claim["pilot_ids"] and profile["pilot_id"] not in claim["pilot_ids"]:
                    raise ValueError(f"Regional evidence leakage: {claim_id}")
                if (
                    claim["production_systems"]
                    and profile["production_system"] not in claim["production_systems"]
                ):
                    raise ValueError(f"Production-system evidence leakage: {claim_id}")
                if name not in claim["parameter_keys"]:
                    raise ValueError(f"Citation does not support parameter: {name}")
                if (
                    fact["review_status"] == "reviewed"
                    and claim["review_status"] != "reviewed"
                ):
                    raise ValueError("Unreviewed evidence promoted to reviewed")
                if (
                    profile["review_status"] != "synthetic"
                    and claim["evidence_kind"] == "synthetic"
                ):
                    raise ValueError("Synthetic evidence in a real reference profile")
            if fact["state"] == "available" and name in (
                "planting_window",
                "harvest_window",
            ):
                value = fact["value"]
                for bound in ("start", "end"):
                    if value[bound] is not None:
                        month_day(value[bound])
                if value["start"] and value["end"]:
                    wraps = value["start"] > value["end"]
                    if value["crosses_year"] != wraps:
                        raise ValueError(
                            "Calendar window crosses_year disagrees with month/day bounds"
                        )
            if fact["state"] == "available" and name == "soil_temperature_guidance":
                depth = fact["value"]["depth_cm"]
                if depth and depth["top"] > depth["bottom"]:
                    raise ValueError("Reversed soil depth")
            if fact["state"] == "available" and name in (
                "duration_days",
                "air_temperature_limits",
                "soil_depth_cm",
                "crop_coefficients",
            ):
                lower, upper = fact["value"]["min"], fact["value"]["max"]
                if lower is None and upper is None:
                    raise ValueError("Available range needs at least one bound")
                if lower is not None and upper is not None and lower > upper:
                    raise ValueError("Reversed parameter bounds")
                if name != "air_temperature_limits" and any(
                    v is not None and (v < 0 or (name == "duration_days" and v == 0))
                    for v in (lower, upper)
                ):
                    raise ValueError("Invalid nonnegative/positive parameter bound")
        if sorted(unknown) != sorted(profile["unknown_properties"]):
            raise ValueError(
                "Unknown-property inventory differs from unavailable facts"
            )
    for pilot in pilots.values():
        expected = sorted(
            p["id"] for p in profiles.values() if p["pilot_id"] == pilot["id"]
        )
        if sorted(pilot["profile_ids"]) != expected:
            raise ValueError("Pilot/profile inventory mismatch")
    return catalog


def build(root=ROOT):
    return validate(
        {
            "schema_version": VERSION,
            "catalog_version": "0.1.0",
            "contract_status": "proposed_pending_7e_review",
            "release_date": "2026-11-14",
            "recommendation_eligible": False,
            "sources": read_json(root / INPUTS[0]),
            "claims": read_json(root / INPUTS[1]),
            "profiles": read_json(root / INPUTS[2]),
            "pilots": read_json(root / INPUTS[3]),
        },
        root,
    )


def audit(catalog, root=ROOT):
    paths = (
        *INPUTS,
        "evidence/captures.json",
        "evidence/http-retrieval-audit.json",
        "catalog.schema.json",
        "catalog.json",
        "fixtures/pilot-cases.json",
    )
    return {
        "schema_version": "earthsync.crop-knowledge-audit.v1",
        "catalog_version": catalog["catalog_version"],
        "checksums": {
            p: {
                "sha256": sha256((root / p).read_bytes()),
                "bytes": (root / p).stat().st_size,
            }
            for p in paths
        },
        "checksum_scope": "Exact repository artifact bytes; never original provider response bytes.",
        "counts": {
            key: len(catalog[key])
            for key in ("sources", "claims", "profiles", "pilots")
        },
        "reviewed_profile_ids": [
            p["id"] for p in catalog["profiles"] if p["review_status"] == "reviewed"
        ],
        "unavailable_parameters": {
            p["id"]: p["unknown_properties"] for p in catalog["profiles"]
        },
        "recommendation_eligible": False,
    }


def lookup(catalog, pilot_id, crop_id, production_system):
    """A pilot ID is a caller-selected research scope, never inferred farm location."""
    matches = [
        p
        for p in catalog["profiles"]
        if (p["pilot_id"], p["crop_id"], p["production_system"])
        == (pilot_id, crop_id, production_system)
    ]
    return {
        "schema_version": VERSION,
        "state": "available" if matches else "unavailable",
        "profile": matches[0] if matches else None,
        "recommendation_eligible": False,
        "limitation": "Regional reference lookup only; confirmed farm applicability and 7E approval are required.",
    }


def pilot_cases(catalog):
    return {
        "schema_version": "earthsync.pilot-reference-cases.v1",
        "data_kind": "reference_only",
        "cases": [
            {
                "id": f"{p['id']}_reference",
                "pilot_id": p["id"],
                "profile_ids": p["profile_ids"],
                "user_approximate_location": None,
                "farmer_confirmed_farm": None,
                "field_photo": None,
                "environmental_evidence": {
                    "state": "unavailable",
                    "kind": "unavailable",
                    "value": None,
                    "unit": None,
                    "dates": None,
                    "spatial_support": None,
                    "source_refs": [],
                    "quality": "No field or environmental observations were collected.",
                },
                "expected_recommendation_state": "insufficient_information",
            }
            for p in catalog["pilots"]
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("build", "check", "lookup"))
    parser.add_argument("--pilot")
    parser.add_argument("--crop")
    parser.add_argument("--system")
    args = parser.parse_args()
    catalog = build()
    if args.command == "lookup":
        if not all((args.pilot, args.crop, args.system)):
            parser.error("lookup requires --pilot, --crop and --system")
        print(
            encoded(lookup(catalog, args.pilot, args.crop, args.system)).decode(),
            end="",
        )
        return
    outputs = {
        "catalog.json": encoded(catalog),
        "fixtures/pilot-cases.json": encoded(pilot_cases(catalog)),
    }
    if args.command == "build":
        for path, data in outputs.items():
            (ROOT / path).write_bytes(data)
        (ROOT / "audit.json").write_bytes(encoded(audit(catalog)))
    else:
        for path, data in outputs.items():
            if (ROOT / path).read_bytes() != data:
                raise ValueError(f"Generated artifact drift: {path}")
        if read_json(ROOT / "audit.json") != audit(catalog):
            raise ValueError("Audit/checksum drift")
    print(
        f"{args.command}: {len(catalog['profiles'])} profiles, {len(catalog['sources'])} sources; recommendation eligibility false"
    )


if __name__ == "__main__":
    main()
