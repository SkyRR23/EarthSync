# Crop knowledge quality report

Independent source desk checks on 14 November 2026. No independent agronomist
acceptance, field trial validation or Myanmar production recommendation is claimed.
All eight global profiles remain `recommendation_eligible=false`; six mappings
to v0.3 remain reference-only with **zero executable requirements**. Two unsupported
profile mappings remain blocked. No scientific acceptance flag was changed.

## Evidence classes

| Class | Meaning and current handling |
| --- | --- |
| Source-reviewed reference fact | Taxonomy, advisory planting context or a scoped institutional management description. Retain original source, partial date precision, units and scope; desk review alone does not authorize execution. |
| Independently applicable executable rule | Requires actual accepted statistic, production system, region, cultivar/stage, units/depth/method and independent applicability review. None was newly accepted. |
| Farmer-reported information | Attributed owner/field/date assertion. It is not an independently measured soil value or proof of complete field history. |
| Model-derived environmental estimate | NASA POWER/MERRA-2 meteorology, SoilGrids predictions and forecast context. Preserve model lineage, grid support, dates and missingness; no observation relabeling. |
| Unverified assertion | Unreviewed contributed thresholds, numeric benefits, drainage proxies, forecast runs or local applicability. Remains blocked. |
| Synthetic test input | Fictional source/profile/value used to exercise software branches; retain synthetic mode and markers. Passing an arithmetic test is not source approval. |

## Original documents rechecked

These are independent bounded checks against the original institutional pages,
not a claim that each full publication or all underlying experiments were audited.
The catalog's existing evidence graph, missing-property inventory and citation
links were also validated with its 39 tests (32 additional subtests).

| Source | Independent check and scope | Decision |
| --- | --- | --- |
| [ISU corn/soybean planting, 1 April 2021](https://crops.extension.iastate.edu/post/corn-and-soybean-planting-date-considerations) | Iowa guidance describes conditional planting and historical April 11–May 18 corn context; fixed dates depend on soil/weather. Insurance dates are separate | Advisory reference, not universal sowing limits or Myanmar guidance. |
| [ISU soybean, 15 February 2024](https://crops.extension.iastate.edu/post/early-soybean-planting-considerations) | Prior-to-May-20 discussion coexists with frost/cold/wet-soil risks and historically revised insurance dates | One advisory endpoint does not define a complete executable planting window. |
| [ISU conditions, 26 March 2026](https://crops.extension.iastate.edu/post/soil-temperature-and-planting-conditions-what-watch-spring) | 50 F soil germination guidance is conditional on warming outlook and soil moisture; separate maps use four-inch depth | Keep Fahrenheit and missing measurement depth. Do not manufacture air-temperature tolerance, or transfer map depth into the general rule. |
| [K-State Tribune research](https://www.wkrec.org/programs/dryland_cropping_systems/index.html) | Institutional abstracts distinguish rotations, tillage, site and year; large-scale study describes 2008–2020 | Reference to wheat–sorghum–fallow is supported; no local duration, nitrogen credit, pest benefit or guaranteed yield extracted. |
| [Arkansas rice water chapter](https://www.uaex.uada.edu/publications/pdf/mp192/chapter-10.pdf) | Water quality/quantity, system capacity and soil texture affect management; pumping examples use GPM/acre | Distinct flooded management reference, not a boolean irrigation-sufficiency rule. Chapter version metadata remains the existing 2021 index attribution, not a newly inferred PDF date. |
| [Arkansas soybean irrigation chapter](https://www.uaex.uada.edu/publications/pdf/mp197/chapter8.pdf) | Drainage and irrigation management are scoped; historical yield examples include 1983–1998 | Historical reference only. Do not turn old yield/cost context into a present farm financial estimate. |
| [NSW drill-sown rice](https://www.dpird.nsw.gov.au/agriculture/broadacre-crops/summer-crops/rice-agronomy/drill-sown) | Landing page confirms Primefact 1253 fourth edition, July 2023; establishment/flush and later permanent water differ | Distinct delayed-flood system; full linked PDF not independently reviewed here. Existing mapping stays blocked. |
| [FAO-56 chapter 5, 1998](https://www.fao.org/4/X0490E/x0490e0a.htm) | Standard-condition ETc = Kc × ET0; crop stage and reference surface matter | Method reference only. No local stage Kc, effective rain, irrigation efficiency, storage trajectory or water balance accepted. |
| ITIS reports for [corn](https://www.itis.gov/servlet/SingleRpt/SingleRpt?search_topic=TSN&search_value=42269), [soybean](https://www.itis.gov/servlet/SingleRpt/SingleRpt?search_topic=TSN&search_value=26716), [wheat](https://www.itis.gov/servlet/SingleRpt/SingleRpt?search_topic=TSN&search_value=42237), [sorghum](https://www.itis.gov/servlet/SingleRpt/SingleRpt?search_topic=TSN&search_value=42108), [rice](https://www.itis.gov/servlet/SingleRpt/SingleRpt?search_topic=TSN&search_value=41976) | Species identities checked; Poaceae/Fabaceae identity is taxonomy | Taxonomic facts do not establish rotation order, pest suppression, N contribution, water needs or suitability. Live taxonomic report publication date remains unknown. |

## Contributed Myanmar profiles: completed bounded source review

All 12 profiles were inventoried, source/CSV/JSON fields compared, and quarantined.
The authoring CSV and data-pack Myanmar snapshot are byte-identical (SHA-256
`65064a00430aecce5d63312775f3b4699b89bebc58a326d980a1a73372229a0c`).
Eleven original ECOCROP datasheets were readable; sunflower's direct request
returned a service error, while its indexed original-source page provides matching
reference numbers. That distinction is retained as cached-only source evidence.
No datum is called a field measurement and no unavailable source is silently filled.

| Crop | ECOCROP ID / original datasheet | Desk-review result |
| --- | --- | --- |
| Paddy rice | [1574](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=1574) | Temperature, annual-rain, cycle and pH reference values match; wet-rice context does not approve a Myanmar field rule. |
| Black gram | [2149](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=2149) | Numeric reference matches; team 60–90-day duration and seasonal water not established by those global descriptors. |
| Mung bean | [2150](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=2150) | Numeric reference matches; page lists a broad life-history context, not the local cultivar/system. |
| Groundnut | [2199](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=2199) | Numeric reference matches; team seasonal-water/N values require separate evidence. |
| Sesame | [1937](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=1937) | Numeric reference matches; species cycle envelope differs from selected Myanmar duration. |
| Maize | [2175](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=2175) | Numeric reference matches; 65–365-day global envelope does not prove why 365 is present or validate the team's 95–120 days. |
| Chickpea | [2479](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=2479) | Numeric reference matches; local stage/temperature/water applicability remains unknown. |
| Pigeon pea | [576](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=576) | Numeric reference matches; perennial species context does not validate local annual duration. |
| Sunflower | [1191](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=1191) | Direct service error; indexed original source matches numbers. Cached reference only, not fresh availability. |
| Cotton | [1160](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=1160) | Numeric reference matches; annual/perennial types and management differ. |
| Sunn hemp | [801](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=801) | Numeric reference matches; a qualitative nitrogen-fixation use is not a 40–80 kg/ha credit available to a following crop. |
| Mustard | [548](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=548) | Numeric reference matches; no sourced soil-fungal break benefit or local catch-crop calendar established. |

These are source-reviewed ecological descriptors, not independently applicable
executable rules. ECOCROP's rainfall is explicitly annual. Its temperature ranges
lack the daily extreme, stage, cultivar and regional semantics needed by v0.3.
The contributor itself calls duration/seasonal water team estimates; no stage
lengths, daily reference ET0, Kc curve or calculation supports its FAO-56-derived
ETc wording. Filled numbers and medium confidence cannot remove those unknowns.

The linked [World Bank Rice and Pulses report](https://documents1.worldbank.org/curated/en/623701579900727742/pdf/Myanmar-Rice-and-Pulses-Farm-Production-Economics-and-Value-Chain-Dynamics.pdf)
is dated **June 2019** on its cover, rather than the archive's 2020 attribution.
Its page 14 / PDF page 26, Figure 24 and adjacent text distinguish central from
lower Myanmar, seasons, and pulse systems. These support bounded calendar
context, not a single universal crop-month list. Historical economic tables also
show why market-use counts cannot establish farm income. Neither old currency
amounts nor calendar examples were imported as current farm rules.

The cited [FAO 2022 groundnut/sesame handbook](https://openknowledge.fao.org/server/api/core/bitstreams/a825f44a-0409-466a-94b4-135e4bc9fd27/content)
returned 403 through the web tool; the official alternate `cc0246en` PDF route was
also inaccessible. Its existence/title is corroborated, but full-text calendar,
water, pest and N applicability were **not** accepted. No source was reconstructed
from the contributor's notes or a third-party synopsis.

Publication dates of ECOCROP entries remain unknown. The CSV's 2026-11-14 date
is a contributed source/extraction date, not independently verified publication
or retrieval time. Myanmar cultivar, production system, soil method/depth, crop
stage, actual field conditions and quantitative uncertainty remain unresolved.

The separate research fixture preserves all original assertions, classifies the
bounded reference evidence, and keeps all 12 profiles `recommendation_eligible=false`,
`approved_for_candidates=false`, `executable_rules=[]`. The live global catalog
is unchanged. No N/pest benefit, irrigation credit, ranking or financial model is
accepted. Independent agronomist/field acceptance remains outstanding.
