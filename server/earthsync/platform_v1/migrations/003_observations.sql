CREATE TABLE observations (id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, owner TEXT NOT NULL, document TEXT NOT NULL, created REAL NOT NULL, FOREIGN KEY(farm_id,owner) REFERENCES farms(id,owner) ON DELETE CASCADE);
CREATE INDEX observations_farm_owner ON observations(farm_id,owner,created);
