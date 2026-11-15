# Reproduce the 7X local candidate

Use the exact full final PR #28 head SHA, not an advancing branch tip or an older
7N/7W artifact. Keep the source checkout clean. Record `git rev-parse HEAD` and
retain the private build manifests separately. No public deployment is required.

## Pinned tools and fresh checkout

Git; Python 3.12; Rust 1.99.0; Flutter **3.44.0 / Dart 3.12.0**; Chromium.
Local Linux used Python 3.12.14 and the same Flutter image digest retained by 7N:
`ghcr.io/cirruslabs/flutter@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8`.
Its SDK reports framework revision `559ffa3f75e7402d65a8def9c28389a9b2e6fe42`.
Keep TLS verification, the checked-in dependency locks and scientific hashes.

```bash
git clone https://github.com/SkyRR23/EarthSync.git earthsync-rc
cd earthsync-rc
git fetch origin integration/earthsync-final-release-v1
RC_SHA=$(git rev-parse origin/integration/earthsync-final-release-v1)
# Compare this full SHA with the final reviewed PR head before proceeding.
git checkout --detach "$RC_SHA"
python3.12 -m venv ../earthsync-tools-venv
PY=$(cd ../earthsync-tools-venv/bin && pwd)/python
"$PY" -m pip install -r server/requirements.lock
"$PY" scripts/verify_7x_integrity.py
```

Use a **fresh checkout**, especially when replacing a previously converted Windows
worktree. Updating `.gitattributes` alone does not rewrite unchanged files already
on disk. Never recalculate the manifest to accept CRLF-converted scientific bytes.
The pinned v1 catalog hash is
`2926584bce3693dff7433afe9c05c535a6d5d1e609fb502d4e2f6017f398fb0e`;
v2 retains `9c61fc394bd73f990fa12cba21d77a3e21028c233b956e1ce31f664178ad241b`.

## Immutable 7Q builds and startup

Use a dedicated private parent outside the checkout, static assets and shared
folders. Both services bind 127.0.0.1 with proxy headers disabled. One worker each.

```bash
umask 077
REPO=$(pwd)
PRIVATE=$(cd .. && pwd)/earthsync-private-rc
mkdir -p "$PRIVATE"
chmod 700 "$PRIVATE"
"$PY" ops/staging/staging.py build --profile platform --source "$REPO" \
  --state "$PRIVATE/platform" --sha "$RC_SHA"
"$PY" ops/staging/staging.py build --profile web --source "$REPO" \
  --state "$PRIVATE/web" --sha "$RC_SHA" --flutter-version 3.44.0
# Run in separate foreground terminals:
"$PY" ops/staging/staging.py run --source "$REPO" --state "$PRIVATE/platform"
"$PY" ops/staging/staging.py run --source "$REPO" --state "$PRIVATE/web"
```

Open **http://127.0.0.1:8080**. The platform uses **127.0.0.1:8021** and admits
only the exact browser origin recorded in its manifest. Both manifests pin actual
executable/catalog/lock/runtime hashes; startup rechecks them. Retain private ACLs,
Host/Origin/owner checks and the two independent photo stores. Workspace tokens
are entered only in the authorized UI session, never committed or embedded in assets.

### Windows PowerShell

The newly added `windows-staging` CI job exercises this path on Windows using
Python 3.12, Rust 1.99.0 and Flutter 3.44.0. Its exact completion/log receipt is
reported in VERIFICATION.md/CI evidence. This is separate from interactive Windows
Chromium acceptance, which was not run in the Linux task environment. The supplied
Windows 7N visual inspection used Python 3.12.10/Rust 1.99.0/Flutter 3.44.0; it is
inherited user evidence, not a new 7W/7X Windows browser pass.

Install Git for Windows, Python's `py` launcher, Visual Studio C++ build tools and
Windows SDK, rustup 1.99.0 and Flutter 3.44.0. Place `flutter.bat` on PATH. The
staging script resolves its full path and completes first-run bootstrap before
reading strict version JSON; do not patch the SDK or enable `shell=True`.

```powershell
$Repo = 'C:\src\earthsync-rc'
$Private = 'C:\earthsync-private-rc'
$RcSha = (git -C $Repo rev-parse HEAD).Trim()
Set-Location $Repo
py -3.12 -m venv C:\earthsync-tools-venv
$Python = 'C:\earthsync-tools-venv\Scripts\python.exe'
& $Python -m pip install -r server\requirements.lock
& $Python scripts\verify_7x_integrity.py
& .\ops\staging\staging.ps1 -State "$Private\platform" build --profile platform --source $Repo --sha $RcSha
& .\ops\staging\staging.ps1 -State "$Private\web" build --profile web --source $Repo --sha $RcSha --flutter-version 3.44.0
# Separate foreground PowerShell terminals; use the ACL wrapper for operations:
& .\ops\staging\staging.ps1 -State "$Private\platform" run --source $Repo
& .\ops\staging\staging.ps1 -State "$Private\web" run --source $Repo
```

Use dedicated NTFS folders outside OneDrive/static directories. The wrapper grants
only the current account and SYSTEM inheritable access and rejects unrelated folders.
CI startup success does not certify ACLs or network controls on a teammate's machine.
Perform the 7Q destination checks there; never bypass an INCOMPLETE report.

## Direct Linux acceptance path used for browser receipts

The retained browser commands use port 8091 and a disposable private state root.
This direct path also allows native Flutter host tests to use the debug example.

```bash
# Choose a fresh disposable root, separate from the immutable 7Q states above.
PRIVATE=$(cd .. && pwd)/earthsync-private-acceptance
cargo build --locked --manifest-path engine/Cargo.toml --examples
cargo build --release --locked --manifest-path app/rust/Cargo.toml
cd app
flutter pub get --enforce-lockfile
flutter analyze
LD_LIBRARY_PATH="$REPO/app/rust/target/release" flutter test --reporter expanded
flutter build web --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run \
  --dart-define=PLATFORM_URL=http://127.0.0.1:8021
cd ..
export PYTHONPATH="$REPO/server"
export EARTHSYNC_EVIDENCE_DIR="$PRIVATE/workspace"
export EARTHSYNC_EVIDENCE_TOKEN_FILE="$PRIVATE/workspace/workspace-token.txt"
export EARTHSYNC_EVIDENCE_ORIGINS=http://127.0.0.1:8091
"$PY" -m earthsync.demo_workspace "$PRIVATE/workspace"
"$PY" scripts/run_final_local.py --directory "$PRIVATE/platform"
```

`run_final_local.py` pins the just-built executable/catalog for this disposable
local run; the immutable 7Q path additionally retains and verifies reviewed build
manifests. On a restricted Linux host, use writable `PUB_CACHE` and
`XDG_CONFIG_HOME`, and allow the analyzer's ordinary `.dartServer` cache. Keep HOME
and SDK sources unchanged. Only a compatible C compiler/linker is needed for Web
and native host tests; Android/JDK/Gradle are not release gates here.

## Verification commands

Use fresh output/private directories, not committed historical receipts. Build
native examples first. The live opt-ins below actually contact providers.

```bash
export EARTHSYNC_TEST_V03="$REPO/engine/target/debug/examples/v03_demo"
"$PY" server/platform-v1/tools/prepare_compat.py "$PRIVATE/compat" --revision "$RC_SHA"
export EARTHSYNC_COMPAT_ROOT="$PRIVATE/compat"
"$PY" -m pytest -q server/tests ops/staging/tests
cargo test --locked --manifest-path engine/Cargo.toml
"$PY" -m unittest discover -s data/crop-knowledge/v1/tests -v
"$PY" data/crop-knowledge/v2/tools/build.py --check
"$PY" data/crop-knowledge/v2/tools/knowledge.py check
"$PY" -m unittest discover -s data/crop-knowledge/v2/tests -p test_offline.py -v
"$PY" -m unittest discover -s data/crop-knowledge/v2/tests -p test_scientific.py -v
"$PY" -m unittest discover -s data/crop-knowledge/v2/tests -p test_rust_contract.py -v
"$PY" data/crop-rule-candidates/v1/tools/package.py --check
"$PY" -m unittest discover -s data/crop-rule-candidates/v1/tests -v
"$PY" scripts/verify_7x_integrity.py
EARTHSYNC_LIVE=1 "$PY" -m unittest discover -s data/crop-knowledge/v2/tests -p test_live.py -v
EARTHSYNC_LIVE_PROVIDERS=nasa "$PY" -m pytest -q server/tests/platform_v1/test_live_opt_in.py
"$PY" -m pip install playwright
"$PY" scripts/browser_7w.py --compare --output "$PRIVATE/browser-7w"
"$PY" scripts/browser_7n.py --token-file "$PRIVATE/workspace/workspace-token.txt" \
  --output "$PRIVATE/browser-7n"
```

For immutable 7Q Web on 8080, add `--base-url http://127.0.0.1:8080` to both
browser commands. The retained runners use installed Linux `/usr/bin/chromium`;
they do not constitute Windows browser acceptance. The live Flutter checks use:

```bash
cd app
LD_LIBRARY_PATH="$REPO/app/rust/target/release" flutter test \
  test/native_bridge_test.dart test/web_engine_test.dart test/ui/platform_live_test.dart \
  --dart-define=RUN_LIVE_NASA=true --dart-define=RUN_WEB_DEMO=true \
  --dart-define=RUN_LIVE_PLATFORM=true \
  --dart-define=BACKEND_URL=http://127.0.0.1:8091 \
  --dart-define=WEB_DEMO_URL=http://127.0.0.1:8091/ --reporter expanded
```

For Docker, follow `.github/workflows/platform-v1.yml`: prepare the exact compat
export, download locked binary wheels and `cargo vendor --locked`, then build with
`--build-context compat_source=<export>` and the file-specific Dockerfile. Run with
read-only root, private tmpfs data, no capabilities and **no published ports**.
`container_smoke.py <container-name>` performs the runtime check. Stop/remove the
disposable container afterward. No live provider claim comes from container smoke.

## NASA demonstration, about five minutes

1. Skip GPS if desired; confirm a named point and explicitly persist a declared
   system. The tested regional example is `(42.0308, -93.6319)`, rainfed. It is a
   software-test farm, not an independently observed farmer field.
2. Request **2024-07-03 to 2024-07-07** NASA inputs. Show original parameter
   sources/response hashes and Rust intermediates. Persisted ET0 is
   **23.193683430451973 mm**, rainfall **28.68 mm** for this captured response.
   These are historical regional quantities, not irrigation advice.
3. Select the saved source snapshots. Look up rice and another crop. Show source
   profile scope, limitations and all blocked rules. An explicit reference region
   is not inferred applicability at this global point.
4. Save two declared sequences separately; compare chronological support/conflict
   and missing evidence in **Compare two saved assessments**. Dates are labeled
   proposals; do not present a favorable calendar finding as crop suitability.
5. Ask the assistant what ET0 means or about the saved crop's reference growing
   period. Show the same persisted number and citations. Show null ETc/irrigation.
6. Refresh and restart the services, then reopen decisions/history. Show the backup
   receipt and restore to a fresh private directory. Explain the explicit simulated
   outage: it produces an unavailable state, never synthetic weather or zero totals.

## Offline backup, restore and rollback

Stop **both** services before maintenance. Keep the original stores and manifests.
The platform and workspace photo databases are distinct; retain both.

```bash
"$PY" -m earthsync.platform_v1.maintenance backup \
  --directory "$PRIVATE/platform" --backup "$PRIVATE/platform-backup"
"$PY" -m earthsync.platform_v1.maintenance restore \
  --directory "$PRIVATE/platform-restored" --backup "$PRIVATE/platform-backup"
```

For the immutable 7Q layout, use its documented `backup`/`restore` commands through
the staging wrapper (PowerShell on Windows). For the independent workspace BLOB
store, use the unchanged 7Q offline SQLite backup procedure and retain its private
workspace token. Never mix the token/BLOB store with platform-owned PNG objects.
`scripts/recovery_7x.py` provides a disposable-store rehearsal and sanitized hashes;
it requires stopped services for baseline/backup/restore and preserves originals.
As an alternative to the manual commands (use fresh backup/restore names), run:

```bash
"$PY" scripts/recovery_7x.py snapshot --private "$PRIVATE" --receipt "$PRIVATE/baseline.json"
"$PY" scripts/recovery_7x.py backup-restore --private "$PRIVATE" --receipt "$PRIVATE/baseline.json"
"$PY" scripts/recovery_7x.py verify --restored --private "$PRIVATE" --receipt "$PRIVATE/baseline.json"
```

The retained two-photo rehearsal deliberately uploaded a generated PNG through
each existing sanitizer first: an authorized workspace upload labeled synthetic,
and a farm-owned upload to a named software-test farm. Neither is a field observation.
`recovery-photo-fixtures.json` records their IDs/hash without credentials. The
helper's `verify-http` command compares the saved browser job/evidence/assessments
and both photos against that receipt after restart. Those exact IDs belong to the
disposable private stores used for this report; new reproductions must retain their
own browser/fixture receipts rather than reuse these IDs against another database.

Rollback: stop services, retain the failing state/log/manifests, select the prior
reviewed checkout and its matching recorded artifacts, and restore the matching
backup into a **new** private directory. Verify integrity, migrations, exact owned
rows/photos and actual Rust readiness before reconnecting. Do not overwrite a live
store, downgrade a database in place, reset main, rewrite another PR, or substitute
an older engine binary for the current pinned artifact. No new schema migration is
introduced by 7X. Until final gates are green, keep the candidate draft and report
any red/unavailable gate accurately.
