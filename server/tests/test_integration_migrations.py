"""Forward upgrades from either published 040 without rewriting its digest."""

import hashlib
from pathlib import Path
import sqlite3

import pytest

from earthsync.platform_v1.store import Store

MIGRATIONS = Path(__file__).parents[1] / "earthsync/platform_v1/migrations"


@pytest.mark.parametrize(
    "legacy", [None, "040_realtime.sql", "040_crop_lab_reports.sql"]
)
@pytest.mark.parametrize("line_endings", ["LF", "CRLF"])
def test_clean_and_both_published_040_upgrade_and_reopen(
    tmp_path, legacy, line_endings
):
    directory = tmp_path / "demo"
    directory.mkdir()
    original = None
    if legacy:
        with sqlite3.connect(directory / "platform.sqlite3") as db:
            for file in sorted(MIGRATIONS.glob("*.sql")):
                version = int(file.name.split("_")[0])
                if version >= 40:
                    continue
                db.executescript(file.read_text())
                raw = file.read_bytes().replace(b"\r\n", b"\n")
                if line_endings == "CRLF":
                    raw = raw.replace(b"\n", b"\r\n")
                db.execute(
                    "INSERT INTO schema_migrations VALUES (?,?)",
                    (version, hashlib.sha256(raw).hexdigest()),
                )
            file = MIGRATIONS / legacy
            raw = file.read_bytes().replace(b"\r\n", b"\n")
            if line_endings == "CRLF":
                raw = raw.replace(b"\n", b"\r\n")
            original = hashlib.sha256(raw).hexdigest()
            db.executescript(file.read_text())
            db.execute("INSERT INTO schema_migrations VALUES (40,?)", (original,))
            if legacy == "040_realtime.sql":
                db.execute("INSERT INTO realtime_state VALUES ('preserved','{}')")
    for _ in range(2):
        store = Store(directory)
        with store.connection() as db:
            assert (
                db.execute("SELECT count(*) FROM crop_lab_reports").fetchone()[0] == 0
            )
            db.execute("SELECT payload FROM realtime_state")
            assert (
                db.execute(
                    "SELECT count(*) FROM schema_migrations WHERE version=41"
                ).fetchone()[0]
                == 1
            )
            if original:
                assert (
                    db.execute(
                        "SELECT sha256 FROM schema_migrations WHERE version=40"
                    ).fetchone()[0]
                    == original
                )
            if legacy == "040_realtime.sql":
                assert (
                    db.execute(
                        "SELECT payload FROM realtime_state WHERE key='preserved'"
                    ).fetchone()[0]
                    == "{}"
                )


def test_unknown_040_hash_is_rejected(tmp_path):
    store = Store(tmp_path / "demo")
    with store.connection() as db:
        db.execute("UPDATE schema_migrations SET sha256='unknown' WHERE version=40")
    with pytest.raises(RuntimeError, match="checksum changed"):
        Store(tmp_path / "demo")
