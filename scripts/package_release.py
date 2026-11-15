"""Package a clean, pinned local release without Git history or private state.

The package includes tracked runtime sources, public Web assets and both native
executables. Python 3.12 dependencies are installed separately from the included
lock; virtual environments and databases are deliberately not portable artifacts.
"""

import argparse
import hashlib
import io
import json
import platform
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATHS = [
    "app",
    "engine",
    "server",
    "data",
    "ops",
    "scripts",
    "tools",
    "docs",
    ".github",
    "README.md",
    "Run-WebDemo.ps1",
    ".gitattributes",
    ".gitignore",
    "start-earthsync.ps1",
    "start-earthsync.cmd",
    "start-earthsync.sh",
    "stop-earthsync.ps1",
    "stop-earthsync.sh",
    "test-earthsync.ps1",
    "test-earthsync.sh",
]
EXTRA_WEB = {"offline-assets.json", "earthsync-offline.js", "flutter_service_worker.js"}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_name(name):
    path = PurePosixPath(name)
    if (
        not name
        or "\\" in name
        or path.is_absolute()
        or any(part in {".", ".."} or ":" in part for part in name.split("/"))
        or path.as_posix() != name
    ):
        raise ValueError("Unsafe package path")
    return path


def git(source, *args):
    return subprocess.check_output(["git", "-C", str(source), *args])


def web_files(root):
    if root.resolve() != root.absolute():
        raise ValueError("Web assets cannot be symlinked")
    manifest = json.loads((root / "offline-assets.json").read_text())
    if (
        manifest.get("schema_version") != "earthsync.offline-shell.v1"
        or manifest.get("private_api_cached") is not False
    ):
        raise ValueError("Prepare the public-only offline shell first")
    resources = manifest["public_assets"]
    if (
        digest(json.dumps(resources, sort_keys=True).encode())
        != manifest["build_sha256"]
    ):
        raise ValueError("Offline manifest hash mismatch")
    files = {}
    for name in sorted(set(resources) | EXTRA_WEB):
        safe_name(name)
        if name in resources and not (
            name
            in {
                "index.html",
                "main.dart.js",
                "flutter.js",
                "flutter_bootstrap.js",
                "manifest.json",
                "version.json",
                "favicon.png",
            }
            or name.startswith(("assets/", "canvaskit/", "icons/"))
        ):
            raise ValueError("Unexpected public asset")
        path = root / name
        if not path.exists() and name == "flutter_service_worker.js":
            continue
        if path.resolve() != path.absolute() or path.suffix in {
            ".db",
            ".sqlite",
            ".sqlite3",
            ".env",
        }:
            raise ValueError("Private/symlinked file in public assets")
        data = path.read_bytes()
        if name in resources and digest(data) != resources[name]:
            raise ValueError("Web asset checksum mismatch: " + name)
        files[name] = data
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()}
    if actual - files.keys() - {".last_build_id"}:
        raise ValueError("Unlisted files in Web output")
    if sum(map(len, files.values())) > 100 * 1024 * 1024:
        raise ValueError("Web output exceeds 100 MiB")
    return files, manifest["build_sha256"]


def build(source, sha, output, v03, web_engine):
    source = source.absolute()
    output = output.absolute()
    if (
        source.resolve() != source
        or output.resolve() != output
        or (output == source or source in output.parents or output in source.parents)
    ):
        raise ValueError(
            "Use a dedicated artifact path outside the source without symlinks"
        )
    if output.exists() or output.with_suffix(output.suffix + ".sha256").exists():
        raise ValueError("Preserve existing release artifacts")
    if (
        not re.fullmatch(r"[0-9a-f]{40}", sha)
        or git(source, "rev-parse", "HEAD").decode().strip() != sha
    ):
        raise ValueError("Source HEAD must equal the explicit reviewed SHA")
    if git(source, "status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Tracked source must be clean")
    public_web, shell_hash = web_files(source / "app/build/web")
    if b"http://127.0.0.1:8021" not in public_web["main.dart.js"]:
        raise ValueError(
            "Build this local artifact with PLATFORM_URL=http://127.0.0.1:8021"
        )
    files = {}
    # git archive includes only this tree, never private archive refs/untracked files.
    snapshot = git(source, "archive", "--format=tar", sha, "--", *SOURCE_PATHS)
    with tarfile.open(fileobj=io.BytesIO(snapshot)) as archive:
        for member in archive:
            if member.isdir():
                continue
            if not member.isfile():
                raise ValueError("Source archive contains a non-regular file")
            safe_name(member.name)
            files["source/" + member.name] = archive.extractfile(member).read()
    suffix = ".exe" if platform.system() == "Windows" else ""
    for name, path in [("v03_demo", v03), ("web_engine", web_engine)]:
        if path.resolve() != path.absolute():
            raise ValueError("Native executable cannot be symlinked")
        data = path.read_bytes()
        if not data.startswith(b"MZ" if suffix else b"\x7fELF"):
            raise ValueError("Native executable does not match the build host")
        files[f"source/engine/target/debug/examples/{name}{suffix}"] = data
    for name, data in public_web.items():
        files["source/app/build/web/" + name] = data
    manifest = {
        "schema_version": "earthsync.local_release.v1",
        "source_sha": sha,
        "source_tree": git(source, "rev-parse", "HEAD^{tree}").decode().strip(),
        "system": platform.system(),
        "machine": platform.machine(),
        "python": "3.12",
        "platform_url": "http://127.0.0.1:8021",
        "web_origin": "http://127.0.0.1:8091",
        "offline_shell_sha256": shell_hash,
        "private_state_included": False,
        "hosted_deployment": False,
        "files": {
            name: {"sha256": digest(data), "bytes": len(data)}
            for name, data in sorted(files.items())
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in sorted(files.items()):
                info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (
                    0o100755 if "/target/debug/examples/" in name else 0o100644
                ) << 16
                archive.writestr(info, data)
            archive.writestr("release.json", json.dumps(manifest, indent=2) + "\n")
        checksum = digest(output.read_bytes())
        output.with_suffix(output.suffix + ".sha256").write_text(
            checksum + "  " + output.name + "\n"
        )
    except Exception:
        output.unlink(missing_ok=True)
        raise
    return manifest, checksum


def verify(directory, expected_sha):
    root = directory.absolute()
    if root.resolve() != root:
        raise ValueError("Package directory cannot be symlinked")
    manifest = json.loads((root / "release.json").read_text())
    if (
        not re.fullmatch(r"[0-9a-f]{40}", expected_sha)
        or manifest.get("schema_version") != "earthsync.local_release.v1"
        or manifest.get("source_sha") != expected_sha
    ):
        raise ValueError("Wrong release source SHA/schema")
    if (
        manifest.get("system") != platform.system()
        or manifest.get("machine") != platform.machine()
    ):
        raise ValueError(
            "Use an artifact built for this operating system and architecture"
        )
    if (
        manifest.get("private_state_included") is not False
        or manifest.get("hosted_deployment") is not False
        or manifest.get("platform_url") != "http://127.0.0.1:8021"
        or manifest.get("web_origin") != "http://127.0.0.1:8091"
    ):
        raise ValueError("Unexpected release scope")
    for name, recorded in manifest["files"].items():
        safe_name(name)
        path = root / name
        if path.resolve() != path.absolute() or not path.is_file():
            raise ValueError("Missing/symlinked package file: " + name)
        data = path.read_bytes()
        if len(data) != recorded["bytes"] or digest(data) != recorded["sha256"]:
            raise ValueError("Package checksum mismatch: " + name)
    paths = list(root.rglob("*"))
    if any(p.is_symlink() for p in paths):
        raise ValueError("Symlinks are not package artifacts")
    actual = {p.relative_to(root).as_posix() for p in paths if p.is_file()}
    if actual != set(manifest["files"]) | {"release.json"}:
        raise ValueError(
            "Unlisted package files; keep virtualenv/private state outside the package"
        )
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    create = sub.add_parser("build")
    create.add_argument("--source", type=Path, default=ROOT)
    create.add_argument("--sha", required=True)
    create.add_argument("--output", type=Path, required=True)
    create.add_argument("--v03", type=Path, required=True)
    create.add_argument("--web-engine", type=Path, required=True)
    check = sub.add_parser("verify")
    check.add_argument("--directory", type=Path, required=True)
    check.add_argument("--expected-sha", required=True)
    args = parser.parse_args()
    if args.command == "build":
        manifest, checksum = build(
            args.source, args.sha, args.output, args.v03, args.web_engine
        )
        print(
            json.dumps(
                {
                    "source_sha": manifest["source_sha"],
                    "files": len(manifest["files"]),
                    "archive_sha256": checksum,
                }
            )
        )
    else:
        result = verify(args.directory, args.expected_sha)
        print(
            "PASS: exact package files, source SHA, native host and public asset hashes; no deployment/Windows interactive acceptance claimed"
        )
        return result


if __name__ == "__main__":
    main()
