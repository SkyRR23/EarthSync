"""Separate private SQLite store: scoped credentials, ownership, quotas and audit."""

import hashlib
import json
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from uuid import uuid4

SCOPES = frozenset(
    {
        "photo:upload",
        "photo:read",
        "photo:delete",
        "photo:analyze",
        "soil:reference:read",
        "lab:extract",
        "lab:confirm",
        "crop:evidence:read",
    }
)


class ResearchError(Exception):
    def __init__(self, code, status=422):
        self.code, self.status = code, status
        super().__init__(code)


class ResearchStore:
    def __init__(self, directory: Path, capacity=256 * 1024 * 1024):
        directory = Path(directory).absolute()
        if directory.resolve() != directory or any(
            p.is_symlink() for p in [directory, *directory.parents]
        ):
            raise ValueError("Private research directory cannot use symlinks")
        root = Path(__file__).resolve().parents[3]
        if directory == root or root in directory.parents:
            raise ValueError("Keep research state outside the source checkout")
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        directory.chmod(0o700)
        self.path, self.capacity = directory / "research.sqlite3", capacity
        if self.path.is_symlink():
            raise ValueError("Database cannot be a symlink")
        fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
        os.close(fd)
        self.path.chmod(0o600)
        with self.connection() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
                INSERT OR IGNORE INTO schema_version VALUES (1);
                CREATE TABLE IF NOT EXISTS credentials (
                    id TEXT PRIMARY KEY, digest TEXT UNIQUE NOT NULL, tenant TEXT NOT NULL,
                    subject TEXT NOT NULL, scopes TEXT NOT NULL, expires REAL NOT NULL, revoked INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS farms (
                    id TEXT PRIMARY KEY, tenant TEXT NOT NULL, subject TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS grants (
                    key_id TEXT NOT NULL REFERENCES credentials(id), farm_id TEXT NOT NULL REFERENCES farms(id),
                    PRIMARY KEY(key_id, farm_id));
                CREATE TABLE IF NOT EXISTS photos (
                    id TEXT PRIMARY KEY, farm_id TEXT NOT NULL REFERENCES farms(id), metadata TEXT NOT NULL, image BLOB NOT NULL);
                CREATE TABLE IF NOT EXISTS reports (
                    id TEXT PRIMARY KEY, photo_id TEXT NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
                    original TEXT NOT NULL, confirmed TEXT);
                CREATE TABLE IF NOT EXISTS rate_windows (
                    key_id TEXT PRIMARY KEY REFERENCES credentials(id), window INTEGER NOT NULL, count INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS audit (
                    id INTEGER PRIMARY KEY, at REAL NOT NULL, key_id TEXT, action TEXT NOT NULL, object_id TEXT, status INTEGER NOT NULL);
            """)

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("PRAGMA secure_delete=ON")
        try:
            with db:
                yield db
        finally:
            db.close()

    def provision(self, tenant, subject, scopes, expires, farm_ids=()):
        if (
            not set(scopes) <= SCOPES
            or not scopes
            or not time.time() < expires <= time.time() + 31 * 86400
        ):
            raise ValueError("Require known scopes and an expiry within 31 days")
        if not tenant or not subject or max(len(tenant), len(subject)) > 100:
            raise ValueError("Require bounded tenant and subject")
        secret, ident = "esr_" + secrets.token_urlsafe(32), str(uuid4())
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute(
                "INSERT INTO credentials VALUES (?,?,?,?,?,?,0)",
                (
                    ident,
                    hashlib.sha256(secret.encode()).hexdigest(),
                    tenant,
                    subject,
                    json.dumps(sorted(scopes)),
                    expires,
                ),
            )
            if not farm_ids:
                farm_ids = [str(uuid4())]
                db.execute(
                    "INSERT INTO farms VALUES (?,?,?)", (farm_ids[0], tenant, subject)
                )
            for farm_id in farm_ids:
                row = db.execute(
                    "SELECT * FROM farms WHERE id=? AND tenant=? AND subject=?",
                    (str(farm_id), tenant, subject),
                ).fetchone()
                if not row:
                    raise ValueError(
                        "Farm must already belong to this tenant and subject"
                    )
                db.execute("INSERT INTO grants VALUES (?,?)", (ident, str(farm_id)))
            self._audit(db, ident, "credential.provisioned", None, 201)
        return {
            "key_id": ident,
            "token": secret,
            "farm_ids": list(farm_ids),
            "expires_at_epoch": expires,
            "scopes": sorted(scopes),
        }

    def revoke(self, ident):
        with self.connection() as db:
            if (
                db.execute(
                    "UPDATE credentials SET revoked=1 WHERE id=?", (str(ident),)
                ).rowcount
                != 1
            ):
                raise ResearchError("NOT_FOUND", 404)
            self._audit(db, str(ident), "credential.revoked", None, 200)

    def authenticate(self, token, limit=60):
        if not token or len(token) > 150:
            raise ResearchError("UNAUTHORIZED", 401)
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT * FROM credentials WHERE digest=?", (digest,)
            ).fetchone()
            if row is None or row["revoked"] or row["expires"] <= time.time():
                raise ResearchError("UNAUTHORIZED", 401)
            principal = dict(row)
            principal.pop("digest")
            principal["scopes"] = json.loads(principal["scopes"])
            window = int(time.time() // 60)
            db.execute(
                """INSERT INTO rate_windows VALUES (?,?,1) ON CONFLICT(key_id) DO UPDATE SET
                       count=CASE WHEN window=excluded.window THEN count+1 ELSE 1 END, window=excluded.window""",
                (row["id"], window),
            )
            count = db.execute(
                "SELECT count FROM rate_windows WHERE key_id=?", (row["id"],)
            ).fetchone()[0]
        if count > limit:
            raise ResearchError("RATE_LIMIT", 429)
        return principal

    @staticmethod
    def require(principal, scope):
        if scope not in principal["scopes"]:
            raise ResearchError("SCOPE_FORBIDDEN", 403)

    def farm(self, principal, farm_id, db=None):
        if db is None:
            with self.connection() as connection:
                return self.farm(principal, farm_id, connection)
        row = db.execute(
            """SELECT f.id FROM farms f JOIN grants g ON f.id=g.farm_id
                         WHERE f.id=? AND f.tenant=? AND f.subject=? AND g.key_id=?""",
            (str(farm_id), principal["tenant"], principal["subject"], principal["id"]),
        ).fetchone()
        if not row:
            raise ResearchError("NOT_FOUND", 404)

    def save_photo(self, principal, farm_id, clean):
        ident = str(uuid4())
        metadata = {
            "id": ident,
            "farm_id": str(farm_id),
            "sha256": clean.sha256,
            "width": clean.width,
            "height": clean.height,
            "size_bytes": len(clean.data),
            "uploaded_at_epoch": time.time(),
            "exif_retained": False,
            "location": None,
        }
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.farm(principal, farm_id, db)
            size, count = db.execute(
                "SELECT coalesce(sum(length(image)),0), count(*) FROM photos"
            ).fetchone()
            if size + len(clean.data) > self.capacity or count >= 500:
                raise ResearchError("STORAGE_QUOTA", 507)
            db.execute(
                "INSERT INTO photos VALUES (?,?,?,?)",
                (ident, str(farm_id), json.dumps(metadata), clean.data),
            )
            self._audit(db, principal["id"], "photo.saved", ident, 201)
        return metadata

    def photo(self, principal, farm_id, ident):
        with self.connection() as db:
            self.farm(principal, farm_id, db)
            row = db.execute(
                "SELECT * FROM photos WHERE id=? AND farm_id=?",
                (str(ident), str(farm_id)),
            ).fetchone()
            if row is None:
                raise ResearchError("NOT_FOUND", 404)
            metadata = json.loads(row["metadata"])
            if hashlib.sha256(row["image"]).hexdigest() != metadata["sha256"]:
                raise ResearchError("IMAGE_INTEGRITY_FAILURE", 500)
            return metadata, row["image"]

    def delete_photo(self, principal, farm_id, ident):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.farm(principal, farm_id, db)
            if (
                db.execute(
                    "DELETE FROM photos WHERE id=? AND farm_id=?",
                    (str(ident), str(farm_id)),
                ).rowcount
                != 1
            ):
                raise ResearchError("NOT_FOUND", 404)
            self._audit(db, principal["id"], "photo.deleted", str(ident), 204)

    def save_report(self, principal, farm_id, photo_id, extraction):
        ident = str(uuid4())
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.farm(principal, farm_id, db)
            if db.execute("SELECT count(*) FROM reports").fetchone()[0] >= 5000:
                raise ResearchError("STORAGE_QUOTA", 507)
            if not db.execute(
                "SELECT id FROM photos WHERE id=? AND farm_id=?",
                (str(photo_id), str(farm_id)),
            ).fetchone():
                raise ResearchError("NOT_FOUND", 404)
            db.execute(
                "INSERT INTO reports VALUES (?,?,?,NULL)",
                (ident, str(photo_id), json.dumps(extraction)),
            )
            self._audit(db, principal["id"], "report.extracted", ident, 201)
        return {
            "id": ident,
            "photo_id": str(photo_id),
            "original": extraction,
            "confirmed": None,
        }

    def report(self, principal, farm_id, ident, confirmation=None):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.farm(principal, farm_id, db)
            row = db.execute(
                """SELECT r.* FROM reports r JOIN photos p ON r.photo_id=p.id
                              WHERE r.id=? AND p.farm_id=?""",
                (str(ident), str(farm_id)),
            ).fetchone()
            if row is None:
                raise ResearchError("NOT_FOUND", 404)
            if confirmation is not None:
                confirmation = {
                    **confirmation,
                    "confirmed_at_epoch": time.time(),
                    "confirmed_by_key_id": principal["id"],
                    "category": "user_confirmed_lab_transcription",
                    "laboratory_authenticity_verified": False,
                }
                db.execute(
                    "UPDATE reports SET confirmed=? WHERE id=?",
                    (json.dumps(confirmation), str(ident)),
                )
                self._audit(db, principal["id"], "report.confirmed", str(ident), 200)
            return {
                "id": row["id"],
                "photo_id": row["photo_id"],
                "original": json.loads(row["original"]),
                "confirmed": confirmation
                if confirmation is not None
                else json.loads(row["confirmed"])
                if row["confirmed"]
                else None,
            }

    def audit(self, key_id, action, object_id=None, status=200):
        with self.connection() as db:
            self._audit(db, key_id, action, object_id, status)

    @staticmethod
    def _audit(db, key_id, action, object_id, status):
        db.execute(
            "INSERT INTO audit(at,key_id,action,object_id,status) VALUES (?,?,?,?,?)",
            (time.time(), key_id, action, object_id, status),
        )
        # Bounded diagnostic retention. Never record tokens, OCR, notes, coordinates or raw URLs.
        db.execute(
            "DELETE FROM audit WHERE id <= (SELECT coalesce(max(id),0)-10000 FROM audit)"
        )

    def backup(self, destination):
        destination = Path(destination)
        if destination.exists():
            raise ValueError("Backup destination must be new")
        fd = os.open(destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(fd)
        with self.connection() as source, sqlite3.connect(destination) as target:
            source.backup(target)
