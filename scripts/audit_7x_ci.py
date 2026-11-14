"""Read exact-head dispatched GitHub checks and retain a sanitized log audit."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

REPOSITORY = "SkyRR23/EarthSync"


def gh(*args, raw=False):
    result = subprocess.check_output(["gh", *args, "--repo", REPOSITORY])
    return result if raw else json.loads(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    assert re.fullmatch("[0-9a-f]{40}", args.sha)
    assert not args.output.exists(), "Preserve existing CI receipts"
    runs = gh(
        "run",
        "list",
        "--commit",
        args.sha,
        "--event",
        "workflow_dispatch",
        "--limit",
        "100",
        "--json",
        "databaseId,name,workflowName,headSha,conclusion,status,url",
    )
    selected = {}
    for run in runs:
        selected.setdefault(run["workflowName"], run)
    assert len(selected) == 11, (
        "Dispatch all eleven required workflows at the final head"
    )
    audited = []
    for run in selected.values():
        assert (
            run["headSha"] == args.sha
            and run["status"] == "completed"
            and run["conclusion"] == "success"
        ), run
        jobs = gh("run", "view", str(run["databaseId"]), "--json", "jobs")["jobs"]
        assert jobs and all(job["conclusion"] == "success" for job in jobs), run["name"]
        assert all(
            step["conclusion"] in {"success", "skipped"}
            for job in jobs
            for step in job["steps"]
        )
        raw = gh("run", "view", str(run["databaseId"]), "--log", raw=True)
        text = raw.decode("utf-8", errors="replace")
        summaries = [
            line.split("Z ", 1)[-1]
            for line in text.splitlines()
            if re.search(
                r"\b\d+ passed\b|All tests passed|test result: ok|PASS: pinned 7Q|PASS: container|No issues found|Built build/web",
                line,
            )
        ]
        audited.append(
            {
                **run,
                "jobs": [
                    {
                        "name": job["name"],
                        "conclusion": job["conclusion"],
                        "url": job["url"],
                    }
                    for job in jobs
                ],
                "raw_log_sha256": hashlib.sha256(raw).hexdigest(),
                "raw_log_bytes": len(raw),
                "raw_log_summaries": summaries,
            }
        )
    receipt = {
        "source_sha": args.sha,
        "status": "PASS",
        "workflows": len(audited),
        "job_count": sum(len(run["jobs"]) for run in audited),
        "runs": audited,
        "scope": "Exact-head CI including Windows/Linux/Docker and Windows staging; local browser/live/provider/recovery receipts are separate",
    }
    args.output.write_text(json.dumps(receipt, indent=2) + "\n")
    print(
        f"PASS: {receipt['workflows']} workflows / {receipt['job_count']} jobs at {args.sha}; raw logs inspected"
    )


if __name__ == "__main__":
    main()
