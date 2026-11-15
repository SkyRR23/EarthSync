# Human actions and unresolved acceptance

## External model

The user explicitly selected **keep external vision disabled; deliver adapters and
offline verification**. No live test is pending authorization in this delivery.
If requested later, first approve account/cost, configure the backend key securely,
verify current model access and consent to each image transfer. Never paste secrets
in chat. Do not enable Qwen, retired Scout or a paid fallback automatically.

## Toolchain access

**BLOCKER:** Local Flutter setup cannot download its Dart SDK (proxy 403).
**WHY:** `storage.googleapis.com` is outside the enforced environment allowlist.
**ACTION:** Add that host in this chat's cloud-environment network settings and
apply it; then rerun Flutter setup, locked dependencies, analyzer, tests and build.
**SECURITY:** No API key is required; keep inherited proxy and TLS verification.
**VERIFICATION:** `flutter --version`, `flutter analyze`, `flutter test`, release Web
build and actual Chromium workflow succeed on the final source.
**CONTINUING WORK:** Python/Rust regression and remote PR CI can run independently.

## Dataset and hosted acceptance

**BLOCKER:** No approved independent image labels, real reports, authorized hosted
research endpoint/credentials or interactive Windows machine are supplied.
**WHY:** Those are required for agricultural accuracy, hosted compatibility and
local Windows acceptance, beyond mocked API and cloud software checks.
**ACTION:** Provide rights-cleared test examples with independent labels via the
approved private file channel; arrange a local Windows retest and an authorized
teammate research deployment URL, TLS/proxy configuration and secure test-key handoff.
**SECURITY:** Keep real reports/keys outside Git and public Firebase assets; transfer
keys only through the team's secret manager. Do not use prohibited deployment hosts.
**VERIFICATION:** Follow IMAGE_EVALUATION.md, run the authenticated sample client
against the approved HTTPS endpoint, and complete the Windows checks below.
**CONTINUING WORK:** The local application, adapters, consent/ownership validation,
deterministic evidence pipeline and software regressions remain reviewable.

## Windows retest

Use Python 3.12+, Flutter 3.44.0, the pinned Rust toolchain and optionally Tesseract.
Install locked dependencies; build both existing Rust examples and Flutter native
bridge, run Python/research/7V/Rust/Flutter suites and release Web build using the
commands in VERIFICATION.md and the inherited crop runbook. Start the app with a
new private directory and `EARTHSYNC_VISION_ENABLED=0`. Test all three categories,
private image preview, vision-unavailable output, real local OCR/manual correction,
explicit appearance history save, restart and stopped-service backup/restore.
Verify directory/file ACLs and that no research token appears in browser assets.
Then test provider consent/errors only if separately authorized. Record actual OS,
versions, source SHA and results; GitHub Windows CI is not interactive acceptance.
