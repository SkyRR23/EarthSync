# Farmer assistant (7F)

Opt-in implementation based on `origin/feat/web-demo` at
`e0cdaaf875efb376e3081a66826b4b5e21601c67` (verify the full SHA with `git rev-parse e0cdaaf`).
The assistant explains supplied evidence with deterministic intent routing and
curated English/Spanish catalogs. No LLM, downloads, keys, GPU, external fetches,
autonomous actions, diagnosis, new crop requirements, rankings, or yield estimates.
It has no server-side conversation history or database. The Flutter view keeps at
most 30 turns in memory and clears them when its context, language or service changes.

## Run the complete basic flow

From the repository root, using Python 3.12 and the baseline's Flutter 3.50 / Dart 3.12:

```sh
python -m venv /tmp/earthsync-assistant-venv
/tmp/earthsync-assistant-venv/bin/python -m pip install -r server/requirements.lock
/tmp/earthsync-assistant-venv/bin/python -m pip install --no-deps -e server
/tmp/earthsync-assistant-venv/bin/python -m uvicorn earthsync.assistant.api:app --host 127.0.0.1 --port 8001
```

In another terminal:

```sh
cd app
flutter pub get
flutter run -d chrome --web-port 8081 --target lib/assistant_demo.dart --dart-define=ASSISTANT_URL=http://127.0.0.1:8001/api/assistant/v1/chat
```

The standalone demo starts with **no selected farm or area and no supplied
measurements**. Suggested questions work without a model or provider connection.
The HTTP service must be running. Failures show retry; they never load a demo or
replace evidence. An Android emulator can use `10.0.2.2:8001` for the host;
no Android or browser validation is asserted here. The standalone API allows only
`http://localhost:8081` and `http://127.0.0.1:8081` for local browser CORS. For another
origin, the service owner can call `create_assistant_app(allowed_origins=(... ,))`.

A deterministic HTTP request, including an explicitly missing rainfall value:

```sh
curl --fail-with-body http://127.0.0.1:8001/api/assistant/v1/chat -H 'Content-Type: application/json' --data-binary @docs/assistant/request.v1.json
```

## Embed without changing 7A navigation

7A owns how this screen is reached. No onboarding, router, providers, results,
NASA client, Rust/FRB, or engine source files were edited. Import these new modules:

```dart
import 'package:earthsync/features/assistant/assistant_client.dart';
import 'package:earthsync/features/assistant/assistant_context_adapter.dart';
import 'package:earthsync/features/assistant/assistant_models.dart';
import 'package:earthsync/features/assistant/assistant_screen.dart';

final context = assistantContextFromAnalysis(
  contextId: 'selection-a:2024-02:revision-1',
  selectedArea: AssistantSelection(
    id: 'selection-a',
    point: const AssistantPoint(42.0, -93.0),
  ),
  analysis: analysis, // optional; must match the explicit selected coordinates
  farmerInput: farmerInput, // optional; retained as farmer-reported, unverified
);
final service = HttpAssistantService(
  endpoint: Uri.parse('https://your-backend.example/api/assistant/v1/chat'),
);
final screen = FarmerAssistantScreen(context: context, service: service);
// FarmerAssistant(context: context, service: service) is the embeddable component.
```

Use `confirmedFarm` only after farmer confirmation; an approximate user location
belongs in `approximateLocation`. Area and farm selection IDs must differ. Supply a
new `contextId` when location, dates, evidence or findings change. Contexts snapshot
all lists; any content change also clears the view even if the caller mistakenly
reuses an ID. Generation checks discard late responses from earlier contexts.
Create a stable service instance outside the host's build method.

The adapter carries Rust climate calculations, monthly rainfall, dates, units,
quality, retrieval mode and original NASA request links from `IntegrationTrace`.
It rejects a different selected location or climate-kind provenance. Gridded
climate always stays **regional**, including when a farm point is confirmed.
Without a trace, original URLs/dates may be missing; values are then withheld by
the service instead of receiving invented provenance. Farmer reports remain
unverified and are available in the details for the “next information” intent.

`assistantFindingsFromRust` consumes existing legacy integration and
`0.2-provisional` result envelopes without changing either interface. It preserves
scenario order and original whole-scenario status. v0.2 factor evidence strings
are not misrepresented as IDs in the assistant's evidence registry. Current Rust
source records have citations but no original-URL field: the adapter leaves their
links null and the service visibly marks incomplete provenance. Add reviewed
provider links through the proposed assistant context only after agreement with
the source owner. No supported status is promoted into crop suitability.

Soil, vegetation, radar, farmer reports and photos can be supplied directly as
`AssistantEvidence`, with their own kind, unit, dates, location scope, source IDs,
limitations and quality. Photos may have no location; they never establish farm
confirmation or become soil measurements. No unverified external adapters were
introduced. The assistant cannot fetch current conditions, forecasts or imagery;
those must arrive as typed, sourced records from their owning components.

For integration by the backend owner, mount the opt-in router in the existing app:

```python
from earthsync.assistant.api import router
app.include_router(router)
```

Until that owner integrates it, run the standalone service above. A deployed service
should inherit the host's request-size limits, authentication, TLS and logging
policy. Do not log request bodies: they can contain precise farm locations and
farmer answers. Source URLs are returned as text and are never fetched by this service.

## Contract proposal and response behavior

`assistant.v1-proposal` is a **new opt-in contract proposal**, not a modification of
NASA `1.0-proposal` or Rust v0.2. Integration owners should review it before wiring
shared flows. [request.schema.json](request.schema.json) and
[response.schema.json](response.schema.json) are generated from the Pydantic models;
[request.v1.json](request.v1.json) / [response.v1.json](response.v1.json) are shared
Python/Dart contract fixtures, explicitly software examples with no measured data.

| Record | Meaning |
| --- | --- |
| Context | Revision ID; separate approximate user location, selected area and confirmed farm; evidence, Rust findings, sources, limitations |
| Evidence | ID, topic/metric, value or null, unit, kind, dates, retrieval timestamp, spatial support, scope/location ID, quality, source IDs, limitations, optional Rust calculation attribution |
| Source | Local source ID, original provider, citation title, optional HTTPS link; no URL is invented |
| Decision | Original scenario ID/status, sources, linked evidence, limitations, synthetic flag; no new eligibility computation |
| Claim | General explanation, supplied fact, deterministic Rust calculation, or unavailable evidence; precise evidence/source ID references |
| Response | Same context ID/language, intent, claims, cited source registry, original evidence/findings, warnings, suggested questions |

IDs are unique per collection. Unknown keys, unsupported versions, invalid dates,
nonfinite values, unitless numbers, invalid coordinates, open boundary rings and
unavailable records with values are rejected. Missing citation IDs are accepted as
missing evidence and reported, not silently repaired. Original links must be HTTPS
and omit credentials. An original link's presence does not prove its trustworthiness.

Numerical explanations require a recognized metric/unit pair, available quality,
non-synthetic kind, source links, dates, spatial support and matching location.
Otherwise the record remains unknown or needs review. Comparison only groups
records with the same metric, unit, dates, kind, scope, location and spatial support.
Disagreeing comparable values are not selected or averaged; a warning appears even
when the contradiction falls outside the short view. Different periods, observed
versus modeled products and different footprints are not silently combined.

Default responses show at most two relevant evidence records and two findings;
expanded explanations include the rest. Original limitations, spatial-support text,
farmer text, source titles and unknown metrics appear in explicitly labeled details,
never as instructions or validated measurements. Provider content cannot select
system instructions, run tools, change decisions or execute HTML/Markdown.

Localization uses `server/earthsync/assistant/locales/{en,es}.json` and
`app/lib/features/assistant/l10n/`. Routing terms stay in `service.py`; agricultural
explanations stay in catalogs. English/Spanish are the initial supported languages,
not claims of local agronomic or native-speaker validation. Burmese and other
languages can be added without changing agricultural logic or geographic coverage.

## Verification

Exact commands from the repository root:

```sh
PYTHONPATH=server /workspace/.earthsync-python/bin/python -m pytest -q server/tests/assistant
/workspace/.earthsync-python/bin/ruff check server/earthsync/assistant server/tests/assistant
/workspace/.earthsync-python/bin/ruff format --check server/earthsync/assistant server/tests/assistant
git diff --check
```

Portable equivalent after the installation above:

```sh
python -m pytest -q server/tests/assistant
python -m ruff check server/earthsync/assistant server/tests/assistant
python -m ruff format --check server/earthsync/assistant server/tests/assistant
cd app
flutter pub get
dart format lib/features/assistant lib/assistant_demo.dart test/assistant
flutter analyze --no-fatal-infos lib/features/assistant lib/assistant_demo.dart test/assistant
flutter test test/assistant --reporter expanded
flutter build web --target lib/assistant_demo.dart --no-wasm-dry-run
```

The added CI workflow runs the backend checks, Flutter analysis, assistant tests
and standalone web build. Tests cover missing sources/links, contradictory evidence,
unknown soil, unrelated and malicious text, API outages, approximate location,
location changes, global example coordinates, citations, old replies, raw v0.2
statuses, optional photo location and English/Spanish routing. The implementation
session's actual results and tooling limitations are recorded in the draft PR;
a test's presence is not a claim that it ran successfully.
