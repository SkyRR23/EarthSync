# Third-party source register — foundation increment

The EarthSync shield/leaf logo in `app/assets/branding/earthsync-logo.png`, the
Android launcher resources and Web icon was supplied by the project owner on
2026-11-15. The supplied PNG is used unchanged; no stock-art license is asserted.

No final project license has been selected. Team confirmation is required.
This is an initial register, not a complete distribution license bundle.

| Component | Source / version | License / disposition |
| --- | --- | --- |
| Rust dependencies | https://crates.io/crates/serde and https://crates.io/crates/serde_json; exact direct/transitive versions in `engine/Cargo.lock` | MIT OR Apache-2.0 for these direct crates; retain selected licenses and audit transitive notices before binary release. No vendored sources in this increment. |
| OpenFarm research | https://github.com/superzero11/OpenFarm/tree/884a61567dd0d149214090baf9edebc533a2a0df | Root BSD-3-Clause, copyright 2026 OpenFarm Contributors. Source inspection only; no copied/adapted code or data. Preserve complete required notices if later reused. |
| Demo fixture | `engine/tests/fixtures/synthetic_field.json` | AI-assisted project test data; synthetic, unmeasured. No NASA or agronomic dataset attribution claimed. |
| NASA POWER (planned) | https://power.larc.nasa.gov/ | Not acquired in this increment. P2 must record actual product, dates, units, scale, retrieval and applicable terms before demo use. |
| NASA GIBS (planned) | https://www.earthdata.nasa.gov/topics/visualization/worldview | No imagery included. P2/P4 must record chosen layer, date, attribution and terms. |

Before release, add all shipped code/data/text/image assets, exact versions and
URLs, transformations, required attribution text and redistribution decisions.
OpenFarm's root license does not license upstream datasets or dependencies.
No NASA logos or mission insignia were generated.

## Flutter app (`app/`, P4) — shipped assets and packages

| Component | Source / version | License / disposition |
| --- | --- | --- |
| Inter font (400/500/600/700, latin subset) | Fontsource `@fontsource/inter` 5.2.5 via cdn.jsdelivr.net; bundled in `app/assets/fonts/` | SIL Open Font License 1.1 (Rasmus Andersson). Bundled unmodified; include OFL text in release notices. |
| OpenStreetMap tiles | `tile.openstreetmap.org`, loaded at runtime (not bundled) | ODbL data; attribution "© OpenStreetMap contributors" shown in app. Light demo use only per OSM tile usage policy; switch provider for wider release. |
| NASA GIBS imagery | `MODIS_Terra_CorrectedReflectance_TrueColor`, GoogleMapsCompatible_Level9, loaded at runtime (not bundled) | NASA open data; source, layer and date shown in app. Provisional layer until P2 confirms. |
| NASA GIBS layer `MODIS_Terra_NDVI_8Day` | GoogleMapsCompatible_Level9, loaded at runtime (not bundled) | NASA open data, attribution "NASA EOSDIS GIBS" shown in app. |
| OpenFarm | superzero11/OpenFarm, commit `884a61567dd0d149214090baf9edebc533a2a0df` | BSD-3-Clause; design reference only, no code copied. |
| `shared_preferences` | 2.5.6 (https://pub.dev/packages/shared_preferences) | BSD-3-Clause (Flutter Authors) |
| `geolocator` | 14.1.2 (https://pub.dev/packages/geolocator) | MIT (Baseflow) |
| `share_plus` | 13.3.1 (https://pub.dev/packages/share_plus) | BSD-3-Clause (Flutter Community) |
| `firebase_core`, `firebase_auth`, `cloud_firestore` | 5.1.0 / 7.0.1 / 7.1.0 (pub.dev, FlutterFire) | BSD-3-Clause (Google). Runtime service: Firebase project `fieldshift-yangon-2026`; Google sign-in; Firestore in asia-southeast1. |
| Flutter packages | Exact versions in `app/pubspec.lock`: flutter_riverpod, go_router, flutter_map, latlong2, fl_chart, intl, flutter_rust_bridge 2.13.0, cupertino_icons | Permissive (MIT / BSD-3-Clause / Apache-2.0); verify transitive notices before binary release. |

v0.2 P0 fixture register: `engine/tests/fixtures/synthetic_v02_request.json` and
`synthetic_v02_response.json` contain AI-assisted fictional observations, family
names and duration bounds for software tests only. No agricultural dataset or
NASA observation is redistributed by these fixtures. They are not scientific
references or Myanmar recommendations. No new dependency or third-party code added.


## Milestone 7H additions

The integrated application uses the NASA POWER pipeline documented in
`server/docs/NASA_POWER.md`; the earlier planned row describes the historical
foundation increment. Live query receipts and scientific limits are recorded in
`docs/integration/VERIFICATION.md`. No satellite pixels are redistributed.

Roboto Regular and Bold in `app/assets/fonts/` are unmodified fonts bundled with
the official Flutter 3.50.0 Linux SDK archive (SHA-256
`6ea2d806fd57269ae783e6788e2a81fc26eaad782f1e0d0ff38623bb765ff9f5`).
They are distributed under Apache License 2.0; retain
`app/assets/fonts/Roboto_LICENSE.txt`. Bundling them avoids an implicit Google
Fonts request during local-demo startup. Renderer assets come from Flutter's
build tool with `--no-web-resources-cdn`; retain the generated notices.
