# Source and pilot review, 14 November 2026

Review scope: extraction accuracy, attribution, units, dates, applicability,
unknowns and quality states. Reviewer: EarthSync 7G source audit (Codex).
Independent agronomist review: **not performed**. Source desk review is not a
scientific validation study. All profile recommendation eligibility remains false.

## Iowa corn and soybean: detailed initial review

The named Story County pilot uses Iowa statewide guidance. This does not create
county trial evidence, a known cultivar, a rainfed water budget or a farm point.
Each populated parameter links through a claim to an original source and section.
The catalog records both source publication dates and the extraction timestamp.

| Parameter | Corn | Soybean | Review disposition |
| --- | --- | --- | --- |
| Scientific identity | Zea mays | Glycine max | Accepted species and family hierarchy checked against ITIS TSNs 42269 and 26716. Taxonomy supplies no agronomic requirement. |
| Crop family | Poaceae | Fabaceae | Identity only; no family-based rotation restriction or benefit inferred. |
| Planting guidance | Historical April 11–May 18 advisory endpoints | Before-May-20 advisory endpoint; earliest date unknown | ISU 2021 corn section and 2024 soybean article. Dates remain advisory. Insurance dates were deliberately excluded. |
| Harvest | Unavailable | Unavailable | No applicable maturity/cultivar harvest rule established. |
| Duration | Unavailable | Unavailable | No typical days substituted for missing cultivar evidence. |
| Air-temperature limits | Unavailable | Unavailable | Soil establishment advice is not daily air-temperature tolerance or monthly climate suitability. |
| Soil establishment temperature | Conditional 2026 guidance | Conditional 2026 guidance plus 2024 early-planting caution | Original unit retained as °F. Depth unspecified; warming trend, relevant outlook and field conditions retained. No current forecast supplied. |
| Water management | Unavailable | Unavailable | Rainfed profile scope is not proof of rainfall adequacy; no quantity, water balance or irrigation rule derived. |
| Soil properties | Qualitative seedbed inspection only | Qualitative seedbed inspection only | 2026 ISU moisture section. No numerical pH, moisture, organic carbon, texture or drainage compatibility rule established. |
| Soil depth | Unavailable | Unavailable | ISU's historical two-inch germination context is retained as a separate claim, not a soil horizon/rooting-depth requirement. |
| Rotation | Unavailable | Unavailable | No succession benefit or restriction sourced for the supplied farm/system. |
| Crop coefficients | Unavailable | Unavailable | FAO-56 method reviewed separately; no regional/stage/cultivar Kc accepted. |

Date reconciliation: the 2021 article's insurance discussion is historical. The
2024 article describes changed policy dates; neither is ingested as a crop
requirement. The 2026 article body is dated March 26, 2026 even where a search
result's relative age differs. That body date is the catalog publication date.
The 2026 guide references 4-inch maps, while its general establishment advice
does not establish a universal measurement depth. Soil temperature depth stays
null. Field seed-zone temperature and local seedbed condition are still needed.

Sources checked:

- [ISU, 2021 planting discussion](https://crops.extension.iastate.edu/post/corn-and-soybean-planting-date-considerations)
- [ISU, 2024 early soybean considerations](https://crops.extension.iastate.edu/post/early-soybean-planting-considerations)
- [ISU, 2026 soil temperature and planting conditions](https://crops.extension.iastate.edu/post/soil-temperature-and-planting-conditions-what-watch-spring)
- [ITIS corn identity](https://www.itis.gov/servlet/SingleRpt/SingleRpt?search_topic=TSN&search_value=42269)
- [ITIS soybean identity](https://www.itis.gov/servlet/SingleRpt/SingleRpt?search_topic=TSN&search_value=26716)

Remaining Iowa acceptance work: independent agronomist review; selected
cultivar/maturity group and system; field-confirmed location and conditions;
depth-compatible field measurements; current relevant weather/forecast; explicit
water adequacy; soil methods and horizons; actual history and dated plans.

## Other pilots: bounded reference coverage

**Tribune:** K-State's institutional research abstracts explicitly identify
wheat–sorghum–fallow among rotations studied near Tribune. The reported study
interval is 2008–2020. January 1/December 31 encode the extent of those reported
years, not individual sample dates. No field-specific yields, wheat planting
dates, fallow duration, water threshold or general rotation benefit is extracted.
All three system profiles remain reference-only. Fallow is management, not a
taxon. [Institutional source](https://www.wkrec.org/programs/dryland_cropping_systems/index.html).

**Stuttgart:** the Arkansas rice handbook's chapter/index versions were checked.
The water chapter is a July 2021 update and distinguishes continuous flood,
alternate wetting/drying and growth-stage/cultivar considerations. Its numerical
examples are not universal requirements. The soybean irrigation chapter is the
2000 version identified in the official index and remains historical reference
only. Surface drainage advice cannot establish a field's drainage condition.
No rice-to-soybean transition benefit or rice calendar is inferred.
[Rice chapter](https://www.uaex.uada.edu/publications/pdf/mp192/chapter-10.pdf),
[rice version index](https://www.uaex.uada.edu/publications/mp-192.aspx),
[soybean chapter](https://www.uaex.uada.edu/publications/pdf/mp197/chapter8.pdf),
[soybean version index](https://www.uaex.uada.edu/publications/mp-197.aspx).

**Riverina:** NSW's summary of Primefact 1253, fourth edition, July 2023 was
checked for drill-sown establishment/flush irrigation and later permanent water.
The linked full PDF was not audited. A drill-sown delayed-flood profile is kept
distinct from aerial-sown or continuously flooded rice. No universal October
sowing month, variety duration, water allocation or Griffith soil condition is
inferred. Other regional crops have no profiles until evidence is reviewed.
[NSW source](https://www.dpird.nsw.gov.au/agriculture/broadacre-crops/summer-crops/rice-agronomy/drill-sown).

## Machine-readable gap register

`unknown_properties` on every profile and `audit.json.unavailable_parameters`
are the machine-readable parameter gap inventory. `pilots.json` records regional
and additional-crop gaps. `evidence/http-retrieval-audit.json` records exact
source-download failures, independently of the successful web source review.

| Priority source family | Current disposition | Required before use |
| --- | --- | --- |
| FAO ECOCROP / GAEZ | No species requirement records ingested | Versioned original crop records, units and original-source/licensing review, then production-system/cultivar applicability review. FAO describes ECOCROP as discontinued around 2015 and incorporated into GAEZ; a landing page is not verified regional thresholds. |
| FAO-56 | Equation 56/units retained as a method claim | Applicable stage Kc, stage dates, valid ET0 and conditions; separate flooded-rice water requirements. |
| USDA NRCS soils | No field properties or soil requirements ingested | Actual area/horizon, original units, method, dates, component/spatial support, quality and local applicability. Mapped soil cannot be silently promoted to a field sample. |
| USDA NASS CDL/statistics | No raster, acreage or crop-presence values ingested | Product/year/version-specific metadata, QA, units and spatial support. Crop presence does not establish suitability or farmer history. |
| NSW / Australian government / CSIRO / ANSIS | NSW drill-rice summary only | Full regional/cultivar guide review, documented soil/irrigation evidence and other crop sources. No ANSIS or CSIRO values inferred. |
| NASA POWER / Earth observation | No environmental data retrieved by this task | Existing NASA interfaces remain owner-controlled. Any future series needs provider lineage, units, dates, requested point/grid support, fill values, completeness and QA. It must remain separate from farm measurements and crop requirements. |

FAO references: [ECOCROP status](https://www.fao.org/land-water/resources/tools/databases/ecocrop/en)
and [FAO-56 chapter 5](https://www.fao.org/4/X0490E/x0490e0a.htm).
The ECOCROP status is contextual research, not an ingested crop rule or an
operational source adapter. An unverified service remains unavailable.

## PR #11 lessons applied

The [Field Shift audit](https://github.com/SkyRR23/EarthSync/pull/11) records
missing original retrieval provenance, shifted climatology months and incomplete
QA. This pack reuses none of its scientific values. Here month/day tokens are
explicit, impossible dates and cross-year mismatches are rejected, missing values
remain null, source/claim links and scope are checked, and original-response
hashes are never inferred from an extracted view. Software checks do not certify
agricultural truth, field precision or forecast safety.
