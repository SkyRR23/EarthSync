"""Read-only FTS5 retrieval. Evidence is data, never instructions or crop rules."""

import copy
import hashlib
import json
import re
import sqlite3
import threading
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field

from earthsync.platform_v1.reference_v2 import ReferenceCatalog
from earthsync.platform_v1.agronomic_review import review_for

ROOT = Path(__file__).resolve().parents[3]
REVIEW_ROOT = ROOT / "data/crop-rule-candidates/v1"


class EvidenceQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")
    crop: str = Field(default="", max_length=150)
    question: str = Field(default="", max_length=1000)
    region: str | None = Field(default=None, min_length=1, max_length=150)
    cultivar: str | None = Field(default=None, min_length=1, max_length=150)
    system: str | None = Field(default=None, min_length=1, max_length=150)
    limit: int = Field(default=12, ge=1, le=25)


class EvidenceIndex:
    def __init__(self, catalog=None):
        self.catalog = catalog or ReferenceCatalog()
        self.crops = self.catalog.data["crops"]
        self.sources = {s["id"]: copy.deepcopy(s) for s in self.catalog.data["sources"]}
        receipts = {s["id"]: s for s in self._read("source-receipts.json")}
        for source in self._read("sources.json"):
            self.sources["7v:" + source["id"]] = {
                **source,
                "id": "7v:" + source["id"],
                "retrieved_at": receipts.get(source["receipt_id"], {}).get(
                    "completed_at"
                ),
            }
        self.records = {}
        for claim in self.catalog.data["claims"]:
            self.records[claim["id"]] = {
                **copy.deepcopy(claim),
                "origin": "crop-knowledge-v2",
                "region": claim["region_id"],
                "evidence_status": claim["review"],
            }
        for fact in self._read("facts.json"):
            self.records["7v:" + fact["id"]] = {
                **fact,
                "id": "7v:" + fact["id"],
                "source_id": "7v:" + fact["source_id"],
                "origin": "7v-reviewed-evidence",
                "parameter": fact["id"],
                "region": fact["geographic_applicability"],
                "evidence_status": fact["source_fact_status"],
            }
        additional = json.loads(
            Path(__file__)
            .with_name("additional_evidence.json")
            .read_text(encoding="utf-8")
        )
        self.sources.update({s["id"]: s for s in additional["sources"]})
        for claim in additional["claims"]:
            if claim["id"] in self.records or claim["source_id"] not in self.sources:
                raise ValueError("Invalid additional source dossier")
            self.records[claim["id"]] = claim
        self.lock = threading.Lock()
        self.db = sqlite3.connect(":memory:", check_same_thread=False)
        self.db.execute("CREATE VIRTUAL TABLE evidence USING fts5(id UNINDEXED, text)")
        self.db.executemany(
            "INSERT INTO evidence VALUES (?,?)",
            [
                (ident, json.dumps(record, ensure_ascii=False))
                for ident, record in self.records.items()
            ],
        )
        self.db.commit()
        # A separate collection in the same read-only FTS5 engine. Crop profiles
        # cannot silently become disease evidence; existing corpus stays intact.
        health = json.loads(
            Path(__file__).with_name("plant_health.json").read_text(encoding="utf-8")
        )
        self.health_sources = {s["id"]: s for s in health["sources"]}
        self.health_records = {r["id"]: r for r in health["claims"]}
        if len(self.health_records) != len(health["claims"]) or any(
            r["source_id"] not in self.health_sources for r in health["claims"]
        ):
            raise ValueError("Invalid plant-health dossier")
        self.health_sha256 = hashlib.sha256(
            json.dumps(health, sort_keys=True).encode()
        ).hexdigest()
        self.db.execute(
            "CREATE VIRTUAL TABLE plant_health USING fts5(id UNINDEXED, text)"
        )
        self.db.executemany(
            "INSERT INTO plant_health VALUES (?,?)",
            [(r["id"], " ".join(r["features"])) for r in health["claims"]],
        )
        self.db.commit()
        # Pin the evidence corpus in each packet; no fetched/uploaded text enters this index.
        self.corpus_sha256 = hashlib.sha256(
            json.dumps(self.records, sort_keys=True).encode()
        ).hexdigest()

    @staticmethod
    def _read(name):
        raw = (REVIEW_ROOT / name).read_bytes()
        pins = json.loads((REVIEW_ROOT / "integrity.json").read_text(encoding="utf-8"))[
            "sha256"
        ]
        if hashlib.sha256(raw).hexdigest() != pins[name]:
            raise ValueError("Scientific review source integrity mismatch")
        return json.loads(raw)

    def search(self, query):
        q = query.strip().casefold()
        return copy.deepcopy(
            [
                c
                for c in self.crops
                if not q
                or any(
                    q in n.casefold()
                    for n in [c["id"], c["scientific_name"], *c["aliases"]]
                )
            ][:100]
        )

    def retrieve_health(self, *, image_kind, crop, features, region=None):
        """Only actual feature matches, exact crop identities and explicit scope.

        User questions cannot force retrieval of symptom evidence absent from
        the validated image. Unknown crop/scope never becomes a local match.
        """
        crops = self.resolve(crop) if crop else []
        crop_id = crops[0]["id"] if len(crops) == 1 else None
        terms = [f for f in features if re.fullmatch(r"[a-z_]{1,60}", f)]
        claims = []
        if terms and (image_kind == "soil" or crop_id):
            expression = " OR ".join('"' + f + '"' for f in terms)
            with self.lock:
                ids = [
                    row[0]
                    for row in self.db.execute(
                        "SELECT id FROM plant_health WHERE plant_health MATCH ? ORDER BY bm25(plant_health), id LIMIT 12",
                        (expression,),
                    )
                ]
            claims = [
                copy.deepcopy(self.health_records[i])
                for i in ids
                if self.health_records[i]["image_kind"] == image_kind
                and self.health_records[i]["crop_id"]
                == (crop_id if image_kind == "crop" else None)
                and (
                    not region
                    or self.health_records[i]["region"].casefold() == region.casefold()
                )
                and set(self.health_records[i]["features"]) & set(terms)
            ]
        return {
            "status": "evidence_available" if claims else "no_matching_evidence",
            "claims": claims,
            "sources": [
                copy.deepcopy(self.health_sources[s])
                for s in sorted({r["source_id"] for r in claims})
            ],
            "citations": [
                {
                    "claim_id": r["id"],
                    "source_id": r["source_id"],
                    "locator": r["locator"],
                }
                for r in claims
            ],
            "corpus_sha256": self.health_sha256,
            "scope_note": "References retain their original geographic scope; they are not locally validated diagnoses.",
        }

    def resolve(self, query):
        q = query.strip().casefold()
        exact = [
            c
            for c in self.crops
            if q
            in [
                c["id"].casefold(),
                c["scientific_name"].casefold(),
                *[a.casefold() for a in c["aliases"]],
            ]
        ]
        if exact:
            return exact
        # Questions can resolve only complete aliases; ambiguous names require selection.
        matches = []
        for crop in self.crops:
            names = [crop["scientific_name"], *crop["aliases"]]
            if any(
                len(n) >= 3
                and re.search(r"(?<!\w)" + re.escape(n.casefold()) + r"(?!\w)", q)
                for n in names
            ):
                matches.append(crop)
        return matches

    def retrieve(self, query: EvidenceQuery):
        crops = self.resolve(query.crop or query.question)
        packet = {
            "schema_version": "earthsync.crop-intelligence.v1",
            "provider": "deterministic-fts5",
            "recommendation_eligible": False,
            "executable_rules": [],
            "catalog_sha256": self.catalog.sha256,
            "corpus_sha256": self.corpus_sha256,
            "crop": None,
            "claims": [],
            "sources": [],
            "citations": [],
            "scope": query.model_dump(exclude={"question"}),
            "missing_information": [
                "Named cultivar and establishment method",
                "Local season and production system",
                "Representative soil sample with depth and test method",
                "Independent field-applicability review",
            ],
            "local_review_questions": [
                "Which cultivar and planting method are used here?",
                "Does this reference cover the field's region, season and water regime?",
                "What sampling depth, test method and field coverage does the laboratory report describe?",
            ],
            "limitations": [
                "Reference evidence does not establish field suitability.",
                "Annual rainfall cannot be converted into seasonal water supply.",
                "Regional modeled pH, farmer reports and laboratory samples have different support.",
            ],
        }
        if len(crops) != 1:
            return {
                **packet,
                "status": "select_crop" if crops else "no_reference",
                "matches": crops[:20],
                "answer": "Select a single verified crop identity to retrieve evidence.",
            }
        crop = crops[0]
        review = review_for(crop["id"])
        eligible = [r for r in self.records.values() if r["crop_id"] == crop["id"]]
        # Explicit filters require exact documented scope. Unknown/global scope is not a local match.
        for field, wanted in (
            ("region", query.region),
            ("cultivar", query.cultivar),
            ("production_system", query.system),
        ):
            if wanted:
                eligible = [
                    r
                    for r in eligible
                    if (r.get(field) or "").casefold() == wanted.casefold()
                ]
        terms = re.findall(r"[^\W_]+", query.question.casefold(), flags=re.UNICODE)[:40]
        aliases = {
            "ph": "ph",
            "water": "water",
            "rain": "rainfall",
            "temperature": "temperature",
            "duration": "duration",
            "soil": "soil",
            "planting": "planting",
            "drainage": "drainage",
        }
        terms += [value for word, value in aliases.items() if word in terms]
        ranked = []
        if terms:
            expression = " OR ".join(
                '"' + t.replace('"', '""') + '"' for t in dict.fromkeys(terms)
            )
            with self.lock:
                ranked = [
                    r[0]
                    for r in self.db.execute(
                        "SELECT id FROM evidence WHERE evidence MATCH ? ORDER BY bm25(evidence), id",
                        (expression,),
                    )
                ]
            positions = {ident: i for i, ident in enumerate(ranked)}
            eligible = [r for r in eligible if r["id"] in positions]
            eligible.sort(key=lambda r: positions[r["id"]])
        else:
            # Overview prioritizes substantive source facts over the large identity alias record.
            eligible.sort(key=lambda r: (r["parameter"] == "identity", r["id"]))
        claims = copy.deepcopy(eligible[: query.limit])
        source_ids = sorted({r["source_id"] for r in claims})
        sources = [copy.deepcopy(self.sources[s]) for s in source_ids]
        citations = [
            {"claim_id": r["id"], "source_id": r["source_id"], "locator": r["locator"]}
            for r in claims
        ]
        self.validate_citations(claims, citations)
        return {
            **packet,
            "status": "evidence_available" if claims else "no_matching_scope",
            "crop": copy.deepcopy(crop),
            "claims": claims,
            "sources": sources,
            "citations": citations,
            "rule_review": review,
            "blocked_candidates": review["candidates"],
            "contradictions": list(
                dict.fromkeys(
                    text
                    for r in review["candidates"]
                    for text in r.get("contradictions_and_limits", [])
                )
            ),
            "truncated": len(eligible) > query.limit,
            "answer": "Retrieved source references are shown below with their original scope and limitations. No field recommendation is approved."
            if claims
            else "No evidence matches the requested documented scope. Unknown scope is not assumed applicable.",
        }

    def validate_citations(self, claims, citations):
        selected = {r["id"]: r for r in claims}
        for citation in citations:
            record = selected.get(citation["claim_id"])
            if (
                record is None
                or record != self.records.get(record["id"])
                or citation["source_id"] not in self.sources
                or citation["source_id"] != record["source_id"]
                or citation["locator"] != record["locator"]
            ):
                raise ValueError("Unretrieved or altered citation")

    def extractive_explanation(self, packet, claim_ids):
        """Optional provider contract: select retrieved IDs only; no generated agronomic prose."""
        selected = {r["id"]: r for r in packet["claims"]}
        if len(claim_ids) > 25 or any(i not in selected for i in claim_ids):
            raise ValueError("Explanation contains an unretrieved claim")
        return {
            "recommendation_eligible": False,
            "claims": [copy.deepcopy(selected[i]) for i in claim_ids],
        }
