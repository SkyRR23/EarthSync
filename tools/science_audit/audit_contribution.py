"""Inspect the hash-pinned contribution as data; never import or run its code."""

import argparse
import csv
import io
import json
import zipfile
from pathlib import Path

from inventory_zip import digest_file, inventory
from research import (
    quarantine_profile,
    rainfall_normals,
    validate_month_labels,
    validate_quarantine,
)

EXPECTED_SHA256 = "241cdcfac1df62b7608b403e8cbcb48d0b8ba9ca9fddc8cce766279016327788"
PREFIX = "nasa_space_challenges/"
CACHED_ONLY_ECOCROP = {"sunflower"}


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate source JSON key")
        result[key] = value
    return result


def audit(path, previous):
    if digest_file(path) != EXPECTED_SHA256:
        raise ValueError("Original archive checksum mismatch; audit stopped")
    listing = inventory(path, previous)
    with zipfile.ZipFile(path) as archive:

        def read(name):
            return archive.read(PREFIX + name).decode("utf-8-sig")

        def document(name):
            return json.loads(read(name), object_pairs_hook=unique)

        # Every non-build JSON record is structurally parsed, including examples.
        json_members = [
            m
            for m in listing["members"]
            if m["path"].endswith(".json") and "/target/" not in m["path"]
        ]
        for member in json_members:
            json.loads(archive.read(member["path"]), object_pairs_hook=unique)
        crops = document("contracts/data/crop-profiles.v1.json")
        quarantined = []
        for crop in crops["crops"]:
            state = (
                "cached_source_reference_only"
                if crop["crop_id"] in CACHED_ONLY_ECOCROP
                else "source_reviewed_reference_fact"
            )
            item = quarantine_profile(
                crop,
                PREFIX + "contracts/data/crop-profiles.v1.json",
                EXPECTED_SHA256,
                state,
            )
            validate_quarantine(item)
            quarantined.append(item)

        raw_records, normals, label_errors = [], {}, []
        for location in ("hlegu", "bago", "magway"):
            for window in ("baseline", "recent"):
                name = f"contracts/raw/power/{location}_{window}.json"
                raw = document(name)
                raw_records.append(
                    {
                        "member": PREFIX + name,
                        "header": raw["header"],
                        "geometry": raw["geometry"],
                        "parameters": raw["parameters"],
                        "messages": raw.get("messages", []),
                        "request_url": read(name.replace(".json", ".url.txt")).strip(),
                        "retrieved_at": None,
                        "original_fetch_receipt_available": False,
                        "classification": "model_derived_environmental_estimate",
                        "missingness": {
                            key: sum(
                                value is None or value == raw["header"]["fill_value"]
                                for value in values.values()
                            )
                            for key, values in raw["properties"]["parameter"].items()
                        },
                    }
                )
                if window == "recent":
                    normals[location] = rainfall_normals(raw, 2016, 2025)
            rows = list(
                csv.DictReader(
                    io.StringIO(read(f"data-pack/csv/power_climatology_{location}.csv"))
                )
            )
            for index, row in enumerate(rows, 2):
                try:
                    validate_month_labels([row])
                except ValueError as exc:
                    label_errors.append(
                        {
                            "location": location,
                            "row": index,
                            "parameter": row["parameter"],
                            "month": row["month"],
                            "month_name": row["month_name"],
                            "reason": str(exc),
                        }
                    )

        report = {
            "archive_sha256": EXPECTED_SHA256,
            "integrity_verified": True,
            "file_count": sum(m["kind"] == "file" for m in listing["members"]),
            "directory_count": sum(
                m["kind"] == "directory" for m in listing["members"]
            ),
            "generated_build_files_rejected": sum(
                m["category"] == "generated_build_artifact_rejected"
                for m in listing["members"]
            ),
            "pr11_identical_file_count": sum(
                bool(m["same_bytes_in_pr11"]) for m in listing["members"]
            ),
            "nonbuild_json_records_parsed": len(json_members),
            "raw_provider_records": raw_records,
            "climatology_month_label_errors": label_errors,
            "crop_count": len(quarantined),
            "source_reviewed_numeric_reference_count": len(quarantined)
            - len(CACHED_ONLY_ECOCROP),
            "cached_original_source_reference_count": len(CACHED_ONLY_ECOCROP),
            "independently_applicable_executable_rules": 0,
            "recommendation_eligible": False,
            "originals_modified": False,
            "precompiled_artifacts_executed": False,
            "limitations": [
                "All ZIP members hashed and CRC checked. Source/code/documents reviewed separately; generated build artifacts rejected as a class.",
                "ECOCROP source availability and bounded numeric desk review were recorded by the auditor; this script does not independently fetch or approve sources.",
                "Provider-shaped original responses retain metadata but lack original retrieval receipts. Matching a current provider series is not field validation.",
            ],
        }
        fixture = {
            "schema_version": "earthsync.research-quarantine.v1",
            "classification": "research_only",
            "archive_sha256": EXPECTED_SHA256,
            "recommendation_eligible": False,
            "profiles": quarantined,
            "rainfall_normals_reference_only": normals,
        }
        return listing, report, fixture


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--compare", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    previous = json.loads(args.compare.read_text(encoding="utf-8"))
    listing, report, fixture = audit(args.archive, previous)
    args.output.mkdir(parents=True, exist_ok=True)
    for name, value in (
        ("inventory.json", listing),
        ("scientific-review.json", report),
        ("reference-only.json", fixture),
    ):
        (args.output / name).write_text(
            json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n",
            encoding="utf-8",
        )
    print(
        json.dumps(
            {
                k: report[k]
                for k in (
                    "file_count",
                    "directory_count",
                    "generated_build_files_rejected",
                    "pr11_identical_file_count",
                    "crop_count",
                    "independently_applicable_executable_rules",
                )
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
