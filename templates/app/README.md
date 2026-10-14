# {{title}}

A [Littoral](https://github.com/lispnik/littoral) application with a database and signing in: users sign in and keep private notes, and an admin at `/admin` manages them.

```sh
make user NAME=ada EMAIL=ada@example.org PASSWORD='a long passphrase' ADMIN=1
make run     # http://127.0.0.1:{{port}}/ in development mode; /admin for users with the admin role
make test    # FiveAM tests through Littoral's fake browser, each on its own database
make migrate # bring the database up to date (serving does this too) and list the migrations
make build   # bin/{{name}}, a standalone executable
make docker  # the image {{name}}, built from that executable
```

Data lives in SQLite under `data/` (or `$DATA_DIR`). Set `DATABASE_URL=postgres://user:password@host:5432/db` to use PostgreSQL instead.

## What's here

- `src/model.lisp`: `note`, a class, its description (validation, the editor, the table, the admin all come from it) and its table.
- `migrations/`: the schema, as numbered SQL files applied in order, each once: `001-notes.sqlite.sql` and `001-notes.postgres.sql` make the notes table. To change a table, add the next file (`002-notes-get-a-due-date.sql`, or a `.sqlite.sql` and `.postgres.sql` pair where the two differ) and never edit one already applied. `make migrate` or starting the app applies new ones; several processes starting at once apply each only once.
- `src/app.lisp`: the pages: who's signed in, and the notes with editors to add, change and remove them. `restricted` shows a sign-in prompt until someone signs in.
- `src/main.lisp`: the database, `register-app`, `serve`, `create-user` and the executable's `toplevel`.
- `tests/app.lisp`: signing in, editing notes, and checking they stay private.
- `deploy/`: a systemd unit and a Caddyfile.

Sign-ins are kept in the database, so they survive restarts; the sign-in form offers "Keep me signed in". "Forgot your password?" mails a reset link. Mail goes into an outbox table and the job runner sends it, trying again if the mail server is down: set `SMTP_URL` to send it, or it's printed to the log. Background jobs (`define-job` and `enqueue-job`, in `src/main.lisp`) are kept in the database too, so they survive restarts; a nightly one tidies up sent mail and finished jobs. An audit log records sign-ins, failures, password and role changes, and the admin's edits; the admin shows it under "Audit log".

## Deploying

`make build`, copy `bin/{{name}}` to the server, and install `deploy/{{name}}.service` and `deploy/Caddyfile`. The executable reads:

| Variable | |
|---|---|
| `PORT`, `ADDRESS` | where to listen (default {{port}}, 127.0.0.1) |
| `PUBLIC_URL` | the site's address, for links in mail; required in deployment |
| `TRUST_PROXY` | set behind a reverse proxy, so limits see real client addresses |
| `DATABASE_URL` or `DATA_DIR` | PostgreSQL, or where the SQLite file goes |
| `SMTP_URL` | the mail server: `smtp://user:password@host:587` (STARTTLS) or `smtps://…:465` (TLS); without it, mail is printed to the log |
| `MAIL_FROM` | the From address, such as `Bookshop <hello@example.org>` |
| `DKIM_KEY_FILE` | a PEM private key (RSA or Ed25519) to sign mail with DKIM; `{{name}} dkim-record` prints the DNS record to publish |
| `DKIM_DOMAIN`, `DKIM_SELECTOR` | the signing domain (the d= tag) and the selector (default `mail`) |

Or run it in a container: `make docker` builds the image `{{name}}` (Littoral comes from your checkout), and

```sh
docker run -d -p 127.0.0.1:{{port}}:{{port}} -e PUBLIC_URL=https://example.org -e TRUST_PROXY=1 \
  -v {{name}}-data:/data --name {{name}} {{name}}
docker exec {{name}} {{name}} create-user ada ada@example.org 'a long passphrase' admin
docker exec {{name}} {{name}} migrations     # which migrations have been applied
```

keeps the SQLite file in the volume `{{name}}-data` (or pass `DATABASE_URL`). The image checks `/healthz` itself.

[Littoral's deployment guide](https://lispnik.github.io/littoral/deployment.html) covers the rest.
