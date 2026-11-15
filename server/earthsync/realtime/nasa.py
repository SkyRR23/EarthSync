"""Latest NASA catalog evidence; discovery never claims numerical retrieval."""

from urllib.parse import urlencode, urlsplit
from datetime import timedelta

from .http import SourceError
from .providers import provenance

PRODUCTS = {
    "HLSL30_VI": "2.0",
    "HLSS30_VI": "2.0",
    "SPL4SMGP": "008",
    "GPM_3IMERGHHE": "07",
}
CONCEPTS = {
    "HLSL30_VI": "C3246892554-LPCLOUD",
    "HLSS30_VI": "C3246894861-LPCLOUD",
    "SPL4SMGP": "C3480440870-NSIDC_CPRD",
    "GPM_3IMERGHHE": "C2723758340-GES_DISC",
}
ASSET_HOSTS = {
    "data.lpdaac.earthdatacloud.nasa.gov",
    "data.nsidc.earthdatacloud.nasa.gov",
    "data.gesdisc.earthdata.nasa.gov",
    "gpm1.gesdisc.eosdis.nasa.gov",
}
ENDPOINT = "https://cmr.earthdata.nasa.gov/search/granules.umm_json"


class NasaCatalog:
    kind = "METADATA_ONLY"
    interval = 3600
    stale_after = 86400
    limitations = "NASA CMR metadata only. This catalog card does not contain numeric IMERG, SMAP or NDVI values. Acquisitions may be substantially older than nominal product latency. Earthdata authorization and product-specific numerical QA are still required."

    def __init__(self, http):
        self.http = http

    async def fetch(self, location, old, now):
        products, receipts = [], []
        for short_name, version in PRODUCTS.items():
            limit = 4 if short_name.startswith("HLS") else 1
            temporal = (
                {
                    "temporal": f"{(now - timedelta(days=45)).date()}T00:00:00Z,{(now + timedelta(days=1)).date()}T00:00:00Z"
                }
                if limit > 1
                else {}
            )
            url = (
                ENDPOINT
                + "?"
                + urlencode(
                    {
                        "short_name": short_name,
                        "version": version,
                        "point": f"{location['lon']},{location['lat']}",
                        "sort_key": "-start_date",
                        "page_size": limit,
                        **temporal,
                    }
                )
            )
            data, receipt = await self.http.json(
                url, ttl=900 if short_name == "GPM_3IMERGHHE" else self.interval
            )
            receipts.append(receipt)
            items = data.get("items")
            if not isinstance(items, list) or len(items) > limit:
                raise SourceError("INVALID_DATA")
            if not items:
                products.append(
                    {
                        "product": short_name,
                        "version": version,
                        "status": "DATASET_NOT_PUBLISHED",
                        "numeric_observation": False,
                    }
                )
                continue
            for item in items:
                umm, meta = item["umm"], item["meta"]
                if meta.get("collection-concept-id") != CONCEPTS[short_name]:
                    raise SourceError("UNSUPPORTED_PRODUCT_VERSION")
                extent = umm["TemporalExtent"]
                temporal = extent.get("RangeDateTime", {})
                urls = []
                for link in umm.get("RelatedUrls", []):
                    asset = urlsplit(link.get("URL", ""))
                    if (
                        link.get("Type") == "GET DATA"
                        and asset.scheme == "https"
                        and asset.hostname in ASSET_HOSTS
                        and not asset.query
                        and not asset.username
                    ):
                        urls.append(link["URL"])
                products.append(
                    {
                        "product": short_name,
                        "version": version,
                        "granule_id": umm["GranuleUR"],
                        "acquired_start": temporal.get("BeginningDateTime")
                        or extent.get("SingleDateTime"),
                        "acquired_end": temporal.get("EndingDateTime")
                        or extent.get("SingleDateTime"),
                        "catalog_revision_at": meta.get("revision-date"),
                        "catalog_checked_at": receipt["retrieved_at"],
                        "collection_concept_id": meta.get("collection-concept-id"),
                        "status": "METADATA_ONLY",
                        "numeric_observation": False,
                        "assets": urls,
                        "publication_at": None,
                        "reason": "Catalog discovery only; see separate numeric source state for asset and QA acceptance.",
                    }
                )
        return {
            "products": products,
            "provenance": [provenance(r) for r in receipts],
            "next_check": min(r["next_check"] for r in receipts),
            "checked_at": min(r["retrieved_at"] for r in receipts),
            "resolution": "Catalog footprints; HLS 30 m, SMAP ~9 km, IMERG 0.1° nominal support",
            "publication_at": None,
        }
