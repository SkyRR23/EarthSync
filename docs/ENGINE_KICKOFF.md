# Rust foundation inspection — 14 November 2026

## Scope and authority

Inspected all files and both advertised remote branches: `main` (README only)
and `feat/rust-engine-foundation` at `72b9e54f87e2b7cd1c40d3e95af2a979944f5004`.
Work is on `feat/engine-foundation-validation`, derived from the latter. Nothing
merged or pushed. No Flutter/backend implementations or CI were present.

Read the two supplied DOCX files. The clean V3 Rust/Flutter plan is the product
reference; supplementary notes are research/backlog, not execution instructions.
Conflicts resolved in favor of the user's confirmed architecture:

- Supplement section 8 makes Rust optional and puts suitability in Python;
  calculations remain mandatory on-device Rust, backend facts/ingestion separate.
- Supplement proposes three days and global-first delivery; use 33 hours and a
  validated Myanmar pilot, while allowing global coordinates.
- Supplement favors English-first and a broad catalog/chat/alerts; primary plan
  prioritizes accessible English/Burmese core flow and defers extras.
- Primary plan mentions a fallback native FFI bridge; current kickoff explicitly
  requires flutter_rust_bridge v2. Any fallback needs team agreement.
- Primary plan's provisional `analyze_field(FarmerInput)` may fetch data; the
  existing `analyze_field(AnalysisRequest)` is pure. Keep it pure and put future
  async retrieval in a separately named adapter. Endpoints are proposals, not live.

## Baseline and first increment

Rust was absent from PATH. Installed Rust 1.85.1 (edition 2024 compatible), rustfmt
and Clippy under `/workspace/.toolchains`, outside the checkout. Baseline four
unit tests and Clippy passed; formatting failed and was corrected before extension.
No initial compilation errors were found.

The first increment extracts private climate validation/aggregation, prevents
rainfall overflow becoming JSON null, avoids temperature intermediate overflow,
and adds eight public-contract regression tests plus a labeled synthetic fixture.
No JSON fields, entrypoint signatures or error variants changed. Existing valid
clients keep their shape; extreme overflowing rainfall is now rejected. Newly
created Cargo.lock is retained for reproducible integration builds.

## Practical module sequence

Keep public types/re-exports in `lib.rs` until schema v1 is agreed. `climate.rs`
is implemented now. Introduce the following only as their milestone needs arise:

1. `models.rs`, `validate.rs`, `evidence.rs`: typed units, dated provenance and
   explicit missingness; coordinate additive changes with P2/P4 and fixtures.
2. Extend `climate.rs`: date-aware monthly/seasonal windows, completeness and
   comparable baselines, without invented agronomic thresholds.
3. `decision/crops.rs`, `decision/rotation.rs`, `decision/risk.rs`: sourced crop
   constraints, production-system distinctions and unknown-aware explanations.
4. `client.rs`: compact backend JSON retrieval, timeouts and explicit fallback
   provenance, separate from pure analysis. P2 owns backend implementation.
5. `api.rs`: flutter_rust_bridge v2 wrapper against P4's real project; Android
   ARM64 bridge/device proof first. Windows development is unverified here.

## Next integration gates and limitations

P2 supplies one real NASA POWER payload with units/dates/scale and documented
local crop constraints; P4 supplies the Flutter project. Agree schema v1 together
before modifying shared fields. Current source labels cannot support scientific
suitability, water risk or real NASA attribution. Scenario placeholders are not
crop recommendations; unknown farmer crop inputs and richer metadata remain debt.

Run from `engine/`: `cargo fmt --check`, `cargo test --locked`,
`cargo clippy -- -D warnings`. Expanded validation also uses
`cargo clippy --all-targets --locked -- -D warnings`. Only native Linux tests
are covered; no live backend, NASA acquisition, APK or device validation yet.
