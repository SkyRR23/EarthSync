# Final combined candidate verification

PR #29 combines completed 7X, completed 7G and the farmer-product implementation.
It targets main and remains a draft: **the complete release gate is not satisfied**.
Quantitative vegetation observations remain unavailable, so main is unmerged.
Implemented workflows below were exercised in the combined application; this is
not a report inferred from three separately passing branches.

## Results and classifications

| Check | Result | Classification / evidence |
|---|---|---|
| Python backend plus operations, actual native v0.3 enabled | **456 passed, 1 skipped** | REAL opted-in NASA/HLS discovery/SoilGrids WebDAV/GFS requests plus CACHED REAL, SYNTHETIC and MOCKED contract fixtures. `evidence/python-integrated.log`, `evidence/live-providers/`. The sole skip is legacy SoilGrids WCS; WebDAV was tested live. |
| Rust after exact-coordinate fix | **124 passed** | Actual native calculations on labeled synthetic/cached-real inputs. `evidence/rust-integrated.log`. |
| Flutter including native bridge | **131 passed, 3 skipped** | Actual native bridge, CACHED REAL source fixtures and MOCKED/SYNTHETIC UI states. Optional live Flutter cases are explicitly skipped; real browser NASA/Rust evidence is separately recorded. `evidence/flutter-integrated.log`. |
| Flutter analyze / production Web build | **Passed** | `flutter-analyze.log`, `flutter-build.log`; compiled with the private loopback PLATFORM_URL, bundled Web resources and a generated public-only offline shell. |
| Farmer screen/refresh/scroll preservation and responsive comparison | **Passed** | `final-ui-regressions.log`, `companion-risk-regressions.log`, `final-display-regressions.log`, `rotation-editor-regression.log`. Tests exercise the actual rotation screen and unsubmitted journal inputs, English/Burmese and phone/desktop widths. |
| Soil-depth/root-trait interpretation | **4 comparison tests passed** | `trait-interpretation-regression.log`. A soil-depth requirement does not establish a crop root characteristic. |
| Three-strategy assistant retrieval | **47 focused tests passed** | `assistant-comparison-regression.log`; default answer preserves all selected strategies and farmer-declared roles without altering original Rust explanations. Actual browser answer includes baseline, alternative B, all three decisions and citations. |
| Crop v1 integrity | **39 passed** | `catalog-v1-tests.log`. |
| Crop v2 reference/native/science | **55 + 5 + 14 passed; 16 artifacts reproducible** | Catalog receipts and `catalog-integrity.json`: 708 identities, 75 profiles, 937 claims, 40 sources, 8 reference rotations. |
| Scientific package and 7V gates | **Passed; 60 blocked, 0 executable** | `source-integrity.log`, `blocked-rule-integrity.log`, `blocked-rule-tests.log` (32 tests). Original reviewed bytes and input pins retained. |
| Docker exact integrated backend | **Build and smoke passed** | `docker-final-build.log`, `docker-final-smoke.log`. Nonroot, read-only root, private tmpfs, no published ports; reference lookup, blocked sidecar, owned polygon with a precision-sensitive coordinate, actual Rust and persisted decision. No live provider claim for this smoke. |
| Combined map/soil/forecast browser | **14 stages, zero page errors** | `browser-7g/results.json`: actual field drawing/edit/undo/confirm/reopen and real source requests. Farmer field/report inputs are SYNTHETIC. |
| Tile delivery | **57 HTTP 200s in a separately disclosed test context** | `browser-7g-tile-verification/`. Normal managed Chromium tile requests failed `ERR_CERT_AUTHORITY_INVALID`; the second run explicitly permits the Cloud proxy certificate in that test browser. Application/backend TLS verification was never weakened. Normal tile certificate trust remains unverified in this environment. |
| Combined farmer journey | **22 distinct checkpoints passed, zero unhandled page errors** | `browser-final/results.json`: real native three-strategy creation, explicit baseline/priorities, save/reopen, date conflict, crop history, sanitized photo, dated observation, explicit reassessment, assistant, Burmese/English, outage and cold offline reopening. See execution scope below. |
| Crop explorer and public reference cache | **Passed** | `browser-crops/results.json`: actual common-alias search, two side-by-side source-reference cards, page reload and cached viewing during a MOCKED API outage. Published crop facts are CACHED REAL reference content, not a new field observation. |
| In-app dated forecast acknowledgment | **Passed** | `browser-risk/results.json`, `acknowledgment.json`: actual Flutter interaction and persisted farmer acknowledgment; dated GFS reference is CACHED REAL. Official issued alerts remain UNAVAILABLE. |
| Restart and restore | **Passed** | `recovery-exact-stores.json`, `restarted-http.json`, `restored-http.json`: every SQLite table/object hash compared, originals unchanged, exact saved comparisons/reports/decisions/source lineage and both separately authorized photo stores verified through original and restored HTTP services. |
| Photo/access controls | **Passed in local scope** | `workspace-photo-auth.json` and HTTP receipts: sanitized test image, authorized retrieval, unauthenticated workspace image rejected 401; untrusted Host/Origin rejected 403. Cross-owner/farm links, quotas and idempotency covered by Python tests. |
| CI on completed product source | **All 11 workflows green at `393b89af913ad4a3afd078a9f164fdc4430d9f06`** | Includes Windows/Linux backend, actual Docker, scientific contracts, Flutter/native and Windows 7Q build/startup. Final report/trait-interpretation update requires its own exact-head checks; the final result is recorded on PR #29. Earlier green heads never certify a later change. |
| Interactive Windows / assistive devices | **SKIPPED** | Linux Chromium and responsive/widget coverage do not establish interactive Windows acceptance, destination-specific ACLs or every screen-reader behavior. |
| Hosting | **SKIPPED / not deployed** | Mandatory full-product gates remain open. Static hosting alone cannot run native Rust/FastAPI with persistent SQLite/photos. No billing changes, public private-port exposure or tunnel. |

## Execution scope

REAL means a provider response or actual runtime execution was obtained; it does
not make the farmer's test inputs real observations. CACHED REAL preserves the
original response/source dates and hashes. SYNTHETIC means explicitly labeled
software-test records. MOCKED includes injected API outage and browser offline
mode. SKIPPED, FAILED and UNAVAILABLE are not converted into passes.

The browser journey was **resumed across browser restarts during defect repair**,
not one uninterrupted 28-step pass. Each resumed stage reopens and compares the
exact saved native assessments, comparison group, photo-linked report and
reassessment against the private API before continuing. No provider response is
substituted. Earlier failed automation diagnostics remain private and are not
published as passing evidence. The final receipt explicitly records resumption. Public JSON receipts now contain only allowlisted summaries and hashes of private originals; raw field geometry, identifiers, observations and provider responses are retained locally outside Git.

The three synthetic sequences use deliberately short July periods and one
inclusive-date overlap to test software chronology. They are not valid crop
maturity examples, recommended sequences or actual farmer practice. The baseline
is explicitly declared as an existing software-test plan. The Iowa test location
and Myanmar reference profiles exercise distinct source scopes; they do not
establish Myanmar-profile applicability to an Iowa field.

Original NASA retrievals and later cache hits remain distinguishable in the private receipts and their public source-summary metadata. The final
rotation receipts use saved historical source snapshots with original retrieval
and exact ET0 values. Separate live opt-ins prove actual current provider access
where claimed. HLS discovery is metadata access, never accepted NDVI pixels.

## Defects corrected without weakening safeguards

- Native JSON parsing changed one polygon longitude by one floating-point rounding
  unit; strict Python/Rust equality correctly rejected it. `float_roundtrip`
  preserves exact parsed coordinates. The guard was retained, with native and API
  regressions. The pre-fix failure is summarized in `geometry-precision-before.json`; its precise-coordinate trace remains private.
- Loading UI shifted an unkeyed editor wrapper and reset the proposal. Stable farm/
  decision keys and blocked input during refresh preserve it.
- Lazy scrolling disposed unfinished forms. Journal, rotation editor and comparison
  state now remain alive while their screen is open, with scroll-away/back tests.
- The forecast disclosure was merged into one accessibility group. Explicit child
  semantics restore actionable forecast and acknowledgment controls.
- Default assistant truncation buried comparison records and omitted strategy B.
  Comparison questions prioritize declared roles and retain up to six selected
  native decisions, keeping farmer text separate from original Rust findings.
- Default comparison cards now show familiar crop names, declared durations,
  original-period water summaries and uncertainty; full technical details remain
  expandable. A soil-depth requirement is never relabeled as root architecture.

## Security and recovery scope

Review covered new journal/comparison/report projections, photo/source ownership,
additive migrations, deterministic context retrieval, public-static caching and
packaging. SQL values are bound; source endpoints accept owned IDs, not arbitrary
raster URLs or local files. Old migrations 001/002 retain checksums; 003/030/031
are additive. No farm note becomes verified science or permanent history without
the applicable explicit confirmation. Forbidden/missing farms do not fall back to
private offline cache. Non-idempotent writes are never silently replayed.

The public service worker's explicit, hash-versioned static allowlist excludes
private APIs, tokens, private photo pixels, map tiles and rasters. Device record
caching is opt-in, revision/origin-bound, read-only when stale/offline and removable.
The original token-authorized workspace and farm-owned photo stores stay separate.
Their private directories are mode 0700 and token mode 0600 in this test environment.
This is scoped engineering verification, not public multi-user authentication or
an exhaustive external security attestation.

## Remaining release gates and limits

1. **Mandatory accepted real vegetation observation: UNAVAILABLE.** Completed 7G
   source evidence records Earthdata 401 and ORNL MODIS 503. No authorized,
   quality-accepted raster/NDVI overlay or vegetation time series was obtained.
   The live ingestion/overlay workflow is not accepted; a clear unavailable state does not implement that missing analysis.
2. **Official warnings/current station weather/forecast precipitation: UNAVAILABLE.**
   GFS support is sparse regional temperature, with verified model/valid times;
   independently verified publication time is absent. No crop-specific injury,
   pest prediction, official warning or all-clear is inferred.
3. **Scientific suitability: SCIENTIFICALLY BLOCKED.** Zero approved executable
   crop rules. Crop exploration works without invented rankings, field benefits,
   nitrogen credits, income, yield or irrigation prescriptions.
4. **Language/accessibility scope: PARTIAL.** Core Burmese labels/glyphs, actual
   language switching and responsive layouts work. Native agricultural translation
   review, every explanatory label, interactive Windows and assistive devices
   remain unverified. Untranslated scientific source text falls back to English.
5. **Optional advanced objectives: PARTIAL.** No new validated multi-year seasonal
   model, field vulnerability score/map, advanced harmonization or simulated NASA
   forecast is claimed. Native source resolutions and unknown gaps are retained.

Main must not merge while mandatory acceptance remains incomplete. The local
candidate and exact build/run/restore commands are the demonstration fallback.

The 28 requested acceptance objectives, including step-specific limits and the
optional Undecided choice, are recorded in `evidence/acceptance-28.json`.


## Publication privacy

Automatic approval review rejected publishing raw runtime evidence containing
precise field coordinates, boundaries, identifiers and environmental records.
Those files were retained privately. They are not ancestors of the final published
commit. Public receipts use `earthsync.public_verification_receipt.v1`, omit field
data and link local originals only by content hash. The five published screenshots
were visually reviewed to exclude location and record identifiers; map and assistant
screens with location details remain private. No screenshot was fabricated or edited.

Raw browser helpers now require a dedicated output directory outside the checkout.
The summary utility copies only reviewed screenshot names with an explicit flag,
rejects UUIDs/location keys in public metadata, and refuses symlinked input. Four
privacy regression tests pass (`publication-privacy-tests.log`). No raw artifact
should be copied from a local archive into a public PR or pushed via archive refs.
