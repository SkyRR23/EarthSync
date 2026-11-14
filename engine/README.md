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
