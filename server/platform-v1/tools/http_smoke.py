"""Actual local HTTP → live POWER → owned evidence → actual Rust smoke.

Run explicitly against a disposable local service. Creates a sample farm marked
as software-test geometry, not a real farmer report or agricultural ground truth.
"""

import argparse
import time
from urllib.parse import urlsplit

import httpx


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8021")
    args = parser.parse_args()
    if urlsplit(args.url).hostname not in ("127.0.0.1", "localhost", "::1"):
        parser.error("Use a local disposable service only")
    with httpx.Client(base_url=args.url + "/api/platform/v1", timeout=30) as client:
        assert client.get("/health").is_success
        assert client.get("/ready").is_success
        response = client.post(
            "/farms",
            json={
                "name": "SOFTWARE TEST: public regional point, no field ground truth",
                "confirmed_point": {"latitude": 42.03, "longitude": -93.62},
                "confirmed_on": "2026-11-14",
                "production_system": "rainfed",
            },
        )
        response.raise_for_status()
        farm = response.json()
        request = {
            "farm_id": farm["id"],
            "query": {
                "point": farm["confirmed_point"],
                "start": "2024-02-01",
                "end": "2024-02-29",
            },
        }
        job_response = client.post("/climate/jobs", json=request)
        job_response.raise_for_status()
        job_id = job_response.json()["id"]
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            job = client.get("/jobs/" + job_id).json()
            if job["status"] in ("succeeded", "failed", "cancelled"):
                break
            time.sleep(0.25)
        assert job["status"] == "succeeded", job.get("error")
        assert job["result"]["gaps"] == [], job["result"]["gaps"]
        evidence = job["result"]["records"]
        assert len(evidence) == 3
        response = client.post(
            "/assessments",
            json={
                "farm_id": farm["id"],
                "evidence_ids": [r["id"] for r in evidence],
                "profile_ids": ["us_ia_story_corn_rainfed_v1"],
                "pilot_id": "us_ia_story",
                "start": "2024-02-01",
                "end": "2024-02-29",
            },
        )
        response.raise_for_status()
        value = response.json()
        assert value["result"]["status"] == "success"
        assert (
            value["result"]["data"]["summaries"][0]["status"]
            == "insufficient_information"
        )
        assert not value["recommendation_eligible"]
        context = client.get(f"/farms/{farm['id']}/assistant-context").json()
        assert len(context["sources"]) == 3
        assert len(client.get(f"/farms/{farm['id']}/decisions").json()) == 1
        print(
            "PASS: actual HTTP, live daily POWER, 3 evidence records, actual Rust v0.3, reference-only result, history and assistant source refs"
        )


if __name__ == "__main__":
    main()
