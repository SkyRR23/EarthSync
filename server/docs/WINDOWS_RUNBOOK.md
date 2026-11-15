# Windows API and Rust troubleshooting

Run in PowerShell from the isolated task worktree. Do not start a second service
on a port already used by another task. Python 3.13 is supported by the pinned
dependencies; Python 3.12 remains supported. Install Python 3.13, Rust stable and
Visual Studio Build Tools with the C++ desktop workload. Flutter is needed only
for the app build. `where.exe python` helps detect a Windows Store alias; commands
below use the explicit virtual-environment interpreter.

## Install and verify the backend

```powershell
py -3.13 --version
py -3.13 -m venv server/.venv
$Python = Join-Path $PWD 'server/.venv/Scripts/python.exe'
& $Python -m pip install -r server/requirements.lock
if ($LASTEXITCODE) { throw 'Pinned dependency installation failed' }
& $Python -m pip install --no-deps -e ./server
if ($LASTEXITCODE) { throw 'Backend installation failed' }
& $Python -m pip check
if ($LASTEXITCODE) { throw 'Dependency compatibility check failed' }
cargo build --locked --manifest-path engine/Cargo.toml --example web_engine
if ($LASTEXITCODE) { throw 'Rust build failed; do not run an old binary' }
Push-Location server
try {
    & $Python -m pytest -q
    if ($LASTEXITCODE) { throw 'Backend/Rust tests failed' }
    & $Python -m ruff check earthsync tests
    if ($LASTEXITCODE) { throw 'Lint failed' }
    & $Python -m ruff format --check earthsync tests
    if ($LASTEXITCODE) { throw 'Formatting failed' }
} finally { Pop-Location }
```

Use a fresh venv when switching Python versions. If no Python 3.13 wheel is
available for your architecture, do not randomly downgrade Pydantic; record the
architecture and pip error. The lock installed successfully on Linux CPython
3.13.18 in this task; Windows execution is covered by the added CI matrix and
still requires its actual CI/device result. Do not infer Windows validation from
Linux tests. No Python package versions or Rust schemas were changed here.

## Ports 8000 and 8080

API-only (native Flutter retrieves climate here and executes its native Rust bridge):

```powershell
$Python = Join-Path $PWD 'server/.venv/Scripts/python.exe'
& $Python -m uvicorn earthsync.api:app --app-dir server --host 127.0.0.1 --port 8000 --no-access-log
```

Web demo (serves Flutter and both APIs from one origin):

```powershell
$env:EARTHSYNC_DIAGNOSTICS = '1' # optional; fixed public point only
./Run-WebDemo.ps1
# After a successful build, restart with: ./Run-WebDemo.ps1 -SkipBuild
```

Do not use `--reload` or multiple workers on Windows for the demo: Uvicorn 0.38
uses a Selector loop in subprocess/reload configurations, which cannot launch
asyncio subprocesses on Windows. The normal single-worker command uses Proactor.
`ENGINE_CONFIGURATION` distinguishes this from NASA errors. A missing executable
also returns this code. Build the exact `engine/target/debug/examples/web_engine.exe`;
if you use a custom `CARGO_TARGET_DIR`, build this demo target at its default path.
Port 8000 does not expose the demo engine route. `/docs` alone does not prove a
Flutter web build exists; rebuild if `app/build/web` is absent.

In a second PowerShell window:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/v1/health
Invoke-RestMethod http://127.0.0.1:8080/api/v1/health
# Health is local liveness only: upstream_checked must remain false.
Invoke-RestMethod -Method Post http://127.0.0.1:8080/api/v1/diagnostics/nasa
Invoke-RestMethod -Method Post http://127.0.0.1:8080/api/v1/diagnostics/integration
# Require status=success and rust_execution=passed on the integration check.
# 404: set EARTHSYNC_DIAGNOSTICS=1 in the server terminal and restart first.
```

Disable diagnostics when finished (`Remove-Item Env:EARTHSYNC_DIAGNOSTICS` in the
server terminal, then restart). `.env.example` is documentation, not auto-loaded.
The run script disables HTTP access logs to avoid retaining field query strings.
Error responses omit coordinates, raw NASA bodies and process stderr.

## Check real NASA, captured replay and mock modes separately

Live historical request; repeat to see `cache.hit` change from false to true:

```powershell
$Uri = 'http://127.0.0.1:8080/api/v1/environment/season?latitude=16.85&longitude=96.15&start_year=2024&start_month=2&end_year=2024&end_month=2'
$Evidence = Invoke-RestMethod $Uri
$Evidence.cache
$Evidence.provenance.source_requests
$Evidence.environment.seasonal.observations
```

This is gridded modeled MERRA-2 context, with dates, units, spatial support,
retrieval provenance and coverage; it is not farm measurement, a forecast or a
crop recommendation. Missing days produce null monthly aggregates, never zero.
A cache hit preserves the original retrieval time. Failures are not cached and
there is no stale-data fallback. The live diagnostic always bypasses this cache.

Replay the committed real capture through the actual HTTP Rust engine:

```powershell
$Captured = Invoke-RestMethod http://127.0.0.1:8080/api/demo/captured-climate
$Request = @{
    data_mode = 'supplied_data'
    field = @{ field_id='public-replay-point'; latitude=$Captured.environment.latitude; longitude=$Captured.environment.longitude; current_crop=''; irrigation_available=$null }
    soil = @{ texture=$null; drainage=$null }
    environment = $Captured.environment
    crop_references = @{ sources=@(); profiles=@() }
    scenarios = @()
}
$Result = Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8080/api/engine/integration -ContentType 'application/json' -Body ($Request | ConvertTo-Json -Depth 30)
$Result.status
$Result.data.climate
```

Keep `$Captured` alongside `$Result`; Rust cannot carry the complete provenance
sidecar. Never reuse that capture for another field/window. In the browser use
`http://127.0.0.1:8080/?climate=captured` and select the capture's public point and
February 2024. It is offline evidence, not new retrieval. Ordinary live fields
and windows remain global.

`http://127.0.0.1:8080/?engine=mock` is the existing Flutter presentation fixture
mode. It makes no real NASA or Rust claim. Independent NASA-shaped mocks are
exercised by `python -m pytest tests/test_backend.py tests/test_reliability.py`
from `server/`; raw real captures are separately labeled replay tests. Synthetic
Rust endpoint tests exercise the real engine on hypothetical data; they do not
validate Flutter mock mode. Browser UI and mock-mode visual checks need a real
Flutter build and must be reported separately.

A recent request can return 502 `UPSTREAM_SOURCE_CHANGED` even when NASA responds
200: the observed October 2026 Iowa response has `sources:["GEOSIT"]`. Inspect
[the source extension proposal](GEOS_IT_CONTRACT_PROPOSAL.md). Do not relabel it
MERRA-2 or substitute the old capture. No fixed publication lag guarantees lineage.

## Same-origin Wi-Fi web hosting

```powershell
./Run-WebDemo.ps1 -SkipBuild -BindAddress 0.0.0.0 -Port 8080
ipconfig
Get-NetTCPConnection -LocalPort 8000,8080 -ErrorAction SilentlyContinue
```

Use the PC's Wi-Fi IPv4 (for example `http://192.168.1.50:8080/`) on the second
device. `0.0.0.0` is a bind address, not the browser URL. Both devices must be on
the same reachable network; guest/AP client isolation may block them. Allow only
the needed private-network inbound port through Windows Firewall if prompted.
Check `/api/v1/health` from the second device first, then the explicit live
diagnostic. If localhost works but the device cannot reach health, investigate
bind address, port ownership, routing and firewall before NASA.

A configured HTTP proxy can also intercept private-address requests. In this
cloud task, a proxy-routed `curl` to the host's private address returned 403,
while the direct local connection returned 200. For a local development check,
use `curl.exe --noproxy "*" http://<PC-Wi-Fi-IPv4>:8080/api/v1/health`, or configure
`NO_PROXY` for localhost and the development host. Do not print proxy URLs or
credentials in diagnostics. A proxy rejection does not establish a NASA failure.

Flutter Web fetches both APIs relative to the page origin. Serve the app and API
on the same host/port to avoid cross-origin requests. An HTTPS page cannot call
an HTTP backend due to mixed-content rules. Existing localhost/same-origin HTTP
policy is retained. No blanket CORS or Android cleartext relaxation was added.
A cloud host reaching its own network address does not prove physical Wi-Fi or
Windows Firewall behavior; perform the second-device check above.

## Android USB and emulator

Existing debug network policy already permits the configured loopback/emulator
hosts. Keep it; no policy change is needed for USB:

```powershell
adb devices
adb reverse tcp:8000 tcp:8000
adb reverse --list
Push-Location app
try { flutter run --debug --dart-define=BACKEND_URL=http://127.0.0.1:8000 }
finally { Pop-Location }
# When finished:
adb reverse --remove tcp:8000
```

For the Android emulator use
`flutter run --debug --dart-define=BACKEND_URL=http://10.0.2.2:8000` from `app/`.
For native Android over Wi-Fi, use a reachable HTTPS backend and the existing
`BACKEND_URL` configuration. Current native client policy does not permit an
arbitrary LAN HTTP host; do not bypass it by reopening the already fixed HTTP
policy. Opening the same-origin web demo in the phone browser is a separate flow.
Health on the PC does not prove native Flutter permissions, USB routing or FFI;
run the opt-in Flutter live integration suite/device checks independently.

## Read the error before retrying

[The API error table](API_V1.md#reliability-extension-additive-http-boundary-only)
separates local network/configuration, provider rejection, invalid metadata,
missing coverage, deadlines and Rust failure. NASA attempts are bounded to three
per year chunk, with 5-second connect/20-second HTTP timeouts and a 70-second
whole retrieval deadline. The API deadline is 80 seconds including cache wait;
the current climate client waits 90 seconds. Rust has a 5-second queue wait plus
20-second execution; its web client waits 30 seconds. These are upper bounds,
not scientific freshness or reliability guarantees. Do not increase client
waits to conceal wrong lineage or malformed responses.
