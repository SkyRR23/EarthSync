# Remaining external/human actions

## Hosted research testing

**BLOCKER:** The supplied Firebase test host serves the existing unauthenticated
climate API; the new authenticated Research API has not been deployed there.

**WHY:** A working health response is not a deployment of this branch or a verified
photo/RAG integration. Both tested OpenAPI paths returned 404. No Firebase account,
routing, secrets or persistent storage configuration was changed.

**USER ACTION:** Review the draft PR with the teammate. Choose a separately
authenticated service/host with persistent private storage and HTTPS, authorize
that deployment, and provide the legacy API schemas if a soil/environment bridge
is desired. Use the provided Firebase test preview for checks; do not use run.app.

**SECURITY:** Provision a short-lived synthetic test tenant key using the CLI and
transfer through the team's secret manager. No secret belongs in chat or Flutter.

**VERIFICATION:** Run `research_client.py` against the deployed research HTTPS URL;
test revoke/expiry, wrong scope/farm and authorized deletion. Health-only success
does not establish this. Existing backend can call it server-to-server without CORS.

**CONTINUING WORK:** All local features/tests, API docs and deployment-neutral
integration contracts are independently reviewable.

## Independent scientific approval

**BLOCKER:** No qualified independent applicability reviewer or field validation
has been supplied for the 60 candidate rules.

**WHY:** References and passing software tests cannot approve field-specific crop
requirements; the original eight gates remain unmet.

**USER ACTION:** Ask an appropriately qualified local agronomist/reviewer to inspect
the original 7V dossiers and the UI's per-domain evidence-needed lists. Record role,
date, decision, crop/cultivar/management/geography and exact approved scope in a
future separately reviewed package. Supply representative field measurements and
validation evidence. Do not simply mark this package approved.

**SECURITY:** Share only authorized, minimized farm/lab records privately.

**VERIFICATION:** Review all eight gates, matching units/depth/statistics/methods,
contradictions and field-validation evidence before executable-rule integration.

**CONTINUING WORK:** Reference explanations and unranked comparisons already work.

## Real report and vision evaluation; Windows

**BLOCKER:** No authorized real lab sample, verified vision provider or interactive
Windows destination acceptance was supplied.

**WHY:** A synthetic OCR example and mocked model boundaries do not establish
real-image accuracy, laboratory authenticity, Windows ACLs or agricultural performance.

**USER ACTION:** Privately supply a consented/redacted report for evaluation and
perform WINDOWS_TESTING.md on the intended machine. Only configure external vision
after confirming model capability, approved data handling and explicit user consent.

**SECURITY:** Keep provider keys in server secret storage; do not paste keys or
unredacted private reports into public GitHub artifacts.

**VERIFICATION:** Compare report values against labeled ground truth, exercise
correction/confirmation and document actual provider/model results separately
from mocked tests. Check local ACLs and backups directly.

**CONTINUING WORK:** Honest unavailable outputs, local OCR/manual entry and safe
private upload remain functional without an external model or new secrets.
