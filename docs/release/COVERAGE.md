# NASA Field Shift objective coverage

Statuses apply to the combined candidate, not merely to separate branch tests.
IMPLEMENTED AND VERIFIED requires the actual completed workflow and valid displayed
evidence. PARTIAL means engineering or acceptance remains incomplete.
SCIENTIFICALLY BLOCKED means software works but the agricultural conclusion has
insufficient independently accepted evidence. UNAVAILABLE means required external
observations/providers cannot be obtained or validated. These are independent
limits; an unavailable-state widget does not complete the absent capability.

| Objective | Status and implemented scope | Evidence / remaining limit |
|---|---|---|
| Confirmed field identity and boundaries | IMPLEMENTED AND VERIFIED within tested non-antimeridian geometry scope | Combined 7G browser: draw/edit/undo/confirm/save/reopen, immutable farm revision, approximate area. No supported terrain/hybrid mode is claimed. |
| Local soil information | IMPLEMENTED AND VERIFIED for raw 0–5 cm mean modeled pH | Real accepted SoilGrids WebDAV TIFF/manifest, bounded cells, nodata, units, native 250 m support, source history and overlay. Other soil properties/depths are PARTIAL, not delivered overlays. |
| Soil precision and crop-specific suitability | SCIENTIFICALLY BLOCKED | Regional/model cells are not farm samples. No approved thresholds, field validation or universal good-soil score. |
| Farmer production system, water access, drainage and priorities | IMPLEMENTED AND VERIFIED | Guided optional inputs, explicit unknowns, source labels, farm-bound persistence and deliberate assessment selection; actual UI records and reassessment plus native projection regressions passed. Reports are unverified farmer evidence; regional sources remain reference sidecars. |
| Three rotation strategies including declared baseline | IMPLEMENTED AND VERIFIED | Extended 7X component and actual native assessments support baseline + ≥2 alternatives; no fabricated baseline. Actual combined browser save/reopen passes on desktop and phone; native Rust assessments retain distinct two-crop sequences, immutable groups, baseline confirmation and ownership. |
| Strategy creation/edit/reopen and explanations | IMPLEMENTED AND VERIFIED | Reuses NASA/Rust assessment form, exact per-crop source scopes, reasons, timing findings, missingness, source citations, priority declarations and local-review requirements. Editing saves a new immutable decision. |
| Supported qualitative crop characteristics | IMPLEMENTED AND VERIFIED for existing source-backed taxonomy/use facts | Each projected profile includes identity/use/source claim. Explicit insufficient-evidence states cover nitrogen credit, ground cover, organic matter, roots, erosion, forage, pest-cycle and water-benefit claims where not present/reviewed. |
| Guaranteed agricultural benefits or suitability rankings | SCIENTIFICALLY BLOCKED | All 60 candidates blocked, zero executable recommendations. No yield/profit/success percentages, guaranteed nitrogen savings or disease prevention. Missing agronomic traits are not inferred from species name. |
| Market and practical resource context | IMPLEMENTED AND VERIFIED | Optional market/income, labor, equipment, budget/resources and other declarations are retained and compared. Prices, profits, market access and economic predictions are UNAVAILABLE unless farmer supplied; no economic forecast implemented. |
| Historical NASA climate and Rust reference ET0 | IMPLEMENTED AND VERIFIED | Real provider receipts, original units/periods/hashes, actual native Rust FAO-56 daily calculations. Rainfall and ET0 remain distinct. Partial totals stay unknown; ET0 is not ETc or irrigation demand. |
| Seasonal timeline, chronology and unknown periods | IMPLEMENTED AND VERIFIED | Actual reported crop/fallow/bare periods; unknown gaps are never inferred bare soil; overlaps are explicit, historical readings and Rust ET0 are inspectable. No biological stage inferred from days alone. |
| Environmental snapshots in comparison/timeline | IMPLEMENTED AND VERIFIED | Exact selected 7G soil/forecast jobs saved with decisions; original dates, support/quality and limitations retained. Not promoted into executable agronomic rules. |
| Real vegetation observations and NDVI overlay/time series | PARTIAL software / UNAVAILABLE live observation; mandatory release gate open | Accepted NASA discovery but no authorized/QA-accepted pixels. Earthdata 401 and ORNL MODIS 503 in 7G evidence. No fake NDVI. Engineering display of an unavailable state does not complete quantitative vegetation analysis. |
| Forecast and risk context | PARTIAL | Real GFS sampled 2 m temperature, 0.25° model grid, valid/model times, Celsius conversion and explicit stale/expired handling. Publication timestamp, precipitation and current observed weather unavailable; sparse samples cannot establish daily extremes. |
| Official agricultural warning service | UNAVAILABLE | No accepted official issued alerts. In-app source history, computed indicator distinction, farmer acknowledgment and explicit on-demand refresh are implemented; no all-clear, pest diagnosis, push delivery or invisible scheduler. |
| Farmer history, observations and photos | IMPLEMENTED AND VERIFIED | Farm-owned sanitized photo links, dates, stage/irrigation/management/harvest reports; plans remain separate. Explicit completed-period confirmation controls Rust history projection. |
| Deterministic assistant | IMPLEMENTED AND VERIFIED | Uses saved comparison, selected source context, history/reports, dated soil/forecast explanations, citations and limitations. No LLM/Groq/vector service. English scientific fallback. |
| Burmese and accessible responsive interface | PARTIAL | Core navigation, forms, uncertainty and assistant labels, bundled Myanmar font; English fallback. Phone/desktop widget checks pass. Full native-language agricultural review, every explanatory label and assistive-device testing are not completed. |
| Offline/degraded records and references | IMPLEMENTED AND VERIFIED within explicit cache scope | Actual cold offline browser reopening, public crop-reference cache after API outage, revision-bound read-only snapshots, original source timestamps, device drafts and a hash-versioned static shell; no write replay. No offline fresh provider data, imagery tile packs or background synchronization. |
| Persistence, backup/restore and access boundaries | IMPLEMENTED AND VERIFIED for local single-user scope | Additive migrations and security/persistence regressions pass; final populated-store backup/restore and original/restored HTTP checks passed with exact row/object hashes. Local single-user loopback only, not public multi-tenant auth. |
| Multi-dataset harmonization | PARTIAL | Shared farm revision, selected source IDs, original units/dates/support preserved. No forced resampling or false equal precision; no new harmonization/ML engine. |
| Explicit seasonal-pattern or multi-year climate analysis | PARTIAL / optional | Historical daily values are retained; no new statistically validated multi-year comparison/seasonal vulnerability model or field risk map. Chronological context is implemented, not an inferred vulnerability score. |
| Time-series overlays and scenarios | PARTIAL / optional | Timeline and evidence readings exist. Real NDVI series unavailable. Proposed crop dates are explicitly farmer-declared scenarios, not forecasts. No simulated weather substituted for NASA data. |
| Combined release and hosting | PARTIAL; main unmerged | Combined CI is green at the published source head; final exact-head results are recorded on PR #29. No public deployment. Mandatory real vegetation acceptance and complete weather/warning scope remain unmet; the full release cannot be certified. |

The software supports exploration when science is blocked. That is not permission
to label blocked agricultural conclusions or unfinished engineering as operational.
See [verification](VERIFICATION.md) and machine-readable receipts for precise test
classifications. Synthetic browser records deliberately identify themselves as
software tests, including the farmer-declared baseline; no actual farmer practice
or realistic growing duration is claimed for those test dates.
