# Local Web startup — 7W

Use the 7W checkout/PR head, Python 3.12+, Rust 1.99.0, Flutter **3.44.0** /
Dart **3.12.0**, and a current Chromium browser. No Android/Gradle build is needed.
Private directories must be outside every checkout and static Web directory.
The example below uses the actual isolated paths from this task; change both
paths together on another host. Never bind the private platform to `0.0.0.0`.

## Build

```sh
export EARTHSYNC_REPO=/workspace/EarthSync-7w
export EARTHSYNC_PRIVATE=/workspace/.earthsync-7w-private
cd "$EARTHSYNC_REPO"
python3.12 -m venv "$EARTHSYNC_PRIVATE/venv"
"$EARTHSYNC_PRIVATE/venv/bin/python" -m pip install -r server/requirements.lock
cargo build --locked --manifest-path engine/Cargo.toml --example web_engine --example v03_demo
# Required for native Flutter regression tests, not browser execution:
cargo build --release --locked --manifest-path app/rust/Cargo.toml
cd app
flutter pub get --enforce-lockfile
flutter build web --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run \
  --dart-define=PLATFORM_URL=http://127.0.0.1:8021
```

Keep v1 at `data/crop-knowledge/v1/catalog.json` and the complete unchanged v2
directory at `data/crop-knowledge/v2/`. Do not point the v1 loader at v2. Retain
the packaged `server/earthsync/platform_v1/rule_review.json` as a non-executable
7V review sidecar. The usual 7Q immutable release workflow remains available;
its platform runtime copy now includes v2 files and their artifact hashes.

On a filesystem-restricted build host, configure writable package/tool caches
(for example `PUB_CACHE=/workspace/.earthsync-tools/pub-cache`) and permit Dart's
normal configuration/analyzer cache directories. Do not change SDK source, disable
TLS, change HOME or relax the app's origin/ownership controls to make a build pass.

## Start the private evidence platform — terminal 1

```sh
export EARTHSYNC_REPO=/workspace/EarthSync-7w
export EARTHSYNC_PRIVATE=/workspace/.earthsync-7w-private
cd "$EARTHSYNC_REPO"
export PYTHONPATH="$EARTHSYNC_REPO/server"
export EARTHSYNC_PLATFORM_LOCAL=1
export EARTHSYNC_PLATFORM_DIR="$EARTHSYNC_PRIVATE/platform"
export EARTHSYNC_PLATFORM_ORIGINS=http://127.0.0.1:8091
export EARTHSYNC_V03_EXECUTABLE="$EARTHSYNC_REPO/engine/target/debug/examples/v03_demo"
export EARTHSYNC_V03_SHA256="$(sha256sum "$EARTHSYNC_V03_EXECUTABLE" | cut -d ' ' -f 1)"
export EARTHSYNC_CATALOG_PATH="$EARTHSYNC_REPO/data/crop-knowledge/v1/catalog.json"
export EARTHSYNC_CATALOG_SHA256="$(sha256sum "$EARTHSYNC_CATALOG_PATH" | cut -d ' ' -f 1)"
"$EARTHSYNC_PRIVATE/venv/bin/python" -m uvicorn earthsync.platform_v1.api:app_factory \
  --factory --host 127.0.0.1 --port 8021 --workers 1 --no-proxy-headers --no-access-log
```

These hashes pin the just-built, locally reviewed artifacts. For an immutable
release, use the recorded reviewed hashes/7Q manifest rather than recomputing a
hash after an unexplained binary change. Readiness runs the actual crop executable;
the water workflow additionally verifies the new method and exact echoed inputs.

## Start Flutter Web and existing services — terminal 2

```sh
export EARTHSYNC_REPO=/workspace/EarthSync-7w
export EARTHSYNC_PRIVATE=/workspace/.earthsync-7w-private
cd "$EARTHSYNC_REPO"
export PYTHONPATH="$EARTHSYNC_REPO/server"
"$EARTHSYNC_PRIVATE/venv/bin/python" -m earthsync.demo_workspace "$EARTHSYNC_PRIVATE/web"
export EARTHSYNC_EVIDENCE_DIR="$EARTHSYNC_PRIVATE/web"
export EARTHSYNC_EVIDENCE_TOKEN_FILE="$EARTHSYNC_PRIVATE/web/workspace-token.txt"
export EARTHSYNC_EVIDENCE_ORIGINS=http://127.0.0.1:8091
"$EARTHSYNC_PRIVATE/venv/bin/python" -m uvicorn earthsync.web_demo:app \
  --host 127.0.0.1 --port 8091 --workers 1 --no-proxy-headers --no-access-log
```

Open **http://127.0.0.1:8091** (use this exact origin). The private API remains on
127.0.0.1:8021. Neither listener is publicly deployed or safe to publish through
an unreviewed proxy. Existing workspace photos require their original authorized
token; no farm/photo migration or token embedding in Web assets occurs.

## Demonstrate the actual workflow

1. Skip device location if desired. Enter and explicitly confirm a global farm
   point/name, then open **My Farm → Persisted farm evidence** and declare the
   actual production system before confirming local persistence.
2. In **Crop references & water intelligence**, enter historical dates and choose
   **Retrieve NASA inputs & calculate ET0**. A tested public regional example is
   `(42.0308, -93.6319)`, **2024-07-03 through 2024-07-07**. This is a software-test
   farm location, not a claim of observed conditions on a real farmer's field.
3. Inspect calculated daily ET0/rainfall, original inputs and full intermediate
   values/hashes. Complete-period totals are withheld if any required day is
   missing. The seven-day July 1–7 example intentionally demonstrates such a gap.
4. Explicitly choose **Use this saved calculation and source snapshots**. Look up
   `rice`, `maize`, `mung bean`, `sesame`, `groundnut` or another exact identity.
   Ambiguous `corn` stays ambiguous. Additional lookups add profiles to the
   comparison. A source profile region is not automatic farm applicability.
5. Select a compatible identity-only profile and optionally a second profile in
   the same reference scope, declare its dates, and save the assessment. Actual
   Rust chronology can be known/conflicting while agronomic requirements remain
   unknown. All 7P rules and all 60 reviewed 7V candidates stay disabled.
6. Ask the assistant about rainfall, ET0, the saved crop's growing period, rotation
   findings or missing irrigation inputs. It retrieves saved evidence and citations;
   it does not calculate a new irrigation number in conversation.
7. Refresh/restart to inspect persisted records. Old results retain their dates;
   an outage never substitutes zero or synthetic weather.

The original daily-climate charts, map, history, photos and v1 assessment remain
available. ETc and field net/gross irrigation are explicitly unknown until accepted
crop/field dependencies exist; a functioning ET0 calculation does not supply them.

## Verification and recovery commands

Run tests with disposable private stores. `scripts/browser_7w.py` and the inherited
7N runner create labeled software-test farms and require the local services.

```sh
export PYTHONPATH="$EARTHSYNC_REPO/server"
export EARTHSYNC_TEST_V03="$EARTHSYNC_REPO/engine/target/debug/examples/v03_demo"
python server/platform-v1/tools/prepare_compat.py /absolute/new/compat --revision HEAD
export EARTHSYNC_COMPAT_ROOT=/absolute/new/compat
python -m pytest -q server/tests ops/staging/tests
cargo test --locked --manifest-path engine/Cargo.toml
python data/crop-knowledge/v2/tools/build.py --check
python data/crop-knowledge/v2/tools/knowledge.py check
python -m unittest discover -s data/crop-knowledge/v2/tests -p test_offline.py -v
python -m unittest discover -s data/crop-knowledge/v2/tests -p test_scientific.py -v
python -m unittest discover -s data/crop-knowledge/v2/tests -p test_rust_contract.py -v
# Explicit opt-in only; live tests are never counted as offline passes:
EARTHSYNC_LIVE=1 python -m unittest discover -s data/crop-knowledge/v2/tests -p test_live.py -v
python scripts/browser_7w.py --output /absolute/new/browser-receipts
```

Flutter regression tests also require the native bridge on the host library path:
on tested Linux, set `LD_LIBRARY_PATH="$EARTHSYNC_REPO/app/rust/target/release"`
and run `flutter test --reporter expanded` from `app/`. Follow the platform's
existing native-library instructions on Windows/macOS; they were not tested here.

For an offline complete platform backup/restore, stop both services first and use
the unchanged maintenance commands; restore only into a new private directory:

```sh
python -m earthsync.platform_v1.maintenance backup \
  --directory "$EARTHSYNC_PRIVATE/platform" --backup /absolute/new/platform-backup
python -m earthsync.platform_v1.maintenance restore \
  --directory /absolute/new/restored-platform --backup /absolute/new/platform-backup
```

The separate 7H photo workspace must also be retained/backed up under the 7Q
runbook. Do not mix its image-BLOB/token store with farm-owned 7I PNG objects.
