"""Build and validate a non-executable scientific review sidecar, offline."""

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[2]
UPSTREAM = REPO / "data/crop-knowledge/v2"
BASE_SHA = "940a8aad62da8b188cdd3af4d200f353d907997a"
VERSION = "earthsync.crop-rule-candidates.v1"


def read(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON key: " + key)
            result[key] = value
        return result

    def nonfinite(value):
        raise ValueError("Nonfinite JSON: " + value)

    return json.loads(
        Path(path).read_text(encoding="utf-8"),
        object_pairs_hook=unique,
        parse_constant=nonfinite,
    )


def encoded(value):
    return (
        json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    ).encode()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def upstream():
    spec = importlib.util.spec_from_file_location(
        "earthsync_7p_knowledge", UPSTREAM / "tools/knowledge.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.load()


def check_pins():
    pins = read(ROOT / "input-pins.json")
    if pins["upstream_sha"] != BASE_SHA:
        raise ValueError("Wrong upstream pin")
    for name, expected in pins["files"].items():
        path = (REPO / name).resolve()
        if not path.is_relative_to(REPO) or digest(path) != expected:
            raise ValueError("Pinned input changed: " + name)


def generate():
    check_pins()
    catalog = upstream()  # Includes complete 7P graph, original-byte and schema checks.
    review = read(ROOT / "review.json")
    facts = read(ROOT / "facts.json")
    sources = read(ROOT / "sources.json")
    receipts = read(ROOT / "source-receipts.json")
    if review["upstream_sha"] != BASE_SHA:
        raise ValueError("Review base changed")
    claims = {c["id"]: c for c in catalog["claims"]}
    verified = set(review["verified_upstream_claim_ids"])
    if not verified <= claims.keys():
        raise ValueError("Unresolved verified claim")
    source_ids = {s["id"] for s in sources}
    if len(source_ids) != len(sources) or len({f["id"] for f in facts}) != len(facts):
        raise ValueError("Duplicate source/fact ID")
    receipt_map = {r["id"]: r for r in receipts}
    for source in sources:
        receipt = receipt_map[source["receipt_id"]]
        if receipt["status"] != 200 or receipt["url"] != source["url"]:
            raise ValueError("Unsuccessful/mismatched source receipt")
    for fact in facts:
        if fact["source_id"] not in source_ids:
            raise ValueError("Unresolved fact source")
        if (
            fact["source_fact_status"] != "verified"
            or fact["independent_applicability_status"] != "not_approved"
            or fact["needs_agronomist_field_validation"] is not True
            or not fact["locator"]
            or not fact["limitations"]
        ):
            raise ValueError("Fact review boundary changed")

    candidates = []
    for crop, eco_id in review["crops"].items():
        crop_id = f"ecocrop.{eco_id}@1"
        profiles = [p for p in catalog["profiles"] if p["crop_id"] == crop_id]
        for domain, policy in review["domains"].items():
            links = [
                {"profile_id": p["id"], "parameter": key}
                for p in profiles
                for key in policy["parameters"]
            ]
            claim_ids = sorted(
                {
                    claim
                    for p in profiles
                    for key in policy["parameters"]
                    for claim in p["parameters"][key]["claim_ids"]
                }
            )
            fact_ids = []
            if domain == "kc_curve":
                fact_ids = [
                    crop + ".kc",
                    "method.etc",
                    "method.curve",
                    "method.group_initial",
                ]
            elif domain == "stage_duration":
                fact_ids = [
                    f["id"] for f in facts if f["id"].startswith(crop + ".stage.")
                ]
            elif domain == "growing_duration" and crop == "groundnut":
                fact_ids = ["groundnut.erect"]
            elif domain == "drought_stage_sensitivity" and crop in {
                "rice",
                "maize",
                "groundnut",
            }:
                fact_ids = [crop + ".water_sensitivity"]
            elif domain == "succession":
                rotation_claims = {
                    "rice": ["rotation.rice_mung", "rotation.rice_groundnut"],
                    "mung_bean": ["rotation.rice_mung"],
                    "groundnut": [
                        "rotation.rice_groundnut",
                        "rotation.groundnut_cereal",
                    ],
                    "maize": ["rotation.groundnut_cereal"],
                    "sesame": [],
                }
                claim_ids = sorted(set(claim_ids + rotation_claims[crop]))
                if crop in {"rice", "mung_bean", "groundnut"}:
                    fact_ids.append("rotation.lowland")
                if crop in {"maize", "groundnut"}:
                    fact_ids.append("rotation.cereal")
            evidence_count = len(claim_ids) + len(fact_ids)
            checked = len(verified & set(claim_ids)) + len(fact_ids)
            fact_status = (
                "unsupported"
                if not evidence_count
                else "verified"
                if checked == evidence_count
                else "partially_verified"
                if checked
                else "not_independently_rechecked"
            )
            candidates.append(
                {
                    "id": f"7v.{crop}.{domain}@1",
                    "crop_id": crop_id,
                    "domain": domain,
                    "target_condition": policy["target_condition"],
                    "proposed_requirement": None,
                    "profile_parameter_links": links,
                    "claim_ids": claim_ids,
                    "fact_ids": fact_ids,
                    "scope_policy": "Retain each evidence item's geographic, system and cultivar scope; no union, intersection or cross-profile inheritance establishes applicability.",
                    "review": {
                        "source_fact": fact_status,
                        "method_numerically_verified": domain == "kc_curve",
                        "applicable_rule_independently_reviewed": False,
                        "needs_agronomist_field_validation": True,
                        "unsupported": evidence_count == 0,
                        "independent_review_status": "desk_review_complete_execution_blocked",
                        "reviewer": review["reviewer"],
                        "reviewed_on": review["reviewed_on"],
                        "agronomist_reviewer": None,
                    },
                    "execution_status": "blocked",
                    "recommendation_eligible": False,
                    "approved_for_candidates": False,
                    "block_reason": policy["reason"],
                    "required_evidence": policy["required_evidence"],
                    "contradictions_and_limits": review["crop_notes"][crop],
                    "uncertainty": "Local applicability and error are unquantified. Source envelopes/alternatives are not confidence intervals.",
                }
            )
    package = {
        "schema_version": VERSION,
        "content_version": "1.0.0",
        "upstream_sha": BASE_SHA,
        "language": "en",
        "recommendation_eligible": False,
        "approved_for_candidates": False,
        "executable_rules": [],
        "candidates": candidates,
    }
    schema = read(ROOT / "package.schema.json")
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(package)
    expected_crops = {
        "ecocrop." + i + "@1" for i in ["1574", "2175", "2150", "1937", "2199"]
    }
    expected_domains = {
        "planting_window",
        "growing_duration",
        "temperature",
        "growing_period_rainfall",
        "soil_ph",
        "soil_texture",
        "soil_drainage",
        "flood_tolerance",
        "drought_stage_sensitivity",
        "kc_curve",
        "stage_duration",
        "succession",
    }
    if {(c["crop_id"], c["domain"]) for c in candidates} != {
        (crop, domain) for crop in expected_crops for domain in expected_domains
    }:
        raise ValueError("Incomplete or duplicated priority-domain coverage")
    fact_ids = {f["id"] for f in facts}
    for candidate in candidates:
        if not set(candidate["fact_ids"]) <= fact_ids:
            raise ValueError("Unresolved candidate fact")
    for fact in facts:
        Draft202012Validator(schema["$defs"]["fact"]).validate(fact)

    # Cover all 75 profiles, including nonpriority research contexts, without claiming
    # that each of the 1,950 parameter slots received a new primary-source review.
    trace = []
    for row in read(UPSTREAM / "mapping-report.json"):
        ids = [
            c["id"]
            for c in candidates
            if {"profile_id": row["profile_id"], "parameter": row["parameter"]}
            in c["profile_parameter_links"]
        ]
        trace.append(
            {
                "profile_id": row["profile_id"],
                "parameter": row["parameter"],
                "candidate_ids": ids,
                "status": "blocked",
                "scope": "priority_domain_review"
                if ids
                else "inherited_block_outside_priority_domain",
                "proposed_condition": row["proposed_condition"],
                "upstream_block_reason": row["reason"],
                "claim_ids": row["claim_ids"],
            }
        )
    used = sorted({claim for c in candidates for claim in c["claim_ids"]})
    source_map = {s["id"]: s for s in catalog["sources"]}
    evidence = {
        "upstream_sha": BASE_SHA,
        "claims": [claims[claim] for claim in used],
        "sources": [
            source_map[s]
            for s in sorted(
                {
                    s
                    for claim in used
                    for s in [
                        claims[claim]["source_id"],
                        *claims[claim]["supporting_source_ids"],
                    ]
                }
            )
        ],
        "profiles": [
            {
                k: p[k]
                for k in [
                    "id",
                    "crop_id",
                    "region_id",
                    "production_system",
                    "cultivar",
                    "country",
                    "agroecological_zone",
                    "season",
                    "source_context",
                ]
            }
            for p in catalog["profiles"]
            if any(
                link["profile_id"] == p["id"]
                for c in candidates
                for link in c["profile_parameter_links"]
            )
        ],
    }
    blocked = [
        {
            k: c[k]
            for k in [
                "id",
                "target_condition",
                "execution_status",
                "block_reason",
                "required_evidence",
                "contradictions_and_limits",
            ]
        }
        for c in candidates
    ]
    matrix = [
        "# Accepted facts and methods versus blocked execution — v1.0.0",
        "",
        "Accepted means retained as evidence or a numerical method check. Zero executable rules are accepted. No independent agronomist or field approval is claimed.",
        "",
        "| Candidate | Source fact | Method arithmetic | Applicable rule reviewed | Disposition |",
        "| --- | --- | --- | --- | --- |",
        *[
            f"| {c['id']} | {c['review']['source_fact']} | {'verified (synthetic/published example only)' if c['review']['method_numerically_verified'] else 'not established'} | no | blocked; agronomist/field validation needed |"
            for c in candidates
        ],
        "",
        "Exact facts, locators and limitations: `facts.json` and `upstream-evidence.json`. Every existing parameter mapping: `traceability.jsonl`. Each candidate's missing acceptance evidence: `blocked-rules.json`.",
    ]
    return {
        "package.json": encoded(package),
        "upstream-evidence.json": encoded(evidence),
        "blocked-rules.json": encoded(blocked),
        "traceability.jsonl": b"".join(
            (json.dumps(row, ensure_ascii=False, allow_nan=False) + "\n").encode()
            for row in trace
        ),
        "EVIDENCE_MATRIX.md": ("\n".join(matrix) + "\n").encode(),
    }


def build(check=False):
    outputs = generate()
    for name in [
        "review.json",
        "facts.json",
        "sources.json",
        "source-receipts.json",
        "input-pins.json",
        "package.schema.json",
    ]:
        outputs[name] = (ROOT / name).read_bytes()
    manifest = {
        name: hashlib.sha256(body).hexdigest() for name, body in sorted(outputs.items())
    }
    outputs["integrity.json"] = encoded({"schema_version": VERSION, "sha256": manifest})
    for name, body in outputs.items():
        path = ROOT / name
        if check:
            if not path.is_file() or path.read_bytes() != body:
                raise ValueError("Package drift: " + name)
        else:
            path.write_bytes(body)


def load():
    build(check=True)
    return read(ROOT / "package.json")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="Read-only reproducibility/integrity check"
    )
    args = parser.parse_args()
    build(check=args.check)
    print(
        "7V package valid: 60 blocked candidates; zero executable rules; no agronomic approval."
    )
