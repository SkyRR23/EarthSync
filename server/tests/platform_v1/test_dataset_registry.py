import hashlib
import json

import pytest

from earthsync.platform_v1.datasets import DatasetDescriptor, DatasetRegistry


def descriptor(**changes):
    return DatasetDescriptor.model_validate(
        {
            "dataset_id": "synthetic-registry-fixture",
            "name": "Synthetic registry fixture, not agricultural evidence",
            "publisher": "EarthSync tests",
            "version": "test-1",
            "source_url": "https://example.com/test",
            "license": "Test only",
            "geographic_coverage": "None, synthetic fixture",
            "access_method": "local_file",
            "cache_policy": "Do not redistribute as real data",
            "redistribution_restrictions": "Synthetic test only",
            **changes,
        }
    )


def test_bootstrap_is_idempotent_and_honest(store, tmp_path):
    registry = DatasetRegistry(store, tmp_path / "datasets")
    registry.bootstrap()
    registry.bootstrap()
    records = registry.records()
    assert len(records) == 5
    assert all(
        not row["operational"] and not row["local_file_present"] for row in records
    )
    assert all("local_server_path" not in row for row in records)
    assert all(not row["scientific_crop_suitability_approved"] for row in records)


def test_registered_versions_are_immutable(store, tmp_path):
    registry = DatasetRegistry(store, tmp_path)
    first = descriptor()
    registry.register(first)
    registry.register(first)
    with pytest.raises(ValueError, match="immutable"):
        registry.register(descriptor(name="Changed"))


@pytest.mark.parametrize(
    "path", ["../private.sqlite3", "../../escape", "/outside/file"]
)
def test_dataset_cannot_escape_storage(store, tmp_path, path):
    with pytest.raises(ValueError):
        DatasetRegistry(store, tmp_path / "datasets").register(
            descriptor(local_server_path=path)
        )


def test_import_verifies_bytes_and_retains_units(store, tmp_path):
    root = tmp_path / "datasets"
    root.mkdir()
    (root / "sample.bin").write_bytes(b"synthetic registry bytes, no soil values")
    registry = DatasetRegistry(store, root)
    with pytest.raises(ValueError, match="checksum"):
        registry.register(
            descriptor(
                local_server_path="sample.bin",
                processing_status="imported",
                sha256="0" * 64,
                acquired_at="2026-11-15T00:00:00Z",
            )
        )
    registry.register(
        descriptor(
            local_server_path="sample.bin",
            processing_status="imported",
            sha256=hashlib.sha256((root / "sample.bin").read_bytes()).hexdigest(),
            acquired_at="2026-11-15T00:00:00Z",
            units={"test": "unitless"},
        )
    )
    row = registry.records(private=True)[0]
    assert row["local_file_present"] and row["units"] == {"test": "unitless"}
    assert not row["operational"]


def test_registry_survives_repository_restart(store, tmp_path):
    DatasetRegistry(store, tmp_path).register(descriptor())
    restored = DatasetRegistry(store, tmp_path).records()
    assert json.loads(json.dumps(restored))[0]["version"] == "test-1"
