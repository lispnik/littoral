-- Who did what, and when (littoral/audit).
CREATE TABLE IF NOT EXISTS audit_log (id BIGSERIAL PRIMARY KEY, at BIGINT NOT NULL, actor_id TEXT, actor_name TEXT,
  action TEXT NOT NULL, subject TEXT, subject_label TEXT, details TEXT, address TEXT);
CREATE INDEX IF NOT EXISTS audit_log_action ON audit_log (action);
CREATE INDEX IF NOT EXISTS audit_log_subject ON audit_log (subject);
CREATE INDEX IF NOT EXISTS audit_log_actor ON audit_log (actor_id);
