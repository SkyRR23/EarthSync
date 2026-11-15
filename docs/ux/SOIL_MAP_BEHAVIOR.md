# Soil-first map

The field remains selected while switching between soil properties, street map, NASA GIBS true color and the existing HLS/NDVI workflow. The soil mode is the default; NDVI is a distinct vegetation layer. No terrain/hybrid provider is advertised.

The implementation reuses the integrated `earthsync.soil-map.v1` server contract from the existing SoilGrids work. It does not merge another branch wholesale or implement a second scientific engine. The private backend retrieves/validates bounded ISRIC data and returns up to 25 native cells around the confirmed point. This is not a farm-wide soil average.

`validatedSoilLayer` checks schema, source identity, pH units, depth, resolution, provenance hash, retrieval timestamp, bounded polygons/values and coverage of the selected point before display. A cached layer for a different point cannot become the current field's soil. Missing/malformed/source-incompatible results produce the unavailable path.

## Properties and suitability

- SoilGrids pH in water: modeled mean, 0–5 cm depth, 250 m source resolution, source hash/URL, original retrieval date. The backend's original dataset/limitations remain accessible through evidence.
- The continuous 0–14 legend represents pH only. Green denotes a numerically higher pH, not better soil. Nodata stays gray.
- Crop context displays the selected farmer-entered crop and an unknown suitability state. All 60 blocked rule candidates remain disabled. No numerical crop thresholds, confidence percentages or red/green planting recommendation is introduced.
- Boundary visibility/soil opacity controls do not alter the saved farm record. Satellite opacity applies to the display layer only.
- NASA GIBS carries its requested date and a warning that a requested date does not prove pixel acquisition. NDVI retains the existing QA/nodata/source workflow; greenness is not a soil or pest diagnosis.
- Missing tiles explain the network limitation while the locally saved boundary/pin remain usable.

## Manual checks

Add soil check opens a real local field-record editor. A numeric pH or texture value requires a measurement source, remains farmer-reported, and does not establish laboratory verification or sampling depth. Hand-feel observations remain observations. Photos are private local records with GPS metadata removed by the existing preparation pipeline. These records never synthesize raster values.

A fresh app with no accepted soil extract shows “No accepted soil extract saved for this field.” Existing data retrieval remains available through `/farm-evidence`. The new dataset registry does not make an uninstalled global SoilGrids raster operational. Live source availability must be assessed separately from rendering/software tests.
