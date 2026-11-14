# EarthSync / Field Shift — Team Integration Contract v1.0

**Status:** PROPOSED — team must acknowledge before treating it as frozen.  
**Date:** 2026-11-14 (hackathon kickoff)  
**Repository:** https://github.com/SkyRR23/EarthSync  
**Application name:** Field Shift  
**Document owner:** Technical lead (Rust developer)

> **Purpose:** Stop four teammates and their coding assistants from inventing incompatible file paths, function names, JSON keys, API routes or calculations. Use the same fixtures and contract across the team. A missing capability is not an implemented capability.

## 0. What's real versus what's planned

- **Existing (unmerged, PR #1, branch feat/rust-engine-foundation):** engine/Cargo.toml, engine/src/lib.rs, engine/README.md, docs/ENGINE_CONTRACT.md, .gitignore. Rust types and functions listed in §4 already exist; no engine build has been independently verified by this document.
- **Not yet created:** app/, server/, presentation/, REST server, Rust network client, crop suitability algorithm, Flutter bridge within EarthSync, farm persistence.
- **This document is a shared design proposal.** Agreement from the backend and Flutter developers is required before freezing the proposed HTTP and UI integration boundaries.
- **Priority:** produce a working end-to-end farm → environmental context → Rust analysis → Flutter display flow before secondary features.
- **Architecture locked from team discussion:** Flutter Android-first UI + on-device Rust analysis via flutter_rust_bridge v2 + remotely served environmental/crop data. Rust remains the calculation authority. Windows desktop is a useful dev target, not the submission platform.
- **Demonstration:** global-capable coordinates, but use a clearly marked, researched regional scenario rather than implying global agronomic validation. Whether the product is marketed as global-first or Myanmar-first remains a product decision.

## 1. Team ownership: one owner per boundary

| Workstream | Primary owner | Owns | Must not silently change |
|---|---|---|---|
| Rust engine / integration lead | Member 1 (you) | engine/, algorithms, validation, Rust-side HTTP integration, bridge wrappers, tests | JSON contract, scientific units, public bridge names |
| Data/backend | Member 2 | server/, NASA request and processing, crop catalog, data provenance, HTTP API, server deployment | Endpoint names, response JSON, source semantics |
| Research / UX / submission | Member 3 | presentation/, UI research, crop citations, source/license register, NASA submission | Scientific thresholds without a cited source, interface keys |
| Flutter app | Member 4 | app/, UI/forms/map/results, Android build, Rust bridge Dart integration | Rust output fields, server API shapes, source units |

Everyone can suggest changes. A change to a shared boundary requires review/ACK from the two affected owners.

## 2. Repository structure — exact proposed paths

~~~text
EarthSync/
├── README.md                        # team owner: project overview and run links
├── LICENSE                          # team selects OSI-compatible license, not yet added
├── THIRD_PARTY_NOTICES.md           # credits OpenFarm and datasets IF used
├── .gitignore
├── docs/
│   ├── TEAM_CONTRACT_v1.md          # THIS source of truth (proposed)
│   ├── ENGINE_CONTRACT.md           # current Rust contract from PR #1
│   ├── fixtures/
│   │   ├── environment.mock.json
│   │   ├── analysis_request.mock.json
│   │   ├── analysis_result.mock.json
│   │   └── api_error.mock.json
│   └── sources.md                   # owned by data + research
├── engine/
│   ├── Cargo.toml                   # actual, PR #1
│   ├── Cargo.lock                   # generate and commit for reproducible builds
│   ├── README.md                    # actual, PR #1
│   └── src/
│       ├── lib.rs                   # actual Rust v0.1 types and entrypoints
│       ├── api.rs                   # PLANNED flutter_rust_bridge export wrappers
│       ├── client.rs                # PLANNED server HTTP client
│       ├── climate.rs               # PLANNED climate helpers
│       ├── crop_rules.rs            # PLANNED verified agronomic constraints
│       ├── rotation.rs              # PLANNED scenario logic
│       └── validation.rs            # PLANNED extracted validation
├── server/                           # owned by backend; implementation not yet chosen
│   ├── README.md                    # run/deploy instructions + real base URL
│   ├── .env.example                 # key NAMES only; no secret values
│   ├── data/
│   │   └── crops_seed.json          # curated crop profiles with sources
│   └── src/                         # backend-specific code; language flexible
├── app/                              # Flutter project root; created by Flutter owner
│   ├── pubspec.yaml
│   ├── flutter_rust_bridge.yaml     # planned custom codegen config; validate first
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/
│   │   │   ├── config/app_config.dart
│   │   │   ├── bridge/engine_bridge.dart
│   │   │   └── widgets/error_view.dart
│   │   ├── features/
│   │   │   ├── farms/farm_input_page.dart
│   │   │   ├── map/farm_map_page.dart
│   │   │   └── analysis/
│   │   │       ├── analysis_page.dart
│   │   │       ├── climate_summary_card.dart
│   │   │       └── scenario_comparison_card.dart
│   │   └── src/rust/               # PLANNED FRB generated Dart output; do not hand edit
│   └── test/
│       └── analysis_contract_test.dart
└── presentation/
    ├── README.md                    # demo narrative / public URLs
    └── assets/                       # licensed or original slides/images
~~~

Paths labeled PLANNED are **not claims that these files already exist**. Do not manually create generated flutter_rust_bridge files. The Flutter and Rust owners must validate codegen output paths before locking flutter_rust_bridge.yaml.

## 3. Naming conventions — mandatory at integration boundaries

| Item | Standard | Example |
|---|---|---|
| JSON properties | snake_case, case-sensitive | monthly_rainfall_mm |
| Rust files / functions | snake_case | analyze_field_json |
| Rust structs / enums | PascalCase | AnalysisRequest |
| Dart files | snake_case.dart | analysis_page.dart |
| Dart classes | PascalCase | ScenarioComparisonCard |
| Dart methods / variables | lowerCamelCase | loadAnalysis |
| HTTP route | /api/v1/ + lowercase kebab-case path segments | /api/v1/environment |
| Git branches | feature/*, fix/*, docs/*, or feat/* | feat/rust-engine-foundation |
| Crop IDs | stable lowercase snake_case | rice, black_gram, mung_bean |
| Scenario IDs | stable lowercase kebab-case | existing, alternative-a |
| Data dates | ISO 8601; use UTC for instants | 2026-11-14T03:00:00Z |
| Coordinates | WGS84 decimal degrees | latitude=16.8, longitude=96.15 |
| Temperature | degrees Celsius | monthly_mean_temp_c |
| Precipitation | millimeters | monthly_rainfall_mm |
| Missing quantitative value | JSON null, NEVER magic -999/zero | null |

- Never use both lat/lng and latitude/longitude within a shared JSON payload.
- Never rename JSON fields in only one app. Change fixtures + contract + engine/server/Flutter together in an agreed PR.
- Field and crop IDs are stable strings; display names can be translated later.
- Monthly series are **exactly 12 elements, January at index 0, December at index 11**.
- No promises of field-scale precision when input environmental grids are coarser than a farm.

## 4. Rust public contract — ALREADY PRESENT in PR #1

Current file: engine/src/lib.rs; source of truth for implementation until superseded by merged tests.

### Public types and their exact serialized keys

**FieldInput**
- field_id: string (required)
- latitude: finite number in [-90, 90]
- longitude: finite number in [-180, 180]
- current_crop: string (required)
- irrigation_available: boolean OR null

**EnvironmentalContext**
- monthly_rainfall_mm: array of exactly 12 numbers-or-null; nonnegative
- monthly_mean_temp_c: array of exactly 12 numbers-or-null; can be negative Celsius
- source: string; should identify actual NASA product, never mark mock as observed
- period: string; live convention YYYY-MM-DD/YYYY-MM-DD

**RotationScenario**
- id: string; unique in team-produced fixtures
- label: string
- crop_sequence: non-empty array of crop-ID strings (including "fallow" if appropriate)
- supporting_notes: array of strings; evidence must be added before claims are validated

**AnalysisRequest**
- field: FieldInput
- environment: EnvironmentalContext
- scenarios: array of **exactly three** RotationScenario objects in Rust v0.1

**ScenarioAssessment**
- id: string
- label: string
- crop_sequence: string[]
- supporting_notes: string[]
- status: string; **currently always requires_agronomic_validation**

**AnalysisResult**
- field_id: string
- annual_rainfall_mm: number OR null
- mean_of_monthly_temps_c: number OR null
- climate_source: string
- climate_period: string
- scenarios: ScenarioAssessment[]
- warnings: string[]

**EngineError** Rust enum values: InvalidLocation, InvalidMonthlyLength, InvalidClimateValue, InvalidScenarios. The JSON adapter returns a text error, not an HTTP error object.

### Already implemented functions

~~~rust
pub fn analyze_field(request: AnalysisRequest) -> Result<AnalysisResult, EngineError>;
pub fn analyze_field_json(input_json: &str) -> Result<String, String>;
~~~

- analyze_field is PURE; it neither fetches NASA data nor predicts crop suitability.
- analyze_field_json parses JSON, calls analyze_field, and returns serialized JSON.
- annual_rainfall_mm is null if any month is null; otherwise it sums monthly rainfall.
- mean_of_monthly_temps_c is null if any month is null; otherwise the *simple mean of twelve monthly means* (not day-weighted annual mean).
- all three scenarios remain unvalidated until credible requirements and season rules are implemented.
- All climate examples in docs/fixtures are **mock values**, not NASA observations.

### Future internal Rust modules / function names — PROPOSED, not yet implemented

~~~rust
// climate.rs
pub fn summarize_climate(ctx: &EnvironmentalContext) -> ClimateSummary;

// validation.rs
pub fn validate_field(input: &FieldInput) -> Result<(), EngineError>;
pub fn validate_environment(ctx: &EnvironmentalContext) -> Result<(), EngineError>;

// crop_rules.rs — only after agronomic thresholds have cited evidence
pub fn assess_crop(profile: &CropProfile, context: &EnvironmentalContext) -> CropAssessment;

// rotation.rs — only after season/family/water rules are validated
pub fn compare_rotations(/* agreed typed parameters */) -> Vec<ScenarioAssessment>;

// client.rs — networking, separate from pure analysis
pub async fn fetch_environment(/* agreed HTTP client, coordinates, year */) -> Result<EnvironmentalContext, ClientError>;
~~~

Proposed signatures with unspecified types are **design placeholders**, not copy/paste compilable Rust API. Rust owner must finalize these in code with tests and update this contract.

## 5. Server HTTP contract — PROPOSED TO FREEZE FIRST

**Base URL:** configured per environment; NOT hardcoded. Backend developer must announce a working public HTTPS URL and health check.  
**Content type:** application/json; UTF-8.  
**API prefix:** /api/v1.  
**Keys:** keep third-party provider secrets server-side. No NASA POWER/Groq keys committed to GitHub.

### GET /api/v1/health — P0

Response HTTP 200:
~~~json
{"status":"ok","api_version":"v1","data_mode":"mock"}
~~~

- status: ok or degraded
- data_mode: mock or live; do not claim live while serving hard-coded data

### GET /api/v1/environment?lat=16.8&lon=96.15&year=2025 — P0

Response HTTP 200 must be **exactly an EnvironmentalContext-compatible object**:
~~~json
{
  "monthly_rainfall_mm": [10,10,10,10,10,10,10,10,10,10,10,10],
  "monthly_mean_temp_c": [28,28,28,28,28,28,28,28,28,28,28,28],
  "source": "MOCK DATA - NOT NASA",
  "period": "illustrative-2025"
}
~~~

The displayed values above are **dummy fixture values only**. In live mode the backend fetches NASA POWER, aggregates and labels the actual product, and uses an actual period such as 2025-01-01/2025-12-31. The Rust client deserializes the *whole response* as EnvironmentalContext; do not wrap it in a "data" object without agreement.

Required query keys:
- lat: decimal degrees, -90 to 90
- lon: decimal degrees, -180 to 180
- year: four-digit year; use complete historical years for this twelve-month format

### GET /api/v1/crops — P1

Initial catalog response (values illustrative):
~~~json
{
  "crops": [
    {
      "id": "rice",
      "common_name": "Rice",
      "scientific_name": "Oryza sativa",
      "crop_family": "Poaceae",
      "production_systems": ["rainfed_lowland", "irrigated_lowland", "upland"],
      "validation_status": "reference_only",
      "source_refs": []
    }
  ]
}
~~~

The catalog must not imply all production systems have identical water/soil needs. Use null/unknown for unavailable science, never fabricated thresholds.

### GET /api/v1/crops/{id} — P1

~~~json
{
  "id": "rice",
  "common_name": "Rice",
  "scientific_name": "Oryza sativa",
  "crop_family": "Poaceae",
  "production_systems": [
    {
      "id": "rainfed_lowland",
      "requirements": {
        "temp_min_c": null,
        "temp_max_c": null,
        "rainfall_min_mm_per_season": null,
        "rainfall_max_mm_per_season": null,
        "soil_ph_min": null,
        "soil_ph_max": null,
        "min_growing_days": null,
        "max_growing_days": null,
        "drainage": "unknown"
      }
    }
  ],
  "validation_status": "reference_only",
  "source_refs": []
}
~~~

Backend and research must populate source_refs and the thresholds **only when evidence supports them**. These crop endpoint schemas are proposed but NOT in the Rust crate yet.

### Future routes — not part of required integration

- GET /api/v1/forecast?lat=...&lon=... — optional forecast, not NASA historical context.
- POST /api/v1/chat — optional Groq assistant, responds from structured engine results and cited data.
- Farm account endpoints / notifications / field image diagnosis: defer until MVP works.

### Error contract for server endpoints

Use HTTP status 400 for invalid query, 404 for unknown crop, 429 for rate limit, 502/503 for upstream/service failures; include response:
~~~json
{
  "error": {
    "code": "SOURCE_UNAVAILABLE",
    "message": "Environmental data are temporarily unavailable.",
    "retryable": true
  }
}
~~~

Use stable UPPER_SNAKE_CASE codes: INVALID_COORDINATES, INVALID_YEAR, CROP_NOT_FOUND, SOURCE_UNAVAILABLE, RATE_LIMITED, INTERNAL_ERROR. Do not expose tokens, raw upstream stack traces or precise user coordinates in logs.

## 6. NASA POWER ingestion rules — backend owner

Official documentation: https://power.larc.nasa.gov/docs/services/api/temporal/daily/

- Request daily point history with parameters T2M and PRECTOTCORR, community AG and specified dates.
- T2M is air temperature in Celsius. PRECTOTCORR is daily precipitation (millimeters per day) and is **summed over each month's valid daily observations** to get monthly mm.
- Daily T2M is **averaged by month** to monthly_mean_temp_c.
- Detect NASA's missing/sentinel values and convert to null. Never treat -999 as rainfall or replace missing data with zero.
- For v1, a month with incomplete required daily data must be marked null unless the team agrees on a documented coverage policy.
- Store the actual product/dataset and time period in source/period. Archive or cache results responsibly. Do not falsely call historic climate "current weather".
- Live data must be tested against the actual NASA response before the backend marks data_mode=live.

## 7. Flutter ↔ Rust ↔ server: one ownership path

~~~text
Farmer enters field + crop in Flutter
    ↓
Flutter builds FieldInput and selected scenarios
    ↓
Rust network client requests /api/v1/environment (planned)
    ↓
Rust validates / combines: AnalysisRequest
    ↓
Rust analyze_field() returns AnalysisResult
    ↓
Flutter renders climate summary, 3 scenarios, warnings and source
~~~

During initial parallel development, Flutter MAY pass the environmental fixture directly to analyze_field_json (no network) to validate the bridge. This is a **temporary mock integration**, not live NASA behavior.

**Map is separate:** Flutter fetches NASA GIBS imagery tiles directly with source/date attribution; this is display evidence, not the numeric Rust climate input. Official docs: https://nasa-gibs.github.io/gibs-api-docs/

**Bridge naming:**
- Rust source-of-truth: analyze_field_json; wrapper file planned engine/src/api.rs.
- Flutter adapter: app/lib/core/bridge/engine_bridge.dart; recommended Dart method name analyzeFieldJson.
- All generated FRB files belong to the code generator; neither teammate edits them by hand.
- Team must agree on flutter_rust_bridge.yaml and generated API before app uses it. A bridge tested in another local example does not guarantee this repository's Android bridge is ready.
- If server is temporarily unreachable, a mock DEMO must remain visibly labeled mock. Do not silently replace live observations with fixture data.

## 8. End-to-end fixture and test requirements

Reference fixtures in docs/fixtures/ are shared by backend, Rust, and Flutter.

| Test | Owner | Expected result |
|---|---|---|
| Deserialize environment.mock.json | Rust/backend | exact 12-month types; no field renamed |
| Analyze analysis_request.mock.json | Rust | 120 mm annual rainfall, 28 °C monthly mean, 3 unvalidated scenarios |
| Compare analysis_result.mock.json | Flutter | full output rendered incl. warnings/status |
| Bad coordinates and negative rain | Rust | predictable errors; no crash |
| Missing climate month | Rust | corresponding summary null with warning |
| GET /health /environment | Backend | valid JSON and correct HTTP status |
| App→Rust smoke test | Flutter + Rust | one request/response on Windows then Android |
| Live NASA SOURCE vs MOCK flag | Backend/research | visibly different; timestamps/units explained |

Do not promise numeric crop suitability percentages without validated thresholds, data quality or uncertainty handling.

## 9. Git workflow, integration and change management

- main: stable integration branch. Never force-push; require a review where possible.
- One feature branch per task. PRs into main. Existing Rust engine is PR #1 and NOT merged.
- Shared contract modifications must be reviewed by both affected workstreams, announced in the team chat, and accompanied by updated fixtures/tests.
- Every PR states: owner, files changed, what works, how tested, dependencies/blockers and sample output.
- Avoid simultaneous edits to bridge config, root pubspec.yaml, or shared docs without coordination.
- Backend publishes live endpoint, sample curl request and response; Rust verifies deserialization; Flutter verifies display.
- At least one integration checkpoint early in the event before adding optional chatbot, reports, forecasts or alerts.

### Review checklist to ACK before parallel coding

- [ ] Rust lead confirms engine/ and current Rust v0.1 keys / scenario count
- [ ] Backend lead confirms /api/v1 routes and exact environment response object
- [ ] Flutter lead confirms app/ and bridge ownership / output keys
- [ ] Research lead confirms source + license register, evidence requirements and demo deliverable
- [ ] All agree how the server will be deployed and announce one actual base URL
- [ ] All agree on app's primary demo location and crop examples; do not claim unvalidated worldwide advice

## 10. NASA Space Apps submission and attribution

- Required demo: **up to 7 slides** OR **up to 30-second video**, public link with no authentication.
- Submission and linked materials in English; if demo video uses other spoken language, English subtitles.
- Cite at least one NASA resource actually USED and all external datasets/code/assets; preserve third-party code license notices including any OpenFarm BSD-3-Clause reuse.
- Disclose AI/SI use (e.g. Codex, ChatGPT) and mark AI-generated images/videos appropriately. Do not generate or modify NASA branding.
- Select an OSI-compatible repo license before submission; don't put secrets in the repository.
- Avoid photos, audio or video of people younger than 18 in submitted materials.
- Project page must be explicitly submitted, not just saved. Respect local organizer demo cutoff if earlier.

Official NASA participant resources: https://www.spaceappschallenge.org/resources/

## 11. Hand-off messages (copy into team chat)

**Backend → Rust:** "My base URL is [URL]. GET /api/v1/environment?lat=16.8&lon=96.15&year=2025 returns EnvironmentalContext v1; data_mode=[live/mock]. Here's the exact JSON, provider, units, missing-data policy, and dataset period. /health responds 200."

**Rust → Flutter:** "Rust engine function analyze_field_json accepts docs/fixtures/analysis_request.mock.json and returns AnalysisResult fields exactly as in docs/fixtures/analysis_result.mock.json. Bridge setup and Android build status are [status]. The scenario status still means unvalidated."

**Flutter → team:** "The app shows one field, source-labeled environmental result, 3 scenarios and warnings. Screenshot/video link [URL]. Tested on [platform]. Mock/live state [state]."

**Research → team:** "These crop profiles and rotation constraints are supported by [sources], [specific season/production system], with license and citation notes. Unknown fields remain null. Slides [n of 7], public demo link [URL]."

## 12. Contract change log

- **v1.0 / 2026-11-14:** First proposed team-wide naming, ownership, routes and fixtures document. NOT approved/merged yet. Rust contract in PR #1 remains provisional until team integration.
