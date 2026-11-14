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

## New contributed Myanmar profiles

**Pending integrity verification and full archive access.** No profile count,
source validity, local calendar, cultivar, duration, temperature/rainfall requirement,
soil rule, market value or review status can yet be certified. The older PR #11
archive contains no crop catalog and cannot substitute for those profiles.

Acceptance must distinguish monsoon/dry-season, rainfed upland/lowland, irrigated
and flooded systems; establish actual local region and cultivar applicability;
retain original statistic and units; separate institution publication date from
retrieval time; and record uncertainty and unavailable properties explicitly.
Do not use global pilots to fill missing Myanmar facts.
