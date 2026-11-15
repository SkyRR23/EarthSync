"""Bounded, capability-validated GIBS display context. Never numerical NDVI."""

from datetime import date
import xml.etree.ElementTree as ET

from .errors import PlatformError
from .store import cache_key

CAPABILITIES = (
    "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/1.0.0/WMTSCapabilities.xml"
)
LAYER = "MODIS_Terra_CorrectedReflectance_TrueColor"
NAMESPACES = {
    "w": "http://www.opengis.net/wmts/1.0",
    "o": "http://www.opengis.net/ows/1.1",
}


def dimensions(body):
    try:
        root = ET.fromstring(body)
        for layer in root.findall(".//w:Layer", NAMESPACES):
            if layer.findtext("o:Identifier", namespaces=NAMESPACES) != LAYER:
                continue
            for dimension in layer.findall("w:Dimension", NAMESPACES):
                if dimension.findtext("o:Identifier", namespaces=NAMESPACES) == "Time":
                    return [
                        v.text
                        for v in dimension.findall("w:Value", NAMESPACES)
                        if v.text
                    ]
    except (ET.ParseError, ValueError) as exc:
        raise PlatformError("IMAGERY_CAPABILITIES_INVALID", 502) from exc
    raise PlatformError("IMAGERY_TIME_DIMENSION_UNAVAILABLE", 503)


def supported(day, values):
    for value in values:
        parts = value.split("/")
        try:
            if len(parts) == 1 and date.fromisoformat(parts[0][:10]) == day:
                return True
            if (
                len(parts) == 3
                and parts[2] == "P1D"
                and date.fromisoformat(parts[0][:10])
                <= day
                <= date.fromisoformat(parts[1][:10])
            ):
                return True
        except ValueError:
            continue
    return False


async def imagery(store, transport, day):
    key = cache_key("NASA GIBS", LAYER, "capabilities.v1", {})
    caps = store.cache_get(key)
    if caps is None:
        capture = await transport.get(CAPABILITIES, {})
        caps = {
            "values": dimensions(capture.body),
            "sha256": capture.sha256,
            "retrieved_at": capture.retrieved_at.isoformat(),
        }
        store.cache_put(key, caps, ttl=86400)
    available = supported(day, caps["values"])
    return {
        "layer": LAYER,
        "requested_date": str(day),
        "acquired_at": None,
        "status": "available_display_context" if available else "unavailable_date",
        "time_dimensions": caps["values"],
        "capabilities_sha256": caps["sha256"],
        "capabilities_retrieved_at": caps["retrieved_at"],
        "tile_url": f"https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/{LAYER}/default/{day}/GoogleMapsCompatible_Level9/{{z}}/{{y}}/{{x}}.jpg"
        if available
        else None,
        "limitations": [
            "Requested tile date does not prove an exact acquisition date. Acquisition metadata unavailable.",
            "Clouds, missing tiles and incomplete imagery remain unknown. True colour is visual context, not NDVI or crop health.",
        ],
    }
