# Littoral API reference

Generated from the docstrings by `make docs`; do not edit by hand.

## Package `littoral`

Littoral: a Seaside-style component web framework for Common Lisp.

### Context

#### `*request*` — variable

The lack/request:request being handled.

#### `*session*` — variable

The `session` owning the current request.

#### `*application*` — variable

The `application` the current request was dispatched to.

#### `*render-context*` — variable

The `render-context` active while rendering: it knows where callbacks go
and how to build URLs back into the session.

#### `request-parameter` `name &optional (request *request*)` — function

The value of the query or body parameter `name` in `request`, or `nil`.

#### `request-parameter-p` `name &optional (request *request*)` — function

True when `request` has the parameter `name`, even with no value (?flag).

#### `request-path` `&optional (request *request*)` — function

The path of `request` below the mount point.

#### `redirect-to` `url` — function

From a callback: when the request's callbacks are done, send the browser
to `url` (another site, say) instead of the next page.

#### `forbidden` — condition

Signal it to refuse a request: the user sees a 403 page.

#### `forbidden-message` `condition` — generic function

The explanation a `forbidden` condition shows the user.

#### `render-phase-error` — condition

Signalled by `call`, `show`, `answer` and `home` during rendering.

### Components

#### `component` — class

A stateful piece of user interface.  Subclass it and
specialise `render`.

#### `component-id` `object` — generic function

Reads the id of a component.  Unique and stable: the `dom` id `ajax` updates target.

#### `render` `component` — generic function

Write `component`'s `html` to *CANVAS*.  Embedded components
are written with `render-component`, never by calling `render` on them.

#### `render-component` `component` — generic function

Render `component` where it is embedded: through its
decorations, inside a halo when halos are on.

#### `children` `component` — generic function

The components `component` renders.  Halos, update-root,
backtracking and `ajax` lookups find components through this.

#### `states` `component` — generic function

Objects whose slots are snapshotted after every action
and restored when the user goes back to an earlier page.  Return `component`
itself to make all its slots backtrack.

#### `update-root` `component root` — generic function

Contribute `component`'s title, stylesheets and scripts to
the `html-root` of the page.  Call `call-next-method` to keep `style` and `script`.

#### `style` `component` — generic function

`css` text this component adds to the page head, or `nil`.

#### `script` `component` — generic function

JavaScript text this component adds to the page, or `nil`.

#### `initial-request` `component request` — generic function

Called on the root component when its session starts,
with the request that started it.  A bookmarked `url` is read back here with
`request-extra-path` and `request-parameter`.

#### `updatable-wrapper` `component` — generic function

The tag and extra attributes of the element an `updatable`
component is written inside: "div" and none by default.  A row of a list
returns "li"; a region whose updates should be announced adds
:aria-live "polite".

#### `update-url` `component url` — generic function

Add to `url`, a `page-url`, whatever would let a bookmark of
this page come back to it.  Called on every visible component, parents
first; read it back in `initial-request` with `request-extra-path` and
`request-parameter`.

#### `page-url` — class

What `update-url` methods add to the `url` of a page.

#### `page-url` `session continuation` — function

The `url` of `continuation`: the application's path, what `update-url` methods
add, then the session and page keys.

#### `add-to-path` `url &rest segments` — function

Append `segments` (strings, or anything `princ` prints) to `url`'s path.

#### `add-parameter` `url key &optional value` — function

Add the query parameter `key` (with `value`, unless `nil`) to `url`.

#### `url-path` `object` — generic function

Reads the path of a page-url.  Segments after the application's path, in order.

#### `url-parameters` `object` — generic function

Reads the parameters of a page-url.  Alist of query parameters, in order.

#### `request-extra-path` `&optional (app *application*) (request *request*)` — function

The decoded path segments of `request` after `app`'s path.

#### `call` `self other` — function

Show `other` in place of `self` and return what it answers.

Inside a flow (see `define-flow`) this reads as a blocking call: the rest of
the flow is captured with cl-cont and resumed by `answer`.  Elsewhere, such
as a callback, it shows `other` and returns at once, discarding the answer;
use `show` with :`on-answer` there to act on it.

#### `answer` `self &optional value` — function

Return control, with `value`, to the component that called `self`.
Validation decorations on `self` may refuse the answer.

#### `show` `self other &key on-answer` — function

Show `other` in place of `self` until `other` answers, then call `on-answer`
with the answer.  Returns `other` at once: the non-blocking form of `call`.

#### `home` `self` — function

Dismiss whatever `self` has called, without answering.

#### `visible-children` `component` — function

The components `component` shows now: its delegate when it has called
another, otherwise its `children`; and any its decorations show.

#### `active-component` `component` — function

The component actually showing in `component`'s place.

#### `html-root` — class

The document head a page collects from `update-root`: title, meta
tags, links, stylesheets and scripts.

#### `root-title` `object` — generic function

Reads the title of a html-root.

#### `add-stylesheet` `root url` — function

Link the stylesheet at `url` from the page.

#### `add-script` `root url` — function

Load the script at `url` in the page.

#### `add-style` `root css` — function

Add the `css` text `css` to the page head.

#### `add-head-meta` `root key content` — function

Add a meta tag `key` with `content` to the page head: description, theme-color,
og:title, twitter:card and the like.  Open Graph keys (og:..., article:...)
are written as property=, the rest as name=.  A later call with the same
`key` replaces the earlier one, so a child component can override its parent.

#### `add-head-link` `root rel href &rest attributes` — function

Add a link element (rel `rel`, href `href`) to the page head, with `attributes`, a plist of
keywords and strings such as :type "image/svg+xml" or :sizes "180x180".
The same `rel` and `href` are added once.  For stylesheets use `add-stylesheet`.

### Decorations

#### `decoration` — class

Wraps a component's rendering or intercepts its answers.
Specialise `render-decoration` and call `render-inner` for what it wraps.

#### `add-decoration` `component decoration` — function

Add `decoration` to `component`, outermost among those of its kind.
Globals come first, then any delegation, then locals.

#### `remove-decoration` `component decoration` — function

Take `decoration` off `component`.

#### `decorations` `object` — generic function

Reads the decorations of a component.  Outermost first.  Replaced, never mutated, so
backtracking can snapshot it as a value.

#### `delegation` — class

Shows the delegate in place of the decorated component.

#### `answer-handler` — class

Remembers who called a component and what to do with
its answer.

#### `message-decoration` — class

A heading above the component.

#### `form-decoration` — class

Puts the component in a form with a row of buttons, the
way Seaside's WAFormDecoration does.

#### `validation-decoration` — class

Refuses answers the validator rejects and shows why.

#### `validate-with` `component validator` — function

Answers from `component` must first pass `validator`, a function of the
answer returning `nil` to accept or an error message to refuse.

#### `render-inner` — function

Render whatever the current decoration wraps.

#### `render-decoration` `decoration component` — generic function

Render `decoration` around `component`; `render-inner` renders
the rest of the chain.

#### `decoration-kind` `decoration` — generic function

:`global` decorations sit outside a delegation and so stay
visible while another component is shown in their owner's place; :`local`
ones sit inside it.

#### `decoration-children` `decoration` — generic function

Components `decoration` shows besides what it wraps (a
modal dialog, say).

#### `updatable` — class

Mixin for components `ajax` can re-render: each is written
inside an element carrying its `component-id`.

#### `show-modal` `other &key on-answer (closable t) title` — function

Show `other` in a dialog over the whole page until it answers, then call
`on-answer` with the answer.  `closable` adds a close button (and Esc), which
answers `nil`; `title` names the dialog for screen readers.

#### `call-modal` `&rest args` — function

Show `other` in a dialog over the page and return what it answers; a
blocking call inside a flow, like `call`.  `title` names the dialog.

#### `modal-decoration` — class

Shows a component over the page, which stays visible
behind it but cannot be used until the dialog answers.

#### `toast` `message &key (kind :info) (session *session*)` — function

Show `message` briefly at the corner of `session`'s page: on its next page or
`ajax` response, or at once on pages with a push stream.  `kind` is :`info`,
:`success` or :`error`.

### Dialogs

#### `message-dialog` — class

Shows a message; answers T.

#### `confirm-dialog` — class

Asks a yes/no question; answers T or `nil`.

#### `input-dialog` — class

Asks for a line of text; answers the string.

#### `choice-dialog` — class

Asks for one of `items`; answers it, or `nil` on Cancel.

#### `login-dialog` — class

Asks for a username and password; answers them as a
cons, or `nil` on Cancel.

#### `inform` `self message` — function

Show `message` in place of `self` until it is acknowledged.  A `call`: blocking inside a flow.

#### `confirm` `self question` — function

Ask `question` in place of `self`; T for yes, `nil` for no.  A `call`: blocking inside a flow.

#### `request-input` `self prompt &optional (default "")` — function

Ask for a line of text with `prompt`, starting from `default`; the string typed.  A `call`.

#### `choose-from` `self items &optional prompt` — function

Ask for one of `items`, with `prompt`; the item chosen, or `nil`.  A `call`.

### Widgets

#### `batched-list` — class

Pages through `items`.  Render the current `batch` yourself
and `render-component` the batched list for its page links, as with Seaside's
WABatchedList.

#### `batch` `list` — function

The items on `list`'s current page.

#### `batch-items` `list` — function

All of `list`'s items.

#### `batch-size` `object` — generic function

Reads the batch-size of a batched-list.

#### `batch-page` `object` — generic function

Reads the page of a batched-list.  Zero-based.

#### `go-to-page` `list page` — function

Show page `page` (zero-based) of `list`, kept in range.

#### `report` — class

A table of `rows` with sortable `columns`, like Seaside's
WATableReport.  Give :`batch-size` to page it.

#### `column` `title value &rest initargs &key render sort-key sort-predicate sortable class` — function

A `report` column titled `title` showing (`funcall` `value` `row`).

#### `report-rows` `object` — generic function

Reads the rows of a report.  A list, or a thunk returning one on every render.

#### `report-columns` `object` — generic function

Reads the columns of a report.

#### `sort-by` `report column` — function

Sort `report` by `column`, reversing the order when it already is.

#### `tab-panel` — class

Shows one of several components, chosen by a row of tabs,
like Seaside's WATabPanel.

#### `navigation` — class

A `tab-panel` drawn as a menu beside its content, like
Seaside's WASimpleNavigation.

#### `panel-tabs` `object` — generic function

Reads the tabs of a tab-panel.  Alist of (`label` . `component`).

#### `panel-selected` `object` — generic function

Reads the selected of a tab-panel.  Index of the tab shown.

#### `selected-tab` `panel` — function

The component `panel` shows, or `nil` when it has no tabs.

#### `select-tab` `panel label` — function

Show the tab of `panel` labelled `label`.

#### `tree` — class

Items in a hierarchy, each expandable, like Seaside's WATree.

#### `tree-expanded` `object` — generic function

Reads the expanded of a tree.  The items whose children show.  Replaced, never changed in place.

#### `tree-selected` `object` — generic function

Reads the selected of a tree.

#### `toggle-item` `tree item` — function

Expand `item` in `tree`, or collapse it.

#### `expand-all` `tree` — function

Expand every item of `tree` that has children.

#### `autocomplete` — class

A text field suggesting completions as you type.

#### `autocomplete-value` `object` — generic function

Reads the value of an autocomplete.

#### `sortable-list` — class

A list the user can reorder by dragging, or with the
up and down buttons beside each item (which work without JavaScript).

#### `sortable-items` `object` — generic function

Reads the items of a sortable-list.

#### `move-item` `list from to` — function

Move the item at `from` to position `to` in `list`.

### Descriptions

#### `define-description` `name fields &key validate` — macro

Describe the objects of class `name`: each of `fields` is (`property` &rest
options), options being :`type` (see *FIELD-KINDS*), :`label`, :`required`,
:`default`, :`help`, :`validate`, :`read-only`, :`in-report`, :`accessor` or :`reader` and
:`writer`, and those of the field's kind (:`max-length`, :`pattern`, :`min`, :`max`,
:`choices`, :`labels`).  `validate` checks the values together.

#### `description` — class

The fields of a kind of object, in order.

#### `find-description` `designator` — function

The description `designator` names, or that of `designator`'s class.

#### `description-fields` `object` — generic function

Reads the fields of a description.

#### `field` — class

One described property of an object.  Subclasses say how
its values are entered, parsed, shown and checked.

#### `field-name` `object` — generic function

Reads the name of a field.

#### `field-label` `object` — generic function

Reads the label of a field.

#### `field-value` `field object` — function

`field`'s value in `object`.

#### `find-field` `description name` — function

The field of `description` for the property `name`.

#### `*field-kinds*` — variable

Keyword → field class, for :`type` in `define-description`.  Push your own.

#### `string-field` — class

A line of text.

#### `text-field` — class

Several lines of text.

#### `password-field` — class

Text that is never shown.

#### `email-field` — class

An email address.

#### `url-field` — class

An http or https `url`.

#### `integer-field` — class

A whole number, optionally between `min` and `max`.

#### `boolean-field` — class

Yes or no.  Never required: unchecked is an answer.

#### `choice-field` — class

One of `choices`, shown through `labels`.

#### `date-field` — class

A calendar date, held as (`year` `month` `day`).

#### `field-choices` `field` — function

`field`'s choices now.

#### `field-hidden-p` `object` — generic function

Reads the hidden of a field.  Stored and validated, but never shown: not in editors, viewers or reports.

#### `parse-field` `field string` — generic function

The value `string`, as typed, stands for; `nil` for blank.
Signals `field-error` when `string` is not acceptable input.

#### `format-field` `field value` — generic function

`value` as text, for showing and for an input to start from.

#### `check-field` `field value` — generic function

`nil` when `value` suits `field`, or a sentence saying why not.
Methods should call `call-next-method` to keep the general checks.

#### `render-field-input` `field id text callback` — generic function

Write the input for `field`, with `dom` id `id`, showing `text`;
`callback` receives what is submitted.

#### `render-field-value` `field value` — generic function

Write `value` for reading, in a viewer or report.

#### `field-error` — condition

Signalled by `parse-field` when input is not a value of the field's kind.

#### `field-problem` `format-control &rest arguments` — function

Signal a `field-error` with the message `format-control`, translated, formats.

#### `validate` `object &optional (description object)` — function

Alist of (`field-name` . `problem`) for the fields of `object` that fail their
checks, then (`nil` . `problem`) when the values fail the description's own.

#### `make-editor` `object &key (description object) title (save-label "Save") (write t)` — function

An editor for `object`, described by `description` (default: by its class).
On Save it writes the values to `object` and answers it; with `write` `nil` it
leaves `object` alone and answers the values as a plist keyed by field name
keywords, for objects shared between sessions that the application changes
under its own lock.

#### `make-viewer` `object &key (description object)` — function

A read-only view of `object`, described by `description`.

#### `description-editor` — class

Edits an object through its description; answers the
object on Save (after writing the values back) and `nil` on Cancel.

#### `description-viewer` — class

Shows an object's described values; answers on Close.

#### `description-columns` `description &rest names` — function

`report` columns for `description`'s fields: those named in `names`, or every
field shown in reports.

### Backtracking

#### `snapshot` — class

The saved state of a page: what `take-snapshot` captured and `restore-snapshot` puts back.

#### `take-snapshot` `root` — function

Capture the state of everything visible from `root`.

#### `restore-snapshot` `snapshot` — function

Put back what `snapshot` captured.

#### `begin-isolation` `&optional (session *session*)` — function

Start a stretch of pages that `end-isolation` will make unreachable.
Returns a token for `end-isolation`; it is a plain value, so a flow can hold
it across CALLs.

#### `end-isolation` `token &optional (session *session*)` — function

Forget every page made since `begin-isolation` returned `token`, so the back
button cannot return into them (to place an order twice, say).  Going back
to one of them shows the session as it is now.

#### `deep` `object` — function

Name `object` in `states` as (`deep` `object`) to snapshot its lists, vectors,
strings and hash tables by copying them, not sharing them.

#### `deep-copy` `value &optional (seen (make-hash-table :test (quote eq)))` — function

A copy of `value`'s lists, vectors, strings and hash tables, all the way
down.  Other objects (instances, structures, symbols, numbers) are shared;
shared structure and cycles are kept.

#### `snapshot-entries` `object` — generic function

Reads the entries of a snapshot.  List of (`object` . `saved`) where `saved` is what
`capture-state` returned for it.

### Tasks

#### `task` — class

A component defined by a `flow` of calls.

#### `define-flow` `class (self) &body body` — macro

Define the flow of the task `class`, with `self` bound to the task.

#### `flow` `task` — generic function

The body of `task`.  Define methods with `define-flow`.

### AJAX and push

#### `ajax` `&key callback update value confirm on-complete` — function

Run `callback` in the background, then re-render the component or list of
components `update`.

`value` is a JavaScript expression evaluated in the browser, with this bound
to the element; when given, `callback` receives its result as a string.
`callback`'s return value goes back to the browser, where `on-complete`, a
JavaScript snippet, can use it as value.  `confirm` asks the user before
anything is sent.

#### `ajax-update` `&rest components` — function

Re-render `components`, running no callback first.

#### `periodical` `seconds &key callback update` — function

For a :`periodical` attribute: every `seconds`, run `callback` and re-render `update`.

#### `execute-script` `javascript` — function

Run `javascript` in the browser once the current `ajax` request's updates are
in place.  Outside an `ajax` request it does nothing and returns `nil`.

#### `channel` — class

Something components can subscribe to and threads `publish`.

#### `make-channel` `&optional name` — function

A new channel, named `name` for printing.

#### `subscriptions` `component` — generic function

The channels whose `publish` re-renders `component` on open pages.

#### `publish` `channel` — function

Re-render, on every open page, the visible components subscribed to `channel`.
Safe to call from any thread.  Returns the number of pages told.

#### `notify` `component &optional (session *session*)` — function

Re-render `component` on `session`'s open pages.  Safe to call from any
thread, given the session (capture *SESSION* in the callback that starts
the work).

#### `close-event-streams` — function

End every open stream; browsers reconnect when their page is current.

#### `with-session` `(session) &body body` — macro

Run `body` as `session`'s requests do: holding its lock, with *SESSION* bound.
For other threads that change a session's components.

#### `*source-editor*` — variable

A function of a pathname and a 1-based character position that opens the
source there, for the halos' edit button.  `nil` uses the Emacs connected
through Swank, when there is one.

#### `*async-stream-opener*` — variable

A function of (`socket` `stream` `writer`) that serves `stream` from an event
loop, set by an optional system such as littoral/woo; `nil` when there is
none and each stream gets a waiting thread.

### Wizards

#### `wizard` — class

A description's fields in steps, with a review before finishing.

#### `make-wizard` `object &key (description object) steps title (write t)` — function

A wizard for `object`, described by `description`, in `steps`: (`title` `field-name` …)
lists.  Without `steps`, one step per field not hidden.

#### `wizard-step` `object` — generic function

Reads the step of a wizard.  The step shown; the number of steps for the review.

### More widgets

#### `data-grid` — class

A table of a description's objects: a filter box per column,
sorting by column, paging, and editing a row in place with the description's
own inputs and validation.

#### `bar-chart` `data &key (title "") (width 480) (height 220) (format-value (function princ-to-string))` — function

Write a bar chart of `data`, a list of (`label` . `value`), as accessible `svg`.

#### `line-chart` `series &key (title "") (width 480) (height 220) x-labels (format-value (function princ-to-string))` — function

Write a line chart of `series`, a list of (`name` . `values`), the values all
the same length, as accessible `svg`.  `x-labels` name the points.

#### `sparkline` `values &key (label "") (width 120) (height 28)` — function

Write a small line of `values`, with `label` for screen readers.

#### `calendar` — class

A month of days, Monday first, with their events, and links
to the months before and after.

#### `calendar-year` `object` — generic function

Reads the year of a calendar.

#### `calendar-month` `object` — generic function

Reads the month of a calendar.

#### `kanban` — class

Columns of cards to drag between, or move with the arrow
buttons on each card (which work without JavaScript or a mouse).

#### `kanban-columns` `object` — generic function

Reads the columns of a kanban.  (`title` . `items`) for each column, replaced on every move.

#### `move-card` `board from-column from-index to-column to-index` — function

Move the card at `from-index` of `from-column` to `to-index` of `to-column`; `nil` if out of range.

#### `markdown-html` `markdown` — function

`markdown` as `html`: paragraphs, # headings, - and 1. lists, > quotes, ```
code blocks, `code`, **strong**, *emphasis* and [links](https://…).  All
of `markdown`'s own `html` is escaped, and links go only to http(s), mailto or
this site, so the result is safe to show whoever wrote it.

#### `markdown-field` — class

Text written in Markdown, shown as safe `html`.

### JSON endpoints

#### `define-endpoint` `application-path method pattern (&rest parameters) &body body` — macro

Serve `body` as `json` for `method` (:`get`, :`post`, :`put`, :`patch`, :`delete`)
requests to `pattern`, such as "/api/items/:id", under the application at
`application-path`.  `parameters` are bound to `pattern`'s :`name` segments, in order.

#### `register-endpoint` `application-path method pattern function` — function

Serve `function` for `method` requests to `pattern` under `application-path`.
`pattern`'s :`name` segments become `function`'s arguments, as strings.

#### `endpoint-error` — condition

Signalled by `endpoint-error`: answered as {"error": message} with its status.

#### `endpoint-error` `status message &rest arguments` — function

Answer the current endpoint request with `status` and {"error": `message`}.

#### `endpoint-body` — function

The request's `json` body, parsed (objects as hash tables), or `nil` when empty.
Signals `endpoint-error` 400 when it isn't `json`.

#### `*endpoint-authenticator*` — variable

A function of no arguments answering who an endpoint request comes from,
and how (:`token` or :`cookie`); littoral/auth sets it.

### Health, metrics, request logs

#### `add-health-check` `name function` — function

Have /healthz call `function`, of no arguments; it fails when `function`
signals or returns `nil`.  Replaces any check called `name`.

#### `remove-health-check` `name` — function

Forget the health check `name`.

#### `serve-metrics` `&key (path "/metrics") (local-only t)` — function

Serve metrics at `path` for Prometheus to scrape.  With `local-only` (the
default) only requests from this machine get them: put the scraper there,
or behind the proxy with *TRUST-FORWARDED-FOR* and an allow list.

#### `metrics-text` — function

Every metric, in Prometheus's text exposition format.

#### `metrics-summary` — function

A plist of headline numbers, for pages that show them: :`requests` :`errors`
:`sessions` :`streams` :`jobs-running` :`heap` :`threads` :`uptime` and :`mean-ms`.

#### `reset-metrics` — function

Start the request counts and timings again from zero.

#### `log-requests-to` `stream &key (format :json)` — function

Write a line to `stream` for every request: `json` (`format` :`json`, for log
collectors) or text (:`text`).  `nil` for `stream` stops logging.

#### `*request-log*` — variable

A function of a plist describing each request (:`time` :`method` :`path` :`app` :`kind`
:`status` :`milliseconds` :`address`), or `nil`.  See `log-requests-to`.

#### `*latency-buckets*` — variable

Upper bounds, in seconds, of the request duration histogram's buckets.

### Background jobs (the class JOB is not exported: the name is too common)

#### `submit-job` `function &key (name "Job") (attempts 1) (backoff 2)` — function

Run `function`, of no arguments, in the background; the `job`.  It is tried
up to `attempts` times, waiting `backoff` seconds before the second and twice
as long before each after.  Its value becomes the `job-result`.

#### `job-progress` `fraction &optional message (job *current-job*)` — function

From inside a job: it is `fraction` (0 to 1) done, with `message` to show.
Re-renders the components watching it.  Signals `job-cancelled` once the job
has been cancelled, ending it.

#### `cancel-job` `job` — function

Stop `job`: at once if it hasn't started or is waiting to retry, otherwise
at its next `job-progress`.

#### `watch-job` `job component &optional (session *session*)` — function

Re-render `component` on `session`'s pages whenever `job` changes.  The page
must listen for pushes: a `job-view` does; another component can subscribe
to *JOBS-CHANNEL*.

#### `wait-for-job` `job &optional (timeout 60)` — function

Wait until `job` has finished, at most `timeout` seconds; its status.

#### `list-jobs` — function

Recent jobs, newest first.

#### `job-view` — class

A job's progress bar, status and Cancel button, kept up to
date by server push once `watch-job` has been called on it.

#### `job-view-job` `object` — generic function

Reads the job of a job-view.

#### `job-cancelled` — condition

Signalled by `job-progress` in a job that `cancel-job` was called on.

#### `*current-job*` — variable

The job this thread is running.

#### `*job-workers*` — variable

Threads running jobs at once.

#### `*jobs-channel*` — variable

Subscribed to by `job-view` so that its page listens for pushes; never published.

#### `job-id` `object` — generic function

Reads the id of a job.

#### `job-name` `object` — generic function

Reads the name of a job.

#### `job-status` `object` — generic function

Reads the status of a job.  :`queued`, :`running`, :`waiting` (to retry), :`done`, :`failed` or :`cancelled`.

#### `job-progress-fraction` `object` — generic function

Reads the progress of a job.

#### `job-message` `object` — generic function

Reads the message of a job.

#### `job-result` `object` — generic function

Reads the result of a job.

#### `job-error` `object` — generic function

Reads the error of a job.  The last failure, as text.

#### `job-attempt` `object` — generic function

Reads the attempt of a job.

#### `job-attempts` `object` — generic function

Reads the attempts of a job.

#### `*live-reload*` — variable

When true, open pages of applications in development mode reload after
their components' rendering methods are redefined (see live.lisp).

#### `reload-pages` `&optional (classes t)` — function

Have the open pages of applications in development mode reload: all of
them, or those showing an instance of one of `classes`.  Pages that poll see
it on their next poll; returns how many pages with event streams were told.

#### `start-live-watcher` `&key (interval 0.5)` — function

Watch for redefined rendering methods every `interval` seconds.

#### `stop-live-watcher` — function

Stop watching for redefined rendering methods.

### Sessions & applications

#### `session` — class

One user's component tree, the pages it has shown, and its lock.

#### `session-key` `object` — generic function

Reads the key of a session.

#### `session-root` `object` — generic function

Reads the root of a session.

#### `session-properties` `object` — generic function

Reads the properties of a session.

#### `session-property` `key &optional (session *session*)` — function

The value stored under `key` in `session`, for application use.

#### `expire-session` `session` — function

Forget `session` at once.

#### `list-sessions` `app` — function

`app`'s sessions, most recently used first.

#### `rotate-session-key` `&optional (session *session*)` — function

Give `session` a new key, so URLs naming the old one stop working, and end
its open event streams and sockets.  Signing in and out call this, so a
session key someone else learned beforehand is no use afterwards.  Sessions
kept in a cookie keep their key: another site cannot plant that cookie.

#### `set-cookie` `name value &key max-age path (http-only t) (same-site "Lax") (session *session*)` — function

Have the browser keep the cookie `name`=`value`, sent with this application's
requests (or `path`'s).  `max-age` in seconds keeps it that long, 0 deletes it,
`nil` keeps it until the browser closes.  Secure over `https`.  The cookie goes
out with `session`'s next `http` response: this one, or the next page load when
called while answering a WebSocket message.

#### `request-cookie` `name` — function

The value of the request's cookie `name`, or `nil`.

#### `mount-handler` `prefix handler` — function

Answer requests for paths under `prefix` (such as "/files/") with `handler`, a
function of the rest of the path that returns a Lack response.  Replaces any
handler mounted at `prefix`.

#### `unmount-handler` `prefix` — function

Stop serving `prefix` with the handler `mount-handler` gave it.

#### `field-multipart-p` `field` — generic function

True when `field`'s input uploads a file, so its form must be multipart.

#### `application` — class

A root component class served at a path, with its settings and live sessions.

#### `application-path` `object` — generic function

Reads the path of an application.

#### `application-root-class` `object` — generic function

Reads the root-class of an application.

#### `application-title` `object` — generic function

Reads the title of an application.

#### `application-mode` `object` — generic function

Reads the mode of an application.  :`development` adds the toolbar and halos.

#### `application-session-timeout` `object` — generic function

Reads the session-timeout of an application.  Seconds a session may sit idle.

#### `application-max-continuations` `object` — generic function

Reads the max-continuations of an application.  Pages per session the back button can reach.

#### `application-cookie-sessions-p` `object` — generic function

Reads the cookie-sessions-p of an application.  Track the session in a cookie instead of the `url`.

#### `application-sessions` `object` — generic function

Reads the sessions of an application.

#### `application-max-sessions` `object` — generic function

Reads the max-sessions of an application.  Most live sessions; the least recently used go first.  `nil` for no limit.

#### `application-error-handler` `object` — generic function

Reads the error-handler of an application.  Function of a condition returning a component or an `html`
string for the error page, or `nil` for the standard one.

#### `application-expired-notice` `object` — generic function

Reads the expired-notice of an application.  Component class shown, before the root, to someone whose
session expired.  `nil` starts them over silently.

#### `application-stylesheets` `object` — generic function

Reads the stylesheets of an application.

#### `application-scripts` `object` — generic function

Reads the scripts of an application.

#### `application-credentials` `object` — generic function

Reads the credentials of an application.  (`user` . `password`) required by `http` basic auth, or `nil`.

#### `reap-all-sessions` — function

Forget the idle sessions of every application.

#### `start-reaper` `&key (interval 60)` — function

Reap idle sessions every `interval` seconds in a background thread.

#### `stop-reaper` — function

Stop the session reaper thread, if it is running.

#### `session-expired-notice` — class

A ready-made `expired-notice` for `register-application`.

#### `*instance-id*` — variable

A short name for this process, put at the front of every session key
("a1.xxxx") so a load balancer can send each session back to the process
that holds it.  `nil` for none.

#### `*max-request-size*` — variable

Largest request body littoral reads, in bytes, unless the application
says otherwise.  Larger requests get 413 before their body is read.

#### `*new-sessions-per-minute*` — variable

How many sessions one client address may start a minute; more get 429.
`nil` for no limit.

#### `*trust-forwarded-for*` — variable

When true, take the client address from X-Forwarded-For.  Set it only
behind a proxy that sets that header itself.

#### `*max-event-streams*` — variable

Most event streams open at once; more get 503.

#### `*max-event-streams-per-session*` — variable

Most event streams one session may hold open.

#### `application-max-request-size` `object` — generic function

Reads the max-request-size of an application.  Largest request body in bytes, or `nil` for *MAX-REQUEST-SIZE*.

#### `application-local-only-p` `object` — generic function

Reads the local-only-p of an application.  Answer only requests from this machine.

#### `application-language` `object` — generic function

Reads the language of an application.  The page's language, for the html lang attribute.

#### `application-around-actions` `object` — generic function

Reads the around-actions of an application.  A function called with a thunk that runs a request's
callbacks, or `nil`.  littoral/db uses it to run them in a transaction.

#### `application-around-request` `object` — generic function

Reads the around-request of an application.  A function called with a thunk that handles a whole
request, rendering included, or `nil`.  littoral/db uses it to choose the
application's database.

#### `application-websockets-p` `object` — generic function

Reads the websockets-p of an application.  Carry `ajax` and server push over one WebSocket per page
(with littoral/websocket loaded), on pages that have push.

#### `application-content-security-policy` `object` — generic function

Reads the content-security-policy of an application.  :`strict` (scripts only with the page's nonce), a policy
string with {nonce} for the nonce, or `nil` for none.

#### `*configuration-file*` — variable

Where `save-configuration` writes, and the /config application saves after
each change.  Set by `start`'s :`configuration-file`.

#### `save-configuration` `&optional (file *configuration-file*)` — function

Write every registered application's settings to `file`, readable only by
its owner since it may hold credentials.  Returns `file`, or `nil` when there
is none.

#### `load-configuration` `&optional (file *configuration-file*)` — function

Configure applications from `file`.  Applications whose classes are not
loaded are skipped with a warning.  Returns the applications configured.

#### `configure-application` `path &rest settings &key root-class title language languages mode session-timeout max-continuations cookie-sessions stylesheets scripts credentials max-sessions expired-notice` — function

Change the settings given for the application at `path`, registering it
when there is none.  Sessions, and settings not given, are kept.

#### `application-settings` `app` — function

`app`'s configuration as a plist, as `save-configuration` writes it.

#### `register-application` `path root-class &rest initargs &key title mode session-timeout max-continuations cookie-sessions stylesheets scripts credentials max-sessions error-handler expired-notice max-request-size local-only language around-actions around-request websockets languages content-security-policy` — function

Serve `root-class`, a component class, at `path`.  Replaces any application
already there.  Returns the `application`.

#### `unregister-application` `path` — function

Stop serving the application at `path`.

#### `find-application` `path` — function

The application registered at exactly `path`, or `nil`.

#### `list-applications` — function

All registered applications, sorted by path.

#### `make-lack-app` `&key (prefix "")` — function

A Lack application serving every registered littoral application.
`prefix` is the path it is mounted under when the mounting middleware does
not set :`script-name` (lack's mount middleware does not).

#### `start` `&key (port 8080) (address "127.0.0.1") (server :hunchentoot) (prefix "") configuration-file (instance-id *instance-id*) (max-threads 100) (workers 4)` — function

Serve all registered applications with Clack on `port`, under `prefix`, and
reap idle sessions in the background.  With `configuration-file`, first load
the applications saved there; /config then saves its changes to it.
`instance-id` prefixes session keys, for routing several processes.
`max-threads` caps Hunchentoot's worker threads; every open page with server
push holds one, so raise it when many pages subscribe.  With `server` :`woo`
(load littoral/woo first) `workers` event loops serve everything, push included,
without a thread per page.

#### `stop` — function

Stop serving, close open event streams and stop reaping sessions.

#### `*debug-errors*` — variable

When true, errors inside a request enter the debugger instead of
rendering an error page.

#### `url-for` `path` — function

`path`, absolute within this littoral, as a `url` the browser can follow.

#### `*base-path*` — variable

Prepended to every `url` littoral writes: the mount prefix given to
`make-lack-app` plus the request's script-name.  No trailing slash.

#### `configure-admin` `&key user password (path "/config")` — function

Serve the configuration application at `path`.  With `user` and `password` it
is behind `http` basic auth; without, it answers only requests from this
machine.

### Languages

#### `translate` `source &rest arguments` — function

`source` in the current language; with `arguments`, used as a `format` control
string for them.

#### `translate-plural` `count singular plural &rest arguments` — function

The current language's form of `singular` (`plural` in English) for `count`,
formatted with `count` and then `arguments`.

#### `define-translations` `language &body entries` — macro

Add `entries`, unevaluated, to `language`'s catalogue.  Each is (`source` `form`
...): one form for plain text, or one per plural form, in the order the
language's plural rule numbers them.

#### `add-translations` `language entries` — function

Add `entries`, a list as `define-translations` takes, to `language`'s catalogue.

#### `load-translations` `language pathname` — function

Add the entries read from the file `pathname`, each a list (`source` `form` ...),
to `language`'s catalogue.  Nothing in the file is evaluated.

#### `define-language` `code &key name plural decimal group months date` — function

Describe the language `code` (such as "fr" or "pt-BR"): its `name` in
itself, its `plural` rule (a function of a count returning the index of the
plural form to use), its `decimal` and `group` separators, its `months`' names and
its `date` function of (`year` `month` `day` `months`) returning a string.  Unsupplied
details are English's.

#### `current-language` — function

The language this request is answered in: *LANGUAGE*, else the
session's, else the application's.

#### `set-language` `code &optional (session *session*)` — function

From now on, show `session` in the language `code`.

#### `*language*` — variable

When bound to a language code, the language to use regardless of the session.

#### `*source-language*` — variable

The language source strings are written in; it needs no catalogue.

#### `missing-translations` `language` — function

The source strings shown in `language` so far that its catalogue lacks;
for translators.

#### `translated-languages` — function

The languages that have a catalogue, with the source language.

#### `language-display-name` `code` — function

What the language `code` calls itself.

#### `translate-label` `label` — function

`label` translated when it is a non-empty string; anything else as it is.

#### `localized-number` `number &key (decimals (if (integerp number) 0 2))` — function

`number` as the current language writes it, with `decimals` places.

#### `localized-date` `year month day` — function

The date as the current language writes it in full, such as
"October 7, 2026" or "7 octobre 2026".

#### `application-languages` `object` — generic function

Reads the languages of an application.  Languages offered besides `language`: a new session takes the
first of these and `language` that the browser's Accept-Language asks for.

#### `language-chooser` — class

Links to show the session in each language offered,
each named in its own language; the current one is not a link.

## Package `littoral.html`

Tags and brushes for writing HTML in RENDER methods.

### Canvas

#### `*canvas*` — variable

The stream render methods write `html` to.

#### `text` `thing` — function

Write `thing`, printed with `princ` and HTML-escaped.

#### `raw` `string` — function

Write `string` verbatim.

#### `with-canvas-to-string` `() &body body` — macro

Evaluate `body` with *CANVAS* collecting into a string, which is returned.

#### `html-escape` `thing` — function

Return the printed representation of `thing` with `html` metacharacters escaped.

### Plain tags

#### `div` `&rest arguments` — macro

Write a <div> element.

#### `span` `&rest arguments` — macro

Write a <span> element.

#### `p` `&rest arguments` — macro

Write a <p> element.

#### `h1` `&rest arguments` — macro

Write a <h1> element.

#### `h2` `&rest arguments` — macro

Write a <h2> element.

#### `h3` `&rest arguments` — macro

Write a <h3> element.

#### `h4` `&rest arguments` — macro

Write a <h4> element.

#### `h5` `&rest arguments` — macro

Write a <h5> element.

#### `h6` `&rest arguments` — macro

Write a <h6> element.

#### `ul` `&rest arguments` — macro

Write a <ul> element.

#### `ol` `&rest arguments` — macro

Write a <ol> element.

#### `li` `&rest arguments` — macro

Write a <li> element.

#### `dl` `&rest arguments` — macro

Write a <dl> element.

#### `dt` `&rest arguments` — macro

Write a <dt> element.

#### `dd` `&rest arguments` — macro

Write a <dd> element.

#### `table` — class

How a class's objects are stored.

#### `table` `&rest arguments` — macro

Write a <table> element.

#### `thead` `&rest arguments` — macro

Write a <thead> element.

#### `tbody` `&rest arguments` — macro

Write a <tbody> element.

#### `tfoot` `&rest arguments` — macro

Write a <tfoot> element.

#### `tr` `&rest arguments` — macro

Write a <tr> element.

#### `td` `&rest arguments` — macro

Write a <td> element.

#### `th` `&rest arguments` — macro

Write a <th> element.

#### `caption` `&rest arguments` — macro

Write a <caption> element.

#### `em` `&rest arguments` — macro

Write a <em> element.

#### `strong` `&rest arguments` — macro

Write a <strong> element.

#### `b` `&rest arguments` — macro

Write a <b> element.

#### `i` `&rest arguments` — macro

Write a <i> element.

#### `u` `&rest arguments` — macro

Write a <u> element.

#### `small` `&rest arguments` — macro

Write a <small> element.

#### `code` `&rest arguments` — macro

Write a <code> element.

#### `pre` `&rest arguments` — macro

Write a <pre> element.

#### `blockquote` `&rest arguments` — macro

Write a <blockquote> element.

#### `sup` `&rest arguments` — macro

Write a <sup> element.

#### `sub` `&rest arguments` — macro

Write a <sub> element.

#### `section` `&rest arguments` — macro

Write a <section> element.

#### `article` `&rest arguments` — macro

Write a <article> element.

#### `aside` `&rest arguments` — macro

Write a <aside> element.

#### `nav` `&rest arguments` — macro

Write a <nav> element.

#### `header` `&rest arguments` — macro

Write a <header> element.

#### `footer` `&rest arguments` — macro

Write a <footer> element.

#### `main` `&rest arguments` — macro

Write a <main> element.

#### `figure` `&rest arguments` — macro

Write a <figure> element.

#### `figcaption` `&rest arguments` — macro

Write a <figcaption> element.

#### `fieldset` `&rest arguments` — macro

Write a <fieldset> element.

#### `legend` `&rest arguments` — macro

Write a <legend> element.

#### `label` `&rest arguments` — macro

Write a <label> element.

#### `abbr` `&rest arguments` — macro

Write a <abbr> element.

#### `cite` `&rest arguments` — macro

Write a <cite> element.

#### `mark` `&rest arguments` — macro

Write a <mark> element.

#### `dfn` `&rest arguments` — macro

Write a <dfn> element.

#### `kbd` `&rest arguments` — macro

Write a <kbd> element.

#### `samp` `&rest arguments` — macro

Write a <samp> element.

#### `var-tag` `&rest arguments` — macro

Write a <var> element.

#### `details` `&rest arguments` — macro

Write a <details> element.

#### `summary` `&rest arguments` — macro

Write a <summary> element.

#### `img` `&rest arguments` — macro

Write a <img> element.

#### `br` `&rest arguments` — macro

Write a <br> element.

#### `hr` `&rest arguments` — macro

Write a <hr> element.

#### `tag` `name &rest arguments` — macro

Write an element whose `name` (a string) is computed.

### Brushes with callbacks

#### `anchor` `&rest arguments` — macro

A link.  :`callback` is a thunk run when it is followed; :`href` a plain `url`.

#### `form` `&rest arguments` — macro

A form posting back to the session.  Its fields' callbacks run before
the action of the button that submitted it.  :`default-action` is a thunk run
when the form is submitted without a button; :`multipart` T allows `file-input`.

#### `text-input` `&optional attributes` — macro

A text field.  :`callback` receives the submitted string.

#### `password-input` `&optional attributes` — macro

A password field.  :`callback` receives the submitted string.

#### `number-input` `&optional attributes` — macro

An integer field.  :`callback` receives an integer, or `nil` when the
submission does not parse.

#### `hidden-input` `&optional attributes` — macro

A hidden field.  :`callback` receives its :`value` when the form is submitted.

#### `text-area` `&optional attributes` — macro

A multi-line text field showing :`value`.  :`callback` receives the submitted string.

#### `checkbox` `&optional attributes` — macro

A checkbox.  :`value` is its state; :`callback` receives T or `nil`.

#### `select-list` `&optional attributes` — macro

A drop-down of :`items` shown through :`labels` (a function, default `princ`).
:`callback` receives the chosen item; :`selected` is the current one.

#### `radio-group` `&optional attributes` — macro

Radio buttons, one per item of :`items`; otherwise like `select-list`.

#### `submit-button` `&rest arguments` — macro

A button submitting its form, then running the thunk :`callback`.

#### `cancel-button` `&rest arguments` — macro

A button that runs the thunk :`callback` and nothing else: the form's
fields are not applied.

#### `button` `&rest arguments` — macro

A button that submits nothing; give it an `ajax` :`on-click`.

#### `file-input` `&optional attributes` — macro

A file chooser.  :`callback` receives an `uploaded-file`, and is not called
when no file was chosen.  The enclosing `form` needs :`multipart` T.

#### `uploaded-file` — class

A file submitted through `file-input`.

#### `file-name` `object` — generic function

Reads the filename of an uploaded-file.  The name the browser gave, without directories.

#### `file-content-type` `object` — generic function

Reads the content-type of an uploaded-file.  The `mime` type the browser gave.

#### `file-contents` `object` — generic function

Reads the contents of an uploaded-file.  The file's bytes, an (`unsigned-byte` 8) vector.

## Package `littoral.test`

Test Littoral applications in-process with a fake browser.

### A browser and its state

#### `browser` — class

A fake browser driving the Lack app in-process.

#### `browser-app` `object` — generic function

Reads the app of a browser.

#### `browser-url` `object` — generic function

Reads the url of a browser.

#### `browser-status` `object` — generic function

Reads the status of a browser.

#### `browser-html` `object` — generic function

Reads the html of a browser.

#### `browser-cookies` `object` — generic function

Reads the cookies of a browser.

#### `browser-headers` `object` — generic function

Reads the headers of a browser.  Alist of header name → value sent with every request,
such as ("accept-language" . "fr").

#### `browser-fields` `object` — generic function

Reads the fields of a browser.  Alist of field name → value typed into the current page.

#### `browser-files` `object` — generic function

Reads the files of a browser.  Alist of field name → (`filename` `content-type` `octets`).

### Requests

#### `visit` `browser url &key (method :get) body content-type` — function

Request `url`, following redirects, and make the result the current page.

#### `back-to` `browser url` — function

Return to an earlier page, as the back button (with no cache) would.

#### `raw-request` `browser method url &key body content-type` — function

One request, no redirects followed.  Returns status, headers, body string.

#### `make-env` `method url &key body cookies extra-headers (content-type "application/x-www-form-urlencoded")` — function

A Lack environment for a `method` request to `url`, with `extra-headers` (an
alist of lower-case names to values).

#### `response-header` `headers name` — function

The header `name` from a Lack response's `headers` plist.

### Reading the page

#### `page-text` `browser` — function

The current page's text without markup.

#### `has-text-p` `browser text` — function

True when the current page's text contains `text`.

#### `find-link` `browser text` — function

The href of the first link whose text contains `text`.

#### `find-links` `browser text` — function

The hrefs of every link whose text is exactly `text`, in page order.

#### `element-name` `browser id` — function

The name of the field with `dom` id `id`.

#### `form-action` `browser` — function

The action `url` of the first form on the page.

#### `attributes` `tag` — function

The attributes in `tag`, the inside of an `html` start tag, as an alist.

#### `attr` `attributes name` — function

The value of attribute `name` in `attributes`.

#### `unescape` `string` — function

`string` with the `html` escapes littoral writes undone.

#### `strip-tags` `html` — function

`html` with its tags removed and escapes undone.  Scripts and style sheets
go whole, as they aren't text (and a < in them isn't a tag).

### Acting on it

#### `click` `browser text` — function

Follow the link whose text contains `text`.

#### `click-nth` `browser text n` — function

Follow the Nth (from 0) link whose text is exactly `text`.

#### `fill-in` `browser id value` — function

Type `value` into the field with `dom` id `id`.

#### `set-checkbox` `browser index checked` — function

Check or uncheck the INDEXth checkbox on the page.

#### `select-option` `browser id label` — function

Choose the option labelled `label` in the select with `dom` id `id`.

#### `attach-file` `browser id filename content-type contents` — function

Choose a file for the file input with `dom` id `id`.  `contents` is a string
or a vector of octets.

#### `press` `browser text` — function

Submit the form with the button whose label contains `text`.

#### `encode-fields` `fields` — function

`fields`, an alist, as a URL-encoded form body.

### AJAX and server push

#### `ajax-request` `browser callback targets &key fields` — function

Post an `ajax` request the way littoral.js does; returns the `json` text.

#### `ajax-specs` `browser attribute` — function

The (`callback` . `targets`) of each element with data-lt-ATTRIBUTE.

#### `sink` — class

Collects what an event stream writes.

#### `sink-text` `sink` — function

Everything written to `sink` so far.

#### `open-stream` `browser sink` — function

Open the current page's event stream in a thread, writing into `sink`.

#### `wait-for` `predicate &optional (seconds 10)` — function

Poll `predicate` for up to `seconds`; true when it came true.

### Test fixtures

#### `with-fresh-applications` `(&rest registrations) &body body` — macro

Run `body` with only the given applications registered.

## Package `littoral.browser-test`

Drive headless Chrome from Lisp tests.

### General

#### `with-chrome` `(page &rest options &key base width height) &body body` — macro

Run `body` with `page` a headless Chrome tab, its paths relative to `base`.

#### `chrome-path` — function

Chrome or Chromium: $`chrome`, $LITTORAL_TEST_CHROME, or the usual places.

#### `page` — class

A Chrome tab, driven over the DevTools protocol.

#### `visit` `page path` — function

Open `path` (relative to the page's base `url`, or absolute).

#### `evaluate` `page javascript` — function

The value of `javascript` in `page` (promises awaited), as JSON-able Lisp data.

#### `click-text` `page text &key (among "a, button")` — function

Click the first link or button (or what `among` selects) whose text is `text`,
or failing that contains it.

#### `click-css` `page selector` — function

Click the first element `selector` matches, as a user would.

#### `type-into` `page selector string` — function

Type `string` into the field `selector` matches, key by key.

#### `text` `page &optional (selector "body")` — function

The visible text of what `selector` matches.

#### `page-url` `page` — function

Where `page` is.

#### `back` `page` — function

The browser's back button.

#### `wait-until` `page javascript &key (timeout 10)` — function

Wait until `javascript` is true in `page`; signals `browser-error` after `timeout` seconds.

#### `screenshot` `page pathname` — function

Save `page` as a `png` at `pathname`.

#### `add-virtual-authenticator` `page` — function

Give `page` a platform authenticator that always says yes, for passkey tests.

#### `browser-error` — condition

Chrome couldn't do what a test asked: no such element, a timeout, a JavaScript error.

## Package `littoral.mail`

Sending mail: MIME messages, SMTP, templates and an outbox that retries.

### Messages

#### `mail` — class

A mail to send: `make-mail` makes one.

#### `make-mail` `&key to cc bcc (from *mail-from*) reply-to (subject "") text html attachments headers` — function

A mail.  `to`, `cc` and `bcc` are addresses ("ada@example.org" or "Ada <ada@example.org>")
or lists of them; `text` and `html` its plain and `html` bodies (one is enough: the
plain one is made from the `html` when missing); `attachments` (`file-name`
`content-type` `data`) lists, `data` octets or a string; `headers` (`name` . `value`) pairs.

#### `mail-to` `object` — generic function

Reads the to of a mail.

#### `mail-cc` `object` — generic function

Reads the cc of a mail.

#### `mail-bcc` `object` — generic function

Reads the bcc of a mail.

#### `mail-from` `object` — generic function

Reads the from of a mail.

#### `mail-reply-to` `object` — generic function

Reads the reply-to of a mail.

#### `mail-subject` `object` — generic function

Reads the subject of a mail.

#### `mail-text` `object` — generic function

Reads the text of a mail.

#### `mail-html` `object` — generic function

Reads the html of a mail.

#### `mail-attachments` `object` — generic function

Reads the attachments of a mail.  (`file-name` `content-type` `octets-or-string`) lists.

#### `mail-headers` `object` — generic function

Reads the headers of a mail.  Extra headers, as (`name` . `value`) pairs.

#### `mail-string` `mail &key (date (get-universal-time))` — function

`mail` as a `mime` message, with `crlf` line breaks; Bcc isn't written.

#### `mail-recipients` `mail` — function

Everyone `mail` goes to, Bcc included, as bare addresses.

#### `*mail-from*` — variable

The From address of mail that doesn't give one.

#### `address-spec` `address` — function

The bare address in `address`: "Ada <ada@example.org>" → "ada@example.org".

### Reading messages back

#### `message-header` `message name` — function

The header `name` of `message` (a `mime` string), decoded, or `nil`.

#### `message-text` `message` — function

The plain text of `message` (a `mime` string), with plain newlines.

#### `message-html` `message` — function

The `html` part of `message` (a `mime` string), or `nil`.

### Mailers

#### `*mailer*` — variable

What sends mail: an `smtp-mailer`, or by default a `log-mailer` that prints it.

#### `send-message` `mailer from recipients message` — generic function

Send `message`, a `mime` string, from the address `from` to the addresses
`recipients`.  Signals on failure; an `smtp-error` that is `smtp-error-permanent-p`
won't succeed if tried again.

#### `send-mail` `mail &key (mailer *mailer*)` — function

Send `mail` now, waiting for the mailer.  `queue-mail` sends it in the
background instead, and tries again when it fails.

#### `smtp-mailer` — class

Sends mail through an `smtp` server: `make-smtp-mailer` makes one.

#### `make-smtp-mailer` `&key (host "localhost") port (security :starttls) username password (helo (machine-instance)) (verify t) ca-file (timeout 30)` — function

A mailer sending through the `smtp` server at `host`.  `security` is :`starttls`
(port 587 by default), :`tls` (465) or :`none` (25, for a relay on this machine).
With `username`, signs in with `auth` `plain` (or `login`).  The server's certificate
is checked against the system's authorities, or `ca-file`'s, unless `verify` is `nil`.
`timeout`, in seconds, bounds each send.

#### `smtp-mailer-from-url` `url &rest options` — function

A mailer from `url`: smtp://user:password@host:port (`starttls`), smtps://… (`tls`)
or smtp+insecure://… (neither).  `options` go to `make-smtp-mailer`.

#### `smtp-error` — condition

The `smtp` server refused, or the conversation went wrong.

#### `smtp-error-code` `condition` — generic function

The server's reply code in an `smtp-error`, such as 550, or `nil` when the conversation itself failed.

#### `smtp-error-permanent-p` `condition` — function

True when `condition` is a refusal (a 5xx reply) that trying again won't change.

#### `log-mailer` — class

Prints each message's addresses, subject and text, instead of sending it.

#### `memory-mailer` — class

Keeps the messages it is given, newest first, instead of sending them.

#### `make-memory-mailer` `&key (keep 50)` — function

A mailer that keeps the last `keep` messages, for tests and demos.

#### `mailer-messages` `mailer` — function

The messages `mailer` (a `memory-mailer`) has kept, newest first.

#### `clear-mailer` `mailer` — function

Forget the messages `mailer` (a `memory-mailer`) has kept.

#### `sent-message` — class

A message a `memory-mailer` was given.

#### `sent-message-from` `object` — generic function

Reads the from of a sent-message.

#### `sent-message-recipients` `object` — generic function

Reads the recipients of a sent-message.

#### `sent-message-text` `object` — generic function

Reads the text of a sent-message.  The `mime` message.

#### `sent-message-time` `object` — generic function

Reads the time of a sent-message.

### Templates

#### `define-mail` `name lambda-list &key to cc bcc from reply-to subject text html attachments headers` — macro

Define `name`, a function of `lambda-list` making a mail.  The keyword forms are
evaluated each time, with `lambda-list`'s variables bound; `html` is a list of
forms written with Littoral's `html` tags (as in `render`), inside *MAIL-LAYOUT*.
Without `text`, the plain text is made from the `html`.

#### `*mail-layout*` — variable

A function of (`subject` `body-thunk`) that writes the `html` around a template's content.

#### `default-mail-layout` `subject body` — function

Write an `html` mail around `body`, a thunk writing its content: a plain,
readable page that mail programs show well.

#### `html-to-text` `html` — function

A plain-text version of `html`: paragraphs and line breaks kept, links
written out after their text, tags dropped, entities decoded.

### The outbox

#### `outbox-mail` — class

A message in the outbox, and how sending it has gone.

#### `create-mail-tables` — function

Create the outbox table unless it exists.

#### `drop-mail-tables` — function

Drop the outbox table.

#### `queue-mail` `mail` — function

Put `mail` in the outbox, in the current database, for the delivery thread
to send; returns its `outbox-mail`.

#### `outbox-sender` `&key (from *mail-from*)` — function

A function of (`to` `subject` `body`) that queues a plain-text mail, for
`littoral`.`auth`:*SEND-MAIL*.

#### `deliver-queued-mail` `&key (mailer *mailer*) (limit 50)` — function

Send the messages in the current database's outbox that are due, with
`mailer`; returns how many were sent.  The delivery thread calls this; so can
a test, to send what's queued without waiting.

#### `start-mail-delivery` `&key (database *database*) (mailer *mailer*) (interval 10) (attempts *mail-attempts*) (retry-seconds *mail-retry-seconds*)` — function

Send the outbox of `database` (a spec, as `littoral`.`db`:*DATABASE* holds) with
`mailer` from a background thread: at once when mail is queued in this process,
and every `interval` seconds for retries and other processes' mail.  `attempts`
and `retry-seconds` stand for *MAIL-ATTEMPTS* and *MAIL-RETRY-SECONDS* there.

#### `stop-mail-delivery` — function

Stop the delivery thread, letting it finish the message it is sending.

#### `mail-delivery-running-p` — function

True while the delivery thread runs.

#### `outbox-messages` `&key status (limit 50)` — function

The outbox's messages, newest first; only those with `status` (a string) if given.

#### `retry-mail` `id` — function

Send the message `id` again now, with its attempts counted afresh.

#### `purge-sent-mail` `&key (older-than (* 7 24 3600))` — function

Delete sent messages more than `older-than` seconds old; returns how many.

#### `*mail-attempts*` — variable

Times a message is tried before it is marked failed.

#### `*mail-retry-seconds*` — variable

Seconds before a failed message is tried again, doubling with each attempt.

#### `outbox-id` `message` — function

`message`'s id in the outbox, for `retry-mail`.

#### `outbox-sender-address` `object` — generic function

Reads the sender of an outbox-mail.

#### `outbox-recipients` `object` — generic function

Reads the recipients of an outbox-mail.  The addresses it goes to, separated by spaces.

#### `outbox-subject` `object` — generic function

Reads the subject of an outbox-mail.

#### `outbox-message` `object` — generic function

Reads the message of an outbox-mail.  The `mime` message.

#### `outbox-status` `object` — generic function

Reads the status of an outbox-mail.  "queued", "sending", "sent" or "failed".

#### `outbox-attempts` `object` — generic function

Reads the attempts of an outbox-mail.

#### `outbox-next-attempt` `object` — generic function

Reads the next-attempt of an outbox-mail.

#### `outbox-last-error` `object` — generic function

Reads the last-error of an outbox-mail.

#### `outbox-created` `object` — generic function

Reads the created of an outbox-mail.

#### `outbox-sent` `object` — generic function

Reads the sent of an outbox-mail.

## Package `littoral.jobs`

Background jobs kept in the database: retried, scheduled, and run by any process.

### General

#### `define-job` `name-and-options lambda-list &body body` — macro

Define the job `name`, run with arguments as `lambda-list` takes them; also a
function `name` that runs `body` at once.  `name-and-options` is `name` or (`name`
&key `queue` `attempts` `retry-seconds` `timeout` `transaction` `every`):
  `queue`          the queue it goes to, "default"
  `attempts`       tries before it is marked failed, 5
  `retry-seconds`  the wait before the second try, doubling after, 30
  `timeout`        seconds a runner holds it before another may take it over, 600
  `transaction`    true to run it, and mark it done, in one transaction
  `every`          seconds between runs, or a function from a universal time to
                 the next time to run (see `daily-at`): it then takes no arguments,
                 is scheduled by the runners, and is never enqueued by hand.

#### `enqueue-job` `call &key at in key queue` — function

Queue `call`, (`name` . `arguments`), in the current database, to run at once,
`in` seconds, or `at` a universal time; its id.  With `key` (a string), nothing is
queued while a job with that key waits untried, and the value is `nil`.  `queue`
overrides the job's own.

#### `daily-at` `hour &optional (minute 0)` — function

For :`every`: once a day, at `hour`:`minute` local time.

#### `create-job-tables` — function

Create the job_queue table unless it exists.

#### `drop-job-tables` — function

Drop the job_queue table.

#### `run-due-jobs` `&key (queues (quote ("default"))) (limit 100)` — function

Run the jobs in `queues` of the current database that are due, here and now,
at most `limit` of them; how many ran.  Runners call this; so can a test.

#### `start-job-runner` `&key (database *database*) (threads 1) (queues (quote ("default"))) (interval 5)` — function

Run the jobs in `queues` of `database` (a spec, as `littoral`.`db`:*DATABASE* holds)
on `threads` background threads: at once when a job is enqueued in this
process, and every `interval` seconds for scheduled jobs, retries and other
processes' jobs.  Stops any runner already started.

#### `stop-job-runner` — function

Stop the runner threads, letting each finish the job it is running.

#### `job-runner-running-p` — function

True while this process's runner threads run.

#### `*durable-job*` — variable

The `durable-job` this thread is running.

#### `note-job-progress` `text` — function

From inside a job: record `text` as how it's going (`durable-job-progress`),
and hold on to the job for another `timeout`.

#### `abandon-job` `control &rest arguments` — function

From inside a job: fail it now, for the reason `control` and `arguments`
format, without trying again.

#### `job-abandoned` — condition

Signalled by `abandon-job`: the job fails without being tried again.

#### `durable-job` — class

A job in the job_queue table, as it was when read.

#### `durable-job-id` `object` — generic function

Reads the id of a durable-job.

#### `durable-job-name` `object` — generic function

Reads the name of a durable-job.  The job's name, a symbol (or its text, when unreadable here).

#### `durable-job-arguments` `object` — generic function

Reads the arguments of a durable-job.

#### `durable-job-queue` `object` — generic function

Reads the queue of a durable-job.

#### `durable-job-status` `object` — generic function

Reads the status of a durable-job.  "queued", "running", "done", "failed" or "cancelled".

#### `durable-job-attempts` `object` — generic function

Reads the attempts of a durable-job.  Tries so far; inside the job, which try this is.

#### `durable-job-run-at` `object` — generic function

Reads the run-at of a durable-job.  When it is due; while running, when another runner may take it over.

#### `durable-job-key` `object` — generic function

Reads the key of a durable-job.

#### `durable-job-progress` `object` — generic function

Reads the progress of a durable-job.  What `note-job-progress` said last.

#### `durable-job-last-error` `object` — generic function

Reads the last-error of a durable-job.

#### `durable-job-created` `object` — generic function

Reads the created of a durable-job.

#### `durable-job-finished` `object` — generic function

Reads the finished of a durable-job.

#### `find-durable-job` `id` — function

The job `id`, or `nil`.

#### `durable-jobs` `&key status queue (limit 50)` — function

Jobs, newest first; only those with `status` and in `queue` (strings) if given.

#### `durable-job-counts` — function

How many jobs have each status: (("queued" . 3) ("done" . 40) …).

#### `retry-durable-job` `id` — function

Run the failed or cancelled job `id` again now, its tries counted afresh;
true unless it wasn't failed or cancelled, or a job with its key waits already.

#### `cancel-durable-job` `id` — function

Cancel the job `id` unless it has started; true if it was cancelled.

#### `purge-durable-jobs` `&key (older-than (* 7 24 3600)) (statuses (quote ("done" "cancelled")))` — function

Delete jobs with one of `statuses` that finished more than `older-than`
seconds ago; how many.
