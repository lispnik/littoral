-- What signing in keeps, whatever the user store: reset, recovery and API
-- tokens, second factors, sign-ins, and roles and permissions by name.
CREATE TABLE IF NOT EXISTS auth_tokens (id BIGSERIAL PRIMARY KEY, version INTEGER NOT NULL DEFAULT 0,
  token_hash TEXT, user_id TEXT, purpose TEXT, expires BIGINT);
CREATE UNIQUE INDEX IF NOT EXISTS auth_tokens_hash ON auth_tokens (token_hash);
CREATE TABLE IF NOT EXISTS auth_factors (id BIGSERIAL PRIMARY KEY, version INTEGER NOT NULL DEFAULT 0,
  user_id TEXT, kind TEXT, name TEXT, data TEXT, counter BIGINT, created BIGINT);
CREATE TABLE IF NOT EXISTS auth_sessions (id BIGSERIAL PRIMARY KEY, version INTEGER NOT NULL DEFAULT 0,
  token_hash TEXT, user_id TEXT, created BIGINT, last_seen BIGINT, expires BIGINT, remember INTEGER,
  user_agent TEXT, address TEXT);
CREATE UNIQUE INDEX IF NOT EXISTS auth_sessions_hash ON auth_sessions (token_hash);
CREATE INDEX IF NOT EXISTS auth_sessions_user ON auth_sessions (user_id);
CREATE TABLE IF NOT EXISTS user_roles (user_id TEXT NOT NULL, role TEXT NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS user_roles_key ON user_roles (user_id, role);
CREATE TABLE IF NOT EXISTS role_permissions (role TEXT NOT NULL, permission TEXT NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS role_permissions_key ON role_permissions (role, permission);
