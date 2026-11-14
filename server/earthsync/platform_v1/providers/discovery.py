"""Bounded HLS CMR discovery; metadata candidates never imply valid pixels."""

from datetime import datetime
from typing import Literal

from pydantic import Field
from shapely.geometry import Point as GeoPoint
from shapely.geometry import Polygon as GeoPolygon

from ..errors import PlatformError
from ..models import Contract, FarmInput

ENDPOINT = "https://cmr.earthdata.nasa.gov/search/granules.umm_json"


class DiscoveryQuery(Contract):
    farm: FarmInput
    start: datetime
    end: datetime
    product: Literal["HLSL30", "HLSS30"] = "HLSS30"
    limit: int = Field(default=20, ge=1, le=100)

    def validate_period(self):
        if (
            not self.start.tzinfo
            or not self.end.tzinfo
            or not 0 <= (self.end - self.start).total_seconds() <= 366 * 86400
        ):
            raise PlatformError("INVALID_INPUT")


def read_candidates(capture, query):
    data = capture.json()
    try:
        items = data["items"]
        if not isinstance(items, list) or len(items) > query.limit:
            raise PlatformError("SCHEMA_MISMATCH", 502)
        result = []
        point = GeoPoint(
            query.farm.confirmed_point.longitude, query.farm.confirmed_point.latitude
        )
        for item in items:
            value = item["umm"]
            ref = value["CollectionReference"]
            if ref["ShortName"] != query.product or ref["Version"] != "2.0":
                raise PlatformError("UNSUPPORTED_PRODUCT", 502)
            temporal = value["TemporalExtent"]
            date_string = (
                temporal.get("SingleDateTime")
                or temporal["RangeDateTime"]["BeginningDateTime"]
            )
            acquired = datetime.fromisoformat(date_string.replace("Z", "+00:00"))
            if acquired.tzinfo is None or not query.start <= acquired <= query.end:
                raise PlatformError("TEMPORAL_MISMATCH", 502)
            geometry = value["SpatialExtent"]["HorizontalSpatialDomain"]["Geometry"]
            polygons = []
            for polygon in geometry.get("GPolygons", []):
                ring = [
                    (p["Longitude"], p["Latitude"])
                    for p in polygon["Boundary"]["Points"]
                ]
                if not all(-180 <= x <= 180 and -90 <= y <= 90 for x, y in ring):
                    raise PlatformError("SPATIAL_MISMATCH", 502)
                shape = GeoPolygon(ring)
                if (
                    not shape.is_valid
                    or shape.area <= 0
                    or shape.bounds[2] - shape.bounds[0] > 180
                ):
                    raise PlatformError("SPATIAL_MISMATCH", 502)
                polygons.append(shape)
            if not polygons or not any(p.covers(point) for p in polygons):
                raise PlatformError("SPATIAL_MISMATCH", 502)
            result.append(
                {
                    "granule_id": value["GranuleUR"],
                    "collection": ref,
                    "acquired_at": acquired.isoformat(),
                    "original_geometry": geometry,
                    "metadata": value,
                    "farm_polygon_fully_covered": None,
                    "numeric_observation": False,
                    "reason": "Catalog discovery only; asset authorization, metadata, CRS, native QA and pixel coverage still require validation.",
                }
            )
        return {
            "status": "candidates" if result else "no_acquisitions",
            "records": result,
            "response_sha256": capture.sha256,
            "retrieved_at": capture.retrieved_at.isoformat(),
            "truncated": data.get("hits", len(items)) > len(items),
            "source_url": ENDPOINT,
        }
    except PlatformError:
        raise
    except (KeyError, TypeError, ValueError) as exc:
        raise PlatformError("SCHEMA_MISMATCH", 502) from exc


class HlsDiscovery:
    def __init__(self, transport):
        self.transport = transport

    async def retrieve(self, query):
        query.validate_period()
        point = query.farm.confirmed_point
        params = {
            "short_name": query.product,
            "version": "2.0",
            "point": f"{point.longitude},{point.latitude}",
            "temporal": f"{query.start.isoformat()},{query.end.isoformat()}",
            "page_size": query.limit,
        }
        return read_candidates(await self.transport.get(ENDPOINT, params), query)
