# Integration capability matrix

| Capability | Implementation | Current-data reuse / remaining requirements |
|---|---|---|
| Confirmed farm/revision | Existing farm-links; exact revision checked | Shared identity; fresh confirmation remains explicit |
| Daily NASA climate | Server-side bounded jobs, cached immutable evidence | Historical only; current/forecast provider must validate independently |
| Rust reference ET0 | Existing WaterPipeline and native executable | Same calculation; current inputs need accepted lineage and freshness |
| Scenario mechanics | Editable baseline/A/B, crop dates, assumptions, chronology, saved lineage | Shared assessment/comparison storage; no forecast readiness inferred |
| Replay | Year/month/day/range controls; day/week/month playback and speed | Historical archive, not a live feed |
| Comparisons | Selected/custom seasons, two years, 2015–2025 context, coverage-aware baseline | Same summaries/visualization; source data must be independently valid |
| Map | Confirmed polygon, capability-checked dated GIBS, opacity | Display-only; exact acquisition time and quantitative NDVI unavailable |
| Soil | Existing accepted static WebDAV pH snapshot | Version fixed across timeline; dated lab observations separate |
| Crop history | Existing journal periods, declared fallow/bare fields, unknown gaps | Reports remain distinct from hypothetical scenarios |
| Existing strategy comparison | Import baseline/A/B; save new native historical reassessments | Original comparisons preserved; 60 blocked rules stay disabled |
| As-of date | Conservative availability gate; unknown historic publication withheld | Requires genuine publication/availability metadata to admit more records |
| Assistant | Existing deterministic assistant with source-linked historical summaries | No new LLM, model keys or unsupported agricultural advice |
| Offline | Explicit device copy, read-only saved series/results, original timestamps | Service/network failures tested separately from provider availability |
| Desktop/mobile/accessibility | Responsive metric cards, calendar controls, semantic timeline and table | Full assistive-device/native-language agricultural review remains a field-rollout gate |
| Windows/Web packaging | Existing CI packaging/startup workflows reused | Exact-branch CI/interactive acceptance status is recorded in VERIFICATION.md |

No yield forecast, nutrient trajectory, disease prediction, irrigation prescription,
field NDVI, crop-suitability percentage or agricultural approval is implemented.
Those outputs are explicitly unavailable, not simulated with invented equations.
Historical simulation success does not establish current-provider readiness.
