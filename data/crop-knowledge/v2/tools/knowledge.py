"""Offline reference lookup, graph validation and deliberately non-executable v0.3 export."""

import argparse
from datetime import date
import hashlib
import json
import math
from pathlib import Path
import re

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
VERSION = "earthsync.crop-knowledge.v2-reference"
SYSTEMS = {
    "flooded_irrigated_lowland": "flooded_lowland",
    "rainfed_lowland": "rainfed",
    "rainfed_upland": "rainfed",
    "rainfed": "rainfed",
    "irrigated_upland": "irrigated",
    "dryland": "dryland",
}
PARAMETERS = [
    "planting_window",
    "harvest_window",
    "growing_duration",
    "ecological_temperature",
    "daily_extreme_temperature",
    "growing_degree_days",
    "annual_precipitation",
    "growing_period_rainfall",
    "water_demand",
    "et0_method",
    "kc_stages",
    "drought_tolerance",
    "flooding_tolerance",
    "stage_vulnerabilities",
    "ecological_soil_ph",
    "soil_ph_by_depth",
    "soil_texture",
    "soil_drainage",
    "ecological_soil_depth",
    "irrigation_requirements",
    "flooded_management",
    "succession",
    "crop_history_relationships",
    "altitude",
    "ecological_crop_cycle",
    "climate_zone",
]
BLOCKS = {
    "planting_window": (
        "planting_window",
        "Advisory regional calendar is not an independently accepted permitted planting window.",
    ),
    "harvest_window": (
        None,
        "v0.3 plans require caller-declared dates; no harvest-window requirement exists.",
    ),
    "growing_duration": (
        "duration",
        "Cultivar/establishment and inclusive-day convention are unverified; reference only.",
    ),
    "ecological_temperature": (
        "temperature",
        "Ecological temperature statistic does not establish bounds for every daily Tmin/Tmax.",
    ),
    "daily_extreme_temperature": (
        "temperature",
        "No accepted daily-extreme requirement supplied.",
    ),
    "growing_degree_days": (
        "growing_degree_days",
        "No accepted crop-specific base and uncapped GDD bounds.",
    ),
    "annual_precipitation": (
        "growing_period_rainfall",
        "Annual precipitation cannot be converted to growing-period rain or ETc.",
    ),
    "growing_period_rainfall": (
        "growing_period_rainfall",
        "No independently accepted inclusive growing-period precipitation requirement.",
    ),
    "water_demand": (
        "crop_evapotranspiration",
        "Generic water descriptions do not provide daily ET0 or stage Kc.",
    ),
    "et0_method": (
        "crop_evapotranspiration",
        "Method reference is not validated, aligned daily reference ET0 evidence.",
    ),
    "kc_stages": (
        "crop_evapotranspiration",
        "General FAO-56 coefficients lack locally accepted stages/adjustments and daily ET0.",
    ),
    "ecological_soil_ph": (
        "soil_numeric",
        "Ecological pH lacks measurement method, sampling depth and accepted local applicability.",
    ),
    "soil_ph_by_depth": (
        "soil_numeric",
        "No accepted depth/method-specific crop requirement.",
    ),
    "soil_texture": (
        "soil_category",
        "Provider qualitative classes are not an accepted engine category vocabulary.",
    ),
    "soil_drainage": (
        "soil_category",
        "Reference drainage class is not confirmed farm drainage or an accepted rule.",
    ),
    "ecological_soil_depth": (
        None,
        "Ecological rooting/soil-depth class is not a soil observation sampling interval.",
    ),
    "irrigation_requirements": (
        "irrigation_required",
        "System label or drought tolerance cannot establish irrigation availability or adequacy.",
    ),
    "flooded_management": (
        "flooded_management",
        "No accepted management category; flooded practices cannot be applied to upland rice.",
    ),
    "succession": (
        "succession",
        "No accepted predecessor/fallow restriction or complete attributed field history.",
    ),
    "crop_history_relationships": (
        "succession",
        "Rotation reference does not establish farm predecessor, nitrogen credit or pest benefit.",
    ),
}


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result

    return json.loads(
        Path(path).read_text(encoding="utf-8"),
        object_pairs_hook=unique,
        parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")),
    )


def encoded(value):
    return (
        json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    ).encode("utf-8")


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def index(records):
    result = {}
    for record in records:
        if record["id"] in result:
            raise ValueError("duplicate ID: " + record["id"])
        result[record["id"]] = record
    return result


def check_window(value):
    for key in ["first_mmdd", "last_mmdd"]:
        number = value[key]
        date(2000, number // 100, number % 100)
    if (
        value["wraps_year"] != (value["first_mmdd"] > value["last_mmdd"])
        or value["advisory"] is not True
    ):
        raise ValueError("calendar meaning changed")


def validate(data, root=ROOT):
    def finite(value):
        if isinstance(value, float) and not math.isfinite(value):
            raise ValueError("nonfinite reference value")
        if isinstance(value, dict):
            if (
                set(value) == {"min", "max"}
                and all(isinstance(value[k], (int, float)) for k in ["min", "max"])
                and value["min"] > value["max"]
            ):
                raise ValueError("reversed numeric bounds")
            for child in value.values():
                finite(child)
        elif isinstance(value, list):
            for child in value:
                finite(child)

    finite(data)
    Draft202012Validator(
        read_json(root / "catalog.schema.json"), format_checker=FormatChecker()
    ).validate(data)
    sources, claims, crops, profiles = (
        index(data[k]) for k in ["sources", "claims", "crops", "profiles"]
    )
    versions = data["dataset_versions"]
    receipts = index(read_json(root / "evidence/retrieval-receipts.json"))
    for source in sources.values():
        publication, precision = (
            source["publication_date"],
            source["publication_date_precision"],
        )
        if precision == "unknown":
            if publication is not None:
                raise ValueError("unknown publication precision requires null date")
        elif publication is None:
            raise ValueError("known publication precision requires a date")
        elif precision == "day":
            date.fromisoformat(publication)
        elif precision == "month":
            date.fromisoformat(publication + "-01")
        elif precision == "year":
            date(int(publication), 1, 1)
        if source["retrieval_date"] is not None:
            date.fromisoformat(source["retrieval_date"])
        if (
            source["dataset_id"] not in versions
            or source["version"] != versions[source["dataset_id"]]
        ):
            raise ValueError("unregistered dataset version")
        if not re.match(r"https://[^/]+/", source["url"]):
            raise ValueError("source must identify an HTTPS resource")
        if source["id"] in receipts:
            receipt = receipts[source["id"]]
            if (source["url"], source["response_sha256"]) != (
                receipt["url"],
                receipt["sha256"],
            ):
                raise ValueError("source identity differs from retrieval receipt")
        if source["original_file"]:
            path = (root / source["original_file"]).resolve()
            if (
                not path.is_relative_to(root.resolve())
                or digest(path) != source["response_sha256"]
            ):
                raise ValueError("source original hash mismatch")
    for claim in claims.values():
        source = sources.get(claim["source_id"])
        if source is None or claim["source_version"] != source["version"]:
            raise ValueError("dangling source or source version mismatch")
        if any(
            s not in sources
            or sources[s]["access_status"]
            not in {"captured", "web_reviewed", "inherited_7j_review"}
            for s in claim["supporting_source_ids"]
        ):
            raise ValueError("invalid supporting source")
        if source["access_status"] not in {
            "captured",
            "web_reviewed",
            "inherited_7j_review",
        }:
            raise ValueError("unavailable source cannot support a claim")
        if claim["crop_id"] is not None and claim["crop_id"] not in crops:
            raise ValueError("dangling claim crop")
        if not claim["locator"].strip() or not claim["limitations"]:
            raise ValueError("claim needs locator and limitations")
    aliases = {}
    for crop in crops.values():
        claim = claims.get(crop["identity_claim_id"])
        if (
            claim is None
            or claim["crop_id"] != crop["id"]
            or claim["parameter"] != "identity"
        ):
            raise ValueError("unsourced crop identity")
        if (
            crop["scientific_name"] != claim["value"]["scientific_name"]
            or crop["aliases"] != claim["value"]["aliases"]
            or crop["family"] != claim["value"]["family"]
        ):
            raise ValueError("identity differs from source claim")
        if not crop["agricultural_basis"] or not crop["categories"]:
            raise ValueError("crop needs positive agricultural classification")
        for alias in [crop["scientific_name"], *crop["aliases"]]:
            key = alias.casefold().strip()
            aliases.setdefault(key, set()).add(crop["id"])
    scientific = [c["scientific_name"].casefold() for c in crops.values()]
    if len(scientific) != len(set(scientific)):
        raise ValueError("duplicate species identity")
    for profile in profiles.values():
        if profile["crop_id"] not in crops or set(profile["parameters"]) != set(
            PARAMETERS
        ):
            raise ValueError("profile crop or parameter inventory mismatch")
        for key, parameter in profile["parameters"].items():
            if parameter["state"] == "unknown":
                if (
                    parameter["value"] is not None
                    or parameter["claim_ids"]
                    or not parameter["missing_reason"]
                ):
                    raise ValueError("unknown value must remain null with reason")
                continue
            if (
                parameter["value"] is None
                or not parameter["claim_ids"]
                or parameter["missing_reason"] is not None
            ):
                raise ValueError("populated parameter needs evidence")
            for claim_id in parameter["claim_ids"]:
                claim = claims.get(claim_id)
                if (
                    claim is None
                    or claim["crop_id"] not in {None, profile["crop_id"]}
                    or claim["parameter"] != key
                ):
                    raise ValueError("claim does not support this crop/parameter")
                for context in ["region_id", "production_system", "cultivar"]:
                    if (
                        claim[context] is not None
                        and claim[context] != profile[context]
                    ):
                        raise ValueError("claim applicability mismatch: " + context)
                if (
                    claim["evidence_kind"] == "ecological_descriptor"
                    and profile["region_id"] is not None
                ):
                    raise ValueError(
                        "global ecology cannot establish regional applicability"
                    )
                for semantic in [
                    "unit",
                    "statistic",
                    "value",
                    "temporal_support",
                    "spatial_support",
                    "method",
                ]:
                    if parameter[semantic] != claim[semantic]:
                        raise ValueError(
                            "parameter/claim semantic mismatch: " + semantic
                        )
            if key in {"planting_window", "harvest_window"}:
                check_window(parameter["value"])
            if key in {"ecological_crop_cycle", "growing_duration"}:
                span = parameter["value"]
                if not 0 < span["min"] <= span["max"]:
                    raise ValueError("invalid duration")
        if (
            profile["production_system"]
            in {"rainfed_upland", "upland_water_supply_unspecified"}
            and profile["parameters"]["flooded_management"]["state"] != "unknown"
        ):
            raise ValueError("upland cannot inherit flooded management")
    for rotation in index(data["rotations"]).values():
        previous = None
        for cycle in rotation["cycles"]:
            start, end = (
                date.fromisoformat(cycle["start"]),
                date.fromisoformat(cycle["end"]),
            )
            if end < start or (previous is not None and start <= previous):
                raise ValueError("rotation chronology invalid; never reorder input")
            previous = end
            if cycle["profile_id"] is not None and cycle["profile_id"] not in profiles:
                raise ValueError("unknown rotation profile")
            if cycle["kind"] == "crop" and cycle["crop_id"] not in crops:
                raise ValueError("unknown rotation crop")
            if cycle["kind"] == "fallow" and (
                cycle["crop_id"] is not None or cycle["profile_id"] is not None
            ):
                raise ValueError("fallow is management, not a crop")
            if (
                cycle["profile_id"] is not None
                and profiles[cycle["profile_id"]]["crop_id"] != cycle["crop_id"]
            ):
                raise ValueError("rotation crop/profile mismatch")
        if any(c not in claims for c in rotation["claim_ids"]):
            raise ValueError("rotation has invalid claim")
    return {
        "crops": len(crops),
        "profiles": len(profiles),
        "claims": len(claims),
        "sources": len(sources),
        "rotations": len(data["rotations"]),
        "ambiguous_aliases": sum(len(v) > 1 for v in aliases.values()),
        "executable_requirements": 0,
        "recommendation_eligible": False,
    }


def verify_integrity(root=ROOT):
    manifest = read_json(root / "integrity.json")
    for record in manifest["files"]:
        path = (root / record["path"]).resolve()
        if not path.is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError("missing or invalid integrity path")
        if path.stat().st_size != record["bytes"] or digest(path) != record["sha256"]:
            raise ValueError("artifact hash mismatch: " + record["path"])


def load(root=ROOT):
    verify_integrity(root)
    data = read_json(root / "catalog.json")
    validate(data, root)
    return data


def lookup(data, query, region=None, system=None, cultivar=None):
    # Exact identity/alias lookup. Ambiguity is explicit; no fuzzy/cultivar substitution.
    matched = [
        c
        for c in data["crops"]
        if query == c["id"]
        or query.casefold()
        in {x.casefold() for x in [c["scientific_name"], *c["aliases"]]}
    ]
    if len(matched) != 1:
        return {
            "status": "ambiguous" if matched else "unavailable",
            "matches": [c["id"] for c in matched],
            "profiles": [],
        }
    crop = matched[0]
    profiles = [
        p
        for p in data["profiles"]
        if p["crop_id"] == crop["id"]
        and (region is None or p["region_id"] == region)
        and (system is None or p["production_system"] == system)
        and (cultivar is None or p["cultivar"] == cultivar)
    ]
    return {
        "status": "reference_only" if profiles else "identity_only",
        "crop": crop,
        "profiles": profiles,
        "recommendation_eligible": False,
        "reason": "Reference evidence only; no nearest-region or cultivar fallback.",
    }


def mapping_report(profile):
    return [
        {
            "profile_id": profile["id"],
            "parameter": key,
            "claim_ids": p["claim_ids"],
            "proposed_condition": BLOCKS.get(
                key,
                (
                    None,
                    "No exact v0.3 requirement represents this qualitative reference.",
                ),
            )[0],
            "status": "blocked",
            "reason": p["missing_reason"]
            if p["state"] == "unknown"
            else BLOCKS.get(key, (None, "No accepted v0.3 rule mapping."))[1],
        }
        for key, p in profile["parameters"].items()
    ]


def project(data, profile_id, region, system, cultivar=None):
    validate(data)
    profile = index(data["profiles"])[profile_id]
    if (profile["region_id"], profile["production_system"], profile["cultivar"]) != (
        region,
        system,
        cultivar,
    ):
        raise ValueError("exact region/system/cultivar required")
    if system not in SYSTEMS:
        raise ValueError("production system has no reviewed identity-only mapping")
    if "IDENTITY DISPUTED" in profile["source_context"]:
        raise ValueError("unresolved crop identity blocks mapping")
    crop = index(data["crops"])[profile["crop_id"]]
    claim_ids = {
        crop["identity_claim_id"],
        *(c for p in profile["parameters"].values() for c in p["claim_ids"]),
    }
    claims = [c for c in data["claims"] if c["id"] in claim_ids]
    source_ids = {
        s for c in claims for s in [c["source_id"], *c["supporting_source_ids"]]
    }
    return {
        "profile": {
            "id": profile_id,
            "crop_id": crop["id"],
            "family": crop["family"],
            "cultivar": cultivar,
            "system": SYSTEMS[system],
            "approved_for_candidates": False,
            "review": "reference_only",
            "rules": [],
        },
        "sidecar": {
            "profile": profile,
            "crop": crop,
            "claims": claims,
            "sources": [s for s in data["sources"] if s["id"] in source_ids],
            "catalog_sha256": hashlib.sha256(encoded(data)).hexdigest(),
            "identity_claim_id": crop["identity_claim_id"],
            "blocked_conversions": mapping_report(profile),
            "recommendation_eligible": False,
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    sub.add_parser("gaps")
    sub.add_parser("sources")
    listing = sub.add_parser("list")
    listing.add_argument("--category")
    trace = sub.add_parser("trace")
    trace.add_argument("profile")
    trace.add_argument("--parameter", required=True, choices=PARAMETERS)
    search = sub.add_parser("lookup")
    search.add_argument("crop")
    search.add_argument("--region")
    search.add_argument("--system")
    search.add_argument("--cultivar")
    export = sub.add_parser("export-v03")
    export.add_argument("profile")
    export.add_argument("--region", required=True)
    export.add_argument("--system", required=True)
    export.add_argument("--cultivar")
    args = parser.parse_args()
    data = load()
    if args.command == "check":
        result = validate(data)
    elif args.command == "lookup":
        result = lookup(data, args.crop, args.region, args.system, args.cultivar)
    elif args.command == "export-v03":
        result = project(data, args.profile, args.region, args.system, args.cultivar)
    elif args.command == "sources":
        result = data["sources"]
    elif args.command == "list":
        result = [
            c
            for c in data["crops"]
            if args.category is None or args.category in c["categories"]
        ]
    elif args.command == "trace":
        profile = index(data["profiles"])[args.profile]
        parameter = profile["parameters"][args.parameter]
        claims = [index(data["claims"])[c] for c in parameter["claim_ids"]]
        result = {
            "profile_id": args.profile,
            "parameter": parameter,
            "claims": claims,
            "sources": [
                index(data["sources"])[s]
                for s in sorted(
                    {
                        s
                        for c in claims
                        for s in [c["source_id"], *c["supporting_source_ids"]]
                    }
                )
            ],
            "proposed_rule": next(
                r for r in mapping_report(profile) if r["parameter"] == args.parameter
            ),
        }
    else:
        result = read_json(ROOT / "missing-parameters.json")
    print(encoded(result).decode(), end="")


if __name__ == "__main__":
    main()
