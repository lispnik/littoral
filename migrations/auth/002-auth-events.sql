-- Recent sign-in failures and reset mails, by name, user or client address,
-- so the limits on them hold across restarts and between processes.
CREATE TABLE IF NOT EXISTS auth_events (kind TEXT NOT NULL, event_key TEXT NOT NULL, happened BIGINT NOT NULL);
CREATE INDEX IF NOT EXISTS auth_events_key ON auth_events (kind, event_key, happened);
