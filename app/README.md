# Field Shift — Flutter app (P4)

NASA Space Apps 2026 · farmer crop-rotation explorer. Design: [docs/flutter-design-system.md](docs/flutter-design-system.md).

## Run

```bash
flutter run                              # mock engine (demo fixture), default
flutter run --dart-define=ENGINE=rust    # on-device Rust engine via flutter_rust_bridge
flutter run --dart-define=MOCK_FAIL=true # test the error screen
```

H2 gate — prove Flutter → Rust works on the connected phone:

```bash
flutter test integration_test/simple_test.dart
```

## Rust bridge

- Crate: `rust/` (`field_shift_bridge`), API in `rust/src/api/engine.rs` — P1 owns the engine logic.
- After changing any `pub fn` in `rust/src/api/`, regenerate Dart bindings:

```bash
flutter_rust_bridge_codegen generate
```

- Generated Dart lives in `lib/src/rust/` (do not edit). The app talks to it only through `lib/data/engine/rust_engine.dart`.
- Boundary is contract-v1 JSON: `analyze_field_json(FarmerInput JSON) -> FieldAnalysis JSON`, errors as EngineError JSON.
- Toolchain: Rust stable + `aarch64-linux-android`, `armv7-linux-androideabi` targets, flutter_rust_bridge_codegen 2.13.0, Android NDK (cargokit finds it automatically during `flutter run`).

## Milestone 4C live climate

Phone Rust mode now retrieves modeled NASA POWER climate from Python, then calls
`analyzeIntegrationJson` locally. The Review screen has a separate inclusive
historical month window (initially February 2024); planting month is a farmer
answer, not the climate query period. There are no verified crop recommendations.

See [the integration contract and Android runbook](../docs/MILESTONE_4C.md).
Build the native bridge with `cargo build --release --locked` from `app/rust/`
before running host `flutter test`. This suite includes actual native FFI tests.
`CLIMATE_MODE=synthetic_demo` and `ENGINE=mock` remain explicit demo modes;
live failures never select them automatically.
