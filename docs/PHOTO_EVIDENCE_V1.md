# Photo and satellite evidence v1 (proposed integration contract)

Branch: `feat/photo-sar-evidence`, based on fetched `origin/feat/web-demo`
`e0cdaaf`. This is an additive private-workspace service and Flutter component;
7A's onboarding/dashboard routes, NASA POWER, Rust, FRB and v0.2 interfaces are
unchanged. Integration into the farm registry or dashboard requires their owners'
review of this small `evidence.v1` contract. No farm registry interface is invented.

## Run the photo upload/viewer slice

From the repository root (Python 3.12+):

```sh
python -m venv /tmp/earthsync-photo-venv
/tmp/earthsync-photo-venv/bin/pip install -r server/requirements.lock -r server/requirements-evidence.lock
export EARTHSYNC_EVIDENCE_TOKEN="$(/tmp/earthsync-photo-venv/bin/python -c 'import secrets; print(secrets.token_urlsafe(32))')"
export EARTHSYNC_EVIDENCE_DIR=/tmp/earthsync-private-evidence
# Optional, exact browser origin only; choose the port used below.
export EARTHSYNC_EVIDENCE_ORIGINS=http://localhost:8018
cd server
/tmp/earthsync-photo-venv/bin/uvicorn earthsync.evidence.app:create_app --factory --host 127.0.0.1 --port 8017
```

The service fails closed without a private token (at least 32 ASCII characters)
and an absolute private storage directory. One token authorizes **one whole
workspace**; it is not shared multi-user authentication. Run separate stores/tokens
for separate farmers. Before public deployment, the authentication owner must
map authenticated farmers to isolated stores and verified farm ownership. Use TLS,
a trusted origin, a request-size limit and concurrency/rate limits at that ingress.
Do not embed workspace tokens in a distributable Flutter app or build flag.

The independent Flutter harness does not touch the app router:

```sh
cd app
flutter pub get
flutter run -d chrome --web-port 8018 --web-hostname localhost -t example/photo_evidence_main.dart
# Android emulator/device: select its reachable HTTPS service; never disable TLS
# validation or embed the private workspace token in the build.
```

Enter the service origin and workspace token at runtime. The token stays in
memory; it is not written to browser storage. Select a JPEG/PNG or take a photo
where the OS/browser offers camera capture. A browser file picker may show a
camera option on mobile; a desktop browser need not offer direct camera capture.
Desktop Flutter uses the gallery/file selector; unsupported camera controls are
hidden. iOS usage descriptions are supplied. Android uses `image_picker`'s native
picker without a broad storage/location permission. Recovering a picker result
after Android process death is not implemented; reselect the photo.

The UI strips metadata by encoding fresh pixels **before upload**, then the server
validates and strips again. EXIF GPS is read only when the farmer opts in **before
selection**. Turning consent off removes it from the pending upload. Consent
authorizes retention of just those coordinates, with unknown uncertainty, not
original EXIF/XMP/ICC/text/thumbnails. To remove already stored coordinates,
delete or replace that photo with GPS consent off. GPS is never a farm confirmation.
No device geolocation or image-to-location model is used.

Preview, add a caption and explicit farmer observation, choose crop/soil/water,
optionally supply a capture date, then upload. Missing capture date stays null;
upload time never substitutes for capture time. A date is not expanded to a fake
midnight timestamp. Without a supplied, farmer-confirmed farm reference and an
explicit association checkbox, evidence remains unlocated. Replace is atomic:
invalid input or a quota failure preserves the original. Remove selected photo
discards the draft; Delete photo deletes its stored image and metadata.

For a repeatable actual HTTP upload/view/delete smoke workflow, keep the service
running and run this in a second shell with the same token environment:

```sh
cd server
/tmp/earthsync-photo-venv/bin/python examples/photo_evidence_workflow.py
```

It creates a visibly labeled synthetic image, uploads and retrieves it, queries
the unavailable satellite adapters, then deletes it. It is not a field, browser,
Android, live NASA or scientific validation.

## API and separation of evidence

All routes require `Authorization: Bearer <private workspace token>`, return
`Cache-Control: no-store`, and use `/api/evidence/v1`:

| Method/path | Contract |
| --- | --- |
| `POST /photos` | Raw `image/jpeg` or `image/png`; JSON metadata in ASCII-escaped `X-EarthSync-Metadata`; returns 201 Photo |
| `GET /photos` | Workspace Photo list |
| `GET /photos/{uuid}` | One Photo |
| `GET /photos/{uuid}/image` | Sanitized PNG bytes; authenticated viewer |
| `PUT /photos/{uuid}` | Complete replacement, same body/metadata as POST; retains ID and initial upload time |
| `DELETE /photos/{uuid}` | Atomic removal; 204 |
| `POST /timeline` | Confirmed field + inclusive date interval; structured evidence timeline |

The header is capped at 8 KiB; non-ASCII text must be JSON `\u` escaped (the Dart
client does this). Only JPEG/PNG signatures with matching declared MIME are
accepted. Input and sanitized output each have a 10 MiB cap; at most 8192 pixels
per side and 16 million pixels; no animated images. Actual image decoding and
integrity checks are required. Original filenames never enter storage. UUIDs and
bound SQLite parameters prevent path/SQL construction from user data. Metadata
and sanitized bytes commit in one SQLite transaction. Storage is private
(directory 0700/database 0600), default 500 photos and 256 MiB of image bytes;
SQLite `secure_delete` wipes freed content (not a secure-erasure guarantee for
filesystem backups or SSDs). No original image, arbitrary user path or EXIF blob
is stored. This is bounded local storage, not an object-store deployment.

Photo input example (all nullable fields may be omitted):

```json
{
  "schema_version": "evidence.v1",
  "source": "gallery",
  "data_kind": "farmer_supplied",
  "category": "soil",
  "caption": "After yesterday's irrigation",
  "farmer_observations": "I see standing water here",
  "captured_date": "2026-11-01",
  "captured_at": null,
  "capture_time_source": "farmer_reported",
  "farm": {"farm_id": "farmer-confirmed-id", "confirmed_by_farmer": true},
  "position": null
}
```

Photo outputs add UUID, upload/update UTC timestamps, pixel dimensions, byte size,
SHA-256, sanitized PNG MIME, `metadata_stripped:true`, `farmer_supplied_photo`,
`photo_view_extent_unknown` and `not_scientifically_validated`. `data_kind` is
`farmer_supplied` or explicitly `synthetic`. Neither captions nor observations
are converted into measured crop/soil/water conditions. Photo position, when
authorized, separately contains WGS84 latitude/longitude in degrees,
`uncertainty_m:null` (or a reported nonnegative value), source `consented_exif` or
`farmer_reported`, and `retention_authorized:true`. No numeric uncertainty is invented.

Timeline request example:

```json
{
  "schema_version": "evidence.v1",
  "field": {
    "farm_id": "farmer-confirmed-id",
    "confirmed_by_farmer": true,
    "point": {"latitude": -33.9, "longitude": 151.2, "uncertainty_m": null}
  },
  "start": "2026-11-01",
  "end": "2026-11-14"
}
```

Coordinates are global WGS84 degrees. Confirmed point queries are supported;
boundary polygon clipping, antimeridian-wrapping pixel footprints and whole-field
aggregation are not implemented. Unconfirmed/approximate device positions are
rejected. Interval is inclusive, ordered and at most 366 days. Satellite
acquisition dates use UTC; a photo's farmer-reported calendar date is retained.
Only explicitly associated photos with matching farm ID enter this timeline.
Unknown-date photos are returned in `undated_photos`, never dated by upload time.
Unlocated photos remain in the viewer/list and cannot initiate satellite matching.

Timeline output contains ordered `events`, `undated_photos`, `providers`,
`rejected_records`, `differences`, and `limitations`. Provider states distinguish
`unavailable`, a successful query with `no_observations`, and `available` records.
`missing_state` and the requested interval explicitly distinguish unavailable
data, no matching observations, and observations only at listed acquisitions.
They never promise daily acquisition coverage or use missingness as a zero.

## Mockable satellite/SAR contract

`SatelliteAdapter.observe(TimelineQuery) -> ProviderResult` is the owned Python
boundary. No live retrieval is activated. `HlsAdapter` is the preferred optical
source; `RtcS1Adapter` targets OPERA RTC-S1. Both currently return
`unavailable/access_unverified`, empty records and product-specific limitations.
They never return fabricated measurements or classify regions as unsupported
just because access failed. Adapter exceptions/invalid responses become
`unavailable/provider_error_or_invalid_response`, not a successful empty query.

A future adapter must return `SatelliteRecord` only after actual pixel extraction
and native QA. The contract requires source URL, retrieval/acquisition timestamps,
observed versus synthetic kind, product/version/platform, confirmed field point,
WGS84 pixel footprint, resolution in metres, total/valid pixel counts, QA state
and method, limitations, metric and units. Optical v1 accepts NDVI with units `1`;
radar v1 accepts explicitly normalized gamma0 backscatter in `dB`. Native linear
power must not be mislabeled dB. Invalid/nonfinite values fail validation; a
`usable` sample requires a finite value and complete valid pixels. Missing values
are null and non-usable. Observed acquisition cannot postdate retrieval.

The matcher checks the exact confirmed field, UTC interval, modality and pixel
coverage of the confirmed point. Rejected associations retain a reason. Point
intersection is explicitly not whole-field coverage. Differences require usable
QA and identical product/version/platform, metric/units, geometry ID, pixel support,
resolution and QA method. Radar additionally requires identical known relative
orbit, direction, polarization and incidence angle. Unknown geometry prevents a
difference; no angular tolerance or cross-sensor comparability is invented.
Observed and synthetic records are never mixed. Duplicate IDs are ignored with a
reason. Differences reference both records, dates, source URLs, product/version,
units, spatial support, QA, missing-state and limitations. A numeric NDVI/radar
difference is never labeled disease, soil moisture, flooding, yield or suitability.
Modeled and forecast data are not accepted by this observed-evidence contract.

## Provider research and access evidence (14 November 2026 UTC)

Successfully read these upstream GitHub sources, pinned for reproducibility:

- [NASA HLS resources](https://github.com/nasa/HLS-Data-Resources/blob/3ac8d6a3e47df95ab3a239e9a474da8a682df503/README.md)
  describes harmonized surface reflectance, global coverage intent and 30 m
  support. Revisit rate is not usable field coverage.
- [NASA HLS tutorial](https://github.com/nasa/HLS-Data-Resources/blob/3ac8d6a3e47df95ab3a239e9a474da8a682df503/python/tutorials/HLS_Tutorial.ipynb)
  uses Earthdata/earthaccess login, CMR HLSL30/HLSS30 discovery, S30 B8A versus L30
  B05 NIR, B04 red, Fmask bit QA and per-band scaling. It documents that scaling
  metadata can be missing at band level. A future adapter must validate actual
  product metadata, nodata and cloud/shadow/snow/aerosol QA, not copy a generic
  reflectance/NDVI assumption. Its example derives EVI, not a field disease model.
- [OPERA RTC-S1 software](https://github.com/opera-adt/RTC/blob/c5cc7403af16bb67fd14f43bf2aec15c6a422297/README.md)
  identifies JPL's Sentinel-1 radiometric terrain-corrected backscatter processor.
- [RTC defaults](https://github.com/opera-adt/RTC/blob/c5cc7403af16bb67fd14f43bf2aec15c6a422297/src/rtc/defaults/rtc_s1.yaml)
  exposes gamma0 output, polarization, orbit files, valid-sample/shadow masking,
  optional incidence-angle layers and layover/shadow masks. Processor defaults
  are not proof of an individual delivered product's units, masks or coverage.

Actual attempted data/documentation URLs:

```text
https://hls.gsfc.nasa.gov/data/
https://cmr.earthdata.nasa.gov/search/collections.json?short_name=HLSS30&version=2.0&page_size=1
https://api.daac.asf.alaska.edu/services/search/param?processingLevel=RTC&maxResults=1&output=geojson
https://www.jpl.nasa.gov/go/opera/opera-products/rtc-product/
```

Each connection was denied by the managed environment's proxy with CONNECT 403;
this is not a provider HTTP response. Current network policy permits GitHub and
NASA POWER but not these catalog/product hosts; no Earthdata credentials are
configured. Needed next: permitted official catalog/data hosts and any redirects,
Earthdata access where required, verified actual HLS/RTC-S1 coverage for a
farmer-confirmed point/window, representative product files, and reviewed native
QA/scaling/pixel extraction. Credentials alone are insufficient. No NASA satellite
or radar request or scientific validation succeeded in this task.

## Tests and integration handoff

```sh
# From engine/ (existing web-demo tests need the native executable):
cargo build --example web_engine
# From server/:
python -m pytest -q
ruff check earthsync/evidence tests/evidence
ruff format --check earthsync/evidence tests/evidence
# From app/ with a Flutter SDK whose Dart satisfies pubspec.yaml (^3.12.0):
flutter pub get
dart format lib/features/photo_evidence test/photo_evidence example/photo_evidence_main.dart
flutter analyze lib/features/photo_evidence test/photo_evidence example/photo_evidence_main.dart
flutter test test/photo_evidence
flutter build web --target example/photo_evidence_main.dart
# From repository root:
git diff --check
```

Python tests exercise CRUD, consent/association boundaries, signatures, truncation,
dimensions, animation, actual EXIF/text removal and orientation, streaming limits,
safe storage, quota rollback, authorization, UTC/global queries, missing/failed
providers, invalid/nonfinite science records, geometry/QA matching and conservative
synthetic differences. Flutter tests cover picker cancellation, previews,
upload/replace/delete, consent revocation, explicit farm association, Unicode JSON
transport, no GPS reads without consent, sanitization and contract unknown states.
All test imagery and numerical satellite fixtures are synthetic and labeled.

Embed `PhotoEvidencePanel(repository: ..., picker: ..., confirmedFarm: ...)` after
the dashboard/farm owners approve the reference and auth handoff. The component
is scroll-parent friendly and accepts an `onChanged` callback. Caller owns HTTP
client lifetime. No token or precise coordinates are logged by the module.
The standalone harness intentionally supplies no farm so the initial flow is
unlocated. No changes to other teams' endpoints, app routes or engine contracts.
