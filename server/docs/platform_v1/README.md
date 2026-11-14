# Backend evidence platform v1 (7I)

This is an implemented, independently runnable **local single-user backend**,
not a completed hosted global platform. It preserves actual evidence and invokes
the real Rust v0.3 engine. Hosted identity/PostgreSQL/PostGIS, accepted live soil,
optical downloads, radar acquisition ingestion, forecasts with verified runs and
independently approved crop requirements remain release blockers.

Start with [the audit matrix](IMPLEMENTATION_MATRIX.md),
[the compatibility handoff](INTEGRATION_HANDOFF.md), and
[verification and phase status](VERIFICATION.md).

## Implemented behavior

- Pydantic and committed JSON Schemas: evidence IDs, exact source/dataset/version,
  response hashes, original geometry/CRS and grid support, retrieval/valid/issue
  times, native/normalized units, conversions, depths, review, limitations,
  quality/missing reasons and explicit agricultural usability. Approximate area
  and confirmed farm geometry are separate; device location never creates farms.
- Real POWER daily Tmin/Tmax/precipitation, strict per-parameter lineage, calendar,
  unit, API-version and point validation; null missing days without interpolation.
  Existing monthly MERRA-2 service remains unchanged. Twelve raw pilot responses
  are captured and replayed offline; they establish regional availability only.
- One focused SoilGrids WCS pH probe with native 250 m/depth/unit/coverage checks;
  descriptor/raster hashes and source metadata retained in reference-only evidence.
  Live transport is blocked. PR #17's broader REST parser is reused by 7H rather
  than duplicated here. No unsupported USDA/Australian values are manufactured.
- HLS v2 catalog discovery and isolated local GeoTIFF processing: co-registration,
  native band/encoding/scale/no-data checks, Fmask rejection, NDVI, valid counts and
  support fractions. Tiny polygons have no invented field average. Point results
  are representative-cell context. Local processing is an unaccepted diagnostic,
  not evidence of successful live ingestion. No GIBS pixels enter numerical paths.
- Local OPERA gamma0 power/mask summaries and strict orbit/polarization/burst/
  geometry/version compatibility gates. Aggregate means are never subtracted
  without a common native valid-pixel mask. Live SAR ingestion and paired-pixel
  change processing are unfinished. No backscatter interpretation or threshold.
- Owned SQLite farms, optional valid polygons, immutable evidence associations,
  farmer-reported history, decisions, object references, caches, jobs and audits.
  Transactions, migration checksums, foreign keys, quotas and complete database+
  object backup/restore. Photos reuse PR #16's sanitizer; files are separate from
  ordinary rows. Existing workspace photo IDs do not automatically become farm IDs.
- Actual hash-pinned Rust executable, bounded admission/timeout/stdout, sanitized
  failures and child cleanup. Requests are built from owned stored evidence;
  clients cannot submit their own reviewed rules or inject arbitrary engine JSON.
  The adapter retains PR #15 review and eligibility and exports **no numerical
  crop rules**. Explicit sequential overlapping plans can return Rust conflicts
  even though crop suitability remains insufficient. Farmer history is retained
  as unreviewed, not silently certified or declared complete.
- PR #14 assistant-context projection with actual source URLs and IDs, no LLM,
  raw daily values labeled as retrieved facts, no fabricated seasonal calculations.
- Bounded two-worker jobs, eight queued tasks, idempotent pending submissions,
  best-effort cancellation, deadlines, retryability, restart failure states and
  expiring dataset/lineage/contract-aware caches. One process only; no Redis/Celery.

## Linux setup and actual API commands

Run from the 7I checkout, not another developer's worktree. Python 3.12+ and Rust
1.99 are used. Use a new private absolute path outside the served repository.
The following commands create temporary compatibility exports from exact audited
Git objects without changing another checkout or merging a branch:

```bash
git fetch origin '+refs/heads/*:refs/remotes/origin/*' '+refs/pull/*/head:refs/remotes/pull/*'
python3.12 -m venv /tmp/earthsync-7i-venv
source /tmp/earthsync-7i-venv/bin/activate
python -m pip install -r server/platform-v1/requirements.lock
python server/platform-v1/tools/prepare_compat.py /tmp/earthsync-7i-compat
cargo build --locked --manifest-path /tmp/earthsync-7i-compat/18/engine/Cargo.toml --example v03_demo
export PYTHONPATH="$PWD/server"
export EARTHSYNC_PLATFORM_LOCAL=1
export EARTHSYNC_PLATFORM_DIR=/tmp/earthsync-7i-private
export EARTHSYNC_V03_EXECUTABLE=/tmp/earthsync-7i-compat/18/engine/target/debug/examples/v03_demo
export EARTHSYNC_V03_SHA256=$(sha256sum "$EARTHSYNC_V03_EXECUTABLE" | cut -d' ' -f1)
export EARTHSYNC_CATALOG_PATH=/tmp/earthsync-7i-compat/15/data/crop-knowledge/v1/catalog.json
export EARTHSYNC_CATALOG_SHA256=$(sha256sum "$EARTHSYNC_CATALOG_PATH" | cut -d' ' -f1)
uvicorn earthsync.platform_v1.api:app_factory --factory --host 127.0.0.1 --port 8021 --workers 1 --no-proxy-headers --no-access-log --limit-concurrency 12 --timeout-keep-alive 5
```

Review/pin executable and catalog hashes before reuse. The image below includes
PR #16's existing sanitizer automatically. A source checkout without #16 can run
the platform but photo upload explicitly returns `PHOTO_SERVICE_NOT_INSTALLED`.
For a native assembled runtime, copy `server/earthsync` to a new private runtime
package directory and add the exported `16/server/earthsync/evidence` package
there; set PYTHONPATH to that package's parent. Do not copy into 7H's checkout.

In another terminal:

```bash
curl --fail http://127.0.0.1:8021/api/platform/v1/health
curl --fail http://127.0.0.1:8021/api/platform/v1/ready
curl --fail http://127.0.0.1:8021/openapi.json
curl --fail http://127.0.0.1:8021/api/platform/v1/providers
curl --fail -H 'Content-Type: application/json' -d '{"query":{"point":{"latitude":42.03,"longitude":-93.62},"start":"2024-02-01","end":"2024-02-29"}}' http://127.0.0.1:8021/api/platform/v1/climate/jobs
# Replace JOB_ID with the returned ID; a completed job can contain explicit source gaps.
curl --fail http://127.0.0.1:8021/api/platform/v1/jobs/JOB_ID
python server/platform-v1/tools/http_smoke.py --url http://127.0.0.1:8021
```

`http_smoke.py` is an explicit live network test against a disposable instance.
It creates software-test sample farm geometry at a public regional query point,
retrieves live POWER, saves three records, invokes actual Rust against a
reference profile, verifies insufficient information, history and assistant refs.
It does not claim a real farm, agronomic field validation or a recommendation.

## Windows native setup

From the independent 7I checkout in PowerShell, with Python 3.12 and Rust 1.99
installed. Choose new absolute local paths and preserve Windows folder ACLs:

```powershell
py -3.12 -m venv C:\EarthSyncPrivate\venv7i
C:\EarthSyncPrivate\venv7i\Scripts\Activate.ps1
python -m pip install -r server/platform-v1/requirements.lock
python server/platform-v1/tools/prepare_compat.py C:\EarthSyncPrivate\compat7i
cargo build --locked --manifest-path C:\EarthSyncPrivate\compat7i\18\engine\Cargo.toml --example v03_demo
$env:PYTHONPATH = (Resolve-Path server).Path
$env:EARTHSYNC_PLATFORM_LOCAL = '1'
$env:EARTHSYNC_PLATFORM_DIR = 'C:\EarthSyncPrivate\data7i'
$env:EARTHSYNC_V03_EXECUTABLE = 'C:\EarthSyncPrivate\compat7i\18\engine\target\debug\examples\v03_demo.exe'
$env:EARTHSYNC_V03_SHA256 = (Get-FileHash $env:EARTHSYNC_V03_EXECUTABLE -Algorithm SHA256).Hash.ToLowerInvariant()
$env:EARTHSYNC_CATALOG_PATH = 'C:\EarthSyncPrivate\compat7i\15\data\crop-knowledge\v1\catalog.json'
$env:EARTHSYNC_CATALOG_SHA256 = (Get-FileHash $env:EARTHSYNC_CATALOG_PATH -Algorithm SHA256).Hash.ToLowerInvariant()
uvicorn earthsync.platform_v1.api:app_factory --factory --host 127.0.0.1 --port 8021 --workers 1 --no-proxy-headers --no-access-log
# In a second activated terminal:
Invoke-RestMethod http://127.0.0.1:8021/api/platform/v1/ready
python server/platform-v1/tools/http_smoke.py --url http://127.0.0.1:8021
```

No shared Run-WebDemo.ps1 change. Windows CI is supplied; interactive Windows,
LAN, phone and Android verification must not be inferred from Linux results.

## Container and local server operations

Build uses digest-pinned base images, exact PR source exports, pinned wheelhouse
and Cargo.lock vendor checksums. Download dependencies using trusted host tooling;
Python installation and Rust compilation then need no package-network access.
The slim image installs Debian's signed libexpat1 runtime package for rasterio.
Do not disable TLS verification to work around an enterprise proxy. The wheelhouse
must match the target Linux/Python ABI/architecture; Linux x86_64 was tested.

```bash
python -m pip download --only-binary=:all: --dest /tmp/earthsync-7i-compat/wheels -r server/platform-v1/requirements.lock
cargo vendor --locked --manifest-path /tmp/earthsync-7i-compat/18/engine/Cargo.toml /tmp/earthsync-7i-compat/cargo-vendor
docker build --build-context compat_source=/tmp/earthsync-7i-compat -f server/platform-v1/Dockerfile -t earthsync-platform-v1:local .
docker compose -f server/platform-v1/compose.yaml up -d
# Linux host networking only, loopback bind; no public deployment.
curl --fail http://127.0.0.1:8021/api/platform/v1/ready
docker compose -f server/platform-v1/compose.yaml down
```

Linux Compose preserves a named private volume, runs UID 10001 with a read-only
root, 1 GiB/2 CPU/64 PID limits, no capabilities and a 64 MiB temporary directory.
Use one service worker: process-local queue/cache concurrency is not coordinated
across replicas. Container CI smoke publishes **no ports**, executing loopback
requests inside the disposable container. Windows should use the native commands;
Linux host-network behavior is not claimed on Docker Desktop.

A hosted deployment is **disabled**: do not put this behind a public reverse proxy
or remove loopback checks. Hosted OIDC/session validation, trusted principal
injection, PostgreSQL/PostGIS persistence, tenant-scoped object storage, quotas,
DB operational acceptance and deployment-origin review are separate integration
work. SQLite is the tested local implementation; no pretend PostgreSQL adapter or
untested PostGIS migrations are advertised. No paid resources or public services
are created by these commands.

## Backup, restore and migration

Stop the single HTTP worker before backup/restore/cleanup so DB and files are
consistent. Backups contain private coordinates and photos; keep folder ACLs,
restrict access, encrypt externally and test restoration. Destination must be new.
No arbitrary archive extraction is accepted by the restore path.

```bash
python -m earthsync.platform_v1.maintenance migrate --directory /absolute/private/data
python -m earthsync.platform_v1.maintenance backup --directory /absolute/private/data --backup /absolute/private/backup-2026-11-14
python -m earthsync.platform_v1.maintenance restore --directory /absolute/private/restored --backup /absolute/private/backup-2026-11-14
python -m earthsync.platform_v1.maintenance cleanup --directory /absolute/private/data
```

Migration application is transactional and checksums are immutable. Restore
checks the manifest, DB integrity, foreign keys and every object reference/hash.
Failed DB writes clean newly created objects; a crash after deletion can leave an
unreferenced private file, removed by offline cleanup. Audit rows contain opaque
IDs/event/version/time, not raw coordinates. Disable access logging as above;
source diagnostics never echo exception messages or request bodies.
