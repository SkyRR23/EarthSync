"""Verify immutable source packages and reconcile the retained 7W derivative.

No regeneration or rule promotion. Run on every supported checkout platform.
"""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(path.read_bytes())


def verify(root=ROOT):
    v2 = root / "data/crop-knowledge/v2"
    records = read(v2 / "integrity.json")["files"]
    for item in records:
        raw = (v2 / item["path"]).read_bytes()
        assert len(raw) == item["bytes"], item["path"]
        assert hashlib.sha256(raw).hexdigest() == item["sha256"], item["path"]
    v7 = root / "data/crop-rule-candidates/v1"
    hashes = read(v7 / "integrity.json")["sha256"]
    for path, expected in hashes.items():
        assert hashlib.sha256((v7 / path).read_bytes()).hexdigest() == expected, path
    derivative = read(root / "server/earthsync/platform_v1/rule_review.json")
    source = root / derivative["source_path"]
    assert (
        hashlib.sha256(source.read_bytes()).hexdigest()
        == derivative["source_package_sha256"]
    )
    package = read(source)
    assert package["executable_rules"] == []
    assert package["approved_for_candidates"] is False
    assert package["recommendation_eligible"] is False
    originals = {c["id"]: c for c in package["candidates"]}
    assert len(originals) == len(derivative["candidates"]) == 60
    assert {c["id"] for c in derivative["candidates"]} == set(originals)
    for candidate in derivative["candidates"]:
        original = originals[candidate["id"]]
        assert all(original[key] == value for key, value in candidate.items()), (
            candidate["id"]
        )
        assert original["proposed_requirement"] is None
        assert original["execution_status"] == "blocked"
        assert original["review"]["applicable_rule_independently_reviewed"] is False
    return {
        "v2_hashed_files": len(records),
        "7v_hashed_files": len(hashes),
        "blocked_candidates": len(originals),
        "executable_rules": 0,
    }


if __name__ == "__main__":
    print(json.dumps(verify(), indent=2))
