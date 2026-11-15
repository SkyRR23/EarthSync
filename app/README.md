# Field Shift — Flutter app (P4)

NASA Space Apps 2026 · farmer crop-rotation explorer. Design: [docs/flutter-design-system.md](docs/flutter-design-system.md).

## Run

```bash
flutter run                              # native Rust engine, live backend required
flutter run --dart-define=ENGINE=rust    # on-device Rust engine via flutter_rust_bridge
flutter run --dart-define-from-file=config/cloud.json  # Rust + hosted NASA backend (Firebase Hosting -> Cloud Run, Singapore)
flutter run --dart-define=ENGINE=mock --dart-define=MOCK_FAIL=true # test the error screen
```

H2 gate — prove Flutter → Rust works on the connected phone:

```bash
flutter devices
flutter test integration_test/simple_test.dart -d PHONE_ID
```

## Rust bridge

- Crate: `rust/` (`field_shift_bridge`), API in `rust/src/api/bridge.rs` — P1 owns the engine logic.
- After changing any `pub fn` in `rust/src/api/`, regenerate Dart bindings:

```bash
flutter_rust_bridge_codegen generate
```

- Generated Dart lives in `lib/src/rust/` (do not edit). The app talks to it only through `lib/data/engine/rust_engine.dart`.
- Boundary: `analyze_integration_json(IntegrationRequest JSON)` returns the shared engine's success/error envelope. `analyze_synthetic_demo_json` applies farmer answers to the engine's synthetic fixture; location and climate remain synthetic. This is not a live NASA or verified agricultural recommendation path.
- Toolchain: Rust stable + `aarch64-linux-android`, `armv7-linux-androideabi` targets, flutter_rust_bridge_codegen 2.13.0, Android NDK (cargokit finds it automatically during `flutter run`).

## Android integration checks

Enable USB debugging, connect the phone and accept its authorization prompt.
Replace `PHONE_ID` with the Android device identifier from `flutter devices`.
From this directory:

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test
cargo test --locked --manifest-path rust/Cargo.toml
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=config/cloud.json  # phone build: live backend
flutter test integration_test/simple_test.dart -d PHONE_ID
flutter run -d PHONE_ID --dart-define-from-file=config/cloud.json
```

The ARM64 build command requires an ARM64 phone for installation. For other
architectures, build for the connected target and install its Rust target too.
The integration test calls Rust directly regardless of the `ENGINE` setting;
the native app defaults to Rust mode; keep `ENGINE=rust` when checking
the actual farmer workflow. Verify synthetic labels, baseline and two
alternatives, unknown states, and the error envelope before merging to `main`.
A successful host test or APK build alone does not establish device success.

### Local Windows SDK and cache

If this checkout has the ignored `.android-sdk/` and `.gradle-local/` folders,
run these commands from `app/` before building so the build uses D: storage.
These environment settings apply only to the current PowerShell session.

```powershell
$env:ANDROID_HOME = (Resolve-Path ../.android-sdk).Path
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:GRADLE_USER_HOME = (Resolve-Path ../.gradle-local).Path
$env:TEMP = Join-Path $env:GRADLE_USER_HOME 'tmp'
$env:TMP = $env:TEMP
$env:CARGO_BUILD_JOBS = '1'
```

The tested local build used Flutter 3.50.0 / Dart 3.14.0, Rust 1.99.0,
Gradle 9.4.1, AGP 9.1.1, Android API 36 and NDK 28.2.13676358. Flutter's
SDK-pinned test dependencies updated `pubspec.lock`; use a matching Flutter
SDK when reproducing the build.

On phones that reject ADB installation with `INSTALL_FAILED_USER_RESTRICTED`,
enable the device's **Install via USB** setting if available, unlock the phone
and approve its installation prompt. USB debugging authorization alone may
not permit APK installation.
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

## Local browser demo

See [the web demo runbook](../docs/WEB_DEMO.md). Run `../Run-WebDemo.ps1` from
PowerShell (or `./Run-WebDemo.ps1` from the repository root). Browser analysis
calls the actual compiled engine through a separate local Python service;
Android continues to use the on-device FRB bridge.
