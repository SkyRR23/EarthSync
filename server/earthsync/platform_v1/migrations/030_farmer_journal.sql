CREATE TABLE farmer_journal (id TEXT NOT NULL, farm_id TEXT NOT NULL, owner TEXT NOT NULL, document TEXT NOT NULL, created REAL NOT NULL, PRIMARY KEY(id,owner), FOREIGN KEY(farm_id,owner) REFERENCES farms(id,owner) ON DELETE CASCADE);
CREATE INDEX farmer_journal_farm ON farmer_journal(farm_id,owner,created);
CREATE TABLE journal_history_links (entry_id TEXT NOT NULL, owner TEXT NOT NULL, history_id TEXT NOT NULL, PRIMARY KEY(entry_id,owner), FOREIGN KEY(entry_id,owner) REFERENCES farmer_journal(id,owner), FOREIGN KEY(history_id) REFERENCES history(id));
