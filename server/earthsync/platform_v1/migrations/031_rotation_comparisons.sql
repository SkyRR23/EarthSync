CREATE TABLE rotation_comparisons (id TEXT NOT NULL, farm_id TEXT NOT NULL, owner TEXT NOT NULL, document TEXT NOT NULL, created REAL NOT NULL, PRIMARY KEY(id,owner), FOREIGN KEY(farm_id,owner) REFERENCES farms(id,owner) ON DELETE CASCADE);
CREATE INDEX rotation_comparisons_farm ON rotation_comparisons(farm_id,owner,created);
