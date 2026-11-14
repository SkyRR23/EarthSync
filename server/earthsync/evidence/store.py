"""Private single-workspace storage: atomic metadata+image CRUD, no user paths."""

import sqlite3
from contextlib import closing, contextmanager
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from .images import CleanImage
from .models import Photo, PhotoInput


class StorageFull(Exception):
    pass


class PhotoStore:
    def __init__(
        self, directory: Path, capacity_bytes=256 * 1024 * 1024, max_photos=500
    ):
        directory = Path(directory)
        if not directory.is_absolute() or directory.resolve() != directory:
            raise ValueError(
                "Use an absolute private storage directory without symlinks"
            )
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        directory.chmod(0o700)
        self.path = directory / "evidence.sqlite3"
        if self.path.is_symlink():
            raise ValueError("Storage database cannot be a symlink")
        self.path.touch(mode=0o600, exist_ok=True)
        self.path.chmod(0o600)
        self.capacity_bytes = capacity_bytes
        self.max_photos = max_photos
        with self.connection() as db:
            # Freed pages are wiped on delete/replace, including image blobs.
            db.execute("PRAGMA secure_delete=ON")
            db.execute(
                "CREATE TABLE IF NOT EXISTS photos "
                "(id TEXT PRIMARY KEY, metadata TEXT NOT NULL, image BLOB NOT NULL)"
            )

    @contextmanager
    def connection(self):
        with closing(sqlite3.connect(self.path, timeout=10)) as db:
            with db:
                db.execute("PRAGMA secure_delete=ON")
                yield db

    def save(self, metadata: PhotoInput, image: CleanImage, photo_id=None) -> Photo:
        now = datetime.now(timezone.utc)
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            old = self.get(photo_id, db) if photo_id else None
            if (
                old is None
                and db.execute("SELECT COUNT(*) FROM photos").fetchone()[0]
                >= self.max_photos
            ):
                raise StorageFull
            total = db.execute(
                "SELECT COALESCE(SUM(length(image)),0) FROM photos"
            ).fetchone()[0]
            if (
                total - (old.size_bytes if old else 0) + len(image.data)
                > self.capacity_bytes
            ):
                raise StorageFull
            photo = Photo(
                **metadata.model_dump(),
                id=photo_id or str(uuid4()),
                uploaded_at=old.uploaded_at if old else now,
                updated_at=now,
                width_px=image.width,
                height_px=image.height,
                size_bytes=len(image.data),
                sha256=image.sha256,
            )
            db.execute(
                "INSERT OR REPLACE INTO photos VALUES (?,?,?)",
                (photo.id, photo.model_dump_json(), image.data),
            )
        return photo

    def get(self, photo_id, db=None) -> Photo:
        if db is None:
            with self.connection() as db:
                return self.get(photo_id, db)
        row = db.execute(
            "SELECT metadata FROM photos WHERE id=?", (photo_id,)
        ).fetchone()
        if row is None:
            raise KeyError(photo_id)
        return Photo.model_validate_json(row[0])

    def list(self) -> list[Photo]:
        with self.connection() as db:
            rows = db.execute(
                "SELECT metadata FROM photos ORDER BY rowid DESC"
            ).fetchall()
        return [Photo.model_validate_json(row[0]) for row in rows]

    def image(self, photo_id) -> bytes:
        with self.connection() as db:
            row = db.execute(
                "SELECT image FROM photos WHERE id=?", (photo_id,)
            ).fetchone()
        if row is None:
            raise KeyError(photo_id)
        return row[0]

    def delete(self, photo_id):
        with self.connection() as db:
            if db.execute("DELETE FROM photos WHERE id=?", (photo_id,)).rowcount != 1:
                raise KeyError(photo_id)
