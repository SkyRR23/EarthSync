"""Separate optional satellite adapters, intentionally unavailable without QA.

No numeric ingestion path is exposed until collection, scale factors, matching
QA, pixel footprints and composite support have been independently verified.
The PR #11 values and GIBS image colours cannot satisfy these requirements.
"""

from .common import unavailable
from .models import Source

PRODUCTS = {
    "ndvi": ("MOD13Q1.061", "NDVI + DetailedQA + pixel reliability"),
    "evi": ("MOD13Q1.061", "EVI + DetailedQA + pixel reliability"),
    "land_surface_temperature": (
        "MOD11A2.061",
        "LST_Day/Night + QC_Day/Night + clear-sky support",
    ),
}


class VegetationAdapter:
    def __init__(self, kind):
        self.kind = kind
        product, self.required_bands = PRODUCTS[kind]
        self.source = Source(
            provider="NASA MODIS / ORNL DAAC",
            dataset=product,
            # A target collection, not an assertion about the audited CSVs.
            documentation=[
                f"https://ladsweb.modaps.eosdis.nasa.gov/filespec/MODIS/61/{product.split('.')[0]}",
                "https://modis.ornl.gov/data/modis_webservice.html",
            ],
            license="NASA Earth science open data; retain exact product citation",
            attribution="NASA MODIS; ORNL DAAC subset service, DOI 10.3334/ORNLDAAC/1600.",
        )

    async def context(self, query):
        evidence = unavailable(
            self.kind,
            self.source,
            query.point,
            "MATCHING_QA_AND_PIXEL_SUPPORT_UNAVAILABLE",
        )
        evidence.limitations = [
            f"Required matching bands: {self.required_bands}.",
            "Collection, raw fill/range/scale/offset, native pixel footprint, valid pixel counts and exact composite dates remain unverified.",
            "Missing QA never means good quality. No MODIS number or browse image is used for scientific conclusions.",
        ]
        return evidence
