# Deploying a Littoral application

This guide takes an application from `make run` to a server: an executable, a service that keeps it running, a reverse proxy with TLS in front, a database, and the settings that matter in production. The configuration files are in [docs/deploy/](deploy/).

## 1. Build an executable

A project from `make new` has a `build` target:

```sh
make build          # bin/bookshop: SBCL, your code and its dependencies in one file
```

The executable starts the application in deployment mode (no toolbar or halos) on `$PORT` (default 8080) and `$ADDRESS` (default 127.0.0.1), and runs until killed. Littoral's own JavaScript and CSS are saved inside it, so the server needs neither the source nor Lisp installed. Build on the same operating system and CPU architecture as the server, for example in a container or on CI.

For an application of your own, the essentials are these, with `bookshop:register-app` standing for whatever registers your applications:

```lisp
(asdf:load-system :bookshop)
(sb-ext:save-lisp-and-die "bookshop" :executable t
  :toplevel (lambda ()
              (bookshop:register-app :mode :deployment)
              (littoral:start :port (parse-integer (or (uiop:getenv "PORT") "8080")))
              (loop (sleep 3600))))
```

Don't connect to the database, start threads or open files before saving. Do it in the toplevel function, which runs at startup.

## 2. Settings that matter in production

| Setting | Why |
|---|---|
| `:mode :deployment` on every application | Development mode shows halos, which let anyone inspect and change component state. `start` warns if a development-mode application is served on a public address. |
| `littoral.auth:*public-url*` | Reset links and OAuth redirects use it. Deployment mode requires it, because the Host header is the client's to choose. |
| `littoral:*trust-forwarded-for*` | Set it to `t` behind a proxy that sets `X-Forwarded-For`, so rate limits, lockouts and logs see real client addresses rather than the proxy's. Leave it off when clients reach Littoral directly, or they could claim any address. |
| `littoral:*max-request-size*` | Default 10 MB. Keep the proxy's limit (`client_max_body_size`) at least as large. |
| `:session-timeout`, `:max-sessions` | How long idle sessions last (default 30 minutes) and how many to keep (no limit by default). |
| `littoral:*new-sessions-per-minute*` | Sessions one address may start a minute (120). |
| `littoral.auth:*send-mail*` | By default reset mail is only printed. Plug in your mailer. |

Read secrets (database passwords, OAuth client secrets) from the environment or an `EnvironmentFile`, not from the source.

## 3. Run it as a service

[deploy/app.service](deploy/app.service) is a systemd unit:

```sh
sudo useradd --system --home /opt/bookshop bookshop
sudo install -o bookshop -d /opt/bookshop /opt/bookshop/data
sudo install -o bookshop bin/bookshop /opt/bookshop/
sudo cp docs/deploy/app.service /etc/systemd/system/bookshop.service
sudo systemctl daemon-reload && sudo systemctl enable --now bookshop
journalctl -u bookshop -f
```

SBCL ignores SIGTERM while Hunchentoot's threads run, so the unit kills the process after five seconds. Nothing is lost by this: data belongs in the database, and sign-ins are kept there too.

### Or in a container

Projects made with `TEMPLATE=app` have a Dockerfile. `make docker` builds an image from the same executable, on Ubuntu, with Littoral and its dependencies taken from your checkout. (It needs Docker with BuildKit, the default today.)

```sh
make docker
docker volume create bookshop-data
docker run -d --name bookshop --restart unless-stopped -p 127.0.0.1:8080:8080 \
  -e PUBLIC_URL=https://bookshop.example.org -e TRUST_PROXY=1 -v bookshop-data:/data bookshop
docker exec bookshop bookshop create-user ada ada@example.org 'a long passphrase' admin
```

- The image runs as an unprivileged user, listens on 0.0.0.0 inside the container, and keeps SQLite in `/data`. Pass `DATABASE_URL` to use PostgreSQL.
- It checks `/healthz` itself, so `docker ps` shows whether it's healthy.
- Publish the port on 127.0.0.1 and put the proxy below in front, as for the service.
- `docker stop` waits ten seconds and then kills it, for the SIGTERM reason above.

Littoral's own `make docker` builds `littoral-demo`, every example in one image: `docker run --rm -p 127.0.0.1:8080:8080 littoral-demo`. The examples run in development mode, so keep that one on your own machine.

## 4. Put a reverse proxy in front

Littoral should listen on 127.0.0.1, with a proxy taking the public connections and handling TLS.

To serve HTTPS without a proxy, give `start` a certificate and its key, as PEM files: `(start :port 8443 :address "0.0.0.0" :ssl-certificate-file "cert.pem" :ssl-key-file "key.pem")`, with `:ssl-key-password` for an encrypted key. It works on Hunchentoot and on Woo, server push included, and cookies are marked `Secure`. A proxy is still the better choice in front of the internet: it renews certificates, holds idle connections cheaply, and can spread requests over several processes.

- **Caddy** ([deploy/Caddyfile](deploy/Caddyfile)) gets certificates by itself. `flush_interval -1` keeps server push streaming.
- **nginx** ([deploy/nginx.conf](deploy/nginx.conf)): use Let's Encrypt (`certbot --nginx`) for certificates. The configuration passes `X-Forwarded-*` headers. For server push it turns buffering off and allows long reads. For `littoral/websocket` it passes WebSocket upgrades through.

With the proxy setting `X-Forwarded-Proto: https`, Littoral marks its cookies `Secure`. If WebSockets are refused (a proxy that doesn't pass upgrades), pages fall back to server-sent events by themselves.

## 5. The database

SQLite suits a single process: give it a file in the data directory (`ReadWritePaths` in the unit). For several processes, or for more than a little traffic, use PostgreSQL (below).

### SQLite in production

- **WAL mode.** Littoral switches a SQLite file to write-ahead logging when it first connects (`littoral.db:*sqlite-journal-mode*`, `:wal`), so pages reading and the job runner writing don't wait for each other; writers still take turns. The mode is kept in the file. Connections also use `synchronous=NORMAL` (`littoral.db:*sqlite-synchronous*`): a power cut can lose the last few commits, but never damages the file. Use `:synchronous :full` in the database spec if every commit must survive a power cut. `:journal-mode nil` leaves the file as it is.
- **Three files.** Beside `app.db` SQLite keeps `app.db-wal` and `app.db-shm`. Copying `app.db` alone while the server runs can miss recent commits. Back up with `sqlite3 app.db "VACUUM INTO '/backups/app.db'"`, or SQLite's `.backup` command, or stop the service first.
- **One machine.** Every process using the file must run on the same host, and the file must be on a local disk, not NFS or another network filesystem.
- **Going back.** To leave WAL mode, set `*sqlite-journal-mode*` to `:delete` and start with nothing else using the file, or run `sqlite3 app.db "PRAGMA journal_mode=DELETE"` while the service is stopped.

### PostgreSQL


```lisp
(littoral.db:connect-database :postgres :database-name "bookshop" :host "localhost"
                              :username "bookshop" :password (uiop:getenv "DB_PASSWORD"))
(littoral.auth:create-auth-tables)      ; safe to run at every start
```

Each thread gets its own connection, made when first needed. Back up with `pg_dump`. `make test-postgres` runs Littoral's database tests against a server of your own.

## 6. More than one process

Sessions (component trees, back-button snapshots, flows in progress) live in the memory of the process that made them, so each browser must keep coming back to the same process:

- **Give every process an instance id**, for example `(start :port 8081 :instance-id "a")`. Session keys then begin `a.`.
- **Route by that prefix**: the commented `map` in [deploy/nginx.conf](deploy/nginx.conf) shows how. With cookie sessions, route on the cookie instead.

Sign-ins are kept in the database (`auth_sessions`), so a browser that lands on another process, or comes back after a restart, is still signed in. Only its page state starts afresh. All processes must share the database.

## 7. Deploying without losing sessions

A restart ends every session: whatever people had on their pages, such as a cart, a half-finished checkout or a step of a wizard, is gone (sign-ins aren't, since they're in the database). Sessions can't be saved, because they are live objects, closures and continuations. So a deploy that keeps them keeps the old process running until its sessions end, while a new one takes everybody else:

1. The application runs as two instances, `a` on port 8081 and `b` on 8082, each with its instance id, so their session keys start `a.` and `b.`. One serves; the other is idle.
2. The proxy sends a request whose key starts `a.` to `a`, one starting `b.` to `b`, and any other to whichever instance takes new sessions.
3. A deploy starts the new version as the idle instance, waits for its `/healthz`, then sends the old one SIGUSR1, which drains it (`littoral:drain`):
   - its sessions go on working, AJAX, server push and WebSockets included;
   - it starts no sessions: a new visitor gets 503, which the proxy retries on the new instance, and a page whose session it no longer has is sent to the same URL without the key, which the proxy gives to the new instance;
   - `/healthz` answers 503 with `"status":"draining"`, and `littoral_draining` is 1;
   - drain hooks (`add-drain-hook`) run; littoral/jobs' stops the job runner, so the new version runs the queue, mail delivery included.
4. Once its last session has ended, or after the longest session timeout (`(drain :seconds …)`), the old instance stops and exits with code 0. Pages still open then reload and start afresh on the new instance; an `auth-root` application signs its user back in.

The files, in [docs/deploy/](deploy/):
- [app@.service](deploy/app@.service): a systemd unit for each instance (`bookshop@a`, `bookshop@b`), with its port in `/etc/bookshop/a.env` and `b.env`. It sets `INSTANCE_ID`, which the executable passes to `start :instance-id`, and the executable calls `(drain-on-signal)` at startup.
- [handover.sh](deploy/handover.sh) `APP EXECUTABLE`: puts the new executable in place, starts it as the idle instance, and once it's healthy, drains the old one. If the new one doesn't become healthy within a minute, it is stopped and the old one goes on serving. `(cancel-drain)` in the old instance takes a drain back.
- [nginx-handover.conf](deploy/nginx-handover.conf) and [Caddyfile.handover](deploy/Caddyfile.handover): proxies that route by key, fall back to the other instance when one has exited, and send new visitors only to an instance that takes them. Neither changes from one deploy to the next. With Caddy, a new visitor may get the 503 in the two seconds before its health check notices the drain; nginx retries it. Both were tried with two instances behind them (nginx 1.29, Caddy 2.10): a draining instance kept its sessions, new visitors went to the other, and once it had exited its old links reached the other too.

Projects made with `TEMPLATE=app` have the unit and the script in `deploy/`, and their executables read `INSTANCE_ID` and handle SIGUSR1.

What to bear in mind:
- **Both versions run at once, against the same database.** A migration may add tables and columns the old version ignores, but not drop or rename what it still reads. Remove those in the following deploy.
- **State kept in memory is split while both run.** Each process has its own shared objects (the wiki and chat room in the examples), and presence only sees pages on its own process.
- **A proxy is needed.** A single process with nothing in front can only restart.
- **The deadline still ends sessions.** A session still in use when the old instance's time is up is lost, as at a restart. The default deadline is the longest session timeout (30 minutes unless set), which an idle session would have reached anyway.

## 8. Server push at scale

An open page with server push holds a connection, but not a thread. On Hunchentoot, one thread, the push hub, serves every open stream; on Linux, 10,000 open pages and their sessions added about 40 MB to the server's heap. On macOS, SBCL waits on sockets with `select(2)`, so a Hunchentoot server there holds about 1,000 connections at most. Woo serves push from its event loops and has no such limit:

```lisp
(asdf:load-system :littoral/woo)          ; needs the libev C library
(littoral:start :port 8080 :server :woo :workers 4)
```

The README's "Deployment and scale" section has measurements of both.

## 9. Health checks, metrics and logs

- **Health.** Point the load balancer or uptime monitor at `/healthz`. It answers 200, or 503 when a check fails. Add checks with `(add-health-check "database" (lambda () (littoral.db:db-query "SELECT 1")))`. Checks run outside any application, so when an application gets its database from `using-database` rather than `connect-database`, bind `littoral.db:*database*` to its spec inside the check.
- **Metrics.** `(serve-metrics)` serves Prometheus metrics at `/metrics` to the machine itself. Scrape from there, or expose the path only to your monitoring network. Two are worth alerting on:
  - `littoral_durable_jobs_oldest_due_seconds` rises when jobs are due but no runner takes them, or the runners can't keep up.
  - `littoral_mail_oldest_unsent_seconds` rises when mail isn't going out, for example while the mail server refuses it.

  Also `littoral_durable_jobs_database_up` and `littoral_mail_outbox_database_up`, which drop to 0 when the database can't be read. Others worth a dashboard or an alert:
  - `rate(littoral_sign_in_failures_total[5m])`: a jump usually means someone is guessing passwords.
  - `rate(littoral_mail_sends_total{result="transient"}[15m])`: the mail server is refusing mail for now.
  - `littoral_migrations_pending > 0` after a deploy: the new version's migrations weren't run.
  - `littoral_db_lock_timeouts_total` rising on SQLite: the database is busier than one SQLite file serves well.
  - `littoral_smtp_pool_waiting > 0` for long: raise the mailer's `:pool-size`.
- **Logs.** `(log-requests-to *standard-output*)` sends a JSON line per request to the journal. It never includes the query string, which carries session keys.

## 10. Checklist

- [ ] Applications registered with `:mode :deployment`
- [ ] Littoral listening on 127.0.0.1, behind a proxy with TLS
- [ ] `*public-url*` set; `*trust-forwarded-for*` set behind the proxy
- [ ] Proxy passes WebSocket upgrades and doesn't buffer streams
- [ ] Mail sending plugged in (`*send-mail*`)
- [ ] Database backed up; secrets read from the environment
- [ ] `/config` either unregistered (`(unregister-application "/config")`), or protected with `configure-admin` or `littoral.auth:configure-signed-in-admin`
- [ ] The service restarts on failure; logs go to the journal
