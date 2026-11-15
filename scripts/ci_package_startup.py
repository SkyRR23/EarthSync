"""Verify unpacked full-stack artifacts using fresh private state and loopback.

This is real native/process/HTTP smoke testing, not interactive Windows acceptance
or a live provider observation. No private workspace or farm record is exported.
"""

import argparse
import json
import os
from pathlib import Path
import platform
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit

from package_release import verify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--expected-sha", required=True)
    parser.add_argument("--private", type=Path, required=True)
    args = parser.parse_args()
    root = args.package.absolute()
    manifest = verify(root, args.expected_sha)
    private = args.private.absolute()
    if (
        private.resolve() != private
        or private.exists()
        or (private == root or root in private.parents or private in root.parents)
    ):
        parser.error("Use a fresh private destination outside the package")
    platform_port = urlsplit(manifest["platform_url"]).port
    web_port = urlsplit(manifest["web_origin"]).port
    for port in [platform_port, web_port]:
        with socket.socket() as probe:
            if probe.connect_ex(("127.0.0.1", port)) == 0:
                parser.error(
                    "Stop the existing loopback runtime before package smoke testing"
                )
    private.mkdir(parents=True, mode=0o700)
    source = root / "source"
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("EARTHSYNC_")
    }
    env.update(
        PYTHONPATH=str(source / "server"),
        PYTHONDONTWRITEBYTECODE="1",
        EARTHSYNC_EVIDENCE_DIR=str(private / "workspace"),
        EARTHSYNC_EVIDENCE_TOKEN_FILE=str(private / "workspace/workspace-token.txt"),
        EARTHSYNC_EVIDENCE_ORIGINS=manifest["web_origin"],
    )
    subprocess.run(
        [sys.executable, "-B", str(source / "scripts/verify_7x_integrity.py")],
        env=env,
        cwd=source,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    subprocess.run(
        [sys.executable, "-m", "earthsync.demo_workspace", str(private / "workspace")],
        env=env,
        cwd=source,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    native = (
        source
        / "engine/target/debug/examples"
        / ("v03_demo.exe" if os.name == "nt" else "v03_demo")
    )
    if os.name != "nt":
        for executable in native.parent.iterdir():
            executable.chmod(0o700)
    result = subprocess.run(
        [str(native)],
        input=(source / "engine/tests/fixtures/v03/unknown_request.json").read_bytes(),
        capture_output=True,
        check=True,
        timeout=10,
    )
    assert json.loads(result.stdout)["status"] == "success", (
        "Actual packaged Rust failed"
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with (private / "startup.log").open("w") as log:
        process = subprocess.Popen(
            [
                sys.executable,
                str(source / "scripts/run_final_local.py"),
                "--directory",
                str(private / "platform"),
                "--web-port",
                str(web_port),
                "--platform-port",
                str(platform_port),
            ],
            env=env,
            cwd=source,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        try:
            for url in [
                manifest["platform_url"] + "/api/platform/v1/ready",
                manifest["web_origin"] + "/api/v1/health",
            ]:
                deadline = time.monotonic() + 45
                while True:
                    assert process.poll() is None, (
                        "Packaged startup failed; inspect private log"
                    )
                    try:
                        with opener.open(url, timeout=2) as response:
                            data = json.load(response)
                        if "ready" in url:
                            assert (
                                data["ready"] and not data["hosted_private_api_enabled"]
                            )
                        break
                    except OSError:
                        if time.monotonic() >= deadline:
                            raise RuntimeError("Packaged startup timed out") from None
                        time.sleep(0.25)
            with opener.open(manifest["web_origin"] + "/") as response:
                assert b"flutter_bootstrap.js" in response.read()
            with opener.open(
                manifest["web_origin"] + "/api/demo/capabilities"
            ) as response:
                assert json.load(response)["photo_workspace"] == "private_local_demo"
            with opener.open(
                manifest["platform_url"] + "/api/platform/v1/crop-references?q=rice"
            ) as response:
                reference = json.load(response)
            assert reference["status"] == "reference_only"
            assert reference["rule_review"]["executable_rule_count"] == 0
            request = urllib.request.Request(
                manifest["platform_url"] + "/api/platform/v1/farms",
                headers={"Origin": "https://untrusted.invalid"},
            )
            try:
                opener.open(request).close()
                raise AssertionError("Untrusted origin was accepted")
            except urllib.error.HTTPError as error:
                assert error.code == 403
            print(
                json.dumps(
                    {
                        "status": "PASS",
                        "source_sha": manifest["source_sha"],
                        "system": platform.system(),
                        "scope": "REAL packaged native/process/HTTP smoke; SYNTHETIC native missing-data fixture; no live provider/browser acceptance",
                        "private_api_public": False,
                        "executable_crop_rules": 0,
                        "science_package_pins_verified": True,
                    }
                )
            )
        finally:
            if process.poll() is None:
                if os.name == "nt":
                    subprocess.run(
                        ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                        check=True,
                        capture_output=True,
                    )
                else:
                    process.terminate()
                process.wait(timeout=25)
    verify(root, args.expected_sha)


if __name__ == "__main__":
    main()
