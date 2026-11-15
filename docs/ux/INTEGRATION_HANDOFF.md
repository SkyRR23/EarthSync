# Predecessor integration handoff (archived)

This file records the earlier independent worktree before the user selected
PR #32 as the primary frontend and authorized final main integration. The
[combined submission handoff](SUBMISSION_HANDOFF.md) supersedes its branch,
navigation, integration-status and authorization descriptions below.

Base: `190f4c527d427c6e009c04c9115e0cb49988801a`.
Branch: `feat/earthsync-local-farmer-experience-v2`.
Workspace: `D:\Nasa_spaceApp\earthsync-farmer-experience-v2`.
Final implementation revision is recorded in the PR and `git rev-parse HEAD`; see verification for the recorded delivery revision.

## Review boundaries

The current main ancestry already integrates newer farmer features, private evidence, crop knowledge, NDVI and real-time NASA work. The older PR #32/`feature/flutter-app` was inspected as lineage information, not used to replace the integrated application. The final pre-publication fetch found `feature/flutter-app` at `50826aa9522285c0e002b96e4e2a5c9b09aa856b`, with newer team-design onboarding, HLS greenness, soil-photo and Groq chat commits. Those changes belong to that distinct lineage and were not copied or overwritten. Main remained at the source base. Separate commits `99c0b9d` and `9051a26` in `integration/earthsync-final-realtime-demo` were not automatically merged. Other local checkouts, active services, source datasets and private databases were left unchanged. No main merge, force push or public deployment is authorized or performed.

## Integration points

- `app/lib/state/local_farm_provider.dart`: shared local store, clock, revision and reconciliation providers. Inject an isolated `LocalFarmStore` for tests.
- `app/lib/data/local/`: schema, tasks, photos, export and native reminder adapter. Existing profile IDs/keys remain compatible.
- `journal_provider.dart`: merge local farmer reports with source-dated server snapshots; local-only completed seasons cannot silently enter server Rust history.
- `dashboard_provider.dart`: exact-query NASA cache; changing origin/point/period never reuses another query.
- `app_shell.dart`/router: five primary destinations and retained old routes.
- `SoilFirstMap`: display adapter over the existing soil-map and NDVI contracts. Preserve validation and unknown suitability when integrating newer map work.
- FastAPI: migration 042 and append-only dataset metadata; retain owner/loopback guards.
- Android: desugaring, notification/boot permissions and receivers. No exact alarm or Firebase secret.
- Web: `sqflite_sw.js`/`sqlite3.wasm` are public runtime assets included by `finalize_offline.py`; private endpoints/photos are excluded.
- Launcher: SQLite asset setup, normal farmer onboarding, optional `EARTHSYNC_JUDGES_DEMO=true`, native bridge PATH for full tests. Each checkout uses its own sibling demo-state folder.

## Dependency review

Necessary additions are SQLite native/Web support, local notifications, timezone/device-zone discovery and explicit path/export support. `pubspec.lock` was regenerated with Flutter 3.44, not the newer default SDK. Rust sources/contracts and scientific rule catalogs are unchanged. Generated SQLite worker/WASM assets should be regenerated with the documented package setup when updating that dependency. See `THIRD_PARTY_RUNTIME.md` for provenance.

## Remaining integration boundaries

Optional authenticated task synchronization/conflict resolution, FCM and a production remote-server adapter are unconfigured. The existing platform remains loopback-only. Do not weaken that guard to expose a private development API on a LAN. Native reminders need hardware verification; Web has in-app delivery only. Soil provider availability and prediction uncertainty remain explicit. No agricultural treatment, crop health percentage or approved suitability rule is added.
