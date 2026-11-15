# Scientific boundaries

Historical environmental inputs are real or cached-real modeled observations,
not observations of a real farmer's field. Scenario inputs are hypothetical and
labelled simulated. Software-test farms, polygons and crop histories are synthetic.

Rainfall sums valid daily PRECTOTCORR rates over their one-day support. Missing
days are never zero. Daily mean temperature uses original T2M, equally weighted
across valid days; `(Tmin+Tmax)/2` is not substituted. Tmin/Tmax summaries retain
actual accepted extrema. Every variable has expected/valid/missing day counts,
accepted-day statistic and a separate complete-period value, which is null if
any day is missing. Monthly/seasonal statistics use the same rules.

Reference ET0 comes solely from the unchanged compiled Rust FAO-56 pipeline.
Its original domain restrictions remain. An accepted-day ET0 subtotal is not a
complete season total. ET0 is not ETc, effective rainfall, irrigation requirement,
water availability, water stress or crop yield. The lab has no models for yield,
soil nutrient change, disease rates or suitability percentages.

POWER dates use NASA Local Solar Time swaths. They are not farmer civil dates or
UTC-day measurements. The API accepts this pinned LST contract only. A query point
is not a polygon-area average. Regional model support does not prove field accuracy.

Retrospective simulation applies hypothetical decisions to the archive available
now. As-of-date mode requires demonstrable retrieval/availability on or before
the decision timestamp and excludes observations on/after the decision day.
Unknown historical publication time is never inferred from a recent retrieval.
Current crop-reference identities support chronology mechanics only; their traits
are withheld in as-of result panels. No claim is made that retrospective outputs
were forecasts possible at the time.

Same-calendar-season comparisons map dates by calendar year. Invalid leap-day
mapping is rejected for review. Other custom seasons map hypothetical crop dates
by offset from the first season start; dates outside the target season are rejected.
Period lengths and missingness remain explicit. A contextual baseline is the
arithmetic mean of complete seasonal statistics, with equal weight per complete
season; excluded seasons and sample counts are listed. Partial periods are never
silently normalized. No anomaly, damage threshold or climate-change attribution
is calculated.

SoilGrids RUN05 pH is one static modeled layer. Moving the timeline never creates
annual pH estimates. Dated laboratory reports remain separate farmer journal
records. No interpolation of soil chemistry is introduced.

NASA GIBS true colour is display context, not numerical NDVI. Advertised tile date
coverage is checked, but actual acquisition time remains unknown. Clouds and
missing tiles are not healthy-crop evidence. The numerical NDVI blockers remain
until an authorized QA-valid raster pipeline is independently accepted.

All 60 candidate crop rules remain blocked. The catalog/review inputs, Rust
calculation and eligibility gates are unchanged. Unknown history gaps are never
bare-field/fallow assertions; declared hypothetical intervals remain simulated.
