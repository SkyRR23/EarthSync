"""Destructive recovery exercises ONLY inside a newly allocated TemporaryDirectory.

Run with the pinned platform venv and its PYTHONPATH. No user DB argument exists.
"""

import argparse
import io
import json
import os
from pathlib import Path
import shutil
import sqlite3
import tempfile
from unittest.mock import patch

from report import Report


def exercise(report, root):
    from PIL import Image
    from earthsync.platform_v1 import store as module
    from earthsync.platform_v1.errors import PlatformError
    from earthsync.platform_v1.maintenance import backup, restore
    from earthsync.platform_v1.models import FarmInput
    from earthsync.platform_v1.objects import LocalObjects
    from earthsync.platform_v1.store import Store

    def rejected(action, exception=Exception):
        try:
            action()
        except exception:
            return
        raise AssertionError("Expected rejection")

    store = Store(root / "data")
    farm = store.create_farm(
        "ops-test",
        FarmInput(
            name="DISPOSABLE SOFTWARE TEST",
            confirmed_point={"latitude": 42.03, "longitude": -93.62},
            confirmed_on="2026-11-14",
            production_system="rainfed",
        ),
    )

    def migration():
        assert store.ready()
        assert Store(root / "data").farm("ops-test", farm.id) == farm
        with store.connection() as db:
            assert (
                db.execute("SELECT count(*) FROM schema_migrations").fetchone()[0] == 1
            )
            assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert not db.execute("PRAGMA foreign_key_check").fetchall()
            rejected(
                lambda: db.execute(
                    "INSERT INTO farm_evidence VALUES ('missing','ops-test','missing')"
                ),
                sqlite3.IntegrityError,
            )
        return (
            "Initial migration, repeat open, persisted farm, integrity and foreign keys"
        )

    report.check("migration and repeat startup", migration)
    objects = LocalObjects(store)
    raw = io.BytesIO()
    Image.new("RGB", (4, 4), "green").save(raw, "PNG")
    clean = objects.clean(raw.getvalue(), "image/png")
    photo = objects.save_photo("ops-test", farm.id, clean)
    original = objects.image("ops-test", farm.id, photo["id"])
    backup_path = root / "backup"

    def roundtrip():
        backup(store, backup_path)
        restored = restore(backup_path, root / "restored")
        assert restored.farm("ops-test", farm.id) == farm
        assert (
            LocalObjects(restored).image("ops-test", farm.id, photo["id"]) == original
        )
        assert restored.ready()
        rejected(lambda: restore(backup_path, root / "restored"), ValueError)
        return "Database plus sanitized object hash round trip; existing destination rejected"

    report.check("backup and restore", roundtrip)

    def corruption():
        corrupt = root / "corrupt"
        shutil.copytree(backup_path, corrupt)
        with (corrupt / "platform.sqlite3").open("ab") as stream:
            stream.write(b"corrupt")
        rejected(lambda: restore(corrupt, root / "reject-db"), ValueError)
        assert not (root / "reject-db").exists()
        shutil.rmtree(corrupt)
        shutil.copytree(backup_path, corrupt)
        (corrupt / "objects" / (photo["id"] + ".png")).write_bytes(b"corrupt")
        rejected(lambda: restore(corrupt, root / "reject-object"), ValueError)
        # Even a recomputed manifest cannot omit a DB-referenced object.
        manifest = json.loads((corrupt / "manifest.json").read_text())
        del manifest["objects/" + photo["id"] + ".png"]
        (corrupt / "manifest.json").write_text(json.dumps(manifest))
        rejected(lambda: restore(corrupt, root / "reject-ref"), ValueError)
        assert not (root / "reject-ref").exists()
        return "Corrupt DB, corrupt object and missing object reference rejected"

    report.check("corrupt backup rejection", corruption)

    def migration_failure():
        fake = root / "migration-code"
        shutil.copytree(
            Path(module.__file__).parent / "migrations", fake / "migrations"
        )
        (fake / "migrations/002_failure.sql").write_text(
            "CREATE TABLE must_rollback (id INTEGER); INVALID SQL;"
        )
        with patch.object(module, "__file__", str(fake / "store.py")):
            rejected(store.migrate, sqlite3.Error)
        with store.connection() as db:
            assert (
                db.execute(
                    "SELECT count(*) FROM sqlite_master WHERE name='must_rollback'"
                ).fetchone()[0]
                == 0
            )
            assert (
                db.execute("SELECT count(*) FROM schema_migrations").fetchone()[0] == 1
            )
        assert Store(root / "data").farm("ops-test", farm.id) == farm
        # Exercise immutable checksums on a COPY, then recover to a fresh target.
        damaged = restore(backup_path, root / "bad-migration")
        with damaged.connection() as db:
            db.execute("UPDATE schema_migrations SET sha256='tampered'")
        rejected(lambda: Store(root / "bad-migration"), RuntimeError)
        recovered = restore(backup_path, root / "migration-recovery")
        assert recovered.ready()
        return "Injected migration rolls back all DDL; changed checksum fails; known backup recovers"

    report.check("migration failure recovery", migration_failure)

    def quota():
        limited = Store(root / "quota", max_rows=1)
        value = FarmInput.model_validate(farm.model_dump(exclude={"id"}))
        limited.create_farm("ops-test", value)
        rejected(lambda: limited.create_farm("ops-test", value), PlatformError)
        assert len(limited.farms("ops-test")) == 1
        tiny = LocalObjects(store, capacity=0)
        rejected(lambda: tiny.save_photo("ops-test", farm.id, clean), PlatformError)
        assert len(objects.list("ops-test", farm.id)) == 1
        return "Row and photo-byte limits reject writes without partial rows/files"

    report.check("storage quotas", quota)

    def missing():
        (objects.root / (photo["id"] + ".png")).unlink()
        rejected(lambda: objects.image("ops-test", farm.id, photo["id"]), PlatformError)
        rejected(lambda: backup(store, root / "missing-backup"), ValueError)
        return "Missing private object fails retrieval and prevents a complete backup"

    report.check("missing object handling", missing)
    if os.name == "nt":
        report.add(
            "private permissions",
            "BLOCKED",
            "Verify Windows ACLs interactively using the runbook",
        )
    else:

        def permissions():
            assert not any(p.stat().st_mode & 0o077 for p in (root / "data").rglob("*"))
            assert (root / "data").stat().st_mode & 0o077 == 0
            return "POSIX data directories 0700 and private files 0600"

        report.check("private permissions", permissions)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = Report()
    with tempfile.TemporaryDirectory(prefix="earthsync-7q-db-") as directory:
        report.check(
            "recovery suite", lambda: exercise(report, Path(directory).resolve())
        )
    return report.write(args.report)


if __name__ == "__main__":
    if os.name != "nt":
        os.umask(0o077)
    raise SystemExit(main())
