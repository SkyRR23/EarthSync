"""Verify and rehearse recovery of disposable final-release stores.

Stop both loopback services first. The original stores are never overwritten.
Only counts and hashes enter the public receipt; private backups stay outside Git.
"""

import argparse
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys

from recovery_7x import ROOT, fingerprint, stopped

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--private", type=Path, required=True)
p.add_argument("--receipt", type=Path, required=True)
a = p.parse_args()
private = a.private.absolute()
assert (
    private.resolve() == private
    and private != ROOT
    and ROOT not in private.parents
    and private not in ROOT.parents
)
assert not a.receipt.exists(), "Preserve previous recovery receipts"
stopped()
platform, web = private / "platform", private / "web"
before = fingerprint(platform, web)
backup, restored, webcopy = (
    private / n
    for n in ["final-platform-backup", "final-platform-restored", "final-web-restored"]
)
assert not any(n.exists() for n in [backup, restored, webcopy]), (
    "Use fresh recovery destinations"
)
for command, directory in [("backup", platform), ("restore", restored)]:
    subprocess.run(
        [
            sys.executable,
            "-m",
            "earthsync.platform_v1.maintenance",
            command,
            "--directory",
            str(directory),
            "--backup",
            str(backup),
        ],
        check=True,
    )
webcopy.mkdir(mode=0o700)
with sqlite3.connect(web / "evidence.sqlite3") as source:
    with sqlite3.connect(webcopy / "evidence.sqlite3") as target:
        source.backup(target)
(webcopy / "evidence.sqlite3").chmod(0o600)
shutil.copy2(web / "workspace-token.txt", webcopy / "workspace-token.txt")
(webcopy / "workspace-token.txt").chmod(0o600)
assert fingerprint(restored, webcopy) == before
assert fingerprint(platform, web) == before
assert before["platform"]["farmer_journal"]["rows"] > 0
assert before["platform"]["rotation_comparisons"]["rows"] > 0
receipt = {
    "status": "PASS",
    "classification": "SYNTHETIC records + CACHED REAL source lineage",
    "originals_unchanged": True,
    "restored_exact_rows_objects_and_separate_stores": True,
    "fingerprint": before,
}
a.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
print(
    "PASS: exact SQLite rows, source lineage, comparisons, journal, separate objects and token; original stores unchanged"
)
