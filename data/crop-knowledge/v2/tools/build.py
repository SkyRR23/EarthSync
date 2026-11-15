"""Deterministically rebuild the offline reference package from reviewed inputs."""

import argparse
from copy import deepcopy
import hashlib
import json

from importers import agricultural_categories, ecocrop_csv, ecocrop_sheet
from knowledge import (
    ROOT,
    PARAMETERS,
    VERSION,
    encoded,
    index,
    mapping_report,
    read_json,
    validate,
)

UNKNOWN = "No independently applicable source claim accepted for this crop, region, cultivar, system and statistic."
LIMIT = "Reference only; neither a farm observation nor an independently accepted executable requirement."


def unknown():
    return {
        "state": "unknown",
        "value": None,
        "unit": None,
        "statistic": "unknown",
        "temporal_support": "unknown",
        "spatial_support": "unknown",
        "method": "unknown",
        "claim_ids": [],
        "review": "reference_only",
        "uncertainty": "unquantified",
        "missing_reason": UNKNOWN,
    }


def profile(
    id,
    crop_id,
    region=None,
    system="reference_unspecified",
    season=None,
    context="",
    cultivar=None,
):
    return {
        "id": id,
        "crop_id": crop_id,
        "region_id": region,
        "production_system": system,
        "cultivar": cultivar,
        "country": region[:2] if region and region[:2] in {"MM", "AU", "US"} else None,
        "agroecological_zone": region if region and "-FAO-AEZ-" in region else None,
        "season": season,
        "source_context": context or LIMIT,
        "recommendation_eligible": False,
        "approved_for_candidates": False,
        "review": "reference_only",
        "executable_rules": [],
        "parameters": {k: unknown() for k in PARAMETERS},
        "limitations": [LIMIT],
    }


def generate(root=ROOT):
    editorial = read_json(root / "editorial.json")
    sources = read_json(root / "sources.json")
    source_index = index(sources)
    # A changed upstream source must become a new reviewed import, never an implicit refresh.
    for record in read_json(root / "original-manifest.json"):
        raw = (root / record["path"]).read_bytes()
        if (
            len(raw) != record["bytes"]
            or hashlib.sha256(raw).hexdigest() != record["sha256"]
        ):
            raise ValueError("original provider/mirror bytes changed")
    rows = ecocrop_csv(
        (root / "originals/ecocrop_openclim_ea43ecd.csv").read_bytes(),
        editorial["expected_ecocrop_rows"],
    )
    priorities = {c["ecocrop_id"]: c for c in editorial["priority_crops"]}
    taxa = index(read_json(root / "evidence/taxon-checks.json"))
    for crop in priorities.values():
        taxon = taxa[crop["grin_source"]]
        if (
            any(taxon[k] != crop[k] for k in ["scientific_name", "family", "aliases"])
            or taxon["source_response_sha256"]
            != source_index[crop["grin_source"]]["response_sha256"]
        ):
            raise ValueError("priority taxon differs from checked original identity")
    crops, profiles, claims, inventory = [], [], [], []

    def claim(
        id,
        source_id,
        locator,
        crop_id,
        parameter,
        value,
        unit,
        statistic,
        region=None,
        system=None,
        cultivar=None,
        temporal="Source reference; not a dated environmental observation",
        spatial="Global species reference; regional applicability unverified",
        method="Source factual extraction",
        kind="published_guidance",
        limitations=None,
        supporting_sources=None,
    ):
        result = {
            "id": id,
            "source_id": source_id,
            "source_version": source_index[source_id]["version"],
            "locator": locator,
            "supporting_source_ids": supporting_sources or [],
            "crop_id": crop_id,
            "parameter": parameter,
            "value": value,
            "unit": unit,
            "statistic": statistic,
            "region_id": region,
            "production_system": system,
            "cultivar": cultivar,
            "temporal_support": temporal,
            "spatial_support": spatial,
            "method": method,
            "review": "reference_only",
            "evidence_kind": kind,
            "uncertainty": "Unquantified; source descriptors are not calibrated local confidence intervals.",
            "limitations": [LIMIT, *(limitations or [])],
        }
        claims.append(result)
        return result

    def attach(p, c):
        p["parameters"][c["parameter"]] = {
            "state": "available",
            **{
                k: deepcopy(c[k])
                for k in [
                    "value",
                    "unit",
                    "statistic",
                    "temporal_support",
                    "spatial_support",
                    "method",
                    "uncertainty",
                ]
            },
            "claim_ids": [c["id"]],
            "review": "reference_only",
            "missing_reason": None,
        }

    for row_number, row in enumerate(rows, start=2):
        eco_id = row["EcoPortCode"]
        crop_id = "ecocrop." + eco_id + "@1"
        categories = agricultural_categories(row)
        preferred = priorities.get(eco_id)
        if preferred:
            categories = sorted(set([*categories, preferred["category"]]))
        inventory.append(
            {
                "source_id": "ecocrop_openclim_ea43ecd",
                "source_record_id": eco_id,
                "scientific_name_as_published": row["ScientificName"],
                "source_categories": row["CAT"],
                "source_cultivation_attributes": row["PLAT"],
                "agricultural_catalog_id": crop_id if categories else None,
                "disposition": "cultivated_agricultural_reference"
                if categories
                else "excluded_pending_documented_agricultural_basis",
                "authenticity": "third_party_snapshot_not_official_export; priority_fields_crosschecked_only",
            }
        )
        if not categories:
            continue
        aliases = (
            preferred["aliases"]
            if preferred
            else sorted(
                {
                    a.strip()
                    for a in row["COMNAME"].split(",")
                    if a.strip() and a.strip() != "NA"
                }
            )
        )
        family = (
            preferred["family"]
            if preferred
            else row["FAMNAME"].split(":")[-1].strip() or "unknown"
        )
        name = preferred["scientific_name"] if preferred else row["ScientificName"]
        identity = {"scientific_name": name, "aliases": aliases, "family": family}
        c = claim(
            "identity-" + eco_id,
            preferred["grin_source"] if preferred else "ecocrop_openclim_ea43ecd",
            "Taxon heading; Nomenclature/Summary/Family; ECOCROP names and editorial English aliases"
            if preferred
            else f"CSV row {row_number}; EcoPortCode={eco_id}; ScientificName, COMNAME, FAMNAME, CAT, PLAT",
            crop_id,
            "identity",
            identity,
            "taxonomic_identity",
            "species identity; aliases do not establish requirements",
            method="GRIN identity/family checked; documented editorial English alias normalization"
            if preferred
            else "Pinned mirror identity transcription; source family nomenclature retained",
            kind="taxonomy",
            supporting_sources=["ecocrop_" + preferred["label"]]
            if preferred
            else ["fao_ecocrop_metadata"],
            limitations=[
                "Additional mirror identities have not been independently reconciled against current accepted taxonomy."
            ],
        )
        crops.append(
            {
                "id": crop_id,
                **identity,
                "categories": categories,
                "agricultural_basis": "Official crop datasheet use plus GRIN species check"
                if preferred
                else "ECOCROP CAT agricultural class AND PLAT grown on small/large scale; conservative documented subset",
                "identity_claim_id": c["id"],
                "profile_coverage": "reference_profiles"
                if preferred
                else "identity_only",
                "recommendation_eligible": False,
                "approved_for_candidates": False,
                "review": "reference_only",
            }
        )
        if not preferred:
            continue
        p = profile(
            preferred["label"] + ".global.ecology@1",
            crop_id,
            context="Historical global ECOCROP descriptors, not Myanmar thresholds; environmental average minimum/maximum growing-season temperatures per help 2000, not daily-extreme limits.",
        )
        sheet = ecocrop_sheet(
            (root / f"originals/ecocrop_{preferred['label']}.html").read_bytes(), name
        )
        # Cross-check every accepted priority numerical descriptor against the pinned mirror.
        checks = {
            "ecological_temperature": ["TOPMN", "TOPMX", "TMIN", "TMAX"],
            "annual_precipitation": ["ROPMN", "ROPMX", "RMIN", "RMAX"],
            "ecological_soil_ph": ["PHOPMN", "PHOPMX", "PHMIN", "PHMAX"],
        }
        for key, fields in checks.items():
            values = sheet[key]
            actual = [
                values[scope][bound]
                for scope in ["optimal", "absolute"]
                for bound in ["min", "max"]
            ]
            if actual != [float(row[f]) for f in fields]:
                raise ValueError("official ECOCROP/mirror disagreement: " + key)
        for key, value in sheet.items():
            if value is None or (
                isinstance(value, dict) and all(v is None for v in value.values())
            ):
                continue
            units = {
                "ecological_temperature": "celsius",
                "annual_precipitation": "mm",
                "ecological_soil_ph": "pH",
                "altitude": "m",
                "ecological_crop_cycle": "days",
                "climate_zone": "qualitative",
            }
            unit = units.get(key, "source_category")
            locator = {
                "ecological_temperature": "Ecology / Temperat. requir.; optimal/absolute Min/Max",
                "annual_precipitation": "Ecology / Rainfall (annual); optimal/absolute Min/Max",
                "ecological_soil_ph": "Ecology / Soil PH; optimal/absolute Min/Max",
                "ecological_crop_cycle": "Cultivation / Crop cycle Min/Max",
            }.get(key, "Ecology / " + key)
            c = claim(
                preferred["label"] + ".eco." + key,
                "ecocrop_" + preferred["label"],
                locator,
                crop_id,
                key,
                value,
                unit,
                "ECOCROP annual rainfall envelope; query guidance also allows supplemental water"
                if key == "annual_precipitation"
                else "Environmental average minimum/maximum growing-season temperature ecological envelopes (help 2000); not daily extrema"
                if key == "ecological_temperature"
                else "ECOCROP original descriptor",
                kind="ecological_descriptor",
                temporal="Annual descriptor, mm; no growing-period allocation, irrigation/ground/run-on inputs allowed by query help 2001"
                if key == "annual_precipitation"
                else "Undated ecological reference; source publication unknown",
                supporting_sources={
                    "ecological_temperature": ["ecocrop_help_2000"],
                    "annual_precipitation": ["ecocrop_help_2001"],
                    "altitude": ["ecocrop_help_2003"],
                }.get(key, []),
                limitations=[
                    "No selected cultivar or validated Myanmar production-system applicability.",
                    "Soil depth describes ecological class, never a laboratory sampling interval.",
                ],
            )
            attach(p, c)
        profiles.append(p)

    labels = {
        p["label"]: "ecocrop." + p["ecocrop_id"] + "@1" for p in priorities.values()
    }
    calendar = read_json(root / "evidence/myanmar-calendar-facts.json")
    discrepancies = []
    for session in calendar:
        crosswalk = editorial["calendar_mapping"][session["crop_code"]]
        label = crosswalk["label"]
        crop_id = labels[label]
        suffix = session["locator"].replace("/", "-").strip("-")
        comments = session["comments"].lower()
        disputed = crosswalk["status"] == "identity_disputed"
        system = "cultivation_unspecified"
        if not disputed:
            if label == "rice":
                if "rainfed, lowland" in comments:
                    system = "rainfed_lowland"
                elif "upland rice" in comments:
                    system = "upland_water_supply_unspecified"
                elif "irrigated" in comments:
                    system = "irrigated_lowland_unspecified_management"
            elif "rainfed" in comments:
                system = "rainfed_upland"
            elif "irrigated" in comments:
                system = "irrigated_upland"
            elif "residual moisture" in comments:
                system = "residual_moisture_unspecified"
        context = f"Provider crop code {session['crop_code']} / {session['provider_crop_name']}; {session['comments']}"
        if disputed:
            context = (
                "IDENTITY DISPUTED; tentative research association only. " + context
            )
            discrepancies.append(
                {
                    "profile_id": label + ".mm.calendar-" + suffix + "@1",
                    "source_locator": session["locator"],
                    "reason": "Maize vs sweet-corn labels conflict"
                    if label == "maize"
                    else "0157 Green gram (Vigna aureus) and 0232 Mung bean/Penauk identity/duration conflicts; no automatic taxonomic merge",
                    "disposition": "retain separately; independent identity review required; mapping blocked",
                }
            )
        p = profile(
            label + ".mm.calendar-" + suffix + "@1",
            crop_id,
            session["region_id"],
            system,
            session["season"],
            context,
        )
        for key in ["planting_window", "harvest_window", "growing_duration"]:
            c = claim(
                p["id"] + "." + key,
                "fao_calendar_mm",
                session["locator"]
                + "/"
                + {
                    "planting_window": "early_sowing + later_sowing",
                    "harvest_window": "early_harvest + late_harvest",
                    "growing_duration": "growing_period",
                }[key],
                crop_id,
                key,
                session[key],
                "days" if key == "growing_duration" else "MMDD",
                "advisory source duration; inclusive-day convention unknown"
                if key == "growing_duration"
                else "advisory month/day endpoints; not guaranteed field window",
                region=p["region_id"],
                system=system,
                temporal="Seasonal calendar; lastUpdated " + session["updated_on"],
                spatial=session["provider_region_name"]
                + "; advisory agroecological zone, not farm boundary",
                kind="advisory_calendar",
                limitations=[
                    context,
                    "Calendar periods do not guarantee a compatible planting/harvest pair or duration.",
                    "No irrigation adequacy, rainfall requirement, precise cultivar or field drainage supplied.",
                ],
            )
            attach(p, c)
        profiles.append(p)

    # Deliberately separate management references from global ecological descriptors.
    for label, initial, mid, end, system, basis in [
        (
            "rice",
            1.05,
            1.20,
            {"min": 0.60, "max": 0.90},
            "flooded_irrigated_lowland",
            "Paddy rice; Kc initial depends on water surface, humidity and wind; Table 14 adjustments needed",
        ),
        (
            "mung_bean",
            None,
            1.05,
            {"min": 0.35, "max": 0.60},
            "cultivation_unspecified",
            "Green gram and cowpeas group; end 0.60 fresh / 0.35 dry (footnote 6)",
        ),
        (
            "groundnut",
            None,
            1.15,
            0.60,
            "cultivation_unspecified",
            "Groundnut; initial column blank in row, no group-value inheritance",
        ),
        (
            "sesame",
            None,
            1.10,
            0.25,
            "cultivation_unspecified",
            "Sesame; initial column blank in row, no group-value inheritance",
        ),
        (
            "maize",
            None,
            1.20,
            {"min": 0.35, "max": 0.60},
            "cultivation_unspecified",
            "Field maize; end 0.60 high grain moisture / 0.35 field dry (footnote 11); sweet corn distinct",
        ),
    ]:
        p = profile(
            label + ".global.fao56@1", labels[label], system=system, context=basis
        )
        c = claim(
            label + ".fao56.kc",
            "fao56_kc",
            "Chapter 6, Table 12 crop row; footnotes 6, 11 as relevant; paddy initial subsection/Table 14",
            labels[label],
            "kc_stages",
            {
                "initial": initial,
                "mid": mid,
                "end": end,
                "stage_offsets": None,
                "basis": basis,
            },
            "dimensionless",
            "tabulated standard-condition single crop coefficients, not complete daily stages",
            system=system,
            kind="method_reference",
            limitations=[
                "No stage offsets, local adjustments, daily ET0 or irrigation water balance.",
                basis,
            ],
        )
        attach(p, c)
        c = claim(
            label + ".fao56.method",
            "fao56_method",
            "Chapter 5, equation 56",
            labels[label],
            "et0_method",
            "Standard-condition ETc uses aligned grass-reference ET0 and an applicable Kc; no ET0 observations supplied.",
            "qualitative",
            "method only",
            kind="method_reference",
        )
        attach(p, c)
        profiles.append(p)

    for label, system, sensitivity, stage in [
        ("rice", "flooded_irrigated_lowland", "high", "head development and flowering"),
        (
            "maize",
            "cultivation_unspecified",
            "medium-high",
            "flowering and grain filling",
        ),
        (
            "groundnut",
            "cultivation_unspecified",
            "low-medium",
            "flowering and pod setting",
        ),
    ]:
        p = profile(
            label + ".global.water-stress@1",
            labels[label],
            system=system,
            context="FAO irrigation-scheduling training reference; qualitative sensitivity is not a water quantity.",
        )
        for key, value, locator in [
            (
                "drought_tolerance",
                "Sensitivity to water shortages: " + sensitivity,
                "Table 1",
            ),
            (
                "stage_vulnerabilities",
                "Water-shortage-sensitive period: " + stage,
                "Table 2",
            ),
        ]:
            attach(
                p,
                claim(
                    label + ".water-stress." + key,
                    "fao_water_stress",
                    "Chapter 2, " + locator,
                    labels[label],
                    key,
                    value,
                    "qualitative",
                    "published qualitative training guidance",
                    system=system,
                ),
            )
        profiles.append(p)

    p = profile(
        "groundnut.mm.erect-type@1",
        labels["groundnut"],
        "MM-central-dry-zone",
        "cultivation_unspecified",
        context="FAO Myanmar handbook; erect-type group, not a selected named cultivar.",
        cultivar="erect_type_unspecified_variety",
    )
    attach(
        p,
        claim(
            "groundnut.mm.erect-duration",
            "fao_myanmar_handbook_2022",
            "Printed page 7 (PDF page 21), section 1.3.1",
            labels["groundnut"],
            "growing_duration",
            {"min": 90, "max": 100},
            "days",
            "published erect-type duration; inclusive-day convention unspecified",
            region=p["region_id"],
            system=p["production_system"],
            cultivar=p["cultivar"],
            spatial="Central dry zone of Myanmar; cultivar group",
            limitations=[
                "Prostrate type separately described in months; not converted to fixed day counts.",
                "Calendar erect-type values differ; retain both within their own contexts.",
            ],
        ),
    )
    profiles.append(p)
    p = profile(
        "rice.mm.rainfed-upland-research@1",
        labels["rice"],
        "MM-FAO-AEZ-005",
        "rainfed_upland",
        context="Requested research scope. Calendar documents upland rice but does not explicitly verify rainfed supply; every requirement unknown.",
    )
    profiles.append(p)
    for label in ["mung_bean", "maize"]:
        profiles.append(
            profile(
                label + ".mm.rainfed-research@1",
                labels[label],
                "MM-research-target",
                "rainfed_upland",
                context="Caller-declared research target only. Calendar crop identity is disputed; every requirement remains unknown.",
            )
        )
    p = profile(
        "rice.au.drill-delayed-flood@1",
        labels["rice"],
        "AU-NSW-Riverina",
        "irrigated_drill_sown_delayed_flood",
        context="Inherited 7J/v1 landing-page reference; full Primefact not independently reviewed. No stage-specific v0.3 mapping.",
    )
    attach(
        p,
        claim(
            "rice.au.drill-system",
            "nsw_drill",
            "Summary; Primefact 1253 edition block; v1 claim riverina_drill_water",
            labels["rice"],
            "flooded_management",
            "Flush irrigation for drill-sown establishment precedes permanent water; timing depends on stage.",
            "qualitative",
            "management sequence reference",
            region=p["region_id"],
            system=p["production_system"],
            spatial="Southern NSW / Riverina; not Myanmar",
            limitations=[
                "Do not apply continuous-flood guidance to establishment or upland rice."
            ],
        ),
    )
    profiles.append(p)

    rotation_claims = {}
    for key, source, locator, text in [
        (
            "rice_mung",
            "fao_myanmar_handbook_2022",
            "Printed page 119 (PDF page 133), section 12.2, CS1",
            "Lowland cropping context includes monsoon paddy and winter cash crops including green gram; exact field scheduling not supplied.",
        ),
        (
            "rice_groundnut",
            "fao_myanmar_handbook_2022",
            "Printed page 119 (PDF page 133), section 12.2, CS2",
            "Lowland cropping context includes monsoon paddy followed by winter cash crops including groundnut; farm drainage and sequence feasibility unknown.",
        ),
        (
            "groundnut_cereal",
            "fao_myanmar_handbook_2022",
            "Printed page 62 (PDF page 76), section 6.8; citing Nataraja et al. 2014",
            "General groundnut/cereal rotation pest-management context; no maize-specific order, quantified benefit or accepted fallow period.",
        ),
        (
            "wheat_sorghum_fallow",
            "kstate_rotation",
            "Large-Scale Dryland Cropping Systems abstract; inherited v1 claim tribune_wsf",
            "Wheat-sorghum-fallow studied near Tribune during 2008–2020; no farm-specific calendar or transferable yield claim.",
        ),
    ]:
        rotation_claims[key] = claim(
            "rotation." + key,
            source,
            locator,
            None,
            "rotation_context",
            text,
            "qualitative",
            "reported cropping context",
            kind="research_context",
        )["id"]
    sesame_after_rice = next(
        c["id"]
        for c in claims
        if c["source_id"] == "fao_calendar_mm"
        and c["crop_id"] == labels["sesame"]
        and "after rice" in " ".join(c["limitations"])
        and c["parameter"] == "planting_window"
    )
    by_name = {c["scientific_name"]: c["id"] for c in crops}
    labels["wheat"], labels["sorghum"] = (
        by_name["Triticum aestivum"],
        by_name["Sorghum bicolor"],
    )
    for label in ["wheat", "sorghum"]:
        profiles.append(
            profile(
                label + ".us.tribune-reference@1",
                labels[label],
                "US-KS-Tribune",
                "dryland",
                context="Research rotation identity only; no accepted crop requirements.",
            )
        )
        next(c for c in crops if c["id"] == labels[label])["profile_coverage"] = (
            "reference_profiles"
        )
    profile_by_label = {
        label: label + ".global.ecology@1"
        for label in labels
        if label not in {"wheat", "sorghum"}
    }
    profile_by_label.update(
        {label: label + ".us.tribune-reference@1" for label in ["wheat", "sorghum"]}
    )
    rotations = []
    sequences = [
        ("rice-mung", ["rice", "mung_bean"], [rotation_claims["rice_mung"]]),
        ("rice-sesame", ["rice", "sesame"], [sesame_after_rice]),
        ("rice-groundnut", ["rice", "groundnut"], [rotation_claims["rice_groundnut"]]),
        ("maize-mung", ["maize", "mung_bean"], []),
        (
            "maize-groundnut",
            ["maize", "groundnut"],
            [rotation_claims["groundnut_cereal"]],
        ),
        (
            "groundnut-maize",
            ["groundnut", "maize"],
            [rotation_claims["groundnut_cereal"]],
        ),
        ("sesame-pulses", ["sesame", "mung_bean"], []),
        (
            "wheat-sorghum-fallow",
            ["wheat", "sorghum", "fallow"],
            [rotation_claims["wheat_sorghum_fallow"]],
        ),
    ]
    for id, sequence, support in sequences:
        cycles = []
        for i, label in enumerate(sequence):
            cycles.append(
                {
                    "kind": "fallow" if label == "fallow" else "crop",
                    "crop_id": labels.get(label),
                    "profile_id": profile_by_label.get(label),
                    "start": f"{2024 + i}-05-01",
                    "end": f"{2024 + i}-08-31",
                }
            )
        rotations.append(
            {
                "id": id,
                "title": " → ".join(sequence),
                "region_id": "US-KS-Tribune" if id.startswith("wheat") else None,
                "production_system": "dryland"
                if id.startswith("wheat")
                else "unverified_for_sequence",
                "date_basis": "synthetic_example_dates_not_source_calendar",
                "claim_ids": support,
                "source_support": "Bounded order/context support only; dates invented exclusively for software demonstration"
                if id
                in {
                    "rice-mung",
                    "rice-sesame",
                    "rice-groundnut",
                    "wheat-sorghum-fallow",
                }
                else "Requested research sequence; exact order/local agronomy unverified; general context only where linked",
                "cycles": cycles,
                "field_drainage": None,
                "water_requirements": None,
                "crop_history_available": False,
                "succession_restrictions": None,
                "verified_tradeoffs": None,
                "missing_evidence": [
                    "Field identity, drainage, dated attributed crop/fallow history",
                    "Local season/cultivar, delivered irrigation, daily weather and ET0",
                    "Accepted succession restrictions; original pest-tradeoff experiments and local applicability",
                    "No N, yield, pest, income or suitability benefit inferred",
                ],
                "recommendation_eligible": False,
                "approved_for_candidates": False,
                "review": "reference_only",
            }
        )
    data = {
        "schema_version": VERSION,
        "content_version": "1.0.0",
        "recommendation_eligible": False,
        "dataset_versions": read_json(root / "dataset-versions.json"),
        "sources": sources,
        "claims": claims,
        "crops": crops,
        "profiles": profiles,
        "rotations": rotations,
    }
    validate(data, root)
    gaps = [
        {
            "profile_id": p["id"],
            "parameter": key,
            "missing_reason": value["missing_reason"],
        }
        for p in profiles
        for key, value in p["parameters"].items()
        if value["state"] == "unknown"
    ]
    from fixtures import requests
    from reference_products import gaez_reference

    return {
        "catalog.json": encoded(data),
        "missing-parameters.json": encoded(gaps),
        "mapping-report.json": encoded(
            [entry for p in profiles for entry in mapping_report(p)]
        ),
        "species-inventory.jsonl": b"".join(
            (json.dumps(x, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
            for x in inventory
        ),
        "evidence/calendar-disagreements.json": encoded(discrepancies),
        "evidence/gaez-v5-reference.json": encoded(
            gaez_reference((root / "originals/gaez_v5_metadata.json").read_bytes())
        ),
        **{
            "fixtures/" + name: encoded(request)
            for name, request in requests(data).items()
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="fail on drift without rewriting anything"
    )
    args = parser.parse_args()
    artifacts = generate()
    for name, content in artifacts.items():
        path = ROOT / name
        if args.check:
            if not path.is_file() or path.read_bytes() != content:
                raise ValueError("generated artifact drift: " + name)
        else:
            path.write_bytes(content)
    paths = sorted(
        p
        for p in ROOT.rglob("*")
        if p.is_file()
        and p.suffix in {".json", ".jsonl", ".csv", ".html", ".bin"}
        and p.name != "integrity.json"
    )
    integrity = encoded(
        {
            "scope": "Exact stored data bytes; hashes establish integrity, not agricultural truth or source acceptance",
            "files": [
                {
                    "path": str(p.relative_to(ROOT)),
                    "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
                    "bytes": p.stat().st_size,
                }
                for p in paths
            ],
        }
    )
    if args.check:
        if (ROOT / "integrity.json").read_bytes() != integrity:
            raise ValueError("integrity manifest drift")
    else:
        (ROOT / "integrity.json").write_bytes(integrity)
    print(json.dumps({"generated_artifacts": len(artifacts), "check_only": args.check}))


if __name__ == "__main__":
    main()
