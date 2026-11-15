CREATE TABLE IF NOT EXISTS dataset_registry (
    dataset_id TEXT NOT NULL,
    version TEXT NOT NULL,
    descriptor TEXT NOT NULL,
    registered_at TEXT NOT NULL,
    PRIMARY KEY (dataset_id, version)
);
