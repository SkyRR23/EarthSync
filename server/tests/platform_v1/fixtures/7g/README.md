# Cached real provider test data

These are public regional pixels near the software-test coordinate
42.0308, -93.6319; they do not identify or measure a farmer's field.

- ISRIC SoilGrids CC BY 4.0, 0–5 cm mean pH, RUN05 model snapshot. Source URL,
  retrieval time and SHA256: docs/integration/7g/evidence/soil-webdav-tile.receipt.json.
  Source VRT hash: soil-vrt.receipt.json. Nodata remains -32768; native /10 → pH.
- NOAA NCEP GFS US government data, 2026-11-14 12 UTC initialization, f006,
  2 m temperature 0.25° bounded GRIB2. Source URL, retrieval time and hash:
  docs/integration/7g/evidence/gfs-grib.receipt.json. Native Kelvin → Celsius.

The tests use cached real bytes. Synthetic arrays in test_soil_webdav.py test
failure/missingness behavior and are never displayed as observations.
