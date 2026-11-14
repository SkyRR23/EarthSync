# EarthSync 7Q: restricted staging and release operations

Use the tested existing Flutter Web + FastAPI + compiled Rust + SQLite design.
This PR changes **only operations files**. It does not merge 7H/7I/7L, replace a
backend, implement identity, or deploy a service. Keep the operations PR draft.

Deadline: **November 15, 2026, 18:00 Myanmar time (11:30 UTC)**. Prioritize one
working local demonstration and a rehearsed restore. Personal-server access has
not been supplied or verified. Team-server deployment requires separate explicit
authorization after acceptance of 7N's final reviewed source SHA.

Read [verification](VERIFICATION.md), [release gates](RELEASE.md), and the
[7N handoff](HANDOFF_7N.md). Reports contain scoped results; a platform PASS is
not complete UI/server acceptance.

## Audited sources and boundaries

| Component | Audited SHA | Existing instructions / entrypoint |
| --- | --- | --- |
| 7H #20 | `a7c33cc6b58703501bbba0ceba1bad1d6d42004b` | `docs/integration/README.md`, `Run-WebDemo.ps1`, `earthsync.web_demo:app` |
| 7I #19 | `b578a6df2764479ff9c9df006cc00e5ddb3ccfa3` | `server/docs/platform_v1/README.md`, `earthsync.platform_v1.api:app_factory` |
| 7L #21 | `bd8d245b0eae92aab353d852baf05adba5527384` | `docs/MILESTONE_7L.md`, locked Flutter app |
| Final 7N RC | See `docs/integration/7n/source-manifest.json` and final verification | Combined source; build a clean immutable checkout with the final full SHA |

The web host serves Flutter and existing 7H services on 8080. Its health endpoint
is liveness, not provider/Rust readiness. The independent 7I service uses 8021 and
checks SQLite integrity plus an actual Rust startup execution at `/api/platform/v1/ready`.
It rejects remote peers, non-loopback Host values and unapproved Origins. Run one
worker per service. Neither process may expose 7I routes through a reverse proxy.

7H photo data are SQLite **image BLOBs** (`evidence.sqlite3`) plus a private
workspace token. 7I photo rows refer to separate sanitized PNG objects beside
`platform.sqlite3`. These stores, ownership models, and farm IDs are different.
7N adds explicit local-farm-ID/confirmation-revision links to server UUIDs.
Daily evidence, history and real Rust decisions are persisted after explicit UI
actions; selected area/device position stay separate. Workspace photos do not
migrate automatically. See `docs/integration/7n/DATABASE.md` for the ownership model.

## Install and pin tools

Install Git, Python **3.12** (tested here: **3.12.14**), Rust **1.99.0** via rustup,
and Flutter matching the accepted app lock. Use trusted official distributions,
verify published SDK checksums, retain TLS verification and record `git --version`,
`python --version`, `rustc --version`, `cargo --version`, `flutter --version`.
On Linux, install the distro's C compiler/linker/build-essential and CA certificates.
On Windows, use Git for Windows, Python with the `py` launcher, and Visual Studio
Build Tools with Desktop C++ and the Windows SDK. A full Android SDK/JDK is not
required for Flutter Web. See Android below for its additional toolchain.

7N selected Flutter **3.44.0** / Dart **3.12.0** after reviewing both locks and
verifying `flutter pub get --enforce-lockfile`, tests, analyzer and release builds.
The operations build defaults to that SDK and includes
`--dart-define=PLATFORM_URL=http://127.0.0.1:8021`. `--platform-url` and
`--web-origin` allow only exact loopback origins; both values are recorded in the
manifest. The platform admits only the recorded browser origin (default
`http://127.0.0.1:8080`). A run-port override must match its build manifest.
Rust's crate package version 0.1.0 is not the protocol version: the runtime smoke
checks `earthsync.engine.v0.3.0`.

`staging.py build` creates a fresh venv and installs the **existing** exact lock
for its profile, checks pip compatibility, uses Cargo `--locked`, and hashes the
binary, catalog, locks, migrations and web assets/runtime snapshot. It records
installed packages and tool versions in private `manifest.json`. Startup rechecks
the source SHA, application cleanliness, hashes, migration set and installed
package list. SHA-256 establishes artifact identity; review the manifest and
retain it independently. It is not an external signature or reproducible-build
attestation. Lock versions are reproducible inputs, not a bit-identical binary
guarantee across operating systems or SDK distributions.

7N reconciled the dependency sets: both profiles use the combined lock retaining
Pillow **12.2.0**, Windows tzdata and the reviewed platform/raster dependencies.
The platform lock includes `server/requirements.lock`; both files are hashed in
the operations manifest. Separate process venvs remain useful for artifact isolation.


## Linux: build and run tonight

Use one clean immutable combined source checkout and separate private state paths
outside every checkout/static directory. Examples use `/srv/earthsync-private`; create
this directory as your account or choose an equivalent writable private path.
Do not point these commands at another developer's active worktree.

```bash
# Fetch reviewed objects and create ONE clean immutable combined checkout.
git fetch origin '+refs/heads/*:refs/remotes/origin/*'
RC_SHA=530c1e1d06c9202dfc1f5d06c659399409b7270f
git worktree add --detach ../earthsync-rc "$RC_SHA"
rustup toolchain install 1.99.0 --profile minimal
export RUSTUP_TOOLCHAIN=1.99.0
umask 077
mkdir -p /srv/earthsync-private
chmod 700 /srv/earthsync-private

OPS=/absolute/path/to/earthsync-rc
WEB=$OPS
PLATFORM=$OPS
PRIVATE=/srv/earthsync-private
# The final tree already contains the reviewed catalog, sanitizer and assistant.
# Two private process states use one combined source and dependency lock.
python3.12 "$OPS/ops/staging/staging.py" build --profile platform --source "$PLATFORM" \
  --state "$PRIVATE/platform-release" --sha "$RC_SHA"
python3.12 "$OPS/ops/staging/staging.py" build --profile web --source "$WEB" \
  --state "$PRIVATE/web-release" --sha "$RC_SHA" --flutter-version 3.44.0

# Separate terminals, foreground lifecycle. Ctrl+C stops and preserves data.
python3.12 "$OPS/ops/staging/staging.py" run --source "$PLATFORM" --state "$PRIVATE/platform-release"
python3.12 "$OPS/ops/staging/staging.py" run --source "$WEB" --state "$PRIVATE/web-release"
```

The standalone platform build copies its package to `state/runtime` and supplies
the exact exported sanitizer/assistant packages when absent, as 7I's native
runbook specifies. It does not write into either source checkout. `--compat` is
unnecessary for a reviewed 7N tree containing the packages, catalog and v03_demo.
The web executable stays at the debug path required by the actual 7H web host;
the platform uses its actual `v03_demo --stdin` release executable. These are
different CLIs and must not be interchanged.

Private state includes `venv/`, `manifest.json`, `data/`, `service.log` and the
platform runtime snapshot. The reference [environment template](staging.env.example)
lists actual setting names. It is deliberately not automatically loaded. Startup
clears inherited EarthSync overrides and constructs paths/hashes from the manifest;
there are no live-to-mock fallback flags. The web token is generated once, stays
in `data/workspace-token.txt`, and must be read locally into the UI session.
Never paste its value into a command, URL, report, asset or repository file.

Startup/maintenance share an exclusive state-directory lock. A live service blocks
backup, restore, migration and cleanup using this tool. Stop it first. After an
unclean host failure, check the recorded PID and all backend processes/listeners;
only remove a stale `operation.lock` once no worker uses that state. Different
state roots must never be redirected to the same data. Run services using this
tool consistently; it cannot detect arbitrary manually launched writers.

## Windows PowerShell

Install/select the same pinned toolchains. Create the combined detached checkout as
above. Use dedicated NTFS paths outside OneDrive/shared/static directories. The
wrapper removes inherited permissions on its dedicated state root and grants
only the current account and SYSTEM inheritable access. Run it for **every**
state operation; Python's chmod does not establish Windows privacy ACLs.

```powershell
$Ops = 'C:\src\earthsync-rc'
$Web = $Ops
$Platform = $Ops
$RcSha = '530c1e1d06c9202dfc1f5d06c659399409b7270f'
$Private = 'C:\EarthSyncPrivate'
$env:RUSTUP_TOOLCHAIN = '1.99.0'
# First create/restrict $Private in Explorer Security to your account and SYSTEM.
& "$Ops\ops\staging\staging.ps1" -State "$Private\platform-release" build --profile platform --source $Platform --sha $RcSha
& "$Ops\ops\staging\staging.ps1" -State "$Private\web-release" build --profile web --source $Web --sha $RcSha --flutter-version 3.44.0
# Separate PowerShell windows; Ctrl+C stops the foreground process group.
& "$Ops\ops\staging\staging.ps1" -State "$Private\platform-release" run --source $Platform
& "$Ops\ops\staging\staging.ps1" -State "$Private\web-release" run --source $Web
Get-Acl "$Private\platform-release\data" | Format-List
icacls "$Private\platform-release\data" /T
```

Verify no broad Users/Everyone/inherited access on data, object files, logs,
receipts, tokens or backups. Windows ACL inheritance, process-group Ctrl+C and
the wrapper have not been interactively exercised here. The original 7H
`Run-WebDemo.ps1` is also available; its `-BindAddress 0.0.0.0` option is outside
this restricted workflow and must never be reused for the platform service.

## Database and HTTP acceptance in dedicated test state

Do not run mutation smoke against real user state. Build **new** state roots
such as `platform-smoke`/`web-smoke`; even named test farms consume persistent
rows. Keep reports/receipts private and outside source. Example after building
and starting a disposable platform state using the same commands as above:

```bash
TEST=/absolute/private/platform-smoke
PYTHONPATH="$TEST/runtime" "$TEST/venv/bin/python" "$OPS/ops/staging/database_check.py" \
  --report /absolute/private/db-check.json
PYTHONPATH="$TEST/runtime" "$TEST/venv/bin/python" "$OPS/ops/staging/smoke.py" \
  --scope platform --platform-state "$TEST" --disposable --live --receipt /absolute/private/http-receipt.json \
  --report /absolute/private/http-exercise.json
# The exercise returns 2 (INCOMPLETE) until the restart check is performed.
# Stop/restart the same disposable service; keep TEST/data and the receipt.
PYTHONPATH="$TEST/runtime" "$TEST/venv/bin/python" "$OPS/ops/staging/smoke.py" \
  --scope platform --platform-state "$TEST" --disposable --phase restart --receipt /absolute/private/http-receipt.json \
  --report /absolute/private/http-restart.json
```

Reports use **0 PASS, 1 FAIL, 2 INCOMPLETE**. Live checks require uncached real
historical NASA MERRA-2 data. An outage, rejected lineage or a cache hit does not
pass as a fresh live retrieval. The controlled outage check uses the real API
and transport with an explicitly injected HTTP 503 in a separate temporary DB:
the job completes with three explicit gaps, no evidence/cache writes, and no
synthetic fallback. A job status of `succeeded` alone is not data availability.

The restart receipt contains opaque test IDs and source context; treat it as
private. Restart proof covers farms, terminal job, evidence hashes, decisions
and sanitized photo bytes. It also requires a changed supervisor generation, so
repeating the check without restarting fails. The DB suite creates its own temporary root and
tests initial/repeat migration, foreign keys, integrity, complete backup/restore,
corrupt DB/object rejection, omitted references, absent objects, quotas, atomic
migration failure rollback, checksum mismatch recovery and POSIX permissions.
It never accepts a user database path. Windows permissions remain BLOCKED until
interactive ACL verification. Application quotas do not replace disk monitoring.

For both HTTP surfaces and the assistant, run smoke with `--scope full`, the
web workspace `--token-file`, `--platform-state`, both URLs if custom ports, and a fresh receipt.
`--web-url` / `--platform-url` only accept literal loopback origins. On Windows
use `$env:PYTHONPATH="$Test\runtime"` and `venv\Scripts\python.exe`.

**Complete Flutter UI requires browser acceptance**. HTTP asset loading cannot
establish navigation, rendered charts, refresh behavior or correct UI ownership.
For pinned 7H, install the existing runner dependency in a separate test venv:

```bash
python3.12 -m venv /absolute/private/browser-venv
/absolute/private/browser-venv/bin/python -m pip install playwright==1.65.2
/absolute/private/browser-venv/bin/python "$WEB/scripts/browser_7h.py" \
  --base-url http://127.0.0.1:8080 --token-file /absolute/private/web-smoke/data/workspace-token.txt \
  --chromium /usr/bin/chromium --output /absolute/private/browser-evidence
```

This uses installed Chromium, exercises actual services, and explicitly interrupts
one browser request for outage/recovery. Its screenshots can contain test farm
coordinates. Do not point output at tracked evidence directories. 7L changes
navigation; 7N must review/adapt acceptance to its final UI and include the 7I
farm/evidence/history path. This operations PR deliberately retains a BLOCKED
complete-UI result until that separate acceptance is recorded. Never replace a
failed live request with the existing opt-in captured/mock query modes.

## Offline backup, restore and rollback

Stop the service and verify no worker remains. For the platform, use **its same
verified source/venv/runtime and state**. Backups are directories, not archives;
destinations must be new. The authoritative implementation is 7I maintenance:

```bash
python3.12 "$OPS/ops/staging/staging.py" backup --source "$PLATFORM" --state "$PRIVATE/platform-release" --backup "$PRIVATE/backup-20261114-01"
python3.12 "$OPS/ops/staging/staging.py" restore --source "$PLATFORM" --state "$PRIVATE/platform-release" --backup "$PRIVATE/backup-20261114-01" --destination "$PRIVATE/restore-trial-01"
```

The backup includes `platform.sqlite3`, **all referenced objects**, and their
SHA-256 manifest. Restore verifies manifest paths/checksums, DB integrity/foreign
keys and object references, applies compatible migrations, and removes failed
new destinations. Checksums detect damage, not a malicious party replacing a
whole backup; protect/encrypt and separately retain its trusted manifest/hash.
Never run object cleanup to hide a missing-object error. Recover the missing
object from a known complete backup or retain the failure for investigation.

Test restoration using the release that produced the backup first. With services
stopped, retain the current `data` directory under a new dated name, then rename
the fully verified trial restore to `state/data`. Start and recheck readiness,
the known farm/decision/photo, and the candidate-specific smoke in test state.
Never restore on top of existing data. Do not delete the prior directory until
acceptance. If anything fails, stop, preserve diagnostics, restore the prior
binary/source **and its compatible pre-migration data backup**. SQLite migrations
have no automatic down-migration guarantee. Do not point an old executable at
an upgraded database and assume rollback is compatible.

7H's separate photo backup must preserve `data/evidence.sqlite3` and
`workspace-token.txt` while the web process is stopped. The photos are BLOBs in
that DB; there is no 7I object folder to copy. With no writers, copy the entire
dedicated web `data/` directory into a new private destination and verify the
SQLite copy using `PRAGMA integrity_check` and `PRAGMA foreign_key_check` before
accepting it. Store the token under private ACLs/encryption, separate from
transferable build artifacts. Restore to a new private directory, validate
DB/token and authorized image retrieval, then switch directories offline. A
server photo backup does not capture the browser's farm/preferences; preserve a
dedicated demo browser profile separately or re-enter the sample farm. Never
claim this migrates browser farms into 7I.

Linux: use owner-only directories/files and encrypted backup storage; inspect
`stat`/`find` and free disk space (`df -h`) before the event. Windows: apply and
inspect restrictive ACLs on new backup/restore parents **before** writing data;
Python chmod alone is insufficient. Leave headroom for both a complete backup
and a restore, logs, SQLite journals and new photos. Rotate `service.log` offline
by renaming it to a private dated file. Keep failures and version records; do
not enable request/access logs or dump raw bodies/tokens for diagnostics.

## Docker/native review

Reuse 7I's `server/platform-v1/Dockerfile`, `.dockerignore`, `container_start.py`
and Compose file. Its Dockerfile pins Rust/Python image digests, builds the real
v03_demo, installs pinned wheels, and runs UID 10001. BuildKit needs the existing
compatibility context plus Cargo vendor tree and ABI-matched wheelhouse. Follow
7I's commands; record image ID/digest and the exact context/lock checksums.
The signed Debian libexpat1 installation still depends on an apt repository;
fully repeatable offline rebuilds require retaining/reviewing that package too.

Compose uses Linux host networking **with an internal loopback bind**, no public
port mappings, a named persistent volume, read-only root, dropped capabilities,
no-new-privileges, CPU/memory/PID limits and a bounded tmpfs. It hosts **only 7I**,
not Flutter/7H. `docker compose down` retains data; **never add `-v`** to routine
shutdown. Do not change host networking to a published port or proxy 7I routes.
Do not assume this works on Docker Desktop. Prefer native staging tonight.
Docker container backup requires stopping the writer and running the existing
maintenance code with that same data volume from an offline maintenance container;
never copy a live DB/object tree. Test this separately before using container
storage for real data. See verification for what was actually rerun here.

## Android and remote-device access

Use a USB-connected trusted device and `adb reverse`; keep the backend on host
loopback. On-device 127.0.0.1 otherwise means the phone, not your server.

```bash
adb devices -l
adb reverse tcp:8080 tcp:8080
# Only when exercising the reviewed opt-in local platform adapter:
adb reverse tcp:8021 tcp:8021
cd /absolute/path/to/reviewed-source/app
flutter run -d DEVICE_ID --dart-define=BACKEND_URL=http://127.0.0.1:8080
# Undo when finished:
adb reverse --remove tcp:8080
adb reverse --remove tcp:8021
```

Build requirements from 7H: full JDK/Android SDK platforms 35/36, build-tools
35.0.0/36.0.0, NDK 28.2.13676358 and Rust targets aarch64-linux-android,
armv7-linux-androideabi, x86_64-linux-android. The Android bridge uses generated
FRB string ABI/version dispatch and actual native Rust libraries; the web CLI
binary cannot substitute for these. APK build success does not prove device
execution. Test location denial/manual selection, gallery/camera, token handling,
refresh/restart, native FFI and backend disconnection on the actual device.
Do not broaden debug cleartext exceptions into a release manifest.

For a remote personal server, an operator may explicitly establish an SSH local
forward on a trusted computer, keeping server/client listeners on loopback:
`ssh -N -L 127.0.0.1:8080:127.0.0.1:8080 -L 127.0.0.1:8021:127.0.0.1:8021 USER@SERVER`.
This is a restricted single-operator tunnel, not production identity or shared
private access. These commands are documentation only; no connection was made.

A separately authorized trusted HTTPS interface may allow **public/reference**
climate, environmental/satellite availability, catalog and bounded demonstration
engine routes after an exact route/rate/body/origin review. Do not use a blanket
`/api/` proxy rule. 7H private photos technically require HTTPS/localhost plus a
workspace bearer token, but that shared token is **not multi-user ownership**;
retain private use over the restricted tunnel/USB path for this demo. 7I farms,
evidence, jobs, history, decisions, assistant-context and photos must never be
published, even behind HTTPS, while its principal is local-single-user. Never
rewrite Host/forwarded headers to bypass the peer/Origin restrictions. Without
reviewed hosted authentication and authorization, shared team private access
is a release blocker. CORS and TLS do not supply user identity.

## Personal-server acceptance boundary

Yes: the final candidate can be tested on a dedicated trusted single-user personal
server using these loopback-only services and standard SSH local forwarding. No
personal server has been accessed, and this is not a public deployment approval.
Do not use a shared untrusted multi-user host: 7I trusts the local OS principal.

From the tester's computer, after separately approving server setup:

```sh
ssh -N -L 8080:127.0.0.1:8080 -L 8021:127.0.0.1:8021 user@personal-server
```

Open `http://127.0.0.1:8080` locally. Both forwards are required because the
private client intentionally targets loopback 8021. Keep the recorded browser
origin `http://127.0.0.1:8080`; no Host/Origin/peer check is disabled. Do not expose
8021 on a public interface, route it through a public parent API, enable wildcard
CORS, or embed a workspace token in assets. Public/multi-user testing of private
farmer records remains blocked without reviewed server identity/ownership.
