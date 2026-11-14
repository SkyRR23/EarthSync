"""One focused SoilGrids pH WCS path; no duplicate PR #17 REST reader.

Reference/probe only until a live raster and DescribeCoverage pair are accepted.
The WCS path avoids relying on the paused REST API, but still needs network access.
"""

import asyncio
from xml.etree import ElementTree

import rasterio
from rasterio.io import MemoryFile
from rasterio.warp import transform

from ..errors import PlatformError
from ..models import Contract, Point, Evidence, Measurement, Depth, Spatial, Temporal
from .power_daily import evidence_id

ENDPOINT = "https://maps.isric.org/mapserv"
NATIVE_CRS = "+proj=igh +datum=WGS84 +units=m +no_defs"


class SoilQuery(Contract):
    point: Point


def read_ph_raster(capture, query, descriptor):
    try:
        root = ElementTree.fromstring(descriptor.body)
        identifiers = [
            n.text for n in root.iter() if n.tag.rsplit("}", 1)[-1] == "CoverageId"
        ]
        if identifiers != ["phh2o_0-5cm_mean"]:
            raise PlatformError("SOIL_COVERAGE_MISMATCH", 502)
        with rasterio.Env(
            GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", GDAL_PAM_ENABLED="NO"
        ):
            with (
                MemoryFile(capture.body) as memory,
                memory.open(allowed_drivers=["GTiff"]) as ds,
            ):
                if (
                    not ds.crs
                    or ds.crs != rasterio.crs.CRS.from_string(NATIVE_CRS)
                    or ds.count != 1
                    or ds.width * ds.height > 100
                ):
                    raise PlatformError("SOIL_GRID_MISMATCH", 502)
                if (
                    any(
                        abs(abs(v) - 250) > 1e-6
                        for v in (ds.transform.a, ds.transform.e)
                    )
                    or ds.transform.b
                    or ds.transform.d
                ):
                    raise PlatformError("SOIL_RESOLUTION_MISMATCH", 502)
                if ds.dtypes != ("int16",) or ds.nodata is None:
                    raise PlatformError("SOIL_ENCODING_MISMATCH", 502)
                xs, ys = transform(
                    "EPSG:4326", ds.crs, [query.point.longitude], [query.point.latitude]
                )
                row, col = ds.index(xs[0], ys[0])
                if not 0 <= row < ds.height or not 0 <= col < ds.width:
                    raise PlatformError("SPATIAL_MISMATCH", 502)
                sample = ds.read(
                    1, window=rasterio.windows.Window(col, row, 1, 1), masked=True
                )
                value = None if sample.mask.any() else int(sample.data[0, 0])
                if value is not None and value < 0:
                    raise PlatformError("SCIENTIFIC_QUALITY_REJECTION", 502)
                bounds = ds.bounds
                original_geometry = {
                    "type": "Polygon",
                    "coordinates": [
                        [
                            [bounds.left, bounds.bottom],
                            [bounds.right, bounds.bottom],
                            [bounds.right, bounds.top],
                            [bounds.left, bounds.top],
                            [bounds.left, bounds.bottom],
                        ]
                    ],
                }
                document = dict(
                    provider="ISRIC SoilGrids",
                    dataset="SoilGrids250m 2.0",
                    dataset_version="2.0; WCS release identity unverified",
                    source_url=ENDPOINT,
                    source_identifier=identifiers[0],
                    data_type="modeled",
                    spatial=Spatial(
                        role="regional_context",
                        query_point=query.point,
                        original_geometry=original_geometry,
                        original_crs=ds.crs.to_wkt(),
                        support="Native modeled grid cell at point; neither laboratory sample nor field-wide average",
                        resolution_m=250,
                    ),
                    temporal=Temporal(
                        retrieved_at=capture.retrieved_at,
                        unknown_reason="Static model observation/training interval not supplied by this coverage",
                    ),
                    measurements=[
                        Measurement(
                            variable="ph",
                            original_value=value,
                            original_unit="pH x 10",
                            value=value / 10 if value is not None else None,
                            unit="pH",
                            conversion="native / 10",
                            depth=Depth(top_cm=0, bottom_cm=5),
                            statistic="mean",
                            quality="usable" if value is not None else "missing",
                            missing_reason="NODATA" if value is None else None,
                        )
                    ],
                    quality_flags=[
                        "LIVE_SOURCE_UNVALIDATED",
                        "DATASET_RELEASE_UNVERIFIED",
                        "UNCERTAINTY_QUANTILES_NOT_RETRIEVED",
                    ],
                    missing_reasons=["NODATA"] if value is None else [],
                    limitations=[
                        "Mapped estimate, not laboratory sample or field-wide average; no drainage inference.",
                        "WCS dataset release, quantiles and live transport acceptance remain unverified; reference only.",
                        "License: ISRIC SoilGrids CC BY 4.0; retain attribution.",
                    ],
                    usable_for_assessment=False,
                    review="reference_only",
                    response_sha256=capture.sha256,
                    source_metadata={
                        "policy": "soilgrids-ph-wcs-probe.v1",
                        "descriptor_sha256": descriptor.sha256,
                        "native_transform": list(ds.transform),
                        "nominal_resolution_m": 250,
                        "native_unit": "pH x 10",
                        "uncertainty_quantiles": None,
                    },
                )
                from fastapi.encoders import jsonable_encoder

                return Evidence(id=evidence_id(jsonable_encoder(document)), **document)

    except PlatformError:
        raise
    except (
        ElementTree.ParseError,
        rasterio.errors.RasterioError,
        ValueError,
        IndexError,
    ) as exc:
        raise PlatformError("SCHEMA_MISMATCH", 502) from exc


class SoilWcs:
    def __init__(self, transport):
        self.transport = transport
        self.slots = asyncio.Semaphore(1)
        self.last_attempt = 0.0

    async def retrieve(self, query):
        # Maximum one two-request operation per 30s, below 5 provider calls/min.
        import time

        async with self.slots:
            now = time.monotonic()
            if now - self.last_attempt < 30:
                raise PlatformError("LOCAL_PROVIDER_RATE_LIMIT", 429, True)
            self.last_attempt = now
            base = {
                "map": "/map/phh2o.map",
                "SERVICE": "WCS",
                "VERSION": "2.0.1",
                "COVERAGEID": "phh2o_0-5cm_mean",
            }
            descriptor = await self.transport.get(
                ENDPOINT, {**base, "REQUEST": "DescribeCoverage"}
            )
            x, y = transform(
                "EPSG:4326", NATIVE_CRS, [query.point.longitude], [query.point.latitude]
            )
            params = list(
                {
                    **base,
                    "REQUEST": "GetCoverage",
                    "FORMAT": "GEOTIFF_INT16",
                    "SUBSETTINGCRS": "http://www.opengis.net/def/crs/EPSG/0/152160",
                    "OUTPUTCRS": "http://www.opengis.net/def/crs/EPSG/0/152160",
                }.items()
            )
            params += [
                ("SUBSET", f"X({x[0] - 250},{x[0] + 250})"),
                ("SUBSET", f"Y({y[0] - 250},{y[0] + 250})"),
            ]
            capture = await self.transport.get(ENDPOINT, params)
            return await asyncio.to_thread(read_ph_raster, capture, query, descriptor)
