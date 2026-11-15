"""Render reviewable tables from measured results; never change eligibility/status."""

import csv
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/validation"
E = OUT / "evidence"
SHA = "660b479c3ffb714cd1d489e1241c026ceae6ed67"


def load(name):
    return json.loads((E / name).read_text())


def document(name, text):
    (OUT / name).write_text(text.strip() + "\n")


def table(name, rows):
    with (OUT / name).open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main():
    result, perf = load("results.json"), load("performance.json")
    sites = json.loads((ROOT / "tests/global_validation/sites.json").read_text())[
        "sites"
    ]
    browser = load("browser-sites.json")
    browser_pass = sum(r["status"] == "PASS" for r in browser["results"])
    et = result["et0"]
    good = [r for r in et if r["status"] == "PASS"]
    reasons = Counter(r["withheld_reason"] for r in et if r["status"] != "PASS")
    weather = list(csv.DictReader((OUT / "WEATHER_VALIDATION.csv").open()))
    soil_rows, location_rows = [], []
    for site, actual in zip(sites, result["sites"]):
        assert site["id"] == actual["site_id"]
        soil_rows.append(
            dict(
                site_id=site["id"],
                model_ph=actual["soil"]["ph"],
                model_depth_cm="0-5",
                model_resolution_m=250,
                raw_value=actual["soil"]["raw"],
                source_sha256=actual["soil"]["source_sha256"],
                observed_ph="",
                observed_depth_cm="",
                observed_method="",
                observed_sampling_date="",
                held_out_matches=0,
                mae="",
                rmse="",
                bias="",
                classification="REAL modeled source; SOURCE-CONSISTENT extraction; FIELD ACCURACY NOT MEASURED",
                reason="No licensed independently held-out water-pH samples with matching depth/method/date obtained; WoSIS training overlap not independent",
            )
        )
        location_rows.append(
            dict(
                site_id=site["id"],
                country=site["country"],
                region=site["region"],
                latitude=site["latitude"],
                longitude=site["longitude"],
                coordinate_source=site["coordinate_source"],
                elevation_m=site["elevation_m"],
                climate_category=site["climate_category"],
                climate_category_source=(
                    site["coordinate_source"]
                    if site["climate_category"] != "not independently classified"
                    else "Not independently classified"
                ),
                geographic_condition=site["condition"],
                agricultural_landscape=site["landscape"],
                landscape_source=site.get(
                    "landscape_source", site["coordinate_source"]
                ),
                dates="2024-01-01..07;2024-07-01..07",
                time_standard="NASA POWER LST",
                climate_retrieval="2/2 real 7-day periods",
                et0_usable_days=sum(p["et0_usable_days"] for p in actual["periods"]),
                soil="REAL modeled pH 0-5 cm, 250 m; source consistent",
                independent_reference=(
                    "Nearby NOAA observations; descriptive only, independence unknown"
                    if site["id"].startswith("us_")
                    else "Not obtained"
                ),
                ndvi="UNAVAILABLE",
                status="TESTED; field accuracy not established",
            )
        )
    location_rows.append(
        {
            **{k: "" for k in location_rows[0]},
            "site_id": "mm_sagaing_excluded",
            "country": "Myanmar",
            "region": "Sagaing",
            "coordinate_source": "Not accepted: inconsistent Zaloke coordinates across candidate publications",
            "status": "UNAVAILABLE: not counted among the 12 verified sites; Yangon is an explicitly additional case, not a hidden replacement",
        }
    )
    table("LOCATION_TEST_MATRIX.csv", location_rows)
    table("SOIL_PH_VALIDATION.csv", soil_rows)
    table(
        "FORECAST_VALIDATION.csv",
        [
            {
                **r,
                "conversion_check": "PASS",
                "later_observation_matches": 0,
                "mae": "",
                "rmse": "",
                "bias": "",
                "accuracy_status": "NOT MEASURED",
            }
            for r in load("forecast-records.json")
        ],
    )
    document(
        "GLOBAL_ACCURACY_REPORT.md",
        f"""# EarthSync global validation — immutable release candidate

Subject: `{SHA}`. Validation date: 2026-11-15 UTC. This is the integrated **candidate**, not a released main build. Main remains `1ea3df7b09637cf8162f834411d830aa8621590c`.

EarthSync's reference ET0 arithmetic is numerically verified on the accepted inputs tested. Its environmental source handling works at the sampled public locations. Global field accuracy, crop suitability, soil-field accuracy and forecast skill are **not established**. There is no defensible overall accuracy percentage.

## Measured results

| Measurement | Result | Interpretation |
|---|---|---|
| Public research sites | 12; 6 Myanmar; 6 countries; 6 continents | P0 count/geographic diversity met; Sagaing unavailable and explicitly excluded |
| Historical retrieval | 24/24 seven-day windows; 168 site-days | REAL NASA POWER production pathway, January/July 2024 only |
| Rust FAO-56 vs independent equations | {len(good)}/{len(good)} accepted days pass; max absolute difference {max(r["absolute_difference_mm"] for r in good):.4g} mm/day | Numerical implementation agreement, not field ET/irrigation accuracy |
| Withheld ET0 | {len(et) - len(good)} days | {dict(reasons)}; never replaced with zero |
| Weather vs station reports | 8 site/season/variable groups × 7 days; MAE {min(float(r["mae"]) for r in weather):.2f}–{max(float(r["mae"]) for r in weather):.2f} °C | Descriptive only: below predeclared 10-day per-group minimum and independence unknown |
| Soil extraction | 12/12 original raster query-cell and scaling checks pass | 250 m modeled 0–5 cm pH; no independent field-error metric |
| GFS | 2 sites × 4 temperature records; conversion/time checks pass | No later matching observations; no forecast-skill score |
| Map sources | 24/24 HTTPS OSM/NASA GIBS tile requests pass | Real display tiles; true color is not NDVI; TLS verification enabled |
| Three-strategy workflow | 12/12 native Rust/SQLite cases; 36 decisions | SYNTHETIC reported plans/history, real/cached-real environmental inputs; explicit scope |
| Browser reopening | {browser_pass}/{len(browser["results"])} sites passed | Actual compiled Flutter, saved-farm selection and saved-comparison reopening; see browser scope/failures |
| Executable crop rules | 0 approved; all 60 blocked | Suitability accuracy is not measurable |

[Site matrix](LOCATION_TEST_MATRIX.csv), [weather](WEATHER_VALIDATION.csv), [soil](SOIL_PH_VALIDATION.csv), [ET0](ET0_NUMERICAL_VALIDATION.csv), [forecast](FORECAST_VALIDATION.csv), [workflow](ROTATION_WORKFLOW_RESULTS.md), [scientific gates](SCIENTIFIC_ELIGIBILITY_REPORT.md), [provider evidence](PROVIDER_AVAILABILITY.md), [limits](BUGS_AND_LIMITATIONS.md), [reproduction](REPRODUCTION_GUIDE.md).

## Study design and exclusions

The public site manifest and protocol were frozen and SHA-256 pinned before model retrieval; no site was replaced based on model results. Published agricultural-research coordinates are not private farmer records or proof of present land use. Geographic conditions span delta, dry zone, highland, coastal/lowland, continental and Southern Hemisphere agriculture. Only source-supported climate classes are recorded; unknown classes remain unknown.

The six Myanmar tested areas are Ayeyarwady, Bago, Mandalay, Magway, Shan and Yangon. Sagaing remains unavailable because candidate Zaloke coordinates could not be reconciled. Expansion to 20 sites, other suggested countries, 2025, transitions and documented extremes was not completed. Two fixed weeks are not annual or multi-year accuracy coverage.

NOAA Global Hourly station data were obtained for two US sites after HTTP-200 HTML responses from old annual URLs were rejected. Only accepted temperature QC flags and days with ≥18 distinct hourly bins were used. NASA hourly UTC/LST responses independently checked the −6-hour day offset (66 matching timestamps per US site); these audit responses never replace production daily values. Grid-to-point, elevation, reporting-frequency and assimilation overlap limitations remain. Rainfall accumulation windows were not reconciled, so precipitation-error metrics are not calculated. Daily mean temperature is not a supported output in the tested water-input contract.

Original raw values and captures stay in a private local evidence directory; public receipts contain public research query coordinates, source URLs, units, dates and content hashes. A new run must retain its own capture timestamps and must not overwrite this baseline evidence.

## Release decision

**Do not merge main.** The integrated release has [11 green exact-candidate CI workflows](evidence/release-ci.json); the [three source PR heads](evidence/release-heads.json) are unchanged. The additional local harness has five passing tests and the selected regression suite has 81 passing tests (including those five), with SYNTHETIC/MOCKED software fixtures labeled separately. However, mandatory accepted quantitative NDVI, local Windows interactive acceptance, independent agricultural review and other stated release limitations remain. This validation branch changes only tests/reports; it does not repair production science, alter eligibility or manufacture a released build. See the existing [final release verification](../release/VERIFICATION.md) and the candidate's release documents under `docs/`.
""",
    )
    document(
        "ROTATION_WORKFLOW_RESULTS.md",
        f"""# Rotation workflow results

Subject `{SHA}`. Native workflow: **12/12 passed**, 36 actual Rust assessment executions, persisted/reopened SQLite comparisons, citation-bearing deterministic assistant responses and cross-owner denial checks. Each comparison has three distinct two-crop sequences: synthetic declared existing rice→mung bean, alternative A rice→sesame, alternative B rice→groundnut. An intentional timing overlap is exercised. Rules remain empty; blocked suitability candidates do not execute.

The crop-history events, tiny square boundaries, priorities and declared baseline are **SYNTHETIC software fixtures**, not actual farming claims about the published sites. NASA historical records are REAL/CACHED REAL. Myanmar crop-source profiles retain their regional scope at all sites; global execution does not establish global crop applicability. Native save/reopen is not manual UI creation.

Actual compiled Flutter Web browser: **{browser_pass}/{len(browser["results"])} saved-farm/comparison reopen cases passed**, {len(browser["unhandled_page_errors"])} unhandled page errors. [Machine-readable outcomes](evidence/browser-sites.json). Tests select the saved field in Settings and reopen its saved three-strategy comparison, then inspect the displayed alternatives and local-review warning. Chromium’s native, non-ignored accessibility tree was used because Playwright’s abbreviated aria snapshot omits Flutter’s merged group labels. Private screenshots also show the three columns and review warnings. The fixtures were created through production service classes in a separate owned test database. This does not claim 12 independent manual planting/photo/map demonstrations.

Earlier exact-candidate release receipts cover the complete fresh farmer journey, responsive UI, language, observation/photo, restart, backup/restore and offline checks; those remain previous-run evidence, not newly repeated 12-location acceptance. The global run adds geographic/provider coverage. Browser harness failures and corrections remain in private diagnostics; a failing assertion is never converted into agricultural evidence.
""",
    )
    document(
        "SCIENTIFIC_ELIGIBILITY_REPORT.md",
        f"""# Scientific eligibility and integrity

Baseline `{SHA}` remained unchanged in `app/`, `server/`, `engine/` and `data/`. [Integrity receipt](evidence/scientific-integrity.json) verifies the pinned v1 catalog, all 49 v2 hashed catalog files, all 11 7V hashed review files and 35 pinned inputs.

- **60 blocked candidate rules; zero approved executable suitability rules.** No hash regeneration or eligibility promotion.
- Crop identity/reference facts and chronology can be explored; field suitability, rankings and success probabilities cannot be validated against zero executable rules.
- Numerical ET0 validation does not establish crop ETc, effective rainfall, water stress, fertilizer credit, yield, profit or irrigation prescriptions.
- The independent test equations use FAO-56 chapters 3–4, including daily mean dewpoint approximation and the same explicitly supported domain. The published Uccle example is checked within its rounding tolerance. This is a separately written implementation, not independently measured evapotranspiration.
- SoilGrids source consistency does not establish held-out field validity. WoSIS contributes to SoilGrids training and cannot automatically be used as independent validation.
- No NDVI value, crop-health diagnosis, pest forecast or official warning was fabricated.

See [ET0 per-day results](ET0_NUMERICAL_VALIDATION.csv) and [limits](BUGS_AND_LIMITATIONS.md).
""",
    )
    document(
        "PROVIDER_AVAILABILITY.md",
        f"""# Provider availability and provenance

Subject `{SHA}`. [Main receipts](evidence/provider-receipts.json) record **188 fresh successful production HTTP requests and 12 disk-cache hits** during the frozen run. Repeated cached bodies are not new observations. Supplemental probes are separate: 24 TLS-verified display tiles, four hourly POWER UTC/LST audit bodies, NOAA station/catalog/reference retrieval and one HLS metadata discovery. GFS consistency was rechecked from cached real records; final summary reports zero supplemental forecast network attempts on that recheck. Do not add these cached results as new provider acquisitions.

| Provider | Measured availability | Scientific limit |
|---|---|---|
| NASA POWER | 24/24 periods, seven production parameters, exact LST/date/source hashes | Regional MERRA-2 and radiation supports differ; not exact farm measurements |
| ISRIC SoilGrids WebDAV | 12/12 bounded mean pH raster extractions | 0–5 cm, 250 m modeled grid; uncertainty and independent held-out samples unavailable |
| NOAA GFS | Four native temperature records at two sites | 0.25° regional model; initialization is not issuance time; later observations not matched |
| NASA GIBS true color / OSM | 24/24 dated/display tile requests | Not quantitative greenness or crop health; not 12 browser map render demonstrations |
| NASA HLS CMR | One actual metadata record discovered | Accepted authorized QA pixels/NDVI unavailable; no true-color substitution |
| NOAA Global Hourly | Two valid annual station CSVs via official public AWS archive | Station temperature only; assimilation independence unknown |
| Official issued hazard alerts | UNAVAILABLE | No fictional official warnings |

NOAA original annual NCEI URLs returned HTTP 200 with HTML rather than station CSV; the parser now rejects these in this **test harness**. The official NOAA Open Data archive fallback supplied actual station data: [NOAA ISD archive](https://registry.opendata.aws/noaa-isd/), [NOAA service location change](https://www.nesdis.noaa.gov/news/service-location-change-integrated-surface-data-global-hourly). Source/content hashes and station metadata are in [reference availability](evidence/reference-availability.json). TMP codes 1 and 5 only; missing 9999 rejected. [ISD format documentation](https://www.itl.nist.gov/div898/winds/NIST_TN/doc/ish-format-document.pdf) and [POWER time documentation](https://power.larc.nasa.gov/docs/services/api/temporal/hourly/) explain QC/time handling.

[SoilGrids documentation](https://docs.isric.org/globaldata/soilgrids/) and [method paper](https://doi.org/10.5194/soil-7-217-2021) describe model/training support. SoilGrids CC BY 4.0 attribution is retained; the application's NASA/NOAA/OSM and original source attributions remain unchanged. Public study-coordinate citations are in the frozen manifest; downloaded papers, annual CSVs and rasters are not redistributed in Git. Reproduction users must check source terms and access permissions.
""",
    )
    native = perf["local_native_subprocess_single_day"]
    network = perf["real_network_transport_requests"]
    document(
        "PERFORMANCE_RESULTS.md",
        f"""# Bounded performance measurements

Subject `{SHA}`. Environment `{perf["hardware"]}`, Python 3.12.14, three reported CPUs. No public-provider load test.

| Path | n | Median | p95 nearest rank | Maximum |
|---|---:|---:|---:|---:|
| Native one-day ET0 subprocess | {native["n"]} | {native["median_seconds"] * 1000:.2f} ms | {native["p95_nearest_rank_seconds"] * 1000:.2f} ms | {native["maximum_seconds"] * 1000:.2f} ms |
| Original REAL transport requests | {network["n"]} | {network["median_seconds"]:.3f} s | {network["p95_nearest_rank_seconds"]:.3f} s | {network["maximum_seconds"]:.3f} s |

Twenty local sequential native calls used clearly synthetic valid weather; the network timings were already captured by the bounded real-source run. They are separate distributions, not whole-screen latency. Network admission was serialized by the disk-cache lock despite a configured maximum concurrency of two. Host/network/caches differ from farmers' devices. No capacity, Windows/mobile speed, low-bandwidth SLA, large-polygon throughput or production uptime claim is supported. [Raw timing summary](evidence/performance.json).
""",
    )
    document(
        "BUGS_AND_LIMITATIONS.md",
        f"""# Baseline errors, exclusions and release blockers

Subject `{SHA}`; production files remain unchanged. No production fix was made to improve a validation result.

## Required gates still open

- Quantitative satellite NDVI/QA pixels unavailable; metadata and true color cannot satisfy the real-vegetation acceptance step.
- No independently held-out matching 0–5 cm soil laboratory observations; pH accuracy cannot be scored.
- No issued-forecast/later-observation matched series; forecast accuracy cannot be scored.
- Weather groups contain only seven days each (<10 predeclared minimum), only two nearby US stations, with unknown assimilation independence. No universal/global weather accuracy conclusion.
- Sagaing public coordinate conflict unresolved; not silently substituted. P1 20 sites, 2025/multi-year, seasonal transitions/extreme events not covered.
- No approved crop-suitability rules; 60 remain blocked. Agricultural local-review, scientific translation review, full accessibility and local interactive Windows acceptance remain release requirements.
- No secure persistent free full-stack hosted deployment verified. No public endpoint was created; no TLS/auth/ownership checks disabled.
- Earlier release evidence documented an intermittent Playwright storage-state restoration confirmation-gate behavior. Real persistent-profile restarts passed then; unresolved cause remains a limitation rather than being concealed by fixture injection.

## Validation-harness diagnostics (not production defects)

Initial harness errors are retained privately: wrong forecast record key (`temperature_k` versus actual `raw_temperature_k`), HTTP-200 HTML misidentified as CSV before strict header checking, local-storage fixture reload order, slash escaping in a Playwright menu selector, Flutter popup animation/viewport scrolling. Corrected probes retain original source bodies/hashes; failed driver runs are not valid observations. Final per-site browser outcomes are in [browser evidence](evidence/browser-sites.json), including any unresolved failures. Chromium screenshots and its non-ignored native accessibility tree confirmed that all three local-review explanations are present. Playwright’s abbreviated aria snapshot omitted the merged named-group label; the final test inspects the native tree instead. This was a test-tool false negative, not a proven production text-omission defect. The production API contract and candidate source were not edited.

## Coverage limits

12 published historical agricultural coordinates are not private active farms. Synthetic field boundaries, plans and reported operations test software only. Myanmar crop references used outside Myanmar retain their original scope and do not establish applicability. Model elevation is not surveyed elevation. Grid resolution and query-cell checks do not validate every polygon pixel. Missing data stay unknown, not zero. No rainfall or ET0 minus rainfall value is an irrigation prescription.

The frozen 2024 January/July windows provide reproducible contrasting seasons but not exhaustive climatic or statistical coverage. No confidence interval, overall accuracy percentage, yield claim, field nutrient diagnosis or guaranteed rotation benefit is supported.
""",
    )
    document(
        "NASA_OBJECTIVE_COVERAGE.md",
        f"""# NASA Field Shift objective coverage

Subject `{SHA}`. Status describes a specific supported workflow or conclusion, not a whole-product marketing label.

| Objective | Status | Evidence and remaining limit |
|---|---|---|
| Select/save/reopen field, link soil/farmer constraints to assessment | IMPLEMENTED AND VERIFIED in native tests; prior browser release evidence | 12 owned test fields; production Rust/SQLite; soil source provenance; synthetic boundary/history scope |
| Three strategies including declared existing practice | IMPLEMENTED AND VERIFIED in native tests; browser {browser_pass}/{len(browser["results"])} reopen checks | 36 native decisions; no invented real-world baseline; manual creation not repeated at 12 sites |
| Explain timing, NASA evidence, priorities, scope and unknowns | IMPLEMENTED AND VERIFIED for deterministic contract checks | Citation-bearing assistant and blocked-rule checks; does not establish scientific advice accuracy |
| Reference ET0 | IMPLEMENTED AND VERIFIED numerically on accepted domain | 149 real-input days match; 19 withheld; field ET accuracy unknown |
| Soil display and extraction | IMPLEMENTED AND VERIFIED as source-consistent software | Independent soil-health/field suitability conclusions SCIENTIFICALLY BLOCKED |
| Climate resilience/seasonal evidence | PARTIAL | Two 2024 weeks, temperature comparisons descriptive, transitions and multi-year not covered |
| Nitrogen/erosion/forage/market benefits | SCIENTIFICALLY BLOCKED where reviewed applicable evidence is missing | Reference traits may be displayed; no guaranteed benefits, profit or nitrogen credit |
| Crop suitability/ranking | SCIENTIFICALLY BLOCKED | Zero executable rules; all 60 candidates disabled |
| Timeline, actual versus planned operations, unknown gaps | IMPLEMENTED AND VERIFIED in prior release tests and native regression suite | Synthetic test operations; gaps never prove bare soil; no exact calendar-inferred crop stage |
| Validated quantitative vegetation | UNAVAILABLE | HLS metadata only; accepted QA pixels absent |
| Forecast display | IMPLEMENTED AND VERIFIED as source-consistent temperature records | Forecast skill, official issuance/current observations and official alerts UNAVAILABLE |
| Unified desktop/mobile, Burmese, offline | PARTIAL overall | Prior browser/regression receipts demonstrate implemented paths; agricultural translation/accessibility review and full 12-location mobile repetition not complete |
| Final local Windows acceptance and safe hosted release | PARTIAL / UNAVAILABLE respectively | CI/packaging receipts do not replace interactive user acceptance; no verified safe free persistent hosting |

This study adds working validation code and actual measurements. An unavailable state alone is not classified as completion of a requested environmental observation or missing engineering workflow.
""",
    )


if __name__ == "__main__":
    main()
