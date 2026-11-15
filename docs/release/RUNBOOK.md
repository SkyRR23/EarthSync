# Run and recover the combined local candidate

Use the reviewed head of PR #29, not the old stacked draft PRs or a moving main.
Tools: Python 3.12, Rust 1.99.0, Flutter 3.44.0 / Dart 3.12.0, Git and a browser.
The Linux candidate was exercised with Python 3.12.14 and Chromium. Windows
build/startup is independently checked by CI; interactive Windows browser and
machine-specific ACL validation must not be inferred from Linux screenshots.

## Fresh source and immutable runtime builds

```bash
git clone https://github.com/SkyRR23/EarthSync.git earthsync-rc
cd earthsync-rc
git fetch origin feat/earthsync-final-product-completion
RC_SHA=$(git rev-parse origin/feat/earthsync-final-product-completion)
# Compare this exact SHA with the reviewed PR head.
git checkout --detach "$RC_SHA"
python3.12 -m venv ../earthsync-tools
PY=$(cd ../earthsync-tools/bin && pwd)/python
"$PY" -m pip install -r server/requirements.lock
"$PY" scripts/verify_7x_integrity.py
umask 077
REPO=$(pwd)
PRIVATE=$(cd .. && pwd)/earthsync-private
mkdir -p "$PRIVATE"
chmod 700 "$PRIVATE"
"$PY" ops/staging/staging.py build --profile platform --source "$REPO" --state "$PRIVATE/platform" --sha "$RC_SHA"
"$PY" ops/staging/staging.py build --profile web --source "$REPO" --state "$PRIVATE/web" --sha "$RC_SHA" --flutter-version 3.44.0
# Two foreground terminals:
"$PY" ops/staging/staging.py run --source "$REPO" --state "$PRIVATE/platform"
"$PY" ops/staging/staging.py run --source "$REPO" --state "$PRIVATE/web"
```

Open http://127.0.0.1:8080. The private platform is 127.0.0.1:8021, restricted
to the exact recorded browser origin. Startup verifies executable, catalog,
lock and runtime hashes. Keep both manifests, private ACLs and separate stores.
Do not expose these ports using a public tunnel or reverse proxy.

## Windows PowerShell

Install Python's `py` launcher, Git, Visual Studio C++ tools/Windows SDK, Rust
1.99.0 and Flutter 3.44.0. Put `flutter.bat` on PATH. Use fresh dedicated NTFS
folders outside OneDrive and static-serving directories; do not rewrite scientific
hashes to accept CRLF bytes. The staging wrapper resolves Flutter's full executable
path, bootstraps it and establishes private ACLs.

```powershell
$Repo = 'C:\src\earthsync-rc'
$Private = 'C:\earthsync-private'
git clone https://github.com/SkyRR23/EarthSync.git $Repo
git -C $Repo fetch origin feat/earthsync-final-product-completion
$RcSha = (git -C $Repo rev-parse origin/feat/earthsync-final-product-completion).Trim()
# Verify $RcSha against the reviewed PR head.
git -C $Repo checkout --detach $RcSha
Set-Location $Repo
py -3.12 -m venv C:\earthsync-tools
$Python = 'C:\earthsync-tools\Scripts\python.exe'
& $Python -m pip install -r server\requirements.lock
& $Python scripts\verify_7x_integrity.py
& .\ops\staging\staging.ps1 -State "$Private\platform" build --profile platform --source $Repo --sha $RcSha
& .\ops\staging\staging.ps1 -State "$Private\web" build --profile web --source $Repo --sha $RcSha --flutter-version 3.44.0
# Separate foreground PowerShell terminals:
& .\ops\staging\staging.ps1 -State "$Private\platform" run --source $Repo
& .\ops\staging\staging.ps1 -State "$Private\web" run --source $Repo
```

Open http://127.0.0.1:8080. Do not bypass an INCOMPLETE destination-security
report. CI does not validate ACLs or browser fonts on a teammate's computer.

## Direct developer/browser reproduction

The final browser receipts use disposable stores outside Git and port 8091.
Build actual Rust and Web assets; a build without PLATFORM_URL intentionally
cannot write to the private farmer service.

```bash
cargo build --locked --manifest-path engine/Cargo.toml --examples
cargo build --locked --release --manifest-path app/rust/Cargo.toml
cd app
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run --dart-define=PLATFORM_URL=http://127.0.0.1:8021
"$PY" ../scripts/finalize_offline.py build/web
cd ..
# Initialize a separate private workspace and retain its token only locally.
export PYTHONPATH="$REPO/server"
export EARTHSYNC_EVIDENCE_DIR="$PRIVATE/workspace"
export EARTHSYNC_EVIDENCE_TOKEN_FILE="$PRIVATE/workspace/workspace-token.txt"
export EARTHSYNC_EVIDENCE_ORIGINS=http://127.0.0.1:8091
"$PY" -m earthsync.demo_workspace "$PRIVATE/workspace"
"$PY" scripts/run_final_local.py --directory "$PRIVATE/platform"
```

Set PYTHONPATH to the checkout's absolute `server` path when invoking modules
without installing the package. Keep HOME unchanged; use ordinary tool cache
configuration when required by a sandbox. No provider TLS verification is disabled.
The separate tile-verification browser run explicitly records a Cloud proxy
certificate exception; normal browser tile trust is not claimed by that receipt.

## Backup, restore and rollback

Stop both foreground services before maintenance. Preserve the source SHA,
built manifests, token authorization, SQLite and each independent photo store.
Use the existing staging backup/restore commands from
[the operations guide](../../ops/staging/README.md). Restore only into a new,
private destination and verify integrity/ownership before switching runtimes.
For disposable final acceptance stores, `scripts/recovery_final.py` rehearses
platform maintenance backup/restore plus an independent workspace SQLite backup,
compares every row/object hash and leaves originals unchanged.

Migrations 003, 030 and 031 are additive. Old 001/002 checksums remain unchanged.
Do not delete tables or edit migration history to run an older binary. Roll back
both application runtime and its matching pre-upgrade backup into a new private
directory. Keep the newer store untouched for recovery and review.

Main's pre-release reference is `1ea3df7b09637cf8162f834411d830aa8621590c`.
Main has not been merged while release blockers remain. A source rollback is a
fresh detached checkout at that SHA plus its matching backup, not a force push
or a destructive reset of another active worktree.

## Hosting

No deployment URL is claimed. A static Flutter host cannot run native Rust,
FastAPI, persistent SQLite or private photo authorization. Cloudflare Pages or
Workers static assets alone are insufficient. A publicly reachable backend would
require a compatible persistent host plus proper authentication/ownership
isolation, or a separate sanitized read-only demo. This release retains the
loopback local demonstration while mandatory data/acceptance gates remain open.
No paid resources, billing changes or public tunnel have been created.

The subsequent [Cloudflare/account and free-host assessment](HOSTING.md) records
actual connected permission failures and persistence limits. The
[full-stack packages](ARTIFACTS.md) include the built Web frontend and both native
executables, with verification and unpacked process/HTTP smoke checks. Final
[local Windows acceptance and user merge approval](WINDOWS_ACCEPTANCE.md) remain
required; CI success cannot substitute for them.


## Private browser receipts and safe publication

Keep browser authorization/state files and raw results outside the checkout.
Raw helpers enforce this boundary; public receipt summaries cannot be used as
raw inputs for `--resume-strategies` or recovery verification.

```bash
# Chromium and Python Playwright are required only for browser verification.
"$PY" scripts/browser_final.py --state "$PRIVATE/browser-state.json" --output "$PRIVATE/verification/browser-final"
"$PY" scripts/browser_crop_explorer.py --state "$PRIVATE/browser-state.json" --output "$PRIVATE/verification/browser-crops"
"$PY" scripts/browser_risk_final.py --state "$PRIVATE/browser-state.json" --output "$PRIVATE/verification/browser-risk"
"$PY" scripts/summarize_release_evidence.py --raw "$PRIVATE/verification" --output docs/release/evidence
```

The public step publishes metadata/hashes only. Screenshots are excluded by default;
add `--include-reviewed-screenshots` only after reviewing the fixed allowlist for
field locations, identifiers and personal information. Retain map screenshots and
full assessment/observation payloads privately. Never push local raw-evidence archive
refs. The historical 7G/7X test fixtures are separate from newly captured runtime data.
