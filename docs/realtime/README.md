# EarthSync real-time candidate

Baseline: **660b479c3ffb714cd1d489e1241c026ceae6ed67**, combined PR #29.
Branch: `feat/earthsync-realtime-final-v1`. Independent worktree:
`EarthSync-Realtime`. PR #31 adds validation, rather than a newer runtime; its
unfinished work is not a dependency. #28/#30 handoffs and #29's 11 successful
workflows were rechecked before selecting this baseline. Main remains unchanged.

Open **Real-time EarthSync** from the dashboard, field map or rotation workspace.
Select the public Ames reference or the selected confirmed field. Field links
retain the exact farm revision; nearby stations and regional grids never become
sensors installed in that field. Existing map, polygon/history, priorities,
baseline/A/B, save/reopen, photos, deterministic assistant and NASA POWER/Rust
workflows remain available.

The local FastAPI process monitors sources; Flutter reads the SQLite cache every
15 seconds. Browsers never receive Earthdata credentials or download NASA assets.
Closing the backend stops monitoring. Nothing is publicly deployed.

## Implementation and evidence

- [Live data matrix](LIVE_DATA_MATRIX.md), [Ames station coverage](AMES_PROVIDER_COVERAGE.md)
- [Forecasts and alerts](FORECASTS_AND_ALERTS.md), [refresh/latency](REFRESH_AND_LATENCY.md)
- [NASA recovery](NASA_DATA_RECOVERY.md), [authentication/errors](PROVIDER_AUTH_AND_ERRORS.md)
- [Verification](VERIFICATION.md), [scientific limitations](SCIENTIFIC_LIMITATIONS.md)
- [Windows startup/retest](WINDOWS_LOCAL_TESTING.md), [user actions](USER_ACTIONS_REQUIRED.md)
- [Historical branch integration/conflict contract](HISTORICAL_BRANCH_INTEGRATION_CONTRACT.md)

Machine-readable evidence is under `evidence/`. Those allowlisted summaries refer
to public reference locations. Original private runtime databases, photos, browser
state, authenticated responses and signed URLs are excluded from Git.

## Reproduce bounded live checks

Use Python 3.12, Flutter 3.44.0, Rust 1.99.0 and the included dependency locks.
Run from this checkout with `PYTHONPATH` set to its absolute `server` directory.

```bash
python -m pip install -r server/requirements.lock
python scripts/realtime_smoke.py --directory /private/new-smoke --all-locations
python scripts/realtime_nasa_access.py --directory /private/new-nasa-access --authenticated
```

Use new private directories outside the checkout. Configure `EARTHDATA_TOKEN`
securely before authenticated checks. A successful range-access probe is **not**
numeric scientific acceptance; the running adapters must read/validate the actual
pixels/cells. `realtime_smoke.py` exits nonzero on a covered mandatory weather
failure, records NASA states separately, and never substitutes captured fixtures.

The normal source/staging launchers enable the worker automatically. Set
`EARTHSYNC_REALTIME_ENABLED=0` to disable it explicitly. Factory-level unit tests
default to disabled monitoring so offline tests do not accidentally call providers.

## Recovery and rollback

Use independent private platform and workspace directories. The only database
migration is additive `040_realtime.sql`; existing migrations, source catalogs,
scientific hashes and Rust equations are unchanged. Latest source state and HTTP
validators share the platform database and its existing backup/restore boundary.
Stop both services before a complete platform/object/workspace backup. Restore to
new directories, check integrity and ownership, then start against the restored
copies. Never point this branch at another chat's database or Windows private store.

Rollback to the baseline uses its original private-state backup. Do not remove an
applied migration or rewrite its checksum. No automatic main merge is authorized.
