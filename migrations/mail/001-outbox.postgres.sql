-- Mail waiting to be sent, and how sending it has gone (littoral/mail).
CREATE TABLE IF NOT EXISTS mail_outbox (id BIGSERIAL PRIMARY KEY, version INTEGER NOT NULL DEFAULT 0,
  sender TEXT, recipients TEXT, subject TEXT, message TEXT, status TEXT, attempts BIGINT,
  next_attempt BIGINT, last_error TEXT, created BIGINT, sent BIGINT);
