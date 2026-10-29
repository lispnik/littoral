# Changelog

## Unreleased

### Added
- **HSTS.** HTTPS responses carry `Strict-Transport-Security: max-age=31536000`, so a browser that has reached the site over HTTPS never tries plain HTTP for it, where a first request could be downgraded. `*hsts-max-age*` sets the time; NIL leaves the header out. It covers the host alone, not its subdomains.
- **Encrypted authenticator-app secrets.** With `$LITTORAL_FACTOR_KEY` (or `littoral.auth:*factor-key*`), 32 bytes as hex or base 64, TOTP secrets are kept encrypted with AES-256-GCM, bound to their user, so whoever reads the database or a backup can't make codes. Secrets kept before the key was set still work and are encrypted when next used; `encrypt-factor-secrets` encrypts them all at once. Without a key, secrets are kept as before.
- **New passwords are checked.** `new-password-problem` refuses passwords shorter than `*min-password-length*` (8), common ones (with digits or symbols added too), and those too easy to guess, counting the user's name and email address for little. The reset form uses it. With `*check-breached-passwords*`, passwords Have I Been Pwned has seen in breaches are refused as well (`breached-password-p`); only five hex digits of the password's SHA-1 are sent, and an unreachable service refuses nothing. littoral/auth now depends on dexador for that.

- **Request ids, users and more in the request log.** Every request has an id (`*request-id*`), sent back as `X-Request-Id`, shown on the error page and logged, so a reported failure can be found; behind a trusted proxy its own `X-Request-Id` is used. Log lines also carry the signed-in user's id (littoral/auth sets `*request-log-user-function*`), the response size, the user agent and the referrer, without its query string.
- **The request log from the environment.** `start` reads `$LITTORAL_REQUEST_LOG` (`json`, `text` or a file) through `log-requests-from-environment`, so a deployment can log requests without code.
- **Changing the factor key.** Old keys go in `$LITTORAL_OLD_FACTOR_KEYS` (or `littoral.auth:*old-factor-keys*`); secrets sealed with them still open, and are sealed again with the current key when next used or by `encrypt-factor-secrets`, which now checks every secret opens before changing any. Each sealed secret names its key by a short hash (`aes1:KEYID:…`); those sealed before then still open. `create-auth-tables` warns when keys are malformed, or when secrets are encrypted but no key is set.

- **More security headers.** Every response carries `Cross-Origin-Opener-Policy: same-origin` and a `Permissions-Policy` turning off the camera, microphone, location, payments and USB.
- **Closed event streams are logged.** The request log gets an `events-closed` line when an open page's stream ends, with how long it was open and the events it sent, under the opening request's id; `littoral_event_stream_seconds` counts the durations.
- **Breached passwords in new projects.** Projects made with `TEMPLATE=app` refuse new passwords seen in breaches (`*check-breached-passwords*`); `CHECK_BREACHED_PASSWORDS=0` turns it off.
- **Request sequences are fuzzed.** `fuzz-request-sequences` wanders the examples in random clicks, form posts, AJAX calls, reloads and back-button steps, checking that no request fails, that going back shows a page as it was shown, that showing a page again changes nothing, and that no action changes snapshotted state in place.
- **Deploying without losing sessions.** `drain` hands a process's place to a new one: it goes on serving the sessions it has, starts none (a new visitor gets 503 and a forgotten session is sent on without its key, both of which the proxy gives to the other process), fails `/healthz`, and stops once its sessions have ended or the deadline passes. `drain-on-signal` drains on SIGUSR1; `add-drain-hook` stops work the new process takes over, and littoral/jobs' stops the job runner. The deployment guide's new section has a systemd unit per instance, `handover.sh`, and nginx and Caddy configurations that route by session key; projects made with `TEMPLATE=app` read `INSTANCE_ID` and handle SIGUSR1.
- **State changed in place is noticed.** A list, vector, string or hash table that the back button's snapshots share, changed in place by a page's actions (`nconc`, `(setf gethash)`, `sort`…), changes in every snapshot, so going back can't undo it. In development mode Littoral now compares what each snapshot saved after the actions run, warns with `state-changed-in-place` (once per slot), and names the slot in the toolbar. `shared-state-slots` lists slots changed in place on purpose; `*check-state-changed-in-place*` turns the check on everywhere (T) or off (NIL).

- **Fuzz tests.** A `fuzz` suite feeds random and mutated input to the passkey parsers, the decoders, sealed secrets, escaping, the SQL splitter, whole requests and JSON endpoints. `make test` runs it on a fixed seed; `make fuzz` runs many more cases on a random one.

### Changed
- **Changing a password signs out everywhere else.** `set-password`, which password reset uses, now ends the user's other sign-ins and voids their API tokens, so someone holding a stolen "keep me signed in" cookie or a token is shut out; the session making the change stays signed in. `:sign-out-others nil` keeps the old behaviour.
- **A passkey used alone must verify the user.** Signing in with only a passkey now asks for, and requires, user verification (a fingerprint, face or PIN), since it stands in for the password; a touch is no longer enough. As the second step after a password, the user need only be present, as before.
- **Signing in with a passkey finds it by index.** Passkeys keep their credential id in a column of their own, `auth_factors.credential_id`, with a unique index; before, each passkey sign-in read every passkey. A migration adds the column and fills it in for existing passkeys.
- **`__Host-` cookies over HTTPS.** The session cookie (with `:cookie-sessions`) and the browser cookie that ties URL sessions to their browser are named `__Host-…`, with the path `/`, over HTTPS, so a subdomain or a plain-HTTP page can't plant one. Browsers holding the old names start new sessions once; sign-ins are kept.

### Fixed
- **A validation's error followed the back button.** The message `validate-with` shows wasn't saved with the page, so going back to the form before a refused answer still showed it. Decorations can now name state in `states`, as components do, and a validation's error is saved with its page. Found by the new request-sequence fuzzing.

These were found by the new fuzz tests.
- **A broken multipart body could stop the server.** fast-http signals a condition that isn't an error when a multipart body stops short, so the handler that turns broken bodies into empty ones missed it. It reached the debugger, which ends a server running without one; one request from anyone did it. Such bodies are now no body, and every request runs under a guard that answers 500 for anything that would reach the debugger, such as an exhausted stack.
- **Passkey parsing.** Deeply nested CBOR exhausted the stack (now at most 16 levels, and no length past the data's end). A COSE key whose coordinates weren't 32-byte strings could make the encoder ask for a terabyte and stop the process; such keys are refused. Signatures must be strict DER: one signature no longer verifies in several encodings. Base 64 with other characters in it is refused, where cl-base64 skipped them with a warning.
- **Requests.** A plain request with `_lt_ws` (no WebSocket upgrade) got 500, now 400; WebSocket refusals carry the security headers, HSTS included. A JSON endpoint given a body that isn't UTF-8 answers 400, not 500, and a path segment with a broken escape matches no endpoint instead of failing.

## 0.5.1 (2026-10-21)

A fix and a feature for JSON endpoints. In 0.5.0 the endpoints of an application registered at `/`, as projects made by `make new` are, all answered 404; now they answer. Endpoints can also describe themselves, and `serve-openapi` serves the description as OpenAPI 3.1 for Swagger UI, Postman and client generators.

### Added
- **OpenAPI descriptions of JSON endpoints.** `serve-openapi` answers `GET /openapi.json` with an OpenAPI 3.1 description of an application's endpoints, for Swagger UI, Postman and client generators; `openapi-description` gives it as a hash table. `define-endpoint` takes a docstring (its first sentence is the summary) and options before the body: `:tags`, `:responses`, `:request-body` and `:query`; `register-endpoint` takes them as keywords. Path parameters come from the pattern, errors are described as `{"error": message}`, and with littoral/auth loaded a bearer token is described as optional. The JSON endpoints example serves its own.

### Fixed
- **Endpoints of an application at `/` answer.** Only `/` itself reached the root application, so its endpoints, such as those of a project made by `make new`, got 404. Paths its endpoints don't serve still do.

## 0.5.0 (2026-10-21)

This release is about widgets and working together live. It adds breadcrumbs, editing in place, menus, accordions, popovers, drawers and split panes, a command palette, lazy panels, lists that load more, filter builders, virtual data grids, event calendars, more charts and ten more field kinds. On top of server push, it adds presence (who else has a page open), comment threads, notifications and an activity feed, and on Hunchentoot an open push page no longer holds a thread. It also changes how HTML is written: `littoral.html` now has a macro for every HTML element and shadows CL's `map`, `search` and `time`, so a package gives it a nickname, `(:local-nicknames (#:h #:littoral.html))`, and writes `h:div`, rather than using it. To upgrade, replace `(:use … #:littoral.html)` with that nickname, prefix tag and brush calls with `h:`, and rename `var-tag` to `h:var`.

### Added
- **Breadcrumbs from the call stack.** `breadcrumb-trail` names a component, then what it has called, down to what shows now; each link goes back to its level. `breadcrumb-label` names each level (a description editor's is its title). `home` now also drops the dismissed component's answer handler, which no caller could use any more.
- **An in-place editor.** `make-in-place-editor` edits one field of one object where it is shown, over AJAX, with the description's own input and validation; `:on-save` gets the object, and `:update` redraws other components that show the value.
- **Durable jobs show progress and can be stopped while running.** `note-job-progress` takes `:fraction` (`durable-job-progress-fraction`). `cancel-durable-job` asks a running job to stop and answers `:requested`: its next `note-job-progress` signals `job-cancelled`, and it ends marked cancelled; a job that fails after the request isn't retried. `durable-job-view` shows a job's progress bar, status and Cancel button, kept up to date by server push for jobs run in this process (`*durable-jobs-channel*`), or by polling (`:poll`). The admin's job queue offers Cancel on running jobs too. Two columns are added to `job_queue` by a migration.
- **Presence: who's here.** `find-presence` names a place pages can be in, such as a wiki page. A `presence-list` shows who has a page there open, by name with what they're doing (`presence-activity`, such as "editing"), and the guests counted, redrawn by server push as people come and go. Components put their page in presences with `presences`. Names come from `(setf presence-name)` or `*presence-name-function*`, which littoral/auth sets to the signed-in user's name. The chat lists who's in the room, and wiki pages show who's reading and who's editing.
- **Edits no longer silently overwrite someone else's.** The in-place editor and the data grid note each value when editing starts. A value someone else changed meanwhile is reported ("Someone else changed this to … meanwhile"), and saving again replaces it. An `:on-save` that signals the new `edit-conflict` condition is reported the same way, with the object put back. littoral.db's `stale-object` is now an `edit-conflict`, so `:on-save #'db-save` just works; the in-place editor's `:reload` (such as `db-reload`) shows the record as it is now. The data grid's `:row-key` finds the row being edited among rows read afresh, which before couldn't be edited at all.
- **CSV export.** `:csv-filename` on a `report` or `data-grid` adds a Download CSV link: every row, with the current filters and order, and cells that would start a spreadsheet formula made safe. `report-csv`, `data-grid-csv` and `csv-text` give the text. `send-download` lets any callback answer with a file, the page staying as it was.
- **Disclosures and accordions** (`disclosure`, `accordion`): details elements that work without JavaScript, with what's open kept on the server. An accordion opens one section at a time unless `:multiple t`.
- **Dropdown menus and menu bars** (`dropdown-menu`, `menu-bar`): details elements too; littoral.js closes them on Escape or a click elsewhere, keeps one open at a time, and moves between items with the arrow keys.
- **Field kinds `:tags`, `:time` and `:date-range`.** Tags are typed separated by commas and shown as removable chips, with suggestions (`:choices`), `:only-choices` and `:max`. Times are `(HOUR MINUTE)` and date ranges `((Y M D) . (Y M D))`, checked so they don't end before they start. All three are stored by littoral.db.
- **Uploads take dropped files and show their progress.** File inputs inside `.lt-drop` (as `file-field`s now are) accept files dropped on them, and a form sending files uploads by XHR with a progress bar, then goes on to the next page as before.
- **HTTPS without a proxy.** `start` takes `:ssl-certificate-file` and `:ssl-key-file` (and `:ssl-key-password`), on Hunchentoot and Woo. On Hunchentoot the push hub serves event streams over TLS too. Cookies are `Secure` and WebSocket URLs `wss:` even on Woo, which reports every request as http.
- **Pushes render in parallel.** The push hub renders and writes on `*push-render-threads*` threads (4), each page by one thread at a time, so a broadcast to many pages isn't rendered one page after another.
- The widgets example has Breadcrumbs (a pantry to browse, fields edited in place), Forms and Menus tabs, the upload example a drop zone, and the jobs demo shows its report's progress in a `durable-job-view`.
- **Lazy panels.** `lazy-panel` sends a placeholder and fills it in over AJAX once the page has loaded, or once it's scrolled into view with `:when-visible t`, so slow parts don't hold the page up. `:content` is a component or a function making one, called only then; without JavaScript a link loads it. The report example's chart is one.
- **Differences between texts.** `diff-view` shows two texts' differences line by line, inline or side by side, with the words that changed in a changed line marked and long unchanged stretches cut to a few lines of context. `text-diff` gives the comparison as data. The wiki's history shows what each revision changed.
- **A command palette.** `command-palette` opens on Ctrl-K (⌘K on a Mac) and finds `palette-command`s by fuzzy match as you type (`palette-match-score`); the arrow keys, Enter and Escape work as expected, and it works without JavaScript. `:search` adds commands from what's typed. The admin has one in its header, going to any table or a new record, and the widgets example has one over its tabs.
- **Notifications** (`littoral/notifications`). `notify-user` keeps a message for a user until they read it. `notification-bell` shows the signed-in user's unread count, updated by server push as notifications arrive (or by `:poll`, for other processes), and opens onto the latest; following one marks it read. `user-notifications`, `mark-notification-read`, `mark-all-notifications-read` and `purge-notifications` do the rest. The members demo notifies a user made an editor, and sends one from a durable job on request.
- **`littoral.db:after-commit`** calls a function once the current transaction commits, and never if it rolls back. Notifications are published through it.
- **Field kinds `:stepper`, `:range`, `:rating`, `:color`, `:multiple-choice`, `:transfer` and `:new-password`.** A stepper has − and + buttons; a slider shows its number as it moves; a rating is radio buttons drawn as stars; a colour has the browser's picker and a box for its code. A multiple choice is a list box, and a transfer list two lists with buttons moving items between them. A new password has a strength meter that littoral.js updates as it's typed, from `password-strength` on the server, and `:min-strength` refuses weak ones. All work without JavaScript, and littoral.db stores them. littoral/auth's password reset form shows the meter too (`render-new-password-input`).
- **Popovers, tooltips, drawers and split panes.** `with-popover` uses the browser's own popover; `with-tooltip` shows a tip on hover or focus, which Escape hides. A `drawer` slides in from the side, taking the focus and giving it back; a `split-pane` has a divider moved by dragging or the arrow keys. Whether a drawer is open, and where a divider was left, are kept on the server.
- Callbacks of a new kind, `:values`, get every value a field posts under its name, as a multiple select sends them. The fake browser's `select-options` chooses several.
- The widgets example has Inputs and Layout tabs, and the accessibility audit now covers its Forms, Inputs and Layout tabs and an open drawer.
- **Lists that load more.** `load-more-list` shows a batch of its items at a time with a Load more button, and with `:automatic t` loads the next batch as the end scrolls into view. `:fetch` asks a database for just the batch. The focus moves to the first new item, a status line says how many are shown, and how many are shown is kept on the server.
- **Filter builders.** `filter-builder` holds conditions such as "Due is before 2026-11-01" on a description's fields, with comparisons suited to each kind of field, matching all or any. `filter-matches-p` applies them. A `data-grid` with `:conditions` has one above it (`data-grid-filter`).
- **Virtual data grids.** A `data-grid` with `:virtual N` shows N rows at a time in a box that scrolls through every row. It writes only the rows near those on screen and fetches others over AJAX as it scrolls, so a table of thousands of rows stays quick. Where it was left is kept on the server, and without JavaScript it pages.
- **Pie, donut, stacked bar and scatter charts** (`pie-chart`, `stacked-bar-chart`, `scatter-chart`), as SVG with a key and their data as a table. The series colours now have dark-mode variants, and there are six of them.
- **Event calendars.** `event-calendar` shows a week or a day of timed events on a grid of hours, with overlapping events side by side. With `:on-move`, events can be dragged to another time or day. Buttons move a chosen event from the keyboard or without JavaScript.
- The widgets example has Big table and Load more tabs, more charts, and a week of events to drag.
- **Comment threads.** `live-comment-thread` shows the comments on something and a box for adding one. Comments posted appear at once on every page showing the thread, announced to screen readers, and those writing one are shown as writing it, from presence. Comments are kept in `*comment-store*` (in memory), or with `littoral/comments` in a database (`database-comment-store`), or in a store of your own. `add-thread-comment` and `delete-thread-comment` work from code. Each wiki page has a thread.
- **Times ago that keep up.** `time-ago` writes a time as "3 minutes ago", and littoral.js keeps it up to date in the page's language; `time-ago-text` gives the words. The notification bell uses it, and now says how many days ago, up to a week.
- **An activity feed.** `littoral.audit:activity-feed` shows what's happened lately from the audit log, newest first, live as events are recorded (`*audit-channel*`), a batch at a time. `*activity-phrases*` says what each action was in words. The members demo shows it to admins.
- `load-more-list` takes `:subscriptions`, channels that draw it again on open pages. A live region whose content hasn't changed is left alone by littoral.js, so it isn't announced again.

### Changed
- **Every HTML element has a tag, under its own name, and `littoral.html` is meant to be used through a nickname.** The package now has a macro for each element in the HTML standard: `time`, `map`, `search`, `var`, `data`, `option`, `picture`, `video`, `dialog`, `template` and the rest, the plain `a`, `input`, `select`, `textarea` and `option` beside the brushes, and `html`, `head`, `style` and `script` for writing whole documents. It shadows CL's `map`, `search` and `time`, so a package can't `:use` both; give it a local nickname instead, `(:local-nicknames (#:h #:littoral.html))`, and write `(h:div (:class "x") (h:p () "Hello"))`. `var-tag` is now `var`. Littoral, its examples, the tutorial and the `make new` templates are written this way.
- **Server push on Hunchentoot no longer holds a thread per page.** Once a page's event stream has begun, its connection leaves Hunchentoot's thread (through `detach-socket`) for littoral's push hub, one thread that watches every open stream (with a few render threads, below). 600 open push pages now cost 22 threads and 121 MB for the whole server, down from 621 threads and 1,355 MB, with `start`'s default `:max-threads` of 100. On Linux, 10,000 open pages took the server from 4 threads to 5, before the render threads were added. A page whose browser has stopped reading is dropped rather than waited for. (On macOS, SBCL waits on sockets with `select(2)`, so a Hunchentoot server there still holds about 1,000 connections at most.)
- **The admin names tables properly**: "Shelves", "Categories" and "People", not "Shelfs", "Categorys" and "Persons". `define-description` takes `:label` and `:plural` for names the rules get wrong; `description-label`, `description-plural` and `english-plural` are exported.
- The admin's Edit, Delete and "Back to the list" links (and the job queue's status filters) have spaces between them, so they read apart without the stylesheet. Edit and Delete are translated.
- littoral/mail uses smtp 0.3.6, which exports `make-reply`; tests and examples no longer reach for `smtp::make-reply`.
- **smtp comes from the ocicl registry**, like every other dependency, so `ocicl install` is all a checkout needs. `tools/fetch-smtp.sh` is gone, and the Docker images no longer install git.

### Fixed
- **A form's own `:method`, `:action`, `:accept-charset` or `:enctype` replaces the one `h:form` writes by default**, rather than writing the attribute twice, which left the browser using the first. `(h:form (:method "dialog") …)` now closes the dialog it is in, without a request.
- **littoral/browser-test waits for slow pages.** `click-text`, `click-css`, `visit` and `back` waited a quarter of a second and then for the document to be complete, but the old page stays complete until the server answers, so a page slower than that (signing in hashes a password) was read before it arrived. They now follow Chrome's loading events.

## 0.4.0 (2026-10-18)

This release is about documentation you can trust: an example for nearly every exported function, macro and class, each run by the test suite, a tutorial that goes on to testing, a database, signing in and translation, and a README whose code is checked. Checking it all against the code found and fixed about fifteen bugs, one of them a way for `/config` to be reopened to everyone. Clicks are also 45–70% faster.

### Added
- **Examples for the whole API, all tested.** docs/API.md has 813 examples, over every exported function, macro and class but those needing Chrome or an S3 server. They live in `docs/examples/`; the test suite runs each on its own, in a fresh package set up as the reference tells readers to, and checks every result shown (`;; ⇒`). `make examples` runs them alone. Docstrings were checked against the code throughout, and many corrected.
- **The reference covers every package**: `littoral.db`, `littoral.storage`, `littoral.oauth`, `littoral.websocket`, `littoral.parenscript`, `littoral.woo` and `littoral.generator` too. Each package's section says which system to load.
- **The tutorial goes further**: testing the reading list with the fake browser, keeping it in a database, signing readers in, and a second language (steps 12 to 15). A test pastes the tutorial's code blocks in order into fresh packages and checks each step does what the text says; another checks every block matches the code in `docs/tutorial/`.
- **The fake browser** (`littoral.test`) gains `body-text`, a page's text as a reader sees it, and `choose-radio`. `fill-in` and `select-option` also find a field by its label, and responses whose body is octets or a file (such as stored files) can be read.
- `*keepalive-seconds*` and `littoral.storage:*signing-key*` are exported, as the docs already said.
- **The README is tested.** Every Lisp block in it must read, so each Littoral name it uses is exported; the complete ones (the first counter, the database, signing in, the audit log, Parenscript and the testing example) run as written, and their results are checked.

### Fixed
- **`start` returns once the server accepts connections.** Clack starts the server in a thread of its own; a `stop` straight after `start` could kill that thread while it held SBCL's name-service lock, and every later address lookup in the process then waited forever.
- **A saved configuration keeps `/config` local.** `:local-only` wasn't saved, so after `/config` was unregistered, loading an older configuration file brought it back open to any address.
- **Editing an object with a password field no longer wipes the password.** The field starts empty, so Save wrote NIL, or refused when it was required. A blank password field now keeps the stored value, in editors and wizards.
- **A wizard's whole-object check sees every field**, with the stored value for those its steps leave out, as an editor's does.
- **Refused uploads aren't stored.** A file too large, or not an image for an image field, was kept in storage with nothing pointing at it.
- **Cached roles belong to their database**, so applications with databases of their own no longer briefly see each other's roles for users with the same id.
- **Inputs and buttons write one `type`.** `(text-input (:type "search"))` wrote two, and browsers took the first.
- `db-select` and `db-search` honour `:offset` without `:limit`.
- Changing `*latency-buckets*` after requests were counted made every later request fail; the request histogram now starts again.
- `current-user`, `signed-in-p`, `has-role-p` and `has-permission-p` answer NIL outside a request rather than signalling.
- The second sign-in step's code field had an empty label; the tree's toggle labels, the suggestion count and "Sign out" are translated.
- Basic auth compares digests, so the time taken says nothing about the credentials' length.
- Generated apps start one job runner, not two, and read `TRUST_PROXY=0` as off.
- Sparklines are inset by a pixel on both sides.
- README and deployment guide: every code block now runs as written, and claims that didn't match the code were corrected.

### Changed
- **Clicks are 45–70% faster.** Profiling store and counter clicks under load found three costs, now gone:
  - Every page render looked at `littoral.js` on disk to fingerprint it, which took over a third of the server's time. Static files are now looked at once a second at most (`*static-check-interval*`), so an edited file still shows up.
  - Responses had no Content-Length, so Hunchentoot sent them chunked, flushing the headers on their own. Littoral now gives one for every response with a body of strings.
  - Classifying each request for `/metrics` compiled up to four regular expressions.

## 0.3.0 (2026-10-15)

This release is about running Littoral in production: admins who sign in from anywhere, metrics for every subsystem, SQLite in WAL mode, mail through the smtp library with DKIM and pooled connections, and a job queue page.

### Added
- **Admins and `/config` behind sign-in.**
  - `register-admin` takes `:role`: users with that role sign in to the admin from anywhere, and the audit log names them.
  - `littoral.auth:configure-signed-in-admin` does the same for `/config`.
  - Any application can do it, with `signed-in-root`, `restrict-application` and `check-application-role`.
  - Generated apps' `/admin` is now for users with the admin role, rather than for this machine only.
- **Pages come back after a restart.** A page's AJAX requests, event stream, WebSocket and live checks are told to reload when its session is gone, instead of being given a session they can't use. Signed-in users stay signed in.
- **DKIM**: `make-smtp-mailer :dkim` signs mail with `smtp/dkim` signers. Generated apps read `DKIM_KEY_FILE`, `DKIM_DOMAIN` and `DKIM_SELECTOR`, and have a `dkim-record` command.
- **SMTP connections are reused**, up to `:pool-size` (2) per mailer. A kept connection the server has dropped is replaced at once, through smtp 0.3.5's `retry-with-fresh-connection` restart.
- **`purge-expired-auth-rows`** deletes old sign-in failures, expired sign-ins, and expired reset links and API tokens. Generated apps' nightly `tidy-up` job calls it, and also deletes audit events more than a year old.
- **A job queue page in the admin.** It lists durable jobs by status, with their errors, and retries or cancels them; the audit log records both. It appears where the database has the job tables. `littoral.jobs:durable-jobs` takes `:offset`, and `job-tables-p` says whether the tables were made.
- **API reference for `littoral.auth` and `littoral.admin`** in docs/API.md.
- **Metrics for durable jobs and mail.** `/metrics` reports jobs by queue and status, how long the oldest due job has waited, runner threads, the outbox by status, and how long the oldest unsent mail has waited, for each database whose tables were made in the process. `add-metrics-source` lets other code add metrics. `littoral.db:database-label` names a database without its credentials.
- **More metrics**: job runs by job and result, with durations; mail sends by result, SMTP send times and connection pools; sign-ins by method, failures by reason, reset mails and active sign-ins; database lock timeouts, conflicting saves, transaction times, SQLite file sizes and pending migrations; sessions started, ended and refused; GC time, bytes allocated and build info. Applications add their own with `define-metric`, `count-metric`, `observe-metric` and `timing-metric`.
- **A comparison with Seaside.** `bench/compare.sh seaside` measures Seaside on Pharo, from an image `bench/seaside/setup.sh` builds, and the README gives the results. `compare.sh` also measures one user clicking, and `WORKERS` sets Woo's event loops.
- **The demo server's** admin demo and `/config` are for the members demo's admins, who sign in to them from anywhere.

### Fixed
- **The load server's push test publishes again.** Its push page lost its channel when the progress example changed, so `/_publish` failed and no page was updated; it has a page and channel of its own now.

### Changed
- **SQLite files use WAL mode**, so reads and writes no longer wait for each other, with `synchronous=NORMAL`. `*sqlite-journal-mode*` and `*sqlite-synchronous*`, or `:journal-mode` and `:synchronous` in the database spec, change this. Back up with `VACUUM INTO`: see "SQLite in production" in the deployment guide.
- **Mail is sent by the job runner.** Each queued message has a `deliver-mail` durable job; the separate delivery thread is gone. `start-mail-delivery` starts a job runner unless one is running, and `create-mail-tables` creates the job tables too.
- **Sign-in limits are kept in the database** (`auth_events`, migration 2 of `:littoral-auth`). Lockouts and reset-mail caps now survive restarts and are shared between processes.
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
