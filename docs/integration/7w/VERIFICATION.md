# 7W verification and implementation status

Verified locally on Linux on 2026-11-14. This report distinguishes runtime
acceptance, cached real inputs, synthetic numerical/fault tests and unintegrated
providers. Source integrity does not establish independent agricultural approval.
Exact tool versions and executable/Web/catalog/lock hashes are in
`evidence/toolchain.json`, `artifact-hashes.json` and `verified-source-hashes.json`.

## Accepted P0 workflow

**Working:** confirmed global farm → actual NASA POWER weather → validated inputs
→ compiled Rust FAO-56 daily reference ET0/rainfall → immutable SQLite evidence →
explicit snapshot/reference selection → actual Rust calendar/gap assessment →
Flutter Web → deterministic assistant using the same saved evidence. Refresh,
process restart, complete backup/restore, desktop and phone rendering were checked.

The canonical eight-stage 7W Chromium acceptance is
[`evidence/browser-final-acceptance/results.json`](evidence/browser-final-acceptance/results.json).
The retained twelve-stage 7N regression is
[`evidence/7n-browser-release/results.json`](evidence/7n-browser-release/results.json).
Both have zero unhandled browser page errors. These are actual built Flutter
assets, actual FastAPI processes, SQLite and the hash-pinned compiled Rust; no
provider response was replaced with a browser fixture.

| Check | Actual result | Evidence |
|---|---|---|
| Full Python server + 7Q operations regressions, real native cross-language consumers, live NASA daily enabled | **413 passed, 2 skipped**, zero failures | `evidence/python-regression.log`; only optional live SoilGrids numeric and HLS discovery probes skipped |
| Existing Rust plus new FAO-56/missingness/domain tests | **123 passed**, zero failures/ignored | `evidence/rust-regression.log`; original crop types, validation and assessment algorithms unchanged |
| Existing v1 crop catalog | **39 passed**, zero skips/failures | `evidence/v1-catalog-tests.log` |
| 7P all tests with explicit live opt-in | **78 passed**, zero skips/failures | `evidence/7p-all-tests.log`: 55 offline, 14 scientific safeguards, 5 native contracts and 4 live source/discovery checks |
| 7P reproducibility and catalog graph | 16 artifacts reproduced; 708 identities, 75 profiles, 937 claims, 40 sources, 8 rotations; zero executable requirements | `evidence/7p-reproducibility.log`, `7p-catalog-check.json`; no v1/v2 dataset changes |
| 7V package/method/native compatibility | **32 passed**, zero skips/failures | `evidence/7v-native-and-package-tests.log`; exact requested 7V snapshot, current 7W executable, all candidates blocked |
| Flutter full offline regression | **112 passed**, 3 explicitly opt-in live checks skipped | `evidence/flutter-regression.log`; actual native FRB library built/loaded |
| Flutter selected live NASA/Web/platform checks | **11 passed**, zero skips/failures | `evidence/flutter-live.log`; the three opt-in paths were enabled and executed separately |
| Flutter analyzer / Web build | No analyzer issues; successful Web build | `evidence/flutter-analyze.log`, `flutter-web-build.log`; Flutter 3.44.0/Dart 3.12.0 |
| Chromium 7W / inherited 7N workflow | **8 / 12 stages passed** | Canonical browser result JSONs above; screenshots and actual API receipts in those directories |
| SQLite process restart / backup / restore | Passed; all pre-restart saved rows retained exactly and independently restored | `evidence/restart-and-restore.json`; later explicit test-farm additions are not mistaken for data loss |
| Ruff, format, dependency integrity, diff | Passed | `evidence/final-static-checks.log`; actual runtime code hashes retained |

The two skipped Python opt-in probes are not claimed as passed numerical
integration. The WCS nodata rejection remains unresolved; authenticated/QA'd HLS
pixels are not accepted. The separate 7P CMR metadata test is discovery only.
Windows, Docker image construction, Android/Gradle and public hosting were not
executed in this environment and are not represented as local successes. Existing
release/CI workflows remain available; remote CI is separate from this report.

## Live versus cached versus synthetic evidence

- `power-probe-receipts.json` and seven `power-*.real.json` files are actual newly
  fetched single-parameter July 1–7 NASA responses with completion times/hashes.
  Their original units, definitions, API/source headers, requested/returned point
  and missingness feed current provider-integrity and native calculation tests.
- `live-uncached-initial-job.json` is a real **uncached** five-day API job, captured
  during the initial browser attempt. Its backend succeeded; that early browser
  attempt did not pass UI acceptance and is not counted as an accepted browser run.
- The canonical browser's `live-water-job.json` records `cache_hit` truthfully. It
  reuses actual persisted provider captures when cached; it still runs current
  compiled Rust and creates an explicitly requested saved assessment. Original
  source retrieval times/hashes remain unchanged rather than becoming "fresh" data.
- For the public regional Iowa point `(42.0308, -93.6319)`, July 3–7 produces
  **23.193683430451973 mm ET0** and **28.68 mm rainfall**, five usable days each.
  The seven-day July 1–7 capture has **59.97 mm rainfall**, six usable ET0 days,
  a null period ET0 total and an explicitly labeled partial sum; July 2's radiation
  method domain is unsupported. Neither total is ETc or irrigation requirement.
- `fao56-example18-verification.json` is a **synthetic software numerical oracle**
  using FAO's published Uccle inputs. Native ET0 is 3.8796934649677484 mm/day versus
  published rounded 3.88, within the declared 0.03 tolerance. Southern-hemisphere
  radiation and domain/missingness rejection also pass native tests.
- 7V's 358.50 / 381.00 mm interpolation comparison uses hypothetical ET0 and is
  explicitly synthetic. No priority crop curve or actual crop ETc is approved.
- Browser transport outage is deliberately injected by aborting the API request.
  The Python provider-outage test deliberately raises a transport error for all
  weather parameters and verifies null quantities/seven explicit gaps. No real
  NASA outage is claimed, and no fake fallback response is served.
- Browser farms, proposed crop dates, history and generated photo are labeled
  software-test inputs, not independently observed field conditions. The 7N
  generated photo is sanitized, checked for authorization and explicitly deleted.

## Screenshots

- [Actual daily water calculation, desktop](evidence/browser-final-acceptance/real-water-calculation-desktop.png)
- [Source-backed reference selection](evidence/browser-final-acceptance/source-reviewed-reference.png)
- [Actual Rust crop gaps and water dependencies](evidence/browser-final-acceptance/crop-constraints-and-water-gaps.png)
- [Assistant using saved evidence](evidence/browser-final-acceptance/assistant-persisted-reference-and-water.png)
- [Water results on phone](evidence/browser-final-acceptance/water-phone.png)
- [Explicit simulated transport outage](evidence/browser-final-acceptance/explicit-simulated-transport-outage.png)

## Defects resolved and compatibility

- Refreshing saved evidence inserted loading widgets before an unkeyed water
  form and discarded its state. A stable farm key fixes it; a regression test
  checks retained dates while loading UI is inserted/removed.
- Explicit semantic containers expose updated water values/job state to assistive
  technology and the real browser acceptance layer. Phone scrolling uses actual
  viewport coordinates. Browser input helpers wait for Flutter focus before
  replacing existing text; early harness failures are not application passes.
- New 7V/7W optional assistant explanations are omitted when absent, retaining
  the existing 7N response shape. Full schema/fixture/assistant tests pass.
- A selected v2 advisory region no longer labels an unrelated global farm's Rust
  context. It stays in the source sidecar; farm region remains null and POWER
  retains its actual query context. Tests and final browser receipts assert this.
- The inherited 7N browser selector now chooses each actual source parameter
  explicitly rather than counting only the checkboxes currently visible in Flutter
  semantics. All original twelve workflow checks remain and passed.

`evidence/diagnostics/` retains the initial form-reset capture and hashed summaries
of superseded attempts. Those partial/failed attempts are excluded from accepted
stage counts. A broad 7P discovery without its required live opt-in intentionally
failed the live-suite admission gate; the explicit opt-in final 78-test run passed.
Initial Flutter runs lacked the compiled native bridge; the final full and live
runs used the actual built library and passed.

## Scientific implementation status and unresolved priorities

| Capability | Delivered status |
|---|---|
| Real daily NASA weather and FAO-56 ET0 | Implemented/tested for the accepted lineage/time/domain subset; full intermediates and gaps persisted |
| v2 crop references / source graph / 7V review | Implemented as bounded read-only adapters/sidecars; v1 remains intact |
| Crop/calendar/rotation constraints | Existing authoritative Rust chronology and unknown-rule findings retained; proposed dates can conflict; no recommendation generated |
| ETc | Existing Rust arithmetic verified, including 7V daily interpolation encoding; **no real accepted crop curve/stage offsets**, therefore live crop ETc withheld |
| Effective rain / storage / depletion / net/gross irrigation / water stress | Separate null outputs and exact dependencies implemented; **no executable complete field water balance** |
| SoilGrids / HWSD numeric soil | Not accepted; original WCS rejection retained, complementary original VRT metadata investigated; no sentinel injection or fabricated soil value |
| Guided soil/photo and wider management/land-use evidence entry | P1 unresolved; existing authorized photos, crop/fallow history and planning notes remain functional, with no silent migration |
| Additional satellite/terrain/water layers, issued warnings, pest/economics context | Inventoried/investigated with QA/rights/access limits in COVERAGE.md; not new numerical integrations or diagnoses |
| Rule promotion | All 7P rules empty and all 60 7V candidates blocked; separate versioned independent applicability review required |

**P0:** working for the accepted historical subset; domain/product exclusions are
visible limits, not manufactured outputs. Remaining P0 release work is independent
PR/scientific review and destination-specific acceptance if moved to another host.
No merge/public deployment is authorized by these tests.

**P1:** independently accepted regional/field soil evidence, guided observations
and non-agricultural land-use/management records, actual stage/field inputs and
reviewed linear Kc curves, effective rainfall/root-zone balance, real irrigation
delivery, paddy losses/storage, issued warnings, additional bounded QA'd products.
A former road/construction site must undergo compaction/contamination investigation;
no food-safety conclusion or automatic legume nitrogen credit is supported.

**P2:** AquaCrop/calibrated crop response and yield, automated photo interpretation,
economics, public multi-user identity/hosting and large-scale raster processing.
No suitability percentage, yield/profit forecast or guaranteed rotation benefit
is produced. Full acceptance and source dependency strategy are in HANDOFF_7X.md.
