# Littoral

[![CI](https://github.com/lispnik/littoral/actions/workflows/ci.yml/badge.svg)](https://github.com/lispnik/littoral/actions/workflows/ci.yml)

Littoral is a Common Lisp port of Smalltalk's [Seaside](https://seaside.st) web framework. You build an application from stateful components instead of routes and templates:

- Links and buttons carry closures (**callbacks**), not URLs you design.
- One component can **call** another and get its **answer** back.
- The **back button** restores the state each page was rendered from.
- **Tasks** describe a multi-page flow as straight-line code.

It runs on SBCL and serves through Clack (Hunchentoot by default). Dependencies are managed with ocicl.

Version 0.5.1 fixes the endpoints of an application at `/`, which answered 404, and serves OpenAPI descriptions of endpoints. Version 0.5.0 added many widgets (breadcrumbs, editing in place, menus, drawers, a command palette, virtual data grids, filter builders, event calendars and more charts and field kinds), presence, comment threads, notifications and an activity feed over server push, and freed Hunchentoot's threads from open push pages. It gave every HTML element a macro, written through a nickname (`h:div`). Version 0.4.0 documented the API with an example for nearly every export, each run by the tests, extended the tutorial to testing, a database, signing in and translation, fixed about fifteen bugs found while checking the docs, and made clicks 45–70% faster. Version 0.3.0 put the admin and `/config` behind sign-in, added metrics for jobs, mail, sign-ins and the database, switched SQLite to WAL mode, and sent mail through the smtp library, with DKIM and pooled connections. Version 0.2.0 added a database with migrations, users and signing in, an admin, mail, durable jobs and an audit log. See the [changelog](https://github.com/lispnik/littoral/blob/master/CHANGELOG.md).

```lisp
(asdf:load-system :littoral)
(defpackage #:hello (:use #:cl #:littoral) (:local-nicknames (#:h #:littoral.html)))
(in-package #:hello)

(defclass counter (component)
  ((count :initform 0 :accessor count-of)))

(defmethod states ((self counter)) (list self))   ; backtrack COUNT

(defmethod render ((self counter))
  (h:h1 () (h:text (count-of self)))
  (h:anchor (:callback (lambda () (incf (count-of self)))) "++")
  (h:anchor (:callback (lambda () (decf (count-of self)))) "--"))

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
make run           # examples on http://127.0.0.1:8080/examples
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

The project has a root component (a counter, a confirmation dialog and a form), tests that click through it, a Makefile that finds this checkout, a README and a license.

`TEMPLATE=app` starts something bigger:
- users who sign in and keep private notes, with a described model, editors and an admin at `/admin`
- SQLite or PostgreSQL, through `DATABASE_URL`
- `make user` to add people
- an executable configured from the environment, with a systemd unit and a Caddyfile in `deploy/`
- a Dockerfile: `make docker` builds an image from that executable

From a REPL: `(asdf:load-system :littoral/generator)`, then `(littoral.generator:make-project "bookshop" :directory "~/src/bookshop/" :author "…" :license "MIT" :port 8080)`.

Other targets:

```sh
make test-chrome   # the examples in headless Chrome, driven from Lisp
make e2e           # littoral.js in headless Chrome (needs Node 22+)
make a11y          # WCAG checks (axe-core) over every example page
make bench         # request and snapshot timings
make build         # bin/littoral-demo, every example in one executable
make docker        # the same as the image littoral-demo
make docs          # regenerate docs/API.md from the docstrings
make clean-check   # build a fresh clone against nothing but its ocicl.csv
make tour          # the narrated video tour, recorded into tour/ (Chrome, Node, ffmpeg)
make lint          # ocicl lint
```

Documentation is online at **<https://lispnik.github.io/littoral/>**. New to littoral? Start with **[the tutorial](docs/tutorial.md)**, which builds a reading list one idea at a time, then tests it, keeps it in a database, signs readers in and translates it. The full API reference is [docs/API.md](docs/API.md).

`/examples` is a guide to the examples. Three of them are complete small applications:

- **Sushi Store** (`/examples/store`): Seaside's classic demo. A catalog report and a cart share the page. Checkout is a task: review the cart, enter an address (validated), pick a delivery date with a reusable date-picker component, choose how to pay, then confirm. You can cancel at any step and the back button works throughout. Once the order is placed, the checkout pages are isolated, so going back can't place it twice.
- **Wiki** (`/examples/wiki`): pages are shared by every session and kept out of backtracking. Each page has its own URL. There are `[[links]]` to new pages, editing with preview through `call`, history showing what each revision changed, with revert, and search.
- **Chat** (`/examples/chat`): many sessions in one room. Messages are posted with an AJAX form submit, and every open page receives them by server push.

**Tracker** (`make tracker`, then `/tracker`) is a complete issue tracker built to try littoral on something real. It has:

- accounts, with PBKDF2 password hashes
- issues with status, priority, assignee and due date, plus comments
- filters and search
- live updates to everyone's lists through server push
- bookmarkable issue URLs
- data saved to a file

It lives in `apps/tracker`, in its own system, `littoral/tracker`.

The smaller examples include counter, multi-counter, login, todo, guess (a task), topics (bookmarkable URLs), report, ajax, upload and progress (a background job reporting through server push). The configuration application is at `/config`.

## Concepts

| Seaside                         | Littoral                                        |
|---------------------------------|-------------------------------------------------|
| `renderContentOn: html`         | `(defmethod render ((self c)) …)`               |
| `html div class: 'x'; with: […]` | `(h:div (:class "x") …)`                          |
| `html anchor callback: […]; with: 'go'` | `(h:anchor (:callback (lambda () …)) "go")` |
| `html textInput on: #name of: self` | `(h:text-input (:value … :callback (lambda (v) …)))` |
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
| `html fileUpload callback:`     | `(h:file-input (:callback (lambda (file) …)))`    |
| `WABatchedList`, `WATableReport` | `batched-list`, `report` + `column`            |

### HTML

The tag and brush macros are in the `littoral.html` package, which has a macro for every element in the HTML standard, each under the element's own name: `h:time`, `h:map`, `h:search`, `h:var`, `h:data`, `h:option` and the rest. Several of those names are CL's or are common in programs, so don't `:use` the package; give it a local nickname, as above, and write `h:` before each tag:

```lisp
(defpackage #:my-app
  (:use #:cl #:littoral)
  (:local-nicknames (#:h #:littoral.html)))
```

A tag's first argument is its attribute plist, and you can omit it. Literal strings in a tag body are written as escaped text. To write any other value, call `h:text` (escaped) or `h:raw` (unescaped). `(h:tag name …)` writes an element whose name is computed, or one outside HTML, such as SVG's.

The brushes are `h:anchor`, `h:form`, `h:text-input`, `h:password-input`, `h:number-input`, `h:hidden-input`, `h:text-area`, `h:checkbox`, `h:select-list`, `h:radio-group`, `h:file-input`, `h:submit-button`, `h:cancel-button` and `h:button`. Links, fields and the submit and cancel buttons take a `:callback`; an `h:button` submits nothing, so give it an AJAX `:on-click` (see "AJAX"). When a form is submitted, the field callbacks run first, in render order, and the button's action runs after them. The plain `h:a`, `h:input`, `h:select`, `h:textarea` and `h:option` write those elements with no callback, for forms that post elsewhere.

An `h:file-input` needs its form to be `(h:form (:multipart t) …)`. Its callback receives an `h:uploaded-file`, with `h:file-name`, `h:file-content-type` and `h:file-contents` (octets), and is not called when no file was chosen.

An `h:cancel-button` runs its callback and nothing else: what was typed into the form is not applied. `(h:form (:default-action thunk) …)` runs the thunk when the form is submitted without a button.

Rendering must not change state. Calling `call`, `show`, `answer` or `home` while a page renders signals `render-phase-error`; do it in a callback instead.

### The page head

A component's `update-root` method adds to the page's `<head>`. Besides `style`, `script` and `add-stylesheet`, it can add meta tags and links, for link previews and icons:

```lisp
(defmethod update-root ((self shop) root)
  (call-next-method)                                  ; keeps STYLE and SCRIPT
  (add-head-meta root "description" "Fresh sushi, delivered.")
  (add-head-meta root "og:image" "https://shop.example/preview.png")
  (add-head-link root "icon" "/static/icon.svg" :type "image/svg+xml"))
```

Open Graph keys (`og:…`, `article:…`) are written as `property=`, the rest as `name=`. A later `add-head-meta` for the same key replaces the earlier one, so a child component can override its parent. Values are escaped.

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
                                   (h:anchor (:callback (lambda () (open-order row))) "open")))))
```

### Wizards

`make-wizard` shows a description's fields a few at a time:

```lisp
(call self (make-wizard (make-instance 'subscriber) :title "Sign up"
                        :steps '(("Account" name email) ("Plan" plan seats) ("About you" about))))
```

- A row of steps shows where the user is.
- **Next** checks the current step's fields, and **Back** keeps what was typed.
- A review lists every answer, with a link back to the step that asked it.
- **Finish** runs the description's whole-object check. It then writes the values to the object and answers it, or answers them as a plist with `:write nil`.
- **Cancel** answers NIL.

It's an ordinary component, so a flow can `call` it. `/examples/wizard` signs someone up in three steps.

### More widgets

- **`data-grid`** shows a description's objects as a table, with a filter box per column, sortable headings and paging. **Edit** turns a row into the description's own inputs, with its validation; `:on-save` gets the object after the values are written to it. For rows read afresh from a database on each render, give `:row-key #'littoral.db:object-id`.
- **Charts**: `bar-chart`, `line-chart` and `sparkline` write inline SVG, styled by the theme. Each chart is an image with a caption and carries its data as a table for screen readers.
- **`calendar`** shows a month, Monday first, with events (`(date . title)`) and month names in the session's language; `:on-select` gets the day chosen.
- **`kanban`** shows columns of cards. Cards can be dragged between columns, or moved with arrow buttons that work by keyboard and without JavaScript; `:on-move` hears about every move.
- **Markdown**: the `:markdown` field kind and `markdown-html` render Markdown as safe HTML. Raw HTML is escaped, and links go only to http(s), mailto or the site itself, so it's safe to show to whoever wrote it.
- **`breadcrumb-trail`** follows a component's calls: it names the component, then what that has called, and so on down to what shows now. Each link goes back to its level, dismissing what that level called, as `home` does. Names come from `breadcrumb-label`, which defaults to the class name; a description editor's is its title. Render the trail outside the component it follows, since a call replaces that component.
- **`make-in-place-editor`** edits one field of one object where it's shown. **Edit** turns the value into the field's input, with **Save** and **Cancel**, over AJAX. Save checks the text with the description's own validation, writes the value, and calls `:on-save` with the object. `:update` lists other components to redraw after a save, such as a heading that shows the value.
- **Edit conflicts.** The in-place editor and the data grid don't silently overwrite someone else's change. If the value changed after Edit was pressed, Save says "Someone else changed this to … meanwhile" and leaves their value; saving again replaces it. An `:on-save` that signals `edit-conflict` is reported the same way, and nothing is kept; littoral.db's `stale-object`, for a row changed since it was read, is one. Give the in-place editor `:reload #'littoral.db:db-reload` to show the record as it is now.
- **CSV.** `:csv-filename "orders.csv"` on a `report` or `data-grid` adds a Download CSV link. It exports every row, not just the page shown, with the current filters and order. Cells that would start a spreadsheet formula get a leading apostrophe. `report-csv`, `data-grid-csv` and `csv-text` give the text, and `send-download` answers any callback with a file.

```lisp
(defmethod breadcrumb-label ((self order-page)) (format nil "Order ~D" (order-id (page-order self))))
(make-instance 'breadcrumb-trail :of orders)            ; render it above ORDERS
(make-in-place-editor order 'note :on-save #'littoral.db:db-save)
```

- **`disclosure`** and **`accordion`** open and close sections. They're HTML details elements, so they work without JavaScript; with it, what's open is kept on the server, so a reload or the back button shows the page as it was left. An accordion opens one section at a time unless `:multiple t`.
- **`dropdown-menu`** and **`menu-bar`**: a dropdown lists items, each a label with a function to call or a URL; a menu bar is a row of links and dropdowns. They open without JavaScript too. littoral.js closes them on Escape or a click elsewhere, keeps one open at a time, and moves between items with the arrow keys.
- **More field kinds** for descriptions:
  - `:tags`, a list of strings, typed separated by commas, which littoral.js shows as removable chips. `:choices` are offered while typing, `:only-choices t` accepts nothing else, and `:max` caps the count.
  - `:time`, as `(9 30)`, with the browser's time input.
  - `:date-range`, two dates with From and To inputs, which must not end before they start.

  Like the other kinds, they're stored by littoral.db.
- **Uploads**: a file input inside an `.lt-drop` element (as `file-field`s are) takes files dropped on it. A form sending files shows a progress bar while it uploads, then goes on to the next page as before.

```lisp
(make-instance 'dropdown-menu :label "Actions"
               :items (list (cons "Rename" (lambda () (rename self))) :separator (cons "Help" "/help")))
(define-description outing
  ((tags :type :tags :choices '("hiking" "food")) (meet :type :time) (dates :type :date-range)))
```

- **`lazy-panel`** leaves slow parts out of the page. The page is sent with a placeholder, and littoral.js asks for the content over AJAX as soon as it has loaded, or, with `:when-visible t`, once the placeholder is scrolled into view. `:content` is a component or a function making one, called only then. Once loaded, the panel is drawn with the page. Without JavaScript, a link loads it.
- **`diff-view`** shows how two texts differ, line by line: removed lines struck through, added ones marked, and in a changed line the words that changed. It has an inline and a side-by-side layout, and cuts unchanged stretches to `:context` lines (3) around each change. `text-diff` gives the comparison as data.
- **`command-palette`**: Ctrl-K (⌘K on a Mac) or its button opens a box that finds commands as you type, by fuzzy match on their labels and keywords. The arrow keys and Enter choose one, and Escape closes it. Each command is a `palette-command`, a label with a function to call or a URL; `:search` can add more from what's typed, such as records whose names match. The results are links, so it works without JavaScript too.

```lisp
(make-instance 'lazy-panel :content (lambda () (make-instance 'sales-chart :rows (slow-query))))
(make-instance 'diff-view :old (revision-text before) :new (revision-text after))
(make-instance 'command-palette
               :commands (list (palette-command "New invoice" (lambda () (call-editor self)) :group "Invoices")
                               (palette-command "Help" "/help" :keywords '("docs" "manual"))))
```

- **Still more field kinds**, each working without JavaScript:
  - `:stepper`, a number between − and + buttons, and `:range`, a slider with its number beside it. Both go in steps of `:step` within `:min` and `:max`.
  - `:rating`, 1 to `:max` stars (5), which are radio buttons drawn as stars.
  - `:color`, a code like `"#3366cc"`, with the browser's colour picker and a box for the code that can be cleared.
  - `:multiple-choice`, any number of the `:choices` in a list box, held as a list, and `:transfer`, the same as two lists with buttons that move the selected items between them, for roles and permissions. `:min` and `:max` bound how many.
  - `:new-password`, a password with a strength meter that littoral.js keeps up to date as it's typed, from `password-strength` on the server. `:min-strength` (0 to 4) refuses weaker ones. littoral/auth's reset form has the meter too, counting the person's own name and address for little.
- **`with-popover`** writes a button that opens the browser's own popover, which needs no script and closes on Escape or a click elsewhere. **`with-tooltip`** shows a tip while what it wraps has the pointer or the focus; littoral.js makes the tip that element's description, and Escape hides it.
- **`drawer`** slides a panel in from the side over the page. Its button opens it, and its close button, Escape or a click outside closes it. The focus goes in and comes back, and whether it's open is kept on the server.
- **`split-pane`** puts two components side by side, such as a list and the detail of what's chosen, with a divider that can be dragged or moved with the arrow keys. The share is kept on the server, and on a phone the panes stack.
- **`load-more-list`** shows a long list a batch at a time, with a Load more button after it. With `:automatic t` the next batch also arrives as the end of the list scrolls into view (infinite scrolling). `:fetch`, a function of a start and a count, lets a database page through it. The focus moves to the first new item, and a status line says how many are shown.
- **`filter-builder`** holds conditions on a description's fields, such as "Status is Open" and "Due is before 2026-11-01". The comparisons suit each field's kind, and the value is entered with an input of that kind. The conditions must all hold, or any one of them. `filter-matches-p` says whether an object passes.
- **`data-grid`** takes `:conditions t` to put a filter builder above it. With `:virtual 12` it shows 12 rows at a time in a box that scrolls through all of them. Only the rows near those on screen are written, and the rest are fetched as it scrolls, so ten thousand rows stay quick. Without JavaScript it pages instead.
- **More charts**, drawn as SVG on the server like `bar-chart`:
  - `pie-chart`, which can be a donut;
  - `stacked-bar-chart`;
  - `scatter-chart`, where each series has a shape as well as a colour.

  Each has a key and its data as a table for screen readers.
- **`event-calendar`** shows a week or a day of timed events on a grid of hours, with events at the same time side by side. With `:on-move`, events can be dragged to another time or day. Choosing an event also shows buttons that move it a step or a day, which work from the keyboard and without JavaScript.

```lisp
(define-description party
  ((guests :type :stepper :min 1 :max 30) (volume :type :range :step 5) (rating :type :rating)
   (helpers :type :transfer :choices '("Ada" "Grace" "Alan"))
   (password :type :new-password :min-strength 2)))
(with-popover ("Shipping") (h:p () "Free over €50."))
(make-instance 'split-pane :first message-list :second message-view :position 35)
(make-instance 'data-grid :description 'shipment :rows shipments :virtual 12 :conditions t)
(pie-chart '(("Email" . 41) ("Chat" . 23) ("Phone" . 9)) :title "Support requests" :donut t)
```

They're in the widgets example. Its Breadcrumbs tab has the breadcrumbs and the in-place editor, in a pantry to browse; the Forms and Inputs tabs have the field kinds, the Menus tab the menus, accordions and disclosures, the Layout tab a popover, a tooltip, a drawer and a split pane, the Big table tab ten thousand rows in a virtual grid with conditions, the Load more tab every symbol of Common Lisp a batch at a time, the Charts tab every kind of chart, the Calendar tab a week of events to drag about, and the Tools tab a lazy panel and a diff view. Its heading has a command palette over the tabs and the other examples. The report example's chart is a lazy panel, and the wiki's history shows each revision's changes. `/examples/monitoring` charts the server's own metrics live.

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

To make a component re-renderable in place, mix `updatable` into its class. Then give an element an `:on-click`, `:on-change` or `:on-input` attribute whose value is `(ajax :callback thunk :update component)`. To re-render on a timer instead, give an element `:periodical (periodical seconds :update component)`. `static/littoral.js` is small and has no dependencies; it posts the request and swaps the HTML.

`ajax` takes more options:

- `:value` is a JavaScript expression, evaluated in the browser with `this` bound to the element. The callback receives its result as a string.
- The callback's return value is sent back to the browser as JSON (strings, numbers, lists, keyword plists and hash tables). The `:on-complete` JavaScript snippet receives it as `value`.
- `:confirm "Really?"` asks the user before anything is sent.
- `(execute-script "…")`, called from a callback, runs JavaScript once the updates are in place.

```lisp
(h:button (:on-click (ajax :value "this.dataset.size"
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

`(notify component session)` re-renders one component for one session. Use it from a background job, and capture `*session*` in the callback that starts the job. Wrap changes made from another thread in `(with-session (session) …)` so they hold the session's lock. A page opens its event stream only if something on it subscribes. Each open page holds one connection, but not a thread: on Hunchentoot, one thread serves every open stream, and on Woo the event loops do. The chat and progress examples use this.

#### Over a WebSocket

Load `littoral/websocket` and register the application with `:websockets t`. Pages that listen for pushes then open one WebSocket instead of an event stream, and their AJAX requests travel over it too, saving a request per click:

```lisp
(asdf:load-system :littoral/websocket)
(register-application "/chat" 'chat :websockets t)
```

Nothing else changes: callbacks, `publish` and `notify` behave as before. Rendering for pushes happens on a small pool of worker threads, never in the thread that called `publish`. If the socket can't open (a proxy that refuses the upgrade, say), the page falls back to server-sent events and plain requests. On Woo, where `littoral/woo` already serves push from the event loops, pages keep server-sent events. The chat example uses this.

A socket opens only from a page of the same site: its `Origin` must match the host, or be in `littoral.websocket:*allowed-origins*`. Sockets count against the event-stream limits. Messages are capped at `*max-message-size*` (1 MB), malformed messages are ignored, and in deployment mode a failing request answers "The request failed." rather than the error.

#### Who's here

A presence is a place pages can be in, such as one wiki page, and `find-presence` gives the one for a key. A `presence-list` shows who has a page in its presence open: "3 people here", then each person by name with what they're doing, you first, and the guests counted. Showing a presence list puts its page in the presence, and it redraws by server push as people come and go:

```lisp
(make-instance 'presence-list :presence (find-presence "chat room"))

(defmethod presences ((self page-editor)) (list (find-presence (page-key self))))
(defmethod presence-activity ((self page-editor)) "editing")
```

- **Being there.** A page is in the presences its visible components name with `presences` while its event stream (or WebSocket) is open. A component's `presence-activity` says what its person is doing there; the first visible one decides.
- **Names.** `(setf (presence-name) "alice")`, in a callback, names the session's person, and otherwise `*presence-name-function*` does. littoral/auth sets that to the signed-in user's name, and anyone else is a guest.
- **Changes.** Who is where is noted when a page's stream opens and after each AJAX request, so a list follows what the page shows. Its `:presence` can also be a function, called each time, such as the presence of the wiki page open now. `presence-viewers` gives the same information as data.

The chat lists who's in the room by nickname, and each wiki page shows who's reading it and who's editing it.

#### Comment threads

A `live-comment-thread` shows the comments on something, such as a wiki page or an order, and a box for adding one:

```lisp
(make-instance 'live-comment-thread :thread (lambda () (format nil "wiki:~A" (page-name self)))
                                    :markdown t :ask-name t)
```

- **Live.** A comment posted shows at once on every page showing the thread, by server push, and is announced to screen readers there (not to the person who posted it). While someone has written a comment but not posted it, the others see "Ada is writing a comment…", from presence.
- **Who posts.** Comments go under the name `:author` (a function) gives, by default the poster's `presence-name`, or "A guest". `:ask-name t` asks for a name, which becomes their presence name too.
- **Where they're kept.** `*comment-store*` is a `memory-comment-store`, kept until the process ends. `littoral/comments` has `database-comment-store`, a `comments` table that `create-comment-tables` makes; there, pages hear of a comment once its transaction commits. A store of your own implements `store-thread-comments`, `store-add-comment` and `store-delete-comment`.
- **From code.** `add-thread-comment` and `delete-thread-comment` change a thread as a job might, and `thread-comments` reads it. `:can-delete`, a function of a comment, offers Delete on the ones it allows.

The comments use `time-ago`, which writes a time as "3 minutes ago" and has littoral.js keep the words up to date in the page's language while it stays open. The notification bell and the activity feed use it too. Each wiki page has a comment thread.

### Files people upload

`littoral/storage` keeps uploads on disk or in S3, and gives descriptions file fields:

```lisp
(setf littoral.storage:*storage*
      (littoral.storage:make-disk-storage #p"/var/lib/app/files/"))   ; served at /files/
;; or (littoral.storage:make-s3-storage :bucket "app-files" :region "eu-west-1"
;;                                      :access-key … :secret-key …)

(define-description photo
  ((caption :required t)
   (picture :type :image :required t :max-size 8000000)    ; with a thumbnail
   (attachment :type :file)))
```

- **Editors** get a file chooser, with the current file and a Remove box. Their form becomes multipart by itself.
- **Viewers and reports** show an image's thumbnail, linked to the original, and any other file as a download link.
- **In a database**, a stored file is one text column: its key, name, type, size and thumbnail.
- **Types come from the bytes**, not from what the browser said.
  - Only PNG, JPEG, GIF and WebP are ever shown in the page. Anything else is served as an attachment, with `nosniff` and a sandboxing CSP, so an uploaded HTML or SVG file can't run script on your site.
  - `:image` refuses files that aren't images.
- **Thumbnails** are JPEGs `*thumbnail-size*` (240) pixels on their longer side, made with opticl. The image's dimensions are read from its header first, so a small file claiming enormous dimensions (a decompression bomb) is never decoded.
- **Private files.** `:private t` serves files only through signed URLs that expire (after an hour unless `stored-file-url` is given `:expires`). On disk, the signature is an HMAC with `*signing-key*`; on S3 it's a presigned URL. S3 storage is private unless you pass `:private nil`.
- **S3.** The S3 backend speaks the S3 API with AWS Signature V4, so it also works with MinIO, R2, Spaces and others: give `:endpoint`. CI tests it against RustFS, an S3-compatible server.
- **Your own code** can use `store-upload`, `store-octets`, `stored-file-url` and `delete-stored-file`.

The gallery example (`/examples/gallery`, system `littoral/storage-demo`) uploads photos with an optional attachment.

### JSON endpoints

An application can answer JSON beside its pages, for mobile apps, scripts and webhooks. These endpoints belong to the application registered at `/notes`, so they answer `/notes/api/notes/…`. `find-note` and `create-note` stand for your own code, and the second needs `littoral/auth`:

```lisp
(define-endpoint "/notes" :get "/api/notes/:id" (id)
  (let ((note (find-note id)))
    (unless note (endpoint-error 404 "No note ~A." id))
    (list :id (note-id note) :title (note-title note))))

(define-endpoint "/notes" :post "/api/notes" ()
  (let ((user (littoral.auth:require-endpoint-user)))        ; 401 without one
    (values (create-note user (gethash "title" (endpoint-body))) 201)))
```

- **Values become JSON.** Keyword plists and hash tables become objects; lists and vectors become arrays (`#()` for an empty one); `t`, `:false` and `:null` (or `nil`) become true, false and null. A second value sets the status, and a third adds headers.
- **Errors** are answered as JSON too. `endpoint-error` sets the status. An unknown method gets 405. Other errors get 500, with the message only in development mode.
- **Context.** Endpoints run through the application's `:around-request`, so they share its database, but outside any session. `endpoint-body` parses the JSON sent.
- **Who's asking.** `endpoint-user` comes from an `Authorization: Bearer` token made with `create-api-token`, or from the browser's sign-in cookie.
- **Cross-site safety.** A write signed in by cookie must be sent as `application/json`, which a cross-site form can't do.

**OpenAPI.** `serve-openapi` answers `GET /openapi.json` with an OpenAPI 3.1 description of an application's endpoints, which Swagger UI, Postman and client generators read. It's made from what the endpoints say about themselves: a docstring's first sentence is the summary, and options before the body give the tags, responses, request body and query parameters. Path parameters come from the pattern, and every endpoint is described as answering errors as `{"error": message}`. With `littoral/auth` loaded, the description says requests may carry a bearer token.

```lisp
(define-endpoint "/notes" :get "/api/notes" ()
  "The notes, newest first."
  :tags ("notes") :query (("q" "Words to find")) :responses ((200 "The notes") (401 "Not signed in"))
  (find-notes (request-parameter "q")))

(serve-openapi "/notes" :title "Notes" :version "1" :license "MIT")
```

`find-notes` stands for your own code, and `request-parameter` reads the query. `openapi-description` gives the description as a hash table, to change or save.

`/examples/api` calls its own endpoints from the page. The members example answers `GET /examples/members/api/me` and makes API tokens.

### Background jobs

`submit-job` runs work on a pool of threads (`*job-workers*`, 4) and keeps the page up to date while it does. This runs in a callback. `resize-photo` stands for the work, and the `job-view` that `watch-job` returns must be rendered as a child:

```lisp
(let ((job (submit-job (lambda ()
                         (dotimes (i 10)
                           (resize-photo i)
                           (job-progress (/ (1+ i) 10) "Resizing…")))
                       :name "Resize photos" :attempts 3 :backoff 2)))
  (watch-job job (make-instance 'job-view :job job)))
```

- **Retries.** A job that signals is tried again, up to `:attempts` times. The first retry comes after `:backoff` seconds, and each one after waits twice as long as the last. The job's value becomes `job-result`, and `job-error` keeps the last failure.
- **Progress.** `job-progress` records how far the job has got and redraws every component `watch-job` has attached, by server push. A `job-view` shows a progress bar, the status (waiting, working, retrying, done, failed, cancelled) and a Cancel button.
- **Cancelling.** `cancel-job` stops a job at once if it's queued or waiting to retry, and at its next `job-progress` if it's running.
- **Inspecting.** `job-status`, `wait-for-job` and `list-jobs` let you check on jobs.

Jobs live in memory, so a restart forgets them; for work that must not be lost, use durable jobs (below). The progress example runs one job that succeeds and one that fails once and is retried.

### Durable jobs

`littoral/jobs` keeps jobs in the database, in a `job_queue` table, so they survive restarts and any process sharing the database can run them. Here `digest-mail` is a mail of your own (see "Sending mail") and `user` one of `littoral/auth`'s users:

```lisp
(littoral.jobs:define-job (send-digest :attempts 5 :retry-seconds 60) (user-id)
  (littoral.mail:queue-mail (digest-mail (littoral.auth:find-user-by-id user-id))))

(littoral.jobs:define-job (tidy-up :every (littoral.jobs:daily-at 3)) ()   ; every night at three
  (littoral.jobs:purge-durable-jobs))

(littoral.db:connect-database :sqlite3 :database-name "app.db")
(littoral.jobs:create-job-tables)
(littoral.jobs:start-job-runner :threads 2)         ; on the database just connected

(littoral.jobs:enqueue-job (list 'send-digest (littoral.auth:user-id user)) :in 600)
```

- **Enqueueing.** `enqueue-job` writes the job inside the request's transaction, so it exists only if the action commits. A job is a name and its arguments, which must print readably (numbers, strings, symbols, lists). Pass ids, not objects. `:in` and `:at` schedule it later. With `:key`, a second job with the same key isn't queued while the first is still waiting, which collapses repeated requests such as "refresh feed 7".
- **Retries.** A job that signals is tried again after `:retry-seconds` (30), doubling each time, up to `:attempts` (5) tries. Then it's marked failed, with its error and backtrace. `abandon-job` fails it at once, for errors that trying again won't fix.
- **Running.** A runner claims a job by updating its row, so each job runs in one process at a time. The runner holds the job for its `:timeout` (600 seconds), extended by each `note-job-progress`. If the process dies, another runner takes the job over once that time has passed, so jobs should be safe to repeat. With `:transaction t`, the job's database work and its being marked done commit together. Runners take jobs only from their `:queues` (`("default")`), and only jobs their process defines, so a rolling deploy doesn't fail jobs that only the new code knows.
- **Recurring jobs.** `:every` takes seconds or a function from a time to the next one, such as `daily-at`. Runners keep exactly one run scheduled, however many processes there are.
- **Progress.** `(note-job-progress "Row 40 of 100" :fraction 0.4)` records how a job is going. A `durable-job-view` shows a job's progress bar, its status and a Cancel button. Its page hears by server push when a job changes in this process; for jobs run by other processes, give it `:poll`, the seconds between looks.
- **Cancelling.** `cancel-durable-job` cancels a queued job at once. A running job can't be stopped at an arbitrary moment, so it is asked to: its next `note-job-progress` signals `job-cancelled`, and the job ends marked cancelled. A job that never notes its progress runs to the end.
- **Looking after them.** `durable-jobs` (with `:limit` and `:offset`), `find-durable-job`, `durable-job-counts`, `retry-durable-job`, `cancel-durable-job` and `purge-durable-jobs` cover inspecting and housekeeping. The admin shows the queue, with buttons to retry and cancel. In tests, `run-due-jobs` runs what's due without a runner.

`/examples/jobs` (system `littoral/members-demo`) has a report that shows its progress in a `durable-job-view`, a job that fails twice and then succeeds, one that always fails, and a job that sends mail ten seconds later through the mail demo's outbox. Generated apps start a runner and tidy up every night.

### Sending mail

`littoral/mail` writes MIME messages, sends them over SMTP, makes them from templates, and keeps them in an outbox in the database until they've gone. It needs a database connected (see "Keeping data in a database"). `order-email`, `order-number` and `tracking-url` stand for your own code:

```lisp
(setf littoral.mail:*mailer* (littoral.mail:smtp-mailer-from-url "smtp://app:secret@smtp.example.org:587")
      littoral.mail:*mail-from* "Bookshop <hello@example.org>")

(littoral.mail:define-mail order-shipped (order)
  :to (order-email order)
  :subject (translate "Your order ~A is on its way" (order-number order))
  :html ((h:p () "It left the warehouse today.")
         (h:p () (h:anchor (:href (tracking-url order)) "Track it"))))

(littoral.mail:create-mail-tables)
(littoral.mail:start-mail-delivery)   ; a job runner sends the outbox
;; …and in an action:
(littoral.mail:queue-mail (order-shipped order))
```

- **The outbox.**
  - `queue-mail` writes the message to the `mail_outbox` table in the request's transaction, so mail goes only if the action that sent it commits. The page never waits for the mail server.
  - Each message has a durable job, `deliver-mail`, so the job runner (`littoral/jobs`) sends mail along with your other jobs; there's no separate delivery thread. `start-mail-delivery` sets the mailer and starts a runner unless one is running. The jobs appear in the jobs list, and the outbox table keeps each message and how sending it went.
  - The job sends at once, then tries again after `*mail-retry-seconds*` (60), doubling each time, up to `*mail-attempts*` (8). A refusal (an SMTP 5xx) fails at once.
  - Several processes can share the table: each one claims a message before sending it.
  - `outbox-messages`, `retry-mail` and `purge-sent-mail` look after it. `deliver-queued-mail` sends what's due right away, which tests find handy.
- **SMTP.**
  - Sending goes through [smtp](https://github.com/lispnik/smtp), which also writes the MIME.
  - `make-smtp-mailer` takes `:security`: `:starttls` (port 587, the default), `:tls` (465) or `:none` (25, for a relay on the same machine).
  - With STARTTLS, a server that doesn't offer it is refused rather than used in the clear, and the certificate must match the host. Pass `:ca-file` for a private authority.
  - Given `:username` and `:password`, it signs in with PLAIN, or LOGIN if the server offers only that. With `:security :none` it won't send a password unless you pass `:allow-insecure-auth t`. Errors never include the password.
  - `smtp-mailer-from-url` reads `smtp://`, `smtps://` and `smtp+insecure://` URLs.
  - Connections are kept and reused, up to `:pool-size` (2), so a batch of mail doesn't connect for each message. `:pool-size nil` connects each time. A kept connection the server has dropped is replaced, and the message sent again over a new one, when the server hadn't accepted it.
  - `:dkim` signs each message as it's sent: a signer from `smtp/dkim:make-dkim-signer` (RSA or Ed25519), or a list of them. `smtp/dkim:dkim-dns-record` gives the TXT record to publish. Generated apps read `DKIM_KEY_FILE`, `DKIM_DOMAIN` and `DKIM_SELECTOR`, and `myapp dkim-record` prints the record.
  - Failures are the library's conditions, all under `smtp-error`. `smtp-error-code` gives the reply code, and `smtp-error-permanent-p` says whether trying again could help.
- **Messages.**
  - `make-mail` takes To, Cc, Bcc, Reply-To, a text body, an HTML body or both, attachments and extra headers.
  - Everything is UTF-8. Each part gets the transfer encoding it needs, and headers with non-ASCII text are encoded, display names and internationalized domains included.
  - `make-mail` checks every address and header, so a bad address fails when the mail is made, not in the outbox. A line break in a header value is an error, so form input can't add headers.
  - Bcc goes in the SMTP envelope only, never in the headers.
- **Templates.**
  - `define-mail` writes the HTML with Littoral's tags, as in `render`, inside `*mail-layout*`: a plain layout that mail programs show well.
  - Without `:text`, the plain-text part is made from the HTML, with links written out.
- **Other mailers.** The default `*mailer*` prints each mail, which is what you want in development. A `memory-mailer` keeps them, for tests: `message-header`, `message-text` and `message-html` read a sent message back.
- **Password reset.** Set `littoral.auth:*send-mail*` to `(littoral.mail:outbox-sender)` and reset links go through the outbox. Then the reset form takes the same time whether or not the address has an account. The `TEMPLATE=app` projects do this, and send through `$SMTP_URL`.
- **The example.** `/examples/mail` (system `littoral/members-demo`) queues plain and templated mail and lets you switch the pretend mail server off to watch the retries. It previews the HTML. CI sends through a real server, Mailpit, over STARTTLS with certificate checks.

### Live redefinition

In development mode, recompile a component's `render` method in Emacs (`C-c C-c`) and every open page showing that component redraws itself within a couple of seconds, with its state intact. A watcher notices when methods of `render`, `style`, `script`, `update-root`, `children` or `render-decoration` are redefined. Pages showing an instance of that class then reload, and because each page's URL names its saved state, reloading keeps that state. Pages with a push stream hear about it through the stream; the others poll a cheap endpoint, so live reloading holds no connection (and on Hunchentoot no thread) open.

For changes the watcher can't see, such as a helper function or a stylesheet, call `(reload-pages)`. Set `*live-reload*` to `nil` to turn it off. Deployment-mode pages are never affected.

### Browser code in Lisp (Parenscript)

`littoral/parenscript` lets a component's browser behaviour be written in [Parenscript](https://parenscript.common-lisp.dev/), next to its `render` method:

```lisp
(asdf:load-system :littoral/parenscript)
(defpackage #:my-app
  (:use #:cl #:littoral #:parenscript #:littoral.parenscript)
  (:local-nicknames (#:h #:littoral.html))
  (:shadowing-import-from #:littoral #:call))         ; Parenscript exports CALL too
(in-package #:my-app)

(defclass buttons (updatable component) ())

(defmethod render ((self buttons))
  (h:button (:on-click (in-browser (ps (chain this class-list (toggle "on")))))
    "Toggle")                                        ; runs in the browser only
  (let ((shout (client-callback (lambda (text) (string-upcase text)) :update self)))
    (h:button (:on-click (in-browser (ps (chain littoral (call (lisp shout) "hi")
                                              (then (lambda (answer) (alert answer)))))))
      "Ask the server")))

(define-script buttons (self)
  (chain console (log "ready")))
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
- **History**: time travel. It lists every page the session has shown, newest first.
  - Each page shows what the action that made it changed: which slot of which object, before and after.
  - **Open** goes back to a page, with its state restored.
- **Components**: the live component tree, with each component's slots, what it's calling, and an inspector link.
- Timings for the last action, snapshot and render.

Each halo has three buttons:

- **inspect** shows the component's slots and lets you edit them.
- **html** shows the HTML the component writes.
- **code** shows its class definition and the `render` method that applies, read from the source files.

When Emacs is connected through SLIME/Swank, the code view also has an **edit** button that opens that definition in Emacs. Set `*source-editor*` to a function of a pathname and a character position to use another editor.

The toolbar reports the last action's callback time, snapshot time and size, and the render time. **Profile** adds a table of every component's inclusive render time, indented by nesting. The session browser shows each session's age, idle time, pages kept, the objects in its newest snapshot, and the snapshot entries held across all its pages.

`/examples/devtools` is a page to try them on.

**The debugger.** When a callback or a render signals an error in a development-mode application, the page becomes a debugger:
- the condition and its message
- the frames that led to it, the application's own first and open, each with its arguments and local variables, and the file and line where the function is defined. The framework's and SBCL's frames are greyed and folded. Locals need code compiled with `(debug 2)` or more, as SLIME does by default.
- the restarts that were on offer
- the request's parameters
- **Retry**, which sends the same request again: fix the code, recompile it (`C-c C-c`), and retry. **Back to the page** and **New session** leave.

An AJAX or WebSocket request that fails shows the same page in place of the one you were on. Deployment mode shows a plain error page with no detail. Set `*debug-errors*` to `t` to have errors land in the Lisp debugger instead, restarts and all.

`/config` lists the registered applications. From there you can add, remove and configure them and browse their sessions. The configurable settings are title, root class, mode, session timeout, pages kept, session limit, cookie sessions, the expiry notice, stylesheets, scripts and basic-auth credentials. Use `(configure-admin :user "u" :password "p")` to put it behind HTTP basic auth, or, with `littoral/auth` loaded, `(littoral.auth:configure-signed-in-admin :role :admin)` to let users with a role sign in to it.

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

Every response carries `Referrer-Policy: same-origin`, so session keys in URLs never leak to other sites, plus `X-Content-Type-Options: nosniff` and `X-Frame-Options: SAMEORIGIN`. Session cookies get `Secure` when the request came over HTTPS, either directly or through a proxy that sets `X-Forwarded-Proto: https`, and HTTPS responses carry `Strict-Transport-Security: max-age=31536000` (`*hsts-max-age*`, NIL to leave it out), so browsers that have seen the site over HTTPS never try plain HTTP.

To keep configuration across restarts, start with a file:

```lisp
(start :port 8080 :configuration-file "littoral.conf")
```

Any applications saved in the file are configured first, and every change made in `/config` is written back to it. The file is plain Lisp, one plist per application, and is created with mode 600 because it can hold basic-auth credentials. Classes are stored by name, so an application whose system isn't loaded is skipped with a warning. Only the settings `/config` edits, and the languages, are saved: error handlers, the `:around-…` hooks, `:websockets`, `:content-security-policy` and `:max-request-size` aren't. From code, use `save-configuration`, `load-configuration`, and `configure-application`; the last changes an application's settings without dropping its sessions.

`(make-lack-app)` returns a plain Lack application you can mount into a larger Lack/Clack stack. Lack's `:mount` middleware strips the prefix without setting `:script-name`, so pass the prefix yourself: `(:mount "/apps" (make-lack-app :prefix "/apps"))`. A `:script-name` set by the server or proxy is honoured as well. Set `*debug-errors*` to enter the debugger on errors instead of rendering an error page.

## Translations

Write strings in English and pass them through `translate`. A language's catalogue gives the translations, and a string it lacks shows as written:

```lisp
(define-translations "fr"
  ("Add a contact" "Ajouter un contact")
  ("Remove ~A?" "Supprimer ~A ?")
  ("~D contact" "~D contact" "~D contacts"))        ; one form per plural form

(defmethod render ((self contacts-app))
  (h:h1 () (translate "Contacts"))                    ; written as text, like a literal
  (h:p () (translate-plural (length (contacts self)) "~D contact" "~D contacts"))
  (h:anchor (:callback …) (translate "Add a contact")))

(register-application "/contacts" 'contacts-app :languages '("fr" "de"))
```

Each session has a language. When a session starts, it takes the first of the application's `:language` (by default "en") and `:languages` that the browser's Accept-Language asks for. `set-language` changes it from a callback, and the `language-chooser` component links to each language, named in its own words. The page's `lang` attribute follows the session's language.

- **Plural forms** follow each language's rule: French counts 0 as singular. `define-language` adds a language with its own rule, separators, month names and date format.
- **Numbers and dates**: `(localized-number 1234.5)` gives "1,234.50" in English and "1.234,50" in German. `(localized-date 2026 10 7)` gives "7 octobre 2026" in French.
- **Littoral's own strings** come translated into French, German and Spanish. That covers dialogs, paging, validation messages, signing in and the admin. Description field labels, help text, choice labels and report column titles go through `translate` too, so a catalogue entry for "Name" translates the label everywhere.
- **For translators**: `(missing-translations "fr")` lists the strings shown in French so far that the catalogue lacks. `(load-translations "fr" #p"fr.lisp")` reads entries from a file without evaluating anything.

The contacts example is translated into French and German.

## Keeping data in a database

`littoral/db` stores described objects in SQL through cl-dbi. It's tested with SQLite and PostgreSQL. A table is a description plus a name:

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
- **Transactions:** `(register-application … :around-actions (littoral.db:transactional))` runs each request's callbacks, page or AJAX, in one transaction, rolled back if any of them signals. `(littoral.db:after-commit function)` calls a function once the transaction commits, and never if it rolls back: for telling other pages of a change, which they could otherwise read the database too early to see.

### Schema migrations

`create-table` is fine for trying things out. Once a database holds data you care about, keep its schema in numbered SQL files and let `migrate` apply the new ones:

```
migrations/001-contacts.sql
migrations/002-contacts-get-a-phone.sql
migrations/003-search.sqlite.sql          ; 003 for SQLite…
migrations/003-search.postgres.sql        ; …and for PostgreSQL
```

```lisp
(littoral.db:define-migrations :my-app (asdf:system-relative-pathname :my-app "migrations/"))
(littoral.db:migrate :my-app)              ; applies 002 and 003 if they're new; returns what it applied
(littoral.db:migration-status :my-app)     ; each file, and when it was applied
```

- **Files.** The version is the leading number, and gaps are fine. `NNN-name.sqlite.sql` or `NNN-name.postgres.sql` replaces `NNN-name.sql` on that database, for where the two differ (`INTEGER PRIMARY KEY AUTOINCREMENT` and `BIGSERIAL`, say). Statements are separated by semicolons; quotes, comments and PostgreSQL's `$$` bodies are understood. A leading comment `-- littoral: one statement` runs a file whole, as a SQLite trigger needs, and `-- littoral: no transaction` runs it outside a transaction, as `CREATE INDEX CONCURRENTLY` needs.
- **Once, in order, all or nothing.** Each migration runs in a transaction that also records it in `schema_migrations`, under a lock: PostgreSQL's advisory lock, or SQLite's write lock. Several processes starting at once apply each migration exactly once, and one that fails is rolled back whole (SQLite and PostgreSQL both roll back DDL) and stops the rest with a `migration-error` naming the file.
- **Forward only.** Fix a mistake with a new migration. Editing a file that's already applied signals a `migration-changed` warning and changes nothing.
- **In an executable.** The files are read when `define-migrations` runs, so `make build` and Docker images carry them.
- **A database that predates its migrations.** Write the first one with `IF NOT EXISTS`, or mark it as applied with `(baseline-migrations :my-app :through 1)`.
- **Littoral's own tables** are migrations too (`:littoral-users`, `:littoral-auth`, `:littoral-mail`, `:littoral-jobs`, `:littoral-audit` and `:littoral-notifications`, in `migrations/`), applied by `create-auth-tables`, `create-mail-tables`, `create-job-tables`, `create-audit-tables` and `create-notification-tables`. A database made by an earlier version is adopted as it is, and later versions change those tables by adding files.

Generated applications keep their schema this way: `make migrate`, or `bin/app migrate` on a server, and starting the app migrates too.

### Full-text search

Give `define-table` the fields to index, and `db-search` finds objects by their words, the best matches first. For an `article` class with `title` and `body` fields:

```lisp
(littoral.db:define-table article :search (title body))
(littoral.db:db-search 'article "macro writ")      ; words starting so, all of them
(littoral.db:highlight-matches (article-body a) "macro writ")   ; HTML, the words <mark>ed
```

- **SQLite** keeps an FTS5 index in step with the table through triggers. **PostgreSQL** uses a GIN index over `to_tsvector('simple', …)`. `create-table` makes the index and fills it from any rows already there.
- **Combining.** `search-condition` gives a `WHERE` clause and its parameters, to combine with other conditions in `db-select`.
- **The admin's search box** uses the index whenever a table has one.

`/examples/search` (system `littoral/search-demo`) searches the documentation of every documented symbol in `COMMON-LISP`, as you type.

## A generated admin

`littoral/admin` builds a whole administration interface from descriptions and tables. Given classes with tables (`define-table`), here `project` and `issue`:

```lisp
(littoral.admin:register-admin "/admin" '(project issue)
  :database '(:sqlite3 :database-name "app.db")
  :role :admin)                     ; users with the admin role sign in
```

For each class it gives:

- a list with search over the text fields, filters for the choice and yes/no fields, sorting and paging
- a page per record, whose references link to the records they point at, and which lists the records that refer to it
- editing with validation, which notices when someone else changed the record meanwhile
- creation, and deletion after asking

A command palette in its header (Ctrl-K) goes to any table, or straight to a new record in one. Each request's changes run in one transaction. `:database` gives the admin its own database (through the `:around-request` hook).

Beside the tables it has two pages of its own:
- **Audit log**, when the audit log is on (the default), showing who did what.
- **Job queue**, when the database has `littoral/jobs`' tables (`create-job-tables` or `create-mail-tables` ran in this process). It lists the durable jobs by status, newest first, with each job's tries, its error and backtrace, Retry for failed and cancelled jobs, and Cancel for waiting ones. Retries and cancellations go in the audit log. `job-queue-view` is the same page as a component.

Who may use it:
- **`:role`.** Users of `littoral/auth` with that role sign in to it from anywhere; `t` admits anyone signed in. Its database must hold the sign-in tables. A visitor without a sign-in is shown the form, a user without the role is refused, and saving, creating and deleting check the role again, so a page from before a sign-out or a revoked role can't change anything. The audit log names the user.
- **`:credentials`** instead, a `(user . password)` pair, puts it behind HTTP basic auth.
- **Neither:** it only answers requests from the machine it runs on. To try it, load `littoral/admin-demo`, call `(littoral-admin-demo:register)`, and open `/examples/admin`.

## Users and signing in

`littoral/auth` adds users, signing in, roles, permissions and password reset, all kept in the database through `littoral/db` (SQLite or PostgreSQL). The members example (`/examples/members`, system `littoral/members-demo`) shows all of it:
- a members' area and an admins' area
- editors with a permission
- sign-ins that survive restarts, with a list of your sessions
- reset mail delivered to a mailbox on the page
- OAuth sign-in against DemoID, a pretend identity provider served alongside it

`/examples/accounts` is the same page signing in against an existing table.

```lisp
(littoral.db:connect-database :sqlite3 :database-name "app.db")
(littoral.auth:create-auth-tables)
(littoral.auth:add-user "ada" "ada@example.org" "a long passphrase" :roles '(:admin))

(defclass app (littoral.auth:auth-root component) ())        ; answers /reset links
(defclass reports (littoral.auth:restricted component) ())   ; signed-in users only…
(defmethod littoral.auth:required-role ((self reports)) :admin)   ; …with the admin role
```

- **Restricted components.** A `restricted` component shows a sign-in prompt in its place until someone is signed in, or a refusal if they lack its role or permission. In callbacks, `(require-role :admin)` and `(require-permission :edit-posts)` refuse with a 403. `current-user`, `log-in`, `log-out`, `has-role-p` and `has-permission-p` cover the rest.
- **Passwords and lockout.** New passwords are stored as PBKDF2-SHA256 hashes with `*pbkdf2-iterations*` (210,000) iterations.
  - After `*lockout-failures*` wrong passwords within `*failure-window-seconds*`, a name is locked for `*lockout-seconds*`.
  - One client address may fail `*failures-per-address*` times across all names, which stops one address trying a common password against many accounts. This and the reset-mail cap apply only to public addresses. A loopback or private address is usually a proxy shared by every visitor, and limiting it would let one person lock everyone out. Behind a proxy, set `*trust-forwarded-for*` so the limits see real clients.
  - An unknown name takes as long to refuse as a wrong password, so timing doesn't reveal which names exist.
  - Failures and reset mails are counted in the `auth_events` table, so the limits hold across restarts and are shared by every process.
- **Sign-ins are kept in the database** (`auth_sessions`). The browser holds a token in an HttpOnly cookie. A new session of an `auth-root` application finds the sign-in through the cookie and restores it, so sign-ins survive a restart and are shared by several processes behind a load balancer.
  - "Keep me signed in" on the sign-in form makes the sign-in last `*remember-days*` (30), renewed by use. Without it, the sign-in lasts until the browser closes, or `*sign-in-idle-hours*` (12) unused.
  - `user-sessions` lists a user's sign-ins, `revoke-session` ends one, and `log-out-everywhere` ends them all. An ended sign-in signs that browser out within `*auth-session-check-seconds*` (60).
  - Callbacks can set cookies of their own with `(set-cookie name value :max-age seconds)`. Read them with `request-cookie`.
- **Old rows.** Signing in deletes expired sign-ins, and a failed attempt now and then deletes old failures, but expired reset links and API tokens stay. Call `purge-expired-auth-rows` from a nightly job: it deletes failures and reset mails too old to count, expired sign-ins, and expired reset links and API tokens.
- **Second factors.** `security-settings` is a component where users add them:
  - **An authenticator app (TOTP, RFC 6238).** Setup shows a QR code; afterwards, signing in with a password asks for the app's code, and each code works once. Set `$LITTORAL_FACTOR_KEY` (32 bytes, as 64 hex digits or base 64; or `*factor-key*`) and the apps' secrets are kept encrypted with AES-256-GCM, so a copy of the database can't make codes. Secrets kept before the key was set are encrypted when next used, or all at once by `encrypt-factor-secrets`.
  - **Passkeys (WebAuthn).** A passkey signs a user in on its own ("Sign in with a passkey", no name or password), or serves as the second step. Littoral checks the browser's response itself: challenge, origin, relying party, and the ES256 signature with a signature count that must go up. A passkey used alone must also have verified the user (fingerprint, face or PIN).
  - **Recovery codes.** Ten single-use codes, stored hashed, made when an authenticator app is set up or on request.
  - Failed codes count towards the lockout, like failed passwords. The members example has a Security section with all three, and CI signs in with a passkey through Chrome's virtual authenticator.
- **Signing in gives the session a new key** (unless the key is kept in a cookie), as does signing out, and closes the session's open streams and sockets. A session URL someone had beforehand, perhaps from a link they sent, is then useless.
- **New passwords** must have `*min-password-length*` (8) characters and mustn't be a common password or too easy to guess, counting the user's name and address for little (`new-password-problem`, which the reset form uses). With `*check-breached-passwords*`, passwords Have I Been Pwned has seen in breaches are refused too; only five hex digits of the password's SHA-1 are sent.
- **Changing a password signs out everywhere else.** `set-password` ends the user's other sign-ins and voids their API tokens, so a stolen "keep me signed in" cookie or token stops working; the session that changed it stays signed in (`:sign-out-others nil` to keep them).
- **Password reset.** "Forgot your password?" emails a single-use link that expires after an hour. The answer is the same whether or not the address has an account. Each account gets at most one mail a minute, and each client address `*reset-mails-per-address*` in the window. `*send-mail*` is where you plug in your mailer; by default it prints the mail. With `littoral/mail`, `(littoral.mail:outbox-sender)` queues it in the outbox (see "Sending mail").
- **`*public-url*`.** Set `littoral.auth:*public-url*` to the site's address (`"https://example.org"`): it is where reset links and OAuth redirects point. In deployment mode it is required, because the Host header is the client's to choose, and a reset link built from a forged one would send its token to someone else's site. In development the request's host is used.
- **OAuth / OpenID Connect.** Load `littoral/oauth` and call `define-oauth-provider` with a provider's URLs and your client id and secret. The sign-in form then offers "Sign in with …". The flow is the authorisation code flow with PKCE, and its state is tied to the browser. Users are found by email, or created; an email the provider marks `"email_verified": false` is refused. Register `/<app>/oauth/<provider>` as the redirect address with the provider.

### Your own users table

Users come from `*user-store*`. By default that's Littoral's `users` table. To sign in against a table you already have, describe its columns:

```lisp
(defparameter *accounts*
  (littoral.auth:make-sql-user-store
   :table "accounts" :id "account_id" :name "login" :email "email_address"
   :password "pw_hash" :active "enabled"                ; :active is optional
   :roles-query "SELECT r.name FROM roles r JOIN account_roles ar ON ar.role_id = r.id
                 WHERE ar.account_id = ?"               ; or :roles-column "roles"
   :writable t))                                        ; password changes write pw_hash

(littoral.auth:create-auth-tables :users nil)           ; only Littoral's own tables
(register-application "/app" 'app :around-request (littoral.auth:using-user-store *accounts*))
```

- **Hash formats.** `verify-password` accepts hashes made elsewhere: bcrypt (`$2a$`, `$2b$` and `$2y$`, as Rails, Laravel, PHP and Node write them), Django's `pbkdf2_sha256$…` and Werkzeug/Flask's `pbkdf2:sha256:…`, as well as Littoral's own. Anything else: pass `:verify`, a function of the password and the stored hash.
- **Upgrades.** On a writable store, signing in re-hashes a correct password kept in another format, or with fewer iterations, as Littoral's PBKDF2 (`*rehash-on-sign-in*`).
- **Other stores.** Without `:writable` the table is only read. Without `:create`, OAuth signs in only users the table already has.
- **Reset links** work for any store: their tokens live in Littoral's `auth_tokens` table, not on the user's row.
- **Your own classes.** For something other than a SQL table, define methods on the store generic functions (`store-find-user`, `store-find-user-by-id`, …). Any class can be a user once it has methods on `user-id`, `user-name`, `user-email`, `user-active-p`, `user-password-hash` and `user-roles`.

### Roles and permissions

Roles and permissions are kept in two tables, keyed by name, so they work with any store:

```lisp
(littoral.auth:grant-role user :editor)
(littoral.auth:grant-permission :editor :edit-posts)
(littoral.auth:has-permission-p :edit-posts)       ; for the current user
(littoral.auth:require-permission :edit-posts)     ; in a callback: 403 otherwise
(defmethod littoral.auth:required-permission ((self post-editor)) :edit-posts)
```

- A user's roles are their store's own (from a SQL store's column or query) plus those granted here.
- Their permissions are those of all their roles.
- `revoke-role`, `revoke-permission`, `role-permissions` and `user-permissions` round it out.
- `create-auth-tables` moves roles that earlier versions kept in a comma-separated column into the new tables.

### The audit log

`littoral/audit` keeps an `audit_log` table recording who did what, and when. `create-auth-tables` creates it, and from then on these are recorded with no further code:

- **From `littoral/auth`:**
  - Sign-ins, with how (password, passkey, OAuth, or password with a second factor) and whether "keep me signed in" was ticked.
  - Failed sign-ins, with the reason: unknown user, wrong password, inactive, locked out, a wrong code or a refused passkey.
  - Sign-outs, sessions ended elsewhere, password resets asked for, and password changes.
  - Users created, roles and permissions granted or revoked, API tokens, and second factors added or removed.
- **From `littoral/admin`:** what it creates, changes (each field's old and new value, though password values are left out) and deletes.

Applications record their own events:

```lisp
(littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                     :details '(:to "ada@example.org"))
(littoral.audit:audit-events :action "sign-in" :since (- (get-universal-time) 86400))
```

- **Who did it.** The actor is the signed-in user unless `:actor-id` and `:actor-name` are given. In the admin, it's the name in its credentials.
- **Transactions.** An event is written in the current transaction, so an event whose action rolls back disappears with it.
- **Without the table.** Events are recorded only where `create-audit-tables` (or `create-auth-tables`) has run in the process, so an application without the table works as before. `*audit-hook*` sees every event either way, if you also want to send them to a log.
- **Looking through it.** `audit-events` filters by action (`"sign-in"` also matches `"sign-in.failed"`), actor, subject, text and time. The admin gets an "Audit log" page, and `audit-log-view` is a component you can put on an admins-only page of your own. `purge-audit-log` deletes old events, by default those more than a year old (`:older-than` takes seconds). Nothing calls it for you, except the nightly job of generated apps.

An `activity-feed` shows what's happened lately, from the log: who did what to what, and how long ago, newest first, a batch at a time with a button for older events. Events recorded in this process reach open pages as they happen, through `*audit-channel*`, published once their transaction commits. `:action`, `:actor` and `:subject` narrow it. The words come from `*activity-phrases*` (signed in, created, changed and so on, translated), or from `:describe`, a function of an event. Like `audit-log-view`, it shows whatever it's given, so put it where those who see it may know these things.

The members demo shows ada the recent activity and the log, under Admins.

### Notifications

`littoral/notifications` keeps messages for users until they read them, in a `notifications` table. A toast is gone once seen; a notification waits, on whatever page and in whatever browser the user comes back with, across restarts.

```lisp
(littoral.notifications:create-notification-tables)
(littoral.notifications:notify-user user "Your export is ready." :url "/exports/7")
(make-instance 'littoral.notifications:notification-bell)   ; in the page's header
```

- **The bell** shows the signed-in user's unread count and opens onto their latest notifications. Following one marks it read and goes to its `:url`; Mark all as read does the rest. It's a dropdown, so it opens without JavaScript.
- **Arriving live.** Each user has a channel (`notifications-channel`), published when their notifications change in this process, so the bell on their open pages counts a new one at once, even when a job thread made it. Inside a transaction it's published only once the transaction commits (`littoral.db:after-commit`), and a notification whose transaction rolls back never existed. For notifications made by other processes, give the bell `:poll`.
- **Reading them.** `user-notifications` (with `:limit` and `:unread-only`), `unread-notification-count`, `mark-notification-read` (a user can mark only their own) and `mark-all-notifications-read`. `:kind` (`:info`, `:success`, `:warning`) is for styling. `purge-notifications` deletes those read more than 90 days ago, for a nightly job.

In the members demo, the bell is beside the signed-in user's name: ada making bob an editor notifies him, and "Send me a notification in three seconds" sends one from a durable job.

### PostgreSQL

`littoral/db` and `littoral/auth` are tested on SQLite and on PostgreSQL. Connect with `(littoral.db:connect-database :postgres :database-name "app" :host "localhost" :username "app" :password "…")`; the driver is pure Lisp. `make test-postgres LITTORAL_TEST_DATABASE=postgres://user:password@host:5432/db` runs the database tests against one, as CI does.

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

`select-option` chooses from a drop-down and `select-options` several items from a list box. `with-fresh-applications` gives a test its own registry of applications. `ajax-request` and `ajax-specs` exercise AJAX; `open-stream`, `sink-text` and `wait-for` exercise server push. The API reference lists everything.

### In a real browser

The fake browser doesn't run JavaScript. For drag and drop, the back button with Chrome's caches, or passkeys, `littoral/browser-test` drives headless Chrome from Lisp over the DevTools protocol, so the tests stay in FiveAM next to the rest:

```lisp
(defpackage #:my-app/chrome-tests (:use #:cl #:fiveam #:littoral.browser-test))
(in-package #:my-app/chrome-tests)

(test passkeys
  (with-chrome (page :base "http://localhost:8080")   ; a fresh profile each time
    (add-virtual-authenticator page)                  ; a passkey device that always says yes
    (visit page "/examples/members")
    (click-text page "Sign in")
    (type-into page "#sign-in-name" "ada")            ; real key events, by CSS selector
    (type-into page "#sign-in-password" "correct horse battery")
    (click-text page "Sign in" :among "button")
    (click-text page "Add a passkey")
    (wait-until page "document.body.innerText.includes('Passkey 1')")
    (is (search "Passkey 1" (text page)))))
```

- Start your application first, with `start`. This test needs the members example: load `littoral/members-demo` and call `(littoral-members-demo:register)`. Serve it at `localhost` rather than `127.0.0.1` when testing passkeys, since WebAuthn won't accept an IP address as the site.
- `evaluate` runs JavaScript in the page and returns its value; `click-css`, `back`, `page-url` and `screenshot` do what they say. Clicks wait for any page load they start. A missing element signals `browser-error`.
- Chrome is found in the usual places, or set `CHROME` to its path.
- `make test-chrome` runs Littoral's own examples this way (`tests/chrome.lisp`, a model for your own), and CI runs it too.

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
- **Leaking session keys.** Every response sends `Referrer-Policy: same-origin`, so URLs carrying session keys aren't sent to other sites. Responses also carry `X-Content-Type-Options: nosniff` and `X-Frame-Options: SAMEORIGIN`. Cookies get `Secure` over HTTPS, and HTTPS responses `Strict-Transport-Security`.
- **Request size.** Bodies larger than `*max-request-size*` (10 MB), or an application's `:max-request-size`, get 413 before they're read. A chunked body without a length gets 411.
- **Abuse limits.**
  - Each client address may start `*new-sessions-per-minute*` sessions a minute (default 120); beyond that it gets 429.
  - Open event streams are capped in total (`*max-event-streams*`) and per session (`*max-event-streams-per-session*`); beyond that, 503.
  - Behind a proxy, set `*trust-forwarded-for*` so the client address comes from `X-Forwarded-For`.
- **`/config`.** Without credentials, it only answers requests from the machine it runs on. A request forwarded by a proxy doesn't count as local unless you trust the proxy. Give it credentials with `(configure-admin :user … :password …)`, which are checked in constant time, or serve it to signed-in users with a role with `littoral.auth:configure-signed-in-admin`.
- **Whole applications behind sign-in.** With `littoral/auth`, make an application's root a `signed-in-root` and call `(restrict-application path role)`: new visitors get the sign-in form, and only users with the role see the application. Call `check-application-role` in actions that change things. The admin's `:role` is built on this.
- **Development mode.** Halos can inspect and change component state, so `start` warns when an application in development mode is served on a public address. Deploy with `:mode :deployment`.
- **New pieces.** Sign-in, reset links and WebSockets have protections of their own, described in their sections.
- **Translations** are FORMAT control strings, so catalogues may not contain the `~/…/` directive, which would call a function named in the text. `define-translations` and `load-translations` refuse it.
- **Content security policy.** Every page sends a strict policy by default: scripts run only from the site itself, and only if they carry the page's nonce, a random value new for each page.
  - Littoral's browser code, including Parenscript handlers, AJAX `:value` and `:on-complete` code and `execute-script`, is defined by the page's own nonce'd script. Attributes name it by id (`data-lt-on-click-js="@c…"`), so markup injected into a page can't bring code past the policy. Nothing needs `'unsafe-eval'`.
  - The origins of an application's own external scripts and stylesheets are allowed automatically.
  - `:content-security-policy` on `register-application` takes `:strict`, your own policy string (with `{nonce}` for the nonce), or `nil`.
  - `/examples/csp` writes typed HTML into the page unescaped, on purpose, and shows the policy stopping the script in it. CI fails if any other example page breaks its policy.
- **Escaping.** Text and attribute values are escaped; `h:raw` is the one way around that. `:href` is written as given, so don't pass it a URL you haven't checked (it could be `javascript:`). An upload's `file-name` comes from the browser; don't use it as a path.

## Deployment and scale

**[The deployment guide](docs/deployment.md)** covers the whole process:
- building an executable
- a systemd service, or a container (`make docker`)
- nginx or Caddy with TLS, WebSockets and server push
- PostgreSQL
- several processes
- a production checklist

**Performance.** These figures were measured over real HTTP against `bench/load-server.lisp`, using Hunchentoot on an Apple-silicon Mac with SBCL 2.6.8. `make load` measures the clicks, the memory per session, and 100 and 300 push streams (`bench/load.mjs`). The `ab` rows are ApacheBench against the same server, and the push row is `bench/load.mjs streams` with `STREAMS=600`, with `start`'s default of 100 threads:

| Measurement | Result |
|---|---|
| clicks (action, redirect, page), 32 users | ~8,400 /s on the counter, ~7,800 /s in the store; p99 ~13 ms |
| rendering a session's page (`ab`, 32 connections) | ~10,900 requests/s |
| static files (`ab`) | ~15,000 requests/s |
| memory per session, back-button pages included | ~10 KB (counter), ~25 KB (store) |
| open push streams | 600 at once: 600 of 600 updates delivered, 22 threads, 121 MB for the whole server |

`make bench` measures the same cycle in-process, without the network: about 60 µs per click on the counter.

Against Seaside on Pharo 12, measured the same way (see "Littoral and Seaside compared" below):
- **Per core:** littoral renders pages about twice as fast and handles 2.5–2.7× the clicks. This compares Woo on one event loop with a Pharo image, which runs on one thread.
- **Whole machine:** littoral spreads over all the cores, for nearly 4× Seaside's clicks.
- **Latency and memory:** with 64 users, littoral's p99 latency is a quarter of Seaside's, and a session takes less than half the memory.

Requests in one session are serialised by its lock, and requests in different sessions run in parallel. The test suite runs concurrent sessions, many requests against one page, and concurrent AJAX.

**Threads.** Hunchentoot gives every connection its own thread while it makes requests, and `start` allows 100 by default (`:max-threads`). Idle keep-alive connections occupy a thread too. Open pages with server push don't: once a page's event stream has begun, its connection leaves Hunchentoot's thread for littoral's push hub. One thread watches every stream, and up to `*push-render-threads*` (4) more render and write their updates. On Linux, 10,000 open push pages took the server from 4 threads to 5, and their sessions and streams added 40 MB to its heap (76 MB to 116 MB); every page received its update. That was measured before the render threads were added, which add up to four more threads while pages are open.

- Put nginx in front: it holds idle browser connections cheaply and sends littoral fewer of its own.
- On macOS, SBCL waits on sockets with `select(2)`, which can't watch file descriptors past 1,024. So a Hunchentoot server there holds about 1,000 connections at most, with or without push. Linux has no such limit.
- The hub renders pushed updates on `*push-render-threads*` threads (4), so a broadcast to many pages is rendered in parallel, each page by one thread at a time. A page whose browser has stopped reading, with its connection's buffer full, is dropped rather than waited for, and its EventSource reconnects later.

A closed page's stream ends within about one keep-alive interval (`*keepalive-seconds*`, 5 s by default).

**Hunchentoot and Woo compared.** An optional system, `littoral/woo`, runs littoral on [Woo](https://github.com/fukamachi/woo), an event-loop server built on libev. It is faster at ordinary requests, and it serves server push from its event loops: each open push page is two libev watchers. `bench/compare.sh hunchentoot` and `bench/compare.sh woo` run the same measurements against each, on an Apple-silicon Mac (8 cores) with SBCL 2.6.8. Woo ran with 4 event-loop workers.

| | Hunchentoot | Woo | Woo vs Hunchentoot |
|---|---|---|---|
| static files, keep-alive (`ab`, 64 connections) | 10,400 req/s | 29,000 req/s | 2.8× |
| page render, keep-alive | 8,000 req/s | 18,000 req/s | 2.2× |
| page render, a new connection per request | 9,700 req/s | 19,300 req/s | 2.0× |
| counter clicks, 64 users from 4 clients | 6,700 /s | 10,200 /s | 1.5× |
| store clicks, same setup | 5,200 /s | 6,500 /s | 1.2× |
| p99 click latency, 64 users | 27 ms | 22 ms | 20% lower |
| one user clicking | 3,070 /s | 3,940 /s | 1.3× |
| memory per session (counter / store) | 10 KB / 25 KB | 8.5 KB / 24 KB | about the same |
| idle server memory | 90 MB | 87 MB | about the same |
| 600 open push pages: threads | 22 | 7 | |
| 600 open push pages: memory | 121 MB | 99 MB | about the same |
| 600 open push pages: updates delivered | 600 of 600 | 600 of 600 | |
| most push pages tried | about 1,000 on macOS (the `select(2)` limit); 10,000 on Linux | 6,000 on macOS, at about 100 MB | |

- **Ordinary pages:** Woo is 1.2–2.2× faster: most on rendering and static files, least on clicks, where littoral's own work (callbacks, snapshots, rendering) dominates.
- **Hunchentoot and new connections:** it didn't slow down when every request opened a new connection, so creating threads isn't its bottleneck.
- **Server push:** on both, an open push page costs almost nothing, so memory and thread count stay nearly flat as pages are added. Hunchentoot's push rows were measured after the push hub was added, with `bench/load.mjs streams` alone; before it, every push page held a thread and about 2 MB (621 threads and 1,355 MB for 600 pages). The other rows predate 0.4.0's faster clicks.
- **Caveats:** the load clients ran on the same machine and competed with the server for CPU, and other applications kept one or two cores busy. The figures are medians of six runs over two days, and runs varied by up to ±30%. The ratios are more reliable than the absolute numbers.

To run on Woo, install the libev C library (`brew install libev`, or your system's package), then:

```lisp
(asdf:load-system :littoral/woo)
(littoral:start :port 8080 :server :woo :workers 4)
```

CI runs the browser checks on both servers.

**Littoral and Seaside compared.** `bench/compare.sh seaside` runs the same measurements against [Seaside](https://github.com/SeasideSt/Seaside) on Pharo 12, built by `bench/seaside/setup.sh`:
- **Counter:** Seaside's own `WACounter`.
- **Store:** `LtStore`, the same menu, report, batch links and cart as littoral's store. Its page is 2.8 KB, against littoral's 3.5 KB.
- **Static files:** `littoral.js`, served from a `WAFileLibrary`.

Seaside runs with Zinc's limits raised: 1,000 connections, a backlog of 128, and Pharo's socket semaphore table at its maximum. Without that, it refuses connections at 64 concurrent users.

A Pharo image runs Smalltalk on one OS thread, so the first column of littoral is Woo with a single event loop, which is the per-core comparison. The setup was an Apple M3 with 8 cores, SBCL 2.6.8, Seaside master (0c52094) on Pharo 12.0, and the median of six runs over two days:

| | Seaside | littoral, Woo, 1 loop | littoral, Hunchentoot | littoral, Woo, 4 loops |
|---|---|---|---|---|
| static file, keep-alive (`ab`, 64 connections) | 540 req/s | 11,800 req/s | 10,400 req/s | 29,000 req/s |
| page render, keep-alive | 7,600 req/s | 14,200 req/s | 8,000 req/s | 18,000 req/s |
| page render, a new connection per request | 7,000 req/s | 14,000 req/s | 9,700 req/s | 19,300 req/s |
| counter clicks, 64 users from 4 clients | 2,770 /s | 7,000 /s | 6,700 /s | 10,200 /s |
| store clicks, same setup | 1,750 /s | 4,760 /s | 5,200 /s | 6,500 /s |
| p99 click latency, 64 users | 83 ms | 20 ms | 27 ms | 22 ms |
| one user clicking (rate, median latency) | 2,330 /s, 0.4 ms | 4,120 /s, 0.2 ms | 3,070 /s, 0.3 ms | 3,940 /s, 0.2 ms |
| memory per session (counter / store) | 20 KB / 55 KB | 8.5 KB / 24 KB | 10 KB / 25 KB | 8.5 KB / 24 KB |
| idle server memory | 92 MB | 72 MB | 90 MB | 87 MB |

- **Per core:** on one thread each, littoral renders pages about twice as fast and handles 2.5–2.7× the clicks. Seaside does about 2,770 counter clicks a second whatever the number of users, so 64 users wait longer: its p99 latency is four times littoral's.
- **Whole machine:** one image can't use more cores, while littoral on Woo spreads over them, which gives nearly 4× Seaside's clicks. Seaside sites scale by running several images behind a load balancer with sticky sessions, as littoral can (see "Several processes" below).
- **Memory:** a Seaside session takes more than twice the memory. Both keep 20 pages for the back button.
- **Single requests:** both answer in well under a millisecond. Seaside is closest on keep-alive page renders against Hunchentoot.
- **Static files:** Seaside's file library spends about 2 ms on each request, even over one connection. Seaside deployments usually serve files from the web server in front, so this row says little about Seaside pages.
- **Not compared:** server push. Seaside's WebSocket and Comet packages work differently from littoral's event streams.
- **Caveats:** other applications kept one or two cores busy during these runs. The littoral runs varied by up to ±30%, Seaside's by under 10%: one thread is less disturbed by others. Seaside's ratios to littoral are therefore conservative, if anything.

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

**Health, metrics and logs.**
- `/healthz` answers `{"status":"ok",…}` for load balancers, with the uptime and each check's result. It answers 503 when a check you add with `add-health-check` fails, for example a database ping.
- `(serve-metrics)` serves Prometheus metrics at `/metrics`, to this machine only by default: requests by application, kind and status, a latency histogram, sessions, push streams, jobs, heap and threads.
  - Also GC time, bytes allocated, the versions running (`littoral_build_info`), and sessions started, ended (expired or evicted) and refused.
  - With `littoral/jobs` and `littoral/mail`, each database whose tables were made in the process: durable jobs by queue and status, how long the oldest due job has waited, the outbox by status, and how long the oldest unsent mail has waited. Also job runs by job and result, with their durations; mail sends by result (sent, transient, permanent); SMTP send times; and the SMTP connection pools.
  - With `littoral/auth`: sign-ins by method, failures by reason, reset mails, and sign-ins still standing.
  - With `littoral/db`: lock timeouts, conflicting saves by table, transaction times, SQLite file sizes (database and write-ahead log), and migrations not yet applied.
  - Your own: `define-metric` makes a counter or histogram, which `count-metric`, `observe-metric` and `timing-metric` feed. `add-metrics-source` writes metrics computed at scrape time, such as a query.
- `(log-requests-to stream)` writes a JSON (or `:format :text`) line per request. Lines carry the path but never the query string, so session keys stay out of logs.

**Restarts.** Sessions don't survive a restart. A session is a graph of live objects, the closures its pages' callbacks hold, and cl-cont continuations for flows in progress. None of these can be serialised, which is also true of Seaside outside image-based persistence. Configuration does survive (see `:configuration-file`). Keep data that must last in your own store, not in components. Use `:expired-notice` to tell people when their session is gone.

What a restart costs is small. A page whose session is gone starts a new one when it's next loaded. Its AJAX requests, event stream, WebSocket and live-redefinition checks are told to reload the page rather than being given a new session they can't use. Sign-ins are kept in the database, so an `auth-root` application signs the user straight back in.

## License

MIT
