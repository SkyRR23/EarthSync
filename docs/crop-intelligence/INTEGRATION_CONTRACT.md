# Integration contracts

## Existing farmer application

The following additive paths remain behind the existing local platform boundary:

* POST `/api/platform/v1/crop-intelligence`: `EvidenceQuery`; public source packet.
* POST `/api/platform/v1/farms/{farm}/photos/{photo}/analyze`: default unavailable
  appearance output; exact owned farm/photo required.
* POST `/api/platform/v1/farms/{farm}/photos/{photo}/lab-extraction`: local OCR,
  201 original extraction with null confirmation.
* GET `/api/platform/v1/farms/{farm}/lab-reports`: own farm's saved reports.
* POST `/api/platform/v1/farms/{farm}/lab-reports/{report}/confirm`: checked sample.
* GET `/api/platform/v1/farms/{farm}/soil-context`: saved SoilGrids source jobs,
  attributed observations and lab transcriptions in separate categories.

Existing `POST /api/platform/v1/farms/{farm}/photos` and authorized image/delete
contracts are reused. The older `/api/evidence/v1/photos` workspace is untouched.
No credentials or records move between those stores and the Research API.

The read-only soil adapter consumes `Store.intelligence(owner,farm)` successful
`soil_map` jobs exactly as saved by the verified WebDAV ingestion. It preserves
the full result's timestamps, source URL, cells, 0–5 cm depth, nominal 250 m grid,
QA and limitations. No raster is refetched, reprocessed or rewritten. Observations
are explicitly farmer-reported. Lab values retain original and corrected forms.

The separate synthetic research tenant has **no verified farmer-database link**.
Its `/soil/context` returns modeled reference unavailable. Caller JSON cannot
pretend to be a trusted SoilGrids snapshot. A future bridge needs an authenticated,
farm-bound, read-only source contract; arbitrary URLs or client-modeled values
must not supply it. Legacy teammate `/soil/estimate` is not assumed equivalent
to the verified SoilGrids contract because its schema/QA has not been inspected.

## Optional AI

The retrieval service is useful without any AI provider. A separate Groq experiment
may select retrieved claim IDs through `extractive_explanation(packet,claim_ids)`.
Unknown IDs or modified citations fail. No free prose, rule status or new numerical
measurement can enter through this contract. No Groq code/key is copied.

A documented image adapter implements `VisionProvider`, with model identity,
image capability and external-processing flag. Explicit request consent precedes
external transfer. Structured feature enums are unverified observations. No actual
external adapter/model was configured, tested or advertised as functional.

The user-supplied Firebase test host has working legacy health but no discoverable
OpenAPI at either tested location. New research routes need an independently
reviewed deployment. Server-to-server integration avoids browser CORS limits.
