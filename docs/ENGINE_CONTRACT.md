# Field Shift Engine Contract — v0.1

**Status:** provisional, for parallel development. Owners must agree before integration.

## Architecture

- Server/backend owns NASA observations, data-source provenance, curated crops and soil estimates.
- Rust engine runs on the user's device, combines server context with farmer inputs and produces deterministic analysis.
- Flutter owns the farm forms, map and display of results. Bridge code will be agreed with the Flutter developer.
- Satellite imagery remains a map-tile service; the engine does not download raw image archives.

## Engine entrypoints

- `analyze_field(request: AnalysisRequest) -> Result<AnalysisResult, EngineError>`: pure computation, no network access.
- `analyze_field_json(input_json: &str) -> Result<String, String>`: development adapter for testing the JSON contract.

## Initial input structure

```json
{
  "field": {
    "field_id": "demo-field",
    "latitude": 16.8,
    "longitude": 96.15,
    "current_crop": "rice",
    "irrigation_available": null
  },
  "environment": {
    "monthly_rainfall_mm": [10,10,10,10,10,10,10,10,10,10,10,10],
    "monthly_mean_temp_c": [28,28,28,28,28,28,28,28,28,28,28,28],
    "source": "MOCK DATA — NOT NASA",
    "period": "illustrative"
  },
  "scenarios": [
    {"id":"current","label":"Existing rotation","crop_sequence":["rice","fallow"],"supporting_notes":[]},
    {"id":"alternative-a","label":"Alternative A","crop_sequence":["rice","candidate-a"],"supporting_notes":[]},
    {"id":"alternative-b","label":"Alternative B","crop_sequence":["rice","candidate-b"],"supporting_notes":[]}
  ]
}
```

**IMPORTANT:** All crop names, climate values and sequences above are illustrative mock data, not validated Myanmar rotation recommendations.

## Computation rules in v0.1

- Require 12 calendar-month values for rainfall and temperature; missing values are `null`.
- Sum monthly rainfall only when all 12 months are present.
- Compute the unweighted mean of 12 monthly mean temperatures only when complete.
- Reject invalid coordinates, negative rainfall, nonfinite numbers, or a scenario list other than 3.
- Preserve source and period labels. Every crop scenario is marked `requires_agronomic_validation`.
- Never claim to predict yield, identify crop diseases, or prove suitability from this provisional contract.

## Next contracts to agree

1. API response units, start/end date, dataset identifiers, spatial resolution, missing-data handling.
2. Crop requirements and provenance, growing windows, soil constraints and evidence IDs.
3. Rust ↔ Flutter bridge data shape and error display.
4. Optional cache, authentication and privacy arrangements.

## Ownership

- Core engine: Rust calculation, validation, integration.
- Data/backend: API and evidence-backed dataset normalization.
- Application: Flutter UX, map and results.
- Design/presentation: wireframes, licenses, research citations and submission.

## Foundation validation update (backward-compatible JSON shape)

The input and output fields above are unchanged. Monthly rainfall totals that
cannot be represented as finite `f64` now return `InvalidClimateValue`, including
through the JSON adapter, rather than serializing infinity as misleading `null`.
Temperature means normalize before summation to avoid intermediate overflow.
Floating-point roundoff remains possible; this is not a day-weighted mean.
`null` summaries mean incomplete observations, never a numeric overflow fallback.
This numerical guard does not establish physically plausible climate ranges.

A runnable offline example is `engine/tests/fixtures/synthetic_field.json`, tested
through the public JSON adapter. It contains **synthetic, unmeasured values**, not
NASA observations, crop reference data, or validated Myanmar recommendations.
Expected rainfall is 1700 mm and the unweighted temperature mean is 334/12 °C.
All three scenarios remain `requires_agronomic_validation`.

### Integration gaps requiring owner agreement before schema v1

- `current_crop` is required as a string; nullable unknown crop/history, management,
  season, drainage and priorities still need a coordinated model update.
- `source` and `period` are free-text labels, not adequate provenance. Agree on
  per-variable provider/product, units, date interval, retrieved time, spatial
  scale, observed/modeled/forecast/hypothetical kind and missingness. Do not feed
  POWER precipitation rates into monthly totals without explicit conversion.
- Exactly three scenarios are accepted; primary plan allows three or more.
  There is no baseline marker or uniqueness validation for IDs yet.
- Status and error strings are provisional; Flutter must display unknown/error
  states rather than treating them as suitability or low risk. Plain supporting
  notes are unverified input, not engine-generated evidence.
- No historical baseline comparisons, water adequacy, crop constraints or risks
  can be inferred from these summaries. Calendar-year arrays cannot express
  cross-year seasons. Define date-aware windows before seasonal comparisons.
- `cdylib` alone does not expose a callable Flutter bridge. No bindings, Android
  build or Windows integration are verified. Generate v2 bindings only against
  P4's actual app. Networking belongs in a separate adapter, outside pure analysis.

## Milestone 2: separate seasonal API (provisional)

`seasonal::analyze_season(&SeasonalRequest)` and
`seasonal::analyze_season_json(&str)` add dated, full-month window statistics.
Existing field-analysis types, signatures and JSON remain unchanged, including
its unweighted annual temperature summary. See [seasonal formulas, data contract
and integration questions](SEASONAL_CLIMATE.md) before using the new API.
Seasonal data include explicit units, inclusive year/month periods, declared
completeness, source labels and data kind. No new agricultural decisions are made.

## Milestone 3A: separate crop/rotation foundation (provisional)

`decision::compare_rotations(&DecisionRequest)` and
`decision::compare_rotations_json(&str)` introduce typed, source-linked categorical
checks without changing existing field or seasonal APIs. Step support means only
support for implemented supplied constraints; whole rotations remain insufficient
without transition rules unless a supplied constraint conflicts. See
[CROP_ROTATION_FOUNDATION.md](CROP_ROTATION_FOUNDATION.md) and the proposed PR #2
[contract review](TEAM_CONTRACT_REVIEW.md). No scientific crop values are built in.

## Milestone 3B: provisional integration adapter

`integration::analyze_integration(&IntegrationRequest)` composes existing seasonal
and decision functions. `integration::analyze_integration_json(&str)` returns a
new success/error envelope; it does not replace earlier JSON adapters. See
[INTEGRATION_READINESS.md](INTEGRATION_READINESS.md) for input/output, provenance,
completeness, error semantics, proposed FRB v2 boundary and unresolved P2/P4 decisions.
This adds no crop scoring, network calls, generated bindings or finalized schema.

## v0.2 P0 proposal

The opt-in `v02::analyze_v02` / `v02::analyze_v02_json` boundary adds independent
soil/history attribution and applicability-gated daily scheduling. Existing types,
functions and response fields remain unchanged. See
[ENGINE_CONTRACT_v0.2.md](ENGINE_CONTRACT_v0.2.md) for exact models, status meanings,
actual Flutter bridge gaps, test fixtures and unapproved P2/P4 integration decisions.
