# Milestone 7L — Flutter product interface

## Review base and isolation

Implementation branch: `feat/flutter-complete-ui-v1`.
Isolated worktree: `/workspace/EarthSync-ui`.

| Source | Reviewed immutable commit | Use |
| --- | --- | --- |
| 7H integration | `5addde741cb9a0efbea9492b2bf8f889d5862517` | Implementation base; existing routes, Riverpod state, clients, Rust v0.3 and photo privacy behavior |
| 7A onboarding | `e05c5371d439d9b1970b4103a1c37eaf3afa500f` | Reviewed area/device/farm separation and persistence; already integrated in 7H |
| 7I platform | `b578a6df2764479ff9c9df006cc00e5ddb3ccfa3` | Reviewed API, JSON Schemas, handoff, job, evidence and daily POWER source contracts |
| Photo evidence | `d5e24f3a6120e745a63394a6ca1e0b28c75794c1` | Existing sanitizer/client/consent/gallery behavior retained |

7H/7I were fetched again before delivery. No merge, rebase, shared backend router,
Rust algorithm, scientific dataset, migration or teammate worktree was changed.
A detached `/workspace/EarthSync-platform-review` checkout runs 7I independently
for consumer verification. It is not an integration merge.

## Product and design decisions

The four supplied references informed the forest-green/ivory palette, rounded
surfaces, quiet typography, field context, visual crop chronology and approachable
chat. They are not displayed as backgrounds or used as scientific evidence.
The contour artwork is decorative Flutter painting, not a map or farm boundary.

- Material 3 light/dark theme, explicit typography and a locally bundled Burmese
  font fallback; semantic surfaces and touch targets; no remote font dependency.
- Shared `design/app_shell.dart`: five functioning primary destinations, bottom
  navigation below 1000 px and a scrollable sidebar above it. Existing secondary
  routes remain in the real router. Results use secondary tabs rather than a
  second bottom navigation bar. Content widths and paired cards adapt independently.
- `design/components/product.dart`: page headers, section/action cards, responsive
  pairs, evidence notices/loading placeholders, source notes, confirmation dialog.
- Welcome actions precede decorative content on mobile. GPS is optional. Selecting
  an area never confirms or relocates a farm. GPS suggestions on the location form
  remain drafts until explicit confirmation.
- Dashboard supports no location, exploration area and confirmed farm. Climate
  dates, graphs, accessible exact-value disclosures, retrieval information and
  unavailable forecasts remain distinct.
- Field overview, dated GIBS view with retry/date selection, consented interactive
  OSM map with distinct area/farm markers, optical/SAR availability and source
  disclosures retain existing server evidence boundaries. One provisional GIBS
  product is supported; unvalidated layers are not advertised as working controls.
- Crop planning adds per-farm local notes, planting/harvest date controls and a
  previous/current crop timeline. Notes are farmer-reported and deliberately do
  not become reviewed Rust inputs. The existing questionnaire and review still
  collect the engine's supported input contract. Rust v0.3 findings, missing
  inputs, source IDs, validation failures and synthetic-test labels remain visible.
- Photos keep the existing private workspace, metadata consent, selection,
  sanitization, replacement and upload behavior. Gallery images open full-screen
  with pan/zoom. Deletion now requires confirmation. Tokens remain session-only.
- The deterministic assistant retains stale-context rejection, retries, citations
  and expandable evidence. The active farm or area is named above the conversation.
- Sources works before any assessment; it no longer presents an endless loader.
  Current climate provenance and original result reference details remain readable.
- Settings persist system/light/dark appearance and language preference. No fake
  account, unsupported unit conversion, subscription or unimplemented setting.
- `app/ui_copy.dart` externalizes navigation and primary presentation text;
  `app/ui_labels.dart` centralizes English supporting-workflow copy. Existing
  `app/strings.dart` and assistant English/Spanish catalogs remain. Burmese is an
  explicitly machine-drafted navigation preview requiring native/domain review;
  complete scientific translation is not claimed.
- The web bootstrap uses bundled CanvasKit so first load does not require a second
  renderer CDN. Live NASA/imagery/map requests still require their services.

## Backend boundaries

Default behavior uses the existing reviewed 7H service clients, not new endpoints:
monthly climate, environmental context, catalog, real Rust execution, assistant,
photos and satellite timeline. No failed request falls back to synthetic data.
The checked-in fixtures remain explicitly selected demos or test inputs.

`data/environment/platform_climate.dart` is a separate typed 7I adapter. Enable
its settings destination only with `--dart-define=PLATFORM_URL=http://127.0.0.1:8021`.
It submits `/api/platform/v1/climate/jobs`, accepts HTTP 202, supports explicit
status refresh/cancellation, and preserves immutable daily records, original units,
quality, source versions, missing reasons and gaps. Completed processing does not
mean complete evidence. Exact coordinate changes invalidate old job callbacks.

The adapter rejects hosted URLs. Start 7I with its documented local-only factory
and exact allowed loopback browser origin. Never mount it publicly, loosen its
origin/ownership checks, reuse a workspace token or upload a local farm implicitly.
Regional climate jobs do not create farm records. A future farm persistence adapter
needs explicit ownership/migration reconciliation and supported production-system
inputs; 7L does not silently replace local state with server farms.

## Skills discovered and applied

Cloud skill catalogs were paged completely, executor-owned skills were listed,
and filesystem skill/AGENTS locations in the repository and user environment were
searched before implementation. There was no project AGENTS.md or exposed custom
Flutter, UI/UX, accessibility or responsive-design SKILL.md. Document/media skills
and unrelated provider skills were not represented as Flutter skills.

| Skill | Applied workflow |
| --- | --- |
| `cloud-environment:cloud-environment-runtime` | Inspected environment policy; followed package/network/Docker references for isolated Flutter, Python, Android and JDK setup; retained proxy/TLS controls |
| `cloud-environment:cloud-desktop` | Opened the running local app in shared Chromium; inspected actual layouts and actions; captured real screenshots |
| `vercel:verification` | Traced user story across UI → typed client → actual API → NASA/Rust/evidence → rendered results, with separate offline, live and browser evidence |

The verification skill's general boundary-tracing method applies without adopting
Vercel or replacing FastAPI/Rust. Its platform-specific deployment steps are not
applicable. Browser DOM automation reported “could not read requirements”, so
visual checks used its documented native Chromium window API. No custom skill
was invented or claimed to have run. Locally installed Windows-only user skills
would need to be exposed to this Linux environment for a later pass.

## Reproduce and integrate

Use Flutter 3.44 / Dart 3.12 or a reviewed compatible toolchain and Rust 1.99.
The environment's original lock required newer transitive SDK versions; dependency
resolution retained the direct Riverpod/router/map/chart/FRB versions and selected
compatible transitive versions. `flutter_localizations` pins intl 0.20.2 in Flutter
3.44; the compatible `^0.20.2` constraint also permits later 0.20.x SDK pins.
The SDK used here came from `ghcr.io/cirruslabs/flutter:stable`, digest
`sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8`.

```sh
cargo build --release --locked --manifest-path app/rust/Cargo.toml
cargo build --locked --manifest-path engine/Cargo.toml --examples
cd app
flutter pub get
# Format the edited Dart files, then:
flutter analyze
flutter test --reporter expanded
flutter build web --no-wasm-dry-run --no-web-resources-cdn
flutter build apk --debug
```

Run the existing demo host from the repository root with an isolated Python
environment containing `server[test,evidence]`:

```sh
PYTHONPATH=server python -m uvicorn earthsync.web_demo:app --host 127.0.0.1 --port 8091
```

Open `http://127.0.0.1:8091`. This serves the actual web build and the existing
APIs together. For an Android local demo, use `adb reverse` for the explicitly
configured loopback backend port; do not send private photo tokens over external
plain HTTP. Release signing and production identity are separate deployment work.

Opt-in live consumer checks (ordinary tests require no NASA network):

```sh
cd app
flutter test test/native_bridge_test.dart --dart-define=RUN_LIVE_NASA=true --dart-define=BACKEND_URL=http://127.0.0.1:8091
flutter test test/web_engine_test.dart --dart-define=RUN_WEB_DEMO=true --dart-define=WEB_DEMO_URL=http://127.0.0.1:8091/
# Start pinned 7I locally using its own handoff first:
flutter test test/ui/platform_live_test.dart --dart-define=RUN_LIVE_PLATFORM=true
```

Create a **new** final integration branch from the accepted 7H snapshot, integrate
this UI branch there, then integrate 7I only after its review. Do not merge this
branch automatically into the active 7H or 7I branches. Reconcile these UI files:
`app/lib/app/router.dart`, `app/lib/main.dart`, `app/lib/design/**`,
`app/lib/features/{dashboard,field,location,onboarding,assistant,results,sources}/**`,
`app/lib/features/photo_evidence/photo_evidence_panel.dart`,
`app/lib/features/questionnaire/historical_window_selector.dart`, `app/pubspec.*`
and `app/web/flutter_bootstrap.js`. New planning/preferences/copy/adapter files
are additive. Original shared home/integration/questionnaire providers and
transport clients are preserved.

## Verification and remaining boundaries

See `MILESTONE_7L_VERIFICATION.md` for measured outcomes and screenshots.
No crop score, crop recommendation, universal field-health score, diagnostic SAR
claim, GIBS-derived NDVI, present weather or invented forecast was added.
Hosted authentication, accepted quantitative satellite ingestion, globally reviewed
agronomic rules, complete translations, production farm/photo migration and
release signing remain outside the reviewed backend's capabilities.

The small brace-only changes in `photo_evidence/photo_picker.dart` remove existing
analyzer notices without changing its metadata validation. This file is also a
potential presentation-branch overlap to reconcile.

React-specific review skills target TSX and were not applied to Dart. Sites and
inline-visualization skills do not implement this repository's Flutter widgets;
they were not used to substitute hosted mockups for the application.
