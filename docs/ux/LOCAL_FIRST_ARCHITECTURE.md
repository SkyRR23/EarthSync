# Local-first boundaries

The existing profile record (`earthsync.home.v1`) and existing preference keys are preserved. No destructive migration, existing database copy, Firebase requirement or scientific-engine replacement is introduced.

| Component | Offline behavior | Internet/server boundary |
|---|---|---|
| Farm profiles, selected farm and boundaries | Existing SharedPreferences storage | No account required |
| Tasks, recurrences, notes, crop reports, private photos | SQLite on device; SQLite/IndexedDB worker on Web | No server request is required to save or edit |
| Notification history/preferences | Same SQLite store | In-app reconciliation runs while the app is open |
| Android task reminders | Platform scheduler, persisted by the notification plugin | No Firebase/backend requirement; device delivery needs verification |
| Historical NASA POWER | Previously validated responses cached for the exact point, period and origin | Fresh retrieval requires the existing NASA backend |
| Farm evidence and comparisons | Saved snapshot retains source dates, farm revision and origin | Refresh requires the existing private platform |
| Soil raster and satellite discovery | Accepted small saved results only | Existing bounded server processing/provider access |
| Map tiles | Saved boundary/pin remain; uncached tiles show a warning | OSM/GIBS tiles require a provider connection; no bulk tile download |
| Crop reference | Existing licensed packaged references remain | Larger catalogs use existing endpoints |
| Rust | Existing on-device native bridge | Web bridge and larger calculations use the existing local server |
| Cloud synchronization / FCM | Unconfigured | No automatic uploads or delivery claims |

## One new structured store

`earthsync-farmer-v2.sqlite3` is a versioned SQLite database opened through the shared `LocalFarmStore`. Native builds place it in application support storage. Web builds use `sqflite_common_ffi_web` and IndexedDB, with the SQLite worker and WASM included in the public offline shell. A browser must first download the app; an offline first visit to an uncached website cannot install it. Browser storage removal/private browsing/quota restrictions can remove or reject local data; export important records.

Tables: `records`, `photos`, `settings`, `reminder_ids`, `outbox`, `sync_versions`. Farm IDs scope structured records and photos. Updates and recurrence creation use transactions. JSON records and images have explicit size bounds. Original source acquisition dates are retained. Permission failures must not expose retained private server evidence.

The existing small SharedPreferences profile/appearance records remain for backward compatibility. Legacy evidence cache reads are preserved. New structured data is not split across multiple competing task databases.

## Optional synchronization

Each changed entity replaces its pending local outbox operation and retains its stable entity ID and base version. This is preparation for a future reviewed owner-scoped adapter, **not an operational synchronization implementation**. No scheduler uploads the outbox. Remote conflict resolution, retries across authenticated owners, Firebase rules, token registration and FCM sending are intentionally unconfigured. Existing private API writes retain their original explicit confirmation behavior.

Local export includes the farm profile, tasks, notification history, notes, photo bytes/metadata, cached farm evidence and reminder preferences. Selected-farm activity deletion removes those new local records and cached farm evidence, then reconciles native schedules; the saved boundary and original server records are explicitly retained. Existing cloud/server deletion controls remain separate.

## Data minimization

Only the public application shell goes into Cache Storage. Private APIs, photos, tokens and arbitrary map tiles are excluded from the offline service worker. Small evidence is stored explicitly in the application database/cache. Global rasters, ECOCROP archives, scientific source databases and server state are not mobile assets. Provider cache/redistribution policy must be reviewed before adding a downloadable dataset.
