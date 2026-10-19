-- How far a running job has got, as a fraction from 0 to 1 (NOTE-JOB-PROGRESS's
-- :FRACTION), and whether someone has asked it to stop (CANCEL-DURABLE-JOB).
ALTER TABLE job_queue ADD COLUMN progress_fraction DOUBLE PRECISION;
ALTER TABLE job_queue ADD COLUMN cancel_requested INTEGER NOT NULL DEFAULT 0;
