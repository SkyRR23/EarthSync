# Milestone 7N final application integration

The complete 7L Flutter interface is reconciled onto final 7H, with reviewed 7J
scientific fixes and the 7Q operations workflow. The usable 7I
backend is connected through a separate private local service. The integration
adds explicit durable farm links, persisted daily evidence, source selection,
actual Rust assessments/history, reported historical periods and cited deterministic
assistant context. It fixes 200/201/202/204 handling and a cache/immutable-JSON
persistence defect found by the live combined test. There is no public deployment.

- [Final measured verification and release limitations](VERIFICATION.md)
- [Exact source pins and Git conflict resolution](CONFLICTS.md)
- [API usage/security/schema/coverage matrix](API_MATRIX.md)
- [Database identity, persistence and photo ownership policy](DATABASE.md)
- [7Q startup, private staging, backup/restore and rollback handoff](HANDOFF_7Q.md)
- [Source/toolchain manifest](source-manifest.json)

Verification receipts are under `evidence/`; final measured results and remaining
release gates are in VERIFICATION.md. Source milestone reports are retained as
historical evidence and are not substituted for this branch's verification.

All crop profiles remain reference-only and recommendation-ineligible. Technical
source-contract review does not validate field applicability. There is no calibrated
suitability ranking, percentage, yield/profit forecast or farming recommendation.
Satellite/soil/forecast acceptance, complete Burmese localization, hosted identity,
consented cross-store photo migration and Android device execution are not claimed.
The Burmese navigation preview remains explicitly unreviewed.

Draft PR: https://github.com/SkyRR23/EarthSync/pull/24. Restricted personal-server
testing is supported through SSH local forwarding; public private-API exposure is
not supported. See the canonical [operations runbook](../../../ops/staging/README.md).
