"""Run both integrated services on loopback only. Never mounts private routes.

Build app/build/web (PLATFORM_URL=http://127.0.0.1:8021) and Rust examples first.
Use a dedicated private directory, not a repository directory or public web root.
"""

import argparse
import hashlib
import os
import signal
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--web-port", type=int, default=8091)
    parser.add_argument("--platform-port", type=int, default=8021)
    args = parser.parse_args()
    if (
        not (1024 <= args.web_port <= 65535 and 1024 <= args.platform_port <= 65535)
        or args.web_port == args.platform_port
    ):
        parser.error("Choose two different unprivileged ports")
    directory = args.directory.absolute()
    if (
        directory.resolve() != directory
        or directory == ROOT
        or ROOT in directory.parents
        or directory in ROOT.parents
        or directory == Path("/tmp")
    ):
        parser.error("Private data must be outside the checkout, without symlinks")
    executable = (
        ROOT
        / "engine/target/debug/examples"
        / ("v03_demo.exe" if os.name == "nt" else "v03_demo")
    )
    catalog = ROOT / "data/crop-knowledge/v1/catalog.json"
    if not executable.is_file() or not (ROOT / "app/build/web/index.html").is_file():
        parser.error("Build the Rust examples and Flutter Web first")
    env = {**os.environ, "PYTHONPATH": str(ROOT / "server")}
    platform_env = {
        **env,
        "EARTHSYNC_PLATFORM_LOCAL": "1",
        "EARTHSYNC_PLATFORM_DIR": str(directory),
        "EARTHSYNC_PLATFORM_ORIGINS": f"http://127.0.0.1:{args.web_port}",
        "EARTHSYNC_V03_EXECUTABLE": str(executable),
        "EARTHSYNC_V03_SHA256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "EARTHSYNC_CATALOG_PATH": str(catalog),
        "EARTHSYNC_CATALOG_SHA256": hashlib.sha256(catalog.read_bytes()).hexdigest(),
    }

    def stop(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    processes = []
    try:
        for app, port, child_env, factory in [
            ("earthsync.web_demo:app", args.web_port, env, []),
            (
                "earthsync.platform_v1.api:app_factory",
                args.platform_port,
                platform_env,
                [
                    "--factory",
                    "--workers",
                    "1",
                    "--limit-concurrency",
                    "12",
                    "--timeout-keep-alive",
                    "5",
                ],
            ),
        ]:
            processes.append(
                subprocess.Popen(
                    [
                        sys.executable,
                        "-m",
                        "uvicorn",
                        app,
                        *factory,
                        "--host",
                        "127.0.0.1",
                        "--port",
                        str(port),
                        "--no-proxy-headers",
                        "--no-access-log",
                    ],
                    cwd=ROOT,
                    env=child_env,
                )
            )
        print(
            f"Local app: http://127.0.0.1:{args.web_port} (private service is separate)",
            flush=True,
        )
        while all(p.poll() is None for p in processes):
            time.sleep(0.5)
    except KeyboardInterrupt:
        pass
    finally:
        for p in processes:
            if p.poll() is None:
                p.terminate()
        for p in processes:
            try:
                p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()
    return next((p.returncode for p in processes if p.returncode not in (0, -15)), 0)


if __name__ == "__main__":
    raise SystemExit(main())
