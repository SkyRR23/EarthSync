# Run the integrated EarthSync application

This is a local/demo agricultural evidence application. Browse without a farm;
confirm a farm to open field context, photos and crop assessments. All real catalog
profiles remain reference-only. Soil/weather/HLS/OPERA observations are unavailable.
Read [audit](AUDIT.md), [verification](VERIFICATION.md) and
[source manifest](source-manifest.json) before treating software execution as
scientific validation.

## Windows PowerShell

Install Git, Flutter **3.50.0** (includes Dart 3.14.0), Rust **1.99.0**, and Python
3.12 or 3.13. Run from this branch's repository root:

```powershell
py -3.13 -m venv server/.venv
& ./server/.venv/Scripts/python.exe -m pip install -r server/requirements.lock
& ./server/.venv/Scripts/python.exe -m pip install --no-deps -e ./server
& ./server/.venv/Scripts/python.exe -m pip check
./Run-WebDemo.ps1
```

The script installs the committed Flutter lockfile, compiles the actual Rust
executable, builds the actual main application with local renderer assets, and
starts **one** backend at `http://127.0.0.1:8080`. A full JDK and Android SDK are
unnecessary for the web build. `-SkipBuild` requires both artifacts already built.

Photos use a dedicated directory under `$env:LOCALAPPDATA/EarthSync/` (override
with `-EvidenceDirectory C:/absolute/private/path`). The launcher sets private
Windows ACLs and generates `workspace-token.txt` there, without printing its value.
Read that file locally and paste it into **Field photos → Connect private workspace**.
Treat it as a password. It stays only in app session memory, is cleared on refresh,
and is never included in assets, farm records, URLs, assistant context or access
logs. Disconnect to clear it sooner. Do not commit the file or share screenshots
of its contents. The PowerShell/ACL flow still needs interactive Windows validation;
see the report's exact verified scope.

For other devices on trusted local Wi-Fi:

```powershell
./Run-WebDemo.ps1 -SkipBuild -BindAddress 0.0.0.0 -Port 8080
```

Open `http://<PC-Wi-Fi-IPv4>:8080`. Climate and public context work through the same
origin. Device GPS can be denied on non-HTTPS origins; manual selection still works.
**Private photos require localhost or properly configured HTTPS**; the mounted
backend rejects remote plain-HTTP photo requests. Do not distribute the token to
other users or set a public wildcard CORS policy. Physical LAN verification remains
separate from same-host HTTP tests.

## Linux / macOS shell

Use the same toolchain versions, then from the repository root:

```sh
python3 -m venv server/.venv
server/.venv/bin/python -m pip install -r server/requirements.lock
server/.venv/bin/python -m pip install --no-deps -e server
cargo build --locked --manifest-path engine/Cargo.toml --example web_engine
(cd app && flutter pub get --enforce-lockfile && flutter build web --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run)
export EARTHSYNC_EVIDENCE_DIR="$PWD/../earthsync-private-evidence"
PYTHONPATH=server server/.venv/bin/python -m earthsync.demo_workspace "$EARTHSYNC_EVIDENCE_DIR"
export EARTHSYNC_EVIDENCE_TOKEN_FILE="$EARTHSYNC_EVIDENCE_DIR/workspace-token.txt"
PYTHONPATH=server server/.venv/bin/python -m uvicorn earthsync.web_demo:app --host 127.0.0.1 --port 8080 --no-access-log
```

Keep the evidence directory outside the checkout, owned by your account, and out
of shared/static folders. Directory/file modes are 0700/0600 on POSIX. If token
configuration is absent, photos fail closed; the other services remain usable.
`--pwa-strategy=none` is supported but deprecated in Flutter 3.50; it prevents the
local development host from retaining stale service-worker bundles. No offline
provider fallback is enabled.

## Working URLs on the normal launcher

| Method | URL suffix | Purpose |
| --- | --- | --- |
| GET | `/` | Main Flutter application |
| GET | `/docs` | Main API workbench (private child routes documented here) |
| GET | `/api/v1/health` | Process health only; `upstream_checked=false` |
| GET | `/api/v1/environment/season` | Existing validated historical POWER query |
| POST | `/api/environmental/v1/context` | Environmental availability/reference envelopes |
| POST | `/api/satellite/v1/timeline` | Public satellite availability; no private photos |
| GET/POST | `/api/evidence/v1/photos` | Private list/upload, bearer authorization required |
| GET/PUT/DELETE | `/api/evidence/v1/photos/{id}` | Private metadata/replace/delete |
| GET | `/api/evidence/v1/photos/{id}/image` | Sanitized private image |
| POST | `/api/evidence/v1/timeline` | Authorized photo and optical/SAR timeline |
| POST | `/api/assistant/v1/chat` | Stateless deterministic evidence explanation |
| POST | `/api/engine/integration`, `/api/engine/v02`, `/api/engine/v03` | Real compiled Rust versioned execution |
| GET | `/api/catalog/v1/profiles` | Validated catalog, graph, explicit mapping/blockers |
| POST | `/api/catalog/v1/assessment-request` | Reference-only v0.3 handoff for a declared farm/period |
| GET | `/api/demo/synthetic-v03` | Explicit fictional software-test request |

Private routes retain `evidence.v1` errors and no-store headers. Other interfaces
retain safe JSON error envelopes. Static hosting never handles an unknown `/api/`
path. Same-origin web hosting needs no permissive CORS. Native applications use
`BACKEND_URL` consistently; the Rust calculation remains native on Android.

The existing opt-in `?climate=captured` replay and `?engine=mock` fixture modes
remain explicit. Neither is selected on live failure. Captured mode's fixed
coordinates/period must match its capture; regional exploration always uses the
live backend. NASA data from unsupported GEOS-IT lineage remain rejected: select
an older completed historical period instead of disabling the guard.

## Android build and run

Install Android Studio's full JDK, SDK platforms 35 and 36, build tools 35.0.0 and
36.0.0, NDK 28.2.13676358, and Rust Android targets. Then:

```sh
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cd app
flutter pub get --enforce-lockfile
flutter build apk --debug --dart-define=BACKEND_URL=http://127.0.0.1:8080
adb devices -l
adb reverse tcp:8080 tcp:8080
flutter run -d <device-id> --dart-define=BACKEND_URL=http://127.0.0.1:8080
```

Start the unified backend on host port 8080 first. `adb reverse` keeps all services,
including private photo access, on loopback. A trusted HTTPS backend is the other
supported photo option. Use an HTTPS URL for release deployments; debug-only
cleartext exceptions must not be broadened into the release manifest. Camera,
location permission denial, gallery upload, refresh/restart persistence and native
FFI must still be checked on a real device. APK compilation is not device testing.

The native v0.3 path uses the existing generated `analyzeIntegrationJson` FRB
string ABI, with explicit `schema_version=earthsync.engine.v0.3.0` dispatch in the
Rust wrapper. The Dart v0.3 wrapper validates the version and retains every result
state, input/source reference and limitation. No generated binding signature or
content hash was manually edited. Existing integration and v0.2 library/HTTP
interfaces are preserved.

## Reproduce the synthetic assessment

In the app: confirm a farm → **Crop assessment → Run labeled synthetic v0.3
demonstration**. The fixture has fictional crops, coefficients and observations
and never uses the saved farm. The actual Rust engine executes; the result stays
`software_test_only=true` and whole scenarios remain insufficient.

Or with the launcher running:

```sh
curl --fail http://127.0.0.1:8080/api/demo/synthetic-v03 -o /tmp/earthsync-v03-request.json
curl --fail http://127.0.0.1:8080/api/engine/v03 -H 'Content-Type: application/json' --data-binary @/tmp/earthsync-v03-request.json
```

To assess a real reference profile, choose its explicitly named research scope and
enter your own exact growing dates. The adapter preserves source desk-review
status and missing inputs; Rust reports insufficient information. No regional
suitability, yield, planting-date recommendation, diagnosis or ranked rotation is
established by this software demonstration.

## Re-run interactive browser acceptance

Start the main unified app first, using a dedicated private test workspace. The
runner creates a labeled test farm/photo and deletes its uploaded photo after
the CRUD checks. Install the separate browser-test dependency (not required to
run the backend), then point it at an installed Chromium/Chrome executable:

```sh
python -m pip install playwright==1.65.2
python -u scripts/browser_7h.py --base-url http://127.0.0.1:8080 --token-file /absolute/private/workspace-token.txt --chromium /absolute/path/to/chromium
```

The executable defaults to `/usr/bin/chromium` on Linux. On Windows, use your
Chrome/Chromium `.exe` path and a private token-file path. Keep credentials out
of command arguments: the argument is the token **file path**, never its value.
The runner explicitly aborts one climate request to check outage/recovery; all
other app responses come from the running services and real compiled Rust.
Provider availability can make this live acceptance run fail. Read the failure
and report it; do not substitute a captured response to make the run pass.
