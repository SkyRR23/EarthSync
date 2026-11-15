# Local 7G Web startup

Branch `feat/earthsync-geospatial-intelligence-v1`, exact base
`edefc0c4dedf232e7ddb9704f6f2180a4936fcc3`. The task worktree is
`/workspace/EarthSync-7G`; private runtime is outside all checkouts/static assets
at `/workspace/.earthsync-7g-private`. No public deployment was performed.

Requires Python 3.12, Rust 1.99.0, Flutter 3.44.0 / Dart 3.12.0 and Chromium.
The existing requirements/Flutter locks are unchanged; no new runtime package.
Use your normal SDK commands, or this task's SDK paths below.

```sh
export EARTHSYNC_REPO=/workspace/EarthSync-7G
export EARTHSYNC_PRIVATE=/workspace/.earthsync-7g-private
export CARGO_HOME=/workspace/.earthsync-tools/cargo
export RUSTUP_HOME=/workspace/.earthsync-tools/rustup
export PUB_CACHE=/workspace/.earthsync-7g-tools/pub-cache
export XDG_CONFIG_HOME=/workspace/.earthsync-7g-tools/config
export PATH=/workspace/.earthsync-7g-tools/flutter/bin:/workspace/.earthsync-tools/cargo/bin:$PATH
cd "$EARTHSYNC_REPO"
python -m venv "$EARTHSYNC_PRIVATE/venv"
"$EARTHSYNC_PRIVATE/venv/bin/pip" install -r server/requirements.lock
cargo build --locked --manifest-path engine/Cargo.toml --example web_engine --example v03_demo
# Needed for native Flutter regression, not the Web runtime:
cargo build --release --locked --manifest-path app/rust/Cargo.toml
cd app
flutter --suppress-analytics pub get --enforce-lockfile
flutter --suppress-analytics build web --no-web-resources-cdn --no-wasm-dry-run \
  --dart-define=PLATFORM_URL=http://127.0.0.1:8031
```

Keep Flutter/Dart's normal tool-cache directories writable. On this managed
computer, the analyzer needed its normal `/home/agent/.dart-tool` cache; HOME and
SDK source were not changed. The additional `--suppress-analytics` flag avoids
unnecessary tool telemetry. Do not embed private tokens into build definitions.

Terminal 1, private service (single worker, loopback only):

```sh
cd "$EARTHSYNC_REPO"
export PYTHONPATH="$EARTHSYNC_REPO/server"
export EARTHSYNC_PLATFORM_LOCAL=1
export EARTHSYNC_PLATFORM_DIR="$EARTHSYNC_PRIVATE/platform"
export EARTHSYNC_PLATFORM_ORIGINS=http://127.0.0.1:8093
export EARTHSYNC_V03_EXECUTABLE="$EARTHSYNC_REPO/engine/target/debug/examples/v03_demo"
export EARTHSYNC_V03_SHA256="$(sha256sum "$EARTHSYNC_V03_EXECUTABLE" | cut -d ' ' -f 1)"
export EARTHSYNC_CATALOG_PATH="$EARTHSYNC_REPO/data/crop-knowledge/v1/catalog.json"
export EARTHSYNC_CATALOG_SHA256="$(sha256sum "$EARTHSYNC_CATALOG_PATH" | cut -d ' ' -f 1)"
"$EARTHSYNC_PRIVATE/venv/bin/python" -m uvicorn earthsync.platform_v1.api:app_factory \
  --factory --host 127.0.0.1 --port 8031 --workers 1 --no-proxy-headers --no-access-log
```

The hashes above pin the freshly reviewed local build, as in 7W. Immutable
release procedures must retain independently reviewed hashes instead of blindly
recomputing a hash after unexplained binary changes. Keep both complete crop
catalog directories and `platform_v1/rule_review.json` installed.

Terminal 2, Flutter assets and existing services:

```sh
cd "$EARTHSYNC_REPO"
export PYTHONPATH="$EARTHSYNC_REPO/server"
"$EARTHSYNC_PRIVATE/venv/bin/python" -m earthsync.demo_workspace "$EARTHSYNC_PRIVATE/web"
export EARTHSYNC_EVIDENCE_DIR="$EARTHSYNC_PRIVATE/web"
export EARTHSYNC_EVIDENCE_TOKEN_FILE="$EARTHSYNC_PRIVATE/web/workspace-token.txt"
export EARTHSYNC_EVIDENCE_ORIGINS=http://127.0.0.1:8093
"$EARTHSYNC_PRIVATE/venv/bin/python" -m uvicorn earthsync.web_demo:app \
  --host 127.0.0.1 --port 8093 --workers 1 --no-proxy-headers --no-access-log
```

Open http://127.0.0.1:8093 . Do not bind either private service to 0.0.0.0.
The separate 7H photo token remains session-only; never put it in URLs/assets.

## Walkthrough

1. Skip GPS if desired. Add My Farm → enter/select a point → open map. Draw
   corners explicitly, select a vertex and tap a new position, undo/cancel or use
   coordinate corner entry. Confirm the boundary, confirm the farm point and save.
   Reopen Edit My Farm to inspect/edit it. Point-only remains a supported fallback.
2. My Farm → Persisted farm evidence → declare the production system and explicitly
   persist the revision. Old revisions are retained, not silently rebound.
3. Farm map & environmental snapshots → Retrieve SoilGrids pH map → Open source
   map. Inspect the legend, opacity, nodata, raw cells and provenance. A regional
   test coordinate used in verification is (42.0308, -93.6319); it is not a claim
   about any farmer's field. Other areas can have missing tiles/pixels.
4. Retrieve NOAA temperature forecast. Read actual model/valid times in UTC,
   unknown publication time, modeled f000, stale label and limited derived condition.
5. Find NASA HLS metadata for a calendar-selected 30-day window. This is metadata,
   not NDVI. Missing credentials/QA remain a blocker; no fake pixel fallback exists.
6. Field timeline → search crop identities or enter a farmer report, pick dates,
   retain unknown context where appropriate, save a dated observation. Existing
   crop history and private photos remain separate supported workflows.
7. Use the unchanged crop-water panel for historical POWER/ET0 and source-backed
   crop references. New soil/forecast/reports do not become assessment inputs.

Source requests are explicit and bounded. No scheduler or automatic monitoring
is installed. External providers must be online for a new capture; saved private
snapshots retain their original times. See CAPABILITIES.md for missing features.
