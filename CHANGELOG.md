# Changelog

## Unreleased

### Changed
- **`littoral/mail` sends through [smtp](https://github.com/lispnik/smtp)**, which replaces Littoral's own SMTP client and MIME writer.
  - The mailer gains XOAUTH2 and OAUTHBEARER, PIPELINING, SIZE checks and internationalized addresses.
  - `make-mail` now checks addresses when the mail is made.
  - `smtp-error` is now the library's condition. Use `smtp-error-code` for the reply code, not a `:code` initarg.
  - `:security :none` no longer sends a password unless the mailer is made with `:allow-insecure-auth t`.
  - smtp isn't in the ocicl registry yet; see "Getting started" in the README.

## 0.2.0 (2026-10-12)

Littoral can now carry a real application: a database, users who sign in, mail, background work, an audit trail, and a schema that can change after deployment.

### Data
- **`littoral/db`**: described objects kept in SQL through cl-dbi, tested on SQLite and PostgreSQL. Optimistic locking (`stale-object`), references between tables, and a transaction per request with `transactional`.
- **Full-text search**: `define-table :search`, `db-search` and `highlight-matches`. It uses FTS5 on SQLite and a GIN index on PostgreSQL.
- **Schema migrations**: numbered SQL files, with `.sqlite.sql` and `.postgres.sql` variants where the two need different SQL. Each one is applied once, in order, in a transaction and under a lock. Littoral's own tables are migrations too.
- **File storage** (`littoral/storage`): on disk or S3, with thumbnails, and `:file` and `:image` fields.

### Users
- **`littoral/auth`**:
  - Users, signing in, roles and permissions tables, and password reset.
  - Sign-ins are kept in the database, so they survive restarts. "Keep me signed in" is offered, and users can see and end their sessions.
  - Your own users table can be used through `sql-user-store`, and bcrypt, Django and Werkzeug password hashes are accepted.
  - Second factors: authenticator apps, passkeys and recovery codes.
- **`littoral/oauth`**: sign in with OAuth 2 and OpenID Connect providers.
- **`littoral/admin`**: an administration interface generated from descriptions.
- **`littoral/audit`**: who did what, and when.
  - Sign-ins and their failures, password and role changes, tokens, second factors, and the admin's edits are recorded without any code in your app.
  - Your app can record its own events, and the admin shows the log.

### Background work and mail
- **`littoral/mail`**: MIME messages, an SMTP client and an outbox.
  - The SMTP client does STARTTLS (with no fallback to sending unencrypted), implicit TLS and AUTH, and checks certificates by default.
  - `define-mail` templates.
  - The outbox is a database table with retries, so pages never wait for a mail server.
- **`littoral/jobs`**: durable jobs in the database.
  - Retries with backoff, scheduled and recurring jobs (`daily-at`), and duplicate jobs collapsed by key.
  - A job is claimed by one process at a time.
- **In-memory jobs** (`submit-job`): a worker pool whose progress is pushed to the page.

### Pages and widgets
- Modal dialogs (`show-modal`, `call-modal`) and toasts.
- A data grid, charts, a calendar, kanban, Markdown, and wizards built from descriptions.
- JSON endpoints beside an application's pages, with API tokens.
- WebSockets (`littoral/websocket`): push and AJAX over one socket.
- Browser code written in Parenscript (`littoral/parenscript`).
- Translations into French, German and Spanish (i18n).
- Meta tags and links in the page head.
- AJAX redraws keep the typed text and caret of a focused field.
- Layouts fit phone screens.

### Development
- **Live redefinition**: recompile a render method and open pages redraw.
- **Debugging**: in development mode, errors show a debugger in the page. The tools also include time travel through history and the component tree.
- **`littoral/test`**: the fake browser, as a kit for testing your own app in-process.
- **`littoral/browser-test`**: tests in headless Chrome, driven from Lisp.
- **Project generator**: `make new` creates a project, from a basic template or a full app template with database, sign-in, admin, mail, jobs and migrations.

### Deployment and operations
- Woo as an alternative server, with server push from its event loops.
- Health checks (`/healthz`), Prometheus metrics, and JSON request logs.
- Docker images for the demos (`make docker`) and for generated apps.
- A deployment guide, and a docs site at https://lispnik.github.io/littoral/.

### Security
- **Content security policy**: a strict one, with a nonce per page, on every page.
- **Security review fixes**: session fixation, reset-link poisoning through the Host header, WebSocket origins, and limits on sign-in attempts.
- **Accessibility**: every example passes a WCAG audit in CI, in both colour schemes.

### Fixes
- **SQLite**: statements are freed as soon as they've run, and transactions begin `IMMEDIATE`. Before, a connection could keep a read lock until garbage collection, and a transaction that read before it wrote could fail at once with "database is locked".
- **Uptime**: an executable counts its uptime from when it starts, not from when it was built.
- **QR codes**: now made with clqr (MIT) instead of cl-qrencode (GPL).

### Upgrading from 0.1
- **Content security policy.** Inline `<script>` elements and `on…` attributes written by hand no longer run. Put browser code in Parenscript handlers, AJAX callbacks or `execute-script`, which carry the nonce. Or pass `:content-security-policy` to `register-application`: a string with `{nonce}`, or `nil` to send no policy.
- **Everything else** in 0.2 is new systems you opt into, and 0.1 had none of them, so there's nothing else to migrate.

### Quality
- 1627 unit checks in 316 tests (FiveAM, in-process).
  - The database suites run again against PostgreSQL in CI.
  - Mail is tested against a real SMTP server (Mailpit) in CI.
- Headless Chrome tests, in JavaScript and in Lisp, and an accessibility audit of every example page.
- 29 examples under `/examples`.

## 0.1.0 (2026-10-06)

The first release: the Seaside model (components, callbacks, `call`/`answer`, the back button, tasks), descriptions, widgets, AJAX, server push, development tools, security defaults, 16 examples and an issue tracker. See the [release notes](https://github.com/lispnik/littoral/releases/tag/v0.1.0).
