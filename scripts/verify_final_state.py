"""Compare exact final farmer-journey data through restarted loopback APIs.

Baseline contains only hashes/counts. Source bodies and tokens are not printed.
"""

import argparse
import hashlib
import json
from pathlib import Path
import httpx

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("command", choices=["snapshot", "verify"])
p.add_argument("--evidence", type=Path, required=True)
p.add_argument("--baseline", type=Path, required=True)
p.add_argument("--receipt", type=Path)
p.add_argument("--workspace", type=Path, required=True)
a = p.parse_args()
base = "http://127.0.0.1:8021/api/platform/v1"


def digest(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


farm = json.loads((a.evidence / "farm.json").read_text())["id"]
with httpx.Client(trust_env=False, timeout=30) as c:

    def get(path):
        r = c.get(base + path)
        assert r.status_code == 200, (path, r.status_code)
        return r.json()

    assert get("/ready")["ready"]
    docs = {
        name: get("/farms/" + farm + "/" + name)
        for name in [
            "journal",
            "comparisons",
            "decisions",
            "timeline",
            "intelligence",
            "photos",
        ]
    }
    group = json.loads((a.evidence / "saved-comparison.json").read_text())
    assert group in docs["comparisons"]
    observation = json.loads((a.evidence / "observation.json").read_text())
    assert observation in docs["journal"]
    photo = json.loads((a.evidence / "synthetic-photo.json").read_text())["id"]
    raw = c.get(base + f"/farms/{farm}/photos/{photo}/image")
    assert raw.status_code == 200
    state = {
        "documents": {
            name: {"sha256": digest(value), "count": len(value)}
            for name, value in docs.items()
        },
        "sanitized_photo_sha256": hashlib.sha256(raw.content).hexdigest(),
    }
    workspace_photo = json.loads(
        (a.evidence.parent / "workspace-photo-auth.json").read_text()
    )
    token = (a.workspace / "workspace-token.txt").read_text().strip()
    workspace_url = (
        "http://127.0.0.1:8091/api/evidence/v1/photos/"
        + workspace_photo["id"]
        + "/image"
    )
    original_image = c.get(workspace_url, headers={"Authorization": "Bearer " + token})
    assert original_image.status_code == 200
    image_hash = hashlib.sha256(original_image.content).hexdigest()
    assert image_hash == workspace_photo["image_sha256"]
    assert c.get(workspace_url).status_code == 401
    state["separate_authorized_workspace_image_sha256"] = image_hash
    for headers in [
        {"Host": "untrusted.example"},
        {"Origin": "https://untrusted.example"},
    ]:
        assert c.get(base + "/farms", headers=headers).status_code == 403
    if a.command == "snapshot":
        assert not a.baseline.exists(), "Preserve prior baseline"
        a.baseline.write_text(json.dumps(state, indent=2) + "\n")
    else:
        assert state == json.loads(a.baseline.read_text()), (
            "Persisted HTTP data changed"
        )
        assert a.receipt and not a.receipt.exists()
        a.receipt.write_text(
            json.dumps(
                {
                    "status": "PASS",
                    "classification": "SYNTHETIC farm records; CACHED REAL source lineage",
                    "exact_saved_comparison_journal_decisions_timeline_sources_and_photo": True,
                    "host_origin_rejected": True,
                    "state": state,
                },
                indent=2,
            )
            + "\n"
        )
    print(
        "PASS: exact comparison, journal, decisions, timeline, sources, photo and Host/Origin rejection; "
        + a.command
    )
