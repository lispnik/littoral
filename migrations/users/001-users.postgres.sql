-- The built-in users table (littoral/auth), names and emails unique whatever their case.
CREATE TABLE IF NOT EXISTS users (id BIGSERIAL PRIMARY KEY, version INTEGER NOT NULL DEFAULT 0,
  name TEXT, email TEXT, roles TEXT, active INTEGER, password_hash TEXT);
CREATE UNIQUE INDEX IF NOT EXISTS users_name ON users (LOWER(name));
CREATE UNIQUE INDEX IF NOT EXISTS users_email ON users (LOWER(email));
