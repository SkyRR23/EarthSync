"""Exercise built 7Q local runtimes on disposable CI state, never public ports."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--private", type=Path, required=True)
    args = parser.parse_args()
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    processes = []
    logs = []
    try:
        for profile, port, ready in [
            ("platform", 8021, "/api/platform/v1/ready"),
            ("web", 8080, "/api/v1/health"),
        ]:
            log = (args.private / f"{profile}-startup.log").open("w")
            logs.append(log)
            process = subprocess.Popen(
                [
                    sys.executable,
                    str(args.source / "ops/staging/staging.py"),
                    "run",
                    "--source",
                    str(args.source),
                    "--state",
                    str(args.private / profile),
                ],
                stdout=log,
                stderr=subprocess.STDOUT,
            )
            processes.append(process)
            deadline = time.monotonic() + 60
            while True:
                assert process.poll() is None, f"{profile} exited; inspect private log"
                try:
                    with opener.open(
                        f"http://127.0.0.1:{port}{ready}", timeout=2
                    ) as response:
                        data = json.load(response)
                    if profile == "web" or data.get("ready") is True:
                        break
                except OSError:
                    pass
                assert time.monotonic() < deadline, f"{profile} startup timed out"
                time.sleep(0.5)
        with opener.open(
            "http://127.0.0.1:8021/api/platform/v1/crop-references?q=rice"
        ) as response:
            reference = json.load(response)
        assert reference["status"] == "reference_only"
        assert reference["rule_review"]["executable_rule_count"] == 0
        with opener.open("http://127.0.0.1:8080/") as response:
            assert b"flutter_bootstrap.js" in response.read()
        print(
            "PASS: pinned 7Q Web/platform startup, actual Rust readiness, v2 integrity/lookup and blocked 7V review; loopback only. No browser acceptance or live provider claim."
        )
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                if os.name == "nt":
                    subprocess.run(
                        ["taskkill", "/PID", str(process.pid), "/T", "/F"], check=True
                    )
                else:
                    process.terminate()
                process.wait(timeout=20)
        for log in logs:
            log.close()


if __name__ == "__main__":
    main()
