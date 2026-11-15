# Isolation, integration contract and conflict report

This branch starts at **660b479c3ffb714cd1d489e1241c026ceae6ed67** and is independently
runnable. It does not depend on a historical chat, modify its branch/worktree,
rewrite its database, backfill 2024–2025, implement simulation, rebase active work
or merge main. Existing bounded NASA/Rust regression journeys use the inherited
dated fixtures/windows only to verify preserved workflows.

## Additive contracts

- Package `earthsync.realtime`: current provider adapters, bounded source state,
  source scheduler and scientific decoders. Never import simulation fixtures here.
- Migration **040_realtime.sql**, table `realtime_state(key, payload)`, same private
  SQLite and complete backup boundary. Reserve/coordinate migration numbers before
  combining branches; never rename an already applied migration in place.
- `GET /api/platform/v1/realtime/locations`: fixed public references.
- `GET /api/platform/v1/realtime/{location_id}`: cached snapshot only.
- `POST .../realtime/{location_id}/refresh`: 202, schedules due sources only.
- `GET .../farms/{farm_id}/realtime`: owner-checked confirmed revision/context.
- Snapshot contract: **earthsync.realtime.v1**. Every source includes type, status,
  independent observation/check/valid times, original provenance, limitations and
  explicit error. Unknown fields remain null. Numeric NASA hashes have range scope.

Station, satellite estimate, assimilated analysis, official/model forecast, static
reference and farmer reports must remain separate. A historical selection must
never reuse current weather as observations from the selected past period.
Current monitoring does not rewrite immutable saved assessments or promote rules.

## Expected merge conflicts

Shared edits are limited to the platform app factory/lifespan/routes, GFS download
throttling, dependency locks, Docker runtime allowlist, Flutter router/dashboard,
field/rotation navigation and wording that previously claimed all weather absent.
New realtime modules/UI/docs/tests and migration are otherwise separate. The
browser verifier now recovers a Chromium discarded response body by checking the
single newly persisted native decision, without replaying a mutation.

Later integration must preserve both lifespan workers, source cache/backoff,
original privacy/owner checks, current-vs-historical date semantics, all 60 blocked
rules and exact scientific pins. Re-run both branches' meaningful tests against a
restored copy, then obtain the user's authorization for any actual reconciliation
or main merge. No such merge is part of this candidate.
