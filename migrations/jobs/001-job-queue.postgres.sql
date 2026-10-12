-- Background jobs (littoral/jobs).
CREATE TABLE IF NOT EXISTS job_queue (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, arguments TEXT NOT NULL,
  queue TEXT NOT NULL, status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, run_at BIGINT NOT NULL,
  unique_key TEXT, progress TEXT, last_error TEXT, created BIGINT NOT NULL, finished BIGINT);
CREATE INDEX IF NOT EXISTS job_queue_due ON job_queue (status, run_at);
-- One untried job per key: ENQUEUE-JOB's :KEY, and each recurring job.
CREATE UNIQUE INDEX IF NOT EXISTS job_queue_key ON job_queue (unique_key)
  WHERE status = 'queued' AND attempts = 0;
