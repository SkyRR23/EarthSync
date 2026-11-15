# Milestone 7A — global onboarding and home dashboard

Base: `origin/feat/web-demo` at `e0cdaaf875efb376e3081a66826b4b5e21601c67`.
Development worktree: `/workspace/EarthSync-global`, branch
`feat/global-onboarding-dashboard`. No existing PR was merged or branch replaced.

## Behavior and architecture

- First launch offers **Use My Location**, **Choose an Area**, and **Skip for Now**.
  GPS is requested only by the first action. Permission denial, disabled services,
  unavailable browser geolocation, and skipping lead to global exploration.
- `UserLocation` is either `UnknownLocation` (with an unknown/skipped/denied/
  unavailable reason) or `ApproximateArea` (device/manual/example source).
  Device coordinates are rounded to two decimals for area context.
- `ConfirmedFarm` is a separate point record with a stable ID, optional name and
  explicit confirmation timestamp. Only **Save Confirmed Farm**, after checking
  the confirmation box, creates or updates it. Changing coordinates clears the
  checkbox. Map taps and form edits stay local until saving.
- `HomeProfile` has a versioned farm list and active farm ID to support a future
  multiple-farm UI. This milestone exposes one farm. It creates no polygons,
  inferred boundaries, soil measurements or new suitability outputs.
- `HomeProfileNotifier` serializes local writes, publishing after successful
  persistence. Saved farm data and onboarding choices use one JSON record in
  `shared_preferences` (`earthsync.home.v1`). Invalid storage recovers with an
  explanation. Skip still opens the dashboard if storage is unavailable.
- Area changes never mutate farm records or questionnaire coordinates. Restored
  farm coordinates seed the questionnaire. Farm edits clear previous analysis
  and invalidate in-flight results while retaining questionnaire answers.
- The dashboard calls the existing validated `NasaPowerClient` directly; it does
  not invoke either crop engine. It shows monthly values only when the backend
  marks each variable complete; missing/incomplete months remain unknown. It
  performs no climate gap filling, agricultural calculation or spatial average.
- Climate state is keyed by exact point and historical window. Refresh failures
  retain same-query values with a **last-known data** label. Data are retained
  only during the screen session, not written into the profile. Area/period
  changes cannot show another query's evidence. Requests do not automatically
  retry; **Try climate again** is an explicit action.
- Normal dashboards start at the last completed calendar year on Android and
  Web. The existing explicitly selected `?climate=captured` analysis mode keeps
  its February 2024 contract. Dashboard climate always requests the real service;
  mock/captured/synthetic analysis modes never become dashboard fallbacks.
- Source, requested point, historical dates, retrieval times, cache provenance,
  completeness, spatial scale, and limitations stay accessible. NASA POWER is
  point-query gridded MERRA-2 context, **not an independently calculated area
  average** or a farm measurement. No regional crop recommendations are shown.
- Satellite cards request the existing provisional MODIS Terra true-colour layer
  from NASA GIBS WMS, around the selected point, with date/source labels and
  loading/error text. Clouds and absent pixels do not establish ground conditions.
  The view shifts at poles/dateline to keep a valid bounding box; its rectangle
  is an image viewport, never a field boundary or a regional averaging polygon.
- The questionnaire/review routes require a confirmed farm, including direct
  links. Results/rotation comparison remain separate from the home dashboard.
  Native Rust initializes only when analysis is requested so engine startup does
  not block onboarding or environmental browsing. Python/Rust JSON contracts,
  generated bridge bindings, crop references and agricultural rules are unchanged.

## Privacy and platform notes

Before choosing or saving a point, the app explains that coordinates go to the
configured environmental backend and NASA POWER. NASA GIBS receives the image
viewport; the optional map requests OpenStreetMap tiles. The area/farm form works
without opening that map. There is no account synchronization, analytics upload,
background location or location stream. Android backup is disabled to prevent
these local coordinate preferences being included in automatic app backup.

Local preferences are not encrypted. Anyone using the same device/browser profile
can access them; clearing app/site storage removes them. Browser persistence is
per origin, so a changed host or port has separate choices. Permission denied or
unsupported geolocation never prevents manual entry or dashboard access.

Geolocation usually requires HTTPS or a trusted localhost origin. A phone opening
`http://<PC-Wi-Fi-IP>:8080` is not equivalent to localhost and may have no geolocation.
Use manual selection there, or a properly secured HTTPS host. Do not bypass
browser certificate warnings. Android needs foreground coarse/fine permissions
(the user may grant approximate access); neither is requested at launch.

## Windows checks (PowerShell)

Use Flutter 3.50.0 / Dart 3.14.0, Rust stable and Python 3.12 or later. Commands
below start at the repository root on this branch. Flutter analysis still has
informational Material-import deprecations from the project's SDK transition;
`--no-fatal-infos` leaves errors and warnings fatal.

```powershell
python -m venv server/.venv
server/.venv/Scripts/python -m pip install -e "./server[test]"
cargo test --locked --manifest-path engine/Cargo.toml
cargo test --locked --manifest-path app/rust/Cargo.toml
cargo build --locked --manifest-path engine/Cargo.toml --example web_engine
cargo build --release --locked --manifest-path app/rust/Cargo.toml
server/.venv/Scripts/python -m pytest server/tests -q
cd app
flutter pub get
dart format lib test
flutter analyze --no-fatal-infos
flutter test --reporter expanded
flutter build web --no-wasm-dry-run --no-web-resources-cdn
cd ..
./Run-WebDemo.ps1 -SkipBuild
```

Open `http://127.0.0.1:8080/`. For a clean first launch, use a fresh browser profile
or clear this origin's site storage. Skip; select an example area; check **Your
Area**, climate graphs, source dates and imagery. Add a test farm using the public
example point, confirm it, refresh, edit it, and open the questionnaire. Switch
back to **Your Area** and select a different point; the farm must stay fixed.
Stop the service or use browser offline mode to exercise unavailable imagery and
climate; the dashboard must never load synthetic climate automatically.

For the existing opt-in live web analysis regression, leave the service running
and use a second PowerShell window at the repository root:

```powershell
cd app
flutter test test/web_engine_test.dart --dart-define=RUN_WEB_DEMO=true --reporter expanded
```

The retained captured and mock analysis modes are described in
[WEB_DEMO.md](WEB_DEMO.md). Yangon is an optional example area, not a geographic
restriction or an automatically confirmed farm.

## Android over USB (Windows PowerShell)

Install Android Studio's SDK/NDK, enable USB debugging, connect and authorize the
phone. Replace `PHONE_ID` below with the identifier reported by `flutter devices`.
Use an ARM64 phone for the ARM64 build command.

Start the Python backend in one PowerShell window at the repository root:

```powershell
server/.venv/Scripts/python -m uvicorn earthsync.api:app --app-dir server --host 127.0.0.1 --port 8000
```

In another PowerShell window at the repository root:

```powershell
rustup target add aarch64-linux-android armv7-linux-androideabi
adb devices
adb reverse tcp:8000 tcp:8000
cd app
flutter doctor -v
flutter devices
flutter pub get
flutter run -d PHONE_ID --dart-define=ENGINE=rust --dart-define=BACKEND_URL=http://127.0.0.1:8000
```

Optional debug APK and existing native integration gate:

```powershell
flutter build apk --debug --target-platform android-arm64 --dart-define=ENGINE=rust --dart-define=BACKEND_URL=http://127.0.0.1:8000
flutter test integration_test/simple_test.dart -d PHONE_ID
```

On-device checklist: deny permission and continue; allow approximate location;
choose a point manually; skip; confirm/name a farm; close/reopen to restore; edit
farm coordinates and re-confirm; change area without moving the farm; open the
questionnaire; stop the backend and verify unavailable text. A production Android
build needs an HTTPS `BACKEND_URL`. Debug-only cleartext localhost support is
already configured; no release networking policy was weakened.

## Verification in this environment

Verified on 14 November 2026 with Flutter 3.50.0 / Dart 3.14.0:

- Formatting check passed for all 28 changed Dart files; `git diff --check` passed.
- `flutter analyze --no-fatal-infos` passed: no errors or warnings, 32 informational
  Material-import deprecations (the existing SDK transition also affects new UI).
- `flutter test --reporter expanded`: 52 passed, two opt-in live-network tests
  skipped. Includes the actual native bridge, lazy native startup, all onboarding
  choices, manual global selection, confirmation/edit/restore, independent area
  updates, concurrent/failed persistence, stale analysis cancellation, missing
  climate, unavailable API, same-query last-known data and no synthetic fallback.
- Engine: 82 Rust tests passed. Native bridge: five Rust tests passed; release
  library built. Python: 48 tests passed with Cargo available on PATH, including
  real cross-language checks (one existing Starlette/AnyIO deprecation warning).
- `flutter build web --no-wasm-dry-run --no-web-resources-cdn` passed. The local
  host served the release build successfully on port 8090.
- Actual desktop Chromium visual testing **succeeded**: welcome, skip to global
  exploration, Nairobi example selection, real 2025 NASA POWER graphs and
  provenance, dated NASA GIBS imagery, separate test-farm confirmation/name,
  refresh restoring the saved farm, and opening the existing questionnaire.
  Visual inspection found chart-axis crowding; the final build uses spaced,
  whole-number ticks. No network mock was used for those climate/imagery views.
- Phone-width widget tests passed at 412 × 880. Managed Chromium policy blocked
  DevTools device emulation; no mobile-browser visual claim is made.
- Android APK/device execution was **not performed**: this environment has no
  Android SDK or connected phone. Use the commands above to complete that gate.
