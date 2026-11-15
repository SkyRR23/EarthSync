# Milestone 7H verification report

Verification date: **14 November 2026**. This report distinguishes software checks,
actual browser interaction, device execution and scientific validation. The work is
on the isolated integration branch; no source PR or `main` is modified.

## Current software evidence

| Check | Observed result |
| --- | --- |
| Combined Python unit/API/compiled-Rust contracts | 270 passed, none skipped, with Rust activated; one existing Starlette/AnyIO deprecation warning |
| Fresh Python environment from `server/requirements.lock` | 30 pinned packages installed, dependency compatibility passed, same 270 passed / none skipped |
| Remote backend matrix | Windows and Ubuntu, Python 3.12 and 3.13: all four jobs passed, 270 tests each |
| Remote component/application CI | All six workflows passed for the tested code commit; [receipt](evidence/ci-final.json) |
| Rust engine, including legacy/integration/v0.2/v0.3 | 111 passed |
| Native bridge Rust tests | 6 passed, including real v0.3 through stable FRB ABI |
| Crop catalog validation | 39 passed; 8 profiles / 13 sources; eligibility false |
| Flutter combined suite | 90 passed, 2 opt-in network checks skipped |
| Separate live web-engine Flutter run | All 5 passed, including NASA → Python HTTP → compiled Rust → Flutter widgets for 12 months of 2025 |
| Combined live native and web Flutter paths | All 10 passed against this branch's unified backend; actual FRB and compiled web executable |
| Web release build | Passed with renderer/fonts served locally |
| Python Ruff lint/format and Rust Clippy/rustfmt | Passed; Clippy denies warnings for both engine and bridge |
| Flutter analysis | No errors or warnings; 45 existing/new Material-import migration infos remain visible |
| Flutter committed dependency lock | `flutter pub get --enforce-lockfile` passed without changing pins |

Toolchain actually used: Linux, Python 3.12.14, Rust 1.99.0, Flutter 3.50.0,
Dart 3.14.0, Chromium with Playwright 1.65.2. The Android debug APK and complete Chromium acceptance journey both passed.
Runtime/device and scientific limits below still apply.

## Acceptance coverage and remaining work

| Requested journey | Evidence and scope |
| --- | --- |
| A: new user without location | Chromium skip flow and location-free assistant; no fabricated farm |
| B: selected area and historical graphs | Actual 2025 POWER request, rendered graphs and source details in Chromium |
| C: farm confirmation and restoration | Chromium confirmation and browser refresh; persistence/edit independence also covered by Flutter tests |
| D/E: field dashboard and unavailable soil/weather | Main-app Chromium flow and mounted API tests; unavailable values remain empty/null |
| F: photo upload/view/replace/delete | Actual Chromium file chooser, authenticated HTTP and rendered image; image sanitation, consent, quotas and authorization regressions |
| G: unavailable satellite/SAR | Main-app Chromium timeline plus API tests; no live pixels claimed |
| H: real NASA → Python → compiled Rust → Flutter | Complete Chromium questionnaire/results flow and separate live Flutter HTTP/widget checks |
| I: synthetic v0.3 | Actual compiled executable through HTTP and main Flutter screen, visibly labeled software test |
| J: reference-only catalog | All six mapped profiles tested through actual Rust; main Chromium profile/date flow with insufficient result |
| K: evidence-bound chatbot | Chromium with no farm and with actual NASA/Rust context; source/status/privacy regression tests |
| L: outage and recovery | Chromium transport abort followed by restored real HTTP; no fixture substitution |
| M: legacy/mock/captured compatibility | Python compiled legacy/v0.2/v0.3 tests, native bridge tests and Flutter fixture/captured transport tests; explicit replay flag preserved |
| N: Android | Debug APK built with all three native Rust ABIs; host bridge execution passed. Physical/emulator runtime remains unverified |

The [HTTP receipt](evidence/http-smoke.json) additionally records 14 requests to
the running unified server, including all three compiled engine versions,
environmental and assistant routers, satellite availability, private photo
authorization, and a JSON 404 instead of the static application for an unknown API.
The photo success was authorized with the local test workspace token; the receipt
does not contain it. Health success does not establish provider validation.

| Capability classification | Delivered state |
| --- | --- |
| Implemented and software/browser tested | Primary onboarding/navigation, independent area/farm state, historical POWER graphs, field availability panels, private demo photos, compiled engine paths, catalog handoff, deterministic assistant |
| Implemented but not live-provider validated | Opt-in environmental adapters and photo/satellite evidence contracts; their defaults remain unavailable |
| Reference-only | All global catalog profiles and associated institutional guidance; no verified candidate eligibility |
| Synthetic demonstrations | Explicit fictional v0.3 fixture and labeled browser photo; software behavior only |
| Unavailable or blocked | Live soil/weather/HLS/OPERA products, GEOS-IT compatibility, real regional crop suitability and scientific field validation |
| Not implemented for production | Account authentication, multi-user ownership/workspace association, production deployment, independently verified executable crop rules |
| Not yet verified | Android device behavior, interactive Windows launcher/ACLs, physical Wi-Fi access; CI status is recorded separately below |

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

The completed run has **12 passing stages and zero unhandled browser errors**:
skip-location exploration; a location-free assistant; actual climate graphs;
farm confirmation/refresh restoration; the complete questionnaire → real NASA →
compiled Rust → results screen; unavailable field providers; private photo CRUD;
synthetic v0.3; reference catalog gap assessment; chat bound to the actual Rust
result and NASA sources; simulated outage with real recovery; and a fresh
360×800 Chromium viewport. Screenshots were inspected. This is browser viewport
verification, not physical mobile-device behavior.

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
That token was rotated, failure artifacts removed, and the runner now redacts its
workspace token from failure text. No production/user credential was used. Tokens
are absent from committed logs, application assets and evidence artifacts.

## Android and Windows scope

Android SDK platforms/build tools 35/36, NDK 28.2.13676358, and a full Temurin JDK
21 were installed locally after the initial machine lacked them. The build uses
normal TLS verification, inherited proxy routing and the managed CA trust store.
Earlier failures were a missing Java compiler, missing SDK 35 for JNI, and the
new JDK's absent managed CA; each setup issue was addressed without bypassing
validation. **The final debug APK build passed**, packaging `libfield_shift_bridge.so` for
`armeabi-v7a`, `arm64-v8a` and `x86_64`. The local artifact is
`app/build/app/outputs/flutter-apk/app-debug.apk`; its checksum and ABI inventory
are in [android-build.json](evidence/android-build.json). A repeat build with the
installed SDK/JDK and all three Rust targets also passed.

Android runtime, physical device/camera/location/gallery, actual device FFI,
USB/LAN connectivity and restart behavior are **not yet device verified**. `adb`
initially aborted attempting to create its default state under the read-only home
directory. A successful host FRB test or APK build is not a device test.

The exact Windows launcher and private ACL setup are supplied in
[setup instructions](README.md). Interactive Windows PowerShell hosting, Windows
ACL inspection and physical Wi-Fi testing were not performed on this Linux host.
Existing upstream CI evidence is not relabeled as this integration's Windows test.

Remote CI exposed a test-reporting defect: the over-limit photo fixture became a
10 MiB pytest node ID. Verbose/duration output repeated it into a 21 MB log,
including 10 MB single lines. Explicit descriptive parameter IDs retain the exact
large payload and assertions while bounding the reports. The local reproduction
and the complete suite pass with short IDs. A 120-second traceback watchdog keeps
future stalls diagnostic rather than silently skipping tests. The rerun made
the actual Windows failures accessible: all 33
failures were CP1252 decoding errors in the assistant's UTF-8 locale resources.
The loader now specifies UTF-8; English and Spanish regression tests simulate the
Windows default without changing the process locale or setting `PYTHONUTF8` to
hide the problem. The JSON fixture endpoints and smoke report also explicitly
use UTF-8. The next run isolated one remaining wire-fixture read with the same
implicit encoding; all assistant wire/schema fixture reads now also specify
UTF-8. [Failed-run receipts](evidence/ci-regressions.json) preserve both observed
results and fixes instead of relabeling them as passes.

The corrected [backend matrix run](https://github.com/SkyRR23/EarthSync/actions/runs/43594600243)
for commit `27f67cb43694c09d40d31a488f2d8d3e89ebd64f` passed on **Windows and
Ubuntu with Python 3.12 and 3.13**. Each job reports **270 passed**, with no test
skips. This verifies the Windows backend tests and compiled Rust contracts; it
does not verify an interactive Windows launcher, ACL configuration or browser.

The environment reports the saved unrestricted network policy as enforced and
current; no pending restart was indicated. The expected GitHub Actions job-log
endpoint was checked directly and returned HTTPS redirects to Azure result
storage (including `productionresultssa16.blob.core.windows.net`). Direct blob
downloads still received proxy 403s. Once the bounded run completed, both the
GitHub integration log tool and the workflow archive successfully returned its
Windows diagnostics. No TLS verification or security setting was weakened.

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
(cd app && flutter test test/native_bridge_test.dart test/web_engine_test.dart --dart-define=RUN_LIVE_NASA=true --dart-define=RUN_WEB_DEMO=true --dart-define=BACKEND_URL=http://127.0.0.1:8080 --dart-define=WEB_DEMO_URL=http://127.0.0.1:8080/ --reporter expanded)
python -u scripts/browser_7h.py --base-url http://127.0.0.1:8080 --token-file /absolute/private/workspace-token.txt
(cd app && flutter build apk --debug --dart-define=BACKEND_URL=http://127.0.0.1:8080)
git diff --check
```

Local executions used `/workspace/.earthsync-python/bin/python`, a separate clean
venv at `/tmp/earthsync-7h-clean-python`, and service ports **8097/8099** to avoid
unrelated running tasks. Flutter/Rust caches lived under `/workspace` because the
home directory is read-only. Tool-specific analytics/cache environment settings
were used without changing HOME. Flutter skip counts refer to opt-in network checks;
actual live verification was run separately as described above. Final Python runs
activate Cargo and include both external-consumer Rust compilation checks with no
skips. Earlier Python runs without Cargo on PATH skipped those two checks; they
were not live-provider tests.
