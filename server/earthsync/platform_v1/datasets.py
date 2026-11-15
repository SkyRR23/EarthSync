"""Versioned server dataset metadata. Registration never downloads global data."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from typing import Literal

from pydantic import AwareDatetime, Field, HttpUrl, model_validator

from .models import Contract
from .store import Store, encoded


class DatasetDescriptor(Contract):
    schema_version: Literal["earthsync.dataset.v1"] = "earthsync.dataset.v1"
    dataset_id: str = Field(pattern=r"^[a-z0-9][a-z0-9_.-]{1,99}$")
    name: str = Field(min_length=1, max_length=300)
    publisher: str = Field(min_length=1, max_length=300)
    version: str = Field(min_length=1, max_length=100)
    source_url: HttpUrl
    license: str = Field(min_length=1, max_length=2000)
    geographic_coverage: str = Field(min_length=1, max_length=1000)
    spatial_resolution: str | None = Field(default=None, max_length=500)
    units: dict[str, str] = Field(default_factory=dict, max_length=100)
    acquired_at: AwareDatetime | None = None
    last_update: AwareDatetime | None = None
    local_server_path: str | None = Field(default=None, max_length=1000)
    processing_status: Literal[
        "not_installed", "remote_service", "imported", "processed", "failed"
    ] = "not_installed"
    validation_status: Literal[
        "unreviewed", "technical_validation_passed", "rejected"
    ] = "unreviewed"
    access_method: Literal["local_file", "api", "wcs", "earthdata", "manual_import"]
    sha256: str | None = Field(default=None, pattern=r"^[a-f0-9]{64}$")
    cache_policy: str = Field(min_length=1, max_length=2000)
    device_cache_permitted: bool = False
    redistribution_restrictions: str = Field(min_length=1, max_length=2000)
    limitations: list[str] = Field(default_factory=list, max_length=50)

    @model_validator(mode="after")
    def imported_metadata(self):
        if self.processing_status in {"imported", "processed"} and not (
            self.local_server_path and self.sha256 and self.acquired_at
        ):
            raise ValueError(
                "Imported datasets require a path, checksum and acquisition time"
            )
        if self.source_url.scheme != "https":
            raise ValueError("Source references must use HTTPS")
        return self


class DatasetRegistry:
    def __init__(self, store, root):
        self.store = store
        self.root = Path(root).resolve()

    def resolve(self, descriptor):
        if not descriptor.local_server_path:
            return None
        relative = Path(descriptor.local_server_path)
        path = self.root / relative
        if relative.is_absolute() or not path.resolve().is_relative_to(self.root):
            raise ValueError("Dataset path must stay inside the server dataset root")
        if any(
            part.is_symlink()
            for part in (path, *path.parents)
            if part != self.root.parent
        ):
            raise ValueError("Dataset paths cannot contain symlinks")
        return path

    def register(self, descriptor):
        path = self.resolve(descriptor)
        if descriptor.processing_status in {"imported", "processed"}:
            if path is None or not path.is_file():
                raise ValueError("Dataset file is unavailable")
            with path.open("rb") as handle:
                actual = hashlib.file_digest(handle, "sha256").hexdigest()
            if actual != descriptor.sha256:
                raise ValueError("Dataset checksum mismatch")
        body = encoded(descriptor.model_dump(mode="json"))
        with self.store.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute(
                "SELECT descriptor FROM dataset_registry WHERE dataset_id=? AND version=?",
                (descriptor.dataset_id, descriptor.version),
            ).fetchone()
            if old:
                if old[0] != body:
                    raise ValueError(
                        "Existing dataset versions are immutable; register a new version"
                    )
                return
            db.execute(
                "INSERT INTO dataset_registry VALUES (?,?,?,?)",
                (
                    descriptor.dataset_id,
                    descriptor.version,
                    body,
                    datetime.now(timezone.utc).isoformat(),
                ),
            )

    def records(self, *, private=False):
        with self.store.connection() as db:
            rows = db.execute(
                "SELECT descriptor FROM dataset_registry ORDER BY dataset_id, version"
            ).fetchall()
        result = []
        for row in rows:
            descriptor = DatasetDescriptor.model_validate_json(row[0])
            path = self.resolve(descriptor)
            present = path is not None and path.is_file()
            data = descriptor.model_dump(mode="json")
            if not private:
                data.pop("local_server_path", None)
            result.append(
                {
                    **data,
                    "local_file_present": present,
                    "operational": False,
                    "availability": "server_file_registered_adapter_required"
                    if present
                    else "not_installed",
                    "scientific_crop_suitability_approved": False,
                    "storage_scope": "server_only",
                }
            )
        return result

    def bootstrap(self):
        sources = [
            (
                "fao-ecocrop",
                "FAO ECOCROP",
                "FAO",
                "https://www.fao.org/land-water/land/land-governance/land-resources-planning-toolbox/category/details/en/c/1027491/",
                "manual_import",
            ),
            (
                "fao-gaez",
                "Global Agro-Ecological Zones",
                "FAO / IIASA",
                "https://gaez.fao.org/",
                "manual_import",
            ),
            (
                "soilgrids",
                "SoilGrids geographic rasters",
                "ISRIC",
                "https://soilgrids.org/",
                "wcs",
            ),
            (
                "nasa-power",
                "NASA POWER historical climate",
                "NASA POWER",
                "https://power.larc.nasa.gov/",
                "api",
            ),
            (
                "nasa-hls",
                "Harmonized Landsat Sentinel",
                "NASA",
                "https://www.earthdata.nasa.gov/data/projects/hls",
                "earthdata",
            ),
        ]
        for identity, name, publisher, source, access in sources:
            descriptor = DatasetDescriptor(
                dataset_id=identity,
                name=name,
                publisher=publisher,
                version="registration-only-v1",
                source_url=source,
                license="Review the exact acquired product license before import or redistribution.",
                geographic_coverage="Product-dependent; spatial coverage must be validated for each requested field.",
                access_method=access,
                cache_policy="Do not cache on a device until the exact product policy is reviewed.",
                redistribution_restrictions="No bulk redistribution authorized by this registration.",
                limitations=[
                    "Registration is not evidence of an installed dataset or operational provider.",
                    "Existing NASA and SoilGrids adapters retain their own source, QA and cache contracts.",
                ],
            )
            self.register(descriptor)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--dataset-root", required=True, type=Path)
    parser.add_argument(
        "--register",
        type=Path,
        help="JSON descriptor for a separately acquired server-local file",
    )
    args = parser.parse_args()
    registry = DatasetRegistry(Store(args.state_dir.resolve()), args.dataset_root)
    registry.bootstrap()
    if args.register:
        if args.register.stat().st_size > 128_000:
            parser.error("Dataset descriptor is too large")
        registry.register(
            DatasetDescriptor.model_validate_json(
                args.register.read_text(encoding="utf-8")
            )
        )
    print(
        json.dumps(
            {
                "schema_version": "earthsync.dataset-registry.v1",
                "datasets": registry.records(private=True),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
