"""Publish only allowlisted verification metadata; raw field evidence stays private.

Screenshots are copied only from a reviewed, location/identifier-free allowlist.
The original receipts remain available locally and are linked by content hashes.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

UUID = re.compile(
    r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", re.I
)
PUBLIC_PACKAGES = {
    "catalog-integrity.json",
    "ancestry.json",
    "artifact-hashes.json",
    "acceptance-28.json",
}
PUBLIC_JSON = {
    "results.json",
    "farm.json",
    "saved-farm.json",
    "saved-comparison.json",
    "assistant-comparison.json",
    "explicit-reassessment.json",
    "nasa-water-job.json",
    "observation.json",
    "reported-season.json",
    "history-confirmation.json",
    "synthetic-photo.json",
    "acknowledgment.json",
    "offline-public-cache.json",
    "forecast-job.json",
    "soil-map-job.json",
    "gfs-fresh-live.json",
    "soil-webdav-fresh-live.json",
    "recovery-exact-stores.json",
    "restarted-http.json",
    "restored-http.json",
    "workspace-photo-auth.json",
    "state-before-restart.json",
    *(f"strategy-{i}.json" for i in range(6)),
}
PUBLIC_LOGS = {
    "assistant-comparison-regression.log",
    "blocked-rule-integrity.log",
    "blocked-rule-tests.log",
    "catalog-native-tests.log",
    "catalog-reproducibility.log",
    "catalog-science-tests.log",
    "catalog-v1-tests.log",
    "catalog-v2-tests.log",
    "companion-risk-regressions.log",
    "docker-final-build.log",
    "docker-final-smoke.log",
    "final-display-regressions.log",
    "final-ui-regressions.log",
    "flutter-analyze.log",
    "flutter-build.log",
    "flutter-integrated.log",
    "legacy-rust-boundary.log",
    "offline-assets.log",
    "precision-api-regression.log",
    "publication-privacy-tests.log",
    "python-integrated.log",
    "recovery.log",
    "rotation-editor-regression.log",
    "rust-integrated.log",
    "saved-choice-regression.log",
    "source-integrity.log",
    "trait-interpretation-regression.log",
}
SCREENSHOTS = {
    "browser-final/three-strategies-desktop.png",
    "browser-final/three-strategies-phone.png",
    "browser-final/burmese-season.png",
    "browser-crops/two-crop-references.png",
    "browser-crops/cached-crop-references.png",
}
SOURCE_FIELDS = {
    "provider",
    "dataset",
    "unit",
    "resolution_m",
    "grid_spacing_degrees",
    "retrieved_at",
    "model_initialized_at",
    "issued_at",
    "observation_time",
    "usable_for_assessment",
    "status",
    "license",
    "depth_cm",
    "statistic",
    "property",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summary(path, relative):
    raw = json.loads(path.read_text())
    out = {
        "schema_version": "earthsync.public_verification_receipt.v1",
        "raw_receipt_sha256": digest(path),
        "private_field_data_omitted": True,
    }
    if path.name == "results.json":
        for key in [
            "status",
            "steps",
            "passed",
            "resumed_from_saved_native_decisions",
            "farmer_records",
            "ndvi",
            "public_catalog",
            "farmer_choices",
            "api_outage",
            "alias_search_and_two_crop_comparison",
            "cached_original_timestamps",
            "classification",
            "official_alerts",
            "automatic_monitoring",
            "test_scoped_ignore_https_errors",
        ]:
            if key in raw:
                out[key] = raw[key]
        out["browser_error_count"] = len(raw.get("browser_errors", []))
        out["tile_response_count"] = len(raw.get("tile_responses", []))
    elif (
        relative.startswith("browser-final/strategy-")
        or path.name == "explicit-reassessment.json"
    ):
        data = raw["result"].get("data", {})
        out.update(
            native_status=raw["result"]["status"],
            recommendation_eligible=raw["recommendation_eligible"],
            strategy_plan_counts=[
                len(s["plans"]) for s in data.get("context", {}).get("scenarios", [])
            ],
            finding_statuses=sorted({f["status"] for f in data.get("findings", [])}),
            executable_rule_count=sum(
                len(p.get("rules", []))
                for p in data.get("context", {}).get("catalog", [])
            ),
            selected_environmental_snapshot_count=len(
                raw.get("environmental_snapshots", [])
            ),
            selected_farmer_report_count=len(raw.get("farmer_reports", [])),
        )
    elif path.name == "saved-comparison.json":
        out.update(
            strategy_count=1 + len(raw["alternative_decision_ids"]),
            baseline_declared_existing_plan=raw["baseline_declared_existing_plan"],
            priority_count=len(raw["priorities"]),
            farmer_choice="undecided"
            if raw.get("chosen_decision_id") is None
            else "selected",
            recommendation_eligible=raw["recommendation_eligible"],
        )
    elif path.name == "assistant-comparison.json":
        out.update(
            intent=raw["intent"],
            claim_count=len(raw["claims"]),
            decision_count=len(raw["decisions"]),
            citation_count=len(raw["citations"]),
            baseline_explained=any(
                "baseline" in c["text"].lower() for c in raw["claims"]
            ),
            alternative_b_explained=any(
                "Alternative B" in c["text"] for c in raw["claims"]
            ),
        )
    elif "job" in path.name or relative.startswith("live-providers/"):
        result = raw.get("result") or raw
        out["source"] = {key: result[key] for key in SOURCE_FIELDS if key in result}
        out["source_cache_hit"] = result.get("cache_hit")
        out["measurement_record_count"] = len(result.get("records", []))
        out["raster_cell_count"] = len(result.get("cells", []))
    elif "recovery" in path.name or path.name in {
        "restarted-http.json",
        "restored-http.json",
        "workspace-photo-auth.json",
        "state-before-restart.json",
    }:
        for key in [
            "status",
            "classification",
            "originals_unchanged",
            "restored_exact_rows_objects_and_separate_stores",
            "exact_saved_comparison_journal_decisions_timeline_sources_and_photo",
            "host_origin_rejected",
            "unauthorized_status",
            "metadata_stripped",
        ]:
            if key in raw:
                out[key] = raw[key]
        out["private_rows_objects_tokens_and_identifiers_omitted"] = True
    elif path.name == "offline-public-cache.json":
        out.update(
            public_static_resource_count=len(raw["keys"]),
            private_api_cached=raw["private_api_cached"],
        )
    else:
        out["raw_record_type"] = path.stem
        out["classification"] = (
            "SYNTHETIC software-test farmer record; raw data retained privately"
        )
    encoded = json.dumps(out, ensure_ascii=False)
    if UUID.search(encoded) or re.search(
        r'"(?:latitude|longitude|coordinates|confirmed_polygon|farm_id|photo_ids)"\s*:',
        encoded,
    ):
        raise ValueError("Private field data found in public summary: " + relative)
    return out


def publish(raw, output, include_screenshots=False):
    if raw.resolve() != raw.absolute():
        raise ValueError("Symlink not allowed for raw evidence root")
    assert raw.resolve() != output.resolve()
    assert (
        raw.resolve() not in output.resolve().parents
        and output.resolve() not in raw.resolve().parents
    )
    assert Path(__file__).resolve().parents[1] not in raw.resolve().parents
    for path in sorted(raw.rglob("*")):
        if path.is_symlink():
            raise ValueError("Symlink not allowed in raw evidence")
        if not path.is_file():
            continue
        relative = path.relative_to(raw).as_posix()
        if UUID.search(relative):
            raise ValueError("Identifier in artifact path")
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix == ".log" and path.name in PUBLIC_LOGS and path.parent == raw:
            text = path.read_text(errors="strict")
            if UUID.search(text) or re.search(
                r"Bearer\s+\S{20,}|\b(?:latitude|longitude|confirmed_polygon|farm_id|photo_ids)\s*[=:]",
                text,
            ):
                raise ValueError("Private identifier in log: " + relative)
            shutil.copyfile(path, destination)
        elif path.name in PUBLIC_PACKAGES:
            text = path.read_text()
            if UUID.search(text) or re.search(
                r'"(?:latitude|longitude|coordinates|confirmed_polygon|farm_id|photo_ids)"\s*:',
                text,
            ):
                raise ValueError("Private values in package metadata")
            shutil.copyfile(path, destination)
        elif path.suffix == ".json" and path.name in PUBLIC_JSON:
            destination.write_text(
                json.dumps(summary(path, relative), indent=2, ensure_ascii=False) + "\n"
            )
        elif include_screenshots and relative in SCREENSHOTS:
            shutil.copyfile(path, destination)
    (output / "PUBLICATION.md").write_text(
        "Raw field boundaries, coordinates, identifiers, reports, photos and provider responses are kept outside Git. Public JSON files contain allowlisted verification summaries and hashes of private originals. Only reviewed screenshots without field coordinates/identifiers are published. Existing scientific-package hashes and source ancestry are preserved.\n"
    )


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--raw", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument(
        "--include-reviewed-screenshots",
        action="store_true",
        help="Copy only the fixed allowlist after manually reviewing that no field location/identifiers are visible",
    )
    args = p.parse_args()
    publish(args.raw, args.output, args.include_reviewed_screenshots)
    print(
        "Published allowlisted verification metadata; raw field evidence remains private"
    )
