"""Inventory an untrusted contribution without extraction, imports or collection.

Only regular files and directories with portable relative names are accepted.
Limits bound metadata and decompression work; CRCs and hashes cover member bytes.
This verifies archive structure, not scientific quality or permission to publish.
"""

import argparse
import hashlib
import json
import re
import stat
import sys
import zipfile
from pathlib import Path

MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_MEMBERS = 2000
MAX_MEMBER_BYTES = 32 * 1024 * 1024
MAX_TOTAL_BYTES = 128 * 1024 * 1024
MAX_RATIO = 200


class ArchiveRejected(ValueError):
    """Archive requires manual review outside this bounded inspector."""


def inspect_archive(path):
    """Return a byte inventory; never execute or extract contributed files."""
    path = Path(path)
    with path.open("rb") as source:
        size = source.seek(0, 2)
        if size > MAX_ARCHIVE_BYTES:
            raise ArchiveRejected("Archive exceeds byte limit")
        source.seek(0)
        archive_hash = hashlib.file_digest(source, "sha256").hexdigest()
        source.seek(0)
        with zipfile.ZipFile(source) as archive:
            members = archive.infolist()
            if len(members) > MAX_MEMBERS:
                raise ArchiveRejected("Archive exceeds member limit")
            seen = set()
            files = set()
            total = 0
            # Validate all metadata before decompressing any member.
            for member in members:
                name = member.orig_filename
                clean = name.rstrip("/") if member.is_dir() else name
                parts = clean.split("/")
                if (
                    not clean
                    or any(part in ("", ".", "..") for part in parts)
                    or any(char in name for char in "\\:")
                    or any(ord(char) < 32 or ord(char) == 127 for char in name)
                    or any(part.endswith((".", " ")) for part in parts)
                    or any(re.fullmatch(r"(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?", part) for part in parts)
                ):
                    raise ArchiveRejected("Unsafe or nonportable member path")
                key = clean.casefold()
                if key in seen:
                    raise ArchiveRejected("Duplicate or case-colliding member path")
                seen.add(key)
                if not member.is_dir():
                    files.add(key)
                kind = stat.S_IFMT(member.external_attr >> 16)
                allowed = (0, stat.S_IFDIR) if member.is_dir() else (0, stat.S_IFREG)
                if kind not in allowed:
                    raise ArchiveRejected("Link, special file or inconsistent member type")
                if member.flag_bits & 1:
                    raise ArchiveRejected("Encrypted member")
                if member.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                    raise ArchiveRejected("Unsupported compression method")
                total += member.file_size
                if (
                    member.file_size > MAX_MEMBER_BYTES
                    or total > MAX_TOTAL_BYTES
                    or member.file_size > MAX_RATIO * max(1, member.compress_size)
                ):
                    raise ArchiveRejected("Decompression budget exceeded")
            for key in seen:
                parents = key.split("/")[:-1]
                if any("/".join(parents[:index]) in files for index in range(1, len(parents) + 1)):
                    raise ArchiveRejected("File/directory path collision")
            inventory = []
            for member in members:
                digest = hashlib.sha256()
                count = 0
                with archive.open(member) as stream:
                    while chunk := stream.read(64 * 1024):
                        count += len(chunk)
                        if count > min(member.file_size, MAX_MEMBER_BYTES):
                            raise ArchiveRejected("Expanded size exceeds declared size")
                        digest.update(chunk)
                if count != member.file_size:
                    raise ArchiveRejected("Expanded size differs from declared size")
                inventory.append({
                    "path": member.filename,
                    "kind": "directory" if member.is_dir() else "file",
                    "bytes": count,
                    "compressed_bytes": member.compress_size,
                    "sha256": digest.hexdigest(),
                    "zip_timestamp_unverified": list(member.date_time),
                })
    return {
        "archive_name": path.name,
        "archive_bytes": size,
        "archive_sha256": archive_hash,
        "structural_check": "passed",
        "scientific_validation": "not_performed",
        "members": inventory,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    try:
        result = inspect_archive(args.archive)
    except (ArchiveRejected, OSError, ValueError, zipfile.BadZipFile, RuntimeError) as exc:
        print(f"Archive inspection failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, ensure_ascii=True, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
