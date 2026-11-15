"""Synthetic sensitive inputs must not enter public verification receipts."""

import importlib.util
import json
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "release_evidence_summary", ROOT / "scripts/summarize_release_evidence.py"
)
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)
spec2 = importlib.util.spec_from_file_location(
    "release_privacy", ROOT / "scripts/release_privacy.py"
)
privacy = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(privacy)


def test_comparison_receipt_omits_private_fields_and_identifiers(tmp_path):
    ident = "12345678-1234-1234-1234-123456789abc"
    source = tmp_path / "saved-comparison.json"
    source.write_text(
        json.dumps(
            {
                "id": ident,
                "farm_id": ident,
                "confirmed_point": {"latitude": 12.345678, "longitude": 98.765432},
                "alternative_decision_ids": [ident, ident],
                "baseline_declared_existing_plan": True,
                "priorities": ["less_water"],
                "chosen_decision_id": ident,
                "recommendation_eligible": False,
            }
        )
    )
    public = summary.summary(source, "browser-final/saved-comparison.json")
    text = json.dumps(public)
    assert ident not in text and "12.345678" not in text and "98.765432" not in text
    assert public["strategy_count"] == 3 and public["farmer_choice"] == "selected"
    assert public["private_field_data_omitted"]


def test_free_text_with_private_identifier_is_rejected(tmp_path):
    source = tmp_path / "results.json"
    source.write_text(
        json.dumps(
            {
                "steps": [
                    {
                        "step": "12345678-1234-1234-1234-123456789abc",
                        "classification": "SYNTHETIC",
                    }
                ]
            }
        )
    )
    with pytest.raises(ValueError, match="Private field data"):
        summary.summary(source, "browser-final/results.json")


def test_raw_browser_output_cannot_be_source_or_shared_tmp(tmp_path):
    for path in [ROOT, ROOT / "docs/release/evidence", Path("/tmp")]:
        with pytest.raises(ValueError, match="dedicated private directory"):
            privacy.private_output(path)
    destination = privacy.private_output(tmp_path / "private-browser")
    if sys.platform != "win32":
        assert destination.stat().st_mode & 0o077 == 0


def test_symlinked_raw_artifact_is_rejected(tmp_path):
    if sys.platform == "win32":
        pytest.skip("Symlink creation privilege is not assumed on Windows")
    raw = tmp_path / "raw"
    raw.mkdir()
    source = tmp_path / "private.json"
    source.write_text("{}")
    (raw / "results.json").symlink_to(source)
    with pytest.raises(ValueError, match="Symlink"):
        summary.publish(raw, tmp_path / "public")
