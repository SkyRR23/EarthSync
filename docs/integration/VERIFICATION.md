# Milestone 7H verification report

Verification date: **14 November 2026**. This report distinguishes software checks,
actual browser interaction, device execution and scientific validation. The work is
on the isolated integration branch; no source PR or `main` is modified.

## Current software evidence

| Check | Observed result |
| --- | --- |
| Combined Python unit/API/compiled-Rust contracts | 265 passed, 2 opt-in live checks skipped; one existing Starlette/AnyIO deprecation warning |
| Fresh Python environment from `server/requirements.lock` | 29 pinned packages installed, dependency compatibility passed, same 265 passed / 2 skipped |
| Rust engine, including legacy/integration/v0.2/v0.3 | 111 passed |
| Native bridge Rust tests | 6 passed, including real v0.3 through stable FRB ABI |
| Crop catalog validation | 39 passed; 8 profiles / 13 sources; eligibility false |
| Flutter combined suite | 89 passed, 2 opt-in network checks skipped |
| Separate live web-engine Flutter run | All 5 passed, including NASA → Python HTTP → compiled Rust → Flutter widgets for 12 months of 2025 |
| Web release build | Passed with renderer/fonts served locally |
| Python Ruff lint/format and Rust Clippy/rustfmt | Passed; Clippy denies warnings for both engine and bridge |
| Flutter analysis | No errors or warnings; Material-import migration infos remain visible; final count recorded below after final checks |
| Flutter committed dependency lock | `flutter pub get --enforce-lockfile` passed without changing pins |

Toolchain actually used: Linux, Python 3.12.14, Rust 1.99.0, Flutter 3.50.0,
Dart 3.14.0, Chromium with Playwright 1.65.2. Android compilation and the final
browser acceptance run are being completed; their outcomes are recorded below.

## Live provider and execution receipts

[February 2024 POWER response](evidence/live-nasa-2024-02.json) passed source,
units, interval, coverage and LST checks through the real provider client.
[Actual Rust result](evidence/live-nasa-rust-result.json): 29 calendar days,
0.04 mm rain, weighted mean temperature 28.03655172413793 °C. No crop assessment
was inferred from these historical statistics.

[2025 browser climate response](evidence/browser-live-nasa.json) contains 12
months of actual POWER MERRA-2 data; it can be a cache hit from the same live
backend after the uncached retrieval, not an offline fixture. The separate
[compiled Rust result](evidence/live-nasa-2025-rust-result.json) is 365 days,
2280.56 mm rain and 27.469178082191778 °C weighted mean temperature. The live
Flutter integration test additionally decodes and renders this actual HTTP/Rust
path. Successful software/source checks do not validate farm representativeness.

The real October 2026 request returned HTTP 502 with
[`UPSTREAM_SOURCE_CHANGED`](evidence/live-geosit-rejection.json). GEOS-IT remains
unsupported. No guard was disabled, no response relabeled and no captured/synthetic
fallback used. The UI explains selecting an older completed historical interval.

## Interactive browser acceptance

The committed [browser runner](../../scripts/browser_7h.py) drives real Chromium
controls in the built `lib/main.dart` application and sends actual HTTP requests.
Only the outage check deliberately aborts a request, then removes that interception
to prove recovery. Screenshots and [machine-readable results](evidence/browser-results.json)
record completed steps. Synthetic uploaded test images and v0.3 evidence remain
explicitly labeled. The browser fixture uses a public example point and an
explicitly confirmed test farm, not a real user's private farm.

The run verifies skip-location exploration, a location-free assistant, actual
climate graphs, farm confirmation and refresh restoration, field context and
unavailable providers, private upload/view/replace/delete, and actual synthetic
Rust v0.3 execution. The final catalog/assistant/recovery/responsive outcomes are
updated after the complete runner finishes. No incomplete browser assertion is
counted as a pass.

Browser testing found and fixed these problems that compilation/unit tests alone
missed:

* External renderer CDN dependency caused a blank page under restricted access.
  The launcher now self-hosts the renderer and bundled font and disables the local
  demo's service-worker cache.
* Chart semantics hid climate text from accessibility. Keep dated numerical text
  accessible separately from the chart painters.
* Encoded `ImageDescriptor.width/height` getters are unsupported on Flutter Web.
  Read bounded JPEG/PNG dimensions before decoding; retain codec validation,
  animation checks, consent and server sanitization/limits.
* Background evidence completion could erase a question being typed. Preserve
  unsent text for evidence-only changes while invalidating old-context answers.

One browser failure dump initially included the generated local test token.
That token was rotated, the diagnostic removed, and the runner now redacts its
workspace token from failure text. No production/user credential was used. Tokens
are absent from committed logs, application assets and evidence artifacts.

## Android and Windows scope

Android SDK platforms/build tools 35/36, NDK 28.2.13676358, and a full Temurin JDK
21 were installed locally after the initial machine lacked them. The build uses
normal TLS verification, inherited proxy routing and the managed CA trust store.
Earlier failures were a missing Java compiler, missing SDK 35 for JNI, and the
new JDK's absent managed CA; each setup issue was addressed without bypassing
validation. Final APK status is recorded after the in-progress build finishes.

Android runtime, physical device/camera/location/gallery, actual device FFI,
USB/LAN connectivity and restart behavior are **not yet device verified**. `adb`
initially aborted attempting to create its default state under the read-only home
directory. A successful host FRB test or APK build is not a device test.

The exact Windows launcher and private ACL setup are supplied in
[setup instructions](README.md). Interactive Windows PowerShell hosting, Windows
ACL inspection and physical Wi-Fi testing were not performed on this Linux host.
Existing upstream CI evidence is not relabeled as this integration's Windows test.

## Scientific and security limitations

* SoilGrids REST is documented as paused; Open-Meteo lacks verified run/issue
  identity in this contract. Default soil/weather adapters provide no numbers.
* NDVI/EVI/surface-temperature, HLS and OPERA live pixel/QA retrieval remains
  unavailable. GIBS visual preview can be unavailable under network restrictions;
  it is dated visual context, never field verification.
* All catalog profiles remain `recommendation_eligible=false`. Six map to explicit
  reference-only engine profiles; delayed-flood drill-sown rice and fallow have
  explicit mapping blockers. No compatible numerical rules are invented.
* Daily Tmin/Tmax, crop-period rainfall, soil depth/method/validity, ET0 definition,
  cultivar duration and applicable stage Kc remain missing for real assessments.
  NASA monthly air temperature cannot supply them.
* v0.3 synthetic fixtures validate software arithmetic only. Supported individual
  comparisons never become whole-crop suitability, yield, rankings or advice.
* There is no production account or ownership service. One private bearer token
  authorizes exactly one local demo workspace; farm IDs are labels, not access
  credentials. Changing farm IDs does not bypass authorization. Main-host private
  routes require loopback/HTTPS. Multi-user production hosting remains blocked
  pending proper account, farm-ownership and workspace association design.
* Photos are bounded and sanitized on client/server; optional consented GPS stays
  separate from farm confirmation. The assistant receives availability only, not
  photo bytes, GPS, captions or workspace tokens. Its supplied evidence is not a
  trusted external multi-user authentication channel.
* No scientific field validation or independent agronomist approval is claimed.

## Exact reproducible checks

Use the Python/Flutter/Rust environments from [setup](README.md). Commands from
repository root, unless a subshell changes directory:

```sh
PYTHONPATH=server python -m pytest -q server/tests
python -m ruff check server scripts/browser_7h.py data/crop-knowledge/v1/tools data/crop-knowledge/v1/tests
python -m ruff format --check server scripts/browser_7h.py data/crop-knowledge/v1/tools data/crop-knowledge/v1/tests
python data/crop-knowledge/v1/tools/catalog.py check
python -m unittest discover -s data/crop-knowledge/v1/tests -q
cargo test --locked --manifest-path engine/Cargo.toml
cargo test --locked --manifest-path app/rust/Cargo.toml
cargo fmt --check --manifest-path engine/Cargo.toml
cargo fmt --check --manifest-path app/rust/Cargo.toml
cargo clippy --all-targets --locked --manifest-path engine/Cargo.toml -- -D warnings
cargo clippy --all-targets --locked --manifest-path app/rust/Cargo.toml -- -D warnings
cargo build --release --locked --manifest-path app/rust/Cargo.toml
(cd app && flutter pub get --enforce-lockfile)
(cd app && flutter test --reporter expanded)
(cd app && flutter analyze --no-fatal-infos)
(cd app && dart format --output=none --set-exit-if-changed lib test integration_test test_support example)
(cd app && flutter build web --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run)
# Unified service running at the requested URL:
(cd app && flutter test test/web_engine_test.dart --dart-define=RUN_WEB_DEMO=true --dart-define=WEB_DEMO_URL=http://127.0.0.1:8080/ --reporter expanded)
python -u scripts/browser_7h.py --base-url http://127.0.0.1:8080 --token-file /absolute/private/workspace-token.txt
(cd app && flutter build apk --debug --dart-define=BACKEND_URL=http://127.0.0.1:8080)
git diff --check
```

Local executions used `/workspace/.earthsync-python/bin/python`, a separate clean
venv at `/tmp/earthsync-7h-clean-python`, and service ports **8097/8099** to avoid
unrelated running tasks. Flutter/Rust caches lived under `/workspace` because the
home directory is read-only. Tool-specific analytics/cache environment settings
were used without changing HOME. Test skip counts refer to opt-in network checks;
actual live verification was run separately as described above.
