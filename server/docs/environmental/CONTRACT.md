# environmental-context/1.0-proposal

For the integration team: this additive contract is for review; no Flutter,
Rust or current POWER mapping is changed. Use `POST /api/environmental/v1/context`
and preserve both outer context and per-source envelope schema versions.
Unsupported/ambiguous inputs return HTTP 422. Successfully reporting missing
data returns HTTP 200 with explicit source-level unavailable reasons.
Health is process liveness only, with `upstream_checked=false`.

Example selected-area request (Iowa is an example, not a coverage restriction):

```sh
curl --fail http://127.0.0.1:8001/api/environmental/v1/context \
  -H 'Content-Type: application/json' \
  --data '{"schema_version":"environmental-context/1.0-proposal","target":{"kind":"selected_area","representative_point":{"latitude":42,"longitude":-93},"bbox":[-94,41,-92,43]},"timezone":"America/Chicago","soil_depths":["0-5cm","15-30cm"]}'
```

Confirmed farm request:

```json
{
  "schema_version": "environmental-context/1.0-proposal",
  "target": {
    "kind": "confirmed_farm",
    "field_id": "farmer-field-123",
    "farmer_confirmed": true,
    "point": {"latitude": 16.87, "longitude": 96.2}
  },
  "approximate_user_location": {"latitude": 16.8, "longitude": 96.1},
  "timezone": "Asia/Yangon",
  "soil_depths": ["0-5cm"]
}
```

`approximate_user_location` is optional and is echoed independently; it never
selects the farm point or enters a provider query. Clients should omit it when
unnecessary. The API accepts all valid global WGS84 coordinates. An area's
optional bbox is `[west,south,east,north]` and must contain its representative
point; west > east represents an antimeridian crossing. Only that representative
point is sampled. It is not a spatial area average or proof of whole-area
coverage. This version accepts confirmed farm points, not boundaries; unsupported
boundary/photo properties are rejected rather than silently sampled or promoted
to farmer confirmation. A photo's optional GPS metadata must stay in a future
separate photo-evidence contract.

The response contains:

| Field | Meaning |
| --- | --- |
| `schema_version`, `as_of`, `query` | Contract version, evaluation UTC time, exact validated target and options |
| `evidence[]` | Independent soil, weather, NDVI, EVI and surface-temperature envelopes |
| `situation.availability` | Per-source `reference_only`, `partial` or `unavailable`; never an agricultural condition |
| `situation.present_value_counts` | Count of present reference values, not count of usable samples or confidence |
| `situation.field_specific_evidence` | `not_supplied`; farmer confirmation only identifies a target |
| `situation.agricultural_diagnosis`, `drainage`, `crop_recommendations` | Always null; no approved inference exists |

Each `environmental-evidence/1.0-proposal` includes source/product/API versus
release/model identity, documentation/license/attribution, request and UTC
retrieval metadata, body digest and HTTP validators when available, query versus
returned point, nominal resolution versus unknown native footprint, extraction
method, time support and freshness, original versus converted values and units,
quality counts/reasons, uncertainty state and limitations. A missing raw capture
or native footprint is explicitly null. `cache_hit` never changes retrieval time.
Every spatial support has `scope=regional_context` and
`on_farm_measurement=false`, including a farm-target query.

Each value retains data kind (`observed`, `modeled`, `forecast`,
`farmer_reported`, `synthetic`), variable, statistic, depth, temporal interval,
original units, conversion scale/offset, quality (`present`, `missing`,
`rejected`) and reason. No absent numeric value is encoded as zero. A genuine
source zero remains zero. A rejected finite raw code may be retained in
`original_value` while `value=null`. Unknown original units are null rather
than asserted from an expected output unit. Zero expected records on an
unavailable envelope means no samples were retrieved, not no environmental
condition was expected or a healthy state.

All values in this proposal are `usable_for_analysis=false`. Soil reference
values never populate farmer texture/drainage inputs. Weather numbers, when
present in an explicit probe, remain unusable without verified run timing.
Consumers must preserve the unavailable reason and quality state instead of
rendering a favorable icon, recommendation or alert absence. Never coerce
unknown context to existing engine enums or use it as POWER history.

See [sources](SOURCES.md) and [operational limitations](README.md). Automated
contract tests cover strict request shapes, global coordinates, farm confirmation,
area mismatch, null handling, partial API responses and unavailable defaults.
