# Deploying a Littoral application

This guide takes an application from `make run` to a server: an executable, a service that keeps it running, a reverse proxy with TLS in front, a database, and the settings that matter in production. The configuration files are in [docs/deploy/](deploy/).

## 1. Build an executable

A project from `make new` has a `build` target:

```sh
make build          # bin/bookshop: SBCL, your code and its dependencies in one file
```

The executable starts the application in deployment mode (no toolbar or halos) on `$PORT` (default 8080) and `$ADDRESS` (default 127.0.0.1), and runs until killed. Littoral's own JavaScript and CSS are saved inside it, so the server needs neither the source nor Lisp installed. Build on the same operating system and CPU architecture as the server, for example in a container or on CI.

For an application of your own, the essentials are:

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
| `*max-request-size*` | Default 10 MB. Keep the proxy's limit (`client_max_body_size`) at least as large. |
| `:session-timeout`, `:max-sessions` | How long idle sessions last (default 30 minutes) and how many to keep. |
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

## 4. Put a reverse proxy in front

Littoral should listen on 127.0.0.1, with a proxy taking the public connections and handling TLS.

- **Caddy** ([deploy/Caddyfile](deploy/Caddyfile)) gets certificates by itself. `flush_interval -1` keeps server push streaming.
- **nginx** ([deploy/nginx.conf](deploy/nginx.conf)): use Let's Encrypt (`certbot --nginx`) for certificates. The configuration passes `X-Forwarded-*` headers. For server push it turns buffering off and allows long reads. For `littoral/websocket` it passes WebSocket upgrades through.

With the proxy setting `X-Forwarded-Proto: https`, Littoral marks its cookies `Secure`. If WebSockets are refused (a proxy that doesn't pass upgrades), pages fall back to server-sent events by themselves.

## 5. The database

SQLite suits a single process: give it a file in the data directory (`ReadWritePaths` in the unit) and back the file up. For several processes, or for more than a little traffic, use PostgreSQL:

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

## 7. Server push at scale

On Hunchentoot every open page with server push holds a thread (about 1.5 MB). If many pages subscribe, raise `:max-threads`, or run on Woo, where an open push page costs almost nothing:

```lisp
(asdf:load-system :littoral/woo)          ; needs the libev C library
(littoral:start :port 8080 :server :woo :workers 4)
```

The README's "Deployment and scale" section has measurements of both.

## 8. Health checks, metrics and logs

- **Health.** Point the load balancer or uptime monitor at `/healthz`. It answers 200, or 503 when a check fails. Add checks with `(add-health-check "database" (lambda () (littoral.db:db-query "SELECT 1")))`, run inside a `using-database` binding when the application has its own database.
- **Metrics.** `(serve-metrics)` serves Prometheus metrics at `/metrics` to the machine itself. Scrape from there, or expose the path only to your monitoring network.
- **Logs.** `(log-requests-to *standard-output*)` sends a JSON line per request to the journal. It never includes the query string, which carries session keys.

## 9. Checklist

- [ ] Applications registered with `:mode :deployment`
- [ ] Littoral listening on 127.0.0.1, behind a proxy with TLS
- [ ] `*public-url*` set; `*trust-forwarded-for*` set behind the proxy
- [ ] Proxy passes WebSocket upgrades and doesn't buffer streams
- [ ] Mail sending plugged in (`*send-mail*`)
- [ ] Database backed up; secrets read from the environment
- [ ] `/config` either unregistered, or protected with `configure-admin`
- [ ] The service restarts on failure; logs go to the journal
