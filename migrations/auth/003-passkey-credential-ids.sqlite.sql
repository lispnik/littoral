-- Each passkey's credential id in a column of its own, so signing in finds
-- it by index rather than reading every passkey.
ALTER TABLE auth_factors ADD COLUMN credential_id TEXT;
UPDATE auth_factors SET credential_id = substr(data, 1, instr(data, ' ') - 1) WHERE kind = 'passkey';
CREATE UNIQUE INDEX IF NOT EXISTS auth_factors_credential ON auth_factors (credential_id);
