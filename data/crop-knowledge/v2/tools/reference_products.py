"""Read official metadata without turning product descriptions into observations."""

import json


def gaez_reference(raw):
    document = json.loads(raw)
    if document.get("success") is not True:
        raise ValueError("FAO catalog did not return a successful result")
    package = document["result"]
    if (
        package["id"] != "dc08a00f-db26-42bf-b59b-871a3bb69e36"
        or package["name"] != "gaez-v5-master-config"
    ):
        raise ValueError("wrong GAEZ dataset identity/version")
    if package["license_id"] != "CC-BY-4.0":
        raise ValueError("unreviewed GAEZ license")
    if not package["resources"]:
        raise ValueError("GAEZ metadata has no resources")
    return {
        "provider": "FAO / IIASA",
        "dataset": "GAEZ v5",
        "package_id": package["id"],
        "metadata_modified": package["metadata_modified"],
        "license": package["license_id"],
        "resources": [
            {"id": r["id"], "name": r["name"], "format": r["format"], "url": r["url"]}
            for r in package["resources"]
        ],
        "numerical_extract": None,
        "review": "reference_only",
        "usable_for_assessment": False,
        "required_product_dimensions": [
            "crop / land utilization type",
            "water supply and input management",
            "variable and original unit/scale",
            "climate model and scenario",
            "baseline/time period",
            "native CRS, grid resolution and bounded geographic support",
            "nodata and quality semantics",
        ],
        "limitations": [
            "Master config is a reference-data discovery product; no numeric crop suitability or yield retrieved.",
            "Future modeled suitability/yield extracts must retain all dimensions and cannot become local crop rules or farmer-yield predictions.",
        ],
    }
