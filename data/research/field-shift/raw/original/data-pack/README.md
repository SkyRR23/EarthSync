# Field Shift data pack

Real, downloaded farm-decision data for the three pilot townships, plus the
factor → API reference the team asked for.

Read `api.txt` first. It is grouped by the six factors we defined (weather,
soil, NASA Earth observation, crop, crop health, farm management), and for each
source it lists the exact URL, whether a key is needed, what the response
contains, a real sample, and where the data has limits.

## What is inside

```
api.txt                       factor -> endpoint -> fields -> sample -> status
README.md                     this file
scripts/fetch_sources.py      re-downloads everything (standard library only)
csv/                          the tables (one header row, ISO dates, units in names)
  power_daily_<loc>.csv          120 days, 10 weather/soil-wetness variables
  power_monthly_<loc>.csv        2016-2025 monthly means (engine input era)
  power_climatology_<loc>.csv    2001-2025 monthly normals
  forecast16_<loc>.csv           16-day forecast + rain probability + ET0
  current_<loc>.csv              conditions right now
  era5land_daily_<loc>.csv       365 days of ERA5-Land daily values
  river_discharge_<loc>.csv      16-day GloFAS river discharge (flood signal)
  soilgrids_<loc>.csv            pH, texture, SOC, N, CEC, bulk density x 4 depths
  modis_ndvi_<loc>.csv           16-day NDVI, 2024-2025
  modis_evi_<loc>.csv            16-day EVI, 2024-2025
  modis_lst_day_<loc>.csv        8-day day land-surface temperature, deg C
  modis_lst_night_<loc>.csv      8-day night land-surface temperature, deg C
  modis_landcover_<loc>.csv      yearly IGBP land-cover class, 2015-2024
  terrain_grid_<loc>.csv         5x5 elevation grid (Copernicus DEM 90 m)
  terrain_summary.csv            relief and slope per field
  satellite_availability_cmr.csv which satellite products actually cover the fields
  us_nv_ssurgo_components.csv    USDA soil components at the Nevada reference point
  us_nv_elevation.csv            USGS 3DEP elevation at the same point
tiles/                        NASA GIBS map tiles (NDVI, LST, IMERG, true colour)
_meta/fetch_log.csv           every HTTP request: URL, status, bytes, outcome
```

`<loc>` is `hlegu`, `bago` or `magway`.

## Reproduce it

```bash
python3 data-pack/scripts/fetch_sources.py            # fetch what is missing
python3 data-pack/scripts/fetch_sources.py --force    # refetch everything
python3 data-pack/scripts/fetch_sources.py --only soil
```

No `pip install`, no API key, no Earthdata account. The script writes only
inside `data-pack/` and never overwrites the engine's contracts.

## What is deliberately NOT here

Sources that need an Earthdata Login are documented in `api.txt` but not
downloaded: SMAP granules, GPM IMERG granules, ECOSTRESS, GEDI, Landsat,
NLDAS/GLDAS. Faking them would be worse than leaving a labelled gap. The route
is `earthaccess` (free account) in every case, and
`csv/satellite_availability_cmr.csv` already proves which of them have granules
over these coordinates.

## Three things that will bite you if nobody says them

1. **SoilGrids units are not percentages.** `phh2o` is pH × 10, texture is
   `g/kg` (divide by 10 for %), SOC is `dg/kg`, nitrogen is `cg/kg`. Every row
   therefore has `value`/`unit` exactly as the provider sent it **and**
   `value_si`/`unit_si` already converted (pH 6.3, clay 33.4 %). Use
   `value_si`; the raw pair is there so a reviewer can check us.
2. **POWER monthly precipitation is a mm/day rate**, not a monthly total. The
   existing `scripts/build_data.py` multiplies by days in the month; keep doing
   that or the water balance will be off by ~30×.
3. **A photo cannot measure pH, N, P, K or exact moisture.** The 5-photo
   protocol in `api.txt` section 2.6 is for texture class, colour, surface
   condition and confidence — it confirms or contradicts SoilGrids, it does not
   replace a lab test.

## How this plugs into what we already built

The Rust engine takes `field-context.<loc>.v1.json` (12 monthly normals) and a
crop library. Nothing in this pack changes that contract. The pack is the
evidence layer behind it, plus the pieces the app needs next:

- `forecast16_*` → the "what should I do this week" card (POWER cannot do this,
  it is reanalysis, not forecast).
- `soilgrids_*` → the soil card outside the US, where SSURGO does not exist.
- `modis_ndvi_*` → the vegetation-stress chart and the anomaly message.
- `satellite_availability_cmr.csv` → the honesty check before promising a layer.
- `tiles/` → a map background with no GIS stack in the app.

## Data honesty rules this pack follows

- A missing value is empty, never `0` and never a guess.
- Every number is traceable to a URL in `_meta/fetch_log.csv`.
- US-only sources are labelled; they are not used for the Myanmar fields.
- A product that returned no granule is reported as "no granule", not hidden.

Compiled 2026-11-14. Re-run the script before the demo: forecasts and current
conditions are only valid on the day they were downloaded.
