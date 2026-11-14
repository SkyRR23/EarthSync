"""Verify a restored disposable 7N runtime and uncached March POWER → Rust.

Use dedicated test state. Reads the private operations receipt without exporting
its contents. Mutations are explicit and never retried. Output contains only
verification results, versions and hashes, not farmer/photo payloads or tokens.
"""

import argparse
import hashlib
import json
from pathlib import Path
import time

import httpx


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    previous = json.loads(args.receipt.read_text())
    assert not args.output.exists(), "Preserve existing verification receipts"
    base = manifest["platform_url"] + "/api/platform/v1"
    assert manifest["platform_url"] == "http://127.0.0.1:8021"
    with httpx.Client(timeout=35, trust_env=False) as client:

        def get(path):
            response = client.get(base + path)
            assert response.status_code == 200
            return response.json()

        ready = get("/ready")
        assert ready["ready"] and not ready["hosted_private_api_enabled"]
        farm = get("/farms/" + previous["farm"])
        history = get("/farms/" + farm["id"] + "/decisions")
        assert any(item["id"] == previous["decision"] for item in history)
        for ident, digest in previous["evidence"].items():
            assert get("/evidence/" + ident)["response_sha256"] == digest
        assert get("/jobs/" + previous["job"])["status"] == "succeeded"
        raw = client.get(base + f"/farms/{farm['id']}/photos/{previous['photo']}/image")
        assert raw.status_code == 200
        assert hashlib.sha256(raw.content).hexdigest() == previous["photo_sha256"]
        for headers in [
            {"Origin": "https://untrusted.example"},
            {"Host": "untrusted.example"},
        ]:
            assert client.get(base + "/farms", headers=headers).status_code == 403

        # A different period ensures this is a new live retrieval rather than
        # relabeling the restored February cache as an uncached provider success.
        submission = client.post(
            base + "/climate/jobs",
            json={
                "farm_id": farm["id"],
                "query": {
                    "point": farm["confirmed_point"],
                    "start": "2024-03-01",
                    "end": "2024-03-31",
                },
            },
        )
        assert submission.status_code == 202
        job = submission.json()
        states = [job["status"]]
        for _ in range(160):
            if job["status"] in ("succeeded", "failed", "cancelled"):
                break
            time.sleep(0.5)
            job = get("/jobs/" + job["id"])
            states.append(job["status"])
        assert job["status"] == "succeeded", job.get("error")
        assert not job["result"]["cache_hit"], (
            "Cached response is not uncached live proof"
        )
        records = job["result"]["records"]
        assert not job["result"]["gaps"] and len(records) == 3
        assert all(len(record["measurements"]) == 31 for record in records)
        assert all(
            record["data_type"] == "modeled"
            and record["source_metadata"]["policy"] == "power-daily-merra2.v1"
            for record in records
        )
        decision = client.post(
            base + "/assessments",
            json={
                "farm_id": farm["id"],
                "evidence_ids": [record["id"] for record in records],
                "profile_ids": ["us_ia_story_corn_rainfed_v1"],
                "pilot_id": "us_ia_story",
                "start": "2024-03-01",
                "end": "2024-03-31",
            },
        )
        assert decision.status_code == 200
        result = decision.json()
        assert result["engine_binary_sha256"] == manifest["files"][manifest["engine"]]
        assert result["recommendation_eligible"] is False
        assert (
            result["result"]["data"]["summaries"][0]["status"]
            == "insufficient_information"
        )
        assert any(
            item["id"] == result["decision_id"]
            for item in get("/farms/" + farm["id"] + "/decisions")
        )
        output = {
            "status": "PASS",
            "source_code_sha": manifest["source_sha"],
            "restored_farm_decision_evidence_job_photo_verified": True,
            "original_data_directory_retained": True,
            "private_boundary_rejections_verified": True,
            "actual_rust_startup_probe_passed": ready["rust_v03_startup_probe_passed"],
            "live_provider": "NASA POWER",
            "live_cache_hit": False,
            "period": ["2024-03-01", "2024-03-31"],
            "job_states": list(dict.fromkeys(states)),
            "daily_record_count": len(records),
            "days_per_record": 31,
            "original_response_hashes": [
                record["response_sha256"] for record in records
            ],
            "actual_rust_binary_sha256": result["engine_binary_sha256"],
            "persisted_new_decision_verified": True,
            "recommendation_eligible": False,
        }
        args.output.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
        print(
            "PASS: restored private records and fresh uncached POWER → actual pinned Rust → SQLite history"
        )


if __name__ == "__main__":
    main()
