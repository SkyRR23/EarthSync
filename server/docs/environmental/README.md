# Environmental context v1 — 7C draft

This is an additive **proposal for integration review**, implemented as a
standalone FastAPI service and independently testable adapters under
`earthsync/environmental/`. No existing route, dashboard, Rust file, NASA POWER
normalization or v0.2 interface is changed. The integration baseline is
`e0cdaaf875efb376e3081a66826b4b5e21601c67` (`origin/feat/web-demo`).

**Live source acceptance is blocked.** The default service returns explicit
unavailable envelopes, with no environmental numbers. ISRIC currently documents
the REST service as paused. Both ISRIC and Open-Meteo requests failed through
the environment's outbound proxy; its enforced allowlist lacks these hosts.
The included live probe record contains the actual failures, not sample data.
No live soil/weather response or farm/scientific validation succeeded. A paused
service is not silently replaced with unverified WMS sampling.

## Implemented behavior

- `soil.py`: SoilGrids REST query construction; strict geometry, mapped-unit,
  divisor, property and depth validation; mean and Q05/Q50/Q95 retained separately;
  eight properties, six optional standard depth intervals. Missing values stay
  null. Prediction quantiles never become accuracy percentages. Transport is
  explicitly opt-in probe mode while the provider is paused.
- `weather.py`: optional Open-Meteo probe selecting `gfs_global`, nearest cell,
  no elevation downscaling, explicit units, timezone, current temperature and
  humidity, and three daily forecast dates. Current conditions are modeled,
  daily values are forecasts. Unit/time/location checks and freshness policy are
  executable, but missing run/issue identity always withholds live use. The
  generic endpoint's `generationtime_ms` is never used as issue time.
- `vegetation.py`: separate NDVI, EVI and surface-temperature unavailable
  adapters. There is deliberately no numeric MODIS ingestion path without
  independently verified collection, scale/fill/range, matching QA, valid pixel
  support and composite intervals. These are release gates, not completed
  satellite integrations. Terrain and water adapters are deferred.
- `service.py`: independently gathers source envelopes and reports availability
  and present-value counts. Diagnosis, drainage and crop recommendations are
  always null. The farmer-confirmed target does not convert regional estimates
  into field-specific observations.

All numeric values from probe/replay readers have `usable_for_analysis=false`.
Soil `reference_only`/`partial` means numbers were parsed, not that agricultural
use is approved. Weather can retain original dated reference values while its
overall availability is `unavailable`; clients must obey availability and
sample usability, not just test whether a number exists.

## Run and verify

Python 3.12+, using the existing pinned server dependencies; no new dependency.
From `server/`:

```sh
python -m pip install -r requirements.lock
python -m pip install --no-deps -e .
python -m ruff check earthsync tests
python -m ruff format --check earthsync tests
python -m pytest -q tests/environmental
python -m uvicorn earthsync.environmental.api:app --host 127.0.0.1 --port 8001
```

The API is separate from the POWER service on port 8000. No deployment or
dashboard integration is included. Machine-readable request/response schemas
are exposed through `/openapi.json`, with `/docs` for local exploration.
See [the contract](CONTRACT.md) for request examples and acceptance semantics.

Explicitly probe live provider connectivity (one request per source; use a new
output filename each time):

```sh
python -m earthsync.environmental.probe --latitude 16.87 --longitude 96.2 --timezone Asia/Yangon --output /tmp/earthsync-environmental-probe.json
```

Exit 1 means at least one source is unavailable; it is the expected result in
this environment. Probe mode is only constructor injection/this explicit CLI;
it does not enable numeric production responses in the default API. Output
includes sanitized query, UTC attempt/retrieval times, HTTP status when known,
response hash/ETag/Last-Modified when retrieved, and per-source reasons. Raw
responses are not persisted; `raw_reference` remains null, and a hash alone is
not an independently replayable capture. Before source acceptance, extend the
verification collection to retain immutable original bodies and metadata.

## Cache, failure and freshness policies

Each adapter owns its own bounded, per-process 64-entry LRU and miss lock.
Keys include exact coordinates, depth selections or timezone, variables, units
policy, endpoint and model selector. Farm IDs and approximate-user locations
never contaminate source cache identity; the request's target is attached only
in the outer response. Hits preserve original retrieval timestamps and response
hashes, return deep copies, and are never described as new retrievals.

Soil's 24-hour refetch interval is an operational cache choice for static
reference data, not a scientific observation date or proof of latest release.
Dataset release and native cell geometry remain unknown; the API version and
HTTP ETag are not substituted for a release. Refreshes retain new response
hashes instead of silently combining revisions. Unit/depth/property drift fails
closed. Soil probes are limited to five attempts per minute per adapter,
including failures; cache hits do not consume that budget.

Weather's configured cache cap is 15 minutes, but **no generic weather response
is cached** while run identity is unavailable. Future acceptable envelopes
would also be checked against their UTC expiry on every hit. The implemented
`weather-probe/1` policy bounds retrieval age to less than one hour and issue age
to less than twelve hours, and expiry to the horizon end. These are application
verification choices, not a forecast-quality guarantee or an approved live
operational policy. Missing timing remains unknown; expiry is exclusive, so a
value is stale exactly at the deadline. No stale fallback is served after a
refresh failure. An old forecast never becomes an observation.

HTTP clients use 20-second read and 5-second connect timeouts, with a 25-second
total transport deadline, 2 MB decompressed body cap, TLS verification, no
redirects, retries or upstream error-body reflection. JSON duplicate keys and
nonfinite constants are rejected. Failures are not cached. Static unavailable
adapters make no requests. Source errors affect that envelope; they never invoke
POWER or invent substitute variables. Public ingress would additionally need
request/concurrency limits, authentication and location retention policy;
loopback is the documented execution mode. Caches and budgets are independent
across workers and reset on restart.

## Release gates and limitations

1. Restore/verify SoilGrids access, or implement the provider-recommended WCS/
   native-raster alternative with its original metadata. Capture immutable raw
   responses, source release and native pixel extraction/footprint. Revalidate
   response schema and conversion semantics on independent live captures before
   considering production enablement. Missing uncertainty must remain explicit.
2. Obtain a documented weather model/run issue-time chain and reviewed freshness
   policy, capture and replay it, check actual grid/time metadata, and confirm
   the applicable Open-Meteo commercial access plan before production use.
3. Satellite numeric work requires matching QA and documented acceptance policy,
   valid pixel counts, native footprint, exact temporal support and scales from
   the same product/collection. No PR #11 MODIS numeric conclusion is allowed.
4. Integrators must agree the new versioned contract. This proposal changes no
   other team's interface. Boundary aggregation and field photos are not
   implemented in v1; they must retain separate evidence and geometry semantics.

The implementation does not provide a fully live-validated soil adapter or a
live weather service yet. Its delivered value is working conservative readers,
transport probes, evidence/availability API, automated tests and traceable
release blockers. Tests demonstrate software behavior using explicitly synthetic
provider-shaped inputs. They do not establish environmental accuracy, crop
suitability, farm representativeness, browser/Android behavior or live API success.
