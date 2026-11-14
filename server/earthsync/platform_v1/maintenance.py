"""Offline migration, complete backup and integrity-checked local restore."""

import argparse
import hashlib
import json
import shutil
from pathlib import Path

from .objects import LocalObjects
from .store import Store


def backup(store, destination):
    destination = Path(destination)
    destination.mkdir(mode=0o700, exist_ok=False)
    store.backup(destination / "platform.sqlite3")
    source = store.path.parent / "objects"
    objects = destination / "objects"
    objects.mkdir(mode=0o700)
    with store.connection() as db:
        rows = db.execute("SELECT object_key,sha256 FROM artifacts").fetchall()
    for row in rows:
        key, digest = row
        path = source / key
        if Path(key).name != key or path.is_symlink() or not path.is_file():
            raise ValueError("Invalid or missing object reference")
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError("Object checksum mismatch")
        shutil.copyfile(path, objects / key)
        (objects / key).chmod(0o600)
    manifest = {
        p.relative_to(destination).as_posix(): hashlib.sha256(
            p.read_bytes()
        ).hexdigest()
        for p in destination.rglob("*")
        if p.is_file()
    }
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (destination / "manifest.json").chmod(0o600)


def restore(source, destination):
    source, destination = Path(source), Path(destination)
    if destination.exists() or source.is_symlink() or not source.is_dir():
        raise ValueError(
            "Restore requires a real backup directory and a new destination"
        )
    manifest = json.loads((source / "manifest.json").read_text())
    if "platform.sqlite3" not in manifest:
        raise ValueError("Backup database absent")
    for key, digest in manifest.items():
        parts = Path(key).parts
        if key != "platform.sqlite3" and not (
            len(parts) == 2 and parts[0] == "objects" and parts[1].endswith(".png")
        ):
            raise ValueError("Unexpected backup path")
        path = source / key
        if (
            path.is_symlink()
            or path.parent.is_symlink()
            or not path.is_file()
            or hashlib.sha256(path.read_bytes()).hexdigest() != digest
        ):
            raise ValueError("Backup checksum or path failure")
    destination.mkdir(mode=0o700)
    try:
        (destination / "objects").mkdir(mode=0o700)
        for key in manifest:
            target = destination / key
            shutil.copyfile(source / key, target)
            target.chmod(0o600)
        restored = Store(destination)
        if not restored.ready():
            raise ValueError("Restored database integrity failed")
        with restored.connection() as db:
            for row in db.execute("SELECT object_key,sha256 FROM artifacts"):
                key, digest = row
                if (
                    "objects/" + key not in manifest
                    or manifest["objects/" + key] != digest
                ):
                    raise ValueError("Restored object reference failed")
        return restored
    except BaseException:
        shutil.rmtree(destination)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["migrate", "backup", "restore", "cleanup"])
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--backup", type=Path)
    args = parser.parse_args()
    if args.command == "restore":
        if not args.backup:
            parser.error("restore requires --backup")
        restore(args.backup, args.directory)
    else:
        store = Store(args.directory)
        if args.command == "backup":
            if not args.backup:
                parser.error("backup requires --backup")
            backup(store, args.backup)
        if args.command == "cleanup":
            LocalObjects(store).cleanup()
    print("Maintenance completed; private contents omitted")


if __name__ == "__main__":
    main()
