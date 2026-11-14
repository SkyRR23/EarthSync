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
