"""Local container entrypoint; no public bind or implicit enablement."""

import hashlib
import os
from pathlib import Path

if os.environ.get("EARTHSYNC_PLATFORM_LOCAL") != "1":
    raise SystemExit("Set EARTHSYNC_PLATFORM_LOCAL=1 for the local single-user demo")
for setting, path in [
    ("EARTHSYNC_V03_SHA256", "/app/v03_demo"),
    ("EARTHSYNC_CATALOG_SHA256", "/app/catalog.json"),
]:
    os.environ[setting] = hashlib.sha256(Path(path).read_bytes()).hexdigest()
os.execvp(
    "uvicorn",
    [
        "uvicorn",
        "earthsync.platform_v1.api:app_factory",
        "--factory",
        "--host",
        "127.0.0.1",
        "--port",
        "8021",
        "--workers",
        "1",
        "--no-proxy-headers",
        "--no-access-log",
        "--limit-concurrency",
        "12",
        "--timeout-keep-alive",
        "5",
    ],
)
