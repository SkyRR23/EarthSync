# Field Shift Rust engine

Minimal on-device calculation foundation. It is intentionally independent of the server, Flutter and unverified crop rules so the team can develop in parallel.

## Run

```powershell
cd engine
cargo fmt --check
cargo test
cargo clippy -- -D warnings
```

The engine currently validates inputs, summarizes complete monthly rainfall and temperature values, and returns three scenario placeholders clearly labeled as not yet validated. **It is not an agronomic recommendation engine yet.**

See [the provisional JSON contract](../docs/ENGINE_CONTRACT.md).

## Integration plan

1. Data team agrees on `EnvironmentalContext` fields, sources and units.
2. Crop reference and rules are reviewed for agricultural validity.
3. Core engine adds crop eligibility and risk modules with tests.
4. Flutter developer and engine owner integrate `flutter_rust_bridge` v2, matching the team's app configuration.
5. Run Android ARM64 compilation and device tests. The Windows bridge proof-of-concept does not prove Android works.

## Third-party licenses

The project must select an OSI-compatible license and record external data, libraries and adapted OpenFarm code before submission. This initial crate does not include OpenFarm code.

## Reproducible foundation checks

Rust 1.85.1 with rustfmt and Clippy was used for this foundation increment
(edition 2024). Keep `Cargo.lock`; use `cargo test --locked` for repeatable builds.
The public JSON tests load `tests/fixtures/synthetic_field.json`: all observations
and rotation sequences there are explicitly synthetic, not recommendations.
See [inspection and next steps](../docs/ENGINE_KICKOFF.md) and
[OpenFarm research](../docs/OPENFARM_RESEARCH.md).

## Seasonal statistics (Milestone 2)

The separate `seasonal` module supports inclusive full-month windows across years,
independent missingness and calendar-day weighting of declared complete monthly
means. It does not change the existing field-analysis JSON. See
[the seasonal contract](../docs/SEASONAL_CLIMATE.md) and the explicitly hypothetical
`tests/fixtures/synthetic_season.json`. No network or extra dependencies required.

## Crop/rotation foundation (Milestone 3A)

The separate `decision` module evaluates supplied categorical constraints and
returns source-linked support/conflict/unknown findings. Whole rotations remain
unvalidated pending sourced transition rules; no recommendations or scores are
implemented. See [the foundation contract](../docs/CROP_ROTATION_FOUNDATION.md)
and [PR #2 reconciliation](../docs/TEAM_CONTRACT_REVIEW.md). The
`tests/fixtures/synthetic_rotations.json` records are fictional test data only.

## Integration adapter (Milestone 3B)

`integration::analyze_integration_json` runs the existing seasonal and crop/rotation
functions together and returns a structured success/error envelope. Try the
explicitly synthetic `tests/fixtures/synthetic_integration_request.json` via
`cargo test --locked --test integration`. See
[the proposed integration design](../docs/INTEGRATION_READINESS.md). Existing APIs
remain available; real backend/Flutter/FRB configuration is still required.

## v0.2 P0 (opt-in, provisional)

The separate `v02` module preserves independent soil records and history, checks
reviewed/applicable daily crop duration and sequential schedules, and retains
existing integration output. It is not a production crop recommendation system.
See [the v0.2 contract](../docs/ENGINE_CONTRACT_v0.2.md). Run the explicitly synthetic
workflow with `cargo run --locked --example v02_demo`; no network required.
