"""Export exact audited PR artifacts to a new build directory, without checkout edits.

Usage: python server/platform-v1/tools/prepare_compat.py /tmp/earthsync-compat
Requires fetched objects for PRs #14, #15, #16, #18; never fetches automatically.
"""

import io
import json
import subprocess
import sys
import tarfile
from pathlib import Path

PINS = {
    "14": ("db42b9620932ed49b71a159e0eb9a61375fa3eec", "server/earthsync/assistant"),
    "15": ("c4112d2d2b69590b8a1e4b8118567635f08a866f", "data/crop-knowledge/v1"),
    "16": ("d5e24f3a6120e745a63394a6ca1e0b28c75794c1", "server/earthsync/evidence"),
    "18": (
        "6f7f81077bbc3709c6206b0a77cf1ff4db15a982",
        ["engine", "app/assets/fixtures/nasa_power_real.json"],
    ),
}


def main():
    destination = Path(sys.argv[1]).absolute()
    destination.mkdir(mode=0o700, parents=False, exist_ok=False)
    for number, (revision, path) in PINS.items():
        actual = subprocess.check_output(
            ["git", "rev-parse", revision + "^{commit}"], text=True
        ).strip()
        if actual != revision:
            raise ValueError("Compatibility source revision mismatch")
        raw = subprocess.check_output(
            ["git", "archive", revision, *([path] if isinstance(path, str) else path)]
        )
        root = destination / number
        root.mkdir(mode=0o700)
        with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
            archive.extractall(root, filter="data")
    (destination / "pins.json").write_text(json.dumps(PINS, indent=2) + "\n")
    print(destination)


if __name__ == "__main__":
    main()
