# Scientific limits and remaining work

**No new agricultural recommendation, suitability score, executable crop rule,
yield forecast or independent agronomic acceptance is delivered.** This package
delivers reference facts, working import/validation/query tools and a fail-closed
v0.3 mapping boundary. Software tests validate behavior and traceability only.

ECOCROP is historical species-level ecological information. Its temperature query
uses average minimum/maximum conditions during a growing season; its annual
rainfall field allows supplemental-water context. Neither defines daily weather
limits, crop-season precipitation, ETc or irrigation sufficiency. Soil pH lacks
accepted sampling depth/method; qualitative soil-depth classes are not lab layers.
Species crop-cycle ranges are not selected local cultivar maturity predictions.

The global CSV is a pinned third-party snapshot with separately established FAO
data licensing, not a claimed official current bulk export. All 2,568 distinct
source names are enumerated; 708 have positive agricultural identity evidence.
Global current accepted-name reconciliation and full-table original-source
authentication are incomplete. Additional crops are overwhelmingly identity-only.
No arbitrary wild/ornamental species becomes an agricultural crop just by being
listed. Alias collisions remain ambiguous.

Myanmar's official calendar is advisory and dated 2021-02-26, not proof of current
local field conditions. AEZ labels do not select a farmer's location. Rainfed,
irrigated, upland, flood-prone and tidal remarks retain their original distinctions.
The green-gram/Penauk and maize/sweet-corn inconsistencies remain unresolved.
Same-zone sessions and differing groundnut durations are retained independently.
No national planting rule or automatic cultivar substitution is produced.

FAO-56 standard-condition coefficients are method references: selected source-row
values/endpoint alternatives are retained, including missing initial-row values.
There are no accepted daily stage offsets, local adjustments, aligned reference
ET0, effective rainfall, root-zone storage, irrigation delivery or paddy
preparation/percolation balance. No coefficient curve, ET0 series or ETc total
is manufactured. The old maize/groundnut crop-water-information URLs returned
404 in this review; no water quantity is inferred from secondary summaries.

Rotation examples preserve requested order and synthetic dates. Some have bounded
published cropping-system context; maize–mung bean and sesame–pulses lack verified
exact order/local agronomy here. General groundnut/cereal guidance does not prove
maize-specific pest control, nitrogen supply, income or suitable fallow duration.
Verified ecological tradeoffs remain null. A gap between dates is not evidence
of actual fallow; complete attributed field history is absent.

SoilGrids transport access is not numerical acceptance. The recorded WCS raster
lacked explicit nodata and was rejected by the existing parser; no replacement
sentinel, nutrient zero, sampling observation or irrigation inference is supplied.
Native 250 m support, six depth intervals and scale factors are documented, but
product release identity, quantiles and effective observation period remain gaps.
REST is documented paused. WebDAV directory access establishes availability of
products, not valid local samples.

GAEZ v5 configuration is actually imported, but no numerical crop-specific
suitability/yield extract was tested. Product legend, crop type, rainfed/irrigated
and high/low management, climate model/scenario, historical baseline, native grid,
unit/scale and nodata must be accepted before a bounded future extract. Modeled
potential yield cannot become predicted farmer yield.

NASA POWER remains the existing validated historical modeled regional evidence.
Monthly means cannot supply daily extrema; MERRA-2 and GEOS-IT cannot be relabeled
or silently combined. Newly reachable CMR collection metadata is discovery only.
GIBS tiles are visual context. IMERG, SMAP, MODIS, HLS and OPERA require separately
tested product access, native QA and spatial/temporal support before numerical
use. No vegetation-color soil moisture, live imagery measurement or SAR crop-health
claim is introduced.

Publication, retrieval and product-version precision remain explicit. Initial
capture receipts know request start and retrieval day but not exact response
completion; later receipts preserve both. Hashes prove stored bytes, not truth
or acceptance. Crop Calendar redistribution rights remain unresolved for bulk
exports; noncommercial/share-alike and third-party handbook conditions remain
separate from the software/data licenses of other sources.
