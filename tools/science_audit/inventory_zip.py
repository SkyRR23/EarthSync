"""Read-only ZIP inventory. Never extracts, imports, or executes archive members."""

import argparse
import csv
import hashlib
import io
import json
import stat
import zipfile
from collections import Counter
from pathlib import Path, PurePosixPath


def digest_file(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def inventory(path, previous=None):
    previous_hashes = {}
    for member in (previous or {}).get("members", []):
        if member.get("kind") != "directory":
            previous_hashes.setdefault(member["sha256"], []).append(member["path"])
    members, names = [], set()
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            name = entry.filename
            parts = PurePosixPath(name).parts
            if (
                name in names
                or name.startswith("/")
                or ".." in parts
                or "\\" in name
                or (parts and ":" in parts[0])
                or stat.S_ISLNK(entry.external_attr >> 16)
                or entry.flag_bits & 1
            ):
                raise ValueError(
                    f"Ambiguous/unsafe or encrypted archive member: {name}"
                )
            names.add(name)
            # A resource bound makes incomplete inspection explicit instead of
            # silently truncating a member. It never claims scientific validity.
            if entry.file_size > 64 * 1024 * 1024:
                raise ValueError(f"Member exceeds 64 MiB inspection bound: {name}")
            raw = archive.read(entry)  # Reads whole member and verifies ZIP CRC.
            sha = hashlib.sha256(raw).hexdigest()
            row = {
                "path": name,
                "kind": "directory" if entry.is_dir() else "file",
                "bytes": len(raw),
                "compressed_bytes": entry.compress_size,
                "sha256": sha,
                "same_bytes_in_pr11": previous_hashes.get(sha, []) if raw else [],
            }
            suffix = PurePosixPath(name).suffix.lower()
            category = "binary_or_generated_asset"
            if entry.is_dir():
                category = "directory"
            elif suffix in (".zip", ".gz", ".tar", ".7z"):
                category = "nested_archive_requires_separate_inspection"
            elif raw.startswith((b"\x7fELF", b"MZ")) or suffix in (
                ".so",
                ".dll",
                ".rlib",
                ".rmeta",
                ".exe",
            ):
                category = "compiled_artifact_rejected"
            elif suffix in (
                ".csv",
                ".json",
                ".rs",
                ".py",
                ".md",
                ".txt",
                ".toml",
                ".lock",
                ".yaml",
                ".yml",
            ):
                text = raw.decode("utf-8-sig")
                category = {
                    ".csv": "csv_data",
                    ".json": "json_data_or_metadata",
                    ".rs": "rust_source_static_review_only",
                    ".py": "python_source_static_review_only",
                }.get(suffix, "documentation_or_configuration")
                row["text_lines"] = len(text.splitlines())
                if suffix == ".csv":
                    rows = list(csv.reader(io.StringIO(text, newline="")))
                    row["columns"] = rows[0] if rows else []
                    row["data_rows"] = max(0, len(rows) - 1)
                    row["ragged_rows"] = [
                        i
                        for i, values in enumerate(rows[1:], 2)
                        if len(values) != len(rows[0])
                    ]
                    row["empty_cells"] = sum(
                        cell == "" for values in rows[1:] for cell in values
                    )
            row["category"] = category
            members.append(row)
    return {
        "archive_name": Path(path).name,
        "archive_bytes": Path(path).stat().st_size,
        "archive_sha256": digest_file(path),
        "scope": "All member bytes read and CRC checked; no member executed or imported. Structural inventory is not scientific acceptance or full manual source review.",
        "recommendation_eligible": False,
        "category_counts": dict(
            sorted(Counter(m["category"] for m in members).items())
        ),
        "members": members,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--compare", type=Path)
    args = parser.parse_args()
    previous = (
        json.loads(args.compare.read_text(encoding="utf-8")) if args.compare else None
    )
    print(json.dumps(inventory(args.archive, previous), indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
