"""Small native pixel/cell reads; no resampling or agronomic recommendations."""

import asyncio
from datetime import datetime, timedelta, timezone
import math
import os
import hashlib
import json
import threading

import numpy as np
import rasterio
from rasterio.warp import transform
from rasterio.windows import Window

from .http import SourceError
from .nasa import NasaCatalog
from .nasa_assets import AssetSession, RangeFile
from .providers import distance, timestamp


def text(value):
    return value.decode() if isinstance(value, bytes) else str(value)


def scalar(dataset, index, *, units=None, low=None, high=None):
    attrs = dataset.attrs
    if units is not None and text(attrs.get("units")) != units:
        raise SourceError("INVALID_UNITS_OR_DATA")
    value = float(dataset[index])
    missing = float(attrs.get("_FillValue", float("nan")))
    lower = float(attrs.get("valid_min", low if low is not None else -math.inf))
    upper = float(attrs.get("valid_max", high if high is not None else math.inf))
    if not math.isfinite(value) or value == missing or not lower <= value <= upper:
        raise SourceError("SCIENTIFIC_QA_REJECTION")
    # Packed HDF data need an explicit product-specific decoder, never a guess.
    if (
        float(attrs.get("scale_factor", 1)) != 1
        or float(attrs.get("add_offset", 0)) != 0
    ):
        raise SourceError("UNREVIEWED_DATA_SCALING")
    return value


def hls_pixel(product, location, session):
    assets = product["assets"]
    ndvi_url = next((u for u in assets if u.endswith(".NDVI.tif")), None)
    qa_url = next((u for u in assets if u.endswith(".Fmask.tif")), None)
    if not ndvi_url or not qa_url:
        raise SourceError("MISSING_SCIENTIFIC_ASSET")
    values, grids, metadata, sizes = [], [], [], []
    for url, name in ((qa_url, "qa.tif"), (ndvi_url, "ndvi.tif")):
        with RangeFile(session, url) as reader:

            def opener(path, mode="rb"):
                if path != name or mode not in ("r", "rb"):
                    raise FileNotFoundError(path)
                reader.seek(0)
                return reader

            with rasterio.Env(
                GDAL_PAM_ENABLED="NO", GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR"
            ):
                with rasterio.open(
                    name, opener=opener, allowed_drivers=["GTiff"]
                ) as ds:
                    if (
                        ds.count != 1
                        or not ds.crs
                        or not ds.crs.is_projected
                        or ds.crs.linear_units != "metre"
                        or ds.res != (30, 30)
                        or ds.transform.b != 0
                        or ds.transform.d != 0
                    ):
                        raise SourceError("RASTER_GRID_MISMATCH")
                    if (
                        name == "ndvi.tif"
                        and (
                            ds.dtypes != ("int16",)
                            or ds.nodata != -19999
                            or ds.scales != (0.0001,)
                            or ds.offsets != (0.0,)
                        )
                    ) or (
                        name == "qa.tif"
                        and (ds.dtypes != ("uint8",) or ds.nodata != 255)
                    ):
                        raise SourceError("RASTER_ENCODING_MISMATCH")
                    tags = ds.tags()
                    acquired = timestamp(tags["SENSING_TIME"])
                    if (
                        abs(
                            (
                                acquired - timestamp(product["acquired_start"])
                            ).total_seconds()
                        )
                        > 2
                    ):
                        raise SourceError("TEMPORAL_MISMATCH")
                    x, y = transform(
                        "EPSG:4326", ds.crs, [location["lon"]], [location["lat"]]
                    )
                    row, col = ds.index(x[0], y[0])
                    if not 0 <= row < ds.height or not 0 <= col < ds.width:
                        raise SourceError("SPATIAL_MISMATCH")
                    cell = ds.read(1, window=Window(col, row, 1, 1), masked=True)
                    values.append(
                        None if np.ma.is_masked(cell[0, 0]) else int(cell[0, 0])
                    )
                    if name == "qa.tif" and (
                        values[-1] is None
                        or values[-1] & 0b00111111
                        or (values[-1] >> 6) & 3 == 3
                    ):
                        raise SourceError(
                            "SCIENTIFIC_QA_REJECTION", details={"qa_value": values[-1]}
                        )
                    grids.append(
                        (ds.crs.to_wkt(), list(ds.transform), list(ds.shape), row, col)
                    )
                    metadata.append(
                        {
                            k: tags.get(k)
                            for k in (
                                "SENSING_TIME",
                                "MGRS_TILE_ID",
                                "scale_factor",
                                "add_offset",
                                "_FillValue",
                                "Fmask description",
                                "HLS_VI_PROCESSING_TIME",
                                "HLS_PROCESSING_TIME",
                            )
                        }
                    )
            sizes.append(reader.downloaded)
    qa, raw = values
    if grids[0] != grids[1]:
        raise SourceError("RASTER_GRID_MISMATCH")
    # Preserve the original conservative HLS v2 policy, including high aerosol.
    if (
        raw is None
        or qa is None
        or (qa & 0b00111111) != 0
        or ((qa >> 6) & 3) == 3
        or not -10000 <= raw <= 10000
    ):
        raise SourceError(
            "SCIENTIFIC_QA_REJECTION", details={"qa_value": qa, "raw_ndvi": raw}
        )
    return {
        "value": raw * 0.0001,
        "unit": "NDVI (dimensionless)",
        "raw_value": raw,
        "scale": 0.0001,
        "offset": 0,
        "qa_value": qa,
        "qa_policy": "hls-v2-conservative.v1; reject bits 0..5, high aerosol, fill and out-of-range NDVI",
        "grid": grids[0],
        "native_metadata": metadata,
        "bytes_downloaded": sum(sizes),
        "measurements": [
            {
                "variable": "ndvi",
                "value": raw * 0.0001,
                "unit": "dimensionless",
                "depth_cm": None,
            }
        ],
    }


def smap_cell(product, location, session):
    import h5py

    url = next((u for u in product["assets"] if u.endswith(".h5")), None)
    if not url:
        raise SourceError("MISSING_SCIENTIFIC_ASSET")
    with (
        RangeFile(session, url, budget=24 * 1024 * 1024, block_size=262144) as reader,
        h5py.File(reader, "r") as f,
    ):
        projection = f["EASE2_global_projection"].attrs
        if (
            text(projection["grid_mapping_name"]) != "lambert_cylindrical_equal_area"
            or float(projection["standard_parallel"]) != 30
            or float(projection["longitude_of_central_meridian"]) != 0
            or float(projection["false_easting"]) != 0
            or float(projection["false_northing"]) != 0
        ):
            raise SourceError("RASTER_GRID_MISMATCH")
        if (
            f["x"].shape != (3856,)
            or f["y"].shape != (1624,)
            or text(f["x"].attrs["units"]) != "m"
            or text(f["y"].attrs["units"]) != "m"
        ):
            raise SourceError("RASTER_GRID_MISMATCH")
        xs, ys = f["x"][:], f["y"][:]
        x, y = transform("EPSG:4326", "EPSG:6933", [location["lon"]], [location["lat"]])
        col, row = int(np.argmin(abs(xs - x[0]))), int(np.argmin(abs(ys - y[0])))
        lat, lon = float(f["cell_lat"][row, col]), float(f["cell_lon"][row, col])
        if (
            distance(location["lat"], location["lon"], lat, lon) > 15
            or int(f["cell_row"][row, col]) != row
            or int(f["cell_column"][row, col]) != col
        ):
            raise SourceError("SPATIAL_MISMATCH")
        records = []
        for name, depth in (("sm_surface", 5), ("sm_rootzone", 100)):
            ds = f["Geophysical_Data/" + name]
            if (
                ds.shape != (1624, 3856)
                or text(ds.attrs["grid_mapping"]) != "EASE2_global_projection"
            ):
                raise SourceError("RASTER_GRID_MISMATCH")
            value = scalar(ds, (row, col), units="m3 m-3", low=0, high=0.9)
            records.append(
                {
                    "variable": name,
                    "value": value,
                    "unit": "m³/m³",
                    "depth_cm": depth,
                    "depth_interpretation": f"0–{depth} cm model layer",
                    "native_long_name": text(ds.attrs["long_name"]),
                    "quality": "Native fill/valid-range checks; model-assimilated estimate, not a local sensor",
                }
            )
        return {
            "measurements": records,
            "grid": {
                "crs": "EPSG:6933",
                "row": row,
                "column": col,
                "lat": lat,
                "lon": lon,
                "cell_spacing_x_m": float(abs(xs[1] - xs[0])),
                "cell_spacing_y_m": float(abs(ys[1] - ys[0])),
            },
            "native_time": float(f["time"][0]),
            "native_time_unit": text(f["time"].attrs["units"]),
            "time_basis": "CMR observation interval retained; native SMAP J2000/atomic time is not relabeled as UTC",
            "bytes_downloaded": reader.downloaded,
        }


def imerg_cell(product, location, session):
    import h5py

    url = next((u for u in product["assets"] if u.endswith(".HDF5")), None)
    if not url:
        raise SourceError("MISSING_SCIENTIFIC_ASSET")
    with RangeFile(session, url) as reader, h5py.File(reader, "r") as f:
        grid = f["Grid"]
        if (
            grid["lat"].shape != (1800,)
            or grid["lon"].shape != (3600,)
            or grid["precipitation"].shape != (1, 3600, 1800)
        ):
            raise SourceError("RASTER_GRID_MISMATCH")
        lats, lons = grid["lat"][:], grid["lon"][:]
        row, col = (
            int(np.argmin(abs(lats - location["lat"]))),
            int(np.argmin(abs(lons - location["lon"]))),
        )
        if (
            abs(float(lats[row]) - location["lat"]) > 0.051
            or abs(float(lons[col]) - location["lon"]) > 0.051
        ):
            raise SourceError("SPATIAL_MISMATCH")
        if (
            text(grid["time_bnds"].attrs["units"])
            != "seconds since 1980-01-06 00:00:00 UTC"
        ):
            raise SourceError("INVALID_TIMESTAMP")
        bounds = grid["time_bnds"][0]
        epoch = datetime(1980, 1, 6, tzinfo=timezone.utc)
        start, end = (epoch + timedelta(seconds=int(v)) for v in bounds)
        if (
            (end - start).total_seconds() != 1800
            or abs((start - timestamp(product["acquired_start"])).total_seconds()) > 2
            or abs((end - timestamp(product["acquired_end"])).total_seconds()) > 2
        ):
            raise SourceError("TEMPORAL_MISMATCH")
        value = scalar(
            grid["precipitation"], (0, col, row), units="mm/hr", low=0, high=1000
        )
        quality = scalar(
            grid["precipitationQualityIndex"], (0, col, row), low=0, high=1
        )
        return {
            "measurements": [
                {
                    "variable": "precipitation_rate",
                    "value": value,
                    "unit": "mm/hour",
                    "depth_cm": None,
                },
                {
                    "variable": "precipitation_estimate_interval",
                    "value": value * 0.5,
                    "unit": "mm",
                    "depth_cm": None,
                },
            ],
            "grid": {
                "row": row,
                "column": col,
                "lat": float(lats[row]),
                "lon": float(lons[col]),
                "spacing_degrees": 0.1,
                "crs": "EPSG:4326",
            },
            "quality_index": quality,
            "qa_policy": "Native missingness, finite/range checks and nonmissing quality index; no unsupported high-quality threshold or field-accuracy claim",
            "interval_start": start.isoformat(),
            "interval_end": end.isoformat(),
            "bytes_downloaded": reader.downloaded,
        }


class NasaNumeric:
    def __init__(self, http, product, lock):
        self.http, self.product, self.lock = http, product, lock
        self.cancel_event = threading.Event()
        self.catalog = NasaCatalog(http)
        self.kind = (
            "LATEST_MODELED_SOIL_MOISTURE"
            if product == "smap"
            else "LATEST_SATELLITE_ESTIMATE"
        )
        self.interval = 900 if product == "imerg" else 3600
        self.stale_after = 86400
        self.limitations = {
            "smap": "Latest available regional NASA SMAP soil-moisture estimate, 9 km, model assimilated, 0–5 / 0–100 cm layers. Normally multi-day delay; never measured inside your farm.",
            "imerg": "NASA IMERG Early V07 regional precipitation estimate, 0.1°, half-hour interval, delayed publication. Never a rain gauge reading or instantaneous weather.",
            "hls_ndvi": "HLS-VI v2 numeric NDVI with conservative native Fmask QA at one 30 m point cell. Acquisition can be old; not a field mean or vegetation-health percentage.",
        }[product]

    def stop(self):
        self.cancel_event.set()

    async def fetch(self, location, old, now):
        if not os.getenv("EARTHDATA_TOKEN"):
            raise SourceError("AUTHENTICATION_REQUIRED")
        catalog = await self.catalog.fetch(location, None, now)
        names = {
            "smap": {"SPL4SMGP"},
            "imerg": {"GPM_3IMERGHHE"},
            "hls_ndvi": {"HLSL30_VI", "HLSS30_VI"},
        }[self.product]
        candidates = sorted(
            [
                p
                for p in catalog["products"]
                if p["product"] in names and p.get("assets")
            ],
            key=lambda p: p["acquired_start"],
            reverse=True,
        )
        if not candidates:
            raise SourceError("DATASET_NOT_PUBLISHED")
        # Catalog checks do not re-download an already accepted unchanged granule.
        if old and old.get("checked_candidate_ids") == [
            [p["granule_id"], p["catalog_revision_at"]] for p in candidates
        ]:
            return {
                **old,
                "checked_at": max(p["catalog_checked_at"] for p in candidates),
            }
        async with self.lock:
            return await asyncio.to_thread(
                self._extract, candidates, location, catalog, now
            )

    def _extract(self, candidates, location, catalog, now):
        session = AssetSession(self.cancel_event)
        rejected = []
        try:
            for product in candidates:
                qa_key = (
                    "qa:"
                    + hashlib.sha256(
                        json.dumps(
                            [
                                product["granule_id"],
                                product["catalog_revision_at"],
                                location["lat"],
                                location["lon"],
                            ]
                        ).encode()
                    ).hexdigest()
                )
                prior_rejection = (
                    self.http.repository.get(qa_key)
                    if self.product == "hls_ndvi"
                    else None
                )
                if prior_rejection:
                    rejected.append(prior_rejection)
                    continue
                begin = len(session.receipts)
                try:
                    extractor = {
                        "smap": smap_cell,
                        "imerg": imerg_cell,
                        "hls_ndvi": hls_pixel,
                    }[self.product]
                    result = extractor(product, location, session)
                except SourceError as exc:
                    rejection = {
                        "granule_id": product["granule_id"],
                        "reason": exc.code,
                        "quality_details": exc.details,
                    }
                    rejected.append(rejection)
                    if (
                        exc.code == "SCIENTIFIC_QA_REJECTION"
                        and self.product == "hls_ndvi"
                    ):
                        self.http.repository.put(qa_key, rejection)
                        continue
                    raise
                retrieved = datetime.now(timezone.utc).isoformat()
                return {
                    **result,
                    **{
                        k: product[k]
                        for k in (
                            "product",
                            "version",
                            "granule_id",
                            "acquired_start",
                            "acquired_end",
                            "catalog_revision_at",
                        )
                    },
                    "observed_at": product["acquired_start"],
                    "publication_at": None,
                    "checked_at": retrieved,
                    "ingested_at": retrieved,
                    "numeric_observation": True,
                    "checked_candidate_ids": [
                        [p["granule_id"], p["catalog_revision_at"]] for p in candidates
                    ],
                    "resolution": "30 m native cell"
                    if self.product == "hls_ndvi"
                    else "9 km EASE-Grid 2.0"
                    if self.product == "smap"
                    else "0.1° regional cell",
                    "source_range_receipts": session.receipts[begin:],
                    "full_asset_sha256": None,
                    "rejected_candidates": rejected,
                    "bytes_downloaded": session.downloaded,
                    "provenance": [
                        {
                            "url": r["source_url"],
                            "sha256": r["sha256"],
                            "hash_scope": f"bytes {r['range_start']}–{r['range_end']}",
                            "retrieved_at": retrieved,
                            "http_status": 206,
                            "request_ms": None,
                        }
                        for r in session.receipts[begin:]
                    ],
                }
        except SourceError:
            raise
        except Exception as exc:
            raise SourceError(
                "NUMERIC_EXTRACTION_FAILED_" + type(exc).__name__
            ) from None
        finally:
            session.close()
        raise SourceError("SCIENTIFIC_QA_REJECTION")
