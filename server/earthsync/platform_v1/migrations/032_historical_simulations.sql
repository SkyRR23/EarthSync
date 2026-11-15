CREATE TABLE historical_windows (id TEXT PRIMARY KEY, farm_id TEXT NOT NULL REFERENCES farms(id), owner TEXT NOT NULL, request_key TEXT NOT NULL, document TEXT NOT NULL, created REAL NOT NULL);
CREATE INDEX historical_windows_farm ON historical_windows(owner,farm_id,created);
CREATE INDEX historical_windows_request ON historical_windows(owner,request_key,created);
CREATE TABLE historical_simulations (id TEXT PRIMARY KEY, farm_id TEXT NOT NULL REFERENCES farms(id), owner TEXT NOT NULL, document TEXT NOT NULL, created REAL NOT NULL);
CREATE INDEX historical_simulations_farm ON historical_simulations(owner,farm_id,created);
