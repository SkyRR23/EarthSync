"""Owned file references, reusing PR #16's reviewed image sanitizer."""

import json
import os
import time
from uuid import UUID, uuid4

from .errors import PlatformError
from .store import encoded


class LocalObjects:
    def __init__(self, store, sanitizer=None, capacity=256 * 1024 * 1024):
        self.store, self.sanitizer, self.capacity = store, sanitizer, capacity
        self.root = store.path.parent / "objects"
        if self.root.is_symlink():
            raise ValueError("Object directory cannot be a symlink")
        self.root.mkdir(mode=0o700, exist_ok=True)
        self.root.chmod(0o700)

    def clean(self, raw, mime):
        sanitizer = self.sanitizer
        if sanitizer is None:
            try:
                from earthsync.evidence.images import sanitize_image

                sanitizer = sanitize_image
            except ImportError as exc:
                raise PlatformError("PHOTO_SERVICE_NOT_INSTALLED", 503) from exc
        try:
            return sanitizer(raw, mime)
        except ValueError as exc:
            raise PlatformError("INVALID_IMAGE") from exc

    def save_photo(self, owner, farm_id, image):
        ident = str(uuid4())
        key = ident + ".png"
        destination = self.root / key
        # Generate names internally. No caller-controlled path or URL is accepted.
        metadata = {
            "id": ident,
            "farm_id": str(farm_id),
            "width": image.width,
            "height": image.height,
            "sha256": image.sha256,
            "size_bytes": len(image.data),
            "uploaded_at_epoch": time.time(),
            "location": None,
            "exif_retained": False,
        }
        try:
            with self.store.connection() as db:
                db.execute("BEGIN IMMEDIATE")
                self.store.farm(owner, farm_id, db)
                self.store._quota(db, "artifacts")
                size = sum(p.stat().st_size for p in self.root.iterdir() if p.is_file())
                if size + len(image.data) > self.capacity:
                    raise PlatformError("STORAGE_QUOTA", 507)
                with destination.open("xb") as stream:
                    os.chmod(destination, 0o600)
                    stream.write(image.data)
                    stream.flush()
                    os.fsync(stream.fileno())
                db.execute(
                    "INSERT INTO artifacts VALUES (?,?,?,?,?,?,?)",
                    (
                        ident,
                        str(farm_id),
                        owner,
                        "photo",
                        key,
                        image.sha256,
                        encoded(metadata),
                    ),
                )
                self.store._audit(db, owner, ident, "photo.saved")
        except BaseException:
            destination.unlink(missing_ok=True)
            raise
        return metadata

    def _record(self, owner, farm_id, ident, db):
        self.store.farm(owner, farm_id, db)
        row = db.execute(
            "SELECT * FROM artifacts WHERE id=? AND farm_id=? AND owner=? AND kind='photo'",
            (str(ident), str(farm_id), owner),
        ).fetchone()
        if row is None:
            raise PlatformError("NOT_FOUND", 404)
        # Defense against corrupted database object keys.
        if row["object_key"] != str(UUID(row["id"])) + ".png":
            raise PlatformError("OBJECT_INTEGRITY_FAILURE", 500)
        path = self.root / row["object_key"]
        if path.is_symlink():
            raise PlatformError("OBJECT_INTEGRITY_FAILURE", 500)
        return row, path

    def list(self, owner, farm_id):
        with self.store.connection() as db:
            self.store.farm(owner, farm_id, db)
            return [
                json.loads(row[0])
                for row in db.execute(
                    "SELECT metadata FROM artifacts WHERE owner=? AND farm_id=? AND kind='photo' LIMIT 100",
                    (owner, str(farm_id)),
                )
            ]

    def image(self, owner, farm_id, ident):
        import hashlib

        with self.store.connection() as db:
            row, path = self._record(owner, farm_id, ident, db)
            if not path.is_file() or path.stat().st_size > 10 * 1024 * 1024:
                raise PlatformError("OBJECT_INTEGRITY_FAILURE", 500)
            raw = path.read_bytes()
            if hashlib.sha256(raw).hexdigest() != row["sha256"]:
                raise PlatformError("OBJECT_INTEGRITY_FAILURE", 500)
            return raw

    def delete(self, owner, farm_id, ident):
        with self.store.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            row, path = self._record(owner, farm_id, ident, db)
            db.execute(
                "DELETE FROM artifacts WHERE id=? AND owner=?", (row["id"], owner)
            )
            self.store._audit(db, owner, row["id"], "photo.deleted")
        # A crash here can leave a private orphan; cleanup removes it later.
        path.unlink(missing_ok=True)

    def cleanup(self):
        """Offline maintenance only, while the HTTP worker is stopped."""
        with self.store.connection() as db:
            keys = {r[0] for r in db.execute("SELECT object_key FROM artifacts")}
        for path in self.root.iterdir():
            if path.name not in keys and not path.is_symlink() and path.is_file():
                path.unlink()
