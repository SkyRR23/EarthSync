# Real-time verification and remaining acceptance gates

Baseline: **660b479c3ffb714cd1d489e1241c026ceae6ed67**. Exact delivery commit and draft
PR are recorded in Git/PR metadata; no main merge or public deployment occurred.
See [machine-readable results](evidence/verification-summary.json),
[current public Ames receipt](evidence/current-ames.json),
[five-location live checks](evidence/live-providers.json) and
[complete recovery hashes/counts](evidence/recovery-summary.json).

## Actual checks

| Check | Result | Scope |
|---|---|---|
| Python/backend/operations | **504 passed, 7 explicit skips** | Actual native Rust executable and combined compatibility exports enabled; optional live opt-ins kept separate |
| New real-time tests | **38 passed** within the backend run | Source parsing, QC, depths/units, timezones, cache/ETag, backoff/restart, 401/403/429/500/503, DNS/TLS/timeout fixtures, expiry, official geographic coverage before empty alerts, byte limits, corrupt data, privacy and recovery |
| Rust engine | **124 passed** | Original engine source unchanged; 6 bridge tests also passed |
| Flutter | **138 passed, 3 explicit live opt-in skips** | Full suite, including meaningful timeout retry-gap and accessibility regressions; clean analyzer and release Web build |
| Actual Chromium map/environment | **14 stages**, no page errors | Polygon draw/edit/undo/save/reopen, actual SoilGrids/GFS, dated modes, reports and phone layout; no TLS exception |
| Actual Chromium farmer workflow | **19 stages**, no page errors | Actual NASA/Rust, three saved strategies, chronology conflict, history/photo/report ownership, reassessment, deterministic citations, Burmese and named injected offline tests |
| Actual Chromium monitoring | **7 stages**, no page errors | Real public station values, newer automatic timestamp without restart/manual refresh, measured cache latency, explicit local transport outage/recovery, phone and actual Burmese settings |
| Live providers | Actual network and numerical requests | Iowa, NWS forecasts/grid/alerts, Open-Meteo, original/extended GFS, SoilGrids, authenticated IMERG/SMAP/HLS-VI; not mocked transport |
| Stop/backup/restore/restart | **PASS** | Original stores unchanged; exact tables including `realtime_state`, objects, separate workspace and token restored to new destinations; actual monitoring browser run against restored stores |
| Scientific integrity | **PASS** | 49 catalog files, 11 review-package files, 35 original input pins; all 60 candidates blocked, zero executable rules |
| Windows interactive acceptance | **PENDING USER** | Linux Chromium and Windows CI do not certify a person's local machine |

CI results are the draft PR's checks for the exact head. Do not infer green CI from
this local table. The inherited Windows/Linux, Flutter, Rust, packaging and Docker
workflows run on the PR; failures must be resolved or explicitly reported before
release approval. No hosted security architecture or public endpoint is claimed.

## Evidence interpretation

Real station observations, forecasts, numerical satellite data and source hashes
are distinct from software test fixtures. Farmer plans/history/photos in browser
acceptance are explicitly synthetic inputs, not field ground truth. The named
browser outage aborts the **local cache request**, rather than pretending that an
actual NASA/NWS provider went down. Offline unit transports separately test genuine
provider-error handling. The primary live flow never substitutes source fixtures.

The first monitoring accessibility check found readable visual values missing
from Chromium's accessibility tree. Explicit semantic containers corrected that,
and a regression checks the observation timestamp's semantic label. Real outage
verification also found periodic timeout polling could keep Refresh disabled;
single-flight polling now waits 15 seconds after completion and leaves an idle
retry gap. Initial browser selectors were corrected to actual composite control
names. Earlier failed diagnostics remain private and are not counted as passes.

An inherited Chromium `Network.getResponseBody` read failed after the UI had
successfully saved a native decision. The verifier now confirms the single newly
persisted decision through the actual API when that specific protocol error occurs,
without replaying a mutation. The subsequent complete 19-stage journey passed.

Open-Meteo initially returned a cloud-route/upstream HTTP 503 connection timeout,
despite successful earlier five-location requests. The backend retained the honest
unavailable state and observed its retry schedule; later it recovered automatically.
The final restored monitoring receipt records all Ames weather sources fresh and
all three numeric NASA sources as **LATEST_AVAILABLE_DELAYED**.

## 30-step acceptance disposition

| Requested behavior | Disposition |
|---|---|
| 1–11 launch/Ames/reference/station/time/moisture/NWS/hourly/daily/alerts/global/GFS | PASS in actual app/API/provider journeys |
| 12–15 IMERG/SMAP/NDVI/soil | PASS for actual bounded numeric Ames extraction and preserved pH; NDVI overlay/field averaging remains unavailable |
| 16–18 source states/automatic refresh/new data without restart | PASS; actual measured watch in evidence |
| 19 stale/unavailable behavior | PASS for offline provider-failure contracts and explicitly injected browser-local outage; these are separate scopes |
| 20–25 field/evidence/three strategies/save/assistant/languages | PASS in actual map/farmer journeys; full native agricultural translation review remains partial |
| 26–29 restart/persistence/independent restore/browser suite | PASS in independent restored local state |
| 30 actual latency | PASS for measured cached HTTP and backend-noticed-to-display samples; provider publication-to-ingestion remains UNKNOWN |

These are multiple explicitly scoped journeys, not a claim of one uninterrupted
30-step run. Independent field accuracy, scientific recommendation approval,
interactive Windows acceptance, extra SoilGrids properties, HRRR ingestion and a
numeric NDVI map overlay remain outside the completed acceptance claim.
