# Milestone 4C — first live NASA climate integration

## Scope and reviewed evidence

Integration branch: `feat/flutter-live-nasa-integration`, based on
`feature/flutter-app` at `f25e5cf`. PR base is `feature/flutter-app`, keeping the
existing Flutter application out of this integration diff. No merge of PR #7,
PR #8 or another developer's changes is required or performed.

Inspected stable Milestone 3B, the existing `analyzeIntegrationJson` FRB v2.13.0
surface, backend `4befe7d1e204c875436ab486c231edcbb944f317`, and optional
Rust v0.2 `1ba6fb08249a95436487575c0ef26ecf8a93df11`. Read backend API_V1 and
INTEGRATION_QUESTIONS, the real NASA example, and the existing engine readiness
and team review documents. A separately named earlier “Milestone 4C contract
audit” was not present in the repository or supplied as an artifact; this record
reconciles the concrete contracts and review questions rather than asserting an
unavailable audit's approval. The prior Windows Android chat was also inspected:
its local build fixes are not on the fetched Flutter branch; device success was
not established there (USB install restricted).

NASA live retrieval is already verified. The real modeled MERRA-2 capture at
16.85 N, 96.15 E, February 2024 has 29 complete days per variable, total
precipitation 0.04 mm and mean temperature 28.03655172413793 degrees C.
`app/assets/fixtures/nasa_power_real.json` is an exact copy of the backend example,
not invented climate. A new localhost backend retrieval in this task also
returned these values. That verifies climate normalization, not crop suitability.

## MVP contract used by this implementation

The user-authorized boundary is Flutter HTTP -> Python normalization -> on-device
Rust -> Flutter display. Rust does no network retrieval. `ENGINE=rust` defaults
to live climate on mobile; `BACKEND_URL` configures the origin. Web's existing
mock mode remains demo-only. No caching or automatic synthetic fallback was added.

- `GET /api/v1/environment/season` uses the selected farmer point, explicit
  inclusive start/end years and months, finished historical LST months, at most
  24 months. Initial selection is February 2024, shown and editable on Review.
- Accept only schema `1.0-proposal`, success status, exact point/window association,
  NASA POWER / MERRA-2 modeled metadata and normalized mm / deg_c units. Validate
  the provenance point/date interval and required sidecar metadata. Rust validates
  observations, ordering, units, values and completeness through its existing API.
- Send only `environment` into `IntegrationRequest.environment`, keep
  `field.latitude/longitude` identical, and set `data_mode: supplied_data`.
  `supplied_data` is not an agronomic certification.
- Retain the **exact backend response text**, complete provenance/cache, original
  farmer answers, serialized Rust request and actual Rust output as one session
  `IntegrationTrace`. Extra provenance is never injected into Rust structs that
  deny unknown fields. Sources exposes the exact response and retained answers.
  This is session retention, not disk persistence or a cryptographic evidence ID.
- Source/dataset, original retrieval timestamp (including cached responses),
  modeled classification, historical LST window, requested point, units,
  completeness, nominal 0.5 x 0.625 degree grid support and limitations stay visible
  or inspectable. The point is not a farm measurement or grid centroid.
- HTTP failures, timeout/unavailable backend and malformed/mismatched responses
  are errors. Valid incomplete evidence succeeds, with per-variable null totals
  and visible month gaps. No null-to-zero conversion or gap filling occurs.
- Previous crops, planting month and priorities survive in the farmer-answer
  sidecar and session draft. They are not claimed as inputs to climate calculations.
  Partial irrigation is unknown for a year-round prerequisite. Farmer drainage
  `good` maps to Rust `well`; no soil texture is invented.
- Rust scenario order is preserved. Nullable crop IDs display as unknown.
  Synthetic crop profiles retain a separate visible warning even with modeled
  climate. Demo climate is always labeled; live errors offer only an explicit
  user-selected demo action or clearly labeled last successful session result.

## Necessary compatibility extension and remaining review

Stable `IntegrationRequest.field.current_crop` is a required string, and the
independent rotation API requires a baseline plus at least two alternatives.
Neither backend climate nor missing farmer crop answers supplies those scenarios.
Inventing a crop or three rotations to satisfy that validator would be misleading.

This branch adds a narrow **climate-only** path to the existing integration
function when scenarios, source references and crop profiles are all empty. It
uses the same field/point/climate validation and seasonal function, and returns
empty rotations with an explicit unknown-suitability limitation. For the legacy
string field, unreported crop is encoded as `""`; it is not a crop identifier and
is never scored. Known farmer crop is preserved. Existing nonempty crop workflows
still use the existing decision validator unchanged. FRB API signatures and all
generated bindings are unchanged. Rust v0.2 remains optional and unmerged.

Rust/Flutter owners should review this additive empty-scenario convention and
legacy empty-string representation before merging. Backend/Rust owners still
need shared approval of the proposed version, source-ID registry, durable evidence
binding, LST/full-coverage/precipitation naming policies and future mixed product
lineage. MERRA-2-only behavior is inherited from the backend. No v0.2 attribution
or scalar meter resolution is fabricated. Production hosting, auth and CORS are
outside this localhost milestone. Source-backed applicable crop constraints and
agronomic review are still required for any crop-suitability claim.

## Windows + physical Android runbook

Keep the existing Python backend on localhost. Use a separate detached checkout
for its exact reviewed revision; do not merge unfinished backend/Rust branches.
From the repository root in PowerShell:

```powershell
git fetch origin feature/flutter-app feat/nasa-power-backend feat/rust-engine-v0-2
git worktree add --detach ../EarthSync-backend-4c 4befe7d1e204c875436ab486c231edcbb944f317
cd ../EarthSync-backend-4c/server
py -3.12 -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.lock
.\.venv\Scripts\python -m uvicorn earthsync.api:app --host 127.0.0.1 --port 8000
```

In another terminal, from the integration checkout's `app/` directory:

```powershell
flutter doctor -v
flutter pub get
flutter analyze
cargo test --locked --manifest-path ../engine/Cargo.toml
cargo test --locked --manifest-path rust/Cargo.toml
cargo build --release --locked --manifest-path rust/Cargo.toml
flutter test
adb devices -l
adb -s PHONE_ID reverse tcp:8000 tcp:8000
flutter test integration_test/simple_test.dart -d PHONE_ID --dart-define=ENGINE=rust --dart-define=BACKEND_URL=http://127.0.0.1:8000 --dart-define=RUN_LIVE_NASA=true
flutter run -d PHONE_ID --dart-define=ENGINE=rust --dart-define=BACKEND_URL=http://127.0.0.1:8000
```

On Windows host FFI tests, `cargo build` needs the Rust MSVC host linker/toolchain.
On Android, Cargokit builds the device library; Android SDK/NDK, Java and the
matching Rust Android target are required. Use the Flutter/Gradle versions validated
by your Android setup. The base Flutter branch predates local Android fixes in
another chat; those changes are not overwritten or silently pulled into this PR.
Inspect the built APK for `lib/arm64-v8a/libfield_shift_bridge.so` before claiming
packaging success. If the phone reports `INSTALL_FAILED_USER_RESTRICTED`, unlock
it, allow Install via USB if available and approve the install prompt.

Debug-only network security permits cleartext solely for localhost/127.0.0.1 and
Android emulator 10.0.2.2. Release/profile use HTTPS; TLS verification is unchanged.
For release configuration pass `BACKEND_URL=https://YOUR_BACKEND_ORIGIN`.
Remove USB forwarding afterward with `adb -s PHONE_ID reverse --remove tcp:8000`.

Manual smoke: choose the sample field (16.85, 96.15), keep crop unknown, review
February 2024 and Analyze. Check real modeled NASA labels, 0.04 mm and 28.0366 C,
empty/unknown rotations and complete source details. Change the map point and
confirm both query and Rust result match it. Stop the backend and retry: an error
must appear without substituted climate. Select demo explicitly and confirm demo
labels. Missing daily/month data are tested offline without NASA outage dependency.

## Verification record

See the PR validation record for final exact outcomes and unresolved limitations.
The normal Flutter suite includes offline actual-native-FRB tests; build
`app/rust` in release mode first. To opt into real backend retrieval on a host,
start the backend as above then run:

```sh
cd app
flutter test test/native_bridge_test.dart --dart-define=RUN_LIVE_NASA=true --dart-define=BACKEND_URL=http://127.0.0.1:8000
```

No physical phone is attached to this cloud environment. No Android device
execution or APK verification may be inferred from host FFI tests or CI.
