"""Reuse the existing local farm and photo boundary without sharing research keys."""

import json
import time
from uuid import UUID, uuid4

from fastapi import APIRouter
from starlette.concurrency import run_in_threadpool

from earthsync.platform_v1.errors import PlatformError

from .retrieval import EvidenceIndex, EvidenceQuery
from .soil import LabConfirmation, LocalOCR, analyze_photo, soil_context


def local_router(store, objects, catalog, owner):
    router = APIRouter(prefix="/api/platform/v1")
    # Index initialization is lazy: inherited source-only routes keep working without it.
    index = None
    ocr = LocalOCR()

    @router.post("/crop-intelligence")
    def evidence(value: EvidenceQuery):
        nonlocal index
        if catalog is None:
            raise PlatformError("CATALOG_NOT_INSTALLED", 503)
        if index is None:
            index = EvidenceIndex(catalog)
        return index.retrieve(value)

    def report_row(db, farm_id, report_id):
        store.farm(owner, farm_id, db)
        row = db.execute(
            "SELECT * FROM crop_lab_reports WHERE id=? AND farm_id=? AND owner=?",
            (str(report_id), str(farm_id), owner),
        ).fetchone()
        if row is None:
            raise PlatformError("NOT_FOUND", 404)
        return row

    def document(row):
        return {
            "id": row["id"],
            "photo_id": row["photo_id"],
            "original": json.loads(row["original"]),
            "confirmed": json.loads(row["confirmed"]) if row["confirmed"] else None,
        }

    @router.post("/farms/{farm_id}/photos/{photo_id}/analyze")
    def analyze(farm_id: UUID, photo_id: UUID):
        pixels = objects.image(owner, farm_id, photo_id)
        return analyze_photo(photo_id, pixels)

    @router.post("/farms/{farm_id}/photos/{photo_id}/lab-extraction", status_code=201)
    async def extract(farm_id: UUID, photo_id: UUID):
        pixels = objects.image(owner, farm_id, photo_id)
        extraction = await run_in_threadpool(ocr.extract, pixels)
        ident = str(uuid4())
        with store.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            store.farm(owner, farm_id, db)
            if (
                db.execute("SELECT count(*) FROM crop_lab_reports").fetchone()[0]
                >= store.max_rows
            ):
                raise PlatformError("STORAGE_QUOTA", 507)
            db.execute(
                "INSERT INTO crop_lab_reports VALUES (?,?,?,?,?,NULL,?)",
                (
                    ident,
                    str(farm_id),
                    owner,
                    str(photo_id),
                    json.dumps(extraction),
                    time.time(),
                ),
            )
            store._audit(db, owner, ident, "lab.extracted")
        return {
            "id": ident,
            "photo_id": str(photo_id),
            "original": extraction,
            "confirmed": None,
        }

    @router.get("/farms/{farm_id}/lab-reports")
    def reports(farm_id: UUID):
        with store.connection() as db:
            store.farm(owner, farm_id, db)
            return [
                document(row)
                for row in db.execute(
                    "SELECT * FROM crop_lab_reports WHERE farm_id=? AND owner=? ORDER BY created DESC LIMIT 100",
                    (str(farm_id), owner),
                )
            ]

    @router.post("/farms/{farm_id}/lab-reports/{report_id}/confirm")
    def confirm(farm_id: UUID, report_id: UUID, value: LabConfirmation):
        with store.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            report_row(db, farm_id, report_id)
            confirmed = {
                **value.model_dump(mode="json"),
                "confirmed_at_epoch": time.time(),
                "category": "user_confirmed_lab_transcription",
                "laboratory_authenticity_verified": False,
            }
            db.execute(
                "UPDATE crop_lab_reports SET confirmed=? WHERE id=?",
                (json.dumps(confirmed), str(report_id)),
            )
            store._audit(db, owner, str(report_id), "lab.confirmed")
            return document(report_row(db, farm_id, report_id))

    @router.get("/farms/{farm_id}/soil-context")
    def context(farm_id: UUID):
        store.farm(owner, farm_id)
        modeled = [
            job["result"]
            for job in store.intelligence(owner, farm_id)
            if job["kind"] == "soil_map" and job["status"] == "succeeded"
        ]
        return soil_context(
            modeled=modeled,
            farmer_reported=store.observations(owner, farm_id),
            laboratory=reports(farm_id),
        )

    return router
