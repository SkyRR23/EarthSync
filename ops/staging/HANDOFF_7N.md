# 7Q operations handoff to 7N

Operations branch: `ops/earthsync-staging-v1`, based on the explicitly supplied
7H SHA `a7c33cc6b58703501bbba0ceba1bad1d6d42004b`. All changes are under
`ops/staging/`; there are no application, migration, router or shared launcher
edits. Cherry-pick the operations commit or merge after review as appropriate.
No 7I/7L application merge is performed here.

The scripts accept a clean independent `--source`, explicit full `--sha` at build,
and private `--state`. They reuse `earthsync.web_demo:app` and
`earthsync.platform_v1.api:app_factory`, the existing immutable migrations,
the actual web_engine/v03_demo CLIs and 7I maintenance. Separate web/platform
venvs preserve their incompatible Pillow pins. The standalone 7I compatibility
export/snapshot is the approach already documented by its owner.

Please supply/resolve these before final release acceptance:

- Full reviewed final RC SHA, chosen Flutter SDK/lock (7H CI says 3.50.0; 7L narrative says 3.44), and any approved combined Python lock (Pillow 12.2.0 versus 12.0.0).
- Final process and route layout. If you mount platform into another app, retain 7I lifespan/jobs/shutdown and loopback/Host/Origin checks. Do not bypass them through a public parent/proxy. These operations scripts currently run the existing separate entrypoints rather than inventing a combined app.
- Confirm which UI actions persist 7I farms, evidence, history and decisions. Current 7H/7L workspace/browser farms and private photos do not automatically map to 7I owner/farm IDs. This is an integration acceptance gate, not something ops silently migrates.
- Keep separate photo storage models explicit: 7H image BLOB DB + token; 7I DB + object files. Backups and rollback must include the matching store. No shared token is a production account system.
- Candidate-specific browser acceptance for the final 7L navigation, 7I ownership/association and real provider outages. Existing 7H browser runner is documented, but complete candidate UI remains unverified by this PR's HTTP checks.
- Migration compatibility on a backup copy and the exact permitted restricted demo features. Public multi-user private access remains blocked without reviewed identity and authorization.

Locally verified 7I operations: pinned dependency installation and compiled Rust,
actual loopback Uvicorn readiness, uncached NASA daily historical provenance,
farm/evidence/decision/photo persistence across service restart, complete offline
backup/restore, injected migration failure recovery, quotas and private POSIX
permissions. See [verification](VERIFICATION.md) for exact scope/results.

No personal or team server has been accessed. No external deployment occurred.
The final RC build, full Flutter/browser/device acceptance and destination-specific
deployment approval are outstanding. The deadline is November 15 at 18:00 Myanmar
time; retain the restricted known-working demo and rollback if any release gate
is incomplete.
