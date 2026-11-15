"""Cross-platform local build, supervised lifecycle and actual HTTP smoke tests."""

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import threading
import time
import uuid
import webbrowser

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / ".earthsync-runtime"
VENV = ROOT / ".venv"
PYTHON = VENV / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
STATE = ROOT.parent / (ROOT.name + "-demo-state")
RUN = RUNTIME / "run.json"
MARKER = ".earthsync-disposable-demo"
EXE = ".exe" if os.name == "nt" else ""


def write(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def read(path, default=None):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def command(args, cwd=ROOT, **kwargs):
    subprocess.run([str(a) for a in args], cwd=cwd, check=True, **kwargs)


def environment():
    return {
        **os.environ,
        "PYTHONPATH": str(ROOT / "server"),
        "PYTHONDONTWRITEBYTECODE": "1",
        "PYTHONUNBUFFERED": "1",
    }


def flutter_sdk():
    choices = [
        os.getenv("EARTHSYNC_FLUTTER"),
        str(
            Path.home()
            / "develop/flutter-3.44.0/bin"
            / ("flutter.bat" if os.name == "nt" else "flutter")
        ),
        shutil.which("flutter"),
    ]
    for choice in choices:
        if choice and Path(choice).is_file():
            return Path(choice)
    raise RuntimeError(
        "Flutter SDK missing. Install Flutter 3.44 and put flutter on PATH, or set EARTHSYNC_FLUTTER to its executable."
    )


def available(preferred, used):
    for port in range(preferred, preferred + 50):
        if port in used:
            continue
        with socket.socket() as probe:
            try:
                probe.bind(("127.0.0.1", port))
            except OSError:
                continue
        used.add(port)
        return port
    raise RuntimeError("No free loopback port in the local demo range")


def config():
    previous = read(RUNTIME / "ports.json", {})
    used = set()
    ports = {
        name: available(previous.get(name, preferred), used)
        for name, preferred in [("web", 8091), ("platform", 8021), ("research", 8031)]
    }
    write(RUNTIME / "ports.json", ports)
    return ports


def secure_state():
    if STATE.resolve() != STATE.absolute() or ROOT in STATE.parents or STATE == ROOT:
        raise RuntimeError("Unsafe demo directory")
    if STATE.exists() and not (STATE / MARKER).is_file():
        raise RuntimeError(f"Existing unmarked directory left untouched: {STATE}")
    STATE.mkdir(parents=True, exist_ok=True)
    marker = STATE / MARKER
    if marker.exists() and read(marker).get("source") != str(ROOT):
        raise RuntimeError("Demo directory belongs to a different checkout")
    write(marker, {"source": str(ROOT), "disposable": True})
    for name in ("platform", "workspace", "research", "smoke"):
        (STATE / name).mkdir(exist_ok=True)
    if os.name == "nt":
        # Restrict only this newly designated demo tree, never another store.
        sid = next(
            csv.reader(
                io.StringIO(
                    subprocess.check_output(
                        ["whoami", "/user", "/fo", "csv", "/nh"], text=True
                    )
                )
            )
        )[1]
        command(
            [
                "icacls",
                STATE,
                "/inheritance:r",
                "/grant:r",
                f"*{sid}:(OI)(CI)F",
                "*S-1-5-18:(OI)(CI)F",
            ],
            stdout=subprocess.DEVNULL,
        )
    else:
        STATE.chmod(0o700)


def source_hash(paths):
    digest = hashlib.sha256()
    for path in sorted(paths):
        if path.is_file():
            digest.update(path.relative_to(ROOT).as_posix().encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def runtime_source():
    return source_hash(
        [
            *(ROOT / "server/earthsync").rglob("*.py"),
            *(ROOT / "server/earthsync").rglob("*.sql"),
            *(ROOT / "server/earthsync/research").glob("*.json"),
            *(ROOT / "app/lib").rglob("*.dart"),
            *(ROOT / "app/web").rglob("*"),
            ROOT / "app/pubspec.lock",
            ROOT / "server/requirements.lock",
            Path(__file__),
        ]
    )


def setup(ports, rebuild=False):
    if sys.version_info < (3, 12):
        raise RuntimeError("Python 3.12+ is required")
    for tool in ("cargo", "rustc"):
        if not shutil.which(tool):
            raise RuntimeError(
                f"{tool} missing. Install Rust with rustup and the native linker/build tools, then reopen PowerShell."
            )
    flutter = flutter_sdk()
    print(f"Python {sys.version.split()[0]} · Flutter SDK: {flutter}", flush=True)
    if not PYTHON.is_file():
        command([sys.executable, "-m", "venv", VENV])
    lock_hash = hashlib.sha256(
        (ROOT / "server/requirements.lock").read_bytes()
    ).hexdigest()
    installed = RUNTIME / "python-lock.json"
    if rebuild or read(installed, {}).get("sha256") != lock_hash:
        command(
            [
                PYTHON,
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "-r",
                ROOT / "server/requirements.lock",
            ]
        )
        command([PYTHON, "-m", "pip", "check"])
        write(installed, {"sha256": lock_hash})
    command(["cargo", "build", "--locked", "--examples"], cwd=ROOT / "engine")
    command(["cargo", "build", "--release", "--locked"], cwd=ROOT / "app/rust")
    web_key = source_hash(
        [
            *(ROOT / "app/lib").rglob("*.dart"),
            *(ROOT / "app/web").rglob("*"),
            *(ROOT / "app/assets").rglob("*"),
            ROOT / "app/pubspec.yaml",
            ROOT / "app/pubspec.lock",
        ]
    )
    build = {
        "source": web_key,
        "platform_port": ports["platform"],
        "web_port": ports["web"],
        "sdk": str(flutter),
    }
    if (
        rebuild
        or read(RUNTIME / "web-build.json", {}) != build
        or not (ROOT / "app/build/web/index.html").is_file()
    ):
        command([flutter, "pub", "get", "--enforce-lockfile"], cwd=ROOT / "app")
        command(
            [
                flutter,
                "build",
                "web",
                "--release",
                "--no-web-resources-cdn",
                f"--dart-define=PLATFORM_URL=http://127.0.0.1:{ports['platform']}",
                f"--dart-define=WEB_DEMO_URL=http://127.0.0.1:{ports['web']}/",
                f"--dart-define=BACKEND_URL=http://127.0.0.1:{ports['web']}",
                "--dart-define=EARTHSYNC_JUDGES_DEMO=true",
            ],
            cwd=ROOT / "app",
        )
        command([PYTHON, ROOT / "scripts/finalize_offline.py", ROOT / "app/build/web"])
        write(RUNTIME / "web-build.json", build)
    for asset in (
        "server/earthsync/research/plant_health.json",
        "server/earthsync/research/additional_evidence.json",
        "data/crop-knowledge/v2/catalog.json",
        "server/earthsync/platform_v1/migrations/041_realtime_crop_compat.sql",
    ):
        if not (ROOT / asset).is_file():
            raise RuntimeError("Missing runtime source asset: " + asset)
    secure_state()
    command(
        [PYTHON, "-m", "earthsync.demo_workspace", STATE / "workspace"],
        env=environment(),
        stdout=subprocess.DEVNULL,
    )
    command([PYTHON, ROOT / "scripts/verify_7x_integrity.py"], env=environment())


def http(method, url, *, body=None, content=None, headers=None, expected=200):
    import httpx

    with httpx.Client(timeout=35, trust_env=False) as client:
        response = client.request(
            method, url, json=body, content=content, headers=headers
        )
    if response.status_code != expected:
        raise RuntimeError(
            f"Local HTTP {method} {url.split('?')[0]} returned {response.status_code}; expected {expected}"
        )
    return (
        response.json()
        if response.headers.get("content-type", "").startswith("application/json")
        else response.content
    )


def urls(ports):
    return {name: f"http://127.0.0.1:{port}" for name, port in ports.items()}


def healthy(run):
    if not run or run.get("status") not in {"starting", "ready"}:
        return False
    try:
        endpoint = urls(run["ports"])
        return bool(
            http("GET", endpoint["platform"] + "/api/platform/v1/ready")["ready"]
            and http("GET", endpoint["web"] + "/api/v1/health")["status"] == "ok"
        )
    except Exception:
        return False


def worker(role, instance, ports):
    import uvicorn

    env = environment()
    native = ROOT / f"engine/target/debug/examples/v03_demo{EXE}"
    catalog = ROOT / "data/crop-knowledge/v1/catalog.json"
    endpoint = urls(ports)
    env.update(
        EARTHSYNC_PLATFORM_LOCAL="1",
        EARTHSYNC_PLATFORM_DIR=str(STATE / "platform"),
        EARTHSYNC_PLATFORM_ORIGINS=endpoint["web"],
        EARTHSYNC_V03_EXECUTABLE=str(native),
        EARTHSYNC_V03_SHA256=hashlib.sha256(native.read_bytes()).hexdigest(),
        EARTHSYNC_CATALOG_PATH=str(catalog),
        EARTHSYNC_CATALOG_SHA256=hashlib.sha256(catalog.read_bytes()).hexdigest(),
        EARTHSYNC_REALTIME_ENABLED="1",
        EARTHSYNC_PUBLIC_NASA_CACHE="1",
        EARTHSYNC_EVIDENCE_DIR=str(STATE / "workspace"),
        EARTHSYNC_EVIDENCE_TOKEN_FILE=str(STATE / "workspace/workspace-token.txt"),
        EARTHSYNC_EVIDENCE_ORIGINS=endpoint["web"],
        EARTHSYNC_RESEARCH_LOCAL="1",
        EARTHSYNC_RESEARCH_DIR=str(STATE / "research"),
        EARTHSYNC_RESEARCH_ORIGINS=endpoint["web"],
    )
    os.environ.update(env)
    sys.path.insert(0, str(ROOT / "server"))
    apps = {
        "web": "earthsync.web_demo:app",
        "platform": "earthsync.platform_v1.api:app_factory",
        "research": "earthsync.research.api:app_factory",
    }
    server = uvicorn.Server(
        uvicorn.Config(
            apps[role],
            factory=role != "web",
            host="127.0.0.1",
            port=ports[role],
            workers=1,
            proxy_headers=False,
            access_log=False,
        )
    )

    def monitor():
        while not server.should_exit:
            if (RUNTIME / f"stop-{instance}").exists():
                server.should_exit = True
                break
            time.sleep(0.25)

    threading.Thread(target=monitor, daemon=True).start()
    server.run()


def supervise(instance, ports):
    children, logs = [], []
    stop_file = RUNTIME / f"stop-{instance}"
    record = {
        "instance": instance,
        "pid": os.getpid(),
        "ports": ports,
        "status": "starting",
        "children": {},
        "runtime_source": runtime_source(),
    }
    try:
        for role in ("platform", "web", "research"):
            log = (RUNTIME / f"{role}.log").open("a", encoding="utf-8")
            logs.append(log)
            child = subprocess.Popen(
                [
                    str(PYTHON),
                    str(Path(__file__)),
                    "worker",
                    "--role",
                    role,
                    "--instance",
                    instance,
                    "--ports",
                    json.dumps(ports),
                ],
                cwd=ROOT,
                env=environment(),
                stdout=log,
                stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
            )
            children.append(child)
            record["children"][role] = child.pid
        write(RUN, record)
        while not stop_file.exists() and all(p.poll() is None for p in children):
            time.sleep(0.25)
    except KeyboardInterrupt:
        pass
    finally:
        stop_file.touch()
        for child in children:
            try:
                child.wait(timeout=35)
            except subprocess.TimeoutExpired:
                # These handles refer only to this supervisor's own children.
                child.terminate()
                child.wait(timeout=10)
        for log in logs:
            log.close()
        write(RUN, {**record, "status": "stopped"})
        stop_file.unlink(missing_ok=True)


def start(no_browser=False, rebuild=False):
    previous = read(RUN)
    if (
        not rebuild
        and healthy(previous)
        and previous.get("runtime_source") == runtime_source()
    ):
        endpoint = urls(previous["ports"])["web"]
        print(f"\nEARTHSYNC READY: {endpoint}\nLogs: {RUNTIME}")
        if not no_browser:
            webbrowser.open(endpoint)
        return previous
    if previous and previous.get("status") in {"starting", "ready"}:
        stop()
    ports = config()
    setup(ports, rebuild)
    instance = uuid.uuid4().hex
    with (RUNTIME / "supervisor.log").open("a", encoding="utf-8") as log:
        subprocess.Popen(
            [
                str(PYTHON),
                str(Path(__file__)),
                "serve",
                "--instance",
                instance,
                "--ports",
                json.dumps(ports),
            ],
            cwd=ROOT,
            env=environment(),
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            close_fds=True,
            creationflags=(
                subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
            )
            if os.name == "nt"
            else 0,
            start_new_session=os.name != "nt",
        )
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        run = read(RUN)
        if run and run.get("instance") == instance:
            if run.get("status") == "stopped":
                raise RuntimeError(f"A required service failed. Inspect {RUNTIME}")
            if healthy(run):
                endpoint = urls(ports)
                # Confirm research service is enforcing authentication and loaded.
                http(
                    "GET",
                    endpoint["research"] + "/api/research/v1/health",
                    expected=401,
                )
                write(RUN, {**run, "status": "ready"})
                print(
                    f"\nEARTHSYNC READY: {endpoint['web']}\nLogs: {RUNTIME}\nPersistent demo state: {STATE}",
                    flush=True,
                )
                if not os.getenv("EARTHDATA_TOKEN"):
                    print(
                        "Earthdata not configured: satellite numeric data uses verified cache or reports unavailable."
                    )
                if not no_browser:
                    webbrowser.open(endpoint["web"])
                return read(RUN)
        time.sleep(0.5)
    stop()
    raise RuntimeError(f"Startup readiness timed out. Inspect {RUNTIME}")


def stop():
    run = read(RUN)
    if not run or run.get("status") == "stopped":
        print("EarthSync is stopped.")
        return
    instance = run.get("instance", "")
    if len(instance) != 32 or any(c not in "0123456789abcdef" for c in instance):
        raise RuntimeError("Invalid lifecycle record; no process was signalled")
    # A unique file is observed only by this instance's supervisor and workers.
    # No PID is killed, so a reused PID can never stop another application.
    (RUNTIME / f"stop-{instance}").touch()
    deadline = time.monotonic() + 55
    while time.monotonic() < deadline:
        current = read(RUN)
        if current.get("instance") != instance or current.get("status") == "stopped":
            print("EarthSync services stopped; demo data preserved.")
            return
        time.sleep(0.25)
    raise RuntimeError(
        "Supervisor did not acknowledge stop. No unrelated process was killed; inspect supervisor.log."
    )


def smoke(run):
    import sqlite3
    from PIL import Image

    endpoint = urls(run["ports"])
    base = endpoint["platform"] + "/api/platform/v1"
    result = {
        "classification": "ACTUAL_LOCAL_HTTP; synthetic photo only; provider states reported separately",
        "checks": [],
    }

    def passed(name):
        result["checks"].append(name)
        print("PASS", name, flush=True)

    assert http("GET", base + "/ready")["rust_v03_startup_probe_passed"]
    passed("platform storage and actual Rust startup probe")
    assert b"flutter_bootstrap.js" in http("GET", endpoint["web"] + "/")
    assert len(http("GET", endpoint["web"] + "/main.dart.js")) > 100000
    passed("Flutter Web release assets")
    snapshot = http("GET", base + "/realtime/ames")
    assert "sources" in snapshot
    result["live_provider_states"] = {
        k: {"status": v.get("status"), "error": v.get("last_error") or v.get("error")}
        for k, v in snapshot["sources"].items()
    }
    passed("real-time persisted cache API; live availability listed separately")
    crop = http(
        "POST", base + "/crop-intelligence", body={"crop": "maize", "question": "soil"}
    )
    assert crop["citations"] and crop["recommendation_eligible"] is False
    passed("FTS5 crop RAG with citations and blocked recommendation eligibility")
    http("POST", base + "/realtime/ames/ndvi-overlay/refresh", expected=202)
    overlay = http("GET", base + "/realtime/ames/ndvi-overlay")
    assert overlay["status"] in {"loading", "cached", "unavailable"}
    result["ndvi_status"] = {k: v for k, v in overlay.items() if k != "data"}
    passed("NDVI overlay API with truthful cache/unavailable contract")
    farm = http(
        "POST",
        base + "/farms",
        expected=201,
        body={
            "name": "AUTOMATED SYNTHETIC PHOTO TEST",
            "confirmed_point": {"latitude": 42.0308, "longitude": -93.6319},
            "confirmed_on": datetime.now(timezone.utc).date().isoformat(),
            "production_system": "rainfed",
        },
    )
    route = base + "/farms/" + farm["id"]
    image = io.BytesIO()
    Image.new("RGB", (40, 40), "brown").save(image, format="PNG")
    photo = None
    try:
        photo = http(
            "POST",
            route + "/photos",
            content=image.getvalue(),
            headers={"content-type": "image/png"},
            expected=201,
        )
        report = http(
            "POST",
            route + f"/photos/{photo['id']}/lab-extraction",
            expected=201,
            body={},
        )
        result["ocr_status"] = report["original"]["status"]
        passed("private synthetic photo upload and safe report extraction response")
        assert http("GET", route)["id"] == farm["id"]
        with sqlite3.connect(STATE / "platform/platform.sqlite3") as db:
            assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert (
                db.execute(
                    "SELECT count(*) FROM schema_migrations WHERE version=41"
                ).fetchone()[0]
                == 1
            )
        passed("database reopening, integrity and combined forward migration")
    finally:
        if photo:
            http("DELETE", route + f"/photos/{photo['id']}", expected=204)
        # No farm-delete API is exposed. Remove only the exact newly-created
        # synthetic fixture, after deleting its object through ownership checks.
        with sqlite3.connect(STATE / "platform/platform.sqlite3") as db:
            db.execute("PRAGMA foreign_keys=ON")
            row = db.execute(
                "SELECT document FROM farms WHERE id=? AND owner=?",
                (farm["id"], "local-single-user"),
            ).fetchone()
            if row and json.loads(row[0])["name"] == "AUTOMATED SYNTHETIC PHOTO TEST":
                db.execute(
                    "DELETE FROM farms WHERE id=? AND owner=?",
                    (farm["id"], "local-single-user"),
                )
    http("GET", endpoint["research"] + "/api/research/v1/health", expected=401)
    passed("dedicated research API authentication boundary")
    command(
        [PYTHON, ROOT / "scripts/verify_7x_integrity.py"],
        env=environment(),
        stdout=subprocess.DEVNULL,
    )
    passed("immutable science catalogs and all 60 blocked rules")
    write(RUNTIME / "smoke.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action",
        choices=[
            "setup",
            "start",
            "stop",
            "test",
            "logs",
            "status",
            "reset-demo",
            "serve",
            "worker",
        ],
    )
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--instance")
    parser.add_argument("--ports")
    parser.add_argument("--role", choices=["web", "platform", "research"])
    args = parser.parse_args()
    RUNTIME.mkdir(exist_ok=True)
    # Re-execute into the isolated environment for runtime dependencies.
    if (
        args.action not in {"setup", "serve", "worker"}
        and PYTHON.is_file()
        and Path(sys.prefix).resolve() != VENV.resolve()
    ):
        return subprocess.call(
            [str(PYTHON), str(Path(__file__)), *sys.argv[1:]], cwd=ROOT
        )
    if args.action == "worker":
        worker(args.role, args.instance, json.loads(args.ports))
    elif args.action == "serve":
        supervise(args.instance, json.loads(args.ports))
    elif args.action == "start":
        start(args.no_browser, args.rebuild)
    elif args.action == "setup":
        setup(config(), args.rebuild)
    elif args.action == "stop":
        stop()
    elif args.action == "test":
        run = start(no_browser=True)
        smoke(run)
        if args.full:
            command(
                [PYTHON, "-m", "pytest", "server/tests", "ops/staging/tests", "-q"],
                env=environment(),
            )
            command(["cargo", "test", "--locked"], cwd=ROOT / "engine")
            flutter = flutter_sdk()
            command([flutter, "analyze"], cwd=ROOT / "app")
            command([flutter, "test"], cwd=ROOT / "app")
    elif args.action == "logs":
        for name in ("supervisor", "web", "platform", "research"):
            path = RUNTIME / f"{name}.log"
            print(f"\n{name}: {path}")
            if path.exists():
                print(
                    "\n".join(
                        path.read_text(encoding="utf-8", errors="replace").splitlines()[
                            -30:
                        ]
                    )
                )
    elif args.action == "status":
        run = read(RUN)
        print(
            json.dumps(
                {
                    "ready": healthy(run),
                    "url": urls(run["ports"])["web"] if run else None,
                    "logs": str(RUNTIME),
                },
                indent=2,
            )
        )
    elif args.action == "reset-demo":
        if not args.yes:
            raise RuntimeError(
                "Deliberate reset requires reset-demo --yes. Only this checkout's marked disposable demo state is affected."
            )
        secure_state()
        stop()
        # Rename within the verified sibling directory; preserve an undo copy.
        destination = STATE.with_name(
            STATE.name + "-reset-" + datetime.now().strftime("%Y%m%d-%H%M%S")
        )
        if destination.exists():
            raise RuntimeError("Reset archive already exists")
        STATE.rename(destination)
        print(f"Demo reset. Previous data preserved at {destination}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"EarthSync: {error}", file=sys.stderr)
        raise SystemExit(1)
