# Littoral

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
```

Other targets:

```sh
make e2e           # littoral.js in headless Chrome (needs Node 22+)
make bench         # request and snapshot timings
make docs          # regenerate docs/API.md from the docstrings
make clean-check   # build a fresh clone against nothing but its ocicl.csv
make lint          # ocicl lint
```

The full API reference is [docs/API.md](docs/API.md).

`/examples` is a guide to the examples. Three of them are complete small applications:

- **Sushi Store** (`/examples/store`): Seaside's classic demo. A catalog report and a cart share the page. Checkout is a task: review the cart, enter an address (validated), pick a delivery date with a reusable date-picker component, choose how to pay, then confirm. You can cancel at any step and the back button works throughout. Once the order is placed, the checkout pages are isolated, so going back can't place it twice.
- **Wiki** (`/examples/wiki`): pages are shared by every session and kept out of backtracking. Each page has its own URL. There are `[[links]]` to new pages, editing with preview through `call`, history with revert, and search.
- **Chat** (`/examples/chat`): many sessions in one room. Messages are posted with an AJAX form submit, and every open page receives them by server push.

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

## Deployment and scale

**Performance.** `make bench` measures the request cycle in-process. On an Apple-silicon Mac with SBCL 2.6.8:

| Operation | Time |
|---|---|
| a click on the counter (action and render) | ~60 µs |
| a click in the sushi store | ~180 µs |
| a snapshot of 100 objects | ~10 µs |
| 16 threads, separate sessions | ~58,000 clicks/s |

Requests in one session are serialised by its lock, and requests in different sessions run in parallel. The test suite runs concurrent sessions, many requests against one page, and concurrent AJAX.

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
