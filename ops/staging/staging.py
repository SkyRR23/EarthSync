"""Local operations around existing EarthSync entrypoints; no application adapter.

Python 3.12. Run --help; see README.md before using real private data.
"""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import signal
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
from urllib.parse import urlsplit


def run(command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True, **kwargs)


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def private_path(value):
    path = Path(value).absolute()
    if path.resolve() != path:
        raise ValueError("Use absolute paths without symlinks")
    return path


def loopback_origin(value):
    try:
        parsed = urlsplit(value)
        valid = (
            parsed.scheme == "http"
            and parsed.hostname in ("127.0.0.1", "localhost", "::1")
            and parsed.username is None
            and parsed.password is None
            and parsed.path in ("", "/")
            and not parsed.query
            and not parsed.fragment
            and parsed.port is not None
            and 1024 <= parsed.port <= 65535
        )
    except ValueError:
        valid = False
    if not valid:
        raise argparse.ArgumentTypeError(
            "Use an exact unprivileged HTTP loopback origin"
        )
    return value.rstrip("/")


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")
    path.chmod(0o600)


@contextmanager
def exclusive(state):
    lock = state / "operation.lock"
    try:
        lock.mkdir(mode=0o700)
    except FileExistsError:
        raise ValueError(
            "State is in use; inspect operation.lock before manual recovery"
        ) from None
    try:
        (lock / "pid").write_text(str(os.getpid()))
        yield
    finally:
        (lock / "pid").unlink()
        lock.rmdir()


def source_pin(source, expected):
    actual = subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "HEAD"], text=True
    ).strip()
    if len(expected) != 40 or actual != expected:
        raise ValueError("Source HEAD must equal the explicit full reviewed SHA")
    dirty = subprocess.check_output(
        [
            "git",
            "-C",
            str(source),
            "status",
            "--porcelain",
            "--untracked-files=all",
            "--",
            "app",
            "engine",
            "server",
            "data",
        ],
        text=True,
    )
    if dirty:
        raise ValueError("Application source is dirty; use a dedicated clean checkout")
    return actual


def environment(source, state, manifest):
    # Never inherit demo/fixture switches or caller-supplied tokens/engine paths.
    env = {k: v for k, v in os.environ.items() if not k.startswith("EARTHSYNC_")}
    env.update(
        PYTHONPATH=manifest.get("runtime", str(source / "server")),
        PYTHONUNBUFFERED="1",
        PYTHONDONTWRITEBYTECODE="1",
    )
    if manifest["profile"] == "web":
        env.update(
            EARTHSYNC_EVIDENCE_DIR=str(state / "data"),
            EARTHSYNC_EVIDENCE_TOKEN_FILE=str(state / "data/workspace-token.txt"),
        )
    else:
        env.update(
            EARTHSYNC_PLATFORM_LOCAL="1",
            EARTHSYNC_PLATFORM_DIR=str(state / "data"),
            EARTHSYNC_PLATFORM_ORIGINS=manifest.get(
                "web_origin", "http://127.0.0.1:8080"
            ),
            EARTHSYNC_V03_EXECUTABLE=manifest["engine"],
            EARTHSYNC_V03_SHA256=manifest["files"][manifest["engine"]],
            EARTHSYNC_CATALOG_PATH=manifest["catalog"],
            EARTHSYNC_CATALOG_SHA256=manifest["files"][manifest["catalog"]],
        )
    return env


def build(args, source, state):
    source_pin(source, args.sha)
    if (state / "manifest.json").exists() or (state / "venv").exists():
        raise ValueError(
            "Build requires a fresh state directory; keep releases separate"
        )
    if sys.version_info[:2] != (3, 12):
        raise ValueError("Use Python 3.12 for this pinned staging workflow")
    rust = subprocess.check_output(["rustc", "--version"], text=True).strip()
    if not rust.startswith("rustc 1.99.0 "):
        raise ValueError("Install/select Rust 1.99.0")
    lock = source / (
        "server/requirements.lock"
        if args.profile == "web"
        else "server/platform-v1/requirements.lock"
    )
    run([sys.executable, "-m", "venv", state / "venv"])
    python = (
        state / "venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    )
    run([python, "-m", "pip", "install", "--disable-pip-version-check", "-r", lock])
    run([python, "-m", "pip", "check"])
    suffix = ".exe" if os.name == "nt" else ""
    files = [lock, source / "server/requirements.lock", source / "engine/Cargo.lock"]
    manifest = {
        "source": str(source),
        "source_sha": args.sha,
        "profile": args.profile,
        "python": str(python),
        "python_version": sys.version.split()[0],
        "rust": rust,
        "platform_url": args.platform_url,
        "web_origin": args.web_origin,
    }
    if args.profile == "web":
        # Resolve PATHEXT on Windows: CreateProcess cannot resolve bare flutter
        # to flutter.bat. Keep an argument list; do not enable shell execution.
        flutter_executable = shutil.which("flutter")
        if flutter_executable is None:
            raise ValueError("Flutter executable not found on PATH")
        # A fresh Windows SDK bootstraps its tool on first invocation and emits
        # pub progress before the requested JSON. Finish that bootstrap first;
        # the subsequent machine response must still be valid, exact JSON.
        run([flutter_executable, "--version"])
        flutter = subprocess.check_output(
            [flutter_executable, "--version", "--machine"], text=True
        )
        if json.loads(flutter)["frameworkVersion"] != args.flutter_version:
            raise ValueError(
                "Flutter version differs from the selected reviewed version"
            )
        manifest["flutter"] = json.loads(flutter)
        run(
            [
                "cargo",
                "build",
                "--locked",
                "--manifest-path",
                source / "engine/Cargo.toml",
                "--example",
                "web_engine",
            ]
        )
        run(
            [flutter_executable, "pub", "get", "--enforce-lockfile"], cwd=source / "app"
        )
        run(
            [
                flutter_executable,
                "build",
                "web",
                "--no-web-resources-cdn",
                "--pwa-strategy=none",
                "--no-wasm-dry-run",
                "--dart-define=PLATFORM_URL=" + manifest["platform_url"],
            ],
            cwd=source / "app",
        )
        run(
            [
                sys.executable,
                source / "scripts/finalize_offline.py",
                source / "app/build/web",
            ]
        )
        manifest["engine"] = str(
            source / f"engine/target/debug/examples/web_engine{suffix}"
        )
        files += [
            source / "app/pubspec.lock",
            *sorted((source / "app/build/web").rglob("*")),
        ]
    else:
        # Standalone 7I uses its own pinned compatibility export. Final 7N source
        # may supply these paths directly. Never merge or alter application code.
        compat = private_path(args.compat) if args.compat else None
        engine_root = compat / "18/engine" if compat else source / "engine"
        catalog = (
            compat / "15/data/crop-knowledge/v1/catalog.json"
            if compat
            else source / "data/crop-knowledge/v1/catalog.json"
        )
        run(
            [
                "cargo",
                "build",
                "--locked",
                "--release",
                "--manifest-path",
                engine_root / "Cargo.toml",
                "--example",
                "v03_demo",
            ]
        )
        manifest["engine"] = str(
            engine_root / f"target/release/examples/v03_demo{suffix}"
        )
        manifest["catalog"] = str(catalog)
        files += [catalog, engine_root / "Cargo.lock"]
        runtime = state / "runtime"
        shutil.copytree(
            source / "server/earthsync",
            runtime / "earthsync",
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )
        for number, package in [("16", "evidence"), ("14", "assistant")]:
            if not (runtime / "earthsync" / package).exists():
                if not compat:
                    raise ValueError(
                        "Platform source lacks compatibility packages; supply --compat"
                    )
                shutil.copytree(
                    compat / number / "server/earthsync" / package,
                    runtime / "earthsync" / package,
                )
        manifest["runtime"] = str(runtime)
        files += sorted(runtime.rglob("*"))
        reference = source / "data/crop-knowledge/v2"
        if reference.is_dir():
            target = state / "data/crop-knowledge/v2"
            shutil.copytree(
                reference, target, ignore=shutil.ignore_patterns("__pycache__", "*.pyc")
            )
            files += sorted(target.rglob("*"))
        if compat:
            files.append(compat / "pins.json")
    files.append(Path(manifest["engine"]))
    manifest["files"] = {str(p): digest(p) for p in files if p.is_file()}
    manifest["migrations"] = {
        p.name: digest(p)
        for p in sorted(
            (source / "server/earthsync/platform_v1/migrations").glob("*.sql")
        )
    }
    manifest["packages"] = subprocess.check_output(
        [python, "-m", "pip", "freeze"], text=True
    ).splitlines()
    save_json(state / "manifest.json", manifest)
    print("BUILD RECORDED; inspect manifest.json. No server started or deployed.")


def verify(source, state):
    manifest = json.loads((state / "manifest.json").read_text())
    if manifest["source"] != str(source):
        raise ValueError("Manifest belongs to another source checkout")
    python_version = subprocess.check_output(
        [manifest["python"], "-c", "import platform; print(platform.python_version())"],
        text=True,
    ).strip()
    if python_version != manifest["python_version"]:
        raise ValueError("Python runtime version differs from the recorded build")
    source_pin(source, manifest["source_sha"])
    for name, expected in manifest["files"].items():
        if digest(name) != expected:
            raise ValueError("Artifact or lock checksum changed")
    current = {
        p.name: digest(p)
        for p in (source / "server/earthsync/platform_v1/migrations").glob("*.sql")
    }
    if current != manifest["migrations"]:
        raise ValueError("Migration set differs from the build")
    packages = subprocess.check_output(
        [manifest["python"], "-m", "pip", "freeze"], text=True
    ).splitlines()
    if packages != manifest["packages"]:
        raise ValueError("Installed dependencies differ from the build")
    return manifest


def stop(process):
    if process.poll() is not None:
        return
    if os.name == "nt":
        process.send_signal(signal.CTRL_BREAK_EVENT)
    else:
        process.send_signal(signal.SIGINT)
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def serve(args, source, state, manifest, env):
    profile = manifest["profile"]
    port = args.port or (8080 if profile == "web" else 8021)
    with socket.socket() as probe:
        if os.name == "nt":
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        else:
            # Match Uvicorn's restart behavior when closed connections are still
            # in TIME_WAIT; an actively listening worker still rejects this bind.
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(("127.0.0.1", port))
    expected_origin = manifest.get("web_origin" if profile == "web" else "platform_url")
    if expected_origin and urlsplit(expected_origin).port != port:
        raise ValueError("Run port must match the origin recorded at build time")
    python = manifest["python"]
    if profile == "web":
        run([python, "-m", "earthsync.demo_workspace", state / "data"], env=env)
        target, factory, ready = "earthsync.web_demo:app", [], "/api/v1/health"
    else:
        run(
            [
                python,
                "-m",
                "earthsync.platform_v1.maintenance",
                "migrate",
                "--directory",
                state / "data",
            ],
            env=env,
        )
        target, factory, ready = (
            "earthsync.platform_v1.api:app_factory",
            ["--factory"],
            "/api/platform/v1/ready",
        )
    log = state / "service.log"
    with log.open("ab") as output:
        log.chmod(0o600)
        process = subprocess.Popen(
            [
                python,
                "-m",
                "uvicorn",
                target,
                *factory,
                "--host",
                "127.0.0.1",
                "--port",
                str(port),
                "--workers",
                "1",
                "--no-proxy-headers",
                "--no-access-log",
                "--limit-concurrency",
                "12",
                "--timeout-keep-alive",
                "5",
            ],
            cwd=source,
            env=env,
            stdout=output,
            stderr=output,
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0,
        )
        try:
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError("Backend exited; inspect private service.log")
                try:
                    opener = urllib.request.build_opener(
                        urllib.request.ProxyHandler({})
                    )
                    with opener.open(
                        f"http://127.0.0.1:{port}{ready}", timeout=2
                    ) as response:
                        value = json.load(response)
                    if profile == "web" or value.get("ready") is True:
                        break
                except (OSError, ValueError):
                    pass
                time.sleep(0.5)
            else:
                raise RuntimeError("Readiness timed out; inspect private service.log")
            print(
                f"LOCAL {profile} listening at http://127.0.0.1:{port}; Ctrl+C stops cleanly.",
                flush=True,
            )
            if profile == "web":
                print(
                    "Web health is liveness only; run smoke and browser acceptance for readiness.",
                    flush=True,
                )
            code = process.wait()
            if code:
                raise RuntimeError(
                    "Backend stopped with an error; inspect private service.log"
                )
        finally:
            stop(process)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=["build", "verify", "run", "migrate", "backup", "restore", "cleanup"],
    )
    parser.add_argument("--source", type=private_path, required=True)
    parser.add_argument("--state", type=private_path, required=True)
    parser.add_argument("--sha", help="Full reviewed source SHA, required for build")
    parser.add_argument("--profile", choices=["web", "platform"], default="web")
    parser.add_argument("--flutter-version", default="3.44.0")
    parser.add_argument(
        "--platform-url", type=loopback_origin, default="http://127.0.0.1:8021"
    )
    parser.add_argument(
        "--web-origin", type=loopback_origin, default="http://127.0.0.1:8080"
    )
    parser.add_argument(
        "--compat", help="Existing prepare_compat export for standalone 7I"
    )
    parser.add_argument("--port", type=int)
    parser.add_argument("--backup", type=private_path)
    parser.add_argument(
        "--destination", type=private_path, help="NEW restore data directory"
    )
    args = parser.parse_args()
    source, state = args.source, args.state
    for path in (state, args.backup, args.destination):
        if path and (
            path == source or source in path.parents or path in source.parents
        ):
            parser.error(
                "Private state/backup/restore paths must not overlap the source checkout"
            )
    if args.command == "build" and not args.sha:
        parser.error("build requires --sha")
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    state.chmod(0o700)
    with exclusive(state):
        if args.command == "build":
            build(args, source, state)
            return
        manifest = verify(source, state)
        env = environment(source, state, manifest)
        if args.command == "verify":
            print(
                "PASS: pinned source, artifacts, locks, migrations and installed packages"
            )
        elif args.command == "run":
            serve(args, source, state, manifest, env)
        else:
            if manifest["profile"] != "platform":
                parser.error(
                    "Use the documented offline SQLite procedure for 7H photo storage"
                )
            directory = (
                args.destination if args.command == "restore" else state / "data"
            )
            if directory is None or (
                args.command in ("backup", "restore") and args.backup is None
            ):
                parser.error(
                    "backup/restore require --backup; restore also needs --destination"
                )
            command = [
                manifest["python"],
                "-m",
                "earthsync.platform_v1.maintenance",
                args.command,
                "--directory",
                directory,
            ]
            if args.backup:
                command += ["--backup", args.backup]
            run(command, env=env)


if __name__ == "__main__":
    if os.name != "nt":
        os.umask(0o077)

        # Service managers normally send TERM; use the same finally/child cleanup
        # path as the interactive Ctrl+C lifecycle.
        def interrupted(signum, frame):
            raise KeyboardInterrupt

        signal.signal(signal.SIGTERM, interrupted)
    try:
        main()
    except KeyboardInterrupt:
        print("Stopped; persistent data retained.")
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
