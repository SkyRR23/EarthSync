# 7I verification and completion status

14 November 2026. Independent branch `feat/backend-evidence-platform-v1`, base
`feat/web-demo` e0cdaaf. No public deployment, paid resource, merge or 7H worktree
modification. Source provenance acceptance is distinct from farm/agricultural
validation. See `provider-probes.json` and `nasa-source-review.json` for receipts.

## Executed checks

- Full Python backend: **131 passed, 3 skipped**. The three skipped tests are the
  explicitly opt-in NASA/soil/HLS live suite. Existing Rust compatibility tests
  were activated with Cargo on PATH; actual v03 integration, PR #14 explanation,
  PR #15 catalog and PR #16 sanitizer were exercised against pinned source exports.
- Pinned PR #18 Rust: **111 passed**, including all 29 v03 tests; no failures.
  The first archive-only attempt lacked an existing app fixture. Exporting that
  exact pinned fixture fixed setup; `prepare_compat.py` includes it now.
- Ruff lint: all server modules/tests pass. New package/tests/tools formatting
  passes. The full server formatting check still reports the **unchanged baseline
  `server/tests/test_web_demo.py`**, already corrected by PR #16 for 7H; it was not
  edited concurrently here. `pip check` passes; patch whitespace check passes.
- Explicit live NASA test: **1 passed**, 2 unselected provider tests skipped.
  Four pilot probes captured **12 successful real daily responses**, 29/29 records
  each, stored byte-for-byte with hashes and completion timestamps. This is
  regional availability for February 2024, not farm/crop scientific validation.
- Explicit live SoilGrids WCS + HLS CMR suite: **2 failed**, 1 unselected NASA test
  skipped. Both fail with `OUTBOUND_PROXY_BLOCKED` (proxy HTTP 403). They do not
  pass by asserting an unavailable stub. USDA, Australian soil and Open-Meteo
  direct probes were also denied. OPERA acquisition/pixel access remains unverified.
- Actual Uvicorn HTTP → live POWER → 3 persisted evidence records → actual Rust
  v03 → reference-only insufficient-information result → persisted decision and
  actual-source assistant context: **passed** on loopback port 8023.
- Docker: **final image build and actual container smoke passed**. Initial package download failed on the
  environment proxy certificate chain; the offline wheelhouse/Cargo vendor build
  resolved package transport without disabling TLS. Smoke testing caught and
  fixed non-root COPY ownership and the slim image's missing libexpat1 dependency.
  Container execution uses no published ports, a read-only root, private temporary
  data, bounded resources and the actual compiled Rust binary.
- Dedicated Linux/Windows × Python 3.12/3.13 CI and container job are supplied.
  Remote CI status belongs to the draft PR; local Linux results do not prove
  interactive Windows, PowerShell, browser, Wi-Fi, Android or phone validation.

## A–O end-to-end coverage

| Flow | Evidence / status |
|---|---|
| A regional climate without farm | API job test + actual daily provider captures; no farm inferred |
| B confirmed farm context | Owned context/history/API tests; real HTTP climate association |
| C soil available/unavailable | Synthetic native-raster parser test; actual live access FAILED |
| D optical available/unavailable | Synthetic QA/NDVI/metadata tests; actual CMR access FAILED |
| E SAR available/unavailable | Synthetic native power/mask and compatibility tests; live ingestion unfinished |
| F photos upload/delete | Actual PR #16 sanitizer; API/file deletion/EXIF stripping and owner isolation tests |
| G catalog reference lookup | Actual pinned catalog lookup/projection; eligibility remains false |
| H actual Rust v03 | Actual compiled binary via process, FastAPI, HTTP and container smoke |
| I missing/incompatible evidence | Explicit gaps, duplicate-series rejection, reference-only results; actual Rust sequential overlap conflict |
| J chatbot source refs | Generated context accepted by actual #14 ChatRequest/explain, original source citations preserved |
| K outage | Offline transport/API/job states; no synthetic fallback |
| L restore | Database + actual sanitized object backup/restore; corruption rejection |
| M unauthorized access | Store/objects/jobs cross-owner rejection, remote/Host/Origin refusal, no owner injection |
| N long job | Queue cap, pending deduplication, cancellation, timeout, restart recovery and safe terminal errors |
| O readiness | DB integrity + actual startup Rust probe; missing Rust returns 503; provider status remains separate |

## Phase completion (no blanket milestone-complete claim)

| Phase | Status | Remaining work |
|---|---|---|
| 1 audit | Implemented | Recheck 7H contracts when published |
| 2 evidence | Implemented v1 proposal | 7H/Flutter acceptance; optical/radar diagnostic-to-evidence projection |
| 3 climate | Working live daily extension | GEOSIT independent validation; ET0 pipeline; farm calendar applicability |
| 4 soil | Focused WCS code + offline QA; live blocked | Accepted real descriptor/raster, quantiles/release; USDA/Australian provider implementation |
| 5 optical | Discovery + local extraction/QA foundation; live blocked | Authenticated asset retrieval, accepted manifests/pixels, native dated time series/visual products |
| 6 SAR | Local summary + compatibility foundation | Live acquisition/asset/mask acceptance, common-pixel change/time series and visualization |
| 7 monitoring | Source health/freshness code + #17 compatibility audit | Verified forecast model issue/run, licensed global adapters; no hazard warnings inferred |
| 8 storage | Working SQLite + files/migrations/restore | Hosted PostgreSQL/PostGIS, tenant object persistence and retention operations |
| 9 security | Local-only boundary and resource tests implemented | Hosted OIDC/session identity, tenant integration and independent security acceptance |
| 10 orchestration | Actual v03, catalog adapter, provenance/history/conflicts | Independently reviewed applicable crop requirements; numeric soil/ET0 projections |
| 11 pilots | Four real regional climate probes + reference scope | Field ground truth, calendar/agronomic validation, non-climate live coverage |
| 12 APIs | Standalone implemented endpoints with OpenAPI | Reviewed 7H routing/consumers; radar/weather routes only after ingestion acceptance |
| 13 processing | Bounded one-process jobs/cache implemented | Durable multi-worker queue only if justified; full raster jobs require accepted retrieval |
| 14 operations | Local image/config, maintenance and runbooks | Hosted auth/database/object deployment and operational acceptance; interactive Windows execution |
| 15 testing | Automated code/contract/runtime suites and CI | Blocked live providers, hosted/field/device tests and 7H combined acceptance |

## Exact verification commands

From the independent 7I checkout with the isolated environment activated:

```bash
python server/platform-v1/tools/prepare_compat.py /tmp/earthsync-7i-compat-new
cargo build --locked --manifest-path engine/Cargo.toml --example web_engine
cargo build --locked --manifest-path /tmp/earthsync-7i-compat-new/18/engine/Cargo.toml --example v03_demo
cargo test --offline --locked --manifest-path /tmp/earthsync-7i-compat-new/18/engine/Cargo.toml
export PYTHONPATH="$PWD/server"
export EARTHSYNC_COMPAT_ROOT=/tmp/earthsync-7i-compat-new
export EARTHSYNC_TEST_V03=/tmp/earthsync-7i-compat-new/18/engine/target/debug/examples/v03_demo
python -m pytest -q server/tests
python -m ruff check server/earthsync/platform_v1 server/tests/platform_v1 server/platform-v1
python -m ruff format --check server/earthsync/platform_v1 server/tests/platform_v1 server/platform-v1
python -m pip check
git diff --check
# Deliberately network-enabled; ordinary CI never sets this variable:
EARTHSYNC_LIVE_PROVIDERS=nasa python -m pytest -q server/tests/platform_v1/test_live_opt_in.py
EARTHSYNC_LIVE_PROVIDERS=soil,hls python -m pytest -q server/tests/platform_v1/test_live_opt_in.py
python server/platform-v1/tools/probe_pilots.py /tmp/new-pilot-captures --allow-network
```

The blocked-provider command is expected to fail in the current environment;
that failure is a release blocker, not successful live ingestion. On Windows,
set environment variables with PowerShell and add `.exe` to the Rust path.
