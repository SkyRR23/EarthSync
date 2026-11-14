# 7V scientific applicability review — v1.0.0

Disposition: retain rigorously scoped facts and numerical method checks; block
all 60 proposed constraint domains from agricultural execution. No source meets
all eight acceptance gates for a specific field rule in this review. No Rust,
FastAPI, Flutter, existing reference profile or 7W worktree was changed.

## Inputs and independence

Base: 7P #25 `940a8aad62da8b188cdd3af4d200f353d907997a`.
Completed audit: 7J #22 `7b27699f13c94461a9d3d6596c47debfcfb9fed6`.
Read 7P sources, all claim/parameter mappings and missing entries, limitations,
rights, calendar disagreements and handoffs. The complete upstream validator
checks 937 claims, 75 profiles and source integrity. Read 7J's crop report,
sources, defects, historical/current issue matrix, verification and handoff;
reuse its archive conclusions without re-running the forensic archive audit or
applying already-integrated fixes. The inherited audit's 12 scientific failures
are not counted as passing tests or replaced by this package.

7V independently inspected five retained original FAO ECOCROP sheets and their
help pages, then re-extracted 28 populated priority values using the reviewed
7P parser. This is an independent source reading, not a second independent
parser implementation. Seven fresh official-source retrievals cover FAO-56
chapters 5/6, water-shortage guidance, the 2022 Myanmar handbook and three FAO
Calendar endpoints. All 55 selected calendar session objects match 7P, including
locators, crop labels, AEZ, update date, dates, duration, season and comments.
The calendar source body has 111 records; its 2021-02-26 update is not a 2026
agronomic review. Original response hashes and exact retrieval times are recorded.

This is a separate automated desk review relative to 7P. There is no independent
credentialed agronomist, replicated field trial, or field-safety certification.
Handbook rotation/IPM material is institutional secondary synthesis: the stated
GRET (2019) and Nataraja et al. (2014) field evidence was not independently read.
That limitation prevents treating the handbook as primary experimental proof.

## Eight acceptance gates for any future executable rule

1. Read the original authoritative document or experiment; a mirror or summary
   alone is insufficient for an executable agronomic threshold.
2. Record exact section/page/table/row and the actual claim, including footnotes.
3. Identify species, harvested crop type, cultivar/type and establishment method;
   preserve unknowns rather than substituting a common name.
4. State geography, climate/season and production system. An ecological global
   species reference is not globally validated field applicability.
5. Match units, temporal statistic, date conventions, sampling depth and method
   to the engine condition and data. State source/update/retrieval date precision.
6. Review conflicting sources, endpoint alternatives and quantitative uncertainty;
   do not select the favorable value or treat a range as a confidence interval.
7. Explain applicability limits and the evidence missing for transfer to the
   intended field/system. Require appropriate agronomist/field validation.
8. Record an independent applicability review with named role, date, evidence,
   decision and scope. Source transcription and software test success are separate.

The v1 schema cannot encode rule approval. Any future acceptance needs a
separately reviewed version, retained evidence, independent applicability record
and integration review. Mechanical regeneration cannot supply these gates.

## Crop-specific decisions

| Crop | Verified bounded evidence retained | Why execution remains blocked |
| --- | --- | --- |
| Rice | ECOCROP temperature 20–30 optimal / 10–36 absolute °C and cycle 80–180 days; separate Myanmar calendar sessions; FAO-56 paddy Kc 1.05/1.20/0.90–0.60; Table 11 stage examples 150 and 180 days | Seasonal average temperature is not each-day tolerance. No local cultivar, establishment origin, harvest endpoint or locally adjusted curve. Rainfed upland, rainfed lowland, maintained paddy and NSW delayed flooding remain separate. Irrigated calendar labels do not prove standing water or flood tolerance. |
| Maize | ECOCROP cycle 65–365 days and air-temperature ecological envelope; six grain-maize Table 11 examples (125–180 days) with original regional/seasonal contexts; Kc mid 1.20, end 0.60 or 0.35 | Code 0113 maize versus sweet-corn labels remain unresolved. Grain/sweet harvest purpose matters. Original sheet has blank texture/drainage; no fallback allowed. Regional stage examples do not validate a global 125–180-day maturity constraint. |
| Mung bean | Vigna radiata ecological facts; distinct 0157/0232 calendar sessions; FAO-56 grouped green gram/cowpeas Kc and Mediterranean March 20/30/30/20-day example | Green gram/Vigna aureus versus Mung bean/Penauk identity/duration conflict persists. Grouped green gram/cowpeas is not a selected local cultivar. Fresh/dry endpoint alternatives remain management states. No verified flood/drought exposure threshold. |
| Sesame | ECOCROP cycle 40–180 days, pH and drainage descriptors; Kc mid 1.10/end 0.25; China June Table 11 row | Official HTML stage lengths 20+30+40+20 = 110 but stated total is 100. Retain both; no silent repair or rescaling. Well-drained ecology does not provide stage-specific waterlogging exposure or drought tolerance. |
| Groundnut | Myanmar handbook §1.3.1: erect type 90–100 days versus prostrate 5–6 months; three regional stage examples 130/140/140 days; Kc mid 1.15/end 0.60 | Type and regional stage examples are different scopes, not a contradiction to average away. Named cultivars and inclusive-day/establishment convention are unresolved. Months remain calendar months. Split HTML planting cells are preserved literally. |

Numerical ecological descriptors in this table are source facts only. They are
not recommended thresholds, planting periods or cultivar choices.

## Cross-domain applicability and contradictions

**Temperature.** ECOCROP help 2000 explicitly requests average minimum and average
maximum temperature within the growing season. Rust `Temperature` tests every
daily Tmin/Tmax against one envelope. No conversion is justified. Monthly means,
monthly extremes, mean daily extremes, soil temperature and MODIS surface skin
temperature must remain distinct. No crop-specific base/upper cutoff or uncapped
GDD maturity target is established.

**Rain and water.** ECOCROP rainfall is annual; help 2001 allows supplemental
water. It cannot be divided by twelve, scaled by duration or treated as crop-season
precipitation. Rust sums daily rainfall over inclusive plan dates, which still is
neither effective rain nor irrigation sufficiency. No new seasonal rainfall
constraint is accepted for any priority crop. ETc needs daily reference ETo and
applicable Kc; irrigation additionally needs effective rain, root-zone storage,
delivery/losses and, for paddy, preparation, seepage and percolation accounting.

**Soil.** ECOCROP pH has no accepted sampling layer or water/salt chemistry method.
Its ecological soil-depth class is not a laboratory horizon. Texture and drainage
categories have no independently accepted engine vocabulary crosswalk; texture
does not measure drainage. Maize blanks remain unsupported. SoilGrids model
estimates, farmer assertions and laboratory measurements retain different support
and uncertainties; 7P's rejected WCS raster supplies no field soil value.

**Flood, drought and stages.** FAO irrigation-training Tables 1/2 verify qualitative
water-shortage sensitivity and sensitive periods for rice (head development and
flowering), maize (flowering and grain filling) and groundnut (flowering and pod
setting). They do not define exposure depth, water potential, duration, day
offsets, recovery or injury thresholds. Mung/sesame quantitative evidence is
absent here. Paddy culture does not prove tolerance of complete submergence.
v0.3 has no quantitative stage-specific flood/drought injury condition; adding
such an algorithm is outside this task.

**FAO-56 Kc and stage lengths.** Table 12 refers to non-stressed standard crops;
mid/end values reference RHmin about 45% and wind about 2 m/s. Equation 62/65
adjustments, height and wetting context need applicability review. The initial
group values (legumes 0.4, oil crops 0.35, cereals 0.3) are explicitly permitted
planning approximations in the source, but do not silently fill the blank crop
row initials retained by 7P. Rice initial 1.05 is specifically paddy standing
water 0.10–0.20 m in sub-humid calm/moderate conditions; Table 14 changes it with
climate. Endpoint alternatives are harvest/management choices, not uncertainty
bands or values to average. Table 11 says local variety/climate validation is
needed; all 13 relevant example rows remain separate. The sesame disagreement
is verified in the retrieved official HTML representation only; no conclusion
about every printed edition or erratum is claimed.

**Method compatibility.** Equations 56/58 give ETc = Kc × ETo. Equation 66 keeps
initial/mid constant and linearly interpolates development/late stages. Example
28 gives rounded Kc 0.15/0.77/1.19/0.56 at days 20/40/70/95. Exact day 40 is
0.774, so published rounding must be respected. With hypothetical ETo = 5 mm/day
for 100 days, the exact example curve sums to 71.70 coefficient-days and 358.50 mm
ETc. This total is a new **synthetic arithmetic demonstration**, not a published
crop water requirement. Unchanged Rust with one constant interval per day
reproduces it. A four-stage endpoint substitution instead gives 381.00 mm.
Daily encoding can preserve the method without changing Rust, but no encoding
of a priority crop curve is approved here. Missing ETo keeps the total unknown.

**Succession/fallow.** Handbook p.119/PDF133 §12.2 preserves lowland CS1/CS2
systems, including monsoon paddy with winter green gram or groundnut. It does
not establish a mandatory preceding crop, universal rice–pulse order, field
drainage, pest suppression, nitrogen credit or numerical fallow. Section 6.8's
cereal rotation text and maize intercrop text must not become the same sequence.
Other pairings remain research leads. Family identity and an empty date gap do
not supply complete attributed history or explicit fallow. No duration of fallow
is invented, including zero as a purported agronomic requirement.

## Integration disposition and next evidence

The nearest bounded duration lead is Myanmar erect-type groundnut, conditional
on cultivar/type, establishment and day-count review. Kc method evidence is
stronger than local Kc applicability: pursue reviewed stage dates, wetting,
climate/height adjustments and daily reference ETo before any crop ETc rule.
Planting calendars require regional extension/cultivar review and actual field
system mapping. Quantitative flood/drought rules and succession/fallow minima
need original experimental evidence. Further species expansion was deferred
because it would add scope without resolving these scientific acceptance gaps.

The [60-row evidence matrix](../../../data/crop-rule-candidates/v1/EVIDENCE_MATRIX.md)
and machine-readable blocked inventory are the acceptance record. Every inherited
mapping stays blocked. No ranking, recommendation, safety certification or merge
is delivered.
