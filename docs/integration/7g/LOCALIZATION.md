# English-first localization and offline foundation

New map labels live in `UiCopy.en`, using the existing locale fallback mechanism.
Remaining evidence/form strings need extraction before complete translation.
The existing Burmese navigation preview stays marked machine-drafted and needing
native/agricultural review. No complete Burmese workflow is claimed.

Prepare reviewed terminology for: confirmed point, boundary, approximate area,
modeled estimate, observed measurement, forecast valid time, model initialization,
unknown issuance, nodata, cloud-covered, NDVI, pH, soil depth and farmer report.
Keep NDVI/pH/unit symbols and original provider names/citations intact. Do not
translate “modeled” into a term implying a laboratory result, “forecast” into an
observed event, or “unknown” into a zero/negative result. Regional model support
and uncertainty explanations need native-domain review before publication.

Geometry/profile viewing is device-local. Source snapshots and the 7P reference
catalog are retained by the private local service, so external provider outages
need not erase already saved reference views. Browser refresh with that service
down is not a completed offline workflow. No offline public tile pack, service
worker, background API emulation or on-device LLM was added. Network-required
maps/new retrievals and stale (≥30 minute saved forecast) labels are explicit.
