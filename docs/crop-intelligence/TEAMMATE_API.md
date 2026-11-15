# Teammate research API

This is a **separate service**, not an authentication bypass on the current
farmer backend. Use a synthetic tenant/farm. Never expose the local platform port
or its workspace master token. The Research API has no access to farmer records.

## Current teammate hosts (user supplied)

* Public existing backend: `https://fieldshift-yangon-2026.web.app`
* Test preview: `https://fieldshift-yangon-2026--test-87chcuks.web.app`
* Teammate local development: `http://127.0.0.1:8000`

On 2026-11-15, both Firebase `/api/v1/health` endpoints returned HTTP 200:
`{"status":"ok","service":"earthsync-climate","upstream_checked":false}`.
The test host's `/openapi.json` and `/api/v1/openapi.json` returned 404.
An actual test-host health GET with Origin `http://127.0.0.1:8091` returned no
`Access-Control-Allow-Origin` header.
The user reports legacy `/api/v1/environment/season` and `/api/v1/soil/estimate`
routes, public access without keys and no cross-origin browser support.
No unknown-input environment/soil request or private image was sent to these hosts.
The user explicitly prohibits using the `run.app` address; it was not used.

Health success does not prove upstream availability or install the new API.
The new authenticated image/RAG service has not been deployed to either host.
Hosting permission, a reviewed deployment configuration and a private test key
are still needed before authenticated hosted compatibility can be established.
Connect backend-to-backend; CORS does not constrain server-to-server HTTP.
Never embed a research key in Flutter, Firebase public assets or browser JavaScript.

## Start locally

From the repository root, Python 3.12+, use the existing pinned dependencies:

```sh
python -m pip install -r server/requirements.lock
export PYTHONPATH="$PWD/server"
export EARTHSYNC_RESEARCH_DIR=/tmp/earthsync-research-private
export EARTHSYNC_RESEARCH_LOCAL=1
python -m earthsync.research.cli --directory "$EARTHSYNC_RESEARCH_DIR" provision \
  --tenant synthetic-teammate --subject developer \
  --scope crop:evidence:read --scope photo:upload --scope photo:read \
  --scope photo:analyze --scope photo:delete --scope lab:extract --scope lab:confirm \
  --scope soil:reference:read --hours 24 \
  --secret-file /tmp/earthsync-test-credential.json
python -m uvicorn earthsync.research.api:app_factory --factory \
  --host 127.0.0.1 --port 8031 --workers 1 --limit-concurrency 12 \
  --no-proxy-headers --no-access-log --timeout-keep-alive 5
```

Use an owner-only private state directory and a new private secret-file path;
both must be outside Git. CLI stdout contains key ID, farm ID, expiry and scopes,
never the token. The token is written once to the requested private file. Transfer
through the team's approved secret manager. Maximum expiry is 31 days.

Interactive OpenAPI: `http://127.0.0.1:8031/docs`; **Authorize** using the private
test token on a trusted local computer. Authorization is not persisted by Swagger.
The published schema has `x-required-scopes` and a shared `ResearchError` schema.
API documentation may be read without a token; every research operation requires one.
No token-in-URL or query-key authentication exists.

Run the actual client (no credential printed):

```sh
python server/examples/research_client.py \
  --base-url http://127.0.0.1:8031 \
  --credential-file /tmp/earthsync-test-credential.json
```

Expected output includes `crop_evidence: evidence_available`,
`photo_analysis: unavailable`, `synthetic_photo_deleted: true` and false eligibility.

Revoke immediately:

```sh
python -m earthsync.research.cli --directory "$EARTHSYNC_RESEARCH_DIR" revoke KEY_ID
```

For key rotation, provision with the same tenant/subject and `--farm FARM_ID` to
grant the existing test farm; omit `--farm` to create a new synthetic farm.

## Versioned endpoints

All paths are under `/api/research/v1`. Authentication uses an Authorization
Bearer header, plus the exact farm grant for private operations.

| Method/path | Required scope | Input |
|---|---|---|
| GET `/health` | Valid key | none |
| POST `/crops/search` | `crop:evidence:read` | `{"query":"rice"}` |
| POST `/crops/evidence` | `crop:evidence:read` | `{"crop":"rice","question":"soil pH"}` |
| POST `/crops/compare` | `crop:evidence:read` | `{"crops":["rice","maize"],"question":"water"}` |
| POST `/photos?farm_id=UUID` | `photo:upload` | raw JPEG/PNG body with matching Content-Type |
| GET `/photos/UUID/image?farm_id=UUID` | `photo:read` | none |
| DELETE `/photos/UUID?farm_id=UUID` | `photo:delete` | none |
| POST `/photos/UUID/analyze` | `photo:analyze` | `{"farm_id":"UUID","external_image_consent":false}` |
| POST `/lab-reports/extract` | `lab:extract` | `{"farm_id":"UUID","photo_id":"UUID"}` |
| GET `/lab-reports/UUID?farm_id=UUID` | `lab:extract` | none |
| POST `/lab-reports/UUID/confirm?farm_id=UUID` | `lab:confirm` | explicit checked sample, see below |
| POST `/soil/context` | `soil:reference:read` (+ `lab:extract` when report IDs supplied) | farm ID, report IDs, optional bounded farmer reports |

`photo:analyze` and `lab:extract` authorize their respective processing of pixels;
they do not grant downloading or deleting images. Responses do not enumerate farms.

Example manual confirmation:

```json
{
  "confirmed": true,
  "document_kind": "laboratory_report",
  "sample_id": "SYNTHETIC-1",
  "values": [{"parameter":"ph","value":6.4,"unit":"pH",
    "method":"water","depth":"0-15 cm","source_locator":"image 1, pH row"}]
}
```

This is a software example, not a real measurement. Responses retain `original`
and `confirmed` separately. A confirmation is not laboratory authentication.

Errors: `{"error":{"code":"SCOPE_FORBIDDEN","retryable":false}}`.
401 missing/invalid/expired/revoked; 403 scope/Host/Origin/HTTPS; 404 unauthorized or
missing resource; 413 size; 422 invalid input/image/consent; 429 rate; 507 storage.
Synchronous extraction may take up to 20 seconds. There is no jobs endpoint.
Future incompatible contracts require `/v2`; additive optional fields remain v1.

## Before external testing

Deploy the reviewed Research API separately with persistent private storage,
HTTPS, exact `EARTHSYNC_RESEARCH_HOSTS`, restricted Origins (or none for backend
clients), secure secret transfer and one worker for this MVP. Unset
`EARTHSYNC_RESEARCH_LOCAL`. Preserve TLS validation. Forwarded headers must be
trusted only from an explicitly reviewed proxy. The repository does not change
Firebase routing, billing, DNS, accounts or deployment protection automatically.
Run the sample client against the approved HTTPS research URL only after deployment.
