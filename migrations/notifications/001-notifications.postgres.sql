-- Notifications for users (littoral/notifications).
CREATE TABLE IF NOT EXISTS notifications (id BIGSERIAL PRIMARY KEY, user_id TEXT NOT NULL,
  message TEXT NOT NULL, url TEXT, kind TEXT NOT NULL, created BIGINT NOT NULL, read_at BIGINT);
CREATE INDEX IF NOT EXISTS notifications_user ON notifications (user_id, created);
