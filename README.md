<div align="center">

<img src="app/assets/branding/earthsync-logo.png" alt="EarthSync leaf-and-orbit logo" width="170">

# EarthSync · Field Shift

**Satellite data made understandable for everyday farming decisions**

A NASA Space Apps Challenge 2026 project by **Team Cosmic Chaos**

[**Try the web app**](https://earth-sync-rose.vercel.app/) · [**Demo walkthrough**](docs/ux/SUBMISSION_HANDOFF.md) · [**Local setup**](docs/release/FINAL_LOCAL.md)

</div>

---

## 🌱 Welcome to EarthSync

Farmers need to make decisions while weather, soil moisture, and seasonal conditions change. EarthSync brings together environmental observations, crop references, and farmer-entered field information in a simpler interface.

Think of it as **a field notebook with a window into Earth observations**: it shows dated evidence, helps compare crop-rotation ideas, and lets farmers document decisions. It does **not** replace farmers, soil laboratories, or qualified agricultural advice.

> ### ⚠️ APK demo vs. real-time implementation
>
> **The shared Android APK uses simulated/demo data. It is not a real-time data application.** Treat its screens and sample values as a demonstration of the user experience, not as current measurements, live warnings, or validated crop recommendations.
>
> **The repository also includes a real-time-ready implementation**—data-provider integrations, backend services, source timestamps, and local launch/test scripts. Live retrieval depends on running and configuring those services, third-party availability, permissions, and successful validation. **Real-time-ready does not mean the APK receives live data or that the hosted web app exposes the complete local backend.**
>
> The [local real-time guide](docs/realtime/README.md), [verification notes](docs/realtime/VERIFICATION.md), and [final local startup](docs/release/FINAL_LOCAL.md) explain the implementation and its limits.

## ✨ What can you explore?

| Feature | Purpose |
| --- | --- |
| **Farm map & field context** | Choose a field and distinguish mapped/model data from information reported by a farmer. |
| **Weather & climate evidence** | Inspect dated rainfall, temperature, forecast and other available environmental context. |
| **Soil information** | View modeled soil properties with source and resolution caveats; these are not laboratory measurements. |
| **Crop information & rotation comparison** | Explore source-backed crop references and compare a farmer-declared rotation with alternatives. |
| **Vegetation (NDVI) views** | Examine satellite vegetation information where imagery access, quality checks and coverage allow it. |
| **Farmer tools** | Keep tasks, notes, observations, photos and saved decisions in supported local workflows. |
| **Accessible assistant** | Explore evidence using simpler language, citations and stated uncertainty; some scientific material remains in English. |

**No guaranteed recommendations:** The project's 60 candidate crop-suitability rules remain blocked pending scientific review. EarthSync does not identify an approved “best crop,” predict farm income, or prescribe irrigation from satellite data alone.

## 🛰️ Data and scientific context

| Source / method | Used for |
| --- | --- |
| **NASA POWER** | Historical weather and climate inputs |
| **NASA HLS vegetation products** | Quality-screened NDVI satellite imagery, when available |
| **ISRIC SoilGrids** | Modeled soil-property context |
| **Weather observations and forecast services** | Dated conditions, model projections and regional context |
| **FAO-56 Penman–Monteith** | Reference evapotranspiration (ET₀), not crop irrigation demand |
| **Crop references and farmer observations** | Crop facts, rotation histories, local priorities and reported field details |

Each product has its own scale and update schedule. A regional soil estimate or model forecast is **not** the same as an on-farm measurement. See [source provenance](docs/release/PROVENANCE.md) and [capability coverage](docs/release/COVERAGE.md).

## 🧮 How our calculations work

**Simple explanation:** EarthSync is like a **field notebook connected to a scientific calculator**. Data comes from dated NASA/weather/soil products; Python checks and organizes it; Rust performs deterministic calculations; Flutter helps the farmer explore the evidence. **These are codebase methods, not proof that the simulated-data APK performs live calculations.**

### Methods at a glance

| Method | Equation or operation | Purpose | Current boundary |
| --- | --- | --- | --- |
| **Monthly rainfall** | Sum daily precipitation rate × 1 day | Convert NASA POWER PRECTOTCORR from mm/day to a monthly accumulation in mm | Requires every day of the month |
| **Monthly mean air temperature** | Sum daily T2M readings / number of days | Describe average daily-mean temperature, in °C | No incomplete-month substitution |
| **Seasonal rainfall** | Sum monthly rainfall accumulations | Summarize precipitation over selected *full* calendar months | Missing month → unknown total |
| **Seasonal mean temperature** | Sum(days in month × monthly mean) / total days | Properly weight months of different lengths | Missing month → unknown mean |
| **NDVI** | (NIR − Red) / (NIR + Red) | Describe vegetation greenness, using red and near-infrared satellite reflectance | Quality-accepted pixels only; not a health percentage |
| **FAO-56 reference ET₀** | Penman–Monteith equation below | Estimate reference-grass atmospheric water demand in mm/day | Not irrigation advice |
| **Growing degree days (GDD)** | Sum max(0, (Tmin + Tmax)/2 − crop base temperature) | Calculate accumulated temperature above an explicitly supplied base | Conditional v0.3 rule check; not approved crop suitability |
| **Growing-period rainfall** | Sum daily rain over the inclusive crop period | Compare a declared growing period against eligible source-backed criteria | No invented rainfall for missing days |
| **Crop ETc** | ETc = Kc × ET₀ | Calculate standard-condition crop evapotranspiration with documented stage coefficients | Conditional v0.3 calculation; not actual irrigation need |
| **Crop duration and rotation timing** | Inclusive days = harvest date − planting date + 1 | Check explicit schedules, planting windows, succession and recorded fallow periods | Evidence checks, not automated “best crop” rankings |

### 1. NASA POWER: rainfall and temperature

The [Python NASA POWER adapter](server/earthsync/power.py) reads daily T2M (°C) and PRECTOTCORR (mm/day) for a specified point and period. It checks source lineage, units, dates and the local solar time convention before aggregation.

For a month of **n** observed days:

$
P_{\mathrm{month}}=\sum_{d=1}^{n}(r_d\times1\ \mathrm{day})
$

$
T_{\mathrm{month}}=\frac{1}{n}\sum_{d=1}^{n}T_d
$

Here **r** is the daily precipitation rate in mm/day, so multiplying by one day produces millimetres; **T** is daily mean temperature in °C.

The [Rust seasonal module](engine/src/seasonal.rs) combines complete months:

$
P_{\mathrm{season}}=\sum_m P_m,\qquad
\overline{T}_{\mathrm{season}}=\frac{\sum_m d_m T_m}{\sum_m d_m}
$

The weight **d** is the actual number of days in each month. For example, months with **30 mm** and **45 mm** of rain total **75 mm**, provided **both months are complete**. If one is missing, EarthSync reports the total as unknown, rather than assuming the missing month had no rain.

**Implementation nuance:** The older [12-month field-summary code](engine/src/climate.rs) uses an *unweighted* mean of twelve complete monthly temperatures; it is distinct from this day-weighted seasonal method. Neither is a crop-yield prediction.

### 2. NDVI: satellite vegetation greenness

Plants absorb red light and reflect much near-infrared (**NIR**) light. The Normalized Difference Vegetation Index (NDVI) compares them:

$
\mathrm{NDVI}=\frac{\mathrm{NIR}-\mathrm{Red}}{\mathrm{NIR}+\mathrm{Red}}
$

Example: NIR = 0.60 and Red = 0.20 gives **NDVI = 0.50**. This **does not mean a plant is 50% healthy**.

The [HLS farm-greenness module](server/earthsync/greenness.py) scales reflectance, rejects invalid/fill values and cloud, shadow, snow and water flags, and can calculate a mean/median from the valid pixels inside a supplied field polygon. The [local HLS-VI workflow](docs/release/FINAL_LOCAL.md) handles precomputed NASA vegetation rasters with the documented 0.0001 scaling, native 30 m grid, QA masks, acquisition dates and bounded map extraction. Availability depends on authorized and accepted imagery.

**NDVI does not measure soil nitrogen, phosphorus, potassium, pH, or crop yield.** A missing or cloudy satellite pixel stays missing.

### 3. FAO-56 Penman–Monteith: reference evapotranspiration (ET₀)

The [Rust FAO-56 engine](engine/src/v03/water.rs) implements the **daily reference-grass Penman–Monteith method**:

$
\mathrm{ET}_0 =
\frac{0.408\Delta(R_n-G)+\gamma\frac{900}{T+273}u_2(e_s-e_a)}
{\Delta+\gamma(1+0.34u_2)}
$

| Symbol | Meaning |
| --- | --- |
| **ET₀** | Reference evapotranspiration, mm/day |
| **Δ** | Slope of saturation vapour-pressure curve, kPa/°C |
| **Rn** | Net radiation, MJ/m²/day |
| **G** | Soil heat flux (the daily reference calculation uses G = 0) |
| **γ** | Psychrometric constant, kPa/°C |
| **T** | Daily mean temperature, °C |
| **u₂** | Wind speed at 2 m, m/s |
| **es − ea** | Saturation minus actual vapour pressure, kPa |

The code also derives vapor pressure, vapour-pressure-curve slope, solar/radiation factors, and the psychrometric constant using the supplied weather, latitude, elevation and day of year. It validates required daily minimum/maximum temperature, dew point, wind, pressure, solar energy and location inputs; invalid or incomplete days do **not** become zero.

**Metaphor:** ET₀ describes how strongly the atmosphere is **asking for water** from standard grass. It is **not** measured soil water, crop-specific water need, or how much a farmer must irrigate.

For a specific crop, an additional *conditional* [v0.3 engine check](engine/src/v03/assess.rs) implements:

$
\mathrm{ETc}_d=K_{c,d}\times\mathrm{ET0}_d
$

The crop coefficient (**Kc**) needs source-backed, reviewed growth-stage values for every relevant day. ETc is standard-condition crop evapotranspiration, **not** a complete water balance or an irrigation prescription.

### 4. Growing degree days (GDD) and crop-period checks

The opt-in [v0.3 assessment engine](engine/src/v03/assess.rs) can compute:

$
\mathrm{GDD}=\sum_d\max\left(0,\frac{T_{\min,d}+T_{\max,d}}{2}-T_{\mathrm{base}}\right)
$

This totals temperature above a **crop-specific, supplied base**. GDD is like a **heat counter** for a growing period—not a predicted harvest date, plant-health score, or yield forecast. The engine does not assume a universal 10 °C base.

Other deterministic checks compare inclusive planting/harvest durations, planting-window dates, growing-period rainfall, crop succession, explicit fallow days and compatible sourced soil observations. They preserve scope, source IDs and uncertainty rather than picking a crop automatically.

**Critical:** All **60 crop-suitability candidate rules are blocked** pending independent review. There are **zero approved executable crop recommendations**. The arithmetic and synthetic software tests do not authorize suitability rankings or claims that a particular rotation improves yields. See [engine contract](docs/ENGINE_CONTRACT_v0.3.md) and [scientific limits](docs/realtime/SCIENTIFIC_LIMITATIONS.md).

### 5. Soil evidence, data quality and missing values

[ISRIC SoilGrids](https://www.isric.org/explore/soilgrids) provides **modeled soil properties**; the project has documented a modeled **0–5 cm pH reference layer** at nominal **250 m** support. It is **not a field laboratory test** or a soil nutrient measurement extracted from a photo. The application does not turn such a regional estimate into a universal “soil quality score.”

Before using a number, the processing pipeline checks:

1. **Provenance:** Which source produced it? Was it observed, modeled, forecast, farmer-reported or synthetic? What date does it describe?
2. **Units and scope:** mm versus mm/day; °C versus other units; soil depth; calendar convention; model-grid cell versus confirmed field.
3. **Completeness and quality:** Missing dates are unknown, not zero; incompatible inputs are rejected; satellite clouds/fill are masked.
4. **Scientific eligibility:** Crop requirements must be approved and applicable to the production system, location and evidence. Conflicting records trigger review instead of being averaged into a false certainty.

**Bottom line:** NASA and other sources provide environmental evidence, EarthSync performs transparent calculations where inputs are valid, and the farmer sees understandable context and its limitations. **The Android APK still demonstrates the interface with simulated data; the full local implementation is separate and real-time-ready, subject to configuration and verification.**


## 🛠️ Technology

| Component | Technology |
| --- | --- |
| User interface | Flutter / Dart |
| API and integration | Python / FastAPI |
| Scientific and evidence processing | Rust |
| Local structured data | SQLite |
| Farm maps | Map layers and OpenStreetMap-based context |

Simplified flow:

```text
NASA / weather / soil / crop sources + farmer input
                       ↓
           Backend and Rust processing
                       ↓
          Dated evidence + local records
                       ↓
             Flutter app interface
                       ↓
           Explore • Compare • Save
```

Some workflows run locally without sign-in. Fresh external observations require connectivity and properly configured providers; cached evidence keeps its original dates.

## 🚀 Run locally

Use the local launcher to evaluate the **full-stack implementation**, not the simulated-data APK.

**Requirements:** Python 3.12+, Rust/native toolchain (reviewed with Rust 1.99.0), Flutter 3.44.0 / Dart 3.12.0, and build tools for your platform. Some NASA services require optional Earthdata authorization.

```bash
git clone https://github.com/SkyRR23/EarthSync.git
cd EarthSync
```

**Windows (PowerShell):**

```powershell
.\start-earthsync.ps1
```

**Linux / macOS:**

```bash
./start-earthsync.sh
```

Wait for the launcher's readiness checks and open **the browser URL printed by the launcher**. It may use a different local port on different machines.

| Action | Windows | Linux / macOS |
| --- | --- | --- |
| Smoke test | `.\test-earthsync.ps1` | `./test-earthsync.sh` |
| Stop services | `.\stop-earthsync.ps1` | `./stop-earthsync.sh` |

The scripts build and run local services; they do not deploy the backend to the public website. Private databases, photos, credentials and local runtime state should not be committed.

For prerequisites, logs, testing, missing-source behavior, and known limitations, see [FINAL_LOCAL.md](docs/release/FINAL_LOCAL.md).

## 🎬 Demo and deployment notes

- **Android APK:** simulated/demo data; **not** a live-data feed.
- **Public web app:** [earth-sync-rose.vercel.app](https://earth-sync-rose.vercel.app/). Feature and backend availability at this public URL must be checked independently; the link alone is not proof of live NASA integration.
- **Full local stack:** use the launcher above for the backend and available real-time provider integrations. Sources may be delayed, missing, unauthorized or unavailable.
- **Satellite imagery and AI:** vegetation access is conditional; ordinary field photos do not automatically measure soil chemistry. Optional vision functionality requires separate configuration and consent.

Use the [five-minute judging walkthrough](docs/ux/SUBMISSION_HANDOFF.md) to demonstrate the farmer journey. Be clear when a screenshot is illustrative rather than a real observation.

## 📚 Documentation

- [Final local setup and demonstration](docs/release/FINAL_LOCAL.md)
- [Farmer experience and submission handoff](docs/ux/SUBMISSION_HANDOFF.md)
- [Real-time integration and sources](docs/realtime/README.md)
- [Real-time verification and unresolved gates](docs/realtime/VERIFICATION.md)
- [Feature coverage and scientific limitations](docs/release/COVERAGE.md)
- [Data provenance, privacy and licensing](docs/release/PROVENANCE.md)
- [Release and hosting limitations](docs/release/HOSTING.md)

## 🤝 Team

**Cosmic Chaos** — Hein Lin, Yan Nan Aung, Htoo Htoo Aung and Amara Cho.

Built for the NASA Space Apps Challenge 2026. Thanks to the public Earth-observation, agricultural and open-source communities whose datasets and tools help make this work possible.

---

<div align="center">

**EarthSync — turning complex Earth data into understandable field context.**

</div>
