-- Comment threads (littoral/comments).
CREATE TABLE IF NOT EXISTS comments (id BIGSERIAL PRIMARY KEY, thread TEXT NOT NULL,
  author TEXT NOT NULL, body TEXT NOT NULL, created BIGINT NOT NULL, origin TEXT);
CREATE INDEX IF NOT EXISTS comments_thread ON comments (thread, id);
