# Baseline errors, exclusions and release blockers

Subject `660b479c3ffb714cd1d489e1241c026ceae6ed67`; production files remain unchanged. No production fix was made to improve a validation result.

## Required gates still open

- Quantitative satellite NDVI/QA pixels unavailable; metadata and true color cannot satisfy the real-vegetation acceptance step.
- No independently held-out matching 0–5 cm soil laboratory observations; pH accuracy cannot be scored.
- No issued-forecast/later-observation matched series; forecast accuracy cannot be scored.
- Weather groups contain only seven days each (<10 predeclared minimum), only two nearby US stations, with unknown assimilation independence. No universal/global weather accuracy conclusion.
- Sagaing public coordinate conflict unresolved; not silently substituted. P1 20 sites, 2025/multi-year, seasonal transitions/extreme events not covered.
- No approved crop-suitability rules; 60 remain blocked. Agricultural local-review, scientific translation review, full accessibility and local interactive Windows acceptance remain release requirements.
- No secure persistent free full-stack hosted deployment verified. No public endpoint was created; no TLS/auth/ownership checks disabled.
- Earlier release evidence documented an intermittent Playwright storage-state restoration confirmation-gate behavior. Real persistent-profile restarts passed then; unresolved cause remains a limitation rather than being concealed by fixture injection.

## Validation-harness diagnostics (not production defects)

Initial harness errors are retained privately: wrong forecast record key (`temperature_k` versus actual `raw_temperature_k`), HTTP-200 HTML misidentified as CSV before strict header checking, local-storage fixture reload order, slash escaping in a Playwright menu selector, Flutter popup animation/viewport scrolling. Corrected probes retain original source bodies/hashes; failed driver runs are not valid observations. Final per-site browser outcomes are in [browser evidence](evidence/browser-sites.json), including any unresolved failures. Chromium screenshots and its non-ignored native accessibility tree confirmed that all three local-review explanations are present. Playwright’s abbreviated aria snapshot omitted the merged named-group label; the final test inspects the native tree instead. This was a test-tool false negative, not a proven production text-omission defect. The production API contract and candidate source were not edited.

## Coverage limits

12 published historical agricultural coordinates are not private active farms. Synthetic field boundaries, plans and reported operations test software only. Myanmar crop references used outside Myanmar retain their original scope and do not establish applicability. Model elevation is not surveyed elevation. Grid resolution and query-cell checks do not validate every polygon pixel. Missing data stay unknown, not zero. No rainfall or ET0 minus rainfall value is an irrigation prescription.

The frozen 2024 January/July windows provide reproducible contrasting seasons but not exhaustive climatic or statistical coverage. No confidence interval, overall accuracy percentage, yield claim, field nutrient diagnosis or guaranteed rotation benefit is supported.
