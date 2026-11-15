# Input propagation, product coverage and post-submission roadmap

Current scope is global location support and English. Myanmar source profiles
are examples with explicit source scope, never a hard-coded applicability exception.

## Farmer input propagation

| Input | Storage / attribution | Rust and evidence boundary |
|---|---|---|
| Selected area / device location | Local preferences; separate from confirmed farm | Does not confirm a farm, boundary or measured field area |
| Confirmed farm name/point/date | Local confirmed profile; explicit farm-link action creates an owned backend farm revision | Backend UUID/point/confirmation reach Rust; changing confirmation creates a separate revision |
| Backend production system | Explicit farmer declaration, selected from existing systems | Validated identity/system context enters Rust; irrigation delivery and field measurements do not follow from a label |
| Previous/current crop planning notes, dates, irrigation/drainage notes and priorities | `farm.notes.<id>` in local SharedPreferences; editable farmer notes | Not silently copied into backend history, accepted observations, source evidence or Rust |
| Questionnaire irrigation/drainage/priorities | Existing typed questionnaire controls include unknown choices | Remain within their existing questionnaire contract, not new independently verified platform observations |
| Explicit saved crop/fallow history | Owned SQLite history with report time and attribution | `farmer_reported`, unreviewed source, field ID, exact dates and uncertainty enter Rust; `history_complete=false` remains |
| Proposed sequence dates / reference choices | Explicit saved assessment and source sidecars | Actual plans/system enter Rust; references retain region/cultivar/source limitations and empty executable rules |
| Selected NASA snapshots | Immutable owned environmental evidence | Exact source hashes/dates/quality and accepted normalized variables enter Rust; unsupported variables stay retained sidecars/gaps |
| Derived ET0 / rainfall | Persisted Rust calculation, executable hash and parent evidence IDs | Flutter and assistant read the same saved quantities; neither calculates replacement values |
| Photos | Authorized workspace BLOB store and separate farm-owned PNG object store | No automatic transfer, soil chemistry inference or private-token inclusion in assistant context |

The farm screen displays saved history through **Saved farmer-reported history**.
The inherited browser acceptance exercises explicit history creation, refresh and
assistant context. A date gap is never inferred as a fallow report. Independent
environmental observations remain distinct from declarations and planning notes.

## Rotation comparison and accessibility

One assessment accepts a first reference profile and optional second profile in
one declared sequence. To compare alternatives, save each sequence separately
and select its saved decision under **Compare two saved assessments**. The view
shows both plans' dates, Rust chronology, original sources/reference scope, missing
inputs and saved history. It does not optimize the sequence, generate alternatives,
recommend a preferred crop or promise rotation benefits. Each alternative can use
different snapshot/history context; reviewers must inspect those sidecars.

The browser comparison uses labeled software-proposed rice/groundnut dates at a
global test point, with an explicitly chosen Myanmar reference scope. It does
not establish that either crop is applicable at the point. One declared order
has chronological support and the reversed order conflicts; both retain unknown
agronomic requirements, no candidates and null ETc.

Crop lookup now offers five catalog-name shortcuts while retaining free lookup,
ambiguity and unavailable results. Exact compatible source profiles use existing
dropdowns. Four water/sequence date fields now offer standard Flutter calendar
pickers while preserving manual exact-date validation. Production systems already
use a dropdown; no unknown value is fabricated to enable persistence. The typed
questionnaire already offers irrigation, drainage, priority and unknown controls.
The local notes form still permits free-text production/irrigation/drainage/priority
notes, so it remains a usability limitation rather than a verified input workflow.
No new dependency or complete form redesign is introduced. This is a lightweight
review, not a WCAG conformance or screen-reader certification.

## Coverage matrix

| Status | Features / limits |
|---|---|
| Implemented; verification receipts linked in VERIFICATION.md | Confirmed point/system, real historical NASA weather, actual Rust FAO-56 ET0/rainfall, immutable lineage, SQLite evidence/history/decisions, v1/v2 reference lookup, deterministic cited assistant, Flutter Web, backup/restore and loopback ownership/photo guards |
| Partially implemented | Two-plan declared sequences and comparison of separately saved alternatives; local farmer notes and explicit saved history are distinct; production context does not establish field water supply |
| Partially implemented geospatial contract | Backend accepts optional confirmed polygons; Flutter ConfirmedFarm remains point-based. No polygon drawing, measured farm area, field-level satellite sampling or completed Flutter boundary-persistence journey is claimed |
| Not implemented | Accepted numerical soil/GAEZ integration, validated satellite index pixels/time series, official forecasts/alerts, automatic plan optimization, public multi-user identity/hosting, LLM/RAG, Android runtime acceptance |
| Scientifically blocked | All 60 7V candidate rules; accepted local Kc curves, crop ETc/field irrigation without required evidence; crop suitability rankings, nitrogen/pest benefits, yield/profit predictions |
| Planned after submission | The milestones below; none is a current release blocker or completed feature |

## Post-submission roadmap

**A. Farm Map & Geospatial UX.** Evaluate MapLibre or a suitable Flutter-compatible
mapping stack; standard/satellite/hybrid/terrain views; polygon drawing/editing,
explicit confirmation and persistent versioned boundaries. Preserve point/boundary
distinctions and avoid describing a drawn boundary as surveyed area.

**B. Satellite Intelligence.** Audit `superzero11/OpenFarm` and its stated
BSD-3-Clause license, relevant source/dependency licenses and redistribution terms
before any reuse. This release does not import or replace EarthSync with OpenFarm.
Then validate HLS/Sentinel-2 ingestion, native quality/cloud/shadow masks, registered
red/NIR bands, NDVI/EVI overlays and acquisition-aware time series. No invented pixels.

**C. Soil Intelligence.** Establish an accepted SoilGrids raster/product/nodata
contract before extraction; depth-aware raw pH, organic carbon and texture overlays;
guided farmer laboratory-test records retaining method, depth and date. Keep modeled
raw properties, measured tests and crop suitability distinct.

**D. Crop Decision Intelligence.** Commission further independent crop-rule
validation, fuller rotation/candidate comparison, and crop-specific ETc/water balance
only with accepted curves, stages, locality and field evidence. Preserve FAO-56
linear development/late interpolation and independent applicability review.

**E. Farmer Companion & Risk Intelligence.** Verified forecasts and official alerts
with geographic/issue/valid-time checks, growing-stage monitoring, source-grounded
assistant and optional RAG. Burmese localization and low-bandwidth support follow
the current English/global release. No unverified warning, diagnosis or economic
forecast is inferred from historical weather or imagery.
