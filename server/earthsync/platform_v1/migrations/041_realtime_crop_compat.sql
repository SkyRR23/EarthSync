CREATE TABLE IF NOT EXISTS realtime_state (
    key TEXT PRIMARY KEY,
    payload TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS crop_lab_reports (
    id TEXT PRIMARY KEY,
    farm_id TEXT NOT NULL,
    owner TEXT NOT NULL,
    photo_id TEXT NOT NULL,
    original TEXT NOT NULL,
    confirmed TEXT,
    created REAL NOT NULL,
    FOREIGN KEY(farm_id,owner) REFERENCES farms(id,owner) ON DELETE CASCADE,
    FOREIGN KEY(photo_id) REFERENCES artifacts(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS crop_lab_reports_farm ON crop_lab_reports(farm_id,owner,created);
