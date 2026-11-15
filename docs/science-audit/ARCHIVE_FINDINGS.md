# Contributed historical findings

Archive identity is the verified SHA-256 in [README](README.md). These findings
concern contributed `fieldshift-engine` 0.1.0 and its data, not the modern
`field_shift_engine` v0.3 contract. Package versions do not identify a Git commit.

Severity describes potential scientific impact if adopted. No original was
silently repaired and no precompiled executable was trusted. Do not import the
old engine or ranking system into v0.3.

| ID | Severity | Confirmed defect | Reproduction/effect | Disposition |
| --- | --- | --- | --- | --- |
| H01 | High | Climatology collector slices CSV as if a year column existed | All 360 rows have wrong ordinals: FEB is 1, ANN is 12, JAN absent | Reject flattened climatology; lost January cannot be fabricated. Separate JSON builder correctly skips annual month 13. |
| H02 | Medium | Date-count claims | POWER "120 days" has 121 inclusive rows; ERA5 "365 days" has 364 | Count actual dates and valid values independently. |
| H03 | High | Builder labels MERRA-2 `observed` | Three generated contexts and copied analysis status confuse modeled/observed | Research estimates labeled modeled; modern adapters already correct. |
| H04 | High | Builder averages available samples; `missing_months=0` hard-coded | Remove `201601`: January still 9.7 mm from nine samples, fill count zero | New research normal validator returns null and missing keys for incomplete coverage. |
| H05 | Medium | Fixed 28.25-day February, no original unit/statistic validation | Exact calendar/window totals can differ; changed units still accepted | Multiply each year-month rate by its actual calendar days before averaging; reject unit changes. |
| H06 | High | Context/farm association and numeric/month domains unchecked | Different-continent farm/Hlegu context, month 13 replacing December, negative rain all accepted | Three historical regressions fail; current validation is separate. J01/J05/J06 repair distinct modern boundaries. |
| H07 | Medium | Public annual aggregation sums any nonempty slice | January alone returns 12.4 mm as annual precipitation | Historical regression fails; no reuse. |
| H08 | High | Monthly T2M_MAX/MIN treated as mean daily extrema and used for Hargreaves/crop checks | NASA identifies extrema separately from `_AVG`; ECOCROP bounds lack executable temporal/stage applicability | Quarantine unsupported transformations; modern v0.3 uses daily Tmin/Tmax. |
| H09 | High | Medium confidence and numeric completeness counted sourced; unverified warning does not block eligibility | Six profiles have empty `unverified` despite team water/duration claims; explicitly unverified crop still Supported | Historical regression fails. All new profiles remain in non-executable quarantine. |
| H10 | High | Irrigation enum adds fixed 120/350 mm; team water threshold | Zero-rain case still Supported without delivered volume or water balance | Historical regression fails; current availability is not sufficiency. |
| H11 | High | Rotation deduplication loses repetitions and reverses | Rice/black-gram/rice becomes rice/black-gram; A+B and B+A treated as one idea | Historical regression fails. Modern supplied order/dates retained. |
| H12 | High | N, pest, cover and income use unsupported proxies and uncalibrated weights/ranks | Missing legume N gets 0.6; two use labels yield income 2/3; family diversity implies pest benefit | N/income regressions fail. No quantified benefit or weighted engine imported. Income score is not a real currency/profit estimate. |
| H13 | High | Fixture/source warnings do not gate support/ranking | Context `fixture` still yields Supported crop findings | Historical regression fails. Current synthetic evidence is labeled and gated. |
| H14 | High | Five-year comparison actually passes full-window `monthly` against `prior_monthly` | Hlegu 268.7 mm reported instead of 537.2 mm recent-half minus prior-half | Historical regression fails; existing `recent_monthly` not used by the API call. |
| H15 | High | Cache clears incompatible planting month for every crop, including baseline | Black gram requested in June evaluated using crop default, no WINDOW_MISMATCH | Historical regression fails. Modern explicit plan dates retained. |
| H16 | Medium | Build time used as fetch time; citations/scope incomplete | Raw bodies/URLs have no original fetch receipts; CURATED ID conflates multiple crop URLs; team values lack per-parameter evidence | Retain original metadata, mark retrieval time unknown, never authenticate from build timestamp. |
| H17 | High | Product-instability cause and era homogeneity asserted from rainfall differences alone | Current provider repeat matches all 390 Hlegu 1991–2020 values, but this does not prove the cause or validate a chosen era | Numeric repeat recorded; causal artifact/trend claims remain unverified pending independent/product/homogeneity evidence. |

Soil/WMS uncertainty, missing MODIS QA, universal LST fill handling, CMR exclusion
of Magway, forecast identity gaps and unsupported anomaly messages retain the
PR #11 findings: the collector, all 46 environmental CSVs, fetch log and 12 JPEGs
are byte-identical. New crop/raw/source artifacts were reviewed independently.

## Reproducing the historical engine safely

All 14 Rust files, manifest, lockfile, CLI, tests and registry configuration were
read. A new `/tmp/earthsync-contributed-source-build` received only inspected
source/contracts, excluding `target/` and the registry override. Rust 1.99 and
cached locked dependencies compiled it offline. Only fresh executables were run.
The collector and builder main were never run; original files were not changed.

Original suite: **13 passed**. New tests in
`tools/science_audit/historical_regressions.rs`, copied into the isolated tree
as `engine/tests/audit_regressions.rs`: **12 failed as expected**. See
[full output](evidence/historical-regressions.txt). These intentional failures
are outside the modern suite and are not reported as passing tests.

```sh
cargo test --locked --offline --manifest-path CLEAN_SOURCE_TREE/engine/Cargo.toml --test engine_tests
cargo test --locked --offline --manifest-path CLEAN_SOURCE_TREE/engine/Cargo.toml --test audit_regressions
```

The reviewed builder's pure normal/profile functions were called for two offline
reproductions only: one absent month still produced a normal, and six populated
medium-confidence profiles were counted sourced. [Receipt](evidence/builder-reproduction.json).
No collector/network action or write into the original tree occurred. All 113
non-build extracted originals were subsequently hash-checked unchanged.

Repair is through strict source/calendar validation and quarantine, preserving
the historical reproducer. Deploying another weighted engine would violate the
scientific acceptance and 7N integration boundaries.
