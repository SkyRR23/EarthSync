"""7V review findings, never a Rust rule registry or an approval mechanism."""

import copy
import json
from pathlib import Path

REVIEW = json.loads(
    Path(__file__).with_name("rule_review.json").read_text(encoding="utf-8")
)
if (
    REVIEW["executable_rule_count"] != 0
    or len(REVIEW["candidates"]) != 60
    or any(
        c["execution_status"] != "blocked"
        or c["recommendation_eligible"] is not False
        or c["approved_for_candidates"] is not False
        or c["review"]["applicable_rule_independently_reviewed"] is not False
        for c in REVIEW["candidates"]
    )
):
    raise ValueError("7V findings sidecar must remain entirely non-executable")


def review_for(crop_id):
    return {
        **copy.deepcopy({k: v for k, v in REVIEW.items() if k != "candidates"}),
        "status": "blocked_or_not_independently_reviewed",
        "candidates": copy.deepcopy(
            [c for c in REVIEW["candidates"] if c["crop_id"] == crop_id]
        ),
    }
