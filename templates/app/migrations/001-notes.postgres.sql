-- The notes table, for the class NOTE in src/model.lisp (id and version
-- come from PERSISTENT; the other columns are its fields).
CREATE TABLE IF NOT EXISTS notes (id BIGSERIAL PRIMARY KEY, version INTEGER NOT NULL DEFAULT 0,
  title TEXT, body TEXT, owner TEXT);
