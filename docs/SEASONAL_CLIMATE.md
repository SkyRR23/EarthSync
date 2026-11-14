# Seasonal climate analysis — provisional additive API

## Compatibility and scope

Milestone 2 adds `field_shift_engine::seasonal` without changing any existing
public models, error variants, JSON fields or function signatures. The Milestone 1
`analyze_field` and `analyze_field_json` still use their original twelve-month,
unweighted-temperature semantics. The private `climate.rs` is unchanged.
No field results automatically incorporate the new summary yet.

New standalone entrypoints:

```rust,ignore
analyze_season(&SeasonalRequest) -> Result<SeasonalSummary, SeasonalError>
analyze_season_json(&str) -> Result<String, String>
```

These are pure, deterministic computations without network access or extra
dependencies. They do not assess suitability, water availability, drought,
rotation eligibility, yield or climate anomalies. Schema v1 remains provisional
until P2 (backend) and P4 (Flutter) agree. This module does not generate bindings.

## Input data and calendar

`window.start` and `window.end` are inclusive `{ "year": 2023, "month": 11 }`
objects. Supported years are 1–9999; months are 1–12. Gregorian leap years are
multiples of 4 except century years not divisible by 400. November–February is
expressed with different explicit years, never inferred from month numbers.
Years outside that range, reversed windows, invalid months, duplicate dates and
out-of-order records return errors. Records must be strictly chronological;
gaps are allowed. Every supplied record is validated, even outside the selected
window. Valid outside-window records do not affect the summaries.

Each `MonthlyObservation.period` identifies exactly one whole calendar month.
No day fields are accepted; neither partial-month selection nor prorating is
supported. Input JSON structures reject unknown fields to avoid silently ignoring
a day boundary or misspelled completeness flag. Required completeness booleans
have no defaults. Null/absent optional values remain missing, including when a
completeness flag is true. A finite value marked incomplete is not used.

The metadata describes one comparable normalized series: `source`, `dataset`,
`data_kind` (`observed`, `modeled`, `forecast`, `hypothetical`), `rainfall_unit`
(`mm` only), and `temperature_unit` (`deg_c` only). Labels must not be blank.
The same metadata is copied into results. Different kinds are not combined
implicitly. Labels/kind are supplied by the caller, not authenticated or inferred.
The caller must normalize units and guarantee compatible products, aggregation
methods, locations and spatial support. The engine cannot establish that from
strings. Retrieval time, spatial resolution and per-variable source records still
need a coordinated evidence contract before live data integration.

## Formulas and completeness

For a season S made up of full months m:

- Rainfall total (mm): `sum(P_m)`, where each P_m is a complete calendar-month
  accumulation in mm. Rates such as NASA POWER mm/day require upstream,
  product-specific conversion; passing rates as totals is invalid usage.
- Temperature (°C): `sum(d_m * T_m) / sum(d_m)`, where d_m is the Gregorian day
  count and T_m is the complete monthly mean of daily mean temperatures. This
  definition must be justified by the provider's aggregation semantics, not
  merely by a "monthly" label. Daily means need comparable definitions and
  temporal coverage. Do not assert completeness for averages of partial samples.
- No missing-day/month interpolation, annual extrapolation, or partial-season
  statistics are substituted. If aggregation semantics are uncertain, set
  `temperature_complete` false; the seasonal temperature is unknown.

Completeness is evaluated independently per variable. An absent record, null value
or false completeness flag adds that month to its variable's ordered gap list.
Any gap produces `null` for that entire variable's seasonal summary, rather than
zero or a mean over available months. `month_count` and `calendar_days` describe
the requested window even when observations are missing. Limitations explicitly
state the reliance on upstream completeness and comparability.

All supplied rainfall must be finite and nonnegative; supplied temperatures must
be finite. Negative Celsius and zero rainfall are valid numeric inputs. No
uncited physical/agronomic cutoffs are imposed. Invalid supplied values are errors
even when another month is missing or their completeness flag is false.

The nonnegative rainfall running sum is checked for overflow after each included
value. Overflow is an error even if another selected month is missing, never
JSON null. Incomplete records are not accumulated. Temperature weighting first
normalizes by the largest absolute selected temperature, sums normalized
value × days, divides by season days, and restores the scale. A final clamp to
[-1,1] handles normalized convex-mean roundoff only, not scientific thresholds.
Zero scale returns zero. Final numeric results must be finite. Floating-point
roundoff remains; consumers/tests should use suitable tolerances for arithmetic
comparisons. Standard serde_json accepts only finite JSON numeric inputs; use
`analyze_season_json` for validated output rather than serializing unchecked Rust
input structs containing NaN/infinity.

## Synthetic example and verification

`engine/tests/fixtures/synthetic_season.json` is explicitly hypothetical test
input, not NASA measurements or a Myanmar agricultural reference. Its November
2023–February 2024 monthly rainfall totals are 10, 20, 30, 40 mm; temperatures
are 10, 20, 30, 40 °C. The expected rainfall is 100 mm, calendar length 121 days,
and temperature `(30*10 + 31*20 + 31*30 + 29*40)/121 = 3010/121 °C`.
These numbers exercise weighting; they are not a local climate characterization.

From `engine/` run:

```sh
cargo fmt --check
cargo test --locked
cargo clippy --all-targets --locked -- -D warnings
git diff --check
```

Tests cover complete/subset seasons, leap/nonleap cross-year windows, Gregorian
centuries, calendar limits, missing/incomplete data, independent completeness,
invalid/nonfinite values, rainfall overflow, stable extreme temperature means,
ordering/duplicates, explicit units, partial-month rejection and JSON round trips.
The original twelve tests remain regression checks for the unchanged field API.

## Questions for P2 and P4 before integration

1. Does the backend supply monthly rainfall accumulations or mean daily rates?
   Which exact product and unit conversion will normalize them?
2. How are monthly temperatures aggregated, and what evidence justifies each
   completeness flag (including modeled or forecast products)?
3. How will per-variable provider/product, retrieval dates, spatial scale, data
   kind and quality travel with the normalized records? This minimal metadata
   must not become an excuse to discard provenance from a real backend response.
4. Do both owners accept inclusive calendar months, strict record ordering,
   separate gap lists, and unknown summaries? Daily/partial-month analysis needs
   a different data contract and method.
5. Should Flutter call this separate API directly or receive seasonal summaries
   in a later versioned analysis result? Keep the existing result unchanged
   until an additive integration contract and bridge mapping are approved.
