"""SQLite repository with explicit owner joins, immutable evidence and migrations."""

import hashlib
import json
import sqlite3
import time
from contextlib import closing, contextmanager
from pathlib import Path
from uuid import uuid4

from .errors import PlatformError
from .models import Evidence, Farm, FarmInput, VERSION


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def migration_hashes(file):
    raw = file.read_bytes()
    unix = raw.replace(b"\r\n", b"\n")
    # Published Windows checkouts used CRLF; archives used LF. Recognize only
    # those exact byte variants and retain the database's original digest.
    return {
        hashlib.sha256(value).hexdigest()
        for value in (raw, unix, unix.replace(b"\n", b"\r\n"))
    }


def cache_key(provider, product, version, request):
    return hashlib.sha256(
        encoded(
            {
                "provider": provider,
                "product": product,
                "contract": VERSION,
                "version": version,
                "request": request,
            }
        ).encode()
    ).hexdigest()


class Store:
    def __init__(self, directory, max_rows=10000):
        root = Path(directory)
        if not root.is_absolute() or root.resolve() != root:
            raise ValueError(
                "Private directory must be absolute and contain no symlinks"
            )
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        root.chmod(0o700)
        self.path = root / "platform.sqlite3"
        if self.path.is_symlink():
            raise ValueError("Database cannot be a symlink")
        self.path.touch(mode=0o600, exist_ok=True)
        self.path.chmod(0o600)
        self.max_rows = max_rows
        self.migrate()

    @contextmanager
    def connection(self):
        with closing(sqlite3.connect(self.path, timeout=5)) as db:
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA foreign_keys=ON")
            db.execute("PRAGMA secure_delete=ON")
            db.execute("PRAGMA busy_timeout=5000")
            with db:
                yield db

    def migrate(self):
        with self.connection() as db:
            # Use a single transaction; executescript would commit before the migration.
            db.execute("BEGIN EXCLUSIVE")
            db.execute(
                "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, sha256 TEXT NOT NULL)"
            )
            files = sorted((Path(__file__).parent / "migrations").glob("*.sql"))
            legacy_040 = {
                digest
                for file in files
                if file.name in {"040_realtime.sql", "040_crop_lab_reports.sql"}
                for digest in migration_hashes(file)
            }
            for file in files:
                # Both published branches used 040. Keep their bytes and applied
                # digest intact; 041 adds whichever table that database lacks.
                if file.name == "040_crop_lab_reports.sql":
                    continue
                version = int(file.name.split("_")[0])
                digest = hashlib.sha256(file.read_bytes()).hexdigest()
                old = db.execute(
                    "SELECT sha256 FROM schema_migrations WHERE version=?", (version,)
                ).fetchone()
                if old:
                    if old[0] not in migration_hashes(file) and not (
                        version == 40 and old[0] in legacy_040
                    ):
                        raise RuntimeError("Applied migration checksum changed")
                    continue
                for statement in file.read_text().split(";"):
                    if statement.strip():
                        db.execute(statement)
                db.execute(
                    "INSERT INTO schema_migrations VALUES (?,?)", (version, digest)
                )

    def _quota(self, db, table):
        # Table names are internal constants, never request fields.
        if table not in {
            "farms",
            "evidence",
            "jobs",
            "decisions",
            "history",
            "artifacts",
            "observations",
            "audit",
        }:
            raise ValueError("Unknown repository table")
        if db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0] >= self.max_rows:
            raise PlatformError("STORAGE_QUOTA", 507)

    def _audit(self, db, owner, resource_id, event, version=VERSION):
        # No coordinates, image bytes, request body or secrets in audit rows.
        self._quota(db, "audit")
        db.execute(
            "INSERT INTO audit VALUES (?,?,?,?,?,?)",
            (str(uuid4()), owner, resource_id, event, version, time.time()),
        )

    def create_farm(self, owner, value: FarmInput):
        farm = Farm(id=uuid4(), **value.model_dump())
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self._quota(db, "farms")
            db.execute(
                "INSERT INTO farms VALUES (?,?,?,?)",
                (str(farm.id), owner, farm.model_dump_json(), time.time()),
            )
            self._audit(db, owner, str(farm.id), "farm.created")
        return farm

    def farm(self, owner, farm_id, db=None):
        if db is None:
            with self.connection() as db:
                return self.farm(owner, farm_id, db)
        row = db.execute(
            "SELECT document FROM farms WHERE id=? AND owner=?", (str(farm_id), owner)
        ).fetchone()
        if row is None:
            raise PlatformError("NOT_FOUND", 404)
        return Farm.model_validate_json(row[0])

    def farm_link(self, owner, local_id, revision, db=None):
        if db is None:
            with self.connection() as db:
                return self.farm_link(owner, local_id, revision, db)
        row = db.execute(
            "SELECT farm_id FROM farm_links WHERE owner=? AND local_profile_id=? AND revision=?",
            (owner, local_id, revision.isoformat()),
        ).fetchone()
        if row is None:
            raise PlatformError("NOT_FOUND", 404)
        return {
            "local_profile_id": local_id,
            "revision": revision.isoformat(),
            "farm": self.farm(owner, row[0], db),
        }

    def link_farm(self, owner, value):
        # An explicit unique key makes manual retries after a lost 201 safe.
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            try:
                linked = self.farm_link(
                    owner, value.local_profile_id, value.revision, db
                )
            except PlatformError as exc:
                if exc.code != "NOT_FOUND":
                    raise
            else:
                if FarmInput(**linked["farm"].model_dump(exclude={"id"})) != value.farm:
                    raise PlatformError("FARM_LINK_CONFLICT", 409)
                return linked
            farm = Farm(id=uuid4(), **value.farm.model_dump())
            self._quota(db, "farms")
            db.execute(
                "INSERT INTO farms VALUES (?,?,?,?)",
                (str(farm.id), owner, farm.model_dump_json(), time.time()),
            )
            db.execute(
                "INSERT INTO farm_links VALUES (?,?,?,?)",
                (
                    owner,
                    value.local_profile_id,
                    value.revision.isoformat(),
                    str(farm.id),
                ),
            )
            self._audit(db, owner, str(farm.id), "farm.explicitly_linked")
            return self.farm_link(owner, value.local_profile_id, value.revision, db)

    def farms(self, owner):
        with self.connection() as db:
            return [
                Farm.model_validate_json(r[0])
                for r in db.execute(
                    "SELECT document FROM farms WHERE owner=? ORDER BY created DESC LIMIT 100",
                    (owner,),
                )
            ]

    def save_evidence(self, owner, record: Evidence, farm_id=None):
        value = record.model_dump(mode="json")
        document = encoded(value)
        if len(document.encode()) > 2_000_000:
            raise PlatformError("EVIDENCE_TOO_LARGE", 413)
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            if farm_id:
                farm = self.farm(owner, farm_id, db)
                if record.spatial.query_point != farm.confirmed_point:
                    raise PlatformError("SPATIAL_MISMATCH")
            old = db.execute(
                "SELECT document FROM evidence WHERE id=? AND owner=?",
                (record.id, owner),
            ).fetchone()
            # Cache JSON is canonicalized and may reorder nested metadata keys.
            # Older databases retain the original serialization. Immutability
            # compares values in either representation, never incidental order.
            if old and json.loads(old[0]) != value:
                raise PlatformError("IMMUTABLE_EVIDENCE_CONFLICT", 409)
            if not old:
                self._quota(db, "evidence")
                db.execute(
                    "INSERT INTO evidence VALUES (?,?,?,?)",
                    (record.id, owner, document, time.time()),
                )
                self._audit(
                    db, owner, record.id, "evidence.saved", record.dataset_version
                )
            if farm_id:
                db.execute(
                    "INSERT OR IGNORE INTO farm_evidence VALUES (?,?,?)",
                    (str(farm_id), owner, record.id),
                )
        return record

    def evidence(self, owner, evidence_id, farm_id=None):
        with self.connection() as db:
            if farm_id:
                self.farm(owner, farm_id, db)
                row = db.execute(
                    "SELECT e.document FROM evidence e JOIN farm_evidence f ON f.evidence_id=e.id AND f.owner=e.owner WHERE e.id=? AND e.owner=? AND f.farm_id=?",
                    (evidence_id, owner, str(farm_id)),
                ).fetchone()
            else:
                row = db.execute(
                    "SELECT document FROM evidence WHERE id=? AND owner=?",
                    (evidence_id, owner),
                ).fetchone()
            if row is None:
                raise PlatformError("NOT_FOUND", 404)
            return Evidence.model_validate_json(row[0])

    def save_decision(self, owner, farm_id, document):
        ident = str(uuid4())
        payload = encoded(document)
        if len(payload) > 4_000_000:
            raise PlatformError("DECISION_TOO_LARGE", 413)
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.farm(owner, farm_id, db)
            self._quota(db, "decisions")
            db.execute(
                "INSERT INTO decisions VALUES (?,?,?,?,?)",
                (ident, str(farm_id), owner, payload, time.time()),
            )
            self._audit(db, owner, ident, "decision.saved", document["engine_version"])
        return ident

    def decisions(self, owner, farm_id):
        with self.connection() as db:
            self.farm(owner, farm_id, db)
            return [
                {"id": r[0], "assessment": json.loads(r[1])}
                for r in db.execute(
                    "SELECT id,document FROM decisions WHERE farm_id=? AND owner=? ORDER BY created DESC LIMIT 100",
                    (str(farm_id), owner),
                )
            ]

    def cache_get(self, key):
        with self.connection() as db:
            row = db.execute(
                "SELECT document FROM source_cache WHERE cache_key=? AND expires>?",
                (key, time.time()),
            ).fetchone()
            return json.loads(row[0]) if row else None

    def cache_put(self, key, document, ttl=3600):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("DELETE FROM source_cache WHERE expires<=?", (time.time(),))
            if db.execute("SELECT COUNT(*) FROM source_cache").fetchone()[0] >= 128:
                db.execute(
                    "DELETE FROM source_cache WHERE cache_key IN (SELECT cache_key FROM source_cache ORDER BY expires LIMIT 1)"
                )
            db.execute(
                "INSERT OR REPLACE INTO source_cache VALUES (?,?,?)",
                (key, encoded(document), time.time() + ttl),
            )

    def ready(self):
        with self.connection() as db:
            return (
                db.execute("PRAGMA quick_check").fetchone()[0] == "ok"
                and not db.execute("PRAGMA foreign_key_check").fetchall()
            )

    def backup(self, destination):
        destination = Path(destination)
        if destination.exists() or destination.is_symlink():
            raise ValueError("Backup destination must be new")
        destination.touch(mode=0o600)
        with self.connection() as db, closing(sqlite3.connect(destination)) as target:
            db.backup(target)

    def save_history(self, owner, farm_id, history):
        ident = str(uuid4())
        value = {
            "id": ident,
            **history.model_dump(mode="json"),
            "reported_at": time.time(),
            "data_type": "farmer_reported",
        }
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.farm(owner, farm_id, db)
            self._quota(db, "history")
            db.execute(
                "INSERT INTO history VALUES (?,?,?,?,?)",
                (ident, str(farm_id), owner, encoded(value), time.time()),
            )
            self._audit(db, owner, ident, "history.reported")
        return value

    def history(self, owner, farm_id):
        with self.connection() as db:
            self.farm(owner, farm_id, db)
            return [
                json.loads(row[0])
                for row in db.execute(
                    "SELECT document FROM history WHERE owner=? AND farm_id=? ORDER BY created LIMIT 100",
                    (owner, str(farm_id)),
                )
            ]

    def farm_records(self, owner, farm_id):
        with self.connection() as db:
            self.farm(owner, farm_id, db)
            return [
                Evidence.model_validate_json(row[0])
                for row in db.execute(
                    "SELECT e.document FROM evidence e JOIN farm_evidence f ON f.evidence_id=e.id AND f.owner=e.owner WHERE f.owner=? AND f.farm_id=? ORDER BY e.created DESC LIMIT 100",
                    (owner, str(farm_id)),
                )
            ]

    def intelligence(self, owner, farm_id):
        """Bounded saved source jobs; original retrieval times survive restart."""
        self.farm(owner, farm_id)
        with self.connection() as db:
            rows = db.execute(
                "SELECT id,kind,status,result,error,updated FROM jobs WHERE owner=? "
                "AND kind IN ('soil_map','optical_discovery','forecast') "
                "AND json_extract(request,'$.farm_id')=? ORDER BY created DESC LIMIT 30",
                (owner, str(farm_id)),
            ).fetchall()
        return [
            {
                **dict(row),
                "result": json.loads(row["result"]) if row["result"] else None,
            }
            for row in rows
        ]

    def observations(self, owner, farm_id):
        with self.connection() as db:
            self.farm(owner, farm_id, db)
            rows = db.execute(
                "SELECT id,document FROM observations WHERE farm_id=? AND owner=? ORDER BY created DESC LIMIT 100",
                (str(farm_id), owner),
            ).fetchall()
        return [{"id": row[0], **json.loads(row[1])} for row in rows]

    def save_observation(self, owner, farm_id, value):
        ident = str(uuid4())
        document = {
            **value.model_dump(mode="json"),
            "data_type": "farmer_reported",
            "independently_verified": False,
        }
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.farm(owner, farm_id, db)
            self._quota(db, "observations")
            db.execute(
                "INSERT INTO observations VALUES (?,?,?,?,?)",
                (ident, str(farm_id), owner, encoded(document), time.time()),
            )
            self._audit(db, owner, ident, "observation.reported")
        return {"id": ident, **document}
