# Engine v0.2 — first P0 increment, PROPOSED

No shared schema is finalized by this document. P2/P4 must review the new boundary
before integration. Existing Rust structs, function signatures and JSON behavior
remain unchanged, including all 56 existing tests. The crate package version stays
0.1.0; `0.2-provisional` labels the opt-in payload, not a released production crate.

## Inspection and contract risks

Started `feat/rust-engine-v0-2` from latest main
`1ea3df7b09637cf8162f834411d830aa8621590c` (Milestone 3B merged). Inspected the actual
engine and tests, the proposed PR #2 contract at `b30cae1`, and Flutter branch
`feature/flutter-app` at `f25e5cf`. No backend branch/implementation was advertised.
The app is now real; earlier docs describing its absence are historical records.

Flutter `app/rust/Cargo.toml` references `../../engine` and pins FRB `=2.13.0`.
`app/flutter_rust_bridge.yaml` uses `crate::api`, `rust/`, `lib/src/rust`. The bridge
has an owned-string passthrough to the existing integration function plus a
synthetic-demo builder. The Dart `RustEngine.analyzeField` forwards only current
crop, irrigation and drainage to the demo builder. Coordinates/environment remain
the embedded synthetic fixture; recent rotation, planting month and priorities are
not sent. `partial` and `full` irrigation both become true; adequacy is not known.
The actual envelope decoder groups forecast/modeled evidence together, casts
nullable step crop IDs to strings, and sorts baseline first, losing engine order.
These are P4 coordination issues, not authorization to edit app files here.

PR #2 is proposed/unmerged: its 12-month environmental arrays lack dated multi-year
metadata; crop endpoints have no accepted per-constraint applicability mapping.
Retain those legacy APIs; do not deserialize the proposed payload into v0.2 by
renaming keys or inferring missing values. Python upstream normalization is P2's
responsibility; all analysis here is HTTP-free Rust.

## Implemented scope and entrypoints

```rust,ignore
v02::analyze_v02(&AnalysisRequestV02)
    -> Result<AnalysisResultV02, AnalysisErrorV02>
v02::analyze_v02_json(&str) -> String
```

The engine reuses `integration::analyze_integration` (which calls seasonal and
categorical decision functions), then validates new contexts and performs daily
schedule/duration checks. `analyze_field`, `analyze_field_json`, `analyze_season`,
`compare_rotations`, `analyze_integration_json` and their struct-literal users are
unchanged. The new module adds no dependencies or bindings.

This P0 increment adds soil/history attribution, physical/unit validation,
explicit applicability for existing categorical rules, daily duration feasibility
and single-field sequential conflicts. It does **not** implement numeric crop
pH/temperature/moisture/water thresholds, crop-stage water budgets, succession
restrictions, forecasts/alerts, photo ML, optimization, ranking or beneficial
legume effects. No real crop-reference records are bundled.

## Exact request structure

All new input structs use snake_case and reject unknown fields. Scalars listed
with `?` are Option fields and accept null/absence. Arrays and booleans without
`?` are required: empty arrays explicitly provide no records; booleans have no
default inference. Existing nested legacy types retain their original parsing.

| Type | Fields (Rust types; `?` means Option) |
| --- | --- |
| `AnalysisRequestV02` | `integration: IntegrationRequest`, `region_id: String?`, `farmer_intent: FarmerIntent`, `soil_context: SoilContext`, `history: FarmHistory`, `sequential_only: bool`, `plans: Vec<StepPlan>`, `duration_rules: Vec<DurationRule>`, `profile_applicability: Vec<ProfileApplicability>`, `environmental_provenance: Provenance?` |
| `Date` | `year: u16`, `month: u8`, `day: u8`; Gregorian dates, years 1–9999 |
| `Provenance` | `kind: EvidenceKind`, `source_refs: Vec<String>`, `provider: String?`, `dataset: String?`, `observed_on: Date?`, `retrieved_on: Date?`, `spatial_resolution_m: f64?`, `uncertainty: String?` |
| `Observation<T>` | `id: String`, `value: T?`, `provenance: Provenance` |
| `SoilContext` | `texture: Vec<Observation<SoilTexture>>`, `drainage: Vec<Observation<Drainage>>`, `ph: Vec<Observation<f64>>`, `organic_carbon_g_kg: Vec<Observation<f64>>`, `moisture: Vec<SoilMoisture>`, `surface_condition: Vec<Observation<SurfaceCondition>>` |
| `SoilMoisture` | `observation: Observation<f64>`, `unit: MoistureUnit`, `zone: MoistureZone?`, `depth_cm: DepthCm?` |
| `DepthCm` | `top: f64`, `bottom: f64` |
| `FarmHistory` | `complete: bool`, `cycles: Vec<HistoryCycle>` |
| `HistoryCycle` | `id: String`, `fallow: bool?`, `crop_id: String?`, `crop_family: String?`, `production_system: ProductionSystem?`, `planting_date: Date?`, `harvest_date: Date?`, `irrigation_available: bool?`, `amendments: Vec<String>?`, `provenance: Provenance` |
| `FarmerIntent` | `current_crop: String?`, `recent_rotation: Vec<String>`, `planting_month: u8?`, `priorities: Vec<String>` |
| `StepPlan` | `scenario_id: String`, `step_index: usize` (zero-based), `season: SeasonContext` |
| `SeasonContext` | `planned_planting_date: Date?`, `planned_harvest_date: Date?`, `regional_label: String?`, `season_start: Date?`, `season_end: Date?`, `available_growing_days: u32?`, `provenance: Provenance` |
| `Applicability` | `region_id: String`, `production_system: ProductionSystem`, `reviewed_for_context: bool` |
| `ProfileApplicability` | `profile_id: String`, `applicability: Applicability` |
| `DurationRule` | `profile_id: String`, `min_days: u32?`, `max_days: u32?`, `applicability: Applicability`, `source_refs: Vec<String>` |

Enums serialize as snake_case. `EvidenceKind`: observed, modeled, forecast,
hypothetical, farmer_reported, unavailable. `SurfaceCondition`: standing_water,
wet, dry, other. `MoistureUnit`: volumetric_fraction, volumetric_percent.
`MoistureZone`: surface, root_zone. Existing production/texture/drainage/evidence
status enums are unchanged. All source IDs reference the existing registry in
`integration.crop_references.sources`, including context-only sources.

`integration` keeps its exact existing fields and is returned unchanged in the
nested result. Nullable `farmer_intent.current_crop` preserves questionnaire
unknowns; when present it must equal legacy `integration.field.current_crop`.
Do not invent a current crop to fill the required legacy string: agree its null
mapping with P4 first. Recent crop-ID strings are not promoted into dated history.
Priorities are retained presentation inputs, never weights or conflict overrides.

## Units, validation and provenance

Dates are calendar days, not UTC instants; P2 must agree local-date semantics and
future timestamp precision. All known dates validate before arithmetic. Observation
IDs, history IDs and step-plan links must be unique; missing source IDs or unknown
scenario/step/profile references are errors. Retrieved date cannot precede the
record's observation date. Resolution must be finite positive meters or null;
uncertainty is retained text, not a calibrated confidence score.

pH values must be finite or null; no crop pH threshold or universal chemical range
is assumed. Organic carbon is g/kg, physically constrained to 0–1000 or null.
Moisture fraction is 0–1 or percent 0–100, with no unit conversion. Depth is a finite
nonnegative top and strictly greater bottom in cm. Missing unit/measurement support
is not inferred; zone/depth/date can remain explicitly unknown. `unavailable`
observations must have null values. Surface wet/dry/standing-water observations
remain separate from modeled moisture. SoilGrids/SMAP can be attributed through
provider/dataset/depth/scale metadata, but no provider fetch or field validation
is implemented. GIBS imagery is never a soil measurement.

Soil records are independently preserved, not averaged or fused. Modeled/coarse
support and uncertainty remain visible in context. No arbitrary resolution cutoff
claims field precision. Conflicting categorical records (including disagreement
with the legacy selected soil value) produce conditional/needs-review tradeoffs
and suppress a v0.2 soil incompatibility claim; they do not suppress an independent
irrigation or duration conflict. Empty/unknown soil remains unknown. Numeric soil
records are retained and validated, not evaluated against crop bounds yet.

Environmental monthly units/dates/nulls/completeness and observed/modeled/forecast/
hypothetical kind remain in the existing integration request/result. Optional extra
provenance must agree with that kind; no dataset merging, rate-to-total conversion,
completeness inference or historical-to-forecast reinterpretation. Extended
provenance is still series-level; per-variable timestamps, uncertainty intervals
and mixed-product evidence need a later approved contract.

History may contain multiple crop and explicit fallow cycles; completeness is a
caller assertion, not inferred. Reversed known planting/harvest dates are invalid.
Fallow cannot also identify a grown crop/family/system. Input cycle order and all
unknowns are preserved. Family/history records generate context, not pest or soil
benefits. History-to-plan conflicts and sourced succession restrictions are deferred;
this increment only checks plan-to-plan sequential scheduling.

## Applicability and daily schedule formulas

A source citation does not establish applicability. Existing categorical conflicts
become v0.2 critical incompatibilities only with an explicit reviewed profile scope
matching request region and selected production system and trusted finding sources.
Duration rules additionally require matching selected crop/profile identity and
a matching system/region, plus trusted rule AND schedule references. Review flags
and matching region IDs are caller assertions: P2 must review their association
with the actual farm and evidence, not simply set booleans to force support.

Trusted means every cited source is `verified_for_supplied_context`; test mechanics
may use `synthetic_test` only when `data_mode` is `synthetic_demo`. Reference-only,
uncited or inapplicable rules cannot produce v0.2 positive or negative constraints.
Raw legacy findings remain nested for compatibility; Flutter must use the new
v0.2 assessments for the new semantics rather than treating legacy findings as
an approved v0.2 verdict. Synthetic records are explicitly labeled throughout.

All durations use **inclusive calendar days**: `harvest - planting + 1`.
Available capacity is an explicit `available_growing_days` and/or inclusive
`season_end - planned_planting_date + 1`, using the smaller bound when both are
supplied. No capacity is inferred from an end date before planting. An applicable
minimum conflicts only if known capacity or explicitly planned crop duration is
shorter. An applicable maximum conflicts only with known planned crop duration,
not a long available season (the farmer may harvest earlier). Null bounds or
unknown schedules produce unknown checks, not a negative classification. At most
one duration rule/profile is accepted until evidence-selection policy is agreed.

Daily planting must match the legacy selected step's start year/month when that
monthly window is known; conflicting input is an error, not silently rewritten.
No daily harvest or season boundary is inferred from the legacy monthly window;
the new daily fields must supply them. Available days must be positive, not
necessarily the entire calendar season.
Season bounds and crop planned dates must each be ordered. Reviewed schedules
can flag planting outside the supplied season or harvest after its end. When
`sequential_only` is true, every selected step has a trusted plan, and relevant
crop dates are known, the next planting must be strictly AFTER previous harvest.
Overlaps and reversed sequence timing conflict. Without that declaration/review
or dates, scheduling remains unknown; intercropping is not implicitly prohibited.
No crop-duration constants, calendars or agricultural thresholds are built in.

## Output, status meanings and compatibility

Success/error envelope stays `{"status":"success","data":...}` or
`{"status":"error","error":{code,message,component,detail,retryable}}` only on
`analyze_v02_json`; the old JSON adapter is unchanged. Errors preserve existing
integration codes or add `INVALID_CONTEXT`, `INVALID_JSON`, `SERIALIZATION_FAILED`.
Validation errors are nonretryable local input errors; no raw JSON is echoed.

`AnalysisResultV02`: `schema_version`, `integration: IntegrationResult`,
`context: AnalysisRequestV02`, `scenarios: Vec<ScenarioAssessmentV02>`,
`limitations: Vec<String>`. The full context is retained for source lookup and
inspection, not uploaded/logged by the library. No external persistence added.

`ScenarioAssessmentV02`: `scenario_id`, `is_baseline`, `status`,
`legacy_eligibility`, `critical_constraints`, `tradeoffs`. Scenario/step ordering
and explicit baseline are preserved. No rankings. Each factor has `factor_id`,
`status`, `explanation`, `evidence: Vec<String>`, `source_refs`, `limitations`,
`missing_information` (all remaining lists are Vec<String>).

| Factor status | Exact meaning | Legacy eligibility mapping |
| --- | --- | --- |
| supported | Only the explicitly evaluated supplied bound/categorical or schedule check passed; not crop suitability | supported_by_supplied_evidence |
| conditional | Conflicting soil records require resolution; no measurement synthesized | insufficient_information |
| unsuitable | An applicable/trusted critical constraint or declared sequential schedule conflicts | conflicts_with_supplied_evidence |
| unknown | Inputs, applicability, references or implemented rules insufficient | insufficient_information |
| requires_agronomic_validation | Whole scenario still lacks a complete scientific assessment | insufficient_information |

Whole scenarios in this increment emit only unsuitable (any critical unsuitable)
or requires_agronomic_validation. Favorable unrelated factors/priorities never
override a critical conflict. Soil conditional findings cannot manufacture a
supported scenario. No probabilities, weighted averages or arbitrary scores.

## Fixtures, checks and remaining gates

`engine/tests/fixtures/synthetic_v02_request.json` and
`synthetic_v02_response.json` are explicitly synthetic software-test mechanics,
not NASA data, Myanmar thresholds or recommendations. The fictional minimum/maximum
durations exist only in these test records. `cargo run --locked --example v02_demo`
reproduces the response. JSON tests verify the deterministic response fixture and
that legacy envelopes/structs remain unchanged. All calculations are offline.

Test with the repository CI's Rust 1.99.0, from `engine/`:

```sh
cargo fmt --check
cargo test --locked
cargo clippy --all-targets --locked -- -D warnings
git diff --check
```

P2/P4 approval gates:

1. P4 forwards actual selected coordinates to both field and environment query,
   nullable crop/history, planting month, irrigation precision, drainage and
   priorities. Do not let synthetic fixture coordinates become the selected field.
2. P4 adds an explicitly versioned wrapper/decoder after agreeing this boundary;
   reuse actual FRB 2.13.0 configuration and regenerate in P4's branch. Existing
   decoder expects legacy data keys, non-null step IDs and baseline-first order;
   it must not silently parse the new nested v0.2 data as old data. No app edits here.
3. P2 provides Python normalization/endpoints, real metadata, verified Myanmar
   constraints, applicability reviews and source/license/version records. Agree
   exact unit/observation-period semantics before adding temperature or water rules.
4. Team approves inclusive duration counts, available-day meaning, local calendar
   dates, sequential/intercrop declaration, regional identity mapping, explicit
   rule selection and synthetic-only test status handling.
5. Future work: trusted temperature extremes versus seasonal means, stage-specific
   water requirements/availability, pH/drainage context resolution, history-based
   restrictions and forecast issue/validity instants. These are unknown here, not
   passed checks. No verified risk calculation, weather alerts or forecast-fetch
   model is implemented. Missing forecasts never block existing climate analysis.

Stop after this P0 increment. The data models/API are a proposal; no agronomic or
production-readiness claim, Windows/device test claim or backend deployment claim.
