---
title: Littoral
---

# Littoral

[![CI](https://github.com/lispnik/littoral/actions/workflows/ci.yml/badge.svg)](https://github.com/lispnik/littoral/actions/workflows/ci.yml)

Littoral is a Common Lisp port of Smalltalk's [Seaside](https://seaside.st) web framework. You build an application from stateful components instead of routes and templates:

- Links and buttons carry closures (**callbacks**), not URLs you design.
- One component can **call** another and get its **answer** back.
- The **back button** restores the state each page was rendered from.
- **Tasks** describe a multi-page flow as straight-line code.

It runs on SBCL and serves through Clack (Hunchentoot by default). Dependencies are managed with ocicl.

```lisp
(defpackage #:hello (:use #:cl #:littoral #:littoral.html))
(in-package #:hello)

(defclass counter (component)
  ((count :initform 0 :accessor count-of)))

(defmethod states ((self counter)) (list self))   ; backtrack COUNT

(defmethod render ((self counter))
  (h1 () (text (count-of self)))
  (anchor (:callback (lambda () (incf (count-of self)))) "++")
  (anchor (:callback (lambda () (decf (count-of self)))) "--"))

(register-application "/counter" 'counter)
(start :port 8080)
```

## Getting started

You need SBCL and [ocicl](https://github.com/ocicl/ocicl).

```sh
git clone https://github.com/lispnik/littoral.git
cd littoral
ocicl install      # fetches everything in ocicl.csv into ./ocicl
make test          # FiveAM suite, in-process, no sockets
make run           # examples on http://127.0.0.1:8080/
make tracker       # the issue tracker on http://127.0.0.1:8080/tracker
```

### A new application

```sh
make new NAME=bookshop DIR=~/src/bookshop
cd ~/src/bookshop
make test          # its own FiveAM tests, through the fake browser
make run           # http://127.0.0.1:8080/, in development mode
make build         # bin/bookshop, a standalone executable
```

The project has a root component (a counter, a confirmation dialog and a form), tests that click through it, a Makefile that finds this checkout, a README and a license. From a REPL: `(asdf:load-system :littoral/generator)`, then `(littoral.generator:make-project "bookshop" :directory "~/src/bookshop/" :author "…" :license "MIT" :port 8080)`.

Other targets:

```sh
make e2e           # littoral.js in headless Chrome (needs Node 22+)
make a11y          # WCAG checks (axe-core) over every example page
make bench         # request and snapshot timings
make docs          # regenerate docs/API.md from the docstrings
make clean-check   # build a fresh clone against nothing but its ocicl.csv
make lint          # ocicl lint
```

Documentation is online at **<https://lispnik.github.io/littoral/>**. New to littoral? Start with **[the tutorial](tutorial.md)**, which builds a reading list one idea at a time. The full API reference is [docs/API.md](API.md).

`/examples` is a guide to the examples. Three of them are complete small applications:

- **Sushi Store** (`/examples/store`): Seaside's classic demo. A catalog report and a cart share the page. Checkout is a task: review the cart, enter an address (validated), pick a delivery date with a reusable date-picker component, choose how to pay, then confirm. You can cancel at any step and the back button works throughout. Once the order is placed, the checkout pages are isolated, so going back can't place it twice.
- **Wiki** (`/examples/wiki`): pages are shared by every session and kept out of backtracking. Each page has its own URL. There are `[[links]]` to new pages, editing with preview through `call`, history with revert, and search.
- **Chat** (`/examples/chat`): many sessions in one room. Messages are posted with an AJAX form submit, and every open page receives them by server push.

**Tracker** (`make tracker`, then `/tracker`) is a complete issue tracker built to try littoral on something real. It has:

- accounts, with PBKDF2 password hashes
- issues with status, priority, assignee and due date, plus comments
- filters and search
- live updates to everyone's lists through server push
- bookmarkable issue URLs
- data saved to a file

It lives in `apps/tracker`, in its own system, `littoral/tracker`.

The smaller examples are counter, multi-counter, login, todo, guess (a task), topics (bookmarkable URLs), report, ajax, upload and progress (a background job reporting through server push). The configuration application is at `/config`.

## Concepts

| Seaside                         | Littoral                                        |
|---------------------------------|-------------------------------------------------|
| `renderContentOn: html`         | `(defmethod render ((self c)) …)`               |
| `html div class: 'x'; with: […]` | `(div (:class "x") …)`                          |
| `html anchor callback: […]; with: 'go'` | `(anchor (:callback (lambda () …)) "go")` |
| `html textInput on: #name of: self` | `(text-input (:value … :callback (lambda (v) …)))` |
| `html render: child`            | `(render-component child)`                      |
| `children`, `states`            | `children`, `states` generics                   |
| `self call: c` / `self answer: x` | `(call self c)` / `(answer c x)`              |
| `show:onAnswer:`                | `(show self c :on-answer fn)`                   |
| `WATask>>go`                    | `(define-flow my-task (self) …)`                |
| `inform:` `confirm:` `request:` `chooseFrom:` | `inform` `confirm` `request-input` `choose-from` |
| decorations                     | `add-decoration`, `form-decoration`, `validate-with`, … |
| `updateRoot:`, `style`, `script` | `update-root`, `style`, `script`                |
| jQuery `load html:`             | `:on-click (ajax :callback … :update component)` |
| `updateUrl:`, `initialRequest:` | `update-url`, `initial-request`, `request-extra-path` |
| `html fileUpload callback:`     | `(file-input (:callback (lambda (file) …)))`    |
| `WABatchedList`, `WATableReport` | `batched-list`, `report` + `column`            |

### HTML

The tag and brush macros are in the `littoral.html` package. They live in their own package because names such as `main`, `header`, `label` and `table` are too common to push onto every package that uses `littoral`. A tag's first argument is its attribute plist, and you can omit it. Literal strings in a tag body are written as escaped text. To write any other value, call `text` (escaped) or `raw` (unescaped).

The brushes are `anchor`, `form`, `text-input`, `password-input`, `number-input`, `hidden-input`, `text-area`, `checkbox`, `select-list`, `radio-group`, `file-input`, `submit-button`, `cancel-button` and `button`. Each takes a `:callback`. When a form is submitted, the field callbacks run first, in render order, and the button's action runs after them.

A `file-input` needs its form to be `(form (:multipart t) …)`. Its callback receives an `uploaded-file`, with `file-name`, `file-content-type` and `file-contents` (octets), and is not called when no file was chosen.

A `cancel-button` runs its callback and nothing else: what was typed into the form is not applied. `(form (:default-action thunk) …)` runs the thunk when the form is submitted without a button.

Rendering must not change state. Calling `call`, `show`, `answer` or `home` while a page renders signals `render-phase-error`; do it in a callback instead.

### Bookmarkable URLs

Every page URL starts with the application's path. Each visible component's `update-url` method can then add to it:

```lisp
(defmethod update-url ((self topics) url)
  (when (current-topic self) (add-to-path url (current-topic self)))
  (when (zoomed-p self) (add-parameter url "big")))
```

That gives URLs like `/examples/topics/tasks?big&_s=…&_k=…`. When someone opens the bookmark without `_s` and `_k`, a new session starts, and the root's `initial-request` reads the URL back with `request-extra-path` and `request-parameter` (or `request-parameter-p`).

### Widgets

A `report` is a table. Clicking a column heading sorts by that column, and clicking it again reverses the order. Cells can be rendered with your own functions, and `:batch-size` pages the rows. A `batched-list` pages any list: render its `batch` yourself, then `render-component` the list to get its page links.

```lisp
(make-instance 'report
  :rows (lambda () (all-orders))
  :batch-size 20
  :columns (list (column "Order" #'order-id)
                 (column "Total" #'order-total :class "number")
                 (column "" nil :sortable nil
                         :render (lambda (row value)
                                   (declare (ignore value))
                                   (anchor (:callback (lambda () (open-order row))) "open")))))
```

### Request cycle

Littoral follows Seaside's request cycle. A request that names callbacks goes through these steps:

1. Restore the snapshot of the page the request came from.
2. Run the callbacks.
3. Snapshot the result as a new page (`_k`).
4. Redirect to that new page.

A request that names no callbacks renders the page. Pages are snapshots of the visible components' decorations, plus the slots of every object named by their `states` methods. Because of this, both going back and acting on an old page work the way they do in Seaside.

### Dialogs over the page, and toasts

`call` and `show` put a component *in place of* another. `show-modal` puts one *over the whole page* instead:

```lisp
(show-modal (make-instance 'confirm-dialog :message "Delete it?")
            :title "Delete" :on-answer (lambda (yes) (when yes (delete-it))))
```

- **The page behind** stays in view but is made `inert`, so it can't be clicked or tabbed into.
- **Keyboard:** focus moves into the dialog and Tab stays there. Esc or the × closes it, answering `nil`; with `:closable nil`, the dialog must be answered.
- **In flows:** `call-modal` is the version that seems to wait.
- **The back button** works through dialogs, as it does through `call`.

`(toast "Saved." :kind :success)` shows a short message at the corner of the page, announced politely to screen readers. It appears on the next page or AJAX response, or straight away on pages with a push stream. A background job can call `(toast … :session session)`.

### Tasks and continuations

Common Lisp has no first-class continuations. `define-flow` therefore rewrites the flow body in continuation-passing style with [cl-cont](https://github.com/ocicl/cl-cont), and each `call` suspends the flow until the called component answers. The rewrite has some limits:

- Don't put `call` inside `unwind-protect`, `catch` or `handler-case`.
- If you `setq` a variable after a `call`, every page that resumes from that call shares the change. Prefer fresh bindings when the back button matters.

Outside a flow, `call` shows the component and returns immediately. Use `show` with `:on-answer` there.

### Isolation

After an irreversible step, such as placing an order, the user shouldn't be able to go back into the pages that led to it and do it again. Seaside's `isolate:` prevents this; littoral splits it in two:

```lisp
(let ((isolation (begin-isolation)))
  … the checkout's calls …
  (place-order …)
  (end-isolation isolation))     ; the checkout pages are gone
```

Going back to one of those pages then shows the session as it is now. `littoral.js` also reloads any page Chrome restores from its back/forward cache, because Chrome does this even for `no-store` pages.

### AJAX

To make a component re-renderable in place, mix `updatable` into its class. Then give an element an `:on-click`, `:on-change` or `:on-input` attribute whose value is `(ajax :callback thunk :update component)`. Use `(periodical seconds :update component)` instead to re-render on a timer. `static/littoral.js` is small and has no dependencies; it posts the request and swaps the HTML.

`ajax` takes more options:

- `:value` is a JavaScript expression, evaluated in the browser with `this` bound to the element. The callback receives its result as a string.
- The callback's return value is sent back to the browser as JSON (strings, numbers, lists, keyword plists and hash tables). The `:on-complete` JavaScript snippet receives it as `value`.
- `:confirm "Really?"` asks the user before anything is sent.
- `(execute-script "…")`, called from a callback, runs JavaScript once the updates are in place.

```lisp
(button (:on-click (ajax :value "this.dataset.size"
                         :callback (lambda (size) (price-for size))
                         :on-complete "document.getElementById('price').textContent = value"))
  "Price it")
```

After every update, `littoral.js` fires a `littoral:updated` event on `document`.

### Server push

Components can be re-rendered on open pages by the server, without polling (this is Seaside's Comet, built on server-sent events). A component lists the channels it listens to in its `subscriptions` method. `publish`, called from any thread, re-renders every visible subscriber on every open page:

```lisp
(defvar *news* (make-channel "news"))
(defmethod subscriptions ((self headlines)) (list *news*))   ; headlines is updatable
… (publish *news*) …
```

`(notify component session)` re-renders one component for one session. Use it from a background job, and capture `*session*` in the callback that starts the job. Wrap changes made from another thread in `(with-session (session) …)` so they hold the session's lock. A page opens its event stream only if something on it subscribes. Each open page holds one connection, which with Hunchentoot means one thread. The chat and progress examples use this.

#### Over a WebSocket

Load `littoral/websocket` and register the application with `:websockets t`. Pages that listen for pushes then open one WebSocket instead of an event stream, and their AJAX requests travel over it too, saving a request per click:

```lisp
(asdf:load-system :littoral/websocket)
(register-application "/chat" 'chat :websockets t)
```

Nothing else changes: callbacks, `publish` and `notify` behave as before. Rendering for pushes happens on a small pool of worker threads, never in the thread that called `publish`. If the socket can't open (a proxy that refuses the upgrade, say), the page falls back to server-sent events and plain requests. On Woo, where `littoral/woo` already serves push from the event loops, pages keep server-sent events. The chat example uses this.

A socket opens only from a page of the same site: its `Origin` must match the host, or be in `littoral.websocket:*allowed-origins*`. Sockets count against the event-stream limits. Messages are capped at `*max-message-size*` (1 MB), malformed messages are ignored, and in deployment mode a failing request answers "The request failed." rather than the error.

### Live redefinition

In development mode, recompile a component's `render` method in Emacs (`C-c C-c`) and every open page showing that component redraws itself within a couple of seconds, with its state intact. A watcher notices when methods of `render`, `style`, `script`, `update-root`, `children` or `render-decoration` are redefined. Pages showing an instance of that class then reload, and because each page's URL names its saved state, reloading keeps that state. Pages with a push stream hear about it through the stream; the others poll a cheap endpoint, so live reloading holds no connection (and on Hunchentoot no thread) open.

For changes the watcher can't see, such as a helper function or a stylesheet, call `(reload-pages)`. Set `*live-reload*` to `nil` to turn it off. Deployment-mode pages are never affected.

### Browser code in Lisp (Parenscript)

`littoral/parenscript` lets a component's browser behaviour be written in [Parenscript](https://parenscript.common-lisp.dev/), next to its `render` method:

```lisp
(defpackage #:my-app
  (:use #:cl #:littoral #:littoral.html #:parenscript #:littoral.parenscript)
  (:shadowing-import-from #:littoral #:call)          ; Parenscript exports these too
  (:shadowing-import-from #:littoral.html #:label))

(button (:on-click (in-browser (ps (chain this class-list (toggle "on")))))
  "Toggle")                                          ; runs in the browser only

(let ((shout (client-callback (lambda (text) (string-upcase text)) :update self)))
  (button (:on-click (in-browser (ps (chain littoral (call (lisp shout) "hi")
                                            (then (lambda (answer) (alert answer)))))))
    "Ask the server"))
```

- **Browser-only handlers:** `in-browser` gives `:on-click`, `:on-change`, `:on-input` or `:on-submit` JavaScript to run in the browser, with `this` the element and `event` the event.
- **Calling Lisp from the browser:** `client-callback` registers a Lisp function that browser code calls with `littoral.call(spec, value)`. That returns a promise of the function's result and re-renders the components given as `:update`.
- **Page-level script:** `define-script` gives a component page-level JavaScript.

### Development tools

Applications in `:development` mode, the default, end each page with a toolbar:

- **New Session**
- **Configure**: opens `/config`.
- **Halos**: frames every component, with buttons to inspect it, see its HTML, or see (and edit) its Lisp source.
- **Profile**: per-component render times.
- **Sessions**: a session browser.
- Timings for the last action, snapshot and render.

Each halo has three buttons:

- **inspect** shows the component's slots and lets you edit them.
- **html** shows the HTML the component writes.
- **code** shows its class definition and the `render` method that applies, read from the source files.

When Emacs is connected through SLIME/Swank, the code view also has an **edit** button that opens that definition in Emacs. Set `*source-editor*` to a function of a pathname and a character position to use another editor.

The toolbar reports the last action's callback time, snapshot time and size, and the render time. **Profile** adds a table of every component's inclusive render time, indented by nesting. The session browser shows each session's age, idle time, pages kept, the objects in its newest snapshot, and the snapshot entries held across all its pages.

`/config` lists the registered applications. From there you can add, remove and configure them and browse their sessions. The configurable settings are title, root class, mode, session timeout, pages kept, session limit, cookie sessions, the expiry notice, stylesheets, scripts and basic-auth credentials. Use `(configure-admin :user "u" :password "p")` to put it behind HTTP basic auth.

### Configuration

```lisp
(register-application "/shop" 'shop-root
  :title "Shop"
  :mode :deployment          ; no toolbar or halos
  :session-timeout 1800      ; seconds idle
  :max-continuations 50      ; pages the back button can reach
  :cookie-sessions t         ; session key in a cookie, not the URL
  :stylesheets '("/static/shop.css")
  :credentials '("user" . "password")
  :max-sessions 10000        ; the least recently used are evicted
  :expired-notice 'session-expired-notice   ; say so when a session has gone
  :error-handler (lambda (condition)        ; a component or HTML string
                   (make-instance 'oops :condition condition)))
```

`start` also runs a thread that reaps idle sessions every minute (`start-reaper`, `stop-reaper`, `reap-all-sessions`).

Every response carries `Referrer-Policy: same-origin`, so session keys in URLs never leak to other sites, plus `X-Content-Type-Options: nosniff` and `X-Frame-Options: SAMEORIGIN`. Session cookies get `Secure` when the request came over HTTPS, either directly or through a proxy that sets `X-Forwarded-Proto: https`.

To keep configuration across restarts, start with a file:

```lisp
(start :port 8080 :configuration-file "littoral.conf")
```

Any applications saved in the file are configured first, and every change made in `/config` is written back to it. The file is plain Lisp, one plist per application, and is created with mode 600 because it can hold basic-auth credentials. Classes are stored by name, so an application whose system isn't loaded is skipped with a warning. Error handlers are functions and aren't saved. From code, use `save-configuration`, `load-configuration`, and `configure-application`; the last changes an application's settings without dropping its sessions.

`(make-lack-app)` returns a plain Lack application you can mount into a larger Lack/Clack stack. Lack's `:mount` middleware strips the prefix without setting `:script-name`, so pass the prefix yourself: `(:mount "/apps" (make-lack-app :prefix "/apps"))`. A `:script-name` set by the server or proxy is honoured as well. Set `*debug-errors*` to enter the debugger on errors instead of rendering an error page.

## Translations

Write strings in English and pass them through `translate`. A language's catalogue gives the translations, and a string it lacks shows as written:

```lisp
(define-translations "fr"
  ("Add a contact" "Ajouter un contact")
  ("Remove ~A?" "Supprimer ~A ?")
  ("~D contact" "~D contact" "~D contacts"))        ; one form per plural form

(defmethod render ((self contacts-app))
  (h1 () (translate "Contacts"))                    ; written as text, like a literal
  (p () (translate-plural (length (contacts self)) "~D contact" "~D contacts"))
  (anchor (:callback …) (translate "Add a contact")))

(register-application "/contacts" 'contacts-app :languages '("fr" "de"))
```

Each session has a language. When a session starts, it takes the first of the application's `:language` (by default "en") and `:languages` that the browser's Accept-Language asks for. `set-language` changes it from a callback, and the `language-chooser` component links to each language, named in its own words. The page's `lang` attribute follows the session's language.

- **Plural forms** follow each language's rule: French counts 0 as singular. `define-language` adds a language with its own rule, separators, month names and date format.
- **Numbers and dates**: `(localized-number 1234.5)` gives "1,234.50" in English and "1.234,50" in German. `(localized-date 2026 10 7)` gives "7 octobre 2026" in French.
- **Littoral's own strings** come translated into French, German and Spanish. That covers dialogs, paging, validation messages, signing in and the admin. Description field labels, help text, choice labels and report column titles go through `translate` too, so a catalogue entry for "Name" translates the label everywhere.
- **For translators**: `(missing-translations "fr")` lists the strings shown in French so far that the catalogue lacks. `(load-translations "fr" #p"fr.lisp")` reads entries from a file without evaluating anything.

The contacts example is translated into French and German.

## Keeping data in a database

`littoral/db` stores described objects in SQL through cl-dbi. It's tested with SQLite and written for PostgreSQL too. A table is a description plus a name:

```lisp
(defclass contact (littoral.db:persistent)      ; adds id and version
  ((name :initarg :name :initform nil) (email :initarg :email :initform nil)))
(define-description contact ((name :required t) (email :type :email)))
(littoral.db:define-table contact)

(littoral.db:connect-database :sqlite3 :database-name "app.db")
(littoral.db:create-table 'contact)
(littoral.db:db-save (make-instance 'contact :name "Ada" :email "ada@example.org"))
(littoral.db:db-select 'contact :where "name LIKE ?" :params '("A%") :order-by "name" :limit 20)
```

- **Where data lives:** the data lives in the database, and components hold only what the user is looking at. To edit, read a fresh copy (`db-find`), give it to `make-editor`, and `db-save` what the editor answers.
- **Conflicting saves:** updates check the row's `version`, so saving an object someone else changed meanwhile signals `stale-object` rather than overwriting their change. Catch it and show the user the current version (`db-reload`).
- **References:** a field of `:type :reference :to 'project` holds another stored object. It's chosen from that table in editors and kept as its id.
- **Transactions:** `(register-application … :around-actions (littoral.db:transactional))` runs each request's callbacks, page or AJAX, in one transaction, rolled back if any of them signals.

## A generated admin

`littoral/admin` builds a whole administration interface from descriptions and tables:

```lisp
(littoral.admin:register-admin "/admin" '(project task)
  :database '(:sqlite3 :database-name "app.db")
  :credentials '("admin" . "a long passphrase"))
```

For each class it gives:

- a list with search over the text fields, filters for the choice and yes/no fields, sorting and paging
- a page per record, whose references link to the records they point at, and which lists the records that refer to it
- editing with validation, which notices when someone else changed the record meanwhile
- creation, and deletion after asking

Each request's changes run in one transaction. `:database` gives the admin its own database (through the new `:around-request` hook). Without credentials it only answers requests from the machine it runs on. To try it, load `littoral/admin-demo`, call `(littoral-admin-demo:register)`, and open `/examples/admin`.

## Users and signing in

`littoral/auth` adds users, signing in, roles and password reset, stored through `littoral/db`:

```lisp
(littoral.auth:create-auth-tables)
(littoral.auth:add-user "ada" "ada@example.org" "a long passphrase" :roles '(:admin))

(defclass app (littoral.auth:auth-root component) …)        ; answers /reset links
(defclass reports (littoral.auth:restricted component) …)   ; signed-in users only
(defmethod littoral.auth:required-role ((self reports)) :admin)
```

- **Restricted components.** A `restricted` component shows a sign-in prompt in its place until someone is signed in, or a refusal if they lack its role. In callbacks, `(require-role :admin)` refuses with a 403. `current-user`, `log-in`, `log-out` and `has-role-p` cover the rest.
- **Passwords and lockout.** Passwords are stored as PBKDF2 hashes.
  - After `*lockout-failures*` wrong passwords within `*failure-window-seconds*`, a name is locked for `*lockout-seconds*`.
  - One client address may fail `*failures-per-address*` times across all names, which stops one address trying a common password against many accounts.
  - An unknown name takes as long to refuse as a wrong password, so timing doesn't reveal which names exist.
- **Signing in gives the session a new key**, as does signing out, and closes the session's open streams and sockets. A session URL someone had beforehand, perhaps from a link they sent, is then useless.
- **Password reset.** "Forgot your password?" emails a single-use link that expires after an hour. The answer is the same whether or not the address has an account. Each account gets at most one mail a minute, and each client address `*reset-mails-per-address*` in the window. `*send-mail*` is where you plug in your mailer; by default it prints the mail.
- **`*public-url*`.** Set `littoral.auth:*public-url*` to the site's address (`"https://example.org"`): it is where reset links and OAuth redirects point. In deployment mode it is required, because the Host header is the client's to choose, and a reset link built from a forged one would send its token to someone else's site. In development the request's host is used.
- **OAuth / OpenID Connect.** Load `littoral/oauth` and call `define-oauth-provider` with a provider's URLs and your client id and secret. The sign-in form then offers "Sign in with …". The flow is the authorisation code flow with PKCE, and its state is tied to the browser. Users are found by email, or created; an email the provider marks `"email_verified": false` is refused. Register `/<app>/oauth/<provider>` as the redirect address with the provider.

## Testing your application

`littoral/test` is the fake browser littoral's own test suite uses. It calls your application's Lack handler directly, with no sockets and no real browser, so tests are fast and need nothing installed. It keeps cookies, follows redirects, and reads links, fields and buttons out of the HTML. It posts forms (multipart too), AJAX requests and event streams the way a browser running `littoral.js` would. It works with any test framework; with FiveAM:

```lisp
(defpackage #:my-app/tests (:use #:cl #:fiveam #:littoral #:littoral.test))
(in-package #:my-app/tests)

(test adding-to-the-list
  (with-fresh-applications (("/todo" 'my-app:todo-list :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/todo")
      (fill-in b "new-title" "Buy milk")      ; by the field's DOM id
      (press b "Add")                         ; by the button's label
      (is (has-text-p b "Buy milk"))
      (let ((before (browser-url b)))
        (click b "remove")                    ; by the link's text
        (back-to b before)                    ; the back button
        (is (has-text-p b "Buy milk"))))))
```

`with-fresh-applications` gives a test its own registry of applications. `ajax-request` and `ajax-specs` exercise AJAX; `open-stream`, `sink-text` and `wait-for` exercise server push. The API reference lists everything.

## Accessibility

`make a11y` runs axe-core's WCAG 2 A and AA rules over every example page, and over the states reached by acting on them, in headless Chrome. CI runs it on every push. What littoral does for you:

- Pages carry `lang`; set it per application with `:language`.
- Editors generated from descriptions label every input. Errors are tied to their inputs with `aria-invalid` and `aria-describedby`, and form-level errors use `role="alert"`.
- Widgets use honest semantics: tab and page links mark the current one with `aria-current`, tree toggles have names and `aria-expanded`, reports mark the sorted column with `aria-sort`, and the sortable list's buttons have names.
- An `updatable` component can choose the element it's written in (`updatable-wrapper`), for example an `li` inside a list. With `:aria-live "polite"` there, AJAX and push updates are announced: `littoral.js` updates a live region's contents in place rather than replacing it.
- Every field brush takes `:label`, which becomes `aria-label`, for inputs without a visible label.

## Security

- **CSRF.** Every action names its page's key (`_k`, random, per page), so a forged request from another site can't act without knowing it. Callbacks are never addressed by guessable URLs.
- **Session fixation.** When a session starts, littoral sets an HttpOnly cookie. From then on, a URL session key only works in the browser that holds that cookie, so a shared link opens a fresh session instead of the sender's. Browsers that never return cookies keep working through the URL.
- **Leaking session keys.** Every response sends `Referrer-Policy: same-origin`, so URLs carrying session keys aren't sent to other sites. Responses also carry `X-Content-Type-Options: nosniff` and `X-Frame-Options: SAMEORIGIN`. Cookies get `Secure` over HTTPS.
- **Request size.** Bodies larger than `*max-request-size*` (10 MB), or an application's `:max-request-size`, get 413 before they're read. A chunked body without a length gets 411.
- **Abuse limits.**
  - Each client address may start `*new-sessions-per-minute*` sessions a minute (default 120); beyond that it gets 429.
  - Open event streams are capped in total (`*max-event-streams*`) and per session (`*max-event-streams-per-session*`); beyond that, 503.
  - Behind a proxy, set `*trust-forwarded-for*` so the client address comes from `X-Forwarded-For`.
- **`/config`.** Without credentials, it only answers requests from the machine it runs on. A request forwarded by a proxy doesn't count as local unless you trust the proxy. Give it credentials with `(configure-admin :user … :password …)`, which are checked in constant time.
- **Development mode.** Halos can inspect and change component state, so `start` warns when an application in development mode is served on a public address. Deploy with `:mode :deployment`.
- **New pieces.** Sign-in, reset links and WebSockets have protections of their own, described in their sections.
- **Translations** are FORMAT control strings, so catalogues may not contain the `~/…/` directive, which would call a function named in the text. `define-translations` and `load-translations` refuse it.
- **Escaping.** Text and attribute values are escaped; `raw` is the one way around that. `:href` is written as given, so don't pass it a URL you haven't checked (it could be `javascript:`). An upload's `file-name` comes from the browser; don't use it as a path.

## Deployment and scale

**Performance.** `make load` measures over real HTTP, using Hunchentoot on an Apple-silicon Mac with SBCL 2.6.8:

| Measurement | Result |
|---|---|
| clicks (action, redirect, page), 32 users | ~8,400 /s on the counter, ~7,800 /s in the store; p99 ~13 ms |
| rendering a session's page (`ab`, 32 connections) | ~10,900 requests/s |
| static files (`ab`) | ~15,000 requests/s |
| memory per session, back-button pages included | ~10 KB (counter), ~25 KB (store) |
| open push streams | 600 at once with `:max-threads 1000`; ~1.5 MB each |

`make bench` measures the same cycle in-process, without the network: about 60 µs per click on the counter.

Requests in one session are serialised by its lock, and requests in different sessions run in parallel. The test suite runs concurrent sessions, many requests against one page, and concurrent AJAX.

**Threads.** Hunchentoot gives every connection its own thread, and `start` allows 100 by default. Both idle keep-alive connections and open pages that use server push occupy a thread, and a push page holds its thread, about 1.5 MB of memory, for as long as it stays open. So capacity is counted in connections, not requests:

- If many pages subscribe to channels, raise `:max-threads`.
- Put nginx in front: it holds idle browser connections cheaply and sends littoral fewer of its own.

A closed page frees its thread within about two keep-alive intervals (`*keepalive-seconds*`, 5 s by default).

**Hunchentoot and Woo compared.** An optional system, `littoral/woo`, runs littoral on [Woo](https://github.com/fukamachi/woo), an event-loop server built on libev. Its point is server push: each open push page is served by two libev watchers on an event loop instead of a dedicated thread. `bench/compare.sh hunchentoot` and `bench/compare.sh woo` run the same measurements against each, on an Apple-silicon Mac (8 cores) with SBCL 2.6.8. Woo ran with 4 event-loop workers.

| | Hunchentoot | Woo | Woo vs Hunchentoot |
|---|---|---|---|
| static files, keep-alive (`ab`, 64 connections) | 15,200 req/s | 44,600 req/s | 2.9× |
| page render, keep-alive | 14,200 req/s | 22,800 req/s | 1.6× |
| page render, a new connection per request | 14,300 req/s | 21,000 req/s | 1.5× |
| counter clicks, 64 users from 4 clients | 12,500 /s | 17,900 /s | 1.4× |
| store clicks, same setup | 9,000 /s | 13,800 /s | 1.5× |
| p99 click latency, 64 users | 17.8 ms | 11.5 ms | 35% lower |
| memory per session (counter / store) | 9.6 KB / 25 KB | 8.1 KB / 23 KB | about the same |
| idle server memory | 91 MB | 91 MB | same |
| 600 open push pages: threads | 623 | 7 | |
| 600 open push pages: memory | 1,420 MB | 179 MB | 8× less |
| 600 open push pages: updates delivered | 600 of 600 | 600 of 600 | |
| most push pages tried | 600 (with 1,000 threads) | 6,000, at about 100 MB | |

- **Ordinary pages:** Woo is 1.4–1.6× faster. The gap is bigger on static files, but on littoral pages littoral's own work (callbacks, snapshots, rendering) dominates.
- **Hunchentoot and new connections:** it didn't slow down when every request opened a new connection, so creating threads isn't its bottleneck.
- **Server push:** this is where the servers really differ. On Hunchentoot a push page costs a thread and about 2 MB of memory. On Woo it costs almost nothing, so memory and thread count stay nearly flat as pages are added.
- **Caveats:** the load clients ran on the same machine and competed with the server for CPU, and repeated runs varied by around ±10%. The ratios are more reliable than the absolute numbers.

To run on Woo, install the libev C library (`brew install libev`, or your system's package), then:

```lisp
(asdf:load-system :littoral/woo)
(littoral:start :port 8080 :server :woo :workers 4)
```

CI runs the browser checks on both servers.

**State that the back button sees.** Snapshots copy the slots of the objects `states` names, but share the slots' values. A list changed in place therefore changes in every snapshot. Either replace such values (`(setf (items self) (append …))`) or name the object as `(deep object)` in `states`. A deep entry copies the object's lists, vectors, strings and hash tables. Other instances are still shared, and cycles are kept.

**Several processes.** Sessions live in the memory of the process that made them. To run several processes behind one site, give each one an instance id; it prefixes every session key:

```lisp
(start :port 8081 :instance-id "a")   ; session keys look like a.Xq3…
```

Then route by that prefix. With nginx, for example:

```nginx
map $arg__s $littoral_backend { ~^a\. 127.0.0.1:8081; ~^b\. 127.0.0.1:8082; default 127.0.0.1:8081; }
location / { proxy_pass http://$littoral_backend; proxy_buffering off; }
```

With cookie sessions, route on the cookie instead. Turning `proxy_buffering` off, or sending `X-Accel-Buffering: no` (littoral does this on its event streams), keeps server push working.

**Restarts.** Sessions don't survive a restart. A session is a graph of live objects, the closures its pages' callbacks hold, and cl-cont continuations for flows in progress. None of these can be serialised, which is also true of Seaside outside image-based persistence. Configuration does survive (see `:configuration-file`). Keep data that must last in your own store, not in components. Use `:expired-notice` to tell people when their session is gone.

## License

MIT
