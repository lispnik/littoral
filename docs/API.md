# Littoral API reference

Generated from the docstrings and docs/examples/ by `make docs`; do not edit by hand.

## Running the examples

The examples are tested: the suite runs every one on its own and checks each result shown after `;; ⇒`, which is what the REPL prints. To try them, load Littoral and its fake browser, and make a package that uses the same packages they do:

```lisp
(asdf:load-system :littoral/test)
(defpackage #:try-littoral (:use #:cl #:littoral #:littoral.html #:littoral.test))
(in-package #:try-littoral)
```

Then paste any example. Most render pages in the fake browser (`visit`, `click`, `page-text`; see `littoral.test`), so they need no server. Examples for another package write its names in full, such as `littoral.db:db-save`, and need its system loaded first, such as `(asdf:load-system :littoral/db)`; each package's section says which.


## Package `littoral`

Littoral: a Seaside-style component web framework for Common Lisp.

### Context

#### `*request*` — variable

The lack/request:request being handled.

*Example:* The request being handled, a lack/request:request, for what the helpers don't cover, such as its headers.  The helpers read it by default.

```lisp
(defclass greeter (component)
  ((language :initform nil :accessor language)))
(defmethod initial-request ((self greeter) request)
  (declare (ignore request))
  (setf (language self)
        (gethash "accept-language" (lack/request:request-headers *request*))))
(defmethod render ((self greeter))
  (p () "Your browser prefers " (text (language self)) "."))
(with-fresh-applications (("/greeter" 'greeter :mode :deployment))
  (let ((b (make-instance 'browser :headers '(("accept-language" . "fr")))))
    (visit b "/greeter")
    (body-text b)))
;; ⇒ "Your browser prefers fr."
```

#### `*session*` — variable

The `session` owning the current request.

*Example:* While a request is handled, *session* is its session and *application* its application.  session-property keeps a value in *session* by default.

```lisp
(defclass visits (component) ())
(defmethod render ((self visits))
  (p () (text (application-title *application*)) ": "
    (text (princ-to-string (or (session-property :clicks) 0))) " clicks")
  (anchor (:callback (lambda ()
                       (setf (session-property :clicks *session*)
                             (1+ (or (session-property :clicks *session*) 0)))))
    "Click"))
(with-fresh-applications (("/visits" 'visits :mode :deployment :title "Visits"))
  (let ((b (make-instance 'browser)))
    (visit b "/visits")
    (click b "Click")
    (click b "Click")
    (body-text b)))
;; ⇒ "Visits: 2 clicks Click"
```

#### `*application*` — variable

The `application` the current request was dispatched to.

*Example:* While a request is handled, *session* is its session and *application* its application.  session-property keeps a value in *session* by default.

```lisp
(defclass visits (component) ())
(defmethod render ((self visits))
  (p () (text (application-title *application*)) ": "
    (text (princ-to-string (or (session-property :clicks) 0))) " clicks")
  (anchor (:callback (lambda ()
                       (setf (session-property :clicks *session*)
                             (1+ (or (session-property :clicks *session*) 0)))))
    "Click"))
(with-fresh-applications (("/visits" 'visits :mode :deployment :title "Visits"))
  (let ((b (make-instance 'browser)))
    (visit b "/visits")
    (click b "Click")
    (click b "Click")
    (body-text b)))
;; ⇒ "Visits: 2 clicks Click"
```

#### `*render-context*` — variable

The `render-context` active while rendering: it knows where callbacks go
and how to build URLs back into the session.

#### `request-parameter` `name &optional (request *request*)` — function

The value of the query or body parameter `name` in `request`, or `nil`.

*Example:* Read the request that started a session in initial-request.  request-parameter-p is true for a parameter given with no value.

```lisp
(defclass welcome (component)
  ((seen :initform nil :accessor seen)))
(defmethod initial-request ((self welcome) request)
  (setf (seen self) (list (request-path request)
                          (request-parameter "name" request)
                          (request-parameter-p "loud" request)
                          (request-parameter "missing" request))))
(defmethod render ((self welcome))
  (p () (text (prin1-to-string (seen self)))))
(with-fresh-applications (("/welcome" 'welcome :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/welcome/back?name=Ada&loud")
    (body-text b)))
;; ⇒ "(\"/welcome/back\" \"Ada\" T NIL)"
```

#### `request-parameter-p` `name &optional (request *request*)` — function

True when `request` has the parameter `name`, even with no value (?flag).

*Example:* Read the request that started a session in initial-request.  request-parameter-p is true for a parameter given with no value.

```lisp
(defclass welcome (component)
  ((seen :initform nil :accessor seen)))
(defmethod initial-request ((self welcome) request)
  (setf (seen self) (list (request-path request)
                          (request-parameter "name" request)
                          (request-parameter-p "loud" request)
                          (request-parameter "missing" request))))
(defmethod render ((self welcome))
  (p () (text (prin1-to-string (seen self)))))
(with-fresh-applications (("/welcome" 'welcome :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/welcome/back?name=Ada&loud")
    (body-text b)))
;; ⇒ "(\"/welcome/back\" \"Ada\" T NIL)"
```

#### `request-path` `&optional (request *request*)` — function

The path of `request` below the mount point, the application's path
included: "/shop/items/3".  `request-extra-path` gives the segments after
the application's path.

*Example:* Read the request that started a session in initial-request.  request-parameter-p is true for a parameter given with no value.

```lisp
(defclass welcome (component)
  ((seen :initform nil :accessor seen)))
(defmethod initial-request ((self welcome) request)
  (setf (seen self) (list (request-path request)
                          (request-parameter "name" request)
                          (request-parameter-p "loud" request)
                          (request-parameter "missing" request))))
(defmethod render ((self welcome))
  (p () (text (prin1-to-string (seen self)))))
(with-fresh-applications (("/welcome" 'welcome :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/welcome/back?name=Ada&loud")
    (body-text b)))
;; ⇒ "(\"/welcome/back\" \"Ada\" T NIL)"
```

#### `redirect-to` `url` — function

From a callback: when the request's callbacks are done, send the browser
to URL (another site, say) instead of the next page.

*Example:* A callback can send the browser elsewhere instead of to the next page.

```lisp
(defclass exit-page (component) ())
(defmethod render ((self exit-page))
  (anchor (:callback (lambda () (redirect-to "https://example.com/bye"))) "Leave"))
(with-fresh-applications (("/exit" 'exit-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/exit")
    (multiple-value-bind (status headers) (raw-request b :get (find-link b "Leave"))
      (list status (getf headers :location)))))
;; ⇒ (302 "https://example.com/bye")
```

#### `forbidden` — condition

Signal it to refuse a request: the user sees a 403 page
showing its `:message`, by default "You are not allowed to do that."

*Example:* Signal forbidden from a callback (or while rendering) to refuse: the user gets a 403 page with the message.

```lisp
(defclass vault (component) ())
(defmethod render ((self vault))
  (anchor (:callback (lambda () (error 'forbidden :message "Only the harbour master may open the vault.")))
    "Open"))
(with-fresh-applications (("/vault" 'vault :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/vault")
    (click b "Open")
    (list (browser-status b) (body-text b))))
;; ⇒ (403 "Forbidden Only the harbour master may open the vault.")
(forbidden-message (make-condition 'forbidden))
;; ⇒ "You are not allowed to do that."
```

#### `forbidden-message` `condition` — generic function

The explanation a `forbidden` condition shows the user.

*Example:* Signal forbidden from a callback (or while rendering) to refuse: the user gets a 403 page with the message.

```lisp
(defclass vault (component) ())
(defmethod render ((self vault))
  (anchor (:callback (lambda () (error 'forbidden :message "Only the harbour master may open the vault.")))
    "Open"))
(with-fresh-applications (("/vault" 'vault :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/vault")
    (click b "Open")
    (list (browser-status b) (body-text b))))
;; ⇒ (403 "Forbidden Only the harbour master may open the vault.")
(forbidden-message (make-condition 'forbidden))
;; ⇒ "You are not allowed to do that."
```

#### `render-phase-error` — condition

Signalled by `call`, `show`, `answer`, `home` and `show-modal` during
rendering, which must not change state.

*Example:* Rendering must not change state, so call, show, answer and home signal render-phase-error while a page renders.  Here an error handler shows the condition.

```lisp
(defclass hasty (component) ())
(defmethod render ((self hasty))
  (answer self 42))                     ; wrong: answer from a callback
(with-fresh-applications (("/hasty" 'hasty :mode :deployment
                                           :error-handler (lambda (condition) (princ-to-string condition))))
  (let ((b (make-instance 'browser)))
    (visit b "/hasty")
    (list (browser-status b) (body-text b))))
;; ⇒ (500 "answer was used while rendering. Rendering must not change state: do it in a callback instead.")
```

### Components

#### `component` — class

A stateful piece of user interface.  Subclass it and
specialise `render`.

*Example:* A component draws itself in its render method.  Visiting an application serves its root component.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (h1 () "Hello"))
(with-fresh-applications (("/greeting" 'greeting :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greeting")
    (body-text b)))
;; ⇒ "Hello"
```

#### `component-id` `object` — generic function

Reads the id of a component.  Unique and stable: the `dom` id AJAX updates target.

*Example:* Every component gets an id of its own when it is made; AJAX updates find their element by it.

```lisp
(let ((a (make-instance 'component))
      (b (make-instance 'component)))
  (list (stringp (component-id a))
        (string= (component-id a) (component-id a))
        (string= (component-id a) (component-id b))))
;; ⇒ (T T NIL)
```

#### `render` `component` — generic function

Write `component`'s HTML to `*canvas*`.  Embedded components
are written with `render-component`, never by calling `render` on them.

*Example:* A component draws itself in its render method.  Visiting an application serves its root component.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (h1 () "Hello"))
(with-fresh-applications (("/greeting" 'greeting :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greeting")
    (body-text b)))
;; ⇒ "Hello"
```

#### `render-component` `component` — generic function

Render `component` where it is embedded: through its
decorations, inside a halo when halos are on.

*Example:* A component that embeds others renders each with render-component and names them in children, so backtracking, AJAX and halos can find them.

```lisp
(defclass counter (component)
  ((label :initarg :label :reader counter-label)
   (count :initform 0 :accessor counter-count)))
(defmethod states ((self counter)) (list self))
(defmethod render ((self counter))
  (p () (text (counter-label self)) ": " (text (princ-to-string (counter-count self))) " "
    (anchor (:callback (lambda () (incf (counter-count self))))
      "more " (text (counter-label self)))))
(defclass tally (component)
  ((counters :initform (list (make-instance 'counter :label "gulls")
                             (make-instance 'counter :label "terns"))
             :reader tally-counters)))
(defmethod children ((self tally)) (tally-counters self))
(defmethod render ((self tally))
  (h1 () "Birds seen")
  (dolist (counter (tally-counters self))
    (render-component counter)))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tally")
    (click b "more terns")
    (click b "more terns")
    (body-text b)))
;; ⇒ "Birds seen gulls: 0 more gulls terns: 2 more terns"
```

#### `children` `component` — generic function

The components `component` renders.  Halos, update-root,
backtracking and AJAX lookups find components through this.

*Example:* A component that embeds others renders each with render-component and names them in children, so backtracking, AJAX and halos can find them.

```lisp
(defclass counter (component)
  ((label :initarg :label :reader counter-label)
   (count :initform 0 :accessor counter-count)))
(defmethod states ((self counter)) (list self))
(defmethod render ((self counter))
  (p () (text (counter-label self)) ": " (text (princ-to-string (counter-count self))) " "
    (anchor (:callback (lambda () (incf (counter-count self))))
      "more " (text (counter-label self)))))
(defclass tally (component)
  ((counters :initform (list (make-instance 'counter :label "gulls")
                             (make-instance 'counter :label "terns"))
             :reader tally-counters)))
(defmethod children ((self tally)) (tally-counters self))
(defmethod render ((self tally))
  (h1 () "Birds seen")
  (dolist (counter (tally-counters self))
    (render-component counter)))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tally")
    (click b "more terns")
    (click b "more terns")
    (body-text b)))
;; ⇒ "Birds seen gulls: 0 more gulls terns: 2 more terns"
```

#### `states` `component` — generic function

Objects whose slots are snapshotted after every action
and restored when the user goes back to an earlier page.  Return `component`
itself to make all its slots backtrack.

*Example:* Naming the component itself in states makes all its slots backtrack: going back to an earlier page and acting there starts from the state that page showed.

```lisp
(defclass score (component)
  ((points :initform 0 :accessor points)))
(defmethod states ((self score)) (list self))
(defmethod render ((self score))
  (p () "Points: " (text (princ-to-string (points self))))
  (anchor (:callback (lambda () (incf (points self)))) "Score"))
(with-fresh-applications (("/score" 'score :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/score")
    (click b "Score")
    (let ((one-point (browser-url b)))
      (click b "Score")
      (click b "Score")
      (back-to b one-point)
      (click b "Score")
      (body-text b))))
;; ⇒ "Points: 2 Score"
```

#### `update-root` `component root` — generic function

Contribute `component`'s title, stylesheets and scripts to
the `html-root` of the page.  Called on every visible component before the
page is written, parents first, so a child's title wins.  Call
`call-next-method` to keep `style` and `script`.

*Example:* A component fills in the page's head from update-root.  Calling the next method keeps what style and script give.

```lisp
(defclass tide-page (component) ())
(defmethod update-root ((self tide-page) root)
  (call-next-method)
  (setf (root-title root) "Tides")
  (add-head-meta root "description" "Why the sea comes and goes.")
  (add-head-meta root "og:title" "Tides")
  (add-head-link root "icon" "/favicon.svg" :type "image/svg+xml")
  (add-stylesheet root "/css/site.css")
  (add-style root "h1 { color: navy }")
  (add-script root "/js/charts.js"))
(defmethod render ((self tide-page))
  (h1 () "Tides"))
(with-fresh-applications (("/tides" 'tide-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (mapcar (lambda (html) (not (null (search html (browser-html b)))))
            '("<title>Tides</title>"
              "<meta name=\"description\" content=\"Why the sea comes and goes.\">"
              "<meta property=\"og:title\" content=\"Tides\">"
              "<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">"
              "<link rel=\"stylesheet\" href=\"/css/site.css\">"
              "h1 { color: navy }"
              "<script src=\"/js/charts.js\" defer"))))
;; ⇒ (T T T T T T T)
```

#### `style` `component` — generic function

CSS text this component adds to the page head, or `nil`.

*Example:* CSS a component needs goes in the page head; its JavaScript goes at the end of the body, with the page's script nonce.

```lisp
(defclass chart (component) ())
(defmethod style ((self chart)) ".chart { height: 10rem }")
(defmethod script ((self chart)) "console.log('chart drawn')")
(defmethod render ((self chart))
  (div (:class "chart")))
(with-fresh-applications (("/chart" 'chart :mode :deployment))
  (let* ((b (make-instance 'browser))
         (html (browser-html (visit b "/chart"))))
    (list (< (search ".chart { height: 10rem }" html) (search "</head>" html))
          (< (search "<body" html) (search "console.log('chart drawn')" html)))))
;; ⇒ (T T)
```

#### `script` `component` — generic function

JavaScript text this component adds to the page, or `nil`.

*Example:* CSS a component needs goes in the page head; its JavaScript goes at the end of the body, with the page's script nonce.

```lisp
(defclass chart (component) ())
(defmethod style ((self chart)) ".chart { height: 10rem }")
(defmethod script ((self chart)) "console.log('chart drawn')")
(defmethod render ((self chart))
  (div (:class "chart")))
(with-fresh-applications (("/chart" 'chart :mode :deployment))
  (let* ((b (make-instance 'browser))
         (html (browser-html (visit b "/chart"))))
    (list (< (search ".chart { height: 10rem }" html) (search "</head>" html))
          (< (search "<body" html) (search "console.log('chart drawn')" html)))))
;; ⇒ (T T)
```

#### `initial-request` `component request` — generic function

Called on the root component when its session starts,
with the request that started it.  A bookmarked URL is read back here with
`request-extra-path` and `request-parameter`.

*Example:* A page that can be bookmarked: update-url puts the tide table shown in the URL, and initial-request reads it back when a session starts from that URL.

```lisp
(defclass harbours (component)
  ((harbour :initform nil :accessor harbour)
   (metric :initform nil :accessor metric)))
(defmethod states ((self harbours)) (list self))
(defmethod update-url ((self harbours) url)
  (when (harbour self)
    (add-to-path url (harbour self)))
  (when (metric self)
    (add-parameter url "metric")))
(defmethod initial-request ((self harbours) request)
  (setf (harbour self) (first (request-extra-path))
        (metric self) (request-parameter-p "metric" request)))
(defmethod render ((self harbours))
  (p () "Tides for " (text (or (harbour self) "nowhere"))
    (text (if (metric self) " in metres. " " in feet. ")))
  (anchor (:callback (lambda () (setf (harbour self) "Dover"))) "Dover")
  (text " ")
  (anchor (:callback (lambda () (setf (metric self) t))) "Metric"))
(with-fresh-applications (("/tides" 'harbours :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (click b "Dover")
    (click b "Metric")
    (let* ((url (browser-url b))
           (bookmark (subseq url 0 (search "&_s=" url)))
           (later (make-instance 'browser)))
      (visit later bookmark)
      (list bookmark (body-text later)))))
;; ⇒ ("/tides/Dover?metric" "Tides for Dover in metres. Dover Metric")
```

#### `updatable-wrapper` `component` — generic function

The tag and extra attributes of the element an `updatable`
component is written inside: "div" and none by default.  A row of a list
returns "li"; a region whose updates should be announced adds
:aria-live "polite".

*Example:* An updatable component is written inside an element carrying its component-id (removed here, as it differs every run), so AJAX can replace it.  updatable-wrapper chooses that element.

```lisp
(defclass shopping-item (component updatable)
  ((name :initarg :name :reader item-name)))
(defmethod updatable-wrapper ((self shopping-item))
  (values "li" '(:aria-live "polite")))
(defmethod render ((self shopping-item))
  (text (item-name self)))
(let ((html (with-canvas-to-string ()
              (render-component (make-instance 'shopping-item :name "Milk")))))
  (cl-ppcre:regex-replace " id=\"[^\"]*\"" html ""))
;; ⇒ "<li class=\"lt-updatable\" aria-live=\"polite\">Milk</li>"
```

#### `update-url` `component url` — generic function

Add to URL, a `page-url`, whatever would let a bookmark of
this page come back to it.  Called on every visible component, parents
first; read it back in `initial-request` with `request-extra-path` and
`request-parameter`.

*Example:* A page that can be bookmarked: update-url puts the tide table shown in the URL, and initial-request reads it back when a session starts from that URL.

```lisp
(defclass harbours (component)
  ((harbour :initform nil :accessor harbour)
   (metric :initform nil :accessor metric)))
(defmethod states ((self harbours)) (list self))
(defmethod update-url ((self harbours) url)
  (when (harbour self)
    (add-to-path url (harbour self)))
  (when (metric self)
    (add-parameter url "metric")))
(defmethod initial-request ((self harbours) request)
  (setf (harbour self) (first (request-extra-path))
        (metric self) (request-parameter-p "metric" request)))
(defmethod render ((self harbours))
  (p () "Tides for " (text (or (harbour self) "nowhere"))
    (text (if (metric self) " in metres. " " in feet. ")))
  (anchor (:callback (lambda () (setf (harbour self) "Dover"))) "Dover")
  (text " ")
  (anchor (:callback (lambda () (setf (metric self) t))) "Metric"))
(with-fresh-applications (("/tides" 'harbours :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (click b "Dover")
    (click b "Metric")
    (let* ((url (browser-url b))
           (bookmark (subseq url 0 (search "&_s=" url)))
           (later (make-instance 'browser)))
      (visit later bookmark)
      (list bookmark (body-text later)))))
;; ⇒ ("/tides/Dover?metric" "Tides for Dover in metres. Dover Metric")
```

#### `page-url` — class

What `update-url` methods add to the URL of a page.

#### `page-url` `session continuation` — function

The URL of `continuation`: the application's path, what `update-url` methods
add, then the session and page keys.

*Example:* A page that can be bookmarked: update-url puts the tide table shown in the URL, and initial-request reads it back when a session starts from that URL.

```lisp
(defclass harbours (component)
  ((harbour :initform nil :accessor harbour)
   (metric :initform nil :accessor metric)))
(defmethod states ((self harbours)) (list self))
(defmethod update-url ((self harbours) url)
  (when (harbour self)
    (add-to-path url (harbour self)))
  (when (metric self)
    (add-parameter url "metric")))
(defmethod initial-request ((self harbours) request)
  (setf (harbour self) (first (request-extra-path))
        (metric self) (request-parameter-p "metric" request)))
(defmethod render ((self harbours))
  (p () "Tides for " (text (or (harbour self) "nowhere"))
    (text (if (metric self) " in metres. " " in feet. ")))
  (anchor (:callback (lambda () (setf (harbour self) "Dover"))) "Dover")
  (text " ")
  (anchor (:callback (lambda () (setf (metric self) t))) "Metric"))
(with-fresh-applications (("/tides" 'harbours :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (click b "Dover")
    (click b "Metric")
    (let* ((url (browser-url b))
           (bookmark (subseq url 0 (search "&_s=" url)))
           (later (make-instance 'browser)))
      (visit later bookmark)
      (list bookmark (body-text later)))))
;; ⇒ ("/tides/Dover?metric" "Tides for Dover in metres. Dover Metric")
```

#### `add-to-path` `url &rest segments` — function

Append `segments` (strings, or anything `princ` prints) to URL's path.

*Example:* A page that can be bookmarked: update-url puts the tide table shown in the URL, and initial-request reads it back when a session starts from that URL.

```lisp
(defclass harbours (component)
  ((harbour :initform nil :accessor harbour)
   (metric :initform nil :accessor metric)))
(defmethod states ((self harbours)) (list self))
(defmethod update-url ((self harbours) url)
  (when (harbour self)
    (add-to-path url (harbour self)))
  (when (metric self)
    (add-parameter url "metric")))
(defmethod initial-request ((self harbours) request)
  (setf (harbour self) (first (request-extra-path))
        (metric self) (request-parameter-p "metric" request)))
(defmethod render ((self harbours))
  (p () "Tides for " (text (or (harbour self) "nowhere"))
    (text (if (metric self) " in metres. " " in feet. ")))
  (anchor (:callback (lambda () (setf (harbour self) "Dover"))) "Dover")
  (text " ")
  (anchor (:callback (lambda () (setf (metric self) t))) "Metric"))
(with-fresh-applications (("/tides" 'harbours :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (click b "Dover")
    (click b "Metric")
    (let* ((url (browser-url b))
           (bookmark (subseq url 0 (search "&_s=" url)))
           (later (make-instance 'browser)))
      (visit later bookmark)
      (list bookmark (body-text later)))))
;; ⇒ ("/tides/Dover?metric" "Tides for Dover in metres. Dover Metric")
```

#### `add-parameter` `url key &optional value` — function

Add the query parameter `key` (with `value`, unless `nil`) to URL.

*Example:* A page that can be bookmarked: update-url puts the tide table shown in the URL, and initial-request reads it back when a session starts from that URL.

```lisp
(defclass harbours (component)
  ((harbour :initform nil :accessor harbour)
   (metric :initform nil :accessor metric)))
(defmethod states ((self harbours)) (list self))
(defmethod update-url ((self harbours) url)
  (when (harbour self)
    (add-to-path url (harbour self)))
  (when (metric self)
    (add-parameter url "metric")))
(defmethod initial-request ((self harbours) request)
  (setf (harbour self) (first (request-extra-path))
        (metric self) (request-parameter-p "metric" request)))
(defmethod render ((self harbours))
  (p () "Tides for " (text (or (harbour self) "nowhere"))
    (text (if (metric self) " in metres. " " in feet. ")))
  (anchor (:callback (lambda () (setf (harbour self) "Dover"))) "Dover")
  (text " ")
  (anchor (:callback (lambda () (setf (metric self) t))) "Metric"))
(with-fresh-applications (("/tides" 'harbours :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (click b "Dover")
    (click b "Metric")
    (let* ((url (browser-url b))
           (bookmark (subseq url 0 (search "&_s=" url)))
           (later (make-instance 'browser)))
      (visit later bookmark)
      (list bookmark (body-text later)))))
;; ⇒ ("/tides/Dover?metric" "Tides for Dover in metres. Dover Metric")
```

#### `url-path` `object` — generic function

Reads the path of a page-url.  Segments after the application's path, in order.

*Example:* What update-url methods have added so far.  Values are printed with princ, and a parameter may have no value.

```lisp
(let ((url (make-instance 'page-url)))
  (add-to-path url "harbours" 42)
  (add-parameter url "metric")
  (add-parameter url "sort" :name)
  (list (url-path url) (url-parameters url)))
;; ⇒ (("harbours" "42") (("metric") ("sort" . "NAME")))
```

#### `url-parameters` `object` — generic function

Reads the parameters of a page-url.  Alist of query parameters, in order.

*Example:* What update-url methods have added so far.  Values are printed with princ, and a parameter may have no value.

```lisp
(let ((url (make-instance 'page-url)))
  (add-to-path url "harbours" 42)
  (add-parameter url "metric")
  (add-parameter url "sort" :name)
  (list (url-path url) (url-parameters url)))
;; ⇒ (("harbours" "42") (("metric") ("sort" . "NAME")))
```

#### `request-extra-path` `&optional (app *application*) (request *request*)` — function

The decoded path segments of `request` after `app`'s path.

*Example:* A page that can be bookmarked: update-url puts the tide table shown in the URL, and initial-request reads it back when a session starts from that URL.

```lisp
(defclass harbours (component)
  ((harbour :initform nil :accessor harbour)
   (metric :initform nil :accessor metric)))
(defmethod states ((self harbours)) (list self))
(defmethod update-url ((self harbours) url)
  (when (harbour self)
    (add-to-path url (harbour self)))
  (when (metric self)
    (add-parameter url "metric")))
(defmethod initial-request ((self harbours) request)
  (setf (harbour self) (first (request-extra-path))
        (metric self) (request-parameter-p "metric" request)))
(defmethod render ((self harbours))
  (p () "Tides for " (text (or (harbour self) "nowhere"))
    (text (if (metric self) " in metres. " " in feet. ")))
  (anchor (:callback (lambda () (setf (harbour self) "Dover"))) "Dover")
  (text " ")
  (anchor (:callback (lambda () (setf (metric self) t))) "Metric"))
(with-fresh-applications (("/tides" 'harbours :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (click b "Dover")
    (click b "Metric")
    (let* ((url (browser-url b))
           (bookmark (subseq url 0 (search "&_s=" url)))
           (later (make-instance 'browser)))
      (visit later bookmark)
      (list bookmark (body-text later)))))
;; ⇒ ("/tides/Dover?metric" "Tides for Dover in metres. Dover Metric")
```

#### `call` `self other` — function

Show `other` in place of `self` and return what it answers.

Inside a flow (see `define-flow`) this reads as a blocking call: the rest of
the flow is captured with cl-cont and resumed by `answer`.  Elsewhere, such
as a callback, it shows `other` and returns at once, discarding the answer;
use `show` with `:on-answer` there to act on it.

*Example:* Outside a flow, call shows the other component in place of the caller and returns at once; when that component answers, the caller comes back.

```lisp
(defclass inbox (component) ())
(defmethod render ((self inbox))
  (p () "Inbox")
  (anchor (:callback (lambda ()
                       (call self (make-instance 'message-dialog :message "No new mail."))))
    "Check mail"))
(with-fresh-applications (("/inbox" 'inbox :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/inbox")
    (click b "Check mail")
    (let ((dialog (body-text b)))
      (press b "OK")                    ; the message dialog answers T
      (list dialog (body-text b)))))
;; ⇒ ("No new mail. OK" "Inbox Check mail")
```

#### `answer` `self &optional value` — function

Return control, with `value`, to the component that called `self`.
Validation decorations on `self` may refuse the answer.  True when a caller
was given `value`; `nil` when a validation refused it or nothing called `self`.
Signals `render-phase-error` while rendering.

*Example:* Outside a flow, call shows the other component in place of the caller and returns at once; when that component answers, the caller comes back.

```lisp
(defclass inbox (component) ())
(defmethod render ((self inbox))
  (p () "Inbox")
  (anchor (:callback (lambda ()
                       (call self (make-instance 'message-dialog :message "No new mail."))))
    "Check mail"))
(with-fresh-applications (("/inbox" 'inbox :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/inbox")
    (click b "Check mail")
    (let ((dialog (body-text b)))
      (press b "OK")                    ; the message dialog answers T
      (list dialog (body-text b)))))
;; ⇒ ("No new mail. OK" "Inbox Check mail")
```

*Example:* A component answers a value; show hands it to `on-answer`, which is how a callback acts on an answer.

```lisp
(defclass colour-picker (component) ())
(defmethod render ((self colour-picker))
  (ul ()
    (dolist (colour '(:red :green :blue))
      (let ((colour colour))
        (li () (anchor (:callback (lambda () (answer self colour)))
                 (text (string-downcase colour))))))))
(defclass boat (component)
  ((colour :initform :white :accessor boat-colour)))
(defmethod states ((self boat)) (list self))
(defmethod render ((self boat))
  (p () "The boat is " (text (string-downcase (boat-colour self))) ". ")
  (anchor (:callback (lambda ()
                       (show self (make-instance 'colour-picker)
                             :on-answer (lambda (colour) (setf (boat-colour self) colour)))))
    "Paint it"))
(with-fresh-applications (("/boat" 'boat :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/boat")
    (click b "Paint it")
    (let ((picker (body-text b)))
      (click b "green")
      (list picker (body-text b)))))
;; ⇒ ("red green blue" "The boat is green. Paint it")
```

#### `show` `self other &key on-answer` — function

Show `other` in place of `self` until `other` answers, then call `on-answer`
(when given) with the answer.  Returns `other` at once: the non-blocking form
of `call`.  Signals `render-phase-error` while rendering.

*Example:* A component answers a value; show hands it to `on-answer`, which is how a callback acts on an answer.

```lisp
(defclass colour-picker (component) ())
(defmethod render ((self colour-picker))
  (ul ()
    (dolist (colour '(:red :green :blue))
      (let ((colour colour))
        (li () (anchor (:callback (lambda () (answer self colour)))
                 (text (string-downcase colour))))))))
(defclass boat (component)
  ((colour :initform :white :accessor boat-colour)))
(defmethod states ((self boat)) (list self))
(defmethod render ((self boat))
  (p () "The boat is " (text (string-downcase (boat-colour self))) ". ")
  (anchor (:callback (lambda ()
                       (show self (make-instance 'colour-picker)
                             :on-answer (lambda (colour) (setf (boat-colour self) colour)))))
    "Paint it"))
(with-fresh-applications (("/boat" 'boat :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/boat")
    (click b "Paint it")
    (let ((picker (body-text b)))
      (click b "green")
      (list picker (body-text b)))))
;; ⇒ ("red green blue" "The boat is green. Paint it")
```

#### `home` `self` — function

Dismiss whatever `self` has called, without answering, so `self` shows
itself again.  Signals `render-phase-error` while rendering.

*Example:* While a component has shown another, that one is active in its place and is what it shows; home dismisses it without an answer.

```lisp
(let* ((page (make-instance 'component))
       (dialog (make-instance 'confirm-dialog :message "Sure?")))
  (show page dialog)
  (list (eq (active-component page) dialog)
        (equal (visible-children page) (list dialog))
        (progn (home page)
               (eq (active-component page) page))))
;; ⇒ (T T T)
```

#### `visible-children` `component` — function

The components `component` shows now: its delegate when it has called
another, otherwise its `children`; and any its decorations show.

*Example:* While a component has shown another, that one is active in its place and is what it shows; home dismisses it without an answer.

```lisp
(let* ((page (make-instance 'component))
       (dialog (make-instance 'confirm-dialog :message "Sure?")))
  (show page dialog)
  (list (eq (active-component page) dialog)
        (equal (visible-children page) (list dialog))
        (progn (home page)
               (eq (active-component page) page))))
;; ⇒ (T T T)
```

#### `active-component` `component` — function

The component actually showing in `component`'s place.

*Example:* While a component has shown another, that one is active in its place and is what it shows; home dismisses it without an answer.

```lisp
(let* ((page (make-instance 'component))
       (dialog (make-instance 'confirm-dialog :message "Sure?")))
  (show page dialog)
  (list (eq (active-component page) dialog)
        (equal (visible-children page) (list dialog))
        (progn (home page)
               (eq (active-component page) page))))
;; ⇒ (T T T)
```

#### `html-root` — class

The document head a page collects from `update-root`: title, meta
tags, links, stylesheets and scripts.

*Example:* A component fills in the page's head from update-root.  Calling the next method keeps what style and script give.

```lisp
(defclass tide-page (component) ())
(defmethod update-root ((self tide-page) root)
  (call-next-method)
  (setf (root-title root) "Tides")
  (add-head-meta root "description" "Why the sea comes and goes.")
  (add-head-meta root "og:title" "Tides")
  (add-head-link root "icon" "/favicon.svg" :type "image/svg+xml")
  (add-stylesheet root "/css/site.css")
  (add-style root "h1 { color: navy }")
  (add-script root "/js/charts.js"))
(defmethod render ((self tide-page))
  (h1 () "Tides"))
(with-fresh-applications (("/tides" 'tide-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (mapcar (lambda (html) (not (null (search html (browser-html b)))))
            '("<title>Tides</title>"
              "<meta name=\"description\" content=\"Why the sea comes and goes.\">"
              "<meta property=\"og:title\" content=\"Tides\">"
              "<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">"
              "<link rel=\"stylesheet\" href=\"/css/site.css\">"
              "h1 { color: navy }"
              "<script src=\"/js/charts.js\" defer"))))
;; ⇒ (T T T T T T T)
```

#### `root-title` `object` — generic function

Reads the title of a html-root.  The page's title: the application's title, or its path, unless a component sets it.

*Example:* A component fills in the page's head from update-root.  Calling the next method keeps what style and script give.

```lisp
(defclass tide-page (component) ())
(defmethod update-root ((self tide-page) root)
  (call-next-method)
  (setf (root-title root) "Tides")
  (add-head-meta root "description" "Why the sea comes and goes.")
  (add-head-meta root "og:title" "Tides")
  (add-head-link root "icon" "/favicon.svg" :type "image/svg+xml")
  (add-stylesheet root "/css/site.css")
  (add-style root "h1 { color: navy }")
  (add-script root "/js/charts.js"))
(defmethod render ((self tide-page))
  (h1 () "Tides"))
(with-fresh-applications (("/tides" 'tide-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (mapcar (lambda (html) (not (null (search html (browser-html b)))))
            '("<title>Tides</title>"
              "<meta name=\"description\" content=\"Why the sea comes and goes.\">"
              "<meta property=\"og:title\" content=\"Tides\">"
              "<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">"
              "<link rel=\"stylesheet\" href=\"/css/site.css\">"
              "h1 { color: navy }"
              "<script src=\"/js/charts.js\" defer"))))
;; ⇒ (T T T T T T T)
```

#### `add-stylesheet` `root url` — function

Link the stylesheet at URL from the page.

*Example:* A component fills in the page's head from update-root.  Calling the next method keeps what style and script give.

```lisp
(defclass tide-page (component) ())
(defmethod update-root ((self tide-page) root)
  (call-next-method)
  (setf (root-title root) "Tides")
  (add-head-meta root "description" "Why the sea comes and goes.")
  (add-head-meta root "og:title" "Tides")
  (add-head-link root "icon" "/favicon.svg" :type "image/svg+xml")
  (add-stylesheet root "/css/site.css")
  (add-style root "h1 { color: navy }")
  (add-script root "/js/charts.js"))
(defmethod render ((self tide-page))
  (h1 () "Tides"))
(with-fresh-applications (("/tides" 'tide-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (mapcar (lambda (html) (not (null (search html (browser-html b)))))
            '("<title>Tides</title>"
              "<meta name=\"description\" content=\"Why the sea comes and goes.\">"
              "<meta property=\"og:title\" content=\"Tides\">"
              "<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">"
              "<link rel=\"stylesheet\" href=\"/css/site.css\">"
              "h1 { color: navy }"
              "<script src=\"/js/charts.js\" defer"))))
;; ⇒ (T T T T T T T)
```

#### `add-script` `root url` — function

Load the script at URL in the page.

*Example:* A component fills in the page's head from update-root.  Calling the next method keeps what style and script give.

```lisp
(defclass tide-page (component) ())
(defmethod update-root ((self tide-page) root)
  (call-next-method)
  (setf (root-title root) "Tides")
  (add-head-meta root "description" "Why the sea comes and goes.")
  (add-head-meta root "og:title" "Tides")
  (add-head-link root "icon" "/favicon.svg" :type "image/svg+xml")
  (add-stylesheet root "/css/site.css")
  (add-style root "h1 { color: navy }")
  (add-script root "/js/charts.js"))
(defmethod render ((self tide-page))
  (h1 () "Tides"))
(with-fresh-applications (("/tides" 'tide-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (mapcar (lambda (html) (not (null (search html (browser-html b)))))
            '("<title>Tides</title>"
              "<meta name=\"description\" content=\"Why the sea comes and goes.\">"
              "<meta property=\"og:title\" content=\"Tides\">"
              "<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">"
              "<link rel=\"stylesheet\" href=\"/css/site.css\">"
              "h1 { color: navy }"
              "<script src=\"/js/charts.js\" defer"))))
;; ⇒ (T T T T T T T)
```

#### `add-style` `root css` — function

Add the CSS text CSS to the page head.

*Example:* A component fills in the page's head from update-root.  Calling the next method keeps what style and script give.

```lisp
(defclass tide-page (component) ())
(defmethod update-root ((self tide-page) root)
  (call-next-method)
  (setf (root-title root) "Tides")
  (add-head-meta root "description" "Why the sea comes and goes.")
  (add-head-meta root "og:title" "Tides")
  (add-head-link root "icon" "/favicon.svg" :type "image/svg+xml")
  (add-stylesheet root "/css/site.css")
  (add-style root "h1 { color: navy }")
  (add-script root "/js/charts.js"))
(defmethod render ((self tide-page))
  (h1 () "Tides"))
(with-fresh-applications (("/tides" 'tide-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (mapcar (lambda (html) (not (null (search html (browser-html b)))))
            '("<title>Tides</title>"
              "<meta name=\"description\" content=\"Why the sea comes and goes.\">"
              "<meta property=\"og:title\" content=\"Tides\">"
              "<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">"
              "<link rel=\"stylesheet\" href=\"/css/site.css\">"
              "h1 { color: navy }"
              "<script src=\"/js/charts.js\" defer"))))
;; ⇒ (T T T T T T T)
```

#### `add-head-meta` `root key content` — function

Add a meta tag `key` with `content` to the page head: description, theme-color,
og:title, twitter:card and the like.  Open Graph keys (og:..., article:...)
are written as property=, the rest as name=.  A later call with the same
`key` replaces the earlier one, so a child component can override its parent.

*Example:* A component fills in the page's head from update-root.  Calling the next method keeps what style and script give.

```lisp
(defclass tide-page (component) ())
(defmethod update-root ((self tide-page) root)
  (call-next-method)
  (setf (root-title root) "Tides")
  (add-head-meta root "description" "Why the sea comes and goes.")
  (add-head-meta root "og:title" "Tides")
  (add-head-link root "icon" "/favicon.svg" :type "image/svg+xml")
  (add-stylesheet root "/css/site.css")
  (add-style root "h1 { color: navy }")
  (add-script root "/js/charts.js"))
(defmethod render ((self tide-page))
  (h1 () "Tides"))
(with-fresh-applications (("/tides" 'tide-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (mapcar (lambda (html) (not (null (search html (browser-html b)))))
            '("<title>Tides</title>"
              "<meta name=\"description\" content=\"Why the sea comes and goes.\">"
              "<meta property=\"og:title\" content=\"Tides\">"
              "<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">"
              "<link rel=\"stylesheet\" href=\"/css/site.css\">"
              "h1 { color: navy }"
              "<script src=\"/js/charts.js\" defer"))))
;; ⇒ (T T T T T T T)
```

#### `add-head-link` `root rel href &rest attributes` — function

Add a link element (rel `rel`, href `href`) to the page head, with `attributes`, a plist of
keywords and strings such as :type "image/svg+xml" or :sizes "180x180".
The same `rel` and `href` are added once.  For stylesheets use `add-stylesheet`.

*Example:* A component fills in the page's head from update-root.  Calling the next method keeps what style and script give.

```lisp
(defclass tide-page (component) ())
(defmethod update-root ((self tide-page) root)
  (call-next-method)
  (setf (root-title root) "Tides")
  (add-head-meta root "description" "Why the sea comes and goes.")
  (add-head-meta root "og:title" "Tides")
  (add-head-link root "icon" "/favicon.svg" :type "image/svg+xml")
  (add-stylesheet root "/css/site.css")
  (add-style root "h1 { color: navy }")
  (add-script root "/js/charts.js"))
(defmethod render ((self tide-page))
  (h1 () "Tides"))
(with-fresh-applications (("/tides" 'tide-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (mapcar (lambda (html) (not (null (search html (browser-html b)))))
            '("<title>Tides</title>"
              "<meta name=\"description\" content=\"Why the sea comes and goes.\">"
              "<meta property=\"og:title\" content=\"Tides\">"
              "<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">"
              "<link rel=\"stylesheet\" href=\"/css/site.css\">"
              "h1 { color: navy }"
              "<script src=\"/js/charts.js\" defer"))))
;; ⇒ (T T T T T T T)
```

### Decorations

#### `decoration` — class

Wraps a component's rendering or intercepts its answers.
Specialise `render-decoration` and call `render-inner` for what it wraps.

*Example:* A decoration wraps what it decorates: render-decoration writes its own HTML and calls render-inner where the component goes.

```lisp
(defclass framed (decoration)
  ((caption :initarg :caption :reader frame-caption)))
(defmethod render-decoration ((self framed) component)
  (declare (ignore component))
  (section (:class "frame")
    (h2 () (text (frame-caption self)))
    (render-inner)))
(defclass forecast (component) ())
(defmethod render ((self forecast))
  (p () "Fair, then rain."))
(let ((c (make-instance 'forecast)))
  (add-decoration c (make-instance 'framed :caption "Shipping forecast"))
  (with-canvas-to-string () (render-component c)))
;; ⇒ "<section class=\"frame\"><h2>Shipping forecast</h2><p>Fair, then rain.</p></section>"
```

#### `add-decoration` `component decoration` — function

Add `decoration` to `component`, outermost among those of its kind.
Globals come first, then any delegation, then locals.  Returns `decoration`.

*Example:* A decoration wraps what it decorates: render-decoration writes its own HTML and calls render-inner where the component goes.

```lisp
(defclass framed (decoration)
  ((caption :initarg :caption :reader frame-caption)))
(defmethod render-decoration ((self framed) component)
  (declare (ignore component))
  (section (:class "frame")
    (h2 () (text (frame-caption self)))
    (render-inner)))
(defclass forecast (component) ())
(defmethod render ((self forecast))
  (p () "Fair, then rain."))
(let ((c (make-instance 'forecast)))
  (add-decoration c (make-instance 'framed :caption "Shipping forecast"))
  (with-canvas-to-string () (render-component c)))
;; ⇒ "<section class=\"frame\"><h2>Shipping forecast</h2><p>Fair, then rain.</p></section>"
```

#### `remove-decoration` `component decoration` — function

Take `decoration` off `component`.

*Example:* Showing another component decorates both: the caller gets a delegation, which renders the other in its place, and the other an answer-handler, which remembers the caller.  Answering takes both away.

```lisp
(let ((page (make-instance 'component))
      (dialog (make-instance 'confirm-dialog :message "Sure?"))
      (heading (make-instance 'message-decoration :message "Settings")))
  (add-decoration page heading)
  (show page dialog)
  (let ((while-shown (list (mapcar #'type-of (decorations page))
                           (mapcar #'type-of (decorations dialog)))))
    (answer dialog t)
    (remove-decoration page heading)
    (list while-shown (decorations page) (decorations dialog))))
;; ⇒ (((DELEGATION MESSAGE-DECORATION) (ANSWER-HANDLER)) NIL NIL)
```

#### `decorations` `object` — generic function

Reads the decorations of a component.  Outermost first.  Replaced, never mutated, so
backtracking can snapshot it as a value.

*Example:* Showing another component decorates both: the caller gets a delegation, which renders the other in its place, and the other an answer-handler, which remembers the caller.  Answering takes both away.

```lisp
(let ((page (make-instance 'component))
      (dialog (make-instance 'confirm-dialog :message "Sure?"))
      (heading (make-instance 'message-decoration :message "Settings")))
  (add-decoration page heading)
  (show page dialog)
  (let ((while-shown (list (mapcar #'type-of (decorations page))
                           (mapcar #'type-of (decorations dialog)))))
    (answer dialog t)
    (remove-decoration page heading)
    (list while-shown (decorations page) (decorations dialog))))
;; ⇒ (((DELEGATION MESSAGE-DECORATION) (ANSWER-HANDLER)) NIL NIL)
```

#### `delegation` — class

Shows the delegate in place of the decorated component.

*Example:* Showing another component decorates both: the caller gets a delegation, which renders the other in its place, and the other an answer-handler, which remembers the caller.  Answering takes both away.

```lisp
(let ((page (make-instance 'component))
      (dialog (make-instance 'confirm-dialog :message "Sure?"))
      (heading (make-instance 'message-decoration :message "Settings")))
  (add-decoration page heading)
  (show page dialog)
  (let ((while-shown (list (mapcar #'type-of (decorations page))
                           (mapcar #'type-of (decorations dialog)))))
    (answer dialog t)
    (remove-decoration page heading)
    (list while-shown (decorations page) (decorations dialog))))
;; ⇒ (((DELEGATION MESSAGE-DECORATION) (ANSWER-HANDLER)) NIL NIL)
```

#### `answer-handler` — class

Remembers who called a component and what to do with
its answer.

*Example:* Showing another component decorates both: the caller gets a delegation, which renders the other in its place, and the other an answer-handler, which remembers the caller.  Answering takes both away.

```lisp
(let ((page (make-instance 'component))
      (dialog (make-instance 'confirm-dialog :message "Sure?"))
      (heading (make-instance 'message-decoration :message "Settings")))
  (add-decoration page heading)
  (show page dialog)
  (let ((while-shown (list (mapcar #'type-of (decorations page))
                           (mapcar #'type-of (decorations dialog)))))
    (answer dialog t)
    (remove-decoration page heading)
    (list while-shown (decorations page) (decorations dialog))))
;; ⇒ (((DELEGATION MESSAGE-DECORATION) (ANSWER-HANDLER)) NIL NIL)
```

#### `message-decoration` — class

A heading above the component: its `:message`, in an h3.

*Example:* A heading above the component, from :message.

```lisp
(defclass tide-table (component) ())
(defmethod render ((self tide-table))
  (p () "High water 06:12"))
(let ((c (make-instance 'tide-table)))
  (add-decoration c (make-instance 'message-decoration :message "Dover"))
  (with-canvas-to-string () (render-component c)))
;; ⇒ "<h3 class=\"lt-message\">Dover</h3><p>High water 06:12</p>"
```

#### `form-decoration` — class

Puts the component in a form with a row of `:buttons`, the
way Seaside's WAFormDecoration does.  The default is one OK button
answering `:ok`.

*Example:* form-decoration puts the component in a form with :buttons, (label . action) pairs: a function action is called with the component, any other is answered.  validate-with makes answers pass a check first; a refusal shows its message.

```lisp
(defclass name-editor (component)
  ((name :initform "" :accessor editor-name)))
(defmethod render ((self name-editor))
  (text-input (:id "name" :value (editor-name self)
               :callback (lambda (value) (setf (editor-name self) value)))))
(defun make-name-editor ()
  (let ((editor (make-instance 'name-editor)))
    (add-decoration editor (make-instance 'form-decoration
                                          :buttons `(("Save" . ,(lambda (e) (answer e (editor-name e))))
                                                     ("Cancel" . nil))))
    (validate-with editor (lambda (name)
                            (when (equal name "") "A name, please.")))))
(defclass crew-list (component)
  ((crew :initform '() :accessor crew)))
(defmethod states ((self crew-list)) (list self))
(defmethod render ((self crew-list))
  (p () "Crew: " (text (format nil "~{~A~^, ~}" (crew self))))
  (anchor (:callback (lambda ()
                       (show self (make-name-editor)
                             :on-answer (lambda (name) (when name (push name (crew self)))))))
    "Add"))
(with-fresh-applications (("/crew" 'crew-list :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/crew")
    (click b "Add")
    (press b "Save")
    (let ((refused (body-text b)))
      (fill-in b "name" "Ada")
      (press b "Save")
      (list refused (body-text b)))))
;; ⇒ ("A name, please. Save Cancel" "Crew: Ada Add")
```

#### `validation-decoration` — class

Refuses answers the validator rejects and shows why.

*Example:* form-decoration puts the component in a form with :buttons, (label . action) pairs: a function action is called with the component, any other is answered.  validate-with makes answers pass a check first; a refusal shows its message.

```lisp
(defclass name-editor (component)
  ((name :initform "" :accessor editor-name)))
(defmethod render ((self name-editor))
  (text-input (:id "name" :value (editor-name self)
               :callback (lambda (value) (setf (editor-name self) value)))))
(defun make-name-editor ()
  (let ((editor (make-instance 'name-editor)))
    (add-decoration editor (make-instance 'form-decoration
                                          :buttons `(("Save" . ,(lambda (e) (answer e (editor-name e))))
                                                     ("Cancel" . nil))))
    (validate-with editor (lambda (name)
                            (when (equal name "") "A name, please.")))))
(defclass crew-list (component)
  ((crew :initform '() :accessor crew)))
(defmethod states ((self crew-list)) (list self))
(defmethod render ((self crew-list))
  (p () "Crew: " (text (format nil "~{~A~^, ~}" (crew self))))
  (anchor (:callback (lambda ()
                       (show self (make-name-editor)
                             :on-answer (lambda (name) (when name (push name (crew self)))))))
    "Add"))
(with-fresh-applications (("/crew" 'crew-list :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/crew")
    (click b "Add")
    (press b "Save")
    (let ((refused (body-text b)))
      (fill-in b "name" "Ada")
      (press b "Save")
      (list refused (body-text b)))))
;; ⇒ ("A name, please. Save Cancel" "Crew: Ada Add")
```

#### `validate-with` `component validator` — function

Answers from `component` must first pass `validator`, a function of the
answer returning `nil` to accept or an error message to refuse.  The message
is shown above `component` until an answer passes.  Returns `component`.

*Example:* form-decoration puts the component in a form with :buttons, (label . action) pairs: a function action is called with the component, any other is answered.  validate-with makes answers pass a check first; a refusal shows its message.

```lisp
(defclass name-editor (component)
  ((name :initform "" :accessor editor-name)))
(defmethod render ((self name-editor))
  (text-input (:id "name" :value (editor-name self)
               :callback (lambda (value) (setf (editor-name self) value)))))
(defun make-name-editor ()
  (let ((editor (make-instance 'name-editor)))
    (add-decoration editor (make-instance 'form-decoration
                                          :buttons `(("Save" . ,(lambda (e) (answer e (editor-name e))))
                                                     ("Cancel" . nil))))
    (validate-with editor (lambda (name)
                            (when (equal name "") "A name, please.")))))
(defclass crew-list (component)
  ((crew :initform '() :accessor crew)))
(defmethod states ((self crew-list)) (list self))
(defmethod render ((self crew-list))
  (p () "Crew: " (text (format nil "~{~A~^, ~}" (crew self))))
  (anchor (:callback (lambda ()
                       (show self (make-name-editor)
                             :on-answer (lambda (name) (when name (push name (crew self)))))))
    "Add"))
(with-fresh-applications (("/crew" 'crew-list :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/crew")
    (click b "Add")
    (press b "Save")
    (let ((refused (body-text b)))
      (fill-in b "name" "Ada")
      (press b "Save")
      (list refused (body-text b)))))
;; ⇒ ("A name, please. Save Cancel" "Crew: Ada Add")
```

#### `render-inner` — function

Render whatever the current decoration wraps.

*Example:* A decoration wraps what it decorates: render-decoration writes its own HTML and calls render-inner where the component goes.

```lisp
(defclass framed (decoration)
  ((caption :initarg :caption :reader frame-caption)))
(defmethod render-decoration ((self framed) component)
  (declare (ignore component))
  (section (:class "frame")
    (h2 () (text (frame-caption self)))
    (render-inner)))
(defclass forecast (component) ())
(defmethod render ((self forecast))
  (p () "Fair, then rain."))
(let ((c (make-instance 'forecast)))
  (add-decoration c (make-instance 'framed :caption "Shipping forecast"))
  (with-canvas-to-string () (render-component c)))
;; ⇒ "<section class=\"frame\"><h2>Shipping forecast</h2><p>Fair, then rain.</p></section>"
```

#### `render-decoration` `decoration component` — generic function

Render `decoration` around `component`; `render-inner` renders
the rest of the chain.

*Example:* A decoration wraps what it decorates: render-decoration writes its own HTML and calls render-inner where the component goes.

```lisp
(defclass framed (decoration)
  ((caption :initarg :caption :reader frame-caption)))
(defmethod render-decoration ((self framed) component)
  (declare (ignore component))
  (section (:class "frame")
    (h2 () (text (frame-caption self)))
    (render-inner)))
(defclass forecast (component) ())
(defmethod render ((self forecast))
  (p () "Fair, then rain."))
(let ((c (make-instance 'forecast)))
  (add-decoration c (make-instance 'framed :caption "Shipping forecast"))
  (with-canvas-to-string () (render-component c)))
;; ⇒ "<section class=\"frame\"><h2>Shipping forecast</h2><p>Fair, then rain.</p></section>"
```

#### `decoration-kind` `decoration` — generic function

`:global` decorations sit outside a delegation and so stay
visible while another component is shown in their owner's place; `:local`
ones, the default, sit inside it.  A `delegation`'s kind is `:delegation`.

*Example:* A :global decoration sits outside the delegation, so it stays on the page while its component shows another; a :local one is replaced with the component.

```lisp
(defclass site-frame (decoration) ())
(defmethod decoration-kind ((self site-frame)) :global)
(defmethod render-decoration ((self site-frame) component)
  (declare (ignore component))
  (header () "Harbour office")
  (render-inner))
(defclass desk (component) ())
(defmethod initialize-instance :after ((self desk) &key)
  (add-decoration self (make-instance 'site-frame))
  (add-decoration self (make-instance 'message-decoration :message "Front desk")))
(defmethod render ((self desk))
  (anchor (:callback (lambda () (call self (make-instance 'message-dialog :message "Closed for lunch."))))
    "Ring the bell"))
(with-fresh-applications (("/desk" 'desk :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/desk")
    (let ((before (body-text b)))
      (click b "Ring the bell")
      (list before (body-text b)))))
;; ⇒ ("Harbour office Front desk Ring the bell" "Harbour office Closed for lunch. OK")
```

#### `decoration-children` `decoration` — generic function

Components `decoration` shows besides what it wraps (a
modal dialog, say).

*Example:* A decoration that renders a component of its own names it in decoration-children, so the component is visible: its state backtracks and AJAX can find it.

```lisp
(defclass tip-counter (component)
  ((tips :initform 0 :accessor tips)))
(defmethod states ((self tip-counter)) (list self))
(defmethod render ((self tip-counter))
  (aside () (text (format nil "~D tips " (tips self)))
    (anchor (:callback (lambda () (incf (tips self)))) "Tip")))
(defclass tip-jar (decoration)
  ((counter :initform (make-instance 'tip-counter) :reader counter)))
(defmethod decoration-children ((self tip-jar))
  (list (counter self)))
(defmethod render-decoration ((self tip-jar) component)
  (declare (ignore component))
  (render-inner)
  (render-component (counter self)))
(defclass busker (component) ())
(defmethod initialize-instance :after ((self busker) &key)
  (add-decoration self (make-instance 'tip-jar)))
(defmethod render ((self busker))
  (p () "A song."))
(with-fresh-applications (("/busker" 'busker :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/busker")
    (let ((none (browser-url b)))
      (click b "Tip")
      (click b "Tip")
      (let ((two (body-text b)))
        (back-to b none)
        (list two (body-text b))))))
;; ⇒ ("A song. 2 tips Tip" "A song. 0 tips Tip")
```

#### `updatable` — class

Mixin for components AJAX can re-render: each is written
inside an element carrying its `component-id`.

*Example:* An updatable component is written inside an element carrying its component-id (removed here, as it differs every run), so AJAX can replace it.  updatable-wrapper chooses that element.

```lisp
(defclass shopping-item (component updatable)
  ((name :initarg :name :reader item-name)))
(defmethod updatable-wrapper ((self shopping-item))
  (values "li" '(:aria-live "polite")))
(defmethod render ((self shopping-item))
  (text (item-name self)))
(let ((html (with-canvas-to-string ()
              (render-component (make-instance 'shopping-item :name "Milk")))))
  (cl-ppcre:regex-replace " id=\"[^\"]*\"" html ""))
;; ⇒ "<li class=\"lt-updatable\" aria-live=\"polite\">Milk</li>"
```

#### `show-modal` `other &key on-answer (closable t) title` — function

Show `other` in a dialog over the whole page until it answers, then call
`on-answer` with the answer.  `closable` adds a close button (and Esc), which
answers `nil`; `title` names the dialog for screen readers.  Use it during a
request: the dialog covers `*session*`'s root.  Returns `other` at once.

*Example:* A dialog over the page, which stays behind it, inert.  The close button (×) answers `nil`; :closable nil leaves it out.

```lisp
(defclass moorings (component)
  ((booked :initform nil :accessor booked)))
(defmethod states ((self moorings)) (list self))
(defmethod render ((self moorings))
  (p () "Booked: " (text (if (booked self) "yes" "no")))
  (anchor (:callback (lambda ()
                       (show-modal (make-instance 'confirm-dialog :message "Book a mooring?")
                                   :title "Booking"
                                   :on-answer (lambda (yes) (setf (booked self) yes)))))
    "Book"))
(with-fresh-applications (("/moorings" 'moorings :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/moorings")
    (click b "Book")
    (let ((with-dialog (body-text b)))
      (press b "Yes")
      (list with-dialog (body-text b)))))
;; ⇒ ("Booked: no Book × Book a mooring? Yes No" "Booked: yes Book")
```

#### `call-modal` `&rest args` — function

Show `other` in a dialog over the page and return what it answers; a
blocking call inside a flow, like `call`.  The optional second argument,
`title`, names the dialog for screen readers.  See `show-modal`.

*Example:* Inside a flow, call-modal waits for the dialog's answer like call.

```lisp
(defclass harbour-dues (task) ())
(define-flow harbour-dues (self)
  (if (call-modal (make-instance 'confirm-dialog :message "Pay the dues?") "Dues")
      (inform self "Paid.")
      (inform self "Not paid.")))
(with-fresh-applications (("/dues" 'harbour-dues :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/dues")
    (let ((modal (not (null (search "<dialog" (browser-html b))))))
      (press b "Yes")
      (list modal (body-text b)))))
;; ⇒ (T "Paid. OK")
```

#### `modal-decoration` — class

Shows a component over the page, which stays visible
behind it but cannot be used until the dialog answers.

*Example:* A dialog over the page, which stays behind it, inert.  The close button (×) answers `nil`; :closable nil leaves it out.

```lisp
(defclass moorings (component)
  ((booked :initform nil :accessor booked)))
(defmethod states ((self moorings)) (list self))
(defmethod render ((self moorings))
  (p () "Booked: " (text (if (booked self) "yes" "no")))
  (anchor (:callback (lambda ()
                       (show-modal (make-instance 'confirm-dialog :message "Book a mooring?")
                                   :title "Booking"
                                   :on-answer (lambda (yes) (setf (booked self) yes)))))
    "Book"))
(with-fresh-applications (("/moorings" 'moorings :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/moorings")
    (click b "Book")
    (let ((with-dialog (body-text b)))
      (press b "Yes")
      (list with-dialog (body-text b)))))
;; ⇒ ("Booked: no Book × Book a mooring? Yes No" "Booked: yes Book")
```

#### `toast` `message &key (kind :info) (session *session*)` — function

Show `message` briefly at the corner of `session`'s page: on its next page or
AJAX response, or at once on pages with a push stream.  `kind` is `:info`,
`:success` or `:error`.

*Example:* A short message on the next page (or AJAX response), shown by littoral.js at the corner of the page.

```lisp
(defclass logbook (component) ())
(defmethod render ((self logbook))
  (anchor (:callback (lambda () (toast "Entry saved." :kind :success))) "Save"))
(with-fresh-applications (("/log" 'logbook :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/log")
    (click b "Save")
    (not (null (search "<div class=\"lt-toast lt-toast-success\">Entry saved.</div>"
                       (browser-html b))))))
;; ⇒ T
```

### Dialogs

#### `message-dialog` — class

Shows its `:message` with an OK button; answers T.

*Example:* In a flow, confirm waits for Yes (T) or No (`nil`), and inform for OK.  They show a confirm-dialog and a message-dialog.

```lisp
(defclass pump-out (task)
  ((emptied :initform 0 :accessor emptied)))
(define-flow pump-out (self)
  (when (confirm self "Pump out the bilge?")
    (incf (emptied self))
    (inform self "Bilge pumped.")))
(with-fresh-applications (("/pump" 'pump-out :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/pump")
    (let ((question (body-text b)))
      (press b "Yes")
      (list question (body-text b)))))
;; ⇒ ("Pump out the bilge? Yes No" "Bilge pumped. OK")
```

#### `confirm-dialog` — class

Asks the yes/no question in its `:message`; answers T for Yes
or `nil` for No.

*Example:* In a flow, confirm waits for Yes (T) or No (`nil`), and inform for OK.  They show a confirm-dialog and a message-dialog.

```lisp
(defclass pump-out (task)
  ((emptied :initform 0 :accessor emptied)))
(define-flow pump-out (self)
  (when (confirm self "Pump out the bilge?")
    (incf (emptied self))
    (inform self "Bilge pumped.")))
(with-fresh-applications (("/pump" 'pump-out :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/pump")
    (let ((question (body-text b)))
      (press b "Yes")
      (list question (body-text b)))))
;; ⇒ ("Pump out the bilge? Yes No" "Bilge pumped. OK")
```

#### `input-dialog` — class

Asks for a line of text, with its `:message` as the prompt and
`:value` (default "") as the text to start from; answers the string.

*Example:* request-input shows an input-dialog and answers the text typed.  Its field is labelled with the question, so the fake browser finds it by that.

```lisp
(defclass sign-on (task) ())
(define-flow sign-on (self)
  (let ((name (request-input self "Your name?" "Sailor")))
    (inform self (format nil "Welcome aboard, ~A." name))))
(with-fresh-applications (("/sign-on" 'sign-on :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/sign-on")
    (let ((default (attr (attributes (cl-ppcre:scan-to-strings "<input[^>]*>" (browser-html b))) "value")))
      (fill-in b "Your name?" "Ada")
      (press b "OK")
      (list default (body-text b)))))
;; ⇒ ("Sailor" "Welcome aboard, Ada. OK")
```

#### `choice-dialog` — class

Asks for one of `:items` from a select list, with `:message` as
the prompt; answers the item, or `nil` on Cancel.  `:labels` is a function
giving each item's label (default `princ-to-string`).

*Example:* choose-from shows a choice-dialog listing the items; it answers the item chosen, or `nil` on Cancel.

```lisp
(defclass charter (task) ())
(define-flow charter (self)
  (let ((boat (choose-from self '(:dinghy :ketch :yawl) "Which boat?")))
    (inform self (if boat
                     (format nil "You chartered the ~(~A~)." boat)
                     "No boat today."))))
(with-fresh-applications (("/charter" 'charter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/charter")
    (let ((choices (body-text b)))
      (select-option b "Which boat?" "KETCH")
      (press b "OK")
      (let ((chosen (body-text b)))
        (press b "OK")                              ; the flow starts again
        (press b "Cancel")
        (list choices chosen (body-text b))))))
;; ⇒ ("Which boat? DINGHY KETCH YAWL OK Cancel" "You chartered the ketch. OK" "No boat today. OK")
```

*Example:* Made directly, a choice-dialog takes :labels, a function naming each item.

```lisp
(defclass berth-picker (component)
  ((berth :initform nil :accessor berth)))
(defmethod states ((self berth-picker)) (list self))
(defmethod render ((self berth-picker))
  (p () "Berth: " (text (princ-to-string (berth self))))
  (anchor (:callback (lambda ()
                       (show self (make-instance 'choice-dialog
                                                 :message "Which berth?"
                                                 :items '(1 2 3)
                                                 :labels (lambda (n) (format nil "Berth ~D" n)))
                             :on-answer (lambda (n) (setf (berth self) n)))))
    "Choose"))
(with-fresh-applications (("/berth" 'berth-picker :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/berth")
    (click b "Choose")
    (let ((choices (body-text b)))
      (select-option b "Which berth?" "Berth 3")
      (press b "OK")
      (list choices (body-text b)))))
;; ⇒ ("Which berth? Berth 1 Berth 2 Berth 3 OK Cancel" "Berth: 3 Choose")
```

#### `login-dialog` — class

Asks for a username and password; answers them as a
cons (`username` . `password`), or `nil` on Cancel.  Its fields have the `dom` ids
username and password.

*Example:* Answers (username . password), or `nil` on Cancel.  Its fields have the ids username and password.

```lisp
(defclass crew-room (component)
  ((user :initform nil :accessor user)))
(defmethod states ((self crew-room)) (list self))
(defmethod render ((self crew-room))
  (p () "Signed in: " (text (or (user self) "nobody")))
  (anchor (:callback (lambda ()
                       (show self (make-instance 'login-dialog :message "Crew only")
                             :on-answer (lambda (credentials)
                                          (when (and credentials (equal (rest credentials) "knots"))
                                            (setf (user self) (first credentials)))))))
    "Sign in"))
(with-fresh-applications (("/crew-room" 'crew-room :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/crew-room")
    (click b "Sign in")
    (fill-in b "username" "ada")
    (fill-in b "password" "knots")
    (press b "Log in")
    (body-text b)))
;; ⇒ "Signed in: ada Sign in"
```

#### `inform` `self message` — function

Show `message` in place of `self` until it is acknowledged.  A `call`: blocking inside a flow.

*Example:* In a flow, confirm waits for Yes (T) or No (`nil`), and inform for OK.  They show a confirm-dialog and a message-dialog.

```lisp
(defclass pump-out (task)
  ((emptied :initform 0 :accessor emptied)))
(define-flow pump-out (self)
  (when (confirm self "Pump out the bilge?")
    (incf (emptied self))
    (inform self "Bilge pumped.")))
(with-fresh-applications (("/pump" 'pump-out :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/pump")
    (let ((question (body-text b)))
      (press b "Yes")
      (list question (body-text b)))))
;; ⇒ ("Pump out the bilge? Yes No" "Bilge pumped. OK")
```

#### `confirm` `self question` — function

Ask `question` in place of `self`; T for yes, `nil` for no.  A `call`: blocking inside a flow.

*Example:* In a flow, confirm waits for Yes (T) or No (`nil`), and inform for OK.  They show a confirm-dialog and a message-dialog.

```lisp
(defclass pump-out (task)
  ((emptied :initform 0 :accessor emptied)))
(define-flow pump-out (self)
  (when (confirm self "Pump out the bilge?")
    (incf (emptied self))
    (inform self "Bilge pumped.")))
(with-fresh-applications (("/pump" 'pump-out :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/pump")
    (let ((question (body-text b)))
      (press b "Yes")
      (list question (body-text b)))))
;; ⇒ ("Pump out the bilge? Yes No" "Bilge pumped. OK")
```

#### `request-input` `self prompt &optional (default "")` — function

Ask for a line of text with `prompt`, starting from `default`; the string typed.  A `call`.

*Example:* request-input shows an input-dialog and answers the text typed.  Its field is labelled with the question, so the fake browser finds it by that.

```lisp
(defclass sign-on (task) ())
(define-flow sign-on (self)
  (let ((name (request-input self "Your name?" "Sailor")))
    (inform self (format nil "Welcome aboard, ~A." name))))
(with-fresh-applications (("/sign-on" 'sign-on :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/sign-on")
    (let ((default (attr (attributes (cl-ppcre:scan-to-strings "<input[^>]*>" (browser-html b))) "value")))
      (fill-in b "Your name?" "Ada")
      (press b "OK")
      (list default (body-text b)))))
;; ⇒ ("Sailor" "Welcome aboard, Ada. OK")
```

#### `choose-from` `self items &optional prompt` — function

Ask for one of `items`, with `prompt`; the item chosen, or `nil` on Cancel.
Items are labelled with `princ-to-string`.  A `call`.

*Example:* choose-from shows a choice-dialog listing the items; it answers the item chosen, or `nil` on Cancel.

```lisp
(defclass charter (task) ())
(define-flow charter (self)
  (let ((boat (choose-from self '(:dinghy :ketch :yawl) "Which boat?")))
    (inform self (if boat
                     (format nil "You chartered the ~(~A~)." boat)
                     "No boat today."))))
(with-fresh-applications (("/charter" 'charter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/charter")
    (let ((choices (body-text b)))
      (select-option b "Which boat?" "KETCH")
      (press b "OK")
      (let ((chosen (body-text b)))
        (press b "OK")                              ; the flow starts again
        (press b "Cancel")
        (list choices chosen (body-text b))))))
;; ⇒ ("Which boat? DINGHY KETCH YAWL OK Cancel" "You chartered the ketch. OK" "No boat today. OK")
```

### Widgets

#### `batched-list` — class

Pages through `:items` (a list, or a function returning
one), `:batch-size` (10 by default) at a time.  Render the current `batch`
yourself and `render-component` the batched list for its page links, as with
Seaside's WABatchedList.

*Example:* A batched list keeps the items and the page; `batch` is what the current page holds.  `go-to-page` keeps the page in range.

```lisp
(let ((list (make-instance 'batched-list :items (loop for i from 1 to 25 collect i) :batch-size 10)))
  (go-to-page list 99)
  (list (batch-page list) (batch list) (batch-size list) (length (batch-items list))))
;; ⇒ (2 (21 22 23 24 25) 10 25)
```

*Example:* In a page: render the current batch yourself, then render the batched list for its page links.

```lisp
(defclass fruit-list (component)
  ((pages :initform (make-instance 'batched-list :batch-size 2
                                                 :items '("Apple" "Banana" "Cherry" "Damson" "Elder"))
          :reader pages)))
(defmethod children ((self fruit-list))
  (list (pages self)))
(defmethod render ((self fruit-list))
  (ul () (dolist (fruit (batch (pages self))) (li () (text fruit))))
  (render-component (pages self)))
(with-fresh-applications (("/fruit" 'fruit-list :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/fruit")
    (click b "Next »")
    (body-text b)))
;; ⇒ "Cherry Damson « Previous123Next »"
```

#### `batch` `list` — function

The items on `list`'s current page.

*Example:* A batched list keeps the items and the page; `batch` is what the current page holds.  `go-to-page` keeps the page in range.

```lisp
(let ((list (make-instance 'batched-list :items (loop for i from 1 to 25 collect i) :batch-size 10)))
  (go-to-page list 99)
  (list (batch-page list) (batch list) (batch-size list) (length (batch-items list))))
;; ⇒ (2 (21 22 23 24 25) 10 25)
```

*Example:* In a page: render the current batch yourself, then render the batched list for its page links.

```lisp
(defclass fruit-list (component)
  ((pages :initform (make-instance 'batched-list :batch-size 2
                                                 :items '("Apple" "Banana" "Cherry" "Damson" "Elder"))
          :reader pages)))
(defmethod children ((self fruit-list))
  (list (pages self)))
(defmethod render ((self fruit-list))
  (ul () (dolist (fruit (batch (pages self))) (li () (text fruit))))
  (render-component (pages self)))
(with-fresh-applications (("/fruit" 'fruit-list :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/fruit")
    (click b "Next »")
    (body-text b)))
;; ⇒ "Cherry Damson « Previous123Next »"
```

#### `batch-items` `list` — function

All of `list`'s items, calling its items function when it has one.
`setf` replaces them (with a list or a function), keeping the page in range.

*Example:* A batched list keeps the items and the page; `batch` is what the current page holds.  `go-to-page` keeps the page in range.

```lisp
(let ((list (make-instance 'batched-list :items (loop for i from 1 to 25 collect i) :batch-size 10)))
  (go-to-page list 99)
  (list (batch-page list) (batch list) (batch-size list) (length (batch-items list))))
;; ⇒ (2 (21 22 23 24 25) 10 25)
```

#### `batch-size` `object` — generic function

Reads the batch-size of a batched-list.  How many items a page holds.

*Example:* A batched list keeps the items and the page; `batch` is what the current page holds.  `go-to-page` keeps the page in range.

```lisp
(let ((list (make-instance 'batched-list :items (loop for i from 1 to 25 collect i) :batch-size 10)))
  (go-to-page list 99)
  (list (batch-page list) (batch list) (batch-size list) (length (batch-items list))))
;; ⇒ (2 (21 22 23 24 25) 10 25)
```

#### `batch-page` `object` — generic function

Reads the page of a batched-list.  The page shown, counting from 0.

*Example:* A batched list keeps the items and the page; `batch` is what the current page holds.  `go-to-page` keeps the page in range.

```lisp
(let ((list (make-instance 'batched-list :items (loop for i from 1 to 25 collect i) :batch-size 10)))
  (go-to-page list 99)
  (list (batch-page list) (batch list) (batch-size list) (length (batch-items list))))
;; ⇒ (2 (21 22 23 24 25) 10 25)
```

#### `go-to-page` `list page` — function

Show page `page` (counting from 0) of `list`, kept in range.  Returns the
page shown.

*Example:* A batched list keeps the items and the page; `batch` is what the current page holds.  `go-to-page` keeps the page in range.

```lisp
(let ((list (make-instance 'batched-list :items (loop for i from 1 to 25 collect i) :batch-size 10)))
  (go-to-page list 99)
  (list (batch-page list) (batch list) (batch-size list) (length (batch-items list))))
;; ⇒ (2 (21 22 23 24 25) 10 25)
```

#### `report` — class

A table of `:rows` (a list, or a function returning one,
called on every render) in `:columns` (made with `column`), sorted by clicking
a heading, like Seaside's WATableReport.  `:row-class`, a function of a row,
gives its CSS class.  Give `:batch-size` to page it.

*Example:* A report shows rows in columns; a column's value is a function of the row.  Clicking a heading sorts by it, and clicking it again reverses the order.

```lisp
(defclass planets (report) ()
  (:default-initargs
   :rows '(("Mercury" 0.39) ("Venus" 0.72) ("Earth" 1.0) ("Mars" 1.52))
   :columns (list (column "Planet" #'first)
                  (column "Distance (AU)" #'second :class "number"))))
(with-fresh-applications (("/planets" 'planets :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/planets")
    (click b "Planet")
    (click b "Planet")
    (body-text b)))
;; ⇒ "Planet ▼ Distance (AU) Venus 0.72 Mercury 0.39 Mars 1.52 Earth 1.0"
```

*Example:* Rows given as a function are fetched on every render, so the report follows its data.  A column with no value and its own `:render` can hold links; `:sortable` `nil` leaves its heading plain.

```lisp
(defclass order-book (component)
  ((orders :initform (list "Tea" "Scones" "Jam") :accessor orders)
   (report :reader order-report)))
(defmethod initialize-instance :after ((self order-book) &key)
  (setf (slot-value self 'report)
        (make-instance 'report
                       :rows (lambda () (orders self))
                       :columns (list (column "Order" #'identity)
                                      (column "" nil :sortable nil
                                                     :render (lambda (row value)
                                                               (declare (ignore value))
                                                               (anchor (:callback (lambda () (setf (orders self) (remove row (orders self)))))
                                                                 "cancel")))))))
(defmethod states ((self order-book))
  (list self))
(defmethod children ((self order-book))
  (list (order-report self)))
(defmethod render ((self order-book))
  (render-component (order-report self)))
(with-fresh-applications (("/orders" 'order-book :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/orders")
    (click-nth b "cancel" 1)
    (body-text b)))
;; ⇒ "Order Tea cancel Jam cancel"
```

*Example:* `:batch-size` pages the report; `:row-class` gives each row a CSS class.

```lisp
(defclass squares (report) ()
  (:default-initargs
   :rows (loop for n from 1 to 7 collect n)
   :columns (list (column "N" #'identity) (column "N²" (lambda (n) (* n n))))
   :row-class (lambda (n) (when (evenp n) "even"))
   :batch-size 3))
(with-fresh-applications (("/squares" 'squares :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/squares")
    (click b "3")
    (body-text b)))
;; ⇒ "N N² 7 49 « Previous123Next »"
```

#### `column` `title value &rest initargs &key render sort-key sort-predicate sortable class` — function

A `report` column titled `title` (translated) showing (`funcall` `value` `row`);
`value` `nil` gives every cell the value `nil`.  `render`, a function of the row
and the value, writes the cell; by default the value is written as text,
and `nil` as nothing.  `sortable` `nil` leaves the heading a plain title.  The
column sorts by `sort-key`, a function of the row (the value by default),
under `sort-predicate` (by default numbers by <, anything else by its
printed form, `nil` last).  `class` is the CSS class of the column's cells.

*Example:* A report shows rows in columns; a column's value is a function of the row.  Clicking a heading sorts by it, and clicking it again reverses the order.

```lisp
(defclass planets (report) ()
  (:default-initargs
   :rows '(("Mercury" 0.39) ("Venus" 0.72) ("Earth" 1.0) ("Mars" 1.52))
   :columns (list (column "Planet" #'first)
                  (column "Distance (AU)" #'second :class "number"))))
(with-fresh-applications (("/planets" 'planets :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/planets")
    (click b "Planet")
    (click b "Planet")
    (body-text b)))
;; ⇒ "Planet ▼ Distance (AU) Venus 0.72 Mercury 0.39 Mars 1.52 Earth 1.0"
```

*Example:* Rows given as a function are fetched on every render, so the report follows its data.  A column with no value and its own `:render` can hold links; `:sortable` `nil` leaves its heading plain.

```lisp
(defclass order-book (component)
  ((orders :initform (list "Tea" "Scones" "Jam") :accessor orders)
   (report :reader order-report)))
(defmethod initialize-instance :after ((self order-book) &key)
  (setf (slot-value self 'report)
        (make-instance 'report
                       :rows (lambda () (orders self))
                       :columns (list (column "Order" #'identity)
                                      (column "" nil :sortable nil
                                                     :render (lambda (row value)
                                                               (declare (ignore value))
                                                               (anchor (:callback (lambda () (setf (orders self) (remove row (orders self)))))
                                                                 "cancel")))))))
(defmethod states ((self order-book))
  (list self))
(defmethod children ((self order-book))
  (list (order-report self)))
(defmethod render ((self order-book))
  (render-component (order-report self)))
(with-fresh-applications (("/orders" 'order-book :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/orders")
    (click-nth b "cancel" 1)
    (body-text b)))
;; ⇒ "Order Tea cancel Jam cancel"
```

#### `report-rows` `object` — generic function

Reads the rows of a report.  A list, or a thunk returning one on every render.

*Example:* Rows given as a function are fetched on every render, so the report follows its data.  A column with no value and its own `:render` can hold links; `:sortable` `nil` leaves its heading plain.

```lisp
(defclass order-book (component)
  ((orders :initform (list "Tea" "Scones" "Jam") :accessor orders)
   (report :reader order-report)))
(defmethod initialize-instance :after ((self order-book) &key)
  (setf (slot-value self 'report)
        (make-instance 'report
                       :rows (lambda () (orders self))
                       :columns (list (column "Order" #'identity)
                                      (column "" nil :sortable nil
                                                     :render (lambda (row value)
                                                               (declare (ignore value))
                                                               (anchor (:callback (lambda () (setf (orders self) (remove row (orders self)))))
                                                                 "cancel")))))))
(defmethod states ((self order-book))
  (list self))
(defmethod children ((self order-book))
  (list (order-report self)))
(defmethod render ((self order-book))
  (render-component (order-report self)))
(with-fresh-applications (("/orders" 'order-book :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/orders")
    (click-nth b "cancel" 1)
    (body-text b)))
;; ⇒ "Order Tea cancel Jam cancel"
```

*Example:* A report's rows and columns can be replaced; the next render shows the new ones.

```lisp
(let ((report (make-instance 'report :rows '(("Tea" 2)) :columns (list (column "Item" #'first)))))
  (setf (report-columns report) (append (report-columns report) (list (column "Qty" #'second)))
        (report-rows report) '(("Tea" 2) ("Jam" 1)))
  (list (length (report-columns report)) (length (report-rows report))))
;; ⇒ (2 2)
```

#### `report-columns` `object` — generic function

Reads the columns of a report.  The columns, made with `column`, in order.

*Example:* A report's rows and columns can be replaced; the next render shows the new ones.

```lisp
(let ((report (make-instance 'report :rows '(("Tea" 2)) :columns (list (column "Item" #'first)))))
  (setf (report-columns report) (append (report-columns report) (list (column "Qty" #'second)))
        (report-rows report) '(("Tea" 2) ("Jam" 1)))
  (list (length (report-columns report)) (length (report-rows report))))
;; ⇒ (2 2)
```

#### `sort-by` `report column` — function

Sort `report` by `column`, one of its columns, in ascending order, or
reverse the order when `report` is sorted by `column` already.  A paged report
goes back to its first page.

*Example:* A report shows rows in columns; a column's value is a function of the row.  Clicking a heading sorts by it, and clicking it again reverses the order.

```lisp
(defclass planets (report) ()
  (:default-initargs
   :rows '(("Mercury" 0.39) ("Venus" 0.72) ("Earth" 1.0) ("Mars" 1.52))
   :columns (list (column "Planet" #'first)
                  (column "Distance (AU)" #'second :class "number"))))
(with-fresh-applications (("/planets" 'planets :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/planets")
    (click b "Planet")
    (click b "Planet")
    (body-text b)))
;; ⇒ "Planet ▼ Distance (AU) Venus 0.72 Mercury 0.39 Mars 1.52 Earth 1.0"
```

#### `tab-panel` — class

Shows one of several components, chosen by a row of tabs,
like Seaside's WATabPanel.  `:tabs` is an alist of (`label` . `component`), the
labels translated when shown; `:selected` is the index of the tab shown first
(0 by default).  The current tab is not a link.

*Example:* A tab panel shows one component of several, picked by a row of tabs; the current tab is not a link.

```lisp
(defclass note (component)
  ((words :initarg :words :reader words)))
(defmethod render ((self note))
  (p () (text (words self))))
(defclass settings (tab-panel) ()
  (:default-initargs
   :tabs (list (cons "Profile" (make-instance 'note :words "Your name and photo."))
               (cons "Security" (make-instance 'note :words "Passwords and keys.")))))
(with-fresh-applications (("/settings" 'settings :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/settings")
    (click b "Security")
    (list (body-text b) (find-link b "Security"))))
;; ⇒ ("Profile Security Passwords and keys." NIL)
```

#### `navigation` — class

A `tab-panel` drawn as a menu beside its content, like
Seaside's WASimpleNavigation.

*Example:* The same as a menu beside the content.

```lisp
(defclass chapter (component)
  ((words :initarg :words :reader words)))
(defmethod render ((self chapter))
  (p () (text (words self))))
(defclass handbook (navigation) ()
  (:default-initargs
   :tabs (list (cons "Start" (make-instance 'chapter :words "Welcome."))
               (cons "Install" (make-instance 'chapter :words "Run make.")))))
(with-fresh-applications (("/handbook" 'handbook :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/handbook")
    (click b "Install")
    (list (body-text b) (not (null (search "lt-menu" (browser-html b)))))))
;; ⇒ ("Start Install Run make." T)
```

#### `panel-tabs` `object` — generic function

Reads the tabs of a tab-panel.  Alist of (`label` . `component`).

*Example:* A tab panel shows one component of several, picked by a row of tabs; the current tab is not a link.

```lisp
(defclass note (component)
  ((words :initarg :words :reader words)))
(defmethod render ((self note))
  (p () (text (words self))))
(defclass settings (tab-panel) ()
  (:default-initargs
   :tabs (list (cons "Profile" (make-instance 'note :words "Your name and photo."))
               (cons "Security" (make-instance 'note :words "Passwords and keys.")))))
(with-fresh-applications (("/settings" 'settings :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/settings")
    (click b "Security")
    (list (body-text b) (find-link b "Security"))))
;; ⇒ ("Profile Security Passwords and keys." NIL)
```

#### `panel-selected` `object` — generic function

Reads the selected of a tab-panel.  Index of the tab shown.

*Example:* Choosing a tab from code: `select-tab` finds it by label.

```lisp
(let* ((profile (make-instance 'component))
       (security (make-instance 'component))
       (panel (make-instance 'tab-panel :tabs (list (cons "Profile" profile) (cons "Security" security)))))
  (select-tab panel "Security")
  (list (panel-selected panel) (eq (selected-tab panel) security) (select-tab panel "Billing")))
;; ⇒ (1 T NIL)
```

#### `selected-tab` `panel` — function

The component `panel` shows, or `nil` when it has no tabs.

*Example:* Choosing a tab from code: `select-tab` finds it by label.

```lisp
(let* ((profile (make-instance 'component))
       (security (make-instance 'component))
       (panel (make-instance 'tab-panel :tabs (list (cons "Profile" profile) (cons "Security" security)))))
  (select-tab panel "Security")
  (list (panel-selected panel) (eq (selected-tab panel) security) (select-tab panel "Billing")))
;; ⇒ (1 T NIL)
```

#### `select-tab` `panel label` — function

Show the tab of `panel` labelled `label` (compared with `equal`), and return
its index; when no tab has that label, change nothing and return `nil`.

*Example:* Choosing a tab from code: `select-tab` finds it by label.

```lisp
(let* ((profile (make-instance 'component))
       (security (make-instance 'component))
       (panel (make-instance 'tab-panel :tabs (list (cons "Profile" profile) (cons "Security" security)))))
  (select-tab panel "Security")
  (list (panel-selected panel) (eq (selected-tab panel) security) (select-tab panel "Billing")))
;; ⇒ (1 T NIL)
```

#### `tree` — class

Items in a hierarchy, each expandable, like Seaside's WATree.
`:roots` are the top-level items and `:children` a function of an item giving
its child items (`nil` for none).  `:labels`, a function of an item, gives the
text shown (`princ-to-string` by default).  Clicking a label selects the item
and calls `:on-select`, when given, with it.  Items are compared with `eql`.

*Example:* A tree needs its roots and a function giving an item's children.  A toggle (▸) expands an item; clicking a label selects it and calls `:on-select`.

```lisp
(defparameter *kingdoms* '((:animals :cats :dogs) (:plants :trees)))
(defclass kingdoms (component)
  ((tree :reader kingdom-tree)
   (chosen :initform nil :accessor chosen)))
(defmethod initialize-instance :after ((self kingdoms) &key)
  (setf (slot-value self 'tree)
        (make-instance 'tree :roots '(:animals :plants)
                             :children (lambda (item) (rest (assoc item *kingdoms*)))
                             :labels #'string-capitalize
                             :on-select (lambda (item) (setf (chosen self) item)))))
(defmethod states ((self kingdoms))
  (list self))
(defmethod children ((self kingdoms))
  (list (kingdom-tree self)))
(defmethod render ((self kingdoms))
  (render-component (kingdom-tree self))
  (when (chosen self) (p () "Chose " (text (string-capitalize (chosen self))))))
(with-fresh-applications (("/kingdoms" 'kingdoms :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/kingdoms")
    (click b "▸")
    (click b "Dogs")
    (body-text b)))
;; ⇒ "▾ Animals · Cats · Dogs ▸ Plants Chose Dogs"
```

#### `tree-expanded` `object` — generic function

Reads the expanded of a tree.  The items whose children show.  Replaced, never changed in place.

*Example:* Expanding and collapsing from code.

```lisp
(let ((tree (make-instance 'tree :roots '(:animals :plants)
                                 :children (lambda (item)
                                             (rest (assoc item '((:animals :cats :dogs) (:plants :trees))))))))
  (expand-all tree)
  (toggle-item tree :plants)
  (tree-expanded tree))
;; ⇒ (:ANIMALS)
```

#### `tree-selected` `object` — generic function

Reads the selected of a tree.  The item whose label was clicked last, or `nil`.

*Example:* A tree needs its roots and a function giving an item's children.  A toggle (▸) expands an item; clicking a label selects it and calls `:on-select`.

```lisp
(defparameter *kingdoms* '((:animals :cats :dogs) (:plants :trees)))
(defclass kingdoms (component)
  ((tree :reader kingdom-tree)
   (chosen :initform nil :accessor chosen)))
(defmethod initialize-instance :after ((self kingdoms) &key)
  (setf (slot-value self 'tree)
        (make-instance 'tree :roots '(:animals :plants)
                             :children (lambda (item) (rest (assoc item *kingdoms*)))
                             :labels #'string-capitalize
                             :on-select (lambda (item) (setf (chosen self) item)))))
(defmethod states ((self kingdoms))
  (list self))
(defmethod children ((self kingdoms))
  (list (kingdom-tree self)))
(defmethod render ((self kingdoms))
  (render-component (kingdom-tree self))
  (when (chosen self) (p () "Chose " (text (string-capitalize (chosen self))))))
(with-fresh-applications (("/kingdoms" 'kingdoms :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/kingdoms")
    (click b "▸")
    (click b "Dogs")
    (body-text b)))
;; ⇒ "▾ Animals · Cats · Dogs ▸ Plants Chose Dogs"
```

#### `toggle-item` `tree item` — function

Expand `item` in `tree`, or collapse it.

*Example:* Expanding and collapsing from code.

```lisp
(let ((tree (make-instance 'tree :roots '(:animals :plants)
                                 :children (lambda (item)
                                             (rest (assoc item '((:animals :cats :dogs) (:plants :trees))))))))
  (expand-all tree)
  (toggle-item tree :plants)
  (tree-expanded tree))
;; ⇒ (:ANIMALS)
```

#### `expand-all` `tree` — function

Expand every item of `tree` that has children.

*Example:* Expanding and collapsing from code.

```lisp
(let ((tree (make-instance 'tree :roots '(:animals :plants)
                                 :children (lambda (item)
                                             (rest (assoc item '((:animals :cats :dogs) (:plants :trees))))))))
  (expand-all tree)
  (toggle-item tree :plants)
  (tree-expanded tree))
;; ⇒ (:ANIMALS)
```

#### `autocomplete` — class

A text field suggesting completions as you type, over
AJAX.  `:suggest` is a function of the text typed (trimmed) returning a list
of suggestions; it is called once `:minimum` characters are typed (1 by
default), and the first `:limit` suggestions (8) are shown, through `:labels` (a
function of a suggestion; `princ-to-string` by default).  Choosing one puts
its label in the field and calls `:on-choose`, when given, with it.  `:value` is
the starting text, `:input-id` the input's element id and `:placeholder` its
placeholder.  The field's text is submitted with its form, like any input.

*Example:* An autocomplete suggests completions as you type (over AJAX, as littoral.js sends them); its value is the text in the field.

```lisp
(defparameter *colours* '("Teal" "Tomato" "Turquoise" "Violet"))
(defclass colour-form (component)
  ((field :initform (make-instance 'autocomplete
                                   :input-id "colour"
                                   :suggest (lambda (typed)
                                              (remove-if-not (lambda (c) (eql 0 (search typed c :test #'char-equal)))
                                                             *colours*)))
          :reader colour-field)
   (picked :initform nil :accessor picked)))
(defmethod states ((self colour-form))
  (list self))
(defmethod children ((self colour-form))
  (list (colour-field self)))
(defmethod render ((self colour-form))
  (form ()
    (render-component (colour-field self))
    (submit-button (:callback (lambda () (setf (picked self) (autocomplete-value (colour-field self)))))
      "Pick"))
  (when (picked self) (p () "Picked " (text (picked self)))))
(with-fresh-applications (("/colours" 'colour-form :mode :deployment))
  (let* ((b (make-instance 'browser))
         (field (progn (visit b "/colours") (element-name b "colour")))
         (typing (first (ajax-specs b "on-input")))
         (json (ajax-request b (first typing) (rest typing) :fields (list (cons field "t")))))
    (fill-in b "colour" "Teal")
    (press b "Pick")
    (list (count-if (lambda (c) (search c json)) *colours*)
          (not (null (has-text-p b "Picked Teal"))))))
;; ⇒ (3 T)
```

#### `autocomplete-value` `object` — generic function

Reads the value of an autocomplete.  The text in the field.

*Example:* An autocomplete suggests completions as you type (over AJAX, as littoral.js sends them); its value is the text in the field.

```lisp
(defparameter *colours* '("Teal" "Tomato" "Turquoise" "Violet"))
(defclass colour-form (component)
  ((field :initform (make-instance 'autocomplete
                                   :input-id "colour"
                                   :suggest (lambda (typed)
                                              (remove-if-not (lambda (c) (eql 0 (search typed c :test #'char-equal)))
                                                             *colours*)))
          :reader colour-field)
   (picked :initform nil :accessor picked)))
(defmethod states ((self colour-form))
  (list self))
(defmethod children ((self colour-form))
  (list (colour-field self)))
(defmethod render ((self colour-form))
  (form ()
    (render-component (colour-field self))
    (submit-button (:callback (lambda () (setf (picked self) (autocomplete-value (colour-field self)))))
      "Pick"))
  (when (picked self) (p () "Picked " (text (picked self)))))
(with-fresh-applications (("/colours" 'colour-form :mode :deployment))
  (let* ((b (make-instance 'browser))
         (field (progn (visit b "/colours") (element-name b "colour")))
         (typing (first (ajax-specs b "on-input")))
         (json (ajax-request b (first typing) (rest typing) :fields (list (cons field "t")))))
    (fill-in b "colour" "Teal")
    (press b "Pick")
    (list (count-if (lambda (c) (search c json)) *colours*)
          (not (null (has-text-p b "Picked Teal"))))))
;; ⇒ (3 T)
```

#### `sortable-list` — class

A list of `:items` the user can reorder by dragging, or with
the up and down links beside each item (which work without JavaScript).
`:render-item`, a function of an item, writes it (as text by default), and
`:on-reorder` is called with the new list after every move.

*Example:* `move-item` reorders from code and calls `:on-reorder` with the new order.

```lisp
(let* ((seen nil)
       (list (make-instance 'sortable-list :items '("Wash" "Dry" "Fold")
                                           :on-reorder (lambda (items) (setf seen items)))))
  (move-item list 2 0)
  (list (sortable-items list) seen))
;; ⇒ (("Fold" "Wash" "Dry") ("Fold" "Wash" "Dry"))
```

*Example:* In a page, each item has up and down links (and can be dragged, with littoral.js).

```lisp
(defclass chores (sortable-list) ()
  (:default-initargs :items '("Wash" "Dry" "Fold")))
(with-fresh-applications (("/chores" 'chores :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/chores")
    (click-nth b "↓" 0)
    (body-text b)))
;; ⇒ "⠿Dry↓ ⠿Wash↑↓ ⠿Fold↑"
```

#### `sortable-items` `object` — generic function

Reads the items of a sortable-list.  The items, in their current order.

*Example:* `move-item` reorders from code and calls `:on-reorder` with the new order.

```lisp
(let* ((seen nil)
       (list (make-instance 'sortable-list :items '("Wash" "Dry" "Fold")
                                           :on-reorder (lambda (items) (setf seen items)))))
  (move-item list 2 0)
  (list (sortable-items list) seen))
;; ⇒ (("Fold" "Wash" "Dry") ("Fold" "Wash" "Dry"))
```

#### `move-item` `list from to` — function

Move the item at position `from` to position `to` in `list`, a `sortable-list`,
counting from 0, and call its `on-reorder`.  Does nothing when either is out
of range or they are the same.

*Example:* `move-item` reorders from code and calls `:on-reorder` with the new order.

```lisp
(let* ((seen nil)
       (list (make-instance 'sortable-list :items '("Wash" "Dry" "Fold")
                                           :on-reorder (lambda (items) (setf seen items)))))
  (move-item list 2 0)
  (list (sortable-items list) seen))
;; ⇒ (("Fold" "Wash" "Dry") ("Fold" "Wash" "Dry"))
```

### Descriptions

#### `define-description` `name fields &key validate` — macro

Describe the objects of class `name`, replacing any description of that
name, and return the `description`.  Each of `fields` is (`property` &rest
options).  `:type` is the field's kind, a keyword in `*field-kinds*` (`:string` by
default), and `:label` its name on the page (by default `property`,
capitalised).  `:required` makes a value necessary; `:default` is the value an
editor starts from when the object has none; `:help` is a line shown under
the input; `:validate` is a function of the value returning `nil`, or what is
wrong.  `:read-only` fields are shown but not edited; `:hidden` ones are
checked by `validate` but never shown; `:in-report` `nil` leaves a field out of
`description-columns` and data grids.  A field reads and writes the slot named
`property`, unless given `:accessor` (the name of a SETF-able function) or
`:reader` and `:writer` (functions of `object`, and of `value` and `object`).  The
field's kind may take more: `:max-length`, `:pattern` and `:pattern-message` for
text, `:min` and `:max` for integers, `:choices` and `:labels` for choices.  The
options are evaluated, except `:accessor`.

`validate`, a function of a plist of the values keyed by keywords, checks
them together: it returns `nil`, or what is wrong.

*Example:* Describe a class's fields once.  `validate` checks an object against its class's description and lists what is wrong, field by field.

```lisp
(defclass guest ()
  ((name :initarg :name :initform nil)
   (email :initarg :email :initform nil)
   (age :initarg :age :initform nil)))
(define-description guest
  ((name :required t :max-length 40)
   (email :type :email :required t)
   (age :type :integer :min 0 :max 150)))
(validate (make-instance 'guest :email "ada@" :age 200))
;; ⇒ ((NAME . "Name is required.") (EMAIL . "Email must be an email address.") (AGE . "Age must be at most 150."))
```

*Example:* `:validate` on the description checks the values together, as a plist keyed by keywords; it runs only once every field passes, and its problem comes back under `nil`.

```lisp
(defclass booking ()
  ((plan :initarg :plan :initform :personal)
   (seats :initarg :seats :initform 1)))
(define-description booking
  ((plan :type :choice :choices '(:personal :team))
   (seats :type :integer :min 1))
  :validate (lambda (values)
              (when (and (eq (getf values :plan) :personal) (> (getf values :seats) 1))
                "A personal plan has one seat.")))
(list (validate (make-instance 'booking :seats 3))
      (validate (make-instance 'booking :plan :team :seats 3)))
;; ⇒ (((NIL . "A personal plan has one seat.")) NIL)
```

*Example:* A field reads and writes the slot of its name, unless given `:accessor` (a SETF-able function) or `:reader` and `:writer`.  `:label` names it on the page; the default comes from the property's name.

```lisp
(defclass author ()
  ((names :initform (list "Mary" "Shelley") :accessor names)))
(defun full-name (author) (format nil "~{~A~^ ~}" (names author)))
(defun (setf full-name) (name author) (setf (names author) (uiop:split-string name)))
(define-description author
  ((full-name :accessor full-name :label "Name")))
(let ((author (make-instance 'author))
      (field (find-field 'author 'full-name)))
  (setf (field-value field author) "Mary Wollstonecraft Shelley")
  (list (field-value field author) (names author)))
;; ⇒ ("Mary Wollstonecraft Shelley" ("Mary" "Wollstonecraft" "Shelley"))
```

#### `description` — class

The fields of a kind of object, in order, as
`define-description` makes them.

*Example:* A description is found by name, or from an object of its class.  Its fields are in the order given.

```lisp
(defclass recipe ()
  ((title :initform "Scones")
   (serves :initform 8)))
(define-description recipe
  ((title :required t)
   (serves :type :integer :label "Serves")))
(let ((description (find-description (make-instance 'recipe))))
  (list (typep description 'description)
        (mapcar #'field-name (description-fields description))
        (mapcar #'field-label (description-fields description))
        (type-of (find-field 'recipe 'serves))))
;; ⇒ (T (TITLE SERVES) ("Title" "Serves") INTEGER-FIELD)
```

#### `find-description` `designator` — function

The description `designator` names: `designator` itself when it is a
`description`, the one defined under it when it is a symbol, or else that of
its class.  Signals an error when there is none.

*Example:* A description is found by name, or from an object of its class.  Its fields are in the order given.

```lisp
(defclass recipe ()
  ((title :initform "Scones")
   (serves :initform 8)))
(define-description recipe
  ((title :required t)
   (serves :type :integer :label "Serves")))
(let ((description (find-description (make-instance 'recipe))))
  (list (typep description 'description)
        (mapcar #'field-name (description-fields description))
        (mapcar #'field-label (description-fields description))
        (type-of (find-field 'recipe 'serves))))
;; ⇒ (T (TITLE SERVES) ("Title" "Serves") INTEGER-FIELD)
```

#### `description-fields` `object` — generic function

Reads the fields of a description.

*Example:* A description is found by name, or from an object of its class.  Its fields are in the order given.

```lisp
(defclass recipe ()
  ((title :initform "Scones")
   (serves :initform 8)))
(define-description recipe
  ((title :required t)
   (serves :type :integer :label "Serves")))
(let ((description (find-description (make-instance 'recipe))))
  (list (typep description 'description)
        (mapcar #'field-name (description-fields description))
        (mapcar #'field-label (description-fields description))
        (type-of (find-field 'recipe 'serves))))
;; ⇒ (T (TITLE SERVES) ("Title" "Serves") INTEGER-FIELD)
```

#### `field` — class

One described property of an object.  Subclasses say how
its values are entered, parsed, shown and checked.  `define-description` makes
them from the options it is given.

*Example:* A description is found by name, or from an object of its class.  Its fields are in the order given.

```lisp
(defclass recipe ()
  ((title :initform "Scones")
   (serves :initform 8)))
(define-description recipe
  ((title :required t)
   (serves :type :integer :label "Serves")))
(let ((description (find-description (make-instance 'recipe))))
  (list (typep description 'description)
        (mapcar #'field-name (description-fields description))
        (mapcar #'field-label (description-fields description))
        (type-of (find-field 'recipe 'serves))))
;; ⇒ (T (TITLE SERVES) ("Title" "Serves") INTEGER-FIELD)
```

#### `field-name` `object` — generic function

Reads the name of a field.  The property described, a symbol.

*Example:* A description is found by name, or from an object of its class.  Its fields are in the order given.

```lisp
(defclass recipe ()
  ((title :initform "Scones")
   (serves :initform 8)))
(define-description recipe
  ((title :required t)
   (serves :type :integer :label "Serves")))
(let ((description (find-description (make-instance 'recipe))))
  (list (typep description 'description)
        (mapcar #'field-name (description-fields description))
        (mapcar #'field-label (description-fields description))
        (type-of (find-field 'recipe 'serves))))
;; ⇒ (T (TITLE SERVES) ("Title" "Serves") INTEGER-FIELD)
```

#### `field-label` `object` — generic function

Reads the label of a field.  The text naming the field on the page, translated when shown.

*Example:* A description is found by name, or from an object of its class.  Its fields are in the order given.

```lisp
(defclass recipe ()
  ((title :initform "Scones")
   (serves :initform 8)))
(define-description recipe
  ((title :required t)
   (serves :type :integer :label "Serves")))
(let ((description (find-description (make-instance 'recipe))))
  (list (typep description 'description)
        (mapcar #'field-name (description-fields description))
        (mapcar #'field-label (description-fields description))
        (type-of (find-field 'recipe 'serves))))
;; ⇒ (T (TITLE SERVES) ("Title" "Serves") INTEGER-FIELD)
```

#### `field-value` `field object` — function

`field`'s value in `object`, through the field's reader.  `setf` writes it
through the field's writer.

*Example:* A field reads and writes the slot of its name, unless given `:accessor` (a SETF-able function) or `:reader` and `:writer`.  `:label` names it on the page; the default comes from the property's name.

```lisp
(defclass author ()
  ((names :initform (list "Mary" "Shelley") :accessor names)))
(defun full-name (author) (format nil "~{~A~^ ~}" (names author)))
(defun (setf full-name) (name author) (setf (names author) (uiop:split-string name)))
(define-description author
  ((full-name :accessor full-name :label "Name")))
(let ((author (make-instance 'author))
      (field (find-field 'author 'full-name)))
  (setf (field-value field author) "Mary Wollstonecraft Shelley")
  (list (field-value field author) (names author)))
;; ⇒ ("Mary Wollstonecraft Shelley" ("Mary" "Wollstonecraft" "Shelley"))
```

#### `find-field` `description name` — function

The field of `description` (anything `find-description` takes) for the
property `name`, or `nil`.

*Example:* A description is found by name, or from an object of its class.  Its fields are in the order given.

```lisp
(defclass recipe ()
  ((title :initform "Scones")
   (serves :initform 8)))
(define-description recipe
  ((title :required t)
   (serves :type :integer :label "Serves")))
(let ((description (find-description (make-instance 'recipe))))
  (list (typep description 'description)
        (mapcar #'field-name (description-fields description))
        (mapcar #'field-label (description-fields description))
        (type-of (find-field 'recipe 'serves))))
;; ⇒ (T (TITLE SERVES) ("Title" "Serves") INTEGER-FIELD)
```

#### `*field-kinds*` — variable

Alist of keyword → field class name, for `:type` in `define-description`.
Push your own (`keyword` . `class-name`).

*Example:* A field kind of your own: a class with methods for what differs, under a keyword in `*field-kinds*`.  `field-problem` signals the `field-error` that rejects input.  (Push onto `*field-kinds*` in your own code; the `let` keeps this example tidy.)

```lisp
(defclass postcode-field (string-field) ())
(defmethod parse-field ((field postcode-field) string)
  (let ((code (string-upcase (remove #\Space string))))
    (cond ((string= code "") nil)
          ((<= 5 (length code) 7)
           (format nil "~A ~A" (subseq code 0 (- (length code) 3)) (subseq code (- (length code) 3))))
          (t (field-problem "~A is not a postcode." (translate (field-label field)))))))
(defclass address ()
  ((postcode :initform nil)))
(let ((*field-kinds* (acons :postcode 'postcode-field *field-kinds*)))
  (define-description address
    ((postcode :type :postcode :required t))))
(let ((field (find-field 'address 'postcode)))
  (list (parse-field field "sw1a2aa")
        (handler-case (parse-field field "12")
          (field-error (e) (princ-to-string e)))))
;; ⇒ ("SW1A 2AA" "Postcode is not a postcode.")
```

#### `string-field` — class

A line of text, at most `:max-length` characters when given.
`:pattern` is a regular expression the whole value must match, and
`:pattern-message` the sentence shown when it does not.

*Example:* Text fields take `:max-length` and `:pattern` (a regular expression for the whole value, with `:pattern-message` to explain it).  Email and URL fields are text fields with a pattern of their own.

```lisp
(defclass shop ()
  ((code :initform nil)
   (contact :initform nil)
   (site :initform nil)))
(define-description shop
  ((code :pattern "[A-Z]{3}" :pattern-message "A code is three capital letters.")
   (contact :type :email)
   (site :type :url)))
(flet ((check (name value) (check-field (find-field 'shop name) value)))
  (list (check 'code "AB1")
        (check 'code "ABC")
        (check 'contact "shop.example.org")
        (check 'site "javascript:alert(1)")))
;; ⇒ ("A code is three capital letters." NIL "Contact must be an email address." "Site must be a web address starting http:// or https://.")
```

#### `text-field` — class

Several lines of text, entered in a text area and shown with
a line break after each.

*Example:* A text field holds several lines; it is shown with a line break after each.

```lisp
(defclass memo ()
  ((body :initform nil)))
(define-description memo
  ((body :type :text)))
(let ((field (find-field 'memo 'body)))
  (with-canvas-to-string ()
    (render-field-value field (parse-field field (format nil "Buy milk.~%Call Ada.~%~%")))))
;; ⇒ "Buy milk.<br>Call Ada.<br>"
```

#### `password-field` — class

Text that is never shown: its input starts empty, its value
is written as dots, and viewers, report columns and data grids leave it out.
Left blank in an editor or wizard for an object that has a value, it keeps
that value.

*Example:* A viewer shows an object's described values in a table, with a Close link that answers.  Password fields and `:hidden` fields are left out (and so are they from reports); hidden fields are left out of editors too.

```lisp
(defclass account ()
  ((login :initform "ada")
   (secret :initform "correct horse")
   (token :initform "x7f3")))
(define-description account
  ((login :required t)
   (secret :type :password)
   (token :hidden t)))
(defclass account-page (component) ())
(defmethod render ((self account-page))
  (render-component (make-viewer (make-instance 'account))))
(with-fresh-applications (("/account" 'account-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/account")
    (list (body-text b) (field-hidden-p (find-field 'account 'token)))))
;; ⇒ ("Login ada Close" T)
```

#### `email-field` — class

An email address: text with one @ and a dot after it.

*Example:* Text fields take `:max-length` and `:pattern` (a regular expression for the whole value, with `:pattern-message` to explain it).  Email and URL fields are text fields with a pattern of their own.

```lisp
(defclass shop ()
  ((code :initform nil)
   (contact :initform nil)
   (site :initform nil)))
(define-description shop
  ((code :pattern "[A-Z]{3}" :pattern-message "A code is three capital letters.")
   (contact :type :email)
   (site :type :url)))
(flet ((check (name value) (check-field (find-field 'shop name) value)))
  (list (check 'code "AB1")
        (check 'code "ABC")
        (check 'contact "shop.example.org")
        (check 'site "javascript:alert(1)")))
;; ⇒ ("A code is three capital letters." NIL "Contact must be an email address." "Site must be a web address starting http:// or https://.")
```

#### `url-field` — class

An http or https URL, shown as a link.

*Example:* Text fields take `:max-length` and `:pattern` (a regular expression for the whole value, with `:pattern-message` to explain it).  Email and URL fields are text fields with a pattern of their own.

```lisp
(defclass shop ()
  ((code :initform nil)
   (contact :initform nil)
   (site :initform nil)))
(define-description shop
  ((code :pattern "[A-Z]{3}" :pattern-message "A code is three capital letters.")
   (contact :type :email)
   (site :type :url)))
(flet ((check (name value) (check-field (find-field 'shop name) value)))
  (list (check 'code "AB1")
        (check 'code "ABC")
        (check 'contact "shop.example.org")
        (check 'site "javascript:alert(1)")))
;; ⇒ ("A code is three capital letters." NIL "Contact must be an email address." "Site must be a web address starting http:// or https://.")
```

#### `integer-field` — class

A whole number, between `:min` and `:max` when given.

*Example:* Whole numbers, between `:min` and `:max` when given.

```lisp
(defclass parcel ()
  ((weight :initform nil)))
(define-description parcel
  ((weight :type :integer :min 1 :max 30 :label "Weight (kg)")))
(let ((field (find-field 'parcel 'weight)))
  (list (parse-field field " 12 ")
        (check-field field 0)
        (handler-case (parse-field field "twelve")
          (field-error (e) (princ-to-string e)))))
;; ⇒ (12 "Weight (kg) must be at least 1." "Weight (kg) must be a whole number.")
```

#### `boolean-field` — class

Yes or no, entered as a checkbox.  Never required: unchecked
is an answer.

*Example:* Yes or no, entered as a checkbox: "on" is true, anything else false.

```lisp
(defclass alert ()
  ((urgent :initform nil)))
(define-description alert
  ((urgent :type :boolean)))
(let ((field (find-field 'alert 'urgent)))
  (list (parse-field field "on") (parse-field field "off") (format-field field t) (check-field field nil)))
;; ⇒ (T NIL "Yes" NIL)
```

#### `choice-field` — class

One of `:choices` (a list, or a function returning one each
time it is needed), shown through `:labels` (a function of a choice;
`princ-to-string` by default) and entered with a select.  Unless the field is
required, the select offers a blank option too.

*Example:* One of `:choices`, shown through `:labels`.  The input posts the chosen item's position; its label means it too.

```lisp
(defclass ticket ()
  ((priority :initform :normal)))
(define-description ticket
  ((priority :type :choice :choices '(:low :normal :high) :labels #'string-capitalize)))
(let ((field (find-field 'ticket 'priority)))
  (list (field-choices field)
        (parse-field field "2")
        (parse-field field "Low")
        (format-field field :normal)))
;; ⇒ ((:LOW :NORMAL :HIGH) :HIGH :LOW "Normal")
```

*Example:* `:choices` may be a function, called whenever the choices are needed, so they can change while a form is open.

```lisp
(defclass assignment ()
  ((assignee :initform nil)))
(defvar *team* (list "Ada" "Grace"))
(define-description assignment
  ((assignee :type :choice :choices (lambda () *team*))))
(let ((field (find-field 'assignment 'assignee)))
  (let ((*team* (list "Ada" "Grace" "Alan")))
    (field-choices field)))
;; ⇒ ("Ada" "Grace" "Alan")
```

#### `date-field` — class

A calendar date, held as (`year` `month` `day`) and written like
2026-10-06.

*Example:* A calendar date, held as (`year` `month` `day`) and written like 2026-07-01.

```lisp
(defclass trip ()
  ((leaves :initform '(2026 7 1))))
(define-description trip
  ((leaves :type :date)))
(let ((field (find-field 'trip 'leaves)))
  (list (format-field field (field-value field (make-instance 'trip)))
        (parse-field field "2028-2-29")))
;; ⇒ ("2026-07-01" (2028 2 29))
```

#### `field-choices` `field` — function

`field`'s choices now, calling its choices function when it has one.

*Example:* One of `:choices`, shown through `:labels`.  The input posts the chosen item's position; its label means it too.

```lisp
(defclass ticket ()
  ((priority :initform :normal)))
(define-description ticket
  ((priority :type :choice :choices '(:low :normal :high) :labels #'string-capitalize)))
(let ((field (find-field 'ticket 'priority)))
  (list (field-choices field)
        (parse-field field "2")
        (parse-field field "Low")
        (format-field field :normal)))
;; ⇒ ((:LOW :NORMAL :HIGH) :HIGH :LOW "Normal")
```

*Example:* `:choices` may be a function, called whenever the choices are needed, so they can change while a form is open.

```lisp
(defclass assignment ()
  ((assignee :initform nil)))
(defvar *team* (list "Ada" "Grace"))
(define-description assignment
  ((assignee :type :choice :choices (lambda () *team*))))
(let ((field (find-field 'assignment 'assignee)))
  (let ((*team* (list "Ada" "Grace" "Alan")))
    (field-choices field)))
;; ⇒ ("Ada" "Grace" "Alan")
```

#### `field-hidden-p` `object` — generic function

Reads the hidden of a field.  Stored and validated, but never shown: not in editors, viewers or reports.

*Example:* A viewer shows an object's described values in a table, with a Close link that answers.  Password fields and `:hidden` fields are left out (and so are they from reports); hidden fields are left out of editors too.

```lisp
(defclass account ()
  ((login :initform "ada")
   (secret :initform "correct horse")
   (token :initform "x7f3")))
(define-description account
  ((login :required t)
   (secret :type :password)
   (token :hidden t)))
(defclass account-page (component) ())
(defmethod render ((self account-page))
  (render-component (make-viewer (make-instance 'account))))
(with-fresh-applications (("/account" 'account-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/account")
    (list (body-text b) (field-hidden-p (find-field 'account 'token)))))
;; ⇒ ("Login ada Close" T)
```

#### `parse-field` `field string` — generic function

The value `string`, as typed, stands for; `nil` for blank.
Signals `field-error` when `string` is not acceptable input.

*Example:* Each field kind turns typed text into a value (`parse-field`), a value back into text (`format-field`), and says what is wrong with a value (`check-field`).  Blank input is `nil`.

```lisp
(defclass reading ()
  ((taken :initform nil)
   (level :initform nil)))
(define-description reading
  ((taken :type :date :required t)
   (level :type :integer :min 0 :max 10)))
(let ((taken (find-field 'reading 'taken))
      (level (find-field 'reading 'level)))
  (list (parse-field taken " 2026-10-06 ")
        (format-field taken '(2026 10 6))
        (parse-field level "  ")
        (check-field level 11)
        (check-field taken nil)))
;; ⇒ ((2026 10 6) "2026-10-06" NIL "Level must be at most 10." "Taken is required.")
```

*Example:* Text that is not a value of the field's kind signals `field-error`, whose message is what an editor shows.

```lisp
(defclass delivery ()
  ((due :initform nil)))
(define-description delivery
  ((due :type :date)))
(handler-case (parse-field (find-field 'delivery 'due) "2026-02-30")
  (field-error (e) (princ-to-string e)))
;; ⇒ "Due must be a date, like 2026-10-06."
```

*Example:* A field kind of your own: a class with methods for what differs, under a keyword in `*field-kinds*`.  `field-problem` signals the `field-error` that rejects input.  (Push onto `*field-kinds*` in your own code; the `let` keeps this example tidy.)

```lisp
(defclass postcode-field (string-field) ())
(defmethod parse-field ((field postcode-field) string)
  (let ((code (string-upcase (remove #\Space string))))
    (cond ((string= code "") nil)
          ((<= 5 (length code) 7)
           (format nil "~A ~A" (subseq code 0 (- (length code) 3)) (subseq code (- (length code) 3))))
          (t (field-problem "~A is not a postcode." (translate (field-label field)))))))
(defclass address ()
  ((postcode :initform nil)))
(let ((*field-kinds* (acons :postcode 'postcode-field *field-kinds*)))
  (define-description address
    ((postcode :type :postcode :required t))))
(let ((field (find-field 'address 'postcode)))
  (list (parse-field field "sw1a2aa")
        (handler-case (parse-field field "12")
          (field-error (e) (princ-to-string e)))))
;; ⇒ ("SW1A 2AA" "Postcode is not a postcode.")
```

#### `format-field` `field value` — generic function

`value` as text, for showing and for an input to start from.

*Example:* Each field kind turns typed text into a value (`parse-field`), a value back into text (`format-field`), and says what is wrong with a value (`check-field`).  Blank input is `nil`.

```lisp
(defclass reading ()
  ((taken :initform nil)
   (level :initform nil)))
(define-description reading
  ((taken :type :date :required t)
   (level :type :integer :min 0 :max 10)))
(let ((taken (find-field 'reading 'taken))
      (level (find-field 'reading 'level)))
  (list (parse-field taken " 2026-10-06 ")
        (format-field taken '(2026 10 6))
        (parse-field level "  ")
        (check-field level 11)
        (check-field taken nil)))
;; ⇒ ((2026 10 6) "2026-10-06" NIL "Level must be at most 10." "Taken is required.")
```

*Example:* A field kind of your own: a class with methods for what differs, under a keyword in `*field-kinds*`.  `field-problem` signals the `field-error` that rejects input.  (Push onto `*field-kinds*` in your own code; the `let` keeps this example tidy.)

```lisp
(defclass postcode-field (string-field) ())
(defmethod parse-field ((field postcode-field) string)
  (let ((code (string-upcase (remove #\Space string))))
    (cond ((string= code "") nil)
          ((<= 5 (length code) 7)
           (format nil "~A ~A" (subseq code 0 (- (length code) 3)) (subseq code (- (length code) 3))))
          (t (field-problem "~A is not a postcode." (translate (field-label field)))))))
(defclass address ()
  ((postcode :initform nil)))
(let ((*field-kinds* (acons :postcode 'postcode-field *field-kinds*)))
  (define-description address
    ((postcode :type :postcode :required t))))
(let ((field (find-field 'address 'postcode)))
  (list (parse-field field "sw1a2aa")
        (handler-case (parse-field field "12")
          (field-error (e) (princ-to-string e)))))
;; ⇒ ("SW1A 2AA" "Postcode is not a postcode.")
```

#### `check-field` `field value` — generic function

`nil` when `value` suits `field`, or a sentence saying why not.
Methods should call `call-next-method` to keep the general checks.

*Example:* Each field kind turns typed text into a value (`parse-field`), a value back into text (`format-field`), and says what is wrong with a value (`check-field`).  Blank input is `nil`.

```lisp
(defclass reading ()
  ((taken :initform nil)
   (level :initform nil)))
(define-description reading
  ((taken :type :date :required t)
   (level :type :integer :min 0 :max 10)))
(let ((taken (find-field 'reading 'taken))
      (level (find-field 'reading 'level)))
  (list (parse-field taken " 2026-10-06 ")
        (format-field taken '(2026 10 6))
        (parse-field level "  ")
        (check-field level 11)
        (check-field taken nil)))
;; ⇒ ((2026 10 6) "2026-10-06" NIL "Level must be at most 10." "Taken is required.")
```

*Example:* `render-field-input` writes the input an editor shows: give the input the `id`, start it from `text`, and pass `callback` what is submitted.  `render-field-value` writes a value for reading.  A `check-field` method adds a check, keeping the general ones with `call-next-method`.

```lisp
(defclass pence-field (integer-field) ())
(defmethod render-field-input ((field pence-field) id text callback)
  (text-input (:id id :value text :callback callback :inputmode "numeric" :placeholder "pence")))
(defmethod render-field-value ((field pence-field) value)
  (when value (text (format nil "£~D.~2,'0D" (floor value 100) (mod value 100)))))
(defmethod check-field ((field pence-field) value)
  (or (call-next-method)
      (when (and value (not (zerop (mod value 5))))
        "Prices end in 0 or 5.")))
(defclass item ()
  ((price :initform 1250)))
(let ((*field-kinds* (acons :pence 'pence-field *field-kinds*)))
  (define-description item
    ((price :type :pence :required t))))
(defclass price-page (component)
  ((item :initform (make-instance 'item) :reader item)))
(defmethod render ((self price-page))
  (render-component (make-viewer (item self)))
  (anchor (:callback (lambda () (show self (make-editor (item self))))) "Edit"))
(with-fresh-applications (("/price" 'price-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/price")
    (let ((before (body-text b)))
      (click b "Edit")
      (let ((input (not (null (search "inputmode=\"numeric\"" (browser-html b))))))
        (fill-in b "price" "1999")
        (press b "Save")
        (list before input (not (null (has-text-p b "Prices end in 0 or 5."))))))))
;; ⇒ ("Price £12.50 Close Edit" T T)
```

#### `render-field-input` `field id text callback` — generic function

Write the input for `field`, with the element id `id`, showing
`text`; `callback` receives what is submitted.  Editors, wizards and data grids
call it.

*Example:* `render-field-input` writes the input an editor shows: give the input the `id`, start it from `text`, and pass `callback` what is submitted.  `render-field-value` writes a value for reading.  A `check-field` method adds a check, keeping the general ones with `call-next-method`.

```lisp
(defclass pence-field (integer-field) ())
(defmethod render-field-input ((field pence-field) id text callback)
  (text-input (:id id :value text :callback callback :inputmode "numeric" :placeholder "pence")))
(defmethod render-field-value ((field pence-field) value)
  (when value (text (format nil "£~D.~2,'0D" (floor value 100) (mod value 100)))))
(defmethod check-field ((field pence-field) value)
  (or (call-next-method)
      (when (and value (not (zerop (mod value 5))))
        "Prices end in 0 or 5.")))
(defclass item ()
  ((price :initform 1250)))
(let ((*field-kinds* (acons :pence 'pence-field *field-kinds*)))
  (define-description item
    ((price :type :pence :required t))))
(defclass price-page (component)
  ((item :initform (make-instance 'item) :reader item)))
(defmethod render ((self price-page))
  (render-component (make-viewer (item self)))
  (anchor (:callback (lambda () (show self (make-editor (item self))))) "Edit"))
(with-fresh-applications (("/price" 'price-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/price")
    (let ((before (body-text b)))
      (click b "Edit")
      (let ((input (not (null (search "inputmode=\"numeric\"" (browser-html b))))))
        (fill-in b "price" "1999")
        (press b "Save")
        (list before input (not (null (has-text-p b "Prices end in 0 or 5."))))))))
;; ⇒ ("Price £12.50 Close Edit" T T)
```

#### `render-field-value` `field value` — generic function

Write `value` for reading, in a viewer or report.

*Example:* A text field holds several lines; it is shown with a line break after each.

```lisp
(defclass memo ()
  ((body :initform nil)))
(define-description memo
  ((body :type :text)))
(let ((field (find-field 'memo 'body)))
  (with-canvas-to-string ()
    (render-field-value field (parse-field field (format nil "Buy milk.~%Call Ada.~%~%")))))
;; ⇒ "Buy milk.<br>Call Ada.<br>"
```

*Example:* `render-field-input` writes the input an editor shows: give the input the `id`, start it from `text`, and pass `callback` what is submitted.  `render-field-value` writes a value for reading.  A `check-field` method adds a check, keeping the general ones with `call-next-method`.

```lisp
(defclass pence-field (integer-field) ())
(defmethod render-field-input ((field pence-field) id text callback)
  (text-input (:id id :value text :callback callback :inputmode "numeric" :placeholder "pence")))
(defmethod render-field-value ((field pence-field) value)
  (when value (text (format nil "£~D.~2,'0D" (floor value 100) (mod value 100)))))
(defmethod check-field ((field pence-field) value)
  (or (call-next-method)
      (when (and value (not (zerop (mod value 5))))
        "Prices end in 0 or 5.")))
(defclass item ()
  ((price :initform 1250)))
(let ((*field-kinds* (acons :pence 'pence-field *field-kinds*)))
  (define-description item
    ((price :type :pence :required t))))
(defclass price-page (component)
  ((item :initform (make-instance 'item) :reader item)))
(defmethod render ((self price-page))
  (render-component (make-viewer (item self)))
  (anchor (:callback (lambda () (show self (make-editor (item self))))) "Edit"))
(with-fresh-applications (("/price" 'price-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/price")
    (let ((before (body-text b)))
      (click b "Edit")
      (let ((input (not (null (search "inputmode=\"numeric\"" (browser-html b))))))
        (fill-in b "price" "1999")
        (press b "Save")
        (list before input (not (null (has-text-p b "Prices end in 0 or 5."))))))))
;; ⇒ ("Price £12.50 Close Edit" T T)
```

#### `field-error` — condition

Signalled by `parse-field` when input is not a value of the field's kind.

*Example:* Text that is not a value of the field's kind signals `field-error`, whose message is what an editor shows.

```lisp
(defclass delivery ()
  ((due :initform nil)))
(define-description delivery
  ((due :type :date)))
(handler-case (parse-field (find-field 'delivery 'due) "2026-02-30")
  (field-error (e) (princ-to-string e)))
;; ⇒ "Due must be a date, like 2026-10-06."
```

#### `field-problem` `format-control &rest arguments` — function

Signal a `field-error` whose message is `format-control`, translated, applied
to `arguments`.  For `parse-field` methods rejecting what was typed.

*Example:* A field kind of your own: a class with methods for what differs, under a keyword in `*field-kinds*`.  `field-problem` signals the `field-error` that rejects input.  (Push onto `*field-kinds*` in your own code; the `let` keeps this example tidy.)

```lisp
(defclass postcode-field (string-field) ())
(defmethod parse-field ((field postcode-field) string)
  (let ((code (string-upcase (remove #\Space string))))
    (cond ((string= code "") nil)
          ((<= 5 (length code) 7)
           (format nil "~A ~A" (subseq code 0 (- (length code) 3)) (subseq code (- (length code) 3))))
          (t (field-problem "~A is not a postcode." (translate (field-label field)))))))
(defclass address ()
  ((postcode :initform nil)))
(let ((*field-kinds* (acons :postcode 'postcode-field *field-kinds*)))
  (define-description address
    ((postcode :type :postcode :required t))))
(let ((field (find-field 'address 'postcode)))
  (list (parse-field field "sw1a2aa")
        (handler-case (parse-field field "12")
          (field-error (e) (princ-to-string e)))))
;; ⇒ ("SW1A 2AA" "Postcode is not a postcode.")
```

#### `validate` `object &optional (description object)` — function

What is wrong with `object`'s stored values, by `description` (by default its
class's): an alist of (`field-name` . `problem`) for the fields that fail
`check-field`.  When they all pass but the description's own `:validate` does
not, ((`nil` . `problem`)).  `nil` when all is well.

*Example:* Describe a class's fields once.  `validate` checks an object against its class's description and lists what is wrong, field by field.

```lisp
(defclass guest ()
  ((name :initarg :name :initform nil)
   (email :initarg :email :initform nil)
   (age :initarg :age :initform nil)))
(define-description guest
  ((name :required t :max-length 40)
   (email :type :email :required t)
   (age :type :integer :min 0 :max 150)))
(validate (make-instance 'guest :email "ada@" :age 200))
;; ⇒ ((NAME . "Name is required.") (EMAIL . "Email must be an email address.") (AGE . "Age must be at most 150."))
```

*Example:* `:validate` on the description checks the values together, as a plist keyed by keywords; it runs only once every field passes, and its problem comes back under `nil`.

```lisp
(defclass booking ()
  ((plan :initarg :plan :initform :personal)
   (seats :initarg :seats :initform 1)))
(define-description booking
  ((plan :type :choice :choices '(:personal :team))
   (seats :type :integer :min 1))
  :validate (lambda (values)
              (when (and (eq (getf values :plan) :personal) (> (getf values :seats) 1))
                "A personal plan has one seat.")))
(list (validate (make-instance 'booking :seats 3))
      (validate (make-instance 'booking :plan :team :seats 3)))
;; ⇒ (((NIL . "A personal plan has one seat.")) NIL)
```

#### `make-editor` `object &key (description object) title (save-label "Save") (write t)` — function

A `description-editor` for `object`, described by `description` (anything
`find-description` takes; by default `object`'s class), headed by `title` when
given, its submit button labelled `save-label` (translated).  Save parses and
checks every field that is neither read-only nor hidden, then the
description's own check, and shows the problems beside the inputs; once
they pass it writes the values to `object` and answers it.  With `write` `nil` it
leaves `object` alone and answers those values as a plist keyed by field name
keywords, for objects shared between sessions that the application changes
under its own lock.  Cancel answers `nil`.

*Example:* An editor is a form made from the description.  Save checks every field and shows the problems beside them; once they pass it writes the values to the object and answers it.  Cancel answers `nil` and leaves the object alone.

```lisp
(defclass guest ()
  ((name :initarg :name :initform nil)
   (email :initarg :email :initform nil)))
(define-description guest
  ((name :required t)
   (email :type :email :required t)))
(defclass guest-page (component)
  ((guest :initform (make-instance 'guest :name "Ada" :email "ada@example.org") :reader guest)))
(defmethod render ((self guest-page))
  (p () (text (slot-value (guest self) 'name)))
  (anchor (:callback (lambda () (show self (make-editor (guest self) :title "Edit guest")))) "Edit"))
(with-fresh-applications (("/guest" 'guest-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/guest")
    (click b "Edit")
    (fill-in b "name" "Ada Lovelace")
    (fill-in b "email" "nowhere")
    (press b "Save")
    (let ((problem (not (null (has-text-p b "Email must be an email address.")))))
      (fill-in b "email" "ada@lovelace.org")
      (press b "Save")
      (list problem (body-text b)))))
;; ⇒ (T "Ada Lovelace Edit")
```

*Example:* With `:write` `nil` the editor leaves the object alone and answers the values as a plist, for the application to store as it sees fit.

```lisp
(defclass topic ()
  ((title :initform "Lunch")
   (notes :initform nil)))
(define-description topic
  ((title :required t)
   (notes :type :text)))
(defclass topic-page (component)
  ((topic :initform (make-instance 'topic) :reader topic)
   (answer :initform nil :accessor editor-answer)))
(defmethod render ((self topic-page))
  (p () (text (prin1-to-string (editor-answer self))))
  (anchor (:callback (lambda ()
                       (show self (make-editor (topic self) :write nil :save-label "Propose")
                             :on-answer (lambda (values) (setf (editor-answer self) values)))))
    "Change"))
(with-fresh-applications (("/topic" 'topic-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/topic")
    (click b "Change")
    (fill-in b "title" "Dinner")
    (press b "Propose")
    (list (body-text b) (slot-value (topic (make-instance 'topic-page)) 'title))))
;; ⇒ ("(:TITLE \"Dinner\" :NOTES NIL) Change" "Lunch")
```

#### `make-viewer` `object &key (description object)` — function

A `description-viewer` of `object`, described by `description` (anything
`find-description` takes; by default `object`'s class).

*Example:* A viewer shows an object's described values in a table, with a Close link that answers.  Password fields and `:hidden` fields are left out (and so are they from reports); hidden fields are left out of editors too.

```lisp
(defclass account ()
  ((login :initform "ada")
   (secret :initform "correct horse")
   (token :initform "x7f3")))
(define-description account
  ((login :required t)
   (secret :type :password)
   (token :hidden t)))
(defclass account-page (component) ())
(defmethod render ((self account-page))
  (render-component (make-viewer (make-instance 'account))))
(with-fresh-applications (("/account" 'account-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/account")
    (list (body-text b) (field-hidden-p (find-field 'account 'token)))))
;; ⇒ ("Login ada Close" T)
```

#### `description-editor` — class

Edits an object through its description; answers the
object on Save (after writing the values back) and `nil` on Cancel.  Make one
with `make-editor`.

*Example:* An editor is a form made from the description.  Save checks every field and shows the problems beside them; once they pass it writes the values to the object and answers it.  Cancel answers `nil` and leaves the object alone.

```lisp
(defclass guest ()
  ((name :initarg :name :initform nil)
   (email :initarg :email :initform nil)))
(define-description guest
  ((name :required t)
   (email :type :email :required t)))
(defclass guest-page (component)
  ((guest :initform (make-instance 'guest :name "Ada" :email "ada@example.org") :reader guest)))
(defmethod render ((self guest-page))
  (p () (text (slot-value (guest self) 'name)))
  (anchor (:callback (lambda () (show self (make-editor (guest self) :title "Edit guest")))) "Edit"))
(with-fresh-applications (("/guest" 'guest-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/guest")
    (click b "Edit")
    (fill-in b "name" "Ada Lovelace")
    (fill-in b "email" "nowhere")
    (press b "Save")
    (let ((problem (not (null (has-text-p b "Email must be an email address.")))))
      (fill-in b "email" "ada@lovelace.org")
      (press b "Save")
      (list problem (body-text b)))))
;; ⇒ (T "Ada Lovelace Edit")
```

#### `description-viewer` — class

Shows an object's described values in a table, except
password and hidden fields, with a Close link that answers `nil`.  Make one
with `make-viewer`.

*Example:* A viewer shows an object's described values in a table, with a Close link that answers.  Password fields and `:hidden` fields are left out (and so are they from reports); hidden fields are left out of editors too.

```lisp
(defclass account ()
  ((login :initform "ada")
   (secret :initform "correct horse")
   (token :initform "x7f3")))
(define-description account
  ((login :required t)
   (secret :type :password)
   (token :hidden t)))
(defclass account-page (component) ())
(defmethod render ((self account-page))
  (render-component (make-viewer (make-instance 'account))))
(with-fresh-applications (("/account" 'account-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/account")
    (list (body-text b) (field-hidden-p (find-field 'account 'token)))))
;; ⇒ ("Login ada Close" T)
```

#### `description-columns` `description &rest names` — function

`report` columns for `description`'s fields: those named in `names`, in that
order, or else every field neither hidden nor `:in-report` `nil`.  Password
fields are always left out.  Each column writes its value with
`render-field-value` and sorts by it (dates by their text); integer columns
get the CSS class "number".

*Example:* Report columns made from a description: each shows its field the way a viewer does and sorts by its value.  Name fields to choose them; without names, every field not marked `:in-report` `nil`.

```lisp
(defclass book ()
  ((title :initarg :title)
   (year :initarg :year)
   (blurb :initarg :blurb :initform "")))
(define-description book
  ((title :required t)
   (year :type :integer)
   (blurb :type :text :in-report nil)))
(defclass shelf (report) ()
  (:default-initargs
   :rows (list (make-instance 'book :title "Emma" :year 1815)
               (make-instance 'book :title "Persuasion" :year 1817)
               (make-instance 'book :title "Ivanhoe" :year 1819))
   :columns (description-columns 'book)))
(with-fresh-applications (("/shelf" 'shelf :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/shelf")
    (click b "Title")
    (body-text b)))
;; ⇒ "Title ▲ Year Emma 1815 Ivanhoe 1819 Persuasion 1817"
```

### Backtracking

#### `snapshot` — class

The saved state of a page: what `take-snapshot` captured and `restore-snapshot` puts back.

*Example:* Littoral snapshots the page after every action and restores it when an old page is used.  A snapshot holds one entry for each object named in the visible components' states (and one for the decorations of each component not named).

```lisp
(defclass fuel-gauge (component)
  ((litres :initform 40 :accessor litres)))
(defmethod states ((self fuel-gauge)) (list self))
(let* ((gauge (make-instance 'fuel-gauge))
       (full (take-snapshot gauge)))
  (setf (litres gauge) 5)
  (restore-snapshot full)
  (list (litres gauge) (length (snapshot-entries full))))
;; ⇒ (40 1)
```

#### `take-snapshot` `root` — function

Capture the state of everything visible from `root`: the slots of each
object the visible components' `states` name, and the decorations of every
visible component.  Returns a `snapshot`.

*Example:* Littoral snapshots the page after every action and restores it when an old page is used.  A snapshot holds one entry for each object named in the visible components' states (and one for the decorations of each component not named).

```lisp
(defclass fuel-gauge (component)
  ((litres :initform 40 :accessor litres)))
(defmethod states ((self fuel-gauge)) (list self))
(let* ((gauge (make-instance 'fuel-gauge))
       (full (take-snapshot gauge)))
  (setf (litres gauge) 5)
  (restore-snapshot full)
  (list (litres gauge) (length (snapshot-entries full))))
;; ⇒ (40 1)
```

#### `restore-snapshot` `snapshot` — function

Put back what `snapshot` captured.

*Example:* Littoral snapshots the page after every action and restores it when an old page is used.  A snapshot holds one entry for each object named in the visible components' states (and one for the decorations of each component not named).

```lisp
(defclass fuel-gauge (component)
  ((litres :initform 40 :accessor litres)))
(defmethod states ((self fuel-gauge)) (list self))
(let* ((gauge (make-instance 'fuel-gauge))
       (full (take-snapshot gauge)))
  (setf (litres gauge) 5)
  (restore-snapshot full)
  (list (litres gauge) (length (snapshot-entries full))))
;; ⇒ (40 1)
```

#### `begin-isolation` `&optional (session *session*)` — function

Start a stretch of pages that `end-isolation` will make unreachable.
Returns a token for `end-isolation`; it is a plain value, so a flow can hold
it across CALLs.

*Example:* Once the order is placed, end-isolation forgets the pages of the checkout, so the back button cannot place it twice: an old page's link shows the session as it is now.

```lisp
(defclass ferry-booking (task)
  ((tickets :initform 0 :accessor tickets)))
(define-flow ferry-booking (self)
  (let ((isolation (begin-isolation)))
    (when (confirm self "Book a ticket?")
      (incf (tickets self))
      (end-isolation isolation)
      (inform self (format nil "Booked ~D ticket~:P." (tickets self))))))
(with-fresh-applications (("/ferry" 'ferry-booking :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/ferry")
    (let ((asked (browser-url b)))
      (press b "Yes")
      (let ((booked (body-text b)))
        (back-to b asked)
        (list booked (body-text b))))))
;; ⇒ ("Booked 1 ticket. OK" "Booked 1 ticket. OK")
```

#### `end-isolation` `token &optional (session *session*)` — function

Forget every page made since `begin-isolation` returned `token`, so the back
button cannot return into them (to place an order twice, say).  Going back
to one of them shows the session as it is now.  Returns how many pages it
forgot.

*Example:* Once the order is placed, end-isolation forgets the pages of the checkout, so the back button cannot place it twice: an old page's link shows the session as it is now.

```lisp
(defclass ferry-booking (task)
  ((tickets :initform 0 :accessor tickets)))
(define-flow ferry-booking (self)
  (let ((isolation (begin-isolation)))
    (when (confirm self "Book a ticket?")
      (incf (tickets self))
      (end-isolation isolation)
      (inform self (format nil "Booked ~D ticket~:P." (tickets self))))))
(with-fresh-applications (("/ferry" 'ferry-booking :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/ferry")
    (let ((asked (browser-url b)))
      (press b "Yes")
      (let ((booked (body-text b)))
        (back-to b asked)
        (list booked (body-text b))))))
;; ⇒ ("Booked 1 ticket. OK" "Booked 1 ticket. OK")
```

#### `deep` `object` — function

Name `object` in `states` as (`deep` `object`) to snapshot its lists, vectors,
strings and hash tables by copying them, not sharing them.

*Example:* Snapshots keep slot values as they are, so a list or hash table changed in place would change in every snapshot.  Naming the object as (deep object) copies them instead, and going back shows the table as it was.

```lisp
(defclass stock (component)
  ((counts :initform (make-hash-table :test 'equal) :reader counts)))
(defmethod states ((self stock)) (list (deep self)))
(defmethod render ((self stock))
  (p () "Rope: " (text (princ-to-string (gethash "rope" (counts self) 0))))
  (anchor (:callback (lambda () (incf (gethash "rope" (counts self) 0)))) "Add rope"))
(with-fresh-applications (("/stock" 'stock :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/stock")
    (click b "Add rope")
    (let ((one (browser-url b)))
      (click b "Add rope")
      (click b "Add rope")
      (back-to b one)
      (body-text b))))
;; ⇒ "Rope: 1 Add rope"
```

#### `deep-copy` `value &optional (seen (make-hash-table :test (quote eq)))` — function

A copy of `value`'s lists, vectors, strings and hash tables, all the way
down.  Other objects (instances, structures, symbols, numbers) are shared;
shared structure and cycles are kept.

*Example:* Lists, vectors, strings and hash tables are copied; shared structure stays shared, and other objects are not copied.

```lisp
(let* ((buoy (make-instance 'component))
       (pair (list 1 2))
       (value (list pair pair buoy))
       (copy (deep-copy value)))
  (list (eq (first copy) pair)
        (eq (first copy) (second copy))
        (eq (third copy) buoy)
        (equal (subseq copy 0 2) (subseq value 0 2))))
;; ⇒ (NIL T T T)
```

#### `snapshot-entries` `object` — generic function

Reads the entries of a snapshot.  List of (`object` . `saved`) where `saved` is what
`capture-state` returned for it.

*Example:* Littoral snapshots the page after every action and restores it when an old page is used.  A snapshot holds one entry for each object named in the visible components' states (and one for the decorations of each component not named).

```lisp
(defclass fuel-gauge (component)
  ((litres :initform 40 :accessor litres)))
(defmethod states ((self fuel-gauge)) (list self))
(let* ((gauge (make-instance 'fuel-gauge))
       (full (take-snapshot gauge)))
  (setf (litres gauge) 5)
  (restore-snapshot full)
  (list (litres gauge) (length (snapshot-entries full))))
;; ⇒ (40 1)
```

### Tasks

#### `task` — class

A component defined by a `flow` of calls.  It renders nothing
itself, only what it calls.  When the flow returns, the task answers its
value; a root task, which nothing called, starts its flow again.

*Example:* A task's flow reads as straight-line code: each call waits for the component's answer.  A root task starts its flow again when it ends.

```lisp
(defclass knot-quiz (task) ())
(define-flow knot-quiz (self)
  (let ((answer (choose-from self '("bowline" "reef knot" "clove hitch")
                             "Which knot makes a fixed loop?")))
    (if (equal answer "bowline")
        (inform self "Right.")
        (inform self "No: the bowline."))))
(with-fresh-applications (("/quiz" 'knot-quiz :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/quiz")
    (select-option b "Which knot makes a fixed loop?" "bowline")
    (press b "OK")
    (let ((verdict (body-text b)))
      (press b "OK")
      (list verdict (body-text b)))))
;; ⇒ ("Right. OK" "Which knot makes a fixed loop? bowline reef knot clove hitch OK Cancel")
```

#### `define-flow` `class (self) &body body` — macro

Define the flow of the task `class`, with `self` bound to the task.  Each
`call` in `body` (and `inform`, `confirm`, `request-input`, `choose-from`, `call-modal`)
waits for the called component's answer; the task answers `body`'s value.
`body` is rewritten with cl-cont, so no `unwind-protect`, `catch` or `handler-case`
may surround a `call`, and a variable `setq`'d after a `call` is shared by every
page resuming from it.

*Example:* A task's flow reads as straight-line code: each call waits for the component's answer.  A root task starts its flow again when it ends.

```lisp
(defclass knot-quiz (task) ())
(define-flow knot-quiz (self)
  (let ((answer (choose-from self '("bowline" "reef knot" "clove hitch")
                             "Which knot makes a fixed loop?")))
    (if (equal answer "bowline")
        (inform self "Right.")
        (inform self "No: the bowline."))))
(with-fresh-applications (("/quiz" 'knot-quiz :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/quiz")
    (select-option b "Which knot makes a fixed loop?" "bowline")
    (press b "OK")
    (let ((verdict (body-text b)))
      (press b "OK")
      (list verdict (body-text b)))))
;; ⇒ ("Right. OK" "Which knot makes a fixed loop? bowline reef knot clove hitch OK Cancel")
```

*Example:* A task another component calls answers what its flow returns.  The back button works inside the flow: going back to the second question and answering again resumes from there.

```lisp
(defclass passage-plan (task) ())
(define-flow passage-plan (self)
  (let ((from (request-input self "From?")))
    (let ((to (request-input self "To?")))
      (list from to))))
(defclass chart-table (component)
  ((plan :initform nil :accessor plan)))
(defmethod states ((self chart-table)) (list self))
(defmethod render ((self chart-table))
  (p () "Plan: " (text (format nil "~{~A~^ to ~}" (plan self))))
  (anchor (:callback (lambda ()
                       (show self (make-instance 'passage-plan)
                             :on-answer (lambda (plan) (setf (plan self) plan)))))
    "Plan a passage"))
(with-fresh-applications (("/chart" 'chart-table :mode :deployment))
  (let ((b (make-instance 'browser)))
    (flet ((type-and-press (question text)
             (fill-in b question text)
             (press b "OK")))
      (visit b "/chart")
      (click b "Plan a passage")
      (type-and-press "From?" "Dover")
      (let ((second-question (browser-url b)))
        (type-and-press "To?" "Calais")
        (let ((first-plan (body-text b)))
          (back-to b second-question)
          (type-and-press "To?" "Boulogne")
          (list first-plan (body-text b)))))))
;; ⇒ ("Plan: Dover to Calais Plan a passage" "Plan: Dover to Boulogne Plan a passage")
```

#### `flow` `task` — generic function

The body of `task`.  Define methods with `define-flow`.

*Example:* A task's flow reads as straight-line code: each call waits for the component's answer.  A root task starts its flow again when it ends.

```lisp
(defclass knot-quiz (task) ())
(define-flow knot-quiz (self)
  (let ((answer (choose-from self '("bowline" "reef knot" "clove hitch")
                             "Which knot makes a fixed loop?")))
    (if (equal answer "bowline")
        (inform self "Right.")
        (inform self "No: the bowline."))))
(with-fresh-applications (("/quiz" 'knot-quiz :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/quiz")
    (select-option b "Which knot makes a fixed loop?" "bowline")
    (press b "OK")
    (let ((verdict (body-text b)))
      (press b "OK")
      (list verdict (body-text b)))))
;; ⇒ ("Right. OK" "Which knot makes a fixed loop? bowline reef knot clove hitch OK Cancel")
```

### AJAX and push

#### `ajax` `&key callback update value confirm on-complete` — function

For an `:on-click`, `:on-change`, `:on-input` or `:on-submit` attribute: post
`callback`, a function of no arguments, in the background (with the element's
field, or its form for a submit button), then re-render the component or
list of components `update`, which must be `updatable`, in place.  Either may be
left out.

`value` is a JavaScript expression evaluated in the browser, with this bound
to the element; when given, `callback` takes one argument, its result as a
string.  `callback`'s return value goes back to the browser (as JSON), where
`on-complete`, a JavaScript snippet, can use it as value.  `confirm` is a
question the user must accept before anything is sent.

*Example:* The button posts its callback in the background and gets back the new HTML of the components to :update, which must be `updatable`.  `ajax-request` posts it as littoral.js does; the reply is JSON.

```lisp
(defclass likes (component updatable)
  ((count :initform 0 :accessor like-count)))
(defmethod render ((self likes))
  (text (format nil "~D likes " (like-count self)))
  (button (:on-click (ajax :callback (lambda () (incf (like-count self))) :update self))
    "Like"))
(with-fresh-applications (("/likes" 'likes :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/likes")
    (destructuring-bind (callback . targets) (first (ajax-specs b "on-click"))
      (let ((reply (com.inuoe.jzon:parse (ajax-request b callback targets))))
        (mapcar #'strip-tags (alexandria:hash-table-values (gethash "fragments" reply)))))))
;; ⇒ ("1 likes Like")
```

*Example:* `:value` is JavaScript the browser evaluates; the callback gets its result as a string, and what the callback returns goes back to the `:on-complete` snippet as value.  `:confirm` asks the user first.  Here the request carries the value the browser would have sent.

```lisp
(defclass size-probe (component) ())
(defmethod render ((self size-probe))
  (button (:on-click (ajax :value "window.innerWidth + 'x' + window.innerHeight"
                           :callback (lambda (size) (format nil "The server saw ~A." size))
                           :on-complete "document.title = value"
                           :confirm "Send your window size?"))
    "Measure"))
(with-fresh-applications (("/probe" 'size-probe :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/probe")
    (destructuring-bind (callback . targets) (first (ajax-specs b "on-click"))
      (gethash "value" (com.inuoe.jzon:parse
                        (ajax-request b callback targets :fields '(("_lt_value" . "1280x800"))))))))
;; ⇒ "The server saw 1280x800."
```

#### `ajax-update` `&rest components` — function

For an `:on-click`, `:on-change`, `:on-input` or `:on-submit` attribute:
re-render `components` (`updatable`) in place, running no callback first.  The
element's field is still posted, so its own `:callback` runs.

*Example:* Re-render components without a callback of their own: here the field's own callback stores what was typed, and the preview is redrawn on every keystroke.

```lisp
(defclass search-box (component)
  ((query :initform "" :accessor query)
   (preview :reader preview)))
(defclass search-preview (component updatable)
  ((box :initarg :box :reader box)))
(defmethod initialize-instance :after ((self search-box) &key)
  (setf (slot-value self 'preview) (make-instance 'search-preview :box self)))
(defmethod children ((self search-box)) (list (preview self)))
(defmethod render ((self search-preview))
  (p () (text (format nil "Searching for ~S" (query (box self))))))
(defmethod render ((self search-box))
  (text-input (:id "q" :label "Search" :value (query self)
               :callback (lambda (v) (setf (query self) v))
               :on-input (ajax-update (preview self))))
  (render-component (preview self)))
(with-fresh-applications (("/search" 'search-box :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/search")
    (destructuring-bind (callback . targets) (first (ajax-specs b "on-input"))
      (ajax-request b callback targets :fields (list (cons (element-name b "q") "otters"))))
    (visit b (browser-url b))
    (body-text b)))
;; ⇒ "Searching for \"otters\""
```

#### `periodical` `seconds &key callback update` — function

For a `:periodical` attribute: every `seconds` while the page is open, run
`callback` (a function of no arguments, or `nil`) and re-render the component or
list of components `update`, which must be `updatable`.

*Example:* For a `:periodical` attribute: littoral.js runs the callback and redraws the components every few seconds.  The attribute holds the interval in milliseconds, then the callback and the components; here one tick is posted by hand.

```lisp
(defclass ticker (component updatable)
  ((ticks :initform 0 :accessor ticks)))
(defmethod render ((self ticker))
  (span (:periodical (periodical 5 :callback (lambda () (incf (ticks self))) :update self))
    (text (format nil "Ticks: ~D" (ticks self)))))
(with-fresh-applications (("/ticker" 'ticker :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/ticker")
    (destructuring-bind (interval . rest) (first (ajax-specs b "periodical"))
      (let ((semicolon (position #\; rest)))
        (ajax-request b (subseq rest 0 semicolon) (subseq rest (1+ semicolon))))
      (visit b (browser-url b))
      (list interval (body-text b)))))
;; ⇒ ("5000" "Ticks: 1")
```

#### `execute-script` `javascript` — function

Run `javascript` in the browser once the current AJAX request's updates are
in place.  Outside an AJAX request it does nothing and returns `nil`.

*Example:* From an AJAX callback, queue JavaScript for the browser to run once the updates are in.  Outside an AJAX request it does nothing.

```lisp
(defclass retitler (component) ())
(defmethod render ((self retitler))
  (button (:on-click (ajax :callback (lambda () (execute-script "document.title = 'Saved'"))))
    "Save"))
(with-fresh-applications (("/retitle" 'retitler :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/retitle")
    (destructuring-bind (callback . targets) (first (ajax-specs b "on-click"))
      (gethash "scripts" (com.inuoe.jzon:parse (ajax-request b callback targets))))))
;; ⇒ #("document.title = 'Saved'")
(execute-script "alert('not now')")
;; ⇒ NIL
```

#### `channel` — class

Something components can subscribe to and threads `publish`.

*Example:* A component names the channels it listens to; a page showing one opens an event stream.  `publish`, from any thread, redraws the subscribers on every open page.  `open-stream` reads the page's stream as its EventSource would.

```lisp
(defvar *news* (make-channel "news"))
(defvar *headline* "Calm seas")
(defclass headline (component updatable) ())
(defmethod subscriptions ((self headline)) (list *news*))
(defmethod render ((self headline))
  (p () (text *headline*)))
(defclass front-page (component)
  ((headline :initform (make-instance 'headline) :reader headline)))
(defmethod children ((self front-page)) (list (headline self)))
(defmethod render ((self front-page))
  (h1 () "The Littoral Times")
  (render-component (headline self)))
(with-fresh-applications (("/news" 'front-page :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/news") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (setf *headline* "Storm warning")
    (publish *news*)
    (prog1 (wait-for (lambda () (search "Storm warning" (sink-text sink))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ T
```

#### `make-channel` `&optional name` — function

A new channel, named `name` for printing.

*Example:* A component names the channels it listens to; a page showing one opens an event stream.  `publish`, from any thread, redraws the subscribers on every open page.  `open-stream` reads the page's stream as its EventSource would.

```lisp
(defvar *news* (make-channel "news"))
(defvar *headline* "Calm seas")
(defclass headline (component updatable) ())
(defmethod subscriptions ((self headline)) (list *news*))
(defmethod render ((self headline))
  (p () (text *headline*)))
(defclass front-page (component)
  ((headline :initform (make-instance 'headline) :reader headline)))
(defmethod children ((self front-page)) (list (headline self)))
(defmethod render ((self front-page))
  (h1 () "The Littoral Times")
  (render-component (headline self)))
(with-fresh-applications (("/news" 'front-page :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/news") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (setf *headline* "Storm warning")
    (publish *news*)
    (prog1 (wait-for (lambda () (search "Storm warning" (sink-text sink))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ T
```

#### `subscriptions` `component` — generic function

The channels whose `publish` re-renders `component` on open pages;
none by default.  A page showing a component with subscriptions opens an
event stream.  Subscribers must be `updatable`.

*Example:* A component names the channels it listens to; a page showing one opens an event stream.  `publish`, from any thread, redraws the subscribers on every open page.  `open-stream` reads the page's stream as its EventSource would.

```lisp
(defvar *news* (make-channel "news"))
(defvar *headline* "Calm seas")
(defclass headline (component updatable) ())
(defmethod subscriptions ((self headline)) (list *news*))
(defmethod render ((self headline))
  (p () (text *headline*)))
(defclass front-page (component)
  ((headline :initform (make-instance 'headline) :reader headline)))
(defmethod children ((self front-page)) (list (headline self)))
(defmethod render ((self front-page))
  (h1 () "The Littoral Times")
  (render-component (headline self)))
(with-fresh-applications (("/news" 'front-page :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/news") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (setf *headline* "Storm warning")
    (publish *news*)
    (prog1 (wait-for (lambda () (search "Storm warning" (sink-text sink))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ T
```

#### `publish` `channel` — function

Re-render, on every open page, the visible components subscribed to `channel`.
Safe to call from any thread: it only queues the work, which each page's
stream does.  Returns the number of open pages woken, whether or not they
show a subscriber.

*Example:* A component names the channels it listens to; a page showing one opens an event stream.  `publish`, from any thread, redraws the subscribers on every open page.  `open-stream` reads the page's stream as its EventSource would.

```lisp
(defvar *news* (make-channel "news"))
(defvar *headline* "Calm seas")
(defclass headline (component updatable) ())
(defmethod subscriptions ((self headline)) (list *news*))
(defmethod render ((self headline))
  (p () (text *headline*)))
(defclass front-page (component)
  ((headline :initform (make-instance 'headline) :reader headline)))
(defmethod children ((self front-page)) (list (headline self)))
(defmethod render ((self front-page))
  (h1 () "The Littoral Times")
  (render-component (headline self)))
(with-fresh-applications (("/news" 'front-page :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/news") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (setf *headline* "Storm warning")
    (publish *news*)
    (prog1 (wait-for (lambda () (search "Storm warning" (sink-text sink))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ T
```

#### `notify` `component &optional (session *session*)` — function

Re-render `component` on `session`'s open pages.  Safe to call from any
thread, given the session (capture `*session*` in the callback that starts
the work).

*Example:* `notify` redraws one component on one session's pages: for work another thread does for that session.  The thread changes the component inside `with-session`, as a request would, holding the session's lock.  The page listens because the inbox subscribes to a channel.  A real application would capture `*session*` in the callback that starts the work.

```lisp
(defvar *mail* (make-channel "mail"))
(defclass inbox (component updatable)
  ((unread :initform 0 :accessor unread)))
(defmethod subscriptions ((self inbox)) (list *mail*))
(defmethod render ((self inbox))
  (p () (text (format nil "~D unread" (unread self)))))
(defclass mail-page (component)
  ((inbox :initform (make-instance 'inbox) :reader inbox)))
(defmethod children ((self mail-page)) (list (inbox self)))
(defmethod render ((self mail-page))
  (render-component (inbox self)))
(with-fresh-applications (("/mail" 'mail-page :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/mail") (open-stream b sink)))
         (session (first (list-sessions (find-application "/mail"))))
         (inbox (inbox (session-root session))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (sb-thread:join-thread
     (sb-thread:make-thread
      (lambda ()
        (with-session (session) (incf (unread inbox) 3))
        (notify inbox session))))
    (prog1 (wait-for (lambda () (search "3 unread" (sink-text sink))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ T
```

#### `close-event-streams` — function

End every open stream; browsers reconnect when their page is current.

*Example:* End every open stream, as when stopping the server; a browser whose page is still current reconnects.

```lisp
(defvar *alerts* (make-channel "alerts"))
(defclass alert-bar (component updatable) ())
(defmethod subscriptions ((self alert-bar)) (list *alerts*))
(defmethod render ((self alert-bar)) (p () "No alerts"))
(with-fresh-applications (("/alerts" 'alert-bar :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/alerts") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (close-event-streams)
    (wait-for (lambda () (not (sb-thread:thread-alive-p stream))))))
;; ⇒ T
```

#### `*keepalive-seconds*` — variable

How often an idle stream sends a comment.  Writing is how a closed page
is noticed, so this bounds how long a gone page keeps its server thread.

#### `with-session` `(session) &body body` — macro

Run `body` as `session`'s requests do: holding its lock, with `*session*` bound.
For other threads that change a session's components.

*Example:* `notify` redraws one component on one session's pages: for work another thread does for that session.  The thread changes the component inside `with-session`, as a request would, holding the session's lock.  The page listens because the inbox subscribes to a channel.  A real application would capture `*session*` in the callback that starts the work.

```lisp
(defvar *mail* (make-channel "mail"))
(defclass inbox (component updatable)
  ((unread :initform 0 :accessor unread)))
(defmethod subscriptions ((self inbox)) (list *mail*))
(defmethod render ((self inbox))
  (p () (text (format nil "~D unread" (unread self)))))
(defclass mail-page (component)
  ((inbox :initform (make-instance 'inbox) :reader inbox)))
(defmethod children ((self mail-page)) (list (inbox self)))
(defmethod render ((self mail-page))
  (render-component (inbox self)))
(with-fresh-applications (("/mail" 'mail-page :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/mail") (open-stream b sink)))
         (session (first (list-sessions (find-application "/mail"))))
         (inbox (inbox (session-root session))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (sb-thread:join-thread
     (sb-thread:make-thread
      (lambda ()
        (with-session (session) (incf (unread inbox) 3))
        (notify inbox session))))
    (prog1 (wait-for (lambda () (search "3 unread" (sink-text sink))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ T
```

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

A description's fields in steps, with a review before
finishing.  Make one with `make-wizard`.

*Example:* A wizard shows a description's fields in steps.  Next checks the step's fields before moving on; the last step reviews everything, and Finish writes the values to the object and answers it.

```lisp
(defclass signup ()
  ((name :initform nil)
   (email :initform nil)
   (seats :initform 1)))
(define-description signup
  ((name :required t)
   (email :type :email :required t)
   (seats :type :integer :min 1)))
(defclass welcome (component)
  ((user :initform nil :accessor user)))
(defmethod render ((self welcome))
  (if (user self)
      (p () (text (format nil "Welcome, ~A!" (slot-value (user self) 'name))))
      (anchor (:callback (lambda ()
                           (show self (make-wizard (make-instance 'signup)
                                                   :title "Sign up"
                                                   :steps '(("Account" name email) ("Team" seats)))
                                 :on-answer (lambda (signup) (setf (user self) signup)))))
        "Sign up")))
(with-fresh-applications (("/welcome" 'welcome :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/welcome")
    (click b "Sign up")
    (press b "Next")
    (let ((problem (not (null (has-text-p b "Name is required.")))))
      (fill-in b "name" "Ada")
      (fill-in b "email" "ada@example.org")
      (press b "Next")
      (fill-in b "seats" "3")
      (press b "Next")
      (let ((review (body-text b)))
        (press b "Finish")
        (list problem review (body-text b))))))
;; ⇒ (T "Sign up 1 Account 2 Team 3 Review Review Name Ada Change Email ada@example.org Change Seats 3 Change Back Finish Cancel" "Welcome, Ada!")
```

#### `make-wizard` `object &key (description object) steps title (write t)` — function

A `wizard` for `object`, described by `description` (anything `find-description`
takes; by default `object`'s class), headed by `title` when given.  `steps` is a
list of (`title` `field-name` …), one for each step; without it, each field not
hidden is a step, titled by its label.  Next checks the step's fields
before moving on and Back keeps what was typed.  After the last step comes
a review of every value, with a link back to each step; Finish checks
everything and then the description's own check, writes the values to
`object` and answers it.  With `write` `nil` it leaves `object` alone and answers
the values as a plist keyed by field name keywords.  Cancel answers `nil`.

*Example:* A wizard shows a description's fields in steps.  Next checks the step's fields before moving on; the last step reviews everything, and Finish writes the values to the object and answers it.

```lisp
(defclass signup ()
  ((name :initform nil)
   (email :initform nil)
   (seats :initform 1)))
(define-description signup
  ((name :required t)
   (email :type :email :required t)
   (seats :type :integer :min 1)))
(defclass welcome (component)
  ((user :initform nil :accessor user)))
(defmethod render ((self welcome))
  (if (user self)
      (p () (text (format nil "Welcome, ~A!" (slot-value (user self) 'name))))
      (anchor (:callback (lambda ()
                           (show self (make-wizard (make-instance 'signup)
                                                   :title "Sign up"
                                                   :steps '(("Account" name email) ("Team" seats)))
                                 :on-answer (lambda (signup) (setf (user self) signup)))))
        "Sign up")))
(with-fresh-applications (("/welcome" 'welcome :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/welcome")
    (click b "Sign up")
    (press b "Next")
    (let ((problem (not (null (has-text-p b "Name is required.")))))
      (fill-in b "name" "Ada")
      (fill-in b "email" "ada@example.org")
      (press b "Next")
      (fill-in b "seats" "3")
      (press b "Next")
      (let ((review (body-text b)))
        (press b "Finish")
        (list problem review (body-text b))))))
;; ⇒ (T "Sign up 1 Account 2 Team 3 Review Review Name Ada Change Email ada@example.org Change Seats 3 Change Back Finish Cancel" "Welcome, Ada!")
```

*Example:* Without `:steps`, each field not hidden is a step of its own, titled by its label.  With `:write` `nil`, Finish leaves the object alone and answers the values as a plist.  `wizard-step` is the step shown, counting from 0; setting it to the number of steps goes to the review.

```lisp
(defclass survey ()
  ((colour :initarg :colour :initform nil)
   (lucky :initform nil)))
(define-description survey
  ((colour :label "Favourite colour")
   (lucky :type :integer :label "Lucky number")))
(defclass survey-page (component)
  ((answers :initform nil :accessor answers)))
(defmethod render ((self survey-page))
  (if (answers self)
      (p () (text (prin1-to-string (answers self))))
      (anchor (:callback (lambda ()
                           (let ((wizard (make-wizard (make-instance 'survey :colour "Teal") :write nil)))
                             (setf (wizard-step wizard) 2)
                             (show self wizard :on-answer (lambda (values) (setf (answers self) values))))))
        "Take the survey")))
(with-fresh-applications (("/survey" 'survey-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/survey")
    (click b "Take the survey")
    (let ((review (body-text b)))
      (press b "Finish")
      (list review (body-text b)))))
;; ⇒ ("1 Favourite colour 2 Lucky number 3 Review Review Favourite colour Teal Change Lucky number Change Back Finish Cancel" "(:COLOUR \"Teal\" :LUCKY NIL)")
```

#### `wizard-step` `object` — generic function

Reads the step of a wizard.  The step shown, counting from 0; the number of steps for the review.

*Example:* Without `:steps`, each field not hidden is a step of its own, titled by its label.  With `:write` `nil`, Finish leaves the object alone and answers the values as a plist.  `wizard-step` is the step shown, counting from 0; setting it to the number of steps goes to the review.

```lisp
(defclass survey ()
  ((colour :initarg :colour :initform nil)
   (lucky :initform nil)))
(define-description survey
  ((colour :label "Favourite colour")
   (lucky :type :integer :label "Lucky number")))
(defclass survey-page (component)
  ((answers :initform nil :accessor answers)))
(defmethod render ((self survey-page))
  (if (answers self)
      (p () (text (prin1-to-string (answers self))))
      (anchor (:callback (lambda ()
                           (let ((wizard (make-wizard (make-instance 'survey :colour "Teal") :write nil)))
                             (setf (wizard-step wizard) 2)
                             (show self wizard :on-answer (lambda (values) (setf (answers self) values))))))
        "Take the survey")))
(with-fresh-applications (("/survey" 'survey-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/survey")
    (click b "Take the survey")
    (let ((review (body-text b)))
      (press b "Finish")
      (list review (body-text b)))))
;; ⇒ ("1 Favourite colour 2 Lucky number 3 Review Review Favourite colour Teal Change Lucky number Change Back Finish Cancel" "(:COLOUR \"Teal\" :LUCKY NIL)")
```

### More widgets

#### `data-grid` — class

A table of a description's objects: a filter box per column,
sorting by column, paging, and editing a row in place with the description's
own inputs and validation.  `:description` names the description (anything
`find-description` takes) and `:rows` gives the objects (a list, or a function
returning one, called on every render).  `:fields` lists the field names to
show; by default those in reports, without password fields.  `:page-size` is
the rows per page (10).  After an edit is written to an object, `:on-save` is
called with it.  Filtering, sorting and paging go over AJAX.

*Example:* A data grid shows a description's objects in a table and edits a row in place, with the description's own inputs and checks.  `:on-save` is called with the object once an edit is written to it.

```lisp
(defclass person ()
  ((name :initarg :name)
   (email :initarg :email)))
(define-description person
  ((name :required t)
   (email :type :email :required t)))
(defclass people (component)
  ((grid :reader grid)
   (saved :initform nil :accessor saved)))
(defmethod initialize-instance :after ((self people) &key)
  (setf (slot-value self 'grid)
        (make-instance 'data-grid
                       :description 'person
                       :rows (list (make-instance 'person :name "Ada" :email "ada@example.org")
                                   (make-instance 'person :name "Alan" :email "alan@example.org"))
                       :on-save (lambda (person) (setf (saved self) (slot-value person 'name))))))
(defmethod states ((self people))
  (list self))
(defmethod children ((self people))
  (list (grid self)))
(defmethod render ((self people))
  (render-component (grid self))
  (when (saved self) (p () "Saved " (text (saved self)))))
(with-fresh-applications (("/people" 'people :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/people")
    (click-nth b "Edit" 1)
    (fill-in b "grid-email" "turing@example.org")
    (press b "Save")
    (body-text b)))
;; ⇒ "Name Email Actions Ada ada@example.org Edit Alan turing@example.org Edit 2 rows Saved Alan"
```

*Example:* Each column has a filter box; littoral.js sends what is typed over AJAX and the grid redraws with the rows that match.  `:fields` chooses the columns and `:page-size` the rows per page (10 by default).

```lisp
(defclass city ()
  ((name :initarg :name)
   (country :initarg :country)))
(define-description city
  ((name :required t)
   (country :required t)))
(defclass cities (data-grid) ()
  (:default-initargs
   :description 'city
   :fields '(name)
   :page-size 2
   :rows (list (make-instance 'city :name "Lyon" :country "France")
               (make-instance 'city :name "Lille" :country "France")
               (make-instance 'city :name "Leeds" :country "England")
               (make-instance 'city :name "York" :country "England"))))
(with-fresh-applications (("/cities" 'cities :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/cities")
    (let* ((before (body-text b))
           (typing (first (ajax-specs b "on-input")))
           (filter (element-name b (cl-ppcre:register-groups-bind (id) ("<input[^>]*id=\"([^\"]+)\"" (browser-html b)) id)))
           (json (ajax-request b (first typing) (rest typing) :fields (list (cons filter "ly")))))
      (list before (not (null (search "1 row" json))) (not (null (search "Lille" json)))))))
;; ⇒ ("Name Actions Lyon Edit Lille Edit 4 rows 1 / 2 Next »" T NIL)
```

#### `bar-chart` `data &key (title "") (width 480) (height 220) (format-value (function princ-to-string))` — function

Write a bar chart of `data`, a list of (`label` . `value`) with `value` a
non-negative number, as accessible SVG: a figure captioned by `title`, each
bar titled with its label and value, and the data as a table for screen
readers.  `format-value`, a function of a number, writes the values and the
axis.  `width` and `height` are in SVG units; the chart scales to fit.

*Example:* A bar chart is SVG in a figure, captioned by `title`, with the data as a table for screen readers.  Each bar's title gives its label and value, written by `:format-value`.

```lisp
(let ((html (with-canvas-to-string ()
              (bar-chart '(("Mon" . 3) ("Tue" . 7) ("Wed" . 5))
                         :title "Orders"
                         :format-value (lambda (n) (format nil "~D orders" n))))))
  (list (cl-ppcre:all-matches-as-strings "<title>[^<]*</title>" html)
        (not (null (search "<figcaption" html)))))
;; ⇒ (("<title>Mon: 3 orders</title>" "<title>Tue: 7 orders</title>" "<title>Wed: 5 orders</title>") T)
```

#### `line-chart` `series &key (title "") (width 480) (height 220) x-labels (format-value (function princ-to-string))` — function

Write a line chart of `series`, a list of (`name` . `values`), the values all
the same length and non-negative, as accessible SVG, like `bar-chart`: a
figure captioned by `title`, with the data as a table.  `x-labels` name the
points; `format-value` writes the values and the axis.  More than one series
gets a legend.

*Example:* One line per series, each a name and its values; `:x-labels` name the points.  With more than one series the chart has a legend.

```lisp
(let ((html (with-canvas-to-string ()
              (line-chart '(("Visits" 10 40 25) ("Sign-ups" 1 4 2))
                          :title "This week" :x-labels '("Mon" "Tue" "Wed")))))
  (list (length (cl-ppcre:all-matches-as-strings "<polyline" html))
        (cl-ppcre:all-matches-as-strings "● [^<]*" html)))
;; ⇒ (2 ("● Visits" "● Sign-ups"))
```

#### `sparkline` `values &key (label "") (width 120) (height 28)` — function

Write a small line of `values`, non-negative numbers, as SVG `width` by
`height` pixels, with `label` for screen readers.  No axes, no figure.

*Example:* A small line with no axes, labelled for screen readers.

```lisp
(with-canvas-to-string ()
  (sparkline '(1 3 2) :label "Errors this hour" :width 40 :height 10))
;; ⇒ "<svg class=\"lt-sparkline\" width=\"40\" height=\"10\" viewBox=\"0 0 40 10\" role=\"img\" aria-label=\"Errors this hour\"><polyline points=\"1.0,6.3 20.0,1.0 39.0,3.7\"/></svg>"
```

#### `calendar` — class

A month of days, Monday first, with their events, and links
to the months before and after.  `:year` and `:month` (1 to 12) say which month
to show first, by default the current one.  `:events` are (`date` . `title`)
pairs, `date` as (`year` `month` `day`): a list, or a function returning one.  With
`:on-select` each day is a link calling it with that day's date.

*Example:* A month of days with their events, Monday first.  `:year` and `:month` default to the current month.

```lisp
(let* ((calendar (make-instance 'calendar :year 2026 :month 10
                                          :events '(((2026 10 9) . "Release"))))
       (html (with-canvas-to-string () (render calendar))))
  (list (calendar-year calendar) (calendar-month calendar)
        (not (null (search "October 2026" html)))
        (not (null (search "<li>Release</li>" html)))))
;; ⇒ (2026 10 T T)
```

*Example:* With `:on-select`, each day is a link that calls it with the date.  The arrows go to the months before and after.

```lisp
(defclass planner (component)
  ((calendar :reader planner-calendar)
   (day :initform nil :accessor day)))
(defmethod initialize-instance :after ((self planner) &key)
  (setf (slot-value self 'calendar)
        (make-instance 'calendar :year 2026 :month 10
                                 :on-select (lambda (date) (setf (day self) date)))))
(defmethod states ((self planner))
  (list self))
(defmethod children ((self planner))
  (list (planner-calendar self)))
(defmethod render ((self planner))
  (render-component (planner-calendar self))
  (when (day self) (p (:id "chosen") (text (format nil "Chose ~{~D-~2,'0D-~2,'0D~}" (day self))))))
(with-fresh-applications (("/planner" 'planner :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/planner")
    (click b "›")
    (click b "9")
    (list (not (null (has-text-p b "November 2026")))
          (cl-ppcre:scan-to-strings "Chose \\S+" (body-text b)))))
;; ⇒ (T "Chose 2026-11-09")
```

#### `calendar-year` `object` — generic function

Reads the year of a calendar.  The year of the month shown.

*Example:* A month of days with their events, Monday first.  `:year` and `:month` default to the current month.

```lisp
(let* ((calendar (make-instance 'calendar :year 2026 :month 10
                                          :events '(((2026 10 9) . "Release"))))
       (html (with-canvas-to-string () (render calendar))))
  (list (calendar-year calendar) (calendar-month calendar)
        (not (null (search "October 2026" html)))
        (not (null (search "<li>Release</li>" html)))))
;; ⇒ (2026 10 T T)
```

#### `calendar-month` `object` — generic function

Reads the month of a calendar.  The month shown, 1 to 12.

*Example:* A month of days with their events, Monday first.  `:year` and `:month` default to the current month.

```lisp
(let* ((calendar (make-instance 'calendar :year 2026 :month 10
                                          :events '(((2026 10 9) . "Release"))))
       (html (with-canvas-to-string () (render calendar))))
  (list (calendar-year calendar) (calendar-month calendar)
        (not (null (search "October 2026" html)))
        (not (null (search "<li>Release</li>" html)))))
;; ⇒ (2026 10 T T)
```

#### `kanban` — class

Columns of cards to drag between, or move with the arrow
links on each card (which work without JavaScript or a mouse).  `:columns` is
a list of (`title` . `items`); `:render-card`, a function of an item, writes a
card (as text by default); `:on-move` is called after every move with the
item, the titles of the columns it left and joined, and its new position.

*Example:* A board's columns are (`title` . `items`).  `move-card` moves a card by column and position, and calls `:on-move` with the card, the titles of the columns it left and joined, and its new position.

```lisp
(let* ((moves '())
       (board (make-instance 'kanban :columns '(("To do" "Write" "Test") ("Done" "Plan"))
                                     :on-move (lambda (card from to position)
                                                (push (list card from to position) moves)))))
  (move-card board 0 1 1 0)
  (list (kanban-columns board) moves (move-card board 5 0 0 0)))
;; ⇒ ((("To do" "Write") ("Done" "Test" "Plan")) (("Test" "To do" "Done" 0)) NIL)
```

*Example:* In a page, cards are dragged between columns (with littoral.js) or moved with the arrows on each card.  Each column's heading counts its cards.

```lisp
(defclass chores-board (kanban) ()
  (:default-initargs :columns '(("To do" "Shop" "Cook") ("Done"))))
(with-fresh-applications (("/board" 'chores-board :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/board")
    (click b "→")
    (body-text b)))
;; ⇒ "To do 1 Cook → Done 1 Shop ←"
```

#### `kanban-columns` `object` — generic function

Reads the columns of a kanban.  (`title` . `items`) for each column, replaced on every move.

*Example:* A board's columns are (`title` . `items`).  `move-card` moves a card by column and position, and calls `:on-move` with the card, the titles of the columns it left and joined, and its new position.

```lisp
(let* ((moves '())
       (board (make-instance 'kanban :columns '(("To do" "Write" "Test") ("Done" "Plan"))
                                     :on-move (lambda (card from to position)
                                                (push (list card from to position) moves)))))
  (move-card board 0 1 1 0)
  (list (kanban-columns board) moves (move-card board 5 0 0 0)))
;; ⇒ ((("To do" "Write") ("Done" "Test" "Plan")) (("Test" "To do" "Done" 0)) NIL)
```

#### `move-card` `board from-column from-index to-column to-index` — function

Move the card at position `from-index` of column `from-column` to position
`to-index` of column `to-column`, all counting from 0, and call `board`'s `on-move`.
`to-index` is kept in range.  Returns T, or `nil`, moving nothing, when a column
or `from-index` is out of range.

*Example:* A board's columns are (`title` . `items`).  `move-card` moves a card by column and position, and calls `:on-move` with the card, the titles of the columns it left and joined, and its new position.

```lisp
(let* ((moves '())
       (board (make-instance 'kanban :columns '(("To do" "Write" "Test") ("Done" "Plan"))
                                     :on-move (lambda (card from to position)
                                                (push (list card from to position) moves)))))
  (move-card board 0 1 1 0)
  (list (kanban-columns board) moves (move-card board 5 0 0 0)))
;; ⇒ ((("To do" "Write") ("Done" "Test" "Plan")) (("Test" "To do" "Done" 0)) NIL)
```

#### `markdown-html` `markdown` — function

`markdown` as HTML: paragraphs, # headings, - and 1. lists, > quotes, ```
code blocks, `code`, **strong**, *emphasis* and [links](https://…).  All
of `markdown`'s own HTML is escaped, and links go only to http(s), mailto or
this site, so the result is safe to show whoever wrote it.  Headings start
at h3 for #, so they sit under a page's own.

*Example:* Markdown as HTML.  Headings start at h3 for #, h4 for ##, so they sit under a page's own.

```lisp
(markdown-html "## Notes

Bring *two* copies of the **form**.

- A pen
- Your `ticket`")
;; ⇒ "<h4>Notes</h4><p>Bring <em>two</em> copies of the <strong>form</strong>.</p><ul><li>A pen</li><li>Your <code>ticket</code></li></ul>"
```

*Example:* Whoever wrote it, the result is safe to show: HTML in the text is escaped, and links go only to http(s), mailto or this site.

```lisp
(markdown-html "<script>alert(1)</script> [home](/) [bad](javascript:alert(1))")
;; ⇒ "<p>&lt;script&gt;alert(1)&lt;/script&gt; <a href=\"/\" rel=\"nofollow noopener\">home</a> [bad](javascript:alert(1))</p>"
```

#### `markdown-field` — class

Text written in Markdown, shown as safe HTML (see
`markdown-html`): the description field kind `:markdown`.

*Example:* The description field kind `:markdown`: entered in a text area, shown as HTML.

```lisp
(defclass announcement ()
  ((body :initform "Doors open at **seven**.")))
(define-description announcement
  ((body :type :markdown)))
(let ((field (find-field 'announcement 'body)))
  (with-canvas-to-string ()
    (render-field-value field (field-value field (make-instance 'announcement)))))
;; ⇒ "<div class=\"lt-markdown\"><p>Doors open at <strong>seven</strong>.</p></div>"
```

### JSON endpoints

#### `define-endpoint` `application-path method pattern (&rest parameters) &body body` — macro

Serve `body` as JSON for `method` (`:get`, `:post`, `:put`, `:patch`, `:delete`)
requests to `pattern`, such as "/api/items/:id", under the application at
`application-path`; a `:get` endpoint answers `head` too.  `parameters` are bound to
`pattern`'s `:name` segments, in order, as strings.  `body`'s value is the
response: hash tables and keyword plists are objects, other lists and
vectors arrays (#() for an empty one: `nil` is null, as `:null` is), T true,
`:false` false.  A second value is the status (200 by default), a third a
plist of extra headers.  `endpoint-error` answers with its status, another
error with 500, and a method `pattern` doesn't serve with 405.

*Example:* An endpoint's value is its JSON response: a keyword plist is an object, a list of them an array.  `:id` in the pattern becomes the argument `id`, a string.  `endpoint-error` answers with a status and {"error": message}.

```lisp
(defvar *notes* (list (list :id 1 :text "Buy milk") (list :id 2 :text "Call Ada")))
(define-endpoint "/notes" :get "/api/notes" ()
  *notes*)
(define-endpoint "/notes" :get "/api/notes/:id" (id)
  (or (find (parse-integer id :junk-allowed t) *notes* :key (lambda (note) (getf note :id)))
      (endpoint-error 404 "No note ~A." id)))
(with-fresh-applications (("/notes" 'component :mode :deployment))
  (let ((b (make-instance 'browser)))
    (flet ((get-json (path)
             (multiple-value-bind (status headers body) (raw-request b :get path)
               (declare (ignore headers))
               (list status body))))
      (list (get-json "/notes/api/notes/2")
            (get-json "/notes/api/notes/9")))))
;; ⇒ ((200 "{\"id\":2,\"text\":\"Call Ada\"}") (404 "{\"error\":\"No note 9.\"}"))
```

*Example:* `endpoint-body` is the JSON the request sent, parsed: objects become hash tables.  A second value is the status, a third extra headers.

```lisp
(defvar *next-id* 3)
(define-endpoint "/notes" :post "/api/notes" ()
  (let* ((body (endpoint-body))
         (text (and body (gethash "text" body))))
    (unless (stringp text)
      (endpoint-error 422 "A note needs text."))
    (let ((id (incf *next-id*)))
      (values (list :id id :text text)
              201
              (list :location (format nil "/notes/api/notes/~D" id))))))
(with-fresh-applications (("/notes" 'component :mode :deployment))
  (let ((b (make-instance 'browser)))
    (flet ((post-json (json)
             (multiple-value-bind (status headers body)
                 (raw-request b :post "/notes/api/notes" :body json :content-type "application/json")
               (list status (getf headers :location) body))))
      (list (post-json "{\"text\": \"Feed the cat\"}")
            (post-json "{\"words\": 3}")
            (first (post-json "not JSON"))))))
;; ⇒ ((201 "/notes/api/notes/4" "{\"id\":4,\"text\":\"Feed the cat\"}") (422 NIL "{\"error\":\"A note needs text.\"}") 400)
```

#### `register-endpoint` `application-path method pattern function` — function

Serve `function` for `method` requests to `pattern` under `application-path`,
replacing any endpoint with the same method and pattern.  `pattern`'s `:name`
segments become `function`'s arguments, URL-decoded strings, in order.
Returns (`method` `pattern`).

*Example:* The function behind `define-endpoint`: serve a function you already have.  It returns the method and pattern.

```lisp
(defun zone-time (zone)
  (list :zone zone :hour 12))
(register-endpoint "/clock" :get "/api/time/:zone" #'zone-time)
;; ⇒ (:GET "/api/time/:zone")
(with-fresh-applications (("/clock" 'component :mode :deployment))
  (nth-value 2 (raw-request (make-instance 'browser) :get "/clock/api/time/UTC")))
;; ⇒ "{\"zone\":\"UTC\",\"hour\":12}"
```

#### `endpoint-error` — condition

Signalled by `endpoint-error`: answered as {"error": message} with its status.

#### `endpoint-error` `status message &rest arguments` — function

Answer the current endpoint request with `status` and {"error": `message`},
`message` being a `format` control string for `arguments`.  Signals `endpoint-error`.

*Example:* An endpoint's value is its JSON response: a keyword plist is an object, a list of them an array.  `:id` in the pattern becomes the argument `id`, a string.  `endpoint-error` answers with a status and {"error": message}.

```lisp
(defvar *notes* (list (list :id 1 :text "Buy milk") (list :id 2 :text "Call Ada")))
(define-endpoint "/notes" :get "/api/notes" ()
  *notes*)
(define-endpoint "/notes" :get "/api/notes/:id" (id)
  (or (find (parse-integer id :junk-allowed t) *notes* :key (lambda (note) (getf note :id)))
      (endpoint-error 404 "No note ~A." id)))
(with-fresh-applications (("/notes" 'component :mode :deployment))
  (let ((b (make-instance 'browser)))
    (flet ((get-json (path)
             (multiple-value-bind (status headers body) (raw-request b :get path)
               (declare (ignore headers))
               (list status body))))
      (list (get-json "/notes/api/notes/2")
            (get-json "/notes/api/notes/9")))))
;; ⇒ ((200 "{\"id\":2,\"text\":\"Call Ada\"}") (404 "{\"error\":\"No note 9.\"}"))
```

#### `endpoint-body` — function

The request's JSON body, parsed (objects as hash tables), or `nil` when empty.
Signals `endpoint-error` 400 when it isn't JSON.

*Example:* `endpoint-body` is the JSON the request sent, parsed: objects become hash tables.  A second value is the status, a third extra headers.

```lisp
(defvar *next-id* 3)
(define-endpoint "/notes" :post "/api/notes" ()
  (let* ((body (endpoint-body))
         (text (and body (gethash "text" body))))
    (unless (stringp text)
      (endpoint-error 422 "A note needs text."))
    (let ((id (incf *next-id*)))
      (values (list :id id :text text)
              201
              (list :location (format nil "/notes/api/notes/~D" id))))))
(with-fresh-applications (("/notes" 'component :mode :deployment))
  (let ((b (make-instance 'browser)))
    (flet ((post-json (json)
             (multiple-value-bind (status headers body)
                 (raw-request b :post "/notes/api/notes" :body json :content-type "application/json")
               (list status (getf headers :location) body))))
      (list (post-json "{\"text\": \"Feed the cat\"}")
            (post-json "{\"words\": 3}")
            (first (post-json "not JSON"))))))
;; ⇒ ((201 "/notes/api/notes/4" "{\"id\":4,\"text\":\"Feed the cat\"}") (422 NIL "{\"error\":\"A note needs text.\"}") 400)
```

#### `*endpoint-authenticator*` — variable

A function of no arguments answering who an endpoint request comes from,
and how (`:token` or `:cookie`), or `nil` for nobody; littoral/auth sets it.  A
write (any method but `get`, `head` and `options`) that comes `:cookie` must send
Content-Type application/json, or gets 415: a cross-site form can't.

*Example:* littoral/auth sets it to say who a request comes from, and how.  A write signed in only by cookie must send JSON, which a cross-site form can't; here a stand-in says every request is Ada's, by cookie.

```lisp
(define-endpoint "/inbox" :post "/api/read-all" ()
  (list :ok t))
(with-fresh-applications (("/inbox" 'component :mode :deployment))
  (let ((*endpoint-authenticator* (lambda () (values "ada" :cookie)))
        (b (make-instance 'browser)))
    (list (raw-request b :post "/inbox/api/read-all" :body "all=1"
                                                     :content-type "application/x-www-form-urlencoded")
          (raw-request b :post "/inbox/api/read-all" :body "{}" :content-type "application/json"))))
;; ⇒ (415 200)
```

### Health, metrics, request logs

#### `add-health-check` `name function` — function

Have /healthz call `function`, of no arguments; it fails when `function`
signals or returns `nil`.  Replaces any check called `name`.

*Example:* /healthz answers 200 while every check passes and 503 when one signals or returns `nil`, naming it.

```lisp
(add-health-check "mail queue" (lambda () (error "The queue is stuck.")))
;; ⇒ "mail queue"
(unwind-protect
     (multiple-value-bind (status headers body) (raw-request (make-instance 'browser) :get "/healthz")
       (declare (ignore headers))
       (list status (gethash "mail queue" (gethash "checks" (com.inuoe.jzon:parse body)))))
  (remove-health-check "mail queue"))
;; ⇒ (503 "failing: The queue is stuck.")
```

#### `remove-health-check` `name` — function

Forget the health check `name`.

*Example:* /healthz answers 200 while every check passes and 503 when one signals or returns `nil`, naming it.

```lisp
(add-health-check "mail queue" (lambda () (error "The queue is stuck.")))
;; ⇒ "mail queue"
(unwind-protect
     (multiple-value-bind (status headers body) (raw-request (make-instance 'browser) :get "/healthz")
       (declare (ignore headers))
       (list status (gethash "mail queue" (gethash "checks" (com.inuoe.jzon:parse body)))))
  (remove-health-check "mail queue"))
;; ⇒ (503 "failing: The queue is stuck.")
```

#### `serve-metrics` `&key (path "/metrics") (local-only t)` — function

Serve `metrics-text` at `path` for Prometheus to scrape, through
`mount-handler` (`unmount-handler` `path` stops it).  With `local-only` (the
default) only requests from this machine get them, others 403: put the
scraper there, or behind the proxy with `*trust-forwarded-for*` and an allow
list.

*Example:* Mount the metrics text at a path for Prometheus to scrape; by default only requests from this machine get it.  Every request is counted by application, kind and status.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello)) (p () "Hello"))
(serve-metrics :path "/hello-metrics")
(unwind-protect
     (with-fresh-applications (("/hello" 'hello :mode :deployment))
       (let ((b (make-instance 'browser)))
         (visit b "/hello")
         (multiple-value-bind (status headers body) (raw-request b :get "/hello-metrics")
           (list status
                 (getf headers :content-type)
                 (not (null (search "littoral_requests_total{app=\"/hello\",kind=\"page\",status=\"200\"}" body)))
                 (not (null (search "littoral_sessions{app=\"/hello\"} 1" (metrics-text))))))))
  (unmount-handler "/hello-metrics"))
;; ⇒ (200 "text/plain; version=0.0.4; charset=utf-8" T T)
```

#### `metrics-text` — function

Every metric, in Prometheus's text exposition format.

*Example:* Mount the metrics text at a path for Prometheus to scrape; by default only requests from this machine get it.  Every request is counted by application, kind and status.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello)) (p () "Hello"))
(serve-metrics :path "/hello-metrics")
(unwind-protect
     (with-fresh-applications (("/hello" 'hello :mode :deployment))
       (let ((b (make-instance 'browser)))
         (visit b "/hello")
         (multiple-value-bind (status headers body) (raw-request b :get "/hello-metrics")
           (list status
                 (getf headers :content-type)
                 (not (null (search "littoral_requests_total{app=\"/hello\",kind=\"page\",status=\"200\"}" body)))
                 (not (null (search "littoral_sessions{app=\"/hello\"} 1" (metrics-text))))))))
  (unmount-handler "/hello-metrics"))
;; ⇒ (200 "text/plain; version=0.0.4; charset=utf-8" T T)
```

#### `metrics-summary` — function

A plist of headline numbers, for pages that show them: `:requests` and
`:errors` (status 500 or more) answered, not counting event streams; live
`:sessions`; open `:streams`; `:jobs-running`; `:heap` bytes in use; `:threads`;
`:uptime` in seconds; and `:mean-ms`, the mean time to answer a request other
than a stream or socket, in milliseconds (a rational).

*Example:* Headline numbers for a status page.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello)) (p () "Hello"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (visit (make-instance 'browser) "/hello")
  (let ((summary (metrics-summary)))
    (list (getf summary :sessions) (integerp (getf summary :heap)))))
;; ⇒ (1 T)
```

#### `reset-metrics` — function

Start the request counts and timings, and `define-metric`'s metrics, again from zero.

#### `log-requests-to` `stream &key (format :json)` — function

Write a line to `stream` for every request: JSON (`format` `:json`, the
default, for log collectors) with the fields time, method, path, app, kind,
status, ms and address, or text (`:text`).  The path leaves out the query
string, where session keys ride.  `nil` for `stream` stops logging.  It sets
`*request-log*`, so it replaces any log already set.

*Example:* One line per request, here as JSON into a string.  Binding `*request-log*` keeps the logging to this example.  Visiting the page is two requests: the first starts the session and redirects.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello)) (p () "Hello"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let ((*request-log* nil)
        (log (make-string-output-stream)))
    (log-requests-to log :format :json)
    (visit (make-instance 'browser) "/hello")
    (with-input-from-string (in (get-output-stream-string log))
      (loop for line = (read-line in nil)
            while line
            collect (let ((entry (com.inuoe.jzon:parse line)))
                      (list (gethash "method" entry) (gethash "path" entry) (gethash "status" entry)))))))
;; ⇒ (("GET" "/hello" 302) ("GET" "/hello" 200))
```

#### `*request-log*` — variable

A function of a plist describing each request (`:time` `:method` `:path` `:app` `:kind`
`:status` `:milliseconds` `:address`), or `nil`.  See `log-requests-to`.

*Example:* Any function of a plist can take the log: here one that keeps each request's kind and status.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello)) (anchor (:callback (lambda () nil)) "Again"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let* ((seen '())
         (*request-log* (lambda (entry) (push (list (getf entry :kind) (getf entry :status)) seen)))
         (b (make-instance 'browser)))
    (visit b "/hello")
    (click b "Again")
    (reverse seen)))
;; ⇒ (("page" 302) ("page" 200) ("action" 302) ("page" 200))
```

#### `*latency-buckets*` — variable

Upper bounds, in seconds, of the request duration histogram's buckets, and
the default buckets of `define-metric`'s histograms.  Changing it starts the
request histogram again, since counts can't be moved between buckets.

#### `add-metrics-source` `name function` — function

Have /metrics also call `function` with the output stream, to write metrics
of its own in Prometheus's text format (`metric-label` escapes label values).
If it signals, what it wrote is dropped and littoral_metrics_source_up for
`name` is 0.  Replaces any source called `name`.

*Example:* A function that writes metrics computed when /metrics is read, such as a queue's length.  `metric-label` escapes a label value.

```lisp
(metric-label "say \"hi\"")
;; ⇒ "say \\\"hi\\\""
(add-metrics-source "doc-example-queue"
                    (lambda (out)
                      (format out "# TYPE doc_example_queue_length gauge~%~
                                   doc_example_queue_length{queue=\"~A\"} ~D~%"
                              (metric-label "mail") 4)))
;; ⇒ "doc-example-queue"
(unwind-protect
     (let ((text (metrics-text)))
       (list (not (null (search "doc_example_queue_length{queue=\"mail\"} 4" text)))
             (not (null (search "littoral_metrics_source_up{source=\"doc-example-queue\"} 1" text)))))
  (remove-metrics-source "doc-example-queue"))
;; ⇒ (T T)
```

#### `remove-metrics-source` `name` — function

Forget the metrics source `name`.

*Example:* A function that writes metrics computed when /metrics is read, such as a queue's length.  `metric-label` escapes a label value.

```lisp
(metric-label "say \"hi\"")
;; ⇒ "say \\\"hi\\\""
(add-metrics-source "doc-example-queue"
                    (lambda (out)
                      (format out "# TYPE doc_example_queue_length gauge~%~
                                   doc_example_queue_length{queue=\"~A\"} ~D~%"
                              (metric-label "mail") 4)))
;; ⇒ "doc-example-queue"
(unwind-protect
     (let ((text (metrics-text)))
       (list (not (null (search "doc_example_queue_length{queue=\"mail\"} 4" text)))
             (not (null (search "littoral_metrics_source_up{source=\"doc-example-queue\"} 1" text)))))
  (remove-metrics-source "doc-example-queue"))
;; ⇒ (T T)
```

#### `metric-label` `value` — function

`value` escaped for a Prometheus label.

*Example:* A function that writes metrics computed when /metrics is read, such as a queue's length.  `metric-label` escapes a label value.

```lisp
(metric-label "say \"hi\"")
;; ⇒ "say \\\"hi\\\""
(add-metrics-source "doc-example-queue"
                    (lambda (out)
                      (format out "# TYPE doc_example_queue_length gauge~%~
                                   doc_example_queue_length{queue=\"~A\"} ~D~%"
                              (metric-label "mail") 4)))
;; ⇒ "doc-example-queue"
(unwind-protect
     (let ((text (metrics-text)))
       (list (not (null (search "doc_example_queue_length{queue=\"mail\"} 4" text)))
             (not (null (search "littoral_metrics_source_up{source=\"doc-example-queue\"} 1" text)))))
  (remove-metrics-source "doc-example-queue"))
;; ⇒ (T T)
```

#### `define-metric` `name type help &key labels (buckets *latency-buckets*)` — function

Make the metric `name` (a string such as "myapp_orders_total") that
/metrics reports: `type` `:counter`, counted by `count-metric`, or `:histogram`, of
values given to `observe-metric` and counted into `buckets`.  `labels` names its
labels; keep their values few (a job's name, not its arguments).  Defining
`name` again keeps its counts.  Returns `name`.

*Example:* A counter of your own, with a label; /metrics reports it.  `series-value` reads one series back from the metrics text.

```lisp
(define-metric "doc_example_orders_total" :counter "Orders placed, by kind." :labels '("kind"))
;; ⇒ "doc_example_orders_total"
(defun series-value (series)
  (let* ((text (metrics-text))
         (start (search (format nil "~A " series) text)))
    (if start (read-from-string text t nil :start (+ start (length series) 1)) 0)))
(let ((before (series-value "doc_example_orders_total{kind=\"book\"}")))
  (count-metric "doc_example_orders_total" '("book"))
  (count-metric "doc_example_orders_total" '("book") 2)
  (- (series-value "doc_example_orders_total{kind=\"book\"}") before))
;; ⇒ 3
```

#### `count-metric` `name &optional label-values (amount 1)` — function

Add `amount` (1 by default) to the counter `name` for `label-values`, a list in
the order of its labels, printed with `princ`.  Returns `amount`.  Signals an
error when `name` hasn't been defined with `define-metric`.

*Example:* A counter of your own, with a label; /metrics reports it.  `series-value` reads one series back from the metrics text.

```lisp
(define-metric "doc_example_orders_total" :counter "Orders placed, by kind." :labels '("kind"))
;; ⇒ "doc_example_orders_total"
(defun series-value (series)
  (let* ((text (metrics-text))
         (start (search (format nil "~A " series) text)))
    (if start (read-from-string text t nil :start (+ start (length series) 1)) 0)))
(let ((before (series-value "doc_example_orders_total{kind=\"book\"}")))
  (count-metric "doc_example_orders_total" '("book"))
  (count-metric "doc_example_orders_total" '("book") 2)
  (- (series-value "doc_example_orders_total{kind=\"book\"}") before))
;; ⇒ 3
```

#### `observe-metric` `name value &optional label-values` — function

Count `value`, such as seconds taken, into the histogram `name` for
`label-values` (a list in the order of its labels).  Returns `value`.  Signals an
error when `name` hasn't been defined with `define-metric`.

*Example:* A histogram counts values into its buckets: `timing-metric` observes how long its body took, even when it fails; `observe-metric` observes any value.

```lisp
(define-metric "doc_example_report_seconds" :histogram "Time to build a report." :buckets '(0.1 1 10))
(defun series-value (series)
  (let* ((text (metrics-text))
         (start (search (format nil "~A " series) text)))
    (if start (read-from-string text t nil :start (+ start (length series) 1)) 0)))
(let ((before (series-value "doc_example_report_seconds_count"))
      (slow-before (series-value "doc_example_report_seconds_bucket{le=\"1\"}")))
  (timing-metric ("doc_example_report_seconds") (sleep 0.01))
  (observe-metric "doc_example_report_seconds" 5)
  (list (- (series-value "doc_example_report_seconds_count") before)
        (- (series-value "doc_example_report_seconds_bucket{le=\"1\"}") slow-before)))
;; ⇒ (2 1)
```

#### `timing-metric` `(name &optional label-values) &body body` — macro

Evaluate `body`, observing the seconds it took in the histogram `name` for
`label-values`, even when it fails.  Returns `body`'s values.

*Example:* A histogram counts values into its buckets: `timing-metric` observes how long its body took, even when it fails; `observe-metric` observes any value.

```lisp
(define-metric "doc_example_report_seconds" :histogram "Time to build a report." :buckets '(0.1 1 10))
(defun series-value (series)
  (let* ((text (metrics-text))
         (start (search (format nil "~A " series) text)))
    (if start (read-from-string text t nil :start (+ start (length series) 1)) 0)))
(let ((before (series-value "doc_example_report_seconds_count"))
      (slow-before (series-value "doc_example_report_seconds_bucket{le=\"1\"}")))
  (timing-metric ("doc_example_report_seconds") (sleep 0.01))
  (observe-metric "doc_example_report_seconds" 5)
  (list (- (series-value "doc_example_report_seconds_count") before)
        (- (series-value "doc_example_report_seconds_bucket{le=\"1\"}") slow-before)))
;; ⇒ (2 1)
```

### Background jobs

#### `submit-job` `function &key (name "Job") (attempts 1) (backoff 2)` — function

Run `function`, of no arguments, in the background, on one of
`*job-workers*` threads in the order submitted; returns the job.  The thread
doesn't see the caller's dynamic bindings.  `name` is shown on pages.  The
job is tried up to `attempts` times, waiting `backoff` seconds (in whole
seconds, at least 1) before the second and twice as long before each
after.  Its value becomes the `job-result`.

*Example:* The function runs on a worker thread; its value becomes the job's result.

```lisp
(let ((job (submit-job (lambda () (reduce #'+ '(1 2 3 4))) :name "Add up")))
  (list (wait-for-job job 5) (job-name job) (job-result job) (job-status job)))
;; ⇒ (:DONE "Add up" 10 :DONE)
```

#### `job-progress` `fraction &optional message (job *current-job*)` — function

From inside a job: it is `fraction` (0 to 1) done, with `message` to show
(when given).  Re-renders the components watching it.  Signals
`job-cancelled` once the job has been cancelled, ending it.  Outside a job
it does nothing.

*Example:* Inside the job, `job-progress` reports how far it has got (and redraws the pages watching it); `*current-job*` is the job itself.  A job that finishes is wholly done.

```lisp
(let ((job (submit-job (lambda ()
                         (job-progress 1/2 "Halfway")
                         (list (job-name *current-job*) (job-progress-fraction *current-job*)))
                       :name "Import")))
  (wait-for-job job 5)
  (list (job-result job) (job-message job) (job-progress-fraction job)))
;; ⇒ (("Import" 1/2) "Halfway" 1)
```

#### `cancel-job` `job` — function

Stop `job`: at once if it hasn't started or is waiting to retry, otherwise
at its next `job-progress`.  Returns `job`.

*Example:* A job waiting to retry (here `:backoff` seconds after its first failure) is cancelled at once; a running one at its next `job-progress`.

```lisp
(let ((job (submit-job (lambda () (error "Not yet.")) :attempts 3 :backoff 60)))
  (wait-for (lambda () (eq (job-status job) :waiting)))
  (list (job-attempt job) (job-error job) (job-status (cancel-job job))))
;; ⇒ (1 "Not yet." :CANCELLED)
```

*Example:* `job-progress` signals `job-cancelled` in a job that was cancelled while running, ending it; the job can clean up with `unwind-protect`.

```lisp
(let* ((cleaned-up nil)
       (job (submit-job (lambda ()
                          (unwind-protect
                               (loop for step from 1
                                     do (job-progress (min 1 (/ step 1000)))
                                        (sleep 0.01))
                            (setf cleaned-up t))))))
  (wait-for (lambda () (eq (job-status job) :running)))
  (cancel-job job)
  (list (wait-for-job job 5) cleaned-up))
;; ⇒ (:CANCELLED T)
```

#### `watch-job` `job component &optional (session *session*)` — function

Re-render `component` on `session`'s pages whenever `job` changes.  The page
must listen for pushes: a `job-view` does; another component can subscribe
to `*jobs-channel*`.  Returns `component`.

*Example:* A `job-view` shows a job's progress bar, status and Cancel button; `watch-job`, called from the callback that starts the job, redraws it on the session's pages as the job goes.  The view subscribes to `*jobs-channel*`, so its page listens for pushes.  The job here waits for the stream to open first.

```lisp
(defvar *go* (sb-thread:make-semaphore))
(defclass exporter (component)
  ((view :initform (make-instance 'job-view) :reader view)))
(defmethod children ((self exporter)) (list (view self)))
(defmethod render ((self exporter))
  (anchor (:callback (lambda ()
                       (let ((job (submit-job (lambda ()
                                                (sb-thread:wait-on-semaphore *go* :timeout 5)
                                                (job-progress 1/2 "Exporting")
                                                :exported)
                                              :name "Export")))
                         (setf (job-view-job (view self)) job)
                         (watch-job job (view self)))))
    "Export")
  (render-component (view self)))
(with-fresh-applications (("/export" 'exporter :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/export") (click b "Export") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (sb-thread:signal-semaphore *go*)
    (prog1 (list (not (null (has-text-p b "Cancel")))
                 (wait-for (lambda () (search "Done." (sink-text sink)))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ (T T)
```

#### `wait-for-job` `job &optional (timeout 60)` — function

Wait until `job` has finished, at most `timeout` seconds (60 by default).
Returns its status, which is `:queued`, `:running` or `:waiting` when the time ran
out first.

*Example:* The function runs on a worker thread; its value becomes the job's result.

```lisp
(let ((job (submit-job (lambda () (reduce #'+ '(1 2 3 4))) :name "Add up")))
  (list (wait-for-job job 5) (job-name job) (job-result job) (job-status job)))
;; ⇒ (:DONE "Add up" 10 :DONE)
```

#### `list-jobs` — function

Recent jobs, newest first.

*Example:* Recent jobs, newest first, each with an id to find it by.

```lisp
(let* ((job (submit-job (lambda () :ok) :name "Find me"))
       (id (job-id job)))
  (wait-for-job job 5)
  (job-name (find id (list-jobs) :key #'job-id :test #'string=)))
;; ⇒ "Find me"
```

#### `job-view` — class

A job's progress bar, status and Cancel button, kept up to
date by server push once `watch-job` has been called on it.

*Example:* A `job-view` shows a job's progress bar, status and Cancel button; `watch-job`, called from the callback that starts the job, redraws it on the session's pages as the job goes.  The view subscribes to `*jobs-channel*`, so its page listens for pushes.  The job here waits for the stream to open first.

```lisp
(defvar *go* (sb-thread:make-semaphore))
(defclass exporter (component)
  ((view :initform (make-instance 'job-view) :reader view)))
(defmethod children ((self exporter)) (list (view self)))
(defmethod render ((self exporter))
  (anchor (:callback (lambda ()
                       (let ((job (submit-job (lambda ()
                                                (sb-thread:wait-on-semaphore *go* :timeout 5)
                                                (job-progress 1/2 "Exporting")
                                                :exported)
                                              :name "Export")))
                         (setf (job-view-job (view self)) job)
                         (watch-job job (view self)))))
    "Export")
  (render-component (view self)))
(with-fresh-applications (("/export" 'exporter :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/export") (click b "Export") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (sb-thread:signal-semaphore *go*)
    (prog1 (list (not (null (has-text-p b "Cancel")))
                 (wait-for (lambda () (search "Done." (sink-text sink)))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ (T T)
```

#### `job-view-job` `object` — generic function

Reads the job of a job-view.  The job shown, or `nil` for none.

*Example:* A `job-view` shows a job's progress bar, status and Cancel button; `watch-job`, called from the callback that starts the job, redraws it on the session's pages as the job goes.  The view subscribes to `*jobs-channel*`, so its page listens for pushes.  The job here waits for the stream to open first.

```lisp
(defvar *go* (sb-thread:make-semaphore))
(defclass exporter (component)
  ((view :initform (make-instance 'job-view) :reader view)))
(defmethod children ((self exporter)) (list (view self)))
(defmethod render ((self exporter))
  (anchor (:callback (lambda ()
                       (let ((job (submit-job (lambda ()
                                                (sb-thread:wait-on-semaphore *go* :timeout 5)
                                                (job-progress 1/2 "Exporting")
                                                :exported)
                                              :name "Export")))
                         (setf (job-view-job (view self)) job)
                         (watch-job job (view self)))))
    "Export")
  (render-component (view self)))
(with-fresh-applications (("/export" 'exporter :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/export") (click b "Export") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (sb-thread:signal-semaphore *go*)
    (prog1 (list (not (null (has-text-p b "Cancel")))
                 (wait-for (lambda () (search "Done." (sink-text sink)))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ (T T)
```

#### `job-cancelled` — condition

Signalled by `job-progress` in a job that `cancel-job` was called on.

*Example:* `job-progress` signals `job-cancelled` in a job that was cancelled while running, ending it; the job can clean up with `unwind-protect`.

```lisp
(let* ((cleaned-up nil)
       (job (submit-job (lambda ()
                          (unwind-protect
                               (loop for step from 1
                                     do (job-progress (min 1 (/ step 1000)))
                                        (sleep 0.01))
                            (setf cleaned-up t))))))
  (wait-for (lambda () (eq (job-status job) :running)))
  (cancel-job job)
  (list (wait-for-job job 5) cleaned-up))
;; ⇒ (:CANCELLED T)
```

#### `*current-job*` — variable

The job this thread is running.

*Example:* Inside the job, `job-progress` reports how far it has got (and redraws the pages watching it); `*current-job*` is the job itself.  A job that finishes is wholly done.

```lisp
(let ((job (submit-job (lambda ()
                         (job-progress 1/2 "Halfway")
                         (list (job-name *current-job*) (job-progress-fraction *current-job*)))
                       :name "Import")))
  (wait-for-job job 5)
  (list (job-result job) (job-message job) (job-progress-fraction job)))
;; ⇒ (("Import" 1/2) "Halfway" 1)
```

#### `*job-workers*` — variable

How many threads run jobs at once.  `submit-job` starts workers up to this
many; lowering it stops none that are running.

#### `*jobs-channel*` — variable

Subscribed to by `job-view` so that its page listens for pushes; never published.

*Example:* A `job-view` shows a job's progress bar, status and Cancel button; `watch-job`, called from the callback that starts the job, redraws it on the session's pages as the job goes.  The view subscribes to `*jobs-channel*`, so its page listens for pushes.  The job here waits for the stream to open first.

```lisp
(defvar *go* (sb-thread:make-semaphore))
(defclass exporter (component)
  ((view :initform (make-instance 'job-view) :reader view)))
(defmethod children ((self exporter)) (list (view self)))
(defmethod render ((self exporter))
  (anchor (:callback (lambda ()
                       (let ((job (submit-job (lambda ()
                                                (sb-thread:wait-on-semaphore *go* :timeout 5)
                                                (job-progress 1/2 "Exporting")
                                                :exported)
                                              :name "Export")))
                         (setf (job-view-job (view self)) job)
                         (watch-job job (view self)))))
    "Export")
  (render-component (view self)))
(with-fresh-applications (("/export" 'exporter :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/export") (click b "Export") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (sb-thread:signal-semaphore *go*)
    (prog1 (list (not (null (has-text-p b "Cancel")))
                 (wait-for (lambda () (search "Done." (sink-text sink)))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ (T T)
```

#### `job-id` `object` — generic function

Reads the id of a job.  A random string naming it.

*Example:* Recent jobs, newest first, each with an id to find it by.

```lisp
(let* ((job (submit-job (lambda () :ok) :name "Find me"))
       (id (job-id job)))
  (wait-for-job job 5)
  (job-name (find id (list-jobs) :key #'job-id :test #'string=)))
;; ⇒ "Find me"
```

#### `job-name` `object` — generic function

Reads the name of a job.  What to call it on a page.

*Example:* The function runs on a worker thread; its value becomes the job's result.

```lisp
(let ((job (submit-job (lambda () (reduce #'+ '(1 2 3 4))) :name "Add up")))
  (list (wait-for-job job 5) (job-name job) (job-result job) (job-status job)))
;; ⇒ (:DONE "Add up" 10 :DONE)
```

#### `job-status` `object` — generic function

Reads the status of a job.  `:queued`, `:running`, `:waiting` (to retry), `:done`, `:failed` or `:cancelled`.

*Example:* The function runs on a worker thread; its value becomes the job's result.

```lisp
(let ((job (submit-job (lambda () (reduce #'+ '(1 2 3 4))) :name "Add up")))
  (list (wait-for-job job 5) (job-name job) (job-result job) (job-status job)))
;; ⇒ (:DONE "Add up" 10 :DONE)
```

#### `job-progress-fraction` `object` — generic function

Reads the progress of a job.  How much is done, from 0 to 1, as `job-progress` last said; 1 once done.

*Example:* Inside the job, `job-progress` reports how far it has got (and redraws the pages watching it); `*current-job*` is the job itself.  A job that finishes is wholly done.

```lisp
(let ((job (submit-job (lambda ()
                         (job-progress 1/2 "Halfway")
                         (list (job-name *current-job*) (job-progress-fraction *current-job*)))
                       :name "Import")))
  (wait-for-job job 5)
  (list (job-result job) (job-message job) (job-progress-fraction job)))
;; ⇒ (("Import" 1/2) "Halfway" 1)
```

#### `job-message` `object` — generic function

Reads the message of a job.  What `job-progress` last said it is doing, or `nil`.

*Example:* Inside the job, `job-progress` reports how far it has got (and redraws the pages watching it); `*current-job*` is the job itself.  A job that finishes is wholly done.

```lisp
(let ((job (submit-job (lambda ()
                         (job-progress 1/2 "Halfway")
                         (list (job-name *current-job*) (job-progress-fraction *current-job*)))
                       :name "Import")))
  (wait-for-job job 5)
  (list (job-result job) (job-message job) (job-progress-fraction job)))
;; ⇒ (("Import" 1/2) "Halfway" 1)
```

#### `job-result` `object` — generic function

Reads the result of a job.  What its function returned, once `:done`.

*Example:* The function runs on a worker thread; its value becomes the job's result.

```lisp
(let ((job (submit-job (lambda () (reduce #'+ '(1 2 3 4))) :name "Add up")))
  (list (wait-for-job job 5) (job-name job) (job-result job) (job-status job)))
;; ⇒ (:DONE "Add up" 10 :DONE)
```

#### `job-error` `object` — generic function

Reads the error of a job.  The last failure, as text.

*Example:* A job that signals is tried again, up to `:attempts` times; with one attempt it fails at once.  `job-error` is the failure as text.

```lisp
(let ((job (submit-job (lambda () (error "The disk is full.")))))
  (list (wait-for-job job 5) (job-error job) (job-attempt job) (job-attempts job)))
;; ⇒ (:FAILED "The disk is full." 1 1)
```

#### `job-attempt` `object` — generic function

Reads the attempt of a job.  How many times it has been started.

*Example:* A job that signals is tried again, up to `:attempts` times; with one attempt it fails at once.  `job-error` is the failure as text.

```lisp
(let ((job (submit-job (lambda () (error "The disk is full.")))))
  (list (wait-for-job job 5) (job-error job) (job-attempt job) (job-attempts job)))
;; ⇒ (:FAILED "The disk is full." 1 1)
```

#### `job-attempts` `object` — generic function

Reads the attempts of a job.  How many times it may be tried.

*Example:* A job that signals is tried again, up to `:attempts` times; with one attempt it fails at once.  `job-error` is the failure as text.

```lisp
(let ((job (submit-job (lambda () (error "The disk is full.")))))
  (list (wait-for-job job 5) (job-error job) (job-attempt job) (job-attempts job)))
;; ⇒ (:FAILED "The disk is full." 1 1)
```

### Live reload

#### `*live-reload*` — variable

When true, open pages of applications in development mode reload after
their components' rendering methods are redefined (see live.lisp).

*Example:* Pages drawn while it is false don't poll for reloads.  Set globally to `nil`, it also stops the watcher reloading pages.

```lisp
(defclass banner (component) ())
(defmethod render ((self banner)) (p () "Welcome"))
(with-fresh-applications (("/banner" 'banner :mode :development))
  (let ((b (make-instance 'browser)))
    (list (progn (visit b "/banner") (not (null (search "data-lt-live" (browser-html b)))))
          (let ((*live-reload* nil))
            (visit b (browser-url b))
            (not (null (search "data-lt-live" (browser-html b))))))))
;; ⇒ (T NIL)
```

#### `reload-pages` `&optional (classes t)` — function

Have the open pages of applications in development mode reload: all of
them (`classes` T, the default), or those showing an instance of one of
`classes`, a list of classes or class names.  Pages that poll see it on their
next poll; returns how many pages with event streams were told.

*Example:* For changes the watcher can't see, such as a helper function or a style sheet: reload the open development pages, all of them or those showing one of the classes given.  Pages with an event stream are told through it, and counted.

```lisp
(defvar *ticks* (make-channel "ticks"))
(defclass dashboard (component updatable) ())
(defmethod subscriptions ((self dashboard)) (list *ticks*))
(defmethod render ((self dashboard)) (p () "Dashboard"))
(with-fresh-applications (("/dashboard" 'dashboard :mode :development))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/dashboard") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (prog1 (list (reload-pages '(dashboard))
                 (wait-for (lambda () (search "event: reload" (sink-text sink)))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ (1 T)
```

#### `start-live-watcher` `&key (interval 0.5)` — function

Every `interval` seconds, in a thread, look for methods of `render`, `style`,
`script`, `update-root`, `children` or `render-decoration` added or replaced since
the last look, and reload the open development pages showing an instance
of a class they are for (see `reload-pages`), while `*live-reload*` is true.
Replaces any watcher already running.

*Example:* While the watcher runs, redefining a render method (as recompiling it in Emacs does) has the open development pages showing that class reload.  A page with no event stream polls the URL in its data-lt-live attribute.

```lisp
(defclass banner (component) ())
(defmethod render ((self banner)) (p () "Welcome"))
(defun reload-asked-p (browser)
  (let ((url (cl-ppcre:register-groups-bind (u) ("data-lt-live=\"([^\"]*)\"" (browser-html browser))
               (unescape u))))
    (not (null (search "\"reload\":true" (nth-value 2 (raw-request browser :get url)))))))
(start-live-watcher :interval 0.1)
(unwind-protect
     (with-fresh-applications (("/banner" 'banner :mode :development))
       (let ((b (make-instance 'browser)))
         (visit b "/banner")
         (let ((before (reload-asked-p b)))
           (eval '(defmethod render ((self banner)) (p () "Welcome aboard")))
           (list before (wait-for (lambda () (reload-asked-p b)) 3)))))
  (stop-live-watcher))
;; ⇒ (NIL T)
```

#### `stop-live-watcher` — function

Stop watching for redefined rendering methods.

*Example:* While the watcher runs, redefining a render method (as recompiling it in Emacs does) has the open development pages showing that class reload.  A page with no event stream polls the URL in its data-lt-live attribute.

```lisp
(defclass banner (component) ())
(defmethod render ((self banner)) (p () "Welcome"))
(defun reload-asked-p (browser)
  (let ((url (cl-ppcre:register-groups-bind (u) ("data-lt-live=\"([^\"]*)\"" (browser-html browser))
               (unescape u))))
    (not (null (search "\"reload\":true" (nth-value 2 (raw-request browser :get url)))))))
(start-live-watcher :interval 0.1)
(unwind-protect
     (with-fresh-applications (("/banner" 'banner :mode :development))
       (let ((b (make-instance 'browser)))
         (visit b "/banner")
         (let ((before (reload-asked-p b)))
           (eval '(defmethod render ((self banner)) (p () "Welcome aboard")))
           (list before (wait-for (lambda () (reload-asked-p b)) 3)))))
  (stop-live-watcher))
;; ⇒ (NIL T)
```

### Sessions & applications

#### `session` — class

One user's component tree, the pages it has shown, and its lock.

*Example:* Every browser that visits an application gets a `session` holding its own root component.  `list-sessions` returns them, most recently used first; `application-sessions` is the table behind it, by key.

```lisp
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let ((ann (visit (make-instance 'browser) "/tally"))
        (bob (visit (make-instance 'browser) "/tally")))
    (click ann "Add one")
    (click ann "Add one")
    (click bob "Add one")
    (let ((app (find-application "/tally")))
      (list (hash-table-count (application-sessions app))
            (every (lambda (s) (typep s 'session)) (list-sessions app))
            (sort (mapcar (lambda (s) (tally-count (session-root s))) (list-sessions app)) #'<)))))
;; ⇒ (2 T (1 2))
```

#### `session-key` `object` — generic function

Reads the key of a session.  The random string naming the session in its pages' URLs (as _s) or
in its cookie; `rotate-session-key` changes it.

*Example:* A session's key is in its pages' URLs (as _s), unless the application keeps it in a cookie.  With `*instance-id*` set, keys start with it, so a load balancer can send each session back to its process.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (let* ((*instance-id* "a1")
         (b (visit (make-instance 'browser) "/hello"))
         (key (session-key (first (list-sessions (find-application "/hello"))))))
    (list (subseq key 0 3)
          (not (null (search (concatenate 'string "_s=" key) (browser-url b)))))))
;; ⇒ ("a1." T)
```

#### `session-root` `object` — generic function

Reads the root of a session.  The session's instance of its application's root component class.

*Example:* Every browser that visits an application gets a `session` holding its own root component.  `list-sessions` returns them, most recently used first; `application-sessions` is the table behind it, by key.

```lisp
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let ((ann (visit (make-instance 'browser) "/tally"))
        (bob (visit (make-instance 'browser) "/tally")))
    (click ann "Add one")
    (click ann "Add one")
    (click bob "Add one")
    (let ((app (find-application "/tally")))
      (list (hash-table-count (application-sessions app))
            (every (lambda (s) (typep s 'session)) (list-sessions app))
            (sort (mapcar (lambda (s) (tally-count (session-root s))) (list-sessions app)) #'<)))))
;; ⇒ (2 T (1 2))
```

#### `session-properties` `object` — generic function

Reads the properties of a session.  The `equal` hash table behind `session-property`.

*Example:* A session keeps whatever the application stores in it with (`setf` `session-property`), by key.  The session defaults to `*session*`, the current request's.

```lisp
(defclass visit-counter (component) ())
(defmethod render ((self visit-counter))
  (p () (text (format nil "Pages seen: ~D" (or (session-property :pages) 0))))
  (anchor (:callback (lambda ()
                       (setf (session-property :pages) (1+ (or (session-property :pages) 0)))))
    "Next"))
(with-fresh-applications (("/visits" 'visit-counter :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/visits")))
    (click b "Next")
    (click b "Next")
    (let ((session (first (list-sessions (find-application "/visits")))))
      (list (body-text b)
            (session-property :pages session)
            (hash-table-p (session-properties session))))))
;; ⇒ ("Pages seen: 2 Next" 2 T)
```

#### `session-property` `key &optional (session *session*)` — function

The value stored under `key` (compared with `equal`) in `session`, for
application use, or `nil`.  `setf` stores one.  Not part of the snapshot: the
back button does not undo it.

*Example:* A session keeps whatever the application stores in it with (`setf` `session-property`), by key.  The session defaults to `*session*`, the current request's.

```lisp
(defclass visit-counter (component) ())
(defmethod render ((self visit-counter))
  (p () (text (format nil "Pages seen: ~D" (or (session-property :pages) 0))))
  (anchor (:callback (lambda ()
                       (setf (session-property :pages) (1+ (or (session-property :pages) 0)))))
    "Next"))
(with-fresh-applications (("/visits" 'visit-counter :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/visits")))
    (click b "Next")
    (click b "Next")
    (let ((session (first (list-sessions (find-application "/visits")))))
      (list (body-text b)
            (session-property :pages session)
            (hash-table-p (session-properties session))))))
;; ⇒ ("Pages seen: 2 Next" 2 T)
```

#### `expire-session` `session` — function

Forget `session` at once.

*Example:* `expire-session` forgets a session at once, as the timeout does.  The browser's next request starts a new session; with an `:expired-notice`, a component class such as `session-expired-notice`, the new session shows it first.

```lisp
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment :expired-notice 'session-expired-notice))
  (let ((b (visit (make-instance 'browser) "/tally")))
    (click b "Add one")
    (expire-session (first (list-sessions (find-application "/tally"))))
    (click b "Add one")
    (list (body-text b)
          (body-text (press b "Continue")))))
;; ⇒ ("Your session expired, so you are starting again from the beginning. Continue" "Count: 0 Add one")
```

#### `list-sessions` `app` — function

`app`'s sessions, most recently used first.

*Example:* Every browser that visits an application gets a `session` holding its own root component.  `list-sessions` returns them, most recently used first; `application-sessions` is the table behind it, by key.

```lisp
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let ((ann (visit (make-instance 'browser) "/tally"))
        (bob (visit (make-instance 'browser) "/tally")))
    (click ann "Add one")
    (click ann "Add one")
    (click bob "Add one")
    (let ((app (find-application "/tally")))
      (list (hash-table-count (application-sessions app))
            (every (lambda (s) (typep s 'session)) (list-sessions app))
            (sort (mapcar (lambda (s) (tally-count (session-root s))) (list-sessions app)) #'<)))))
;; ⇒ (2 T (1 2))
```

#### `rotate-session-key` `&optional (session *session*)` — function

Give `session` a new key, so URLs naming the old one stop working, and end
its open event streams and sockets.  Signing in and out call this, so a
session key someone else learned beforehand is no use afterwards.  Sessions
kept in a cookie keep their key: another site cannot plant that cookie.

*Example:* Give the session a new key when its user signs in, so a key someone learned before is no use.  The session and its state carry on under the new key, and the page that follows names it.

```lisp
(defclass sign-in-page (component)
  ((user :initform nil :accessor signed-in-user)))
(defmethod render ((self sign-in-page))
  (p () (text (or (signed-in-user self) "Nobody")))
  (anchor (:callback (lambda ()
                       (setf (signed-in-user self) "ada")
                       (rotate-session-key)))
    "Sign in"))
(with-fresh-applications (("/members" 'sign-in-page :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/members"))
         (before (session-key (first (list-sessions (find-application "/members"))))))
    (click b "Sign in")
    (let ((after (session-key (first (list-sessions (find-application "/members"))))))
      (list (body-text b)
            (string= before after)
            (null (search before (browser-url b)))
            (length (list-sessions (find-application "/members")))))))
;; ⇒ ("ada Sign in" NIL T 1)
```

#### `set-cookie` `name value &key max-age path (http-only t) (same-site "Lax") (session *session*)` — function

Have the browser keep the cookie `name`=`value`, sent with this application's
requests (or `path`'s).  `max-age` in seconds keeps it that long, 0 deletes it,
`nil` keeps it until the browser closes.  `http-only` hides it from scripts;
`same-site` is "Lax", "Strict", "None" or `nil` to leave it out.  Secure
over HTTPS.  The cookie goes out with `session`'s next HTTP response: this
one, or the next page load when called while answering a WebSocket message.
Signals an error when `name` is not letters, digits and _.- or `value` has
characters other than letters, digits and _.~+/=-.  Returns `value`.

*Example:* A callback queues a cookie with `set-cookie`; it goes out with the response, scoped to the application's path unless `:path` says otherwise.  `request-cookie` reads one the browser sent back.  A `:max-age` of 0 deletes it.

```lisp
(defclass biscuit-tin (component) ())
(defmethod render ((self biscuit-tin))
  (p () (text (format nil "Flavour: ~A" (or (request-cookie "flavour") "none"))))
  (p ()
    (anchor (:callback (lambda () (set-cookie "flavour" "oat" :max-age 3600))) "Bake")
    " or "
    (anchor (:callback (lambda () (set-cookie "flavour" "" :max-age 0))) "Eat")))
(with-fresh-applications (("/tin" 'biscuit-tin :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/tin")))
    (multiple-value-bind (status headers) (raw-request b :get (find-link b "Bake"))
      (list status
            (getf headers :set-cookie)
            (body-text (visit b (getf headers :location)))
            (body-text (click b "Eat"))))))
;; ⇒ (302 "flavour=oat; Path=/tin; Max-Age=3600; HttpOnly; SameSite=Lax" "Flavour: oat Bake or Eat" "Flavour: none Bake or Eat")
```

#### `request-cookie` `name` — function

The value of the current request's cookie `name`, or `nil`.

*Example:* A callback queues a cookie with `set-cookie`; it goes out with the response, scoped to the application's path unless `:path` says otherwise.  `request-cookie` reads one the browser sent back.  A `:max-age` of 0 deletes it.

```lisp
(defclass biscuit-tin (component) ())
(defmethod render ((self biscuit-tin))
  (p () (text (format nil "Flavour: ~A" (or (request-cookie "flavour") "none"))))
  (p ()
    (anchor (:callback (lambda () (set-cookie "flavour" "oat" :max-age 3600))) "Bake")
    " or "
    (anchor (:callback (lambda () (set-cookie "flavour" "" :max-age 0))) "Eat")))
(with-fresh-applications (("/tin" 'biscuit-tin :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/tin")))
    (multiple-value-bind (status headers) (raw-request b :get (find-link b "Bake"))
      (list status
            (getf headers :set-cookie)
            (body-text (visit b (getf headers :location)))
            (body-text (click b "Eat"))))))
;; ⇒ (302 "flavour=oat; Path=/tin; Max-Age=3600; HttpOnly; SameSite=Lax" "Flavour: oat Bake or Eat" "Flavour: none Bake or Eat")
```

#### `mount-handler` `prefix handler` — function

Answer requests for paths under `prefix` (such as "/files/") with `handler`, a
function of the rest of the path that returns a Lack response.  Mounted
handlers are tried before applications.  Replaces any handler mounted at
`prefix`.  Returns `prefix`.

*Example:* A handler mounted at a prefix answers paths under it outside any application: it gets the rest of the path and returns a Lack response.

```lisp
(unwind-protect
     (progn
       (mount-handler "/hello/" (lambda (rest)
                                  (list 200 '(:content-type "text/plain; charset=utf-8")
                                        (list (format nil "Hello, ~A!" rest)))))
       (body-text (visit (make-instance 'browser) "/hello/world")))
  (unmount-handler "/hello/"))
;; ⇒ "Hello, world!"
```

#### `unmount-handler` `prefix` — function

Stop serving `prefix` with the handler `mount-handler` gave it.

*Example:* A handler mounted at a prefix answers paths under it outside any application: it gets the rest of the path and returns a Lack response.

```lisp
(unwind-protect
     (progn
       (mount-handler "/hello/" (lambda (rest)
                                  (list 200 '(:content-type "text/plain; charset=utf-8")
                                        (list (format nil "Hello, ~A!" rest)))))
       (body-text (visit (make-instance 'browser) "/hello/world")))
  (unmount-handler "/hello/"))
;; ⇒ "Hello, world!"
```

#### `field-multipart-p` `field` — generic function

True when `field`'s input uploads a file, so its form must be multipart.

*Example:* Description editors and wizards make their form multipart when any field says it uploads a file.  A field kind of your own whose input is a file input says so with a method; littoral.storage:file-field (in littoral/storage) already does.

```lisp
(defclass scan-field (field) ())
(defmethod field-multipart-p ((field scan-field))
  t)
(list (field-multipart-p (make-instance 'string-field :name 'title :label "Title"))
      (field-multipart-p (make-instance 'scan-field :name 'scan :label "Scanned letter"))
      (field-multipart-p (make-instance 'littoral.storage:file-field :name 'photo :label "Photo")))
;; ⇒ (NIL T T)
```

#### `application` — class

A root component class served at a path, with its settings and live sessions.

*Example:* An application serves a root component class at a path.  The path is normalised to one leading slash and no trailing one, and `find-application` takes either spelling.

```lisp
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome to the shop"))
(with-fresh-applications ()
  (register-application "shop/" 'storefront :mode :deployment)
  (let ((app (find-application "/shop")))
    (list (application-path app) (application-root-class app) (typep app 'application))))
;; ⇒ ("/shop" STOREFRONT T)
```

#### `application-path` `object` — generic function

Reads the path of an application.  Where it is served, such as "/shop": a leading slash and no trailing one.

*Example:* An application serves a root component class at a path.  The path is normalised to one leading slash and no trailing one, and `find-application` takes either spelling.

```lisp
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome to the shop"))
(with-fresh-applications ()
  (register-application "shop/" 'storefront :mode :deployment)
  (let ((app (find-application "/shop")))
    (list (application-path app) (application-root-class app) (typep app 'application))))
;; ⇒ ("/shop" STOREFRONT T)
```

#### `application-root-class` `object` — generic function

Reads the root-class of an application.  The component class each new session makes its root.

*Example:* An application serves a root component class at a path.  The path is normalised to one leading slash and no trailing one, and `find-application` takes either spelling.

```lisp
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome to the shop"))
(with-fresh-applications ()
  (register-application "shop/" 'storefront :mode :deployment)
  (let ((app (find-application "/shop")))
    (list (application-path app) (application-root-class app) (typep app 'application))))
;; ⇒ ("/shop" STOREFRONT T)
```

#### `application-title` `object` — generic function

Reads the title of an application.  The pages' title, or `nil` for the path.  Components may change
it with `update-root`.

*Example:* Each initarg of `register-application` has a reader, which `setf` changes for the running application.  The defaults:

```lisp
(defclass blank-page (component) ())
(with-fresh-applications (("/notes" 'blank-page))
  (let ((app (find-application "/notes")))
    (list (application-title app) (application-mode app) (application-session-timeout app)
          (application-max-continuations app) (application-max-sessions app)
          (application-cookie-sessions-p app) (application-websockets-p app)
          (application-local-only-p app) (application-content-security-policy app)
          (application-max-request-size app))))
;; ⇒ (NIL :DEVELOPMENT 1800 50 NIL NIL NIL NIL :STRICT NIL)
```

*Example:* The title, language, style sheets and scripts go into every page's head.

```lisp
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome"))
(with-fresh-applications (("/shop" 'storefront :mode :deployment :title "Fish Shop" :language "fr"
                                   :stylesheets '("/css/shop.css") :scripts '("/js/basket.js")))
  (let* ((b (visit (make-instance 'browser) "/shop"))
         (html (browser-html b)))
    (list (not (null (search "<title>Fish Shop</title>" html)))
          (not (null (search "<html lang=\"fr\">" html)))
          (not (null (search "<link rel=\"stylesheet\" href=\"/css/shop.css\">" html)))
          (not (null (search "<script src=\"/js/basket.js\" defer" html))))))
;; ⇒ (T T T T)
```

#### `application-mode` `object` — generic function

Reads the mode of an application.  `:development` adds the toolbar and halos.

*Example:* Each initarg of `register-application` has a reader, which `setf` changes for the running application.  The defaults:

```lisp
(defclass blank-page (component) ())
(with-fresh-applications (("/notes" 'blank-page))
  (let ((app (find-application "/notes")))
    (list (application-title app) (application-mode app) (application-session-timeout app)
          (application-max-continuations app) (application-max-sessions app)
          (application-cookie-sessions-p app) (application-websockets-p app)
          (application-local-only-p app) (application-content-security-policy app)
          (application-max-request-size app))))
;; ⇒ (NIL :DEVELOPMENT 1800 50 NIL NIL NIL NIL :STRICT NIL)
```

*Example:* In `:development` mode, the default, every page ends with the development toolbar (New Session, Halos, …); `:deployment` leaves it out.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/dev" 'greeting) ("/live" 'greeting :mode :deployment))
  (list (not (null (find-link (visit (make-instance 'browser) "/dev") "New Session")))
        (body-text (visit (make-instance 'browser) "/live"))))
;; ⇒ (T "Hello")
```

#### `application-session-timeout` `object` — generic function

Reads the session-timeout of an application.  Seconds a session may sit idle.

*Example:* Each initarg of `register-application` has a reader, which `setf` changes for the running application.  The defaults:

```lisp
(defclass blank-page (component) ())
(with-fresh-applications (("/notes" 'blank-page))
  (let ((app (find-application "/notes")))
    (list (application-title app) (application-mode app) (application-session-timeout app)
          (application-max-continuations app) (application-max-sessions app)
          (application-cookie-sessions-p app) (application-websockets-p app)
          (application-local-only-p app) (application-content-security-policy app)
          (application-max-request-size app))))
;; ⇒ (NIL :DEVELOPMENT 1800 50 NIL NIL NIL NIL :STRICT NIL)
```

*Example:* A session idle for longer than the application's `:session-timeout` (in seconds) is forgotten when next looked up, or by `reap-all-sessions`, which `start-reaper` runs in a thread (`start` starts one).  A timeout of -1 makes every session too old here, so the example needn't wait.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (let ((app (find-application "/hello")))
    (visit (make-instance 'browser) "/hello")
    (let ((before (length (list-sessions app))))
      (setf (application-session-timeout app) -1)
      (reap-all-sessions)
      (list before (length (list-sessions app))))))
;; ⇒ (1 0)
(start-reaper :interval 300)
(stop-reaper)
;; ⇒ NIL
```

#### `application-max-continuations` `object` — generic function

Reads the max-continuations of an application.  Pages per session the back button can reach.

*Example:* Each initarg of `register-application` has a reader, which `setf` changes for the running application.  The defaults:

```lisp
(defclass blank-page (component) ())
(with-fresh-applications (("/notes" 'blank-page))
  (let ((app (find-application "/notes")))
    (list (application-title app) (application-mode app) (application-session-timeout app)
          (application-max-continuations app) (application-max-sessions app)
          (application-cookie-sessions-p app) (application-websockets-p app)
          (application-local-only-p app) (application-content-security-policy app)
          (application-max-request-size app))))
;; ⇒ (NIL :DEVELOPMENT 1800 50 NIL NIL NIL NIL :STRICT NIL)
```

*Example:* A session keeps its last `max-continuations` pages for the back button.  Going back to a page it has forgotten shows the session as it is now.

```lisp
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod states ((self tally))
  (list self))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/kept" 'tally :mode :deployment)
                          ("/forgetful" 'tally :mode :deployment :max-continuations 2))
  (flet ((go-back (path)
           (let* ((b (visit (make-instance 'browser) path))
                  (first-page (browser-url b)))
             (dotimes (i 3) (click b "Add one"))
             (body-text (back-to b first-page)))))
    (list (go-back "/kept") (go-back "/forgetful"))))
;; ⇒ ("Count: 0 Add one" "Count: 3 Add one")
```

#### `application-cookie-sessions-p` `object` — generic function

Reads the cookie-sessions-p of an application.  Track the session in a cookie instead of the URL.

*Example:* Each initarg of `register-application` has a reader, which `setf` changes for the running application.  The defaults:

```lisp
(defclass blank-page (component) ())
(with-fresh-applications (("/notes" 'blank-page))
  (let ((app (find-application "/notes")))
    (list (application-title app) (application-mode app) (application-session-timeout app)
          (application-max-continuations app) (application-max-sessions app)
          (application-cookie-sessions-p app) (application-websockets-p app)
          (application-local-only-p app) (application-content-security-policy app)
          (application-max-request-size app))))
;; ⇒ (NIL :DEVELOPMENT 1800 50 NIL NIL NIL NIL :STRICT NIL)
```

*Example:* With `:cookie-sessions` the session key travels in a cookie instead of the URL.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment :cookie-sessions t))
  (let* ((b (visit (make-instance 'browser) "/hello"))
         (key (session-key (first (list-sessions (find-application "/hello"))))))
    (list (null (search "_s=" (browser-url b)))
          (equal key (cdr (assoc "_s_hello" (browser-cookies b) :test #'string=))))))
;; ⇒ (T T)
```

#### `application-sessions` `object` — generic function

Reads the sessions of an application.  Session key → live `session`.  Guarded by the application's lock;
`list-sessions` reads it safely.

*Example:* Every browser that visits an application gets a `session` holding its own root component.  `list-sessions` returns them, most recently used first; `application-sessions` is the table behind it, by key.

```lisp
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let ((ann (visit (make-instance 'browser) "/tally"))
        (bob (visit (make-instance 'browser) "/tally")))
    (click ann "Add one")
    (click ann "Add one")
    (click bob "Add one")
    (let ((app (find-application "/tally")))
      (list (hash-table-count (application-sessions app))
            (every (lambda (s) (typep s 'session)) (list-sessions app))
            (sort (mapcar (lambda (s) (tally-count (session-root s))) (list-sessions app)) #'<)))))
;; ⇒ (2 T (1 2))
```

#### `application-max-sessions` `object` — generic function

Reads the max-sessions of an application.  Most live sessions; the least recently used go first.  `nil` for no limit.

*Example:* Each initarg of `register-application` has a reader, which `setf` changes for the running application.  The defaults:

```lisp
(defclass blank-page (component) ())
(with-fresh-applications (("/notes" 'blank-page))
  (let ((app (find-application "/notes")))
    (list (application-title app) (application-mode app) (application-session-timeout app)
          (application-max-continuations app) (application-max-sessions app)
          (application-cookie-sessions-p app) (application-websockets-p app)
          (application-local-only-p app) (application-content-security-policy app)
          (application-max-request-size app))))
;; ⇒ (NIL :DEVELOPMENT 1800 50 NIL NIL NIL NIL :STRICT NIL)
```

#### `application-error-handler` `object` — generic function

Reads the error-handler of an application.  Function of a condition returning a component or an HTML
string for the error page, or `nil` for the standard one.

*Example:* An error in a request shows an error page.  `:error-handler`, a function of the condition, makes the page: it returns a component (rendered on its own, so use plain links) or a string of HTML.

```lisp
(defclass fragile (component) ())
(defmethod render ((self fragile))
  (anchor (:callback (lambda () (error "The till is stuck."))) "Pay"))
(defclass apology (component)
  ((problem :initarg :problem :reader apology-problem)))
(defmethod render ((self apology))
  (h1 () "Sorry")
  (p () (text (princ-to-string (apology-problem self))))
  (anchor (:href "/till") "Start again"))
(with-fresh-applications (("/till" 'fragile :mode :deployment
                                   :error-handler (lambda (condition)
                                                    (make-instance 'apology :problem condition))))
  (let ((b (visit (make-instance 'browser) "/till")))
    (click b "Pay")
    (list (browser-status b) (body-text b))))
;; ⇒ (500 "Sorry The till is stuck. Start again")
```

#### `application-expired-notice` `object` — generic function

Reads the expired-notice of an application.  Component class shown, before the root, to someone whose
session expired.  `nil` starts them over silently.

*Example:* `expire-session` forgets a session at once, as the timeout does.  The browser's next request starts a new session; with an `:expired-notice`, a component class such as `session-expired-notice`, the new session shows it first.

```lisp
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment :expired-notice 'session-expired-notice))
  (let ((b (visit (make-instance 'browser) "/tally")))
    (click b "Add one")
    (expire-session (first (list-sessions (find-application "/tally"))))
    (click b "Add one")
    (list (body-text b)
          (body-text (press b "Continue")))))
;; ⇒ ("Your session expired, so you are starting again from the beginning. Continue" "Count: 0 Add one")
```

#### `application-stylesheets` `object` — generic function

Reads the stylesheets of an application.  URLs of style sheets every page links, after littoral.css.

*Example:* The title, language, style sheets and scripts go into every page's head.

```lisp
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome"))
(with-fresh-applications (("/shop" 'storefront :mode :deployment :title "Fish Shop" :language "fr"
                                   :stylesheets '("/css/shop.css") :scripts '("/js/basket.js")))
  (let* ((b (visit (make-instance 'browser) "/shop"))
         (html (browser-html b)))
    (list (not (null (search "<title>Fish Shop</title>" html)))
          (not (null (search "<html lang=\"fr\">" html)))
          (not (null (search "<link rel=\"stylesheet\" href=\"/css/shop.css\">" html)))
          (not (null (search "<script src=\"/js/basket.js\" defer" html))))))
;; ⇒ (T T T T)
```

#### `application-scripts` `object` — generic function

Reads the scripts of an application.  URLs of scripts every page loads (deferred), after littoral.js.

*Example:* The title, language, style sheets and scripts go into every page's head.

```lisp
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome"))
(with-fresh-applications (("/shop" 'storefront :mode :deployment :title "Fish Shop" :language "fr"
                                   :stylesheets '("/css/shop.css") :scripts '("/js/basket.js")))
  (let* ((b (visit (make-instance 'browser) "/shop"))
         (html (browser-html b)))
    (list (not (null (search "<title>Fish Shop</title>" html)))
          (not (null (search "<html lang=\"fr\">" html)))
          (not (null (search "<link rel=\"stylesheet\" href=\"/css/shop.css\">" html)))
          (not (null (search "<script src=\"/js/basket.js\" defer" html))))))
;; ⇒ (T T T T)
```

#### `application-credentials` `object` — generic function

Reads the credentials of an application.  (`user` . `password`) required by HTTP basic auth, or `nil`.

*Example:* With `:credentials`, a (`user` . `password`) pair, the application asks for HTTP basic authentication.

```lisp
(defclass vault (component) ())
(defmethod render ((self vault))
  (p () "The secret is 42."))
(with-fresh-applications (("/vault" 'vault :mode :deployment :credentials '("ada" . "lovelace")))
  (let ((stranger (make-instance 'browser))
        (ada (make-instance 'browser
                            :headers (list (cons "authorization"
                                                 (concatenate 'string "Basic "
                                                              (cl-base64:string-to-base64-string "ada:lovelace")))))))
    (list (browser-status (visit stranger "/vault"))
          (body-text (visit ada "/vault")))))
;; ⇒ (401 "The secret is 42.")
```

#### `reap-all-sessions` — function

Forget the idle sessions of every application.

*Example:* A session idle for longer than the application's `:session-timeout` (in seconds) is forgotten when next looked up, or by `reap-all-sessions`, which `start-reaper` runs in a thread (`start` starts one).  A timeout of -1 makes every session too old here, so the example needn't wait.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (let ((app (find-application "/hello")))
    (visit (make-instance 'browser) "/hello")
    (let ((before (length (list-sessions app))))
      (setf (application-session-timeout app) -1)
      (reap-all-sessions)
      (list before (length (list-sessions app))))))
;; ⇒ (1 0)
(start-reaper :interval 300)
(stop-reaper)
;; ⇒ NIL
```

#### `start-reaper` `&key (interval 60)` — function

Reap idle sessions every `interval` seconds in a background thread,
replacing any reaper already running.  Returns the thread.

*Example:* A session idle for longer than the application's `:session-timeout` (in seconds) is forgotten when next looked up, or by `reap-all-sessions`, which `start-reaper` runs in a thread (`start` starts one).  A timeout of -1 makes every session too old here, so the example needn't wait.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (let ((app (find-application "/hello")))
    (visit (make-instance 'browser) "/hello")
    (let ((before (length (list-sessions app))))
      (setf (application-session-timeout app) -1)
      (reap-all-sessions)
      (list before (length (list-sessions app))))))
;; ⇒ (1 0)
(start-reaper :interval 300)
(stop-reaper)
;; ⇒ NIL
```

#### `stop-reaper` — function

Stop the session reaper thread, if it is running.

*Example:* A session idle for longer than the application's `:session-timeout` (in seconds) is forgotten when next looked up, or by `reap-all-sessions`, which `start-reaper` runs in a thread (`start` starts one).  A timeout of -1 makes every session too old here, so the example needn't wait.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (let ((app (find-application "/hello")))
    (visit (make-instance 'browser) "/hello")
    (let ((before (length (list-sessions app))))
      (setf (application-session-timeout app) -1)
      (reap-all-sessions)
      (list before (length (list-sessions app))))))
;; ⇒ (1 0)
(start-reaper :interval 300)
(stop-reaper)
;; ⇒ NIL
```

#### `session-expired-notice` — class

A ready-made `expired-notice` for `register-application`: it says the
session expired and answers when its Continue button is pressed.

*Example:* `expire-session` forgets a session at once, as the timeout does.  The browser's next request starts a new session; with an `:expired-notice`, a component class such as `session-expired-notice`, the new session shows it first.

```lisp
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment :expired-notice 'session-expired-notice))
  (let ((b (visit (make-instance 'browser) "/tally")))
    (click b "Add one")
    (expire-session (first (list-sessions (find-application "/tally"))))
    (click b "Add one")
    (list (body-text b)
          (body-text (press b "Continue")))))
;; ⇒ ("Your session expired, so you are starting again from the beginning. Continue" "Count: 0 Add one")
```

#### `*instance-id*` — variable

A short name for this process, put at the front of every session key
("a1.xxxx") so a load balancer can send each session back to the process
that holds it.  `nil` for none.

*Example:* A session's key is in its pages' URLs (as _s), unless the application keeps it in a cookie.  With `*instance-id*` set, keys start with it, so a load balancer can send each session back to its process.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (let* ((*instance-id* "a1")
         (b (visit (make-instance 'browser) "/hello"))
         (key (session-key (first (list-sessions (find-application "/hello"))))))
    (list (subseq key 0 3)
          (not (null (search (concatenate 'string "_s=" key) (browser-url b)))))))
;; ⇒ ("a1." T)
```

#### `*max-request-size*` — variable

Largest request body littoral reads, in bytes, unless the application
says otherwise.  Larger requests get 413 before their body is read.

*Example:* A request whose body is larger than the application's `:max-request-size` (or, when that is `nil`, `*max-request-size*`) gets 413 before its body is read.

```lisp
(defclass guestbook (component) ())
(defmethod render ((self guestbook))
  (p () "Sign here"))
(with-fresh-applications (("/guestbook" 'guestbook :mode :deployment :max-request-size 1000))
  (let ((b (make-instance 'browser)))
    (list (raw-request b :post "/guestbook" :body (make-string 2000 :initial-element #\x))
          (let ((*max-request-size* 100))
            (raw-request b :post "/elsewhere" :body (make-string 200 :initial-element #\x))))))
;; ⇒ (413 413)
```

#### `*new-sessions-per-minute*` — variable

How many sessions one client address may start a minute; more get 429.
`nil` for no limit.

*Example:* Each client address may start only so many sessions a minute.  Behind a proxy every request comes from the proxy, so set `*trust-forwarded-for*` to count the address it reports instead.  (The address here is made up afresh, as the counts last a minute.)

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (let* ((*new-sessions-per-minute* 1)
         (*trust-forwarded-for* t)
         (address (format nil "198.18.~D.~D" (random 256) (random 256)))
         (headers (list (cons "x-forwarded-for" address))))
    (list (browser-status (visit (make-instance 'browser :headers headers) "/hello"))
          (browser-status (visit (make-instance 'browser :headers headers) "/hello")))))
;; ⇒ (200 429)
```

#### `*trust-forwarded-for*` — variable

When true, take the client address from X-Forwarded-For.  Set it only
behind a proxy that sets that header itself.

*Example:* Each client address may start only so many sessions a minute.  Behind a proxy every request comes from the proxy, so set `*trust-forwarded-for*` to count the address it reports instead.  (The address here is made up afresh, as the counts last a minute.)

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (let* ((*new-sessions-per-minute* 1)
         (*trust-forwarded-for* t)
         (address (format nil "198.18.~D.~D" (random 256) (random 256)))
         (headers (list (cons "x-forwarded-for" address))))
    (list (browser-status (visit (make-instance 'browser :headers headers) "/hello"))
          (browser-status (visit (make-instance 'browser :headers headers) "/hello")))))
;; ⇒ (200 429)
```

#### `*max-event-streams*` — variable

Most event streams open at once; more get 503.

*Example:* A page with subscribers opens an event stream for server push.  Past either limit, the stream is refused with 503 and the browser tries again later.

```lisp
(defvar *headlines* (make-channel "headlines"))
(defclass headlines (component) ())
(defmethod subscriptions ((self headlines))
  (list *headlines*))
(defmethod render ((self headlines))
  (p () "No news yet"))
(with-fresh-applications (("/news" 'headlines :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/news"))
         (events (cl-ppcre:register-groups-bind (url) ("data-lt-events=\"([^\"]*)\"" (browser-html b))
                   (cl-ppcre:regex-replace-all "&amp;" url "&"))))
    (list (let ((*max-event-streams* 0))
            (raw-request b :get events))
          (let ((*max-event-streams-per-session* 0))
            (raw-request b :get events)))))
;; ⇒ (503 503)
```

#### `*max-event-streams-per-session*` — variable

Most event streams one session may hold open.

*Example:* A page with subscribers opens an event stream for server push.  Past either limit, the stream is refused with 503 and the browser tries again later.

```lisp
(defvar *headlines* (make-channel "headlines"))
(defclass headlines (component) ())
(defmethod subscriptions ((self headlines))
  (list *headlines*))
(defmethod render ((self headlines))
  (p () "No news yet"))
(with-fresh-applications (("/news" 'headlines :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/news"))
         (events (cl-ppcre:register-groups-bind (url) ("data-lt-events=\"([^\"]*)\"" (browser-html b))
                   (cl-ppcre:regex-replace-all "&amp;" url "&"))))
    (list (let ((*max-event-streams* 0))
            (raw-request b :get events))
          (let ((*max-event-streams-per-session* 0))
            (raw-request b :get events)))))
;; ⇒ (503 503)
```

#### `application-max-request-size` `object` — generic function

Reads the max-request-size of an application.  Largest request body in bytes, or `nil` for `*max-request-size*`.

*Example:* Each initarg of `register-application` has a reader, which `setf` changes for the running application.  The defaults:

```lisp
(defclass blank-page (component) ())
(with-fresh-applications (("/notes" 'blank-page))
  (let ((app (find-application "/notes")))
    (list (application-title app) (application-mode app) (application-session-timeout app)
          (application-max-continuations app) (application-max-sessions app)
          (application-cookie-sessions-p app) (application-websockets-p app)
          (application-local-only-p app) (application-content-security-policy app)
          (application-max-request-size app))))
;; ⇒ (NIL :DEVELOPMENT 1800 50 NIL NIL NIL NIL :STRICT NIL)
```

*Example:* A request whose body is larger than the application's `:max-request-size` (or, when that is `nil`, `*max-request-size*`) gets 413 before its body is read.

```lisp
(defclass guestbook (component) ())
(defmethod render ((self guestbook))
  (p () "Sign here"))
(with-fresh-applications (("/guestbook" 'guestbook :mode :deployment :max-request-size 1000))
  (let ((b (make-instance 'browser)))
    (list (raw-request b :post "/guestbook" :body (make-string 2000 :initial-element #\x))
          (let ((*max-request-size* 100))
            (raw-request b :post "/elsewhere" :body (make-string 200 :initial-element #\x))))))
;; ⇒ (413 413)
```

#### `application-local-only-p` `object` — generic function

Reads the local-only-p of an application.  Answer only requests from this machine, and not through a
proxy unless `*trust-forwarded-for*`; others get 403.

*Example:* Each initarg of `register-application` has a reader, which `setf` changes for the running application.  The defaults:

```lisp
(defclass blank-page (component) ())
(with-fresh-applications (("/notes" 'blank-page))
  (let ((app (find-application "/notes")))
    (list (application-title app) (application-mode app) (application-session-timeout app)
          (application-max-continuations app) (application-max-sessions app)
          (application-cookie-sessions-p app) (application-websockets-p app)
          (application-local-only-p app) (application-content-security-policy app)
          (application-max-request-size app))))
;; ⇒ (NIL :DEVELOPMENT 1800 50 NIL NIL NIL NIL :STRICT NIL)
```

*Example:* A `:local-only` application answers only requests from this machine.  A request that came through a proxy (it has an X-Forwarded-For header) is not one, unless `*trust-forwarded-for*` says to believe the header.

```lisp
(defclass console (component) ())
(defmethod render ((self console))
  (p () "Console"))
(with-fresh-applications (("/console" 'console :mode :deployment :local-only t))
  (list (browser-status (visit (make-instance 'browser) "/console"))
        (browser-status (visit (make-instance 'browser :headers '(("x-forwarded-for" . "203.0.113.7")))
                               "/console"))))
;; ⇒ (200 403)
```

#### `application-language` `object` — generic function

Reads the language of an application.  The language pages are shown in, unless the session has chosen
another: their html lang attribute and the language `translate` uses.

*Example:* The title, language, style sheets and scripts go into every page's head.

```lisp
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome"))
(with-fresh-applications (("/shop" 'storefront :mode :deployment :title "Fish Shop" :language "fr"
                                   :stylesheets '("/css/shop.css") :scripts '("/js/basket.js")))
  (let* ((b (visit (make-instance 'browser) "/shop"))
         (html (browser-html b)))
    (list (not (null (search "<title>Fish Shop</title>" html)))
          (not (null (search "<html lang=\"fr\">" html)))
          (not (null (search "<link rel=\"stylesheet\" href=\"/css/shop.css\">" html)))
          (not (null (search "<script src=\"/js/basket.js\" defer" html))))))
;; ⇒ (T T T T)
```

#### `application-around-actions` `object` — generic function

Reads the around-actions of an application.  A function called with a thunk that runs a request's
callbacks, or `nil`.  It must return what the thunk returns (true when any
callback ran).  It is called for every page request and AJAX request,
including those naming no callbacks.  littoral/db uses it to run them in a
transaction.

*Example:* `:around-request` wraps the whole request, rendering included; `:around-actions` wraps only the callbacks.  Each is a function of a thunk; it must call the thunk and return what the thunk returns.  `around-actions` runs for every request for a page, with callbacks or not: here the click runs the callback, and the page it redirects to runs none.

```lisp
(defvar *shop-currency* nil)
(defvar *action-log* '())
(defclass price-list (component) ())
(defmethod render ((self price-list))
  (p () (text (format nil "Cod: 4 ~A" *shop-currency*)))
  (anchor (:callback (lambda () (push :bought *action-log*))) "Buy"))
(with-fresh-applications (("/prices" 'price-list :mode :deployment
                                     :around-request (lambda (thunk)
                                                       (let ((*shop-currency* "EUR")) (funcall thunk)))
                                     :around-actions (lambda (thunk)
                                                       (push :begin *action-log*)
                                                       (prog1 (funcall thunk)
                                                         (push :commit *action-log*)))))
  (let* ((*action-log* '())
         (b (visit (make-instance 'browser) "/prices")))
    (setf *action-log* '())
    (click b "Buy")
    (list (body-text b) (reverse *action-log*))))
;; ⇒ ("Cod: 4 EUR Buy" (:BEGIN :BOUGHT :COMMIT :BEGIN :COMMIT))
```

#### `application-around-request` `object` — generic function

Reads the around-request of an application.  A function called with a thunk that handles a whole
request, rendering included, or `nil`.  littoral/db uses it to choose the
application's database.

*Example:* `:around-request` wraps the whole request, rendering included; `:around-actions` wraps only the callbacks.  Each is a function of a thunk; it must call the thunk and return what the thunk returns.  `around-actions` runs for every request for a page, with callbacks or not: here the click runs the callback, and the page it redirects to runs none.

```lisp
(defvar *shop-currency* nil)
(defvar *action-log* '())
(defclass price-list (component) ())
(defmethod render ((self price-list))
  (p () (text (format nil "Cod: 4 ~A" *shop-currency*)))
  (anchor (:callback (lambda () (push :bought *action-log*))) "Buy"))
(with-fresh-applications (("/prices" 'price-list :mode :deployment
                                     :around-request (lambda (thunk)
                                                       (let ((*shop-currency* "EUR")) (funcall thunk)))
                                     :around-actions (lambda (thunk)
                                                       (push :begin *action-log*)
                                                       (prog1 (funcall thunk)
                                                         (push :commit *action-log*)))))
  (let* ((*action-log* '())
         (b (visit (make-instance 'browser) "/prices")))
    (setf *action-log* '())
    (click b "Buy")
    (list (body-text b) (reverse *action-log*))))
;; ⇒ ("Cod: 4 EUR Buy" (:BEGIN :BOUGHT :COMMIT :BEGIN :COMMIT))
```

#### `application-websockets-p` `object` — generic function

Reads the websockets-p of an application.  Carry AJAX and server push over one WebSocket per page
(with littoral/websocket loaded), on pages that have push.

*Example:* Each initarg of `register-application` has a reader, which `setf` changes for the running application.  The defaults:

```lisp
(defclass blank-page (component) ())
(with-fresh-applications (("/notes" 'blank-page))
  (let ((app (find-application "/notes")))
    (list (application-title app) (application-mode app) (application-session-timeout app)
          (application-max-continuations app) (application-max-sessions app)
          (application-cookie-sessions-p app) (application-websockets-p app)
          (application-local-only-p app) (application-content-security-policy app)
          (application-max-request-size app))))
;; ⇒ (NIL :DEVELOPMENT 1800 50 NIL NIL NIL NIL :STRICT NIL)
```

#### `application-content-security-policy` `object` — generic function

Reads the content-security-policy of an application.  `:strict` (scripts only with the page's nonce), a policy
string with {nonce} for the nonce, or `nil` for none.

*Example:* Each initarg of `register-application` has a reader, which `setf` changes for the running application.  The defaults:

```lisp
(defclass blank-page (component) ())
(with-fresh-applications (("/notes" 'blank-page))
  (let ((app (find-application "/notes")))
    (list (application-title app) (application-mode app) (application-session-timeout app)
          (application-max-continuations app) (application-max-sessions app)
          (application-cookie-sessions-p app) (application-websockets-p app)
          (application-local-only-p app) (application-content-security-policy app)
          (application-max-request-size app))))
;; ⇒ (NIL :DEVELOPMENT 1800 50 NIL NIL NIL NIL :STRICT NIL)
```

*Example:* Pages get a strict Content-Security-Policy header by default.  A string replaces it ({nonce} stands for the nonce the page gives its scripts); `nil` sends none.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/strict" 'greeting :mode :deployment)
                          ("/own" 'greeting :mode :deployment :content-security-policy "default-src 'self'")
                          ("/none" 'greeting :mode :deployment :content-security-policy nil))
  (flet ((policy (path)
           (let ((b (visit (make-instance 'browser) path)))
             (multiple-value-bind (status headers) (raw-request b :get (browser-url b))
               (declare (ignore status))
               (getf headers :content-security-policy)))))
    (list (subseq (policy "/strict") 0 18) (policy "/own") (policy "/none"))))
;; ⇒ ("default-src 'self'" "default-src 'self'" NIL)
```

#### `*configuration-file*` — variable

Where `save-configuration` writes, and the /config application saves after
each change.  Set by `start`'s `:configuration-file`.

*Example:* `save-configuration` writes every registered application's settings to a file (by default `*configuration-file*`, which `start`'s `:configuration-file` sets); `load-configuration` reads them back, registering or changing applications.  Error handlers and other functions are not saved.

```lisp
(defclass storefront (component) ())
(let ((*configuration-file* (merge-pathnames (format nil "littoral-config-~D.lisp" (random 1000000))
                                             (uiop:temporary-directory))))
  (unwind-protect
       (progn
         (with-fresh-applications (("/shop" 'storefront :title "Fish Shop" :session-timeout 600))
           (save-configuration))
         (with-fresh-applications ()
           (let ((app (first (load-configuration))))
             (list (application-path app) (application-root-class app)
                   (application-title app) (application-session-timeout app)))))
    (delete-file *configuration-file*)))
;; ⇒ ("/shop" STOREFRONT "Fish Shop" 600)
```

#### `save-configuration` `&optional (file *configuration-file*)` — function

Write every registered application's settings to `file`, readable only by
its owner since it may hold credentials.  Returns `file`, or `nil` when there
is none.

*Example:* `save-configuration` writes every registered application's settings to a file (by default `*configuration-file*`, which `start`'s `:configuration-file` sets); `load-configuration` reads them back, registering or changing applications.  Error handlers and other functions are not saved.

```lisp
(defclass storefront (component) ())
(let ((*configuration-file* (merge-pathnames (format nil "littoral-config-~D.lisp" (random 1000000))
                                             (uiop:temporary-directory))))
  (unwind-protect
       (progn
         (with-fresh-applications (("/shop" 'storefront :title "Fish Shop" :session-timeout 600))
           (save-configuration))
         (with-fresh-applications ()
           (let ((app (first (load-configuration))))
             (list (application-path app) (application-root-class app)
                   (application-title app) (application-session-timeout app)))))
    (delete-file *configuration-file*)))
;; ⇒ ("/shop" STOREFRONT "Fish Shop" 600)
```

#### `load-configuration` `&optional (file *configuration-file*)` — function

Configure applications from `file`, with `configure-application`.  Applications
whose classes are not loaded are skipped with a warning.  Returns the
applications configured; `nil` when `file` is `nil` or does not exist.

*Example:* `save-configuration` writes every registered application's settings to a file (by default `*configuration-file*`, which `start`'s `:configuration-file` sets); `load-configuration` reads them back, registering or changing applications.  Error handlers and other functions are not saved.

```lisp
(defclass storefront (component) ())
(let ((*configuration-file* (merge-pathnames (format nil "littoral-config-~D.lisp" (random 1000000))
                                             (uiop:temporary-directory))))
  (unwind-protect
       (progn
         (with-fresh-applications (("/shop" 'storefront :title "Fish Shop" :session-timeout 600))
           (save-configuration))
         (with-fresh-applications ()
           (let ((app (first (load-configuration))))
             (list (application-path app) (application-root-class app)
                   (application-title app) (application-session-timeout app)))))
    (delete-file *configuration-file*)))
;; ⇒ ("/shop" STOREFRONT "Fish Shop" 600)
```

#### `configure-application` `path &rest settings &key root-class title language languages mode session-timeout max-continuations cookie-sessions stylesheets scripts credentials local-only max-sessions expired-notice` — function

Change the settings given for the application at `path`, registering it
(with `root-class`) when there is none.  Sessions, and settings not given,
are kept.  It takes the settings `application-settings` lists; others, such as
`error-handler`, are set with `register-application` or the readers' `setf`.
Returns the `application`.

*Example:* `configure-application` changes only the settings it is given, and keeps the application's sessions.  For a path with no application it registers one, so it needs `:root-class` then.

```lisp
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome"))
(with-fresh-applications (("/shop" 'storefront :title "Fish Shop" :mode :deployment))
  (visit (make-instance 'browser) "/shop")
  (configure-application "/shop" :title "Fish & Chip Shop")
  (configure-application "/shop-test" :root-class 'storefront :mode :deployment)
  (let ((app (find-application "/shop")))
    (list (application-title app) (application-mode app) (length (list-sessions app))
          (mapcar #'application-path (list-applications)))))
;; ⇒ ("Fish & Chip Shop" :DEPLOYMENT 1 ("/shop" "/shop-test"))
```

#### `application-settings` `app` — function

`app`'s configuration as a plist, as `save-configuration` writes it.

*Example:* An application's settings as a plist, the way `save-configuration` writes them.  The root class is a string, so a file naming a system that isn't loaded still reads.

```lisp
(defclass storefront (component) ())
(with-fresh-applications (("/shop" 'storefront :title "Fish Shop" :mode :deployment :max-sessions 500))
  (let ((settings (application-settings (find-application "/shop"))))
    (list (getf settings :path)
          (string= (getf settings :root-class) (format nil "~A::STOREFRONT" (package-name *package*)))
          (getf settings :title) (getf settings :mode) (getf settings :max-sessions))))
;; ⇒ ("/shop" T "Fish Shop" :DEPLOYMENT 500)
```

#### `register-application` `path root-class &rest initargs &key title mode session-timeout max-continuations cookie-sessions stylesheets scripts credentials max-sessions error-handler expired-notice max-request-size local-only language around-actions around-request websockets languages content-security-policy` — function

Serve `root-class`, a component class, at `path`.  Replaces any application
already there, and with it that application's sessions (`configure-application`
keeps them).  Each keyword sets the setting its reader names, such as
`application-title` for `title`; `cookie-sessions`, `local-only` and `websockets` are
read with `application-cookie-sessions-p`, `application-local-only-p` and
`application-websockets-p`.  Returns the `application`.

*Example:* An application serves a root component class at a path.  The path is normalised to one leading slash and no trailing one, and `find-application` takes either spelling.

```lisp
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome to the shop"))
(with-fresh-applications ()
  (register-application "shop/" 'storefront :mode :deployment)
  (let ((app (find-application "/shop")))
    (list (application-path app) (application-root-class app) (typep app 'application))))
;; ⇒ ("/shop" STOREFRONT T)
```

#### `unregister-application` `path` — function

Stop serving the application at `path`.

*Example:* `list-applications` returns them sorted by path; `unregister-application` stops serving one.

```lisp
(defclass blank-page (component) ())
(defmethod render ((self blank-page))
  (p () "Nothing here yet."))
(with-fresh-applications (("/wiki" 'blank-page) ("/blog" 'blank-page) ("/admin" 'blank-page))
  (unregister-application "/admin")
  (mapcar #'application-path (list-applications)))
;; ⇒ ("/blog" "/wiki")
```

#### `find-application` `path` — function

The application registered at exactly `path`, or `nil`.

*Example:* An application serves a root component class at a path.  The path is normalised to one leading slash and no trailing one, and `find-application` takes either spelling.

```lisp
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome to the shop"))
(with-fresh-applications ()
  (register-application "shop/" 'storefront :mode :deployment)
  (let ((app (find-application "/shop")))
    (list (application-path app) (application-root-class app) (typep app 'application))))
;; ⇒ ("/shop" STOREFRONT T)
```

#### `list-applications` — function

All registered applications, sorted by path.

*Example:* `list-applications` returns them sorted by path; `unregister-application` stops serving one.

```lisp
(defclass blank-page (component) ())
(defmethod render ((self blank-page))
  (p () "Nothing here yet."))
(with-fresh-applications (("/wiki" 'blank-page) ("/blog" 'blank-page) ("/admin" 'blank-page))
  (unregister-application "/admin")
  (mapcar #'application-path (list-applications)))
;; ⇒ ("/blog" "/wiki")
```

#### `make-lack-app` `&key (prefix "")` — function

A Lack application serving every registered littoral application.
`prefix` is the path it is mounted under when the mounting middleware does
not set `:script-name` (lack's mount middleware does not).

*Example:* `make-lack-app` returns the Lack application that serves every registered application; mount it under a prefix with Lack's builder, passing the same `:prefix` so the URLs littoral writes include it.  `url-for` puts `*base-path*` in front of a path, as every URL littoral writes does.

```lisp
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let* ((site (lack:builder
                (:mount "/apps" (make-lack-app :prefix "/apps"))
                (lambda (env) (declare (ignore env)) '(200 (:content-type "text/plain") ("The rest of the site")))))
         (b (make-instance 'browser :app site)))
    (visit b "/apps/tally")
    (click b "Add one")
    (list (body-text b)
          (subseq (browser-url b) 0 (position #\? (browser-url b)))
          (subseq (find-link b "Add one") 0 12))))
;; ⇒ ("Count: 1 Add one" "/apps/tally" "/apps/tally?")
(let ((*base-path* "/apps"))
  (url-for "/tally"))
;; ⇒ "/apps/tally"
```

*Example:* The Lack application is a function of a request's environment.  A request for a new session is answered with a redirect to its first page.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (destructuring-bind (status headers body) (funcall (make-lack-app) (make-env :get "/hello"))
    (declare (ignore body))
    (list status (subseq (getf headers :location) 0 10))))
;; ⇒ (302 "/hello?_s=")
```

#### `start` `&key (port 8080) (address "127.0.0.1") (server :hunchentoot) (prefix "") configuration-file (instance-id *instance-id*) (max-threads 100) (workers 4)` — function

Serve all registered applications with Clack on `port`, under `prefix`, and
reap idle sessions in the background.  With `configuration-file`, first load
the applications saved there; /config then saves its changes to it.
`instance-id` prefixes session keys, for routing several processes.
`max-threads` caps Hunchentoot's worker threads; every open page with server
push holds one, so raise it when many pages subscribe.  With `server` `:woo`
(load littoral/woo first) `workers` event loops serve everything, push included,
without a thread per page.  A server already started is stopped first.
Returns the Clack handler.

*Example:* `start` serves the registered applications over HTTP until `stop`.  It prints the address it listens on.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(register-application "/hello" 'greeting :mode :deployment)
(unwind-protect
     (progn (start :port 48173)
            (not (null (find-application "/hello"))))
  (stop))
;; ⇒ T
```

#### `stop` — function

Stop serving, close open event streams and stop reaping sessions (and
watching for redefinitions, as `start` began).  Returns `nil`.

*Example:* `start` serves the registered applications over HTTP until `stop`.  It prints the address it listens on.

```lisp
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(register-application "/hello" 'greeting :mode :deployment)
(unwind-protect
     (progn (start :port 48173)
            (not (null (find-application "/hello"))))
  (stop))
;; ⇒ T
```

#### `*debug-errors*` — variable

When true, errors inside a request enter the debugger instead of
rendering an error page.

*Example:* An error in a request normally becomes an error page.  With `*debug-errors*` true it is not handled, so it reaches the debugger (or, here, the caller).

```lisp
(defclass fragile (component) ())
(defmethod render ((self fragile))
  (anchor (:callback (lambda () (error "The till is stuck."))) "Pay"))
(with-fresh-applications (("/till" 'fragile :mode :deployment))
  (list (browser-status (click (visit (make-instance 'browser) "/till") "Pay"))
        (let ((*debug-errors* t))
          (handler-case (click (visit (make-instance 'browser) "/till") "Pay")
            (error (condition) (princ-to-string condition))))))
;; ⇒ (500 "The till is stuck.")
```

#### `url-for` `path` — function

`path`, absolute within this littoral, as a URL the browser can follow.

*Example:* `make-lack-app` returns the Lack application that serves every registered application; mount it under a prefix with Lack's builder, passing the same `:prefix` so the URLs littoral writes include it.  `url-for` puts `*base-path*` in front of a path, as every URL littoral writes does.

```lisp
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let* ((site (lack:builder
                (:mount "/apps" (make-lack-app :prefix "/apps"))
                (lambda (env) (declare (ignore env)) '(200 (:content-type "text/plain") ("The rest of the site")))))
         (b (make-instance 'browser :app site)))
    (visit b "/apps/tally")
    (click b "Add one")
    (list (body-text b)
          (subseq (browser-url b) 0 (position #\? (browser-url b)))
          (subseq (find-link b "Add one") 0 12))))
;; ⇒ ("Count: 1 Add one" "/apps/tally" "/apps/tally?")
(let ((*base-path* "/apps"))
  (url-for "/tally"))
;; ⇒ "/apps/tally"
```

#### `*base-path*` — variable

Prepended to every URL littoral writes: the mount prefix given to
`make-lack-app` plus the request's script-name.  No trailing slash.

*Example:* `make-lack-app` returns the Lack application that serves every registered application; mount it under a prefix with Lack's builder, passing the same `:prefix` so the URLs littoral writes include it.  `url-for` puts `*base-path*` in front of a path, as every URL littoral writes does.

```lisp
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let* ((site (lack:builder
                (:mount "/apps" (make-lack-app :prefix "/apps"))
                (lambda (env) (declare (ignore env)) '(200 (:content-type "text/plain") ("The rest of the site")))))
         (b (make-instance 'browser :app site)))
    (visit b "/apps/tally")
    (click b "Add one")
    (list (body-text b)
          (subseq (browser-url b) 0 (position #\? (browser-url b)))
          (subseq (find-link b "Add one") 0 12))))
;; ⇒ ("Count: 1 Add one" "/apps/tally" "/apps/tally?")
(let ((*base-path* "/apps"))
  (url-for "/tally"))
;; ⇒ "/apps/tally"
```

#### `configure-admin` `&key user password (path "/config")` — function

Serve the configuration application at `path`.  With `user` and `password` it
is behind HTTP basic auth; without, it answers only requests from this
machine.

*Example:* The configuration application edits the registered applications' settings in the browser.  Littoral serves it at /config for requests from this machine only; with `:user` and `:password` it is behind HTTP basic authentication instead, and answers anyone who has them.

```lisp
(with-fresh-applications ()
  (let ((open (configure-admin))
        (guarded (configure-admin :path "/settings" :user "admin" :password "correct horse")))
    (list (application-path open) (application-local-only-p open) (application-credentials open)
          (application-path guarded) (application-local-only-p guarded) (application-credentials guarded))))
;; ⇒ ("/config" T NIL "/settings" NIL ("admin" . "correct horse"))
```

### Languages

#### `translate` `source &rest arguments` — function

`source` in the current language; with `arguments`, used as a `format` control
string for them.  A regional language such as "fr-CA" falls back to
"fr"'s catalogue; with no translation, `source` itself is used (and noted
for `missing-translations`).

*Example:* Source strings are English and are their own keys.  With arguments, the translation is a `format` control string for them.  A string with no translation shows as written.  Binding `*language*` chooses the language whatever the session's.

```lisp
(let ((*language* "fr"))
  (list (translate "Save")
        (translate "~A is required." "Nom")
        (translate "Feed the otters")))
;; ⇒ ("Enregistrer" "Nom est obligatoire." "Feed the otters")
```

#### `translate-plural` `count singular plural &rest arguments` — function

The current language's form of `singular` (`plural` in English) for `count`,
formatted with `count` and then `arguments`.  The catalogue's entry is keyed by
`singular`; the language's plural rule picks the form.  With no translation,
`singular` when `count` is 1, else `plural`.

*Example:* An entry is the source string and its translation, or one form per plural form, in the order the language's rule numbers them.  `translate-plural` formats the form for `count` with `count`.  French counts zero as singular.

```lisp
(define-translations "fr"
  ("Your basket" "Votre panier")
  ("~D otter" "~D loutre" "~D loutres"))
;; ⇒ "fr"
(let ((*language* "fr"))
  (list (translate "Your basket")
        (translate-plural 0 "~D otter" "~D otters")
        (translate-plural 2 "~D otter" "~D otters")))
;; ⇒ ("Votre panier" "0 loutre" "2 loutres")
(let ((*language* "en"))
  (list (translate-plural 0 "~D otter" "~D otters")
        (translate-plural 1 "~D otter" "~D otters")))
;; ⇒ ("0 otters" "1 otter")
```

#### `define-translations` `language &body entries` — macro

Add `entries`, unevaluated, to `language`'s catalogue.  Each is (`source` `form`
...): one form for plain text, or one per plural form, in the order the
language's plural rule numbers them.  An entry replaces any for the same
`source`.  Signals an error when a form isn't a string or calls a function
with ~/…/.  Returns `language`.

*Example:* An entry is the source string and its translation, or one form per plural form, in the order the language's rule numbers them.  `translate-plural` formats the form for `count` with `count`.  French counts zero as singular.

```lisp
(define-translations "fr"
  ("Your basket" "Votre panier")
  ("~D otter" "~D loutre" "~D loutres"))
;; ⇒ "fr"
(let ((*language* "fr"))
  (list (translate "Your basket")
        (translate-plural 0 "~D otter" "~D otters")
        (translate-plural 2 "~D otter" "~D otters")))
;; ⇒ ("Votre panier" "0 loutre" "2 loutres")
(let ((*language* "en"))
  (list (translate-plural 0 "~D otter" "~D otters")
        (translate-plural 1 "~D otter" "~D otters")))
;; ⇒ ("0 otters" "1 otter")
```

#### `add-translations` `language entries` — function

Add `entries`, a list as `define-translations` takes, to `language`'s catalogue.

*Example:* `define-translations`'s function, for entries made at run time, such as read from a database.  A translation may not call functions with ~/…/.

```lisp
(add-translations "de" (list (list "Opening hours" "Öffnungszeiten")))
;; ⇒ "de"
(let ((*language* "de")) (translate "Opening hours"))
;; ⇒ "Öffnungszeiten"
(handler-case (add-translations "de" '(("Hi" "~/cl-user::steal/")))
  (error () :refused))
;; ⇒ :REFUSED
```

#### `load-translations` `language pathname` — function

Add the entries read from the file `pathname`, each a list (`source` `form` ...),
to `language`'s catalogue.  Nothing in the file is evaluated.

*Example:* A file of entries, one list per entry, as translators can edit them; it is read, never evaluated.

```lisp
(let ((file (merge-pathnames "doc-example-es.lisp" (uiop:temporary-directory))))
  (unwind-protect
       (progn
         (with-open-file (out file :direction :output :if-exists :supersede :external-format :utf-8)
           (write-line "(\"Tide tables\" \"Tablas de mareas\")" out)
           (write-line "(\"~D wave\" \"~D ola\" \"~D olas\")" out))
         (load-translations "es" file)
         (let ((*language* "es"))
           (list (translate "Tide tables") (translate-plural 3 "~D wave" "~D waves"))))
    (delete-file file)))
;; ⇒ ("Tablas de mareas" "3 olas")
```

#### `define-language` `code &key name plural decimal group months date` — function

Describe the language `code` (such as "fr" or "pt-BR"): its `name` in
itself, its `plural` rule (a function of a count returning the index of the
plural form to use), its `decimal` and `group` separators, its `months`' names and
its `date` function of (`year` `month` `day` `months`) returning a string.  Unsupplied
details are English's.  Replaces any description of `code`; returns `code`.

*Example:* Describe a language Littoral doesn't know: what it calls itself, its plural rule, separators, months and date format.  Unsupplied details are English's.  A regional code such as "pt-BR" falls back to "pt".

```lisp
(define-language "pt" :name "Português"
  :decimal "," :group "."
  :months '("janeiro" "fevereiro" "março" "abril" "maio" "junho" "julho"
            "agosto" "setembro" "outubro" "novembro" "dezembro")
  :date (lambda (year month day months)
          (format nil "~D de ~A de ~D" day (nth (1- month) months) year)))
;; ⇒ "pt"
(let ((*language* "pt-BR"))
  (list (language-display-name "pt-BR")
        (localized-number 1234.5)
        (localized-date 2026 3 14)))
;; ⇒ ("Português" "1.234,50" "14 de março de 2026")
```

#### `current-language` — function

The language this request is answered in: `*language*`, else the
session's, else the application's.

*Example:* A session starts in the application's language (or the browser's choice among its `:languages`); `set-language` changes it from then on.

```lisp
(defclass greeter (component) ())
(defmethod render ((self greeter))
  (p () (text (current-language)) ": " (translate "Yes"))
  (anchor (:callback (lambda () (set-language "es"))) "Español"))
(with-fresh-applications (("/greeter" 'greeter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greeter")
    (let ((before (body-text b)))
      (click b "Español")
      (list before (body-text b)))))
;; ⇒ ("en: Yes Español" "es: Sí Español")
```

#### `set-language` `code &optional (session *session*)` — function

From now on, show `session` in the language `code`.

*Example:* A session starts in the application's language (or the browser's choice among its `:languages`); `set-language` changes it from then on.

```lisp
(defclass greeter (component) ())
(defmethod render ((self greeter))
  (p () (text (current-language)) ": " (translate "Yes"))
  (anchor (:callback (lambda () (set-language "es"))) "Español"))
(with-fresh-applications (("/greeter" 'greeter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greeter")
    (let ((before (body-text b)))
      (click b "Español")
      (list before (body-text b)))))
;; ⇒ ("en: Yes Español" "es: Sí Español")
```

#### `*language*` — variable

When bound to a language code, the language to use regardless of the session.

*Example:* Source strings are English and are their own keys.  With arguments, the translation is a `format` control string for them.  A string with no translation shows as written.  Binding `*language*` chooses the language whatever the session's.

```lisp
(let ((*language* "fr"))
  (list (translate "Save")
        (translate "~A is required." "Nom")
        (translate "Feed the otters")))
;; ⇒ ("Enregistrer" "Nom est obligatoire." "Feed the otters")
```

#### `*source-language*` — variable

The language source strings are written in; it needs no catalogue.

*Example:* The languages with a catalogue, the source language (which needs none) first.

```lisp
(let ((languages (translated-languages)))
  (list (first languages) *source-language*
        (not (null (member "fr" languages :test #'string=)))))
;; ⇒ ("en" "en" T)
```

#### `missing-translations` `language` — function

The source strings shown in `language` so far that its catalogue lacks;
for translators.

*Example:* The source strings shown in a language whose catalogue lacks them, for the translators.

```lisp
(let ((*language* "nl"))
  (translate "Opening hours")
  (translate "~D otter" 2)
  (missing-translations "nl"))
;; ⇒ ("Opening hours" "~D otter")
```

#### `translated-languages` — function

The languages that have a catalogue, with the source language.

*Example:* The languages with a catalogue, the source language (which needs none) first.

```lisp
(let ((languages (translated-languages)))
  (list (first languages) *source-language*
        (not (null (member "fr" languages :test #'string=)))))
;; ⇒ ("en" "en" T)
```

#### `language-display-name` `code` — function

What the language `code` calls itself, as `define-language` named it; a
regional code falls back to its language's name, an unknown one is
returned as it is.

*Example:* Describe a language Littoral doesn't know: what it calls itself, its plural rule, separators, months and date format.  Unsupplied details are English's.  A regional code such as "pt-BR" falls back to "pt".

```lisp
(define-language "pt" :name "Português"
  :decimal "," :group "."
  :months '("janeiro" "fevereiro" "março" "abril" "maio" "junho" "julho"
            "agosto" "setembro" "outubro" "novembro" "dezembro")
  :date (lambda (year month day months)
          (format nil "~D de ~A de ~D" day (nth (1- month) months) year)))
;; ⇒ "pt"
(let ((*language* "pt-BR"))
  (list (language-display-name "pt-BR")
        (localized-number 1234.5)
        (localized-date 2026 3 14)))
;; ⇒ ("Português" "1.234,50" "14 de março de 2026")
```

#### `translate-label` `label` — function

`label` translated when it is a non-empty string; anything else as it is.

*Example:* For labels that may be absent: a non-empty string is translated, anything else returned as it is.

```lisp
(let ((*language* "fr"))
  (list (translate-label "Cancel") (translate-label "") (translate-label nil)))
;; ⇒ ("Annuler" "" NIL)
```

#### `localized-number` `number &key (decimals (if (integerp number) 0 2))` — function

`number` as the current language writes it, rounded to `decimals` places (0
for an integer, else 2 by default), with its digit group and decimal
separators.

*Example:* Integers get no decimals unless asked; other numbers two.

```lisp
(let ((*language* "en"))
  (list (localized-number 1234567) (localized-number -0.5) (localized-number 3 :decimals 1)))
;; ⇒ ("1,234,567" "-0.50" "3.0")
(let ((*language* "de"))
  (localized-number 1234.567))
;; ⇒ "1.234,57"
```

#### `localized-date` `year month day` — function

The date as the current language writes it in full, such as
"October 7, 2026" or "7 octobre 2026".

```lisp
(list (let ((*language* "en")) (localized-date 2026 10 7))
      (let ((*language* "de")) (localized-date 2026 10 7))
      (let ((*language* "es")) (localized-date 2026 10 7)))
;; ⇒ ("October 7, 2026" "7. Oktober 2026" "7 de octubre de 2026")
```

#### `application-languages` `object` — generic function

Reads the languages of an application.  Languages offered besides `language`: a new session takes the
first of these and `language` that the browser's Accept-Language asks for.

*Example:* A new session takes the first language the browser's Accept-Language asks for among the application's `:language` and `:languages`.  A `language-chooser` links to each, named in itself; the current one is not a link.

```lisp
(defclass shop (component)
  ((chooser :initform (make-instance 'language-chooser) :reader chooser)))
(defmethod children ((self shop)) (list (chooser self)))
(defmethod render ((self shop))
  (render-component (chooser self))
  (p () (translate "Cancel")))
(with-fresh-applications (("/shop" 'shop :mode :deployment :languages '("fr" "de")))
  (let ((b (make-instance 'browser :headers '(("accept-language" . "de-CH, de;q=0.9")))))
    (visit b "/shop")
    (let ((german (body-text b)))
      (click b "Français")
      (list (application-languages (find-application "/shop"))
            german
            (body-text b)
            (null (find-link b "Français"))))))
;; ⇒ (("fr" "de") "English Français Deutsch Abbrechen" "English Français Deutsch Annuler" T)
```

#### `language-chooser` — class

Links to show the session in each language offered,
each named in its own language; the current one is not a link.  `:languages`
lists the codes to offer; by default the application's `language` and
`languages`.

*Example:* A new session takes the first language the browser's Accept-Language asks for among the application's `:language` and `:languages`.  A `language-chooser` links to each, named in itself; the current one is not a link.

```lisp
(defclass shop (component)
  ((chooser :initform (make-instance 'language-chooser) :reader chooser)))
(defmethod children ((self shop)) (list (chooser self)))
(defmethod render ((self shop))
  (render-component (chooser self))
  (p () (translate "Cancel")))
(with-fresh-applications (("/shop" 'shop :mode :deployment :languages '("fr" "de")))
  (let ((b (make-instance 'browser :headers '(("accept-language" . "de-CH, de;q=0.9")))))
    (visit b "/shop")
    (let ((german (body-text b)))
      (click b "Français")
      (list (application-languages (find-application "/shop"))
            german
            (body-text b)
            (null (find-link b "Français"))))))
;; ⇒ (("fr" "de") "English Français Deutsch Abbrechen" "English Français Deutsch Annuler" T)
```

## Package `littoral.html`

Tags and brushes for writing HTML in RENDER methods.

### Canvas

#### `*canvas*` — variable

The stream render methods write HTML to.  Outside rendering (and
`with-canvas-to-string`) it discards what is written.

*Example:* Tags write to whatever stream `*canvas*` is bound to.  Outside rendering it discards what it is given.

```lisp
(let ((*canvas* (make-string-output-stream)))
  (p () "Saved.")
  (get-output-stream-string *canvas*))
;; ⇒ "<p>Saved.</p>"
```

#### `text` `thing` — function

Write `thing`, printed with `princ` and HTML-escaped.

*Example:* A literal string in a tag's body is written as text, but any other form is only evaluated, so a computed value needs `text`.  `text` prints with `princ` and escapes.

```lisp
(defun price-tag (pence)
  (span (:class "price")
    "£" (text (/ pence 100.0))))
(with-canvas-to-string ()
  (price-tag 450)
  (p () (format nil "~D items" 3))  ; written nowhere: the value is dropped
  (p () (text "<3 items>")))
;; ⇒ "<span class=\"price\">£4.5</span><p></p><p>&lt;3 items&gt;</p>"
```

#### `raw` `string` — function

Write `string` verbatim.

*Example:* `raw` writes a string as it is, for markup you trust, such as HTML your own code made.

```lisp
(with-canvas-to-string ()
  (div (:class "icon")
    (raw "<svg width=\"8\" height=\"8\"></svg>")))
;; ⇒ "<div class=\"icon\"><svg width=\"8\" height=\"8\"></svg></div>"
```

#### `with-canvas-to-string` `() &body body` — macro

Evaluate `body` with `*canvas*` collecting into a string, which is returned.

*Example:* The HTML that rendering code writes, as a string.

```lisp
(with-canvas-to-string () (p (:class "note") "Fish & chips"))
;; ⇒ "<p class=\"note\">Fish &amp; chips</p>"
```

*Example:* Render code writes to the canvas; this macro collects what it writes into a string, which is handy at the `repl` and in tests.

```lisp
(with-canvas-to-string ()
  (h1 () "Menu")
  (p (:class "note") "Fish & chips"))
;; ⇒ "<h1>Menu</h1><p class=\"note\">Fish &amp; chips</p>"
```

#### `html-escape` `thing` — function

Return the printed representation of `thing` with HTML metacharacters escaped.

*Example:* The escaping `text` does, as a function.  Anything that isn't a string is printed first.

```lisp
(list (html-escape "Tom & \"Jerry\" <tj@example.com>")
      (html-escape 42))
;; ⇒ ("Tom &amp; &quot;Jerry&quot; &lt;tj@example.com&gt;" "42")
```

### Plain tags

#### `div` `&rest arguments` — macro

Write an HTML div element.  Arguments are as for `tag`, without the name.

*Example:* The first argument of a tag is a plist of attributes, whose values are evaluated.  A `nil` value leaves the attribute out, T writes it bare (a boolean attribute), and a `:class` list is joined with spaces, its NILs dropped.  Values are escaped.

```lisp
(let ((selected t) (disabled nil))
  (with-canvas-to-string ()
    (div (:id "row-1" :class (list "row" (and selected "selected") nil)
          :hidden disabled :data-note "say \"hi\"")
      (span (:title "Ready" :aria-busy t) "Go"))))
;; ⇒ "<div id=\"row-1\" class=\"row selected\" data-note=\"say &quot;hi&quot;\"><span title=\"Ready\" aria-busy>Go</span></div>"
```

*Example:* The attribute list may be left out when the tag has none and its body does not start with a keyword list; () works too.

```lisp
(with-canvas-to-string ()
  (div
    (p "No attributes.")
    (p () "Empty attributes.")
    (span (text 3))))
;; ⇒ "<div><p>No attributes.</p><p>Empty attributes.</p><span>3</span></div>"
```

*Example:* The document-structure tags.

```lisp
(with-canvas-to-string ()
  (header () (nav (:aria-label "Site") "Home"))
  (main ()
    (section (:id "news")
      (article () "First post")
      (aside () "Related")))
  (footer () (span () "2026")))
;; ⇒ "<header><nav aria-label=\"Site\">Home</nav></header><main><section id=\"news\"><article>First post</article><aside>Related</aside></section></main><footer><span>2026</span></footer>"
```

#### `span` `&rest arguments` — macro

Write an HTML span element.  Arguments are as for `tag`, without the name.

*Example:* The first argument of a tag is a plist of attributes, whose values are evaluated.  A `nil` value leaves the attribute out, T writes it bare (a boolean attribute), and a `:class` list is joined with spaces, its NILs dropped.  Values are escaped.

```lisp
(let ((selected t) (disabled nil))
  (with-canvas-to-string ()
    (div (:id "row-1" :class (list "row" (and selected "selected") nil)
          :hidden disabled :data-note "say \"hi\"")
      (span (:title "Ready" :aria-busy t) "Go"))))
;; ⇒ "<div id=\"row-1\" class=\"row selected\" data-note=\"say &quot;hi&quot;\"><span title=\"Ready\" aria-busy>Go</span></div>"
```

*Example:* The attribute list may be left out when the tag has none and its body does not start with a keyword list; () works too.

```lisp
(with-canvas-to-string ()
  (div
    (p "No attributes.")
    (p () "Empty attributes.")
    (span (text 3))))
;; ⇒ "<div><p>No attributes.</p><p>Empty attributes.</p><span>3</span></div>"
```

*Example:* The document-structure tags.

```lisp
(with-canvas-to-string ()
  (header () (nav (:aria-label "Site") "Home"))
  (main ()
    (section (:id "news")
      (article () "First post")
      (aside () "Related")))
  (footer () (span () "2026")))
;; ⇒ "<header><nav aria-label=\"Site\">Home</nav></header><main><section id=\"news\"><article>First post</article><aside>Related</aside></section></main><footer><span>2026</span></footer>"
```

#### `p` `&rest arguments` — macro

Write an HTML p element.  Arguments are as for `tag`, without the name.

*Example:* The attribute list may be left out when the tag has none and its body does not start with a keyword list; () works too.

```lisp
(with-canvas-to-string ()
  (div
    (p "No attributes.")
    (p () "Empty attributes.")
    (span (text 3))))
;; ⇒ "<div><p>No attributes.</p><p>Empty attributes.</p><span>3</span></div>"
```

*Example:* Headings and paragraphs.

```lisp
(with-canvas-to-string ()
  (h1 () "Guide")
  (h2 () "Setup")
  (h3 () "Linux")
  (h4 () "Debian")
  (h5 () "Packages")
  (h6 () "Notes")
  (p () "Install SBCL first."))
;; ⇒ "<h1>Guide</h1><h2>Setup</h2><h3>Linux</h3><h4>Debian</h4><h5>Packages</h5><h6>Notes</h6><p>Install SBCL first.</p>"
```

#### `h1` `&rest arguments` — macro

Write an HTML h1 element.  Arguments are as for `tag`, without the name.

*Example:* Headings and paragraphs.

```lisp
(with-canvas-to-string ()
  (h1 () "Guide")
  (h2 () "Setup")
  (h3 () "Linux")
  (h4 () "Debian")
  (h5 () "Packages")
  (h6 () "Notes")
  (p () "Install SBCL first."))
;; ⇒ "<h1>Guide</h1><h2>Setup</h2><h3>Linux</h3><h4>Debian</h4><h5>Packages</h5><h6>Notes</h6><p>Install SBCL first.</p>"
```

#### `h2` `&rest arguments` — macro

Write an HTML h2 element.  Arguments are as for `tag`, without the name.

*Example:* Headings and paragraphs.

```lisp
(with-canvas-to-string ()
  (h1 () "Guide")
  (h2 () "Setup")
  (h3 () "Linux")
  (h4 () "Debian")
  (h5 () "Packages")
  (h6 () "Notes")
  (p () "Install SBCL first."))
;; ⇒ "<h1>Guide</h1><h2>Setup</h2><h3>Linux</h3><h4>Debian</h4><h5>Packages</h5><h6>Notes</h6><p>Install SBCL first.</p>"
```

#### `h3` `&rest arguments` — macro

Write an HTML h3 element.  Arguments are as for `tag`, without the name.

*Example:* Headings and paragraphs.

```lisp
(with-canvas-to-string ()
  (h1 () "Guide")
  (h2 () "Setup")
  (h3 () "Linux")
  (h4 () "Debian")
  (h5 () "Packages")
  (h6 () "Notes")
  (p () "Install SBCL first."))
;; ⇒ "<h1>Guide</h1><h2>Setup</h2><h3>Linux</h3><h4>Debian</h4><h5>Packages</h5><h6>Notes</h6><p>Install SBCL first.</p>"
```

#### `h4` `&rest arguments` — macro

Write an HTML h4 element.  Arguments are as for `tag`, without the name.

*Example:* Headings and paragraphs.

```lisp
(with-canvas-to-string ()
  (h1 () "Guide")
  (h2 () "Setup")
  (h3 () "Linux")
  (h4 () "Debian")
  (h5 () "Packages")
  (h6 () "Notes")
  (p () "Install SBCL first."))
;; ⇒ "<h1>Guide</h1><h2>Setup</h2><h3>Linux</h3><h4>Debian</h4><h5>Packages</h5><h6>Notes</h6><p>Install SBCL first.</p>"
```

#### `h5` `&rest arguments` — macro

Write an HTML h5 element.  Arguments are as for `tag`, without the name.

*Example:* Headings and paragraphs.

```lisp
(with-canvas-to-string ()
  (h1 () "Guide")
  (h2 () "Setup")
  (h3 () "Linux")
  (h4 () "Debian")
  (h5 () "Packages")
  (h6 () "Notes")
  (p () "Install SBCL first."))
;; ⇒ "<h1>Guide</h1><h2>Setup</h2><h3>Linux</h3><h4>Debian</h4><h5>Packages</h5><h6>Notes</h6><p>Install SBCL first.</p>"
```

#### `h6` `&rest arguments` — macro

Write an HTML h6 element.  Arguments are as for `tag`, without the name.

*Example:* Headings and paragraphs.

```lisp
(with-canvas-to-string ()
  (h1 () "Guide")
  (h2 () "Setup")
  (h3 () "Linux")
  (h4 () "Debian")
  (h5 () "Packages")
  (h6 () "Notes")
  (p () "Install SBCL first."))
;; ⇒ "<h1>Guide</h1><h2>Setup</h2><h3>Linux</h3><h4>Debian</h4><h5>Packages</h5><h6>Notes</h6><p>Install SBCL first.</p>"
```

#### `ul` `&rest arguments` — macro

Write an HTML ul element.  Arguments are as for `tag`, without the name.

*Example:* Lists.  A body may contain any Lisp code, such as a loop writing one item per element.

```lisp
(with-canvas-to-string ()
  (ul (:class "tags")
    (dolist (tag '("lisp" "web"))
      (li () (text tag))))
  (ol () (li () "Clone") (li () "Build"))
  (dl ()
    (dt () "SBCL") (dd () "A Common Lisp compiler")))
;; ⇒ "<ul class=\"tags\"><li>lisp</li><li>web</li></ul><ol><li>Clone</li><li>Build</li></ol><dl><dt>SBCL</dt><dd>A Common Lisp compiler</dd></dl>"
```

#### `ol` `&rest arguments` — macro

Write an HTML ol element.  Arguments are as for `tag`, without the name.

*Example:* Lists.  A body may contain any Lisp code, such as a loop writing one item per element.

```lisp
(with-canvas-to-string ()
  (ul (:class "tags")
    (dolist (tag '("lisp" "web"))
      (li () (text tag))))
  (ol () (li () "Clone") (li () "Build"))
  (dl ()
    (dt () "SBCL") (dd () "A Common Lisp compiler")))
;; ⇒ "<ul class=\"tags\"><li>lisp</li><li>web</li></ul><ol><li>Clone</li><li>Build</li></ol><dl><dt>SBCL</dt><dd>A Common Lisp compiler</dd></dl>"
```

#### `li` `&rest arguments` — macro

Write an HTML li element.  Arguments are as for `tag`, without the name.

*Example:* Lists.  A body may contain any Lisp code, such as a loop writing one item per element.

```lisp
(with-canvas-to-string ()
  (ul (:class "tags")
    (dolist (tag '("lisp" "web"))
      (li () (text tag))))
  (ol () (li () "Clone") (li () "Build"))
  (dl ()
    (dt () "SBCL") (dd () "A Common Lisp compiler")))
;; ⇒ "<ul class=\"tags\"><li>lisp</li><li>web</li></ul><ol><li>Clone</li><li>Build</li></ol><dl><dt>SBCL</dt><dd>A Common Lisp compiler</dd></dl>"
```

#### `dl` `&rest arguments` — macro

Write an HTML dl element.  Arguments are as for `tag`, without the name.

*Example:* Lists.  A body may contain any Lisp code, such as a loop writing one item per element.

```lisp
(with-canvas-to-string ()
  (ul (:class "tags")
    (dolist (tag '("lisp" "web"))
      (li () (text tag))))
  (ol () (li () "Clone") (li () "Build"))
  (dl ()
    (dt () "SBCL") (dd () "A Common Lisp compiler")))
;; ⇒ "<ul class=\"tags\"><li>lisp</li><li>web</li></ul><ol><li>Clone</li><li>Build</li></ol><dl><dt>SBCL</dt><dd>A Common Lisp compiler</dd></dl>"
```

#### `dt` `&rest arguments` — macro

Write an HTML dt element.  Arguments are as for `tag`, without the name.

*Example:* Lists.  A body may contain any Lisp code, such as a loop writing one item per element.

```lisp
(with-canvas-to-string ()
  (ul (:class "tags")
    (dolist (tag '("lisp" "web"))
      (li () (text tag))))
  (ol () (li () "Clone") (li () "Build"))
  (dl ()
    (dt () "SBCL") (dd () "A Common Lisp compiler")))
;; ⇒ "<ul class=\"tags\"><li>lisp</li><li>web</li></ul><ol><li>Clone</li><li>Build</li></ol><dl><dt>SBCL</dt><dd>A Common Lisp compiler</dd></dl>"
```

#### `dd` `&rest arguments` — macro

Write an HTML dd element.  Arguments are as for `tag`, without the name.

*Example:* Lists.  A body may contain any Lisp code, such as a loop writing one item per element.

```lisp
(with-canvas-to-string ()
  (ul (:class "tags")
    (dolist (tag '("lisp" "web"))
      (li () (text tag))))
  (ol () (li () "Clone") (li () "Build"))
  (dl ()
    (dt () "SBCL") (dd () "A Common Lisp compiler")))
;; ⇒ "<ul class=\"tags\"><li>lisp</li><li>web</li></ul><ol><li>Clone</li><li>Build</li></ol><dl><dt>SBCL</dt><dd>A Common Lisp compiler</dd></dl>"
```

#### `table` — class

How a class's objects are stored.

#### `table` `&rest arguments` — macro

Write an HTML table element.  Arguments are as for `tag`, without the name.

*Example:* Tables.

```lisp
(let ((rows '(("Apples" 3) ("Pears" 5))))
  (with-canvas-to-string ()
    (table (:class "stock")
      (caption () "Stock")
      (thead () (tr () (th (:scope "col") "Fruit") (th (:scope "col") "Count")))
      (tbody ()
        (loop for (fruit count) in rows
              do (tr () (td () (text fruit)) (td () (text count)))))
      (tfoot () (tr () (th () "Total") (td () (text (reduce #'+ rows :key #'second))))))))
;; ⇒ "<table class=\"stock\"><caption>Stock</caption><thead><tr><th scope=\"col\">Fruit</th><th scope=\"col\">Count</th></tr></thead><tbody><tr><td>Apples</td><td>3</td></tr><tr><td>Pears</td><td>5</td></tr></tbody><tfoot><tr><th>Total</th><td>8</td></tr></tfoot></table>"
```

#### `thead` `&rest arguments` — macro

Write an HTML thead element.  Arguments are as for `tag`, without the name.

*Example:* Tables.

```lisp
(let ((rows '(("Apples" 3) ("Pears" 5))))
  (with-canvas-to-string ()
    (table (:class "stock")
      (caption () "Stock")
      (thead () (tr () (th (:scope "col") "Fruit") (th (:scope "col") "Count")))
      (tbody ()
        (loop for (fruit count) in rows
              do (tr () (td () (text fruit)) (td () (text count)))))
      (tfoot () (tr () (th () "Total") (td () (text (reduce #'+ rows :key #'second))))))))
;; ⇒ "<table class=\"stock\"><caption>Stock</caption><thead><tr><th scope=\"col\">Fruit</th><th scope=\"col\">Count</th></tr></thead><tbody><tr><td>Apples</td><td>3</td></tr><tr><td>Pears</td><td>5</td></tr></tbody><tfoot><tr><th>Total</th><td>8</td></tr></tfoot></table>"
```

#### `tbody` `&rest arguments` — macro

Write an HTML tbody element.  Arguments are as for `tag`, without the name.

*Example:* Tables.

```lisp
(let ((rows '(("Apples" 3) ("Pears" 5))))
  (with-canvas-to-string ()
    (table (:class "stock")
      (caption () "Stock")
      (thead () (tr () (th (:scope "col") "Fruit") (th (:scope "col") "Count")))
      (tbody ()
        (loop for (fruit count) in rows
              do (tr () (td () (text fruit)) (td () (text count)))))
      (tfoot () (tr () (th () "Total") (td () (text (reduce #'+ rows :key #'second))))))))
;; ⇒ "<table class=\"stock\"><caption>Stock</caption><thead><tr><th scope=\"col\">Fruit</th><th scope=\"col\">Count</th></tr></thead><tbody><tr><td>Apples</td><td>3</td></tr><tr><td>Pears</td><td>5</td></tr></tbody><tfoot><tr><th>Total</th><td>8</td></tr></tfoot></table>"
```

#### `tfoot` `&rest arguments` — macro

Write an HTML tfoot element.  Arguments are as for `tag`, without the name.

*Example:* Tables.

```lisp
(let ((rows '(("Apples" 3) ("Pears" 5))))
  (with-canvas-to-string ()
    (table (:class "stock")
      (caption () "Stock")
      (thead () (tr () (th (:scope "col") "Fruit") (th (:scope "col") "Count")))
      (tbody ()
        (loop for (fruit count) in rows
              do (tr () (td () (text fruit)) (td () (text count)))))
      (tfoot () (tr () (th () "Total") (td () (text (reduce #'+ rows :key #'second))))))))
;; ⇒ "<table class=\"stock\"><caption>Stock</caption><thead><tr><th scope=\"col\">Fruit</th><th scope=\"col\">Count</th></tr></thead><tbody><tr><td>Apples</td><td>3</td></tr><tr><td>Pears</td><td>5</td></tr></tbody><tfoot><tr><th>Total</th><td>8</td></tr></tfoot></table>"
```

#### `tr` `&rest arguments` — macro

Write an HTML tr element.  Arguments are as for `tag`, without the name.

*Example:* Tables.

```lisp
(let ((rows '(("Apples" 3) ("Pears" 5))))
  (with-canvas-to-string ()
    (table (:class "stock")
      (caption () "Stock")
      (thead () (tr () (th (:scope "col") "Fruit") (th (:scope "col") "Count")))
      (tbody ()
        (loop for (fruit count) in rows
              do (tr () (td () (text fruit)) (td () (text count)))))
      (tfoot () (tr () (th () "Total") (td () (text (reduce #'+ rows :key #'second))))))))
;; ⇒ "<table class=\"stock\"><caption>Stock</caption><thead><tr><th scope=\"col\">Fruit</th><th scope=\"col\">Count</th></tr></thead><tbody><tr><td>Apples</td><td>3</td></tr><tr><td>Pears</td><td>5</td></tr></tbody><tfoot><tr><th>Total</th><td>8</td></tr></tfoot></table>"
```

#### `td` `&rest arguments` — macro

Write an HTML td element.  Arguments are as for `tag`, without the name.

*Example:* Tables.

```lisp
(let ((rows '(("Apples" 3) ("Pears" 5))))
  (with-canvas-to-string ()
    (table (:class "stock")
      (caption () "Stock")
      (thead () (tr () (th (:scope "col") "Fruit") (th (:scope "col") "Count")))
      (tbody ()
        (loop for (fruit count) in rows
              do (tr () (td () (text fruit)) (td () (text count)))))
      (tfoot () (tr () (th () "Total") (td () (text (reduce #'+ rows :key #'second))))))))
;; ⇒ "<table class=\"stock\"><caption>Stock</caption><thead><tr><th scope=\"col\">Fruit</th><th scope=\"col\">Count</th></tr></thead><tbody><tr><td>Apples</td><td>3</td></tr><tr><td>Pears</td><td>5</td></tr></tbody><tfoot><tr><th>Total</th><td>8</td></tr></tfoot></table>"
```

#### `th` `&rest arguments` — macro

Write an HTML th element.  Arguments are as for `tag`, without the name.

*Example:* Tables.

```lisp
(let ((rows '(("Apples" 3) ("Pears" 5))))
  (with-canvas-to-string ()
    (table (:class "stock")
      (caption () "Stock")
      (thead () (tr () (th (:scope "col") "Fruit") (th (:scope "col") "Count")))
      (tbody ()
        (loop for (fruit count) in rows
              do (tr () (td () (text fruit)) (td () (text count)))))
      (tfoot () (tr () (th () "Total") (td () (text (reduce #'+ rows :key #'second))))))))
;; ⇒ "<table class=\"stock\"><caption>Stock</caption><thead><tr><th scope=\"col\">Fruit</th><th scope=\"col\">Count</th></tr></thead><tbody><tr><td>Apples</td><td>3</td></tr><tr><td>Pears</td><td>5</td></tr></tbody><tfoot><tr><th>Total</th><td>8</td></tr></tfoot></table>"
```

#### `caption` `&rest arguments` — macro

Write an HTML caption element.  Arguments are as for `tag`, without the name.

*Example:* Tables.

```lisp
(let ((rows '(("Apples" 3) ("Pears" 5))))
  (with-canvas-to-string ()
    (table (:class "stock")
      (caption () "Stock")
      (thead () (tr () (th (:scope "col") "Fruit") (th (:scope "col") "Count")))
      (tbody ()
        (loop for (fruit count) in rows
              do (tr () (td () (text fruit)) (td () (text count)))))
      (tfoot () (tr () (th () "Total") (td () (text (reduce #'+ rows :key #'second))))))))
;; ⇒ "<table class=\"stock\"><caption>Stock</caption><thead><tr><th scope=\"col\">Fruit</th><th scope=\"col\">Count</th></tr></thead><tbody><tr><td>Apples</td><td>3</td></tr><tr><td>Pears</td><td>5</td></tr></tbody><tfoot><tr><th>Total</th><td>8</td></tr></tfoot></table>"
```

#### `em` `&rest arguments` — macro

Write an HTML em element.  Arguments are as for `tag`, without the name.

*Example:* Inline text tags for emphasis and position.

```lisp
(with-canvas-to-string ()
  (p ()
    (em () "really") " " (strong () "must") " " (b () "bold") " " (i () "aside") " "
    (u () "misspelt") " " (small () "fine print") " " (mark () "found") " "
    "x" (sup () "2") " H" (sub () "2") "O"))
;; ⇒ "<p><em>really</em> <strong>must</strong> <b>bold</b> <i>aside</i> <u>misspelt</u> <small>fine print</small> <mark>found</mark> x<sup>2</sup> H<sub>2</sub>O</p>"
```

#### `strong` `&rest arguments` — macro

Write an HTML strong element.  Arguments are as for `tag`, without the name.

*Example:* Inline text tags for emphasis and position.

```lisp
(with-canvas-to-string ()
  (p ()
    (em () "really") " " (strong () "must") " " (b () "bold") " " (i () "aside") " "
    (u () "misspelt") " " (small () "fine print") " " (mark () "found") " "
    "x" (sup () "2") " H" (sub () "2") "O"))
;; ⇒ "<p><em>really</em> <strong>must</strong> <b>bold</b> <i>aside</i> <u>misspelt</u> <small>fine print</small> <mark>found</mark> x<sup>2</sup> H<sub>2</sub>O</p>"
```

#### `b` `&rest arguments` — macro

Write an HTML b element.  Arguments are as for `tag`, without the name.

*Example:* Inline text tags for emphasis and position.

```lisp
(with-canvas-to-string ()
  (p ()
    (em () "really") " " (strong () "must") " " (b () "bold") " " (i () "aside") " "
    (u () "misspelt") " " (small () "fine print") " " (mark () "found") " "
    "x" (sup () "2") " H" (sub () "2") "O"))
;; ⇒ "<p><em>really</em> <strong>must</strong> <b>bold</b> <i>aside</i> <u>misspelt</u> <small>fine print</small> <mark>found</mark> x<sup>2</sup> H<sub>2</sub>O</p>"
```

#### `i` `&rest arguments` — macro

Write an HTML i element.  Arguments are as for `tag`, without the name.

*Example:* Inline text tags for emphasis and position.

```lisp
(with-canvas-to-string ()
  (p ()
    (em () "really") " " (strong () "must") " " (b () "bold") " " (i () "aside") " "
    (u () "misspelt") " " (small () "fine print") " " (mark () "found") " "
    "x" (sup () "2") " H" (sub () "2") "O"))
;; ⇒ "<p><em>really</em> <strong>must</strong> <b>bold</b> <i>aside</i> <u>misspelt</u> <small>fine print</small> <mark>found</mark> x<sup>2</sup> H<sub>2</sub>O</p>"
```

#### `u` `&rest arguments` — macro

Write an HTML u element.  Arguments are as for `tag`, without the name.

*Example:* Inline text tags for emphasis and position.

```lisp
(with-canvas-to-string ()
  (p ()
    (em () "really") " " (strong () "must") " " (b () "bold") " " (i () "aside") " "
    (u () "misspelt") " " (small () "fine print") " " (mark () "found") " "
    "x" (sup () "2") " H" (sub () "2") "O"))
;; ⇒ "<p><em>really</em> <strong>must</strong> <b>bold</b> <i>aside</i> <u>misspelt</u> <small>fine print</small> <mark>found</mark> x<sup>2</sup> H<sub>2</sub>O</p>"
```

#### `small` `&rest arguments` — macro

Write an HTML small element.  Arguments are as for `tag`, without the name.

*Example:* Inline text tags for emphasis and position.

```lisp
(with-canvas-to-string ()
  (p ()
    (em () "really") " " (strong () "must") " " (b () "bold") " " (i () "aside") " "
    (u () "misspelt") " " (small () "fine print") " " (mark () "found") " "
    "x" (sup () "2") " H" (sub () "2") "O"))
;; ⇒ "<p><em>really</em> <strong>must</strong> <b>bold</b> <i>aside</i> <u>misspelt</u> <small>fine print</small> <mark>found</mark> x<sup>2</sup> H<sub>2</sub>O</p>"
```

#### `code` `&rest arguments` — macro

Write an HTML code element.  Arguments are as for `tag`, without the name.

*Example:* Tags for code and computer text.  The HTML var element is `var-tag`, as `var` is too useful a name to take from your code.

```lisp
(with-canvas-to-string ()
  (p () "Press " (kbd () "Ctrl-C") " to stop " (code () "(main)") "; it prints "
     (samp () "Bye") ". Let " (var-tag () "n") " be the port.")
  (pre () "(+ 1 2) ⇒ 3"))
;; ⇒ "<p>Press <kbd>Ctrl-C</kbd> to stop <code>(main)</code>; it prints <samp>Bye</samp>. Let <var>n</var> be the port.</p><pre>(+ 1 2) ⇒ 3</pre>"
```

#### `pre` `&rest arguments` — macro

Write an HTML pre element.  Arguments are as for `tag`, without the name.

*Example:* Tags for code and computer text.  The HTML var element is `var-tag`, as `var` is too useful a name to take from your code.

```lisp
(with-canvas-to-string ()
  (p () "Press " (kbd () "Ctrl-C") " to stop " (code () "(main)") "; it prints "
     (samp () "Bye") ". Let " (var-tag () "n") " be the port.")
  (pre () "(+ 1 2) ⇒ 3"))
;; ⇒ "<p>Press <kbd>Ctrl-C</kbd> to stop <code>(main)</code>; it prints <samp>Bye</samp>. Let <var>n</var> be the port.</p><pre>(+ 1 2) ⇒ 3</pre>"
```

#### `blockquote` `&rest arguments` — macro

Write an HTML blockquote element.  Arguments are as for `tag`, without the name.

*Example:* Quotations, citations, abbreviations and definitions.

```lisp
(with-canvas-to-string ()
  (blockquote (:cite "https://example.com/talk")
    (p () "Make it work, then make it fast."))
  (p () (cite () "The Talk") ": " (dfn () (abbr (:title "Server-sent events") "SSE"))
     " streams events to a page."))
;; ⇒ "<blockquote cite=\"https://example.com/talk\"><p>Make it work, then make it fast.</p></blockquote><p><cite>The Talk</cite>: <dfn><abbr title=\"Server-sent events\">SSE</abbr></dfn> streams events to a page.</p>"
```

#### `sup` `&rest arguments` — macro

Write an HTML sup element.  Arguments are as for `tag`, without the name.

*Example:* Inline text tags for emphasis and position.

```lisp
(with-canvas-to-string ()
  (p ()
    (em () "really") " " (strong () "must") " " (b () "bold") " " (i () "aside") " "
    (u () "misspelt") " " (small () "fine print") " " (mark () "found") " "
    "x" (sup () "2") " H" (sub () "2") "O"))
;; ⇒ "<p><em>really</em> <strong>must</strong> <b>bold</b> <i>aside</i> <u>misspelt</u> <small>fine print</small> <mark>found</mark> x<sup>2</sup> H<sub>2</sub>O</p>"
```

#### `sub` `&rest arguments` — macro

Write an HTML sub element.  Arguments are as for `tag`, without the name.

*Example:* Inline text tags for emphasis and position.

```lisp
(with-canvas-to-string ()
  (p ()
    (em () "really") " " (strong () "must") " " (b () "bold") " " (i () "aside") " "
    (u () "misspelt") " " (small () "fine print") " " (mark () "found") " "
    "x" (sup () "2") " H" (sub () "2") "O"))
;; ⇒ "<p><em>really</em> <strong>must</strong> <b>bold</b> <i>aside</i> <u>misspelt</u> <small>fine print</small> <mark>found</mark> x<sup>2</sup> H<sub>2</sub>O</p>"
```

#### `section` `&rest arguments` — macro

Write an HTML section element.  Arguments are as for `tag`, without the name.

*Example:* The document-structure tags.

```lisp
(with-canvas-to-string ()
  (header () (nav (:aria-label "Site") "Home"))
  (main ()
    (section (:id "news")
      (article () "First post")
      (aside () "Related")))
  (footer () (span () "2026")))
;; ⇒ "<header><nav aria-label=\"Site\">Home</nav></header><main><section id=\"news\"><article>First post</article><aside>Related</aside></section></main><footer><span>2026</span></footer>"
```

#### `article` `&rest arguments` — macro

Write an HTML article element.  Arguments are as for `tag`, without the name.

*Example:* The document-structure tags.

```lisp
(with-canvas-to-string ()
  (header () (nav (:aria-label "Site") "Home"))
  (main ()
    (section (:id "news")
      (article () "First post")
      (aside () "Related")))
  (footer () (span () "2026")))
;; ⇒ "<header><nav aria-label=\"Site\">Home</nav></header><main><section id=\"news\"><article>First post</article><aside>Related</aside></section></main><footer><span>2026</span></footer>"
```

#### `aside` `&rest arguments` — macro

Write an HTML aside element.  Arguments are as for `tag`, without the name.

*Example:* The document-structure tags.

```lisp
(with-canvas-to-string ()
  (header () (nav (:aria-label "Site") "Home"))
  (main ()
    (section (:id "news")
      (article () "First post")
      (aside () "Related")))
  (footer () (span () "2026")))
;; ⇒ "<header><nav aria-label=\"Site\">Home</nav></header><main><section id=\"news\"><article>First post</article><aside>Related</aside></section></main><footer><span>2026</span></footer>"
```

#### `nav` `&rest arguments` — macro

Write an HTML nav element.  Arguments are as for `tag`, without the name.

*Example:* The document-structure tags.

```lisp
(with-canvas-to-string ()
  (header () (nav (:aria-label "Site") "Home"))
  (main ()
    (section (:id "news")
      (article () "First post")
      (aside () "Related")))
  (footer () (span () "2026")))
;; ⇒ "<header><nav aria-label=\"Site\">Home</nav></header><main><section id=\"news\"><article>First post</article><aside>Related</aside></section></main><footer><span>2026</span></footer>"
```

#### `header` `&rest arguments` — macro

Write an HTML header element.  Arguments are as for `tag`, without the name.

*Example:* The document-structure tags.

```lisp
(with-canvas-to-string ()
  (header () (nav (:aria-label "Site") "Home"))
  (main ()
    (section (:id "news")
      (article () "First post")
      (aside () "Related")))
  (footer () (span () "2026")))
;; ⇒ "<header><nav aria-label=\"Site\">Home</nav></header><main><section id=\"news\"><article>First post</article><aside>Related</aside></section></main><footer><span>2026</span></footer>"
```

#### `footer` `&rest arguments` — macro

Write an HTML footer element.  Arguments are as for `tag`, without the name.

*Example:* The document-structure tags.

```lisp
(with-canvas-to-string ()
  (header () (nav (:aria-label "Site") "Home"))
  (main ()
    (section (:id "news")
      (article () "First post")
      (aside () "Related")))
  (footer () (span () "2026")))
;; ⇒ "<header><nav aria-label=\"Site\">Home</nav></header><main><section id=\"news\"><article>First post</article><aside>Related</aside></section></main><footer><span>2026</span></footer>"
```

#### `main` `&rest arguments` — macro

Write an HTML main element.  Arguments are as for `tag`, without the name.

*Example:* The document-structure tags.

```lisp
(with-canvas-to-string ()
  (header () (nav (:aria-label "Site") "Home"))
  (main ()
    (section (:id "news")
      (article () "First post")
      (aside () "Related")))
  (footer () (span () "2026")))
;; ⇒ "<header><nav aria-label=\"Site\">Home</nav></header><main><section id=\"news\"><article>First post</article><aside>Related</aside></section></main><footer><span>2026</span></footer>"
```

#### `figure` `&rest arguments` — macro

Write an HTML figure element.  Arguments are as for `tag`, without the name.

*Example:* Figures and images.  `img`, `br` and `hr` are void elements: they take attributes but no body, and have no closing tag.

```lisp
(with-canvas-to-string ()
  (figure ()
    (img (:src "/static/boat.png" :alt "A boat" :width 120))
    (figcaption () "Low tide" (br) "at noon"))
  (hr))
;; ⇒ "<figure><img src=\"/static/boat.png\" alt=\"A boat\" width=\"120\"><figcaption>Low tide<br>at noon</figcaption></figure><hr>"
```

#### `figcaption` `&rest arguments` — macro

Write an HTML figcaption element.  Arguments are as for `tag`, without the name.

*Example:* Figures and images.  `img`, `br` and `hr` are void elements: they take attributes but no body, and have no closing tag.

```lisp
(with-canvas-to-string ()
  (figure ()
    (img (:src "/static/boat.png" :alt "A boat" :width 120))
    (figcaption () "Low tide" (br) "at noon"))
  (hr))
;; ⇒ "<figure><img src=\"/static/boat.png\" alt=\"A boat\" width=\"120\"><figcaption>Low tide<br>at noon</figcaption></figure><hr>"
```

#### `fieldset` `&rest arguments` — macro

Write an HTML fieldset element.  Arguments are as for `tag`, without the name.

*Example:* Grouping and labelling form controls.  The controls themselves are brushes, such as `text-input`.

```lisp
(with-canvas-to-string ()
  (fieldset ()
    (legend () "Contact")
    (label (:for "email") "Email")
    (text-input (:id "email" :name "email"))))
;; ⇒ "<fieldset><legend>Contact</legend><label for=\"email\">Email</label><input type=\"text\" name=\"email\" id=\"email\"></fieldset>"
```

#### `legend` `&rest arguments` — macro

Write an HTML legend element.  Arguments are as for `tag`, without the name.

*Example:* Grouping and labelling form controls.  The controls themselves are brushes, such as `text-input`.

```lisp
(with-canvas-to-string ()
  (fieldset ()
    (legend () "Contact")
    (label (:for "email") "Email")
    (text-input (:id "email" :name "email"))))
;; ⇒ "<fieldset><legend>Contact</legend><label for=\"email\">Email</label><input type=\"text\" name=\"email\" id=\"email\"></fieldset>"
```

#### `label` `&rest arguments` — macro

Write an HTML label element.  Arguments are as for `tag`, without the name.

*Example:* Grouping and labelling form controls.  The controls themselves are brushes, such as `text-input`.

```lisp
(with-canvas-to-string ()
  (fieldset ()
    (legend () "Contact")
    (label (:for "email") "Email")
    (text-input (:id "email" :name "email"))))
;; ⇒ "<fieldset><legend>Contact</legend><label for=\"email\">Email</label><input type=\"text\" name=\"email\" id=\"email\"></fieldset>"
```

#### `abbr` `&rest arguments` — macro

Write an HTML abbr element.  Arguments are as for `tag`, without the name.

*Example:* Quotations, citations, abbreviations and definitions.

```lisp
(with-canvas-to-string ()
  (blockquote (:cite "https://example.com/talk")
    (p () "Make it work, then make it fast."))
  (p () (cite () "The Talk") ": " (dfn () (abbr (:title "Server-sent events") "SSE"))
     " streams events to a page."))
;; ⇒ "<blockquote cite=\"https://example.com/talk\"><p>Make it work, then make it fast.</p></blockquote><p><cite>The Talk</cite>: <dfn><abbr title=\"Server-sent events\">SSE</abbr></dfn> streams events to a page.</p>"
```

#### `cite` `&rest arguments` — macro

Write an HTML cite element.  Arguments are as for `tag`, without the name.

*Example:* Quotations, citations, abbreviations and definitions.

```lisp
(with-canvas-to-string ()
  (blockquote (:cite "https://example.com/talk")
    (p () "Make it work, then make it fast."))
  (p () (cite () "The Talk") ": " (dfn () (abbr (:title "Server-sent events") "SSE"))
     " streams events to a page."))
;; ⇒ "<blockquote cite=\"https://example.com/talk\"><p>Make it work, then make it fast.</p></blockquote><p><cite>The Talk</cite>: <dfn><abbr title=\"Server-sent events\">SSE</abbr></dfn> streams events to a page.</p>"
```

#### `mark` `&rest arguments` — macro

Write an HTML mark element.  Arguments are as for `tag`, without the name.

*Example:* Inline text tags for emphasis and position.

```lisp
(with-canvas-to-string ()
  (p ()
    (em () "really") " " (strong () "must") " " (b () "bold") " " (i () "aside") " "
    (u () "misspelt") " " (small () "fine print") " " (mark () "found") " "
    "x" (sup () "2") " H" (sub () "2") "O"))
;; ⇒ "<p><em>really</em> <strong>must</strong> <b>bold</b> <i>aside</i> <u>misspelt</u> <small>fine print</small> <mark>found</mark> x<sup>2</sup> H<sub>2</sub>O</p>"
```

#### `dfn` `&rest arguments` — macro

Write an HTML dfn element.  Arguments are as for `tag`, without the name.

*Example:* Quotations, citations, abbreviations and definitions.

```lisp
(with-canvas-to-string ()
  (blockquote (:cite "https://example.com/talk")
    (p () "Make it work, then make it fast."))
  (p () (cite () "The Talk") ": " (dfn () (abbr (:title "Server-sent events") "SSE"))
     " streams events to a page."))
;; ⇒ "<blockquote cite=\"https://example.com/talk\"><p>Make it work, then make it fast.</p></blockquote><p><cite>The Talk</cite>: <dfn><abbr title=\"Server-sent events\">SSE</abbr></dfn> streams events to a page.</p>"
```

#### `kbd` `&rest arguments` — macro

Write an HTML kbd element.  Arguments are as for `tag`, without the name.

*Example:* Tags for code and computer text.  The HTML var element is `var-tag`, as `var` is too useful a name to take from your code.

```lisp
(with-canvas-to-string ()
  (p () "Press " (kbd () "Ctrl-C") " to stop " (code () "(main)") "; it prints "
     (samp () "Bye") ". Let " (var-tag () "n") " be the port.")
  (pre () "(+ 1 2) ⇒ 3"))
;; ⇒ "<p>Press <kbd>Ctrl-C</kbd> to stop <code>(main)</code>; it prints <samp>Bye</samp>. Let <var>n</var> be the port.</p><pre>(+ 1 2) ⇒ 3</pre>"
```

#### `samp` `&rest arguments` — macro

Write an HTML samp element.  Arguments are as for `tag`, without the name.

*Example:* Tags for code and computer text.  The HTML var element is `var-tag`, as `var` is too useful a name to take from your code.

```lisp
(with-canvas-to-string ()
  (p () "Press " (kbd () "Ctrl-C") " to stop " (code () "(main)") "; it prints "
     (samp () "Bye") ". Let " (var-tag () "n") " be the port.")
  (pre () "(+ 1 2) ⇒ 3"))
;; ⇒ "<p>Press <kbd>Ctrl-C</kbd> to stop <code>(main)</code>; it prints <samp>Bye</samp>. Let <var>n</var> be the port.</p><pre>(+ 1 2) ⇒ 3</pre>"
```

#### `var-tag` `&rest arguments` — macro

Write an HTML var element.  Arguments are as for `tag`, without the name.

*Example:* Tags for code and computer text.  The HTML var element is `var-tag`, as `var` is too useful a name to take from your code.

```lisp
(with-canvas-to-string ()
  (p () "Press " (kbd () "Ctrl-C") " to stop " (code () "(main)") "; it prints "
     (samp () "Bye") ". Let " (var-tag () "n") " be the port.")
  (pre () "(+ 1 2) ⇒ 3"))
;; ⇒ "<p>Press <kbd>Ctrl-C</kbd> to stop <code>(main)</code>; it prints <samp>Bye</samp>. Let <var>n</var> be the port.</p><pre>(+ 1 2) ⇒ 3</pre>"
```

#### `details` `&rest arguments` — macro

Write an HTML details element.  Arguments are as for `tag`, without the name.

*Example:* A disclosure box the browser opens and closes by itself; `:open` T starts it open.

```lisp
(with-canvas-to-string ()
  (details (:open t)
    (summary () "More")
    (p () "Hidden until opened.")))
;; ⇒ "<details open><summary>More</summary><p>Hidden until opened.</p></details>"
```

#### `summary` `&rest arguments` — macro

Write an HTML summary element.  Arguments are as for `tag`, without the name.

*Example:* A disclosure box the browser opens and closes by itself; `:open` T starts it open.

```lisp
(with-canvas-to-string ()
  (details (:open t)
    (summary () "More")
    (p () "Hidden until opened.")))
;; ⇒ "<details open><summary>More</summary><p>Hidden until opened.</p></details>"
```

#### `img` `&rest arguments` — macro

Write an HTML img element.  Arguments are as for `tag`, without the name.

*Example:* Figures and images.  `img`, `br` and `hr` are void elements: they take attributes but no body, and have no closing tag.

```lisp
(with-canvas-to-string ()
  (figure ()
    (img (:src "/static/boat.png" :alt "A boat" :width 120))
    (figcaption () "Low tide" (br) "at noon"))
  (hr))
;; ⇒ "<figure><img src=\"/static/boat.png\" alt=\"A boat\" width=\"120\"><figcaption>Low tide<br>at noon</figcaption></figure><hr>"
```

#### `br` `&rest arguments` — macro

Write an HTML br element.  Arguments are as for `tag`, without the name.

*Example:* Figures and images.  `img`, `br` and `hr` are void elements: they take attributes but no body, and have no closing tag.

```lisp
(with-canvas-to-string ()
  (figure ()
    (img (:src "/static/boat.png" :alt "A boat" :width 120))
    (figcaption () "Low tide" (br) "at noon"))
  (hr))
;; ⇒ "<figure><img src=\"/static/boat.png\" alt=\"A boat\" width=\"120\"><figcaption>Low tide<br>at noon</figcaption></figure><hr>"
```

#### `hr` `&rest arguments` — macro

Write an HTML hr element.  Arguments are as for `tag`, without the name.

*Example:* Figures and images.  `img`, `br` and `hr` are void elements: they take attributes but no body, and have no closing tag.

```lisp
(with-canvas-to-string ()
  (figure ()
    (img (:src "/static/boat.png" :alt "A boat" :width 120))
    (figcaption () "Low tide" (br) "at noon"))
  (hr))
;; ⇒ "<figure><img src=\"/static/boat.png\" alt=\"A boat\" width=\"120\"><figcaption>Low tide<br>at noon</figcaption></figure><hr>"
```

#### `tag` `name &rest arguments` — macro

Write an element whose `name` (a string) is computed.  As for every tag,
the first of `arguments` may be a plist of attributes, whose values are
evaluated: `nil` leaves an attribute out, T writes it bare, a `:class` list is
joined with spaces, and anything else is printed and escaped.  The list may
be omitted when the body does not start with a list beginning with a
keyword.  In the body, literal strings (and `translate` forms) are written as
escaped text; other forms are evaluated for their effect, so a computed
value is written with `text`.

*Example:* The first argument of a tag is a plist of attributes, whose values are evaluated.  A `nil` value leaves the attribute out, T writes it bare (a boolean attribute), and a `:class` list is joined with spaces, its NILs dropped.  Values are escaped.

```lisp
(let ((selected t) (disabled nil))
  (with-canvas-to-string ()
    (div (:id "row-1" :class (list "row" (and selected "selected") nil)
          :hidden disabled :data-note "say \"hi\"")
      (span (:title "Ready" :aria-busy t) "Go"))))
;; ⇒ "<div id=\"row-1\" class=\"row selected\" data-note=\"say &quot;hi&quot;\"><span title=\"Ready\" aria-busy>Go</span></div>"
```

*Example:* `tag` writes an element whose name is computed, for elements without a macro of their own.

```lisp
(defun stamp (element when label)
  (tag element (:datetime when) (text label)))
(with-canvas-to-string ()
  (stamp "time" "2026-10-15" "today"))
;; ⇒ "<time datetime=\"2026-10-15\">today</time>"
```

### Brushes with callbacks

#### `anchor` `&rest arguments` — macro

A link.  `:callback` is a thunk run when it is followed; `:href` a plain URL.
With neither, an AJAX `:on-click` gets the href "#".  `:label` becomes the
aria-label; other attributes are written as given.

*Example:* A link whose `:callback`, a function of no arguments, runs when it is followed; the page is then rendered again.

```lisp
(defclass counter (component)
  ((count :initform 0 :accessor count-of)))
(defmethod render ((self counter))
  (p () (text (count-of self)))
  (anchor (:callback (lambda () (incf (count-of self)))) "Add one"))
(with-fresh-applications (("/counter" 'counter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/counter")
    (click b "Add one")
    (click b "Add one")
    (body-text b)))
;; ⇒ "2 Add one"
```

*Example:* Without a callback, `:href` makes a plain link, and other attributes are written as given.  `:label` becomes aria-label.

```lisp
(with-canvas-to-string ()
  (anchor (:href "https://sbcl.org/" :rel "external" :label "SBCL's site") "SBCL"))
;; ⇒ "<a href=\"https://sbcl.org/\" rel=\"external\" aria-label=\"SBCL&#39;s site\">SBCL</a>"
```

#### `form` `&rest arguments` — macro

A form posting back to the session.  Its fields' callbacks run before
the action of the button that submitted it.  `:default-action` is a thunk run
when the form is submitted without a button; `:multipart` T allows `file-input`.

*Example:* A form posts back to the session.  Each field's `:callback` receives what was typed; then the `:callback` of the button pressed runs.  Fields are found in tests by their `:id`.

```lisp
(defclass greeter (component)
  ((name :initform "" :accessor name-of)
   (greeting :initform nil :accessor greeting-of)))
(defmethod render ((self greeter))
  (form ()
    (label (:for "name") "Name")
    (text-input (:id "name" :value (name-of self)
                 :callback (lambda (value) (setf (name-of self) value))))
    (submit-button (:callback (lambda () (setf (greeting-of self) (format nil "Hello, ~A!" (name-of self)))))
      "Greet"))
  (when (greeting-of self)
    (p () (text (greeting-of self)))))
(with-fresh-applications (("/greet" 'greeter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greet")
    (fill-in b "name" "Ada")
    (press b "Greet")
    (body-text b)))
;; ⇒ "Name Greet Hello, Ada!"
```

*Example:* `:default-action` runs when the form is submitted without a button, as when Enter is pressed in a field of a form whose buttons all have callbacks.  The fake browser's `press` always names a button, so the test posts the fields itself.

```lisp
(defclass search-box (component)
  ((query :initform "" :accessor query-of)
   (results :initform nil :accessor results-of)))
(defmethod render ((self search-box))
  (form (:role "search" :default-action (lambda () (setf (results-of self) (format nil "Results for ~A" (query-of self)))))
    (text-input (:id "q" :callback (lambda (value) (setf (query-of self) value))))
    (submit-button (:callback (lambda () (setf (results-of self) "Feeling lucky"))) "Lucky"))
  (p () (text (results-of self))))
(with-fresh-applications (("/search" 'search-box :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/search")))
    (fill-in b "q" "lisp")
    (visit b (form-action b) :method :post :body (encode-fields (browser-fields b)))
    (body-text b)))
;; ⇒ "Lucky Results for lisp"
```

#### `text-input` `&optional attributes` — macro

A text field showing `:value`.  `:callback` receives the submitted string;
without one, the field is named `:name`.

*Example:* A form posts back to the session.  Each field's `:callback` receives what was typed; then the `:callback` of the button pressed runs.  Fields are found in tests by their `:id`.

```lisp
(defclass greeter (component)
  ((name :initform "" :accessor name-of)
   (greeting :initform nil :accessor greeting-of)))
(defmethod render ((self greeter))
  (form ()
    (label (:for "name") "Name")
    (text-input (:id "name" :value (name-of self)
                 :callback (lambda (value) (setf (name-of self) value))))
    (submit-button (:callback (lambda () (setf (greeting-of self) (format nil "Hello, ~A!" (name-of self)))))
      "Greet"))
  (when (greeting-of self)
    (p () (text (greeting-of self)))))
(with-fresh-applications (("/greet" 'greeter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greet")
    (fill-in b "name" "Ada")
    (press b "Greet")
    (body-text b)))
;; ⇒ "Name Greet Hello, Ada!"
```

#### `password-input` `&optional attributes` — macro

A password field, empty unless given a `:value`.  `:callback` receives the
submitted string.

*Example:* A password field never shows a `:value` unless you give it one.  A cancel button runs its callback and nothing else: what was typed is not applied.

```lisp
(defclass sign-in (component)
  ((password :initform nil :accessor password-of)
   (outcome :initform "" :accessor outcome-of)))
(defmethod render ((self sign-in))
  (form ()
    (password-input (:id "password" :autocomplete "current-password"
                     :callback (lambda (value) (setf (password-of self) value))))
    (submit-button (:callback (lambda () (setf (outcome-of self) (format nil "Got ~D characters." (length (password-of self))))))
      "Sign in")
    (cancel-button (:callback (lambda () (setf (outcome-of self) (format nil "Cancelled; password ~S." (password-of self)))))
      "Cancel"))
  (p () (text (outcome-of self))))
(with-fresh-applications (("/sign-in" 'sign-in :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/sign-in")
    (fill-in b "password" "hunter2")
    (press b "Cancel")
    (let ((cancelled (body-text b)))
      (fill-in b "password" "hunter2")
      (press b "Sign in")
      (list cancelled (body-text b)))))
;; ⇒ ("Sign in Cancel Cancelled; password NIL." "Sign in Cancel Got 7 characters.")
```

#### `number-input` `&optional attributes` — macro

An integer field.  `:callback` receives an integer, or `nil` when the
submission does not parse.

*Example:* The callback receives an integer, or `nil` when what was submitted is not one.

```lisp
(defclass quantity (component)
  ((amount :initform 1 :accessor amount-of)))
(defmethod render ((self quantity))
  (form ()
    (number-input (:id "amount" :min 1 :value (or (amount-of self) "")
                   :callback (lambda (n) (setf (amount-of self) n))))
    (submit-button () "Update"))
  (p () (text (if (amount-of self) (format nil "~D in the basket" (amount-of self)) "Not a number"))))
(with-fresh-applications (("/quantity" 'quantity :mode :deployment))
  (let ((b (make-instance 'browser)) (seen '()))
    (visit b "/quantity")
    (dolist (typed '("3" "three"))
      (fill-in b "amount" typed)
      (press b "Update")
      (push (body-text b) seen))
    (reverse seen)))
;; ⇒ ("Update 3 in the basket" "Update Not a number")
```

#### `hidden-input` `&optional attributes` — macro

A hidden field.  `:callback` receives its `:value` when the form is submitted.

*Example:* A hidden field sends back its `:value`, here the version of the record the form was rendered from.

```lisp
(defclass versioned-note (component)
  ((version :initform 7 :accessor version-of)
   (submitted :initform nil :accessor submitted-of)))
(defmethod render ((self versioned-note))
  (form ()
    (hidden-input (:value (version-of self)
                   :callback (lambda (value) (setf (submitted-of self) value))))
    (submit-button () "Save"))
  (p () "Submitted version: " (text (submitted-of self))))
(with-fresh-applications (("/note" 'versioned-note :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/note")
    (press b "Save")
    (body-text b)))
;; ⇒ "Save Submitted version: 7"
```

#### `text-area` `&optional attributes` — macro

A multi-line text field showing `:value`.  `:callback` receives the submitted string.

*Example:* A multi-line field showing `:value`, escaped, and passing the submitted text to `:callback`.

```lisp
(defclass notes (component)
  ((body :initform "Bring <cake>" :accessor body-of)))
(defmethod render ((self notes))
  (form ()
    (text-area (:id "body" :rows 4 :value (body-of self)
                :callback (lambda (value) (setf (body-of self) value))))
    (submit-button () "Save"))
  (p () (text (length (body-of self))) " characters"))
(with-fresh-applications (("/notes" 'notes :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/notes")
    (let ((field (not (null (search "&lt;cake&gt;</textarea>" (browser-html b))))))
      (fill-in b "body" (format nil "Bring cake~%and tea"))
      (press b "Save")
      (list field (body-text b)))))
;; ⇒ (T "Bring cake and tea Save 18 characters")
```

#### `checkbox` `&optional attributes` — macro

A checkbox.  `:value` is its state; `:callback` receives T or `nil`.

*Example:* `:value` is whether the box is checked; `:callback` receives T or `nil`.  An unchecked box still reports `nil`, as the brush writes a hidden twin.  In tests, `set-checkbox` picks boxes by their position on the page.

```lisp
(defclass preferences (component)
  ((newsletter :initform nil :accessor newsletter-p)
   (digest :initform t :accessor digest-p)))
(defmethod render ((self preferences))
  (form ()
    (label () (checkbox (:value (newsletter-p self) :callback (lambda (on) (setf (newsletter-p self) on))))
      "Newsletter")
    (label () (checkbox (:value (digest-p self) :callback (lambda (on) (setf (digest-p self) on))))
      "Weekly digest")
    (submit-button () "Save"))
  (p () (text (list (newsletter-p self) (digest-p self)))))
(with-fresh-applications (("/prefs" 'preferences :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/prefs")
    (set-checkbox b 0 t)
    (set-checkbox b 1 nil)
    (press b "Save")
    (body-text b)))
;; ⇒ "Newsletter Weekly digest Save (T NIL)"
```

#### `select-list` `&optional attributes` — macro

A drop-down of `:items` shown through `:labels` (a function, default `princ`).
`:callback` receives the chosen item, or `nil` when the submission names none;
`:selected` is the current one, compared with `:test` (default `eql`).

*Example:* A drop-down of `:items`, which may be any objects: `:labels` turns one into its text, `:selected` is the one shown chosen (compared with `:test`, default `eql`), and `:callback` receives the item chosen.

```lisp
(defclass shipping (component)
  ((carrier :initform :post :accessor carrier-of)))
(defmethod render ((self shipping))
  (form ()
    (select-list (:id "method" :items '(:post :courier :collect)
                  :labels (lambda (item) (string-capitalize item))
                  :selected (carrier-of self)
                  :callback (lambda (item) (setf (carrier-of self) item))))
    (submit-button () "Choose"))
  (p () "Shipping by " (text (string-downcase (carrier-of self)))))
(with-fresh-applications (("/ship" 'shipping :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/ship")
    (select-option b "method" "Courier")
    (press b "Choose")
    (body-text b)))
;; ⇒ "Post Courier Collect Choose Shipping by courier"
```

#### `radio-group` `&optional attributes` — macro

Radio buttons, one per item of `:items`; otherwise like `select-list`.

*Example:* One radio button per item, inside a span of class lt-radio-group; it takes the same keywords as `select-list`.  Outside a request, as here, callback names are numbered from 1.

```lisp
(with-canvas-to-string ()
  (radio-group (:items '(1 2 3) :selected 2 :labels (lambda (n) (format nil "~D star~:P" n))
                :callback (lambda (n) (print n)))))
;; ⇒ "<span class=\"lt-radio-group\"><label><input type=\"radio\" name=\"1\" value=\"0\">1 star</label><label><input type=\"radio\" name=\"1\" value=\"1\" checked>2 stars</label><label><input type=\"radio\" name=\"1\" value=\"2\">3 stars</label></span>"
```

*Example:* The submitted choice reaches `:callback` as the item itself.  The fake browser's choose-radio clicks a button by its label.

```lisp
(defclass size-picker (component)
  ((size :initform :small :accessor size-of)))
(defmethod render ((self size-picker))
  (form ()
    (radio-group (:id "size" :items '(:small :medium :large) :selected (size-of self)
                  :labels #'string-downcase
                  :callback (lambda (size) (setf (size-of self) size))))
    (submit-button () "Pick"))
  (p () "Size: " (text (size-of self))))
(with-fresh-applications (("/size" 'size-picker :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/size")))
    (choose-radio b "large")
    (press b "Pick")
    (body-text b)))
;; ⇒ "small medium large Pick Size: LARGE"
```

#### `submit-button` `&rest arguments` — macro

A button submitting its form, then running the thunk `:callback`.

*Example:* A form posts back to the session.  Each field's `:callback` receives what was typed; then the `:callback` of the button pressed runs.  Fields are found in tests by their `:id`.

```lisp
(defclass greeter (component)
  ((name :initform "" :accessor name-of)
   (greeting :initform nil :accessor greeting-of)))
(defmethod render ((self greeter))
  (form ()
    (label (:for "name") "Name")
    (text-input (:id "name" :value (name-of self)
                 :callback (lambda (value) (setf (name-of self) value))))
    (submit-button (:callback (lambda () (setf (greeting-of self) (format nil "Hello, ~A!" (name-of self)))))
      "Greet"))
  (when (greeting-of self)
    (p () (text (greeting-of self)))))
(with-fresh-applications (("/greet" 'greeter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greet")
    (fill-in b "name" "Ada")
    (press b "Greet")
    (body-text b)))
;; ⇒ "Name Greet Hello, Ada!"
```

#### `cancel-button` `&rest arguments` — macro

A button that runs the thunk `:callback` and nothing else: the form's
fields are not applied.

*Example:* A password field never shows a `:value` unless you give it one.  A cancel button runs its callback and nothing else: what was typed is not applied.

```lisp
(defclass sign-in (component)
  ((password :initform nil :accessor password-of)
   (outcome :initform "" :accessor outcome-of)))
(defmethod render ((self sign-in))
  (form ()
    (password-input (:id "password" :autocomplete "current-password"
                     :callback (lambda (value) (setf (password-of self) value))))
    (submit-button (:callback (lambda () (setf (outcome-of self) (format nil "Got ~D characters." (length (password-of self))))))
      "Sign in")
    (cancel-button (:callback (lambda () (setf (outcome-of self) (format nil "Cancelled; password ~S." (password-of self)))))
      "Cancel"))
  (p () (text (outcome-of self))))
(with-fresh-applications (("/sign-in" 'sign-in :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/sign-in")
    (fill-in b "password" "hunter2")
    (press b "Cancel")
    (let ((cancelled (body-text b)))
      (fill-in b "password" "hunter2")
      (press b "Sign in")
      (list cancelled (body-text b)))))
;; ⇒ ("Sign in Cancel Cancelled; password NIL." "Sign in Cancel Got 7 characters.")
```

#### `button` `&rest arguments` — macro

A button that submits nothing; give it an AJAX `:on-click`.

*Example:* A button that submits nothing; it is for an AJAX `:on-click`, which runs its callback in the background and re-renders the components to `:update`.  Those components must be `updatable`.

```lisp
(defclass likes (updatable component)
  ((count :initform 0 :accessor count-of)))
(defmethod render ((self likes))
  (span () (text (count-of self)) " likes")
  (button (:class "like" :on-click (ajax :callback (lambda () (incf (count-of self))) :update self))
    "Like"))
(with-fresh-applications (("/likes" 'likes :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/likes"))
         (spec (first (ajax-specs b "on-click"))))
    (ajax-request b (first spec) (rest spec))
    (ajax-request b (first spec) (rest spec))
    (visit b (browser-url b))             ; reload: the change stayed
    (body-text b)))
;; ⇒ "2 likes Like"
```

#### `file-input` `&optional attributes` — macro

A file chooser.  `:callback` receives an `uploaded-file`, and is not called
when no file was chosen.  The enclosing `form` needs `:multipart` T.

*Example:* A file chooser needs a form with `:multipart` T.  Its `:callback` receives an `uploaded-file`, whose bytes are an octet vector, and is not called when no file was chosen.

```lisp
(defclass uploader (component)
  ((report :initform "Nothing yet" :accessor report-of)))
(defmethod render ((self uploader))
  (form (:multipart t)
    (file-input (:id "file" :accept "text/*"
                 :callback (lambda (file)
                             (setf (report-of self)
                                   (format nil "~A (~A): ~D bytes, starting ~S"
                                           (file-name file) (file-content-type file)
                                           (length (file-contents file))
                                           (code-char (aref (file-contents file) 0)))))))
    (submit-button () "Upload"))
  (p () (text (report-of self))))
(with-fresh-applications (("/upload" 'uploader :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/upload")))
    (attach-file b "file" "notes.txt" "text/plain" "Hello, world")
    (press b "Upload")
    (body-text b)))
;; ⇒ "Upload notes.txt (text/plain): 12 bytes, starting #\\H"
```

#### `uploaded-file` — class

A file submitted through `file-input`.

*Example:* A file chooser needs a form with `:multipart` T.  Its `:callback` receives an `uploaded-file`, whose bytes are an octet vector, and is not called when no file was chosen.

```lisp
(defclass uploader (component)
  ((report :initform "Nothing yet" :accessor report-of)))
(defmethod render ((self uploader))
  (form (:multipart t)
    (file-input (:id "file" :accept "text/*"
                 :callback (lambda (file)
                             (setf (report-of self)
                                   (format nil "~A (~A): ~D bytes, starting ~S"
                                           (file-name file) (file-content-type file)
                                           (length (file-contents file))
                                           (code-char (aref (file-contents file) 0)))))))
    (submit-button () "Upload"))
  (p () (text (report-of self))))
(with-fresh-applications (("/upload" 'uploader :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/upload")))
    (attach-file b "file" "notes.txt" "text/plain" "Hello, world")
    (press b "Upload")
    (body-text b)))
;; ⇒ "Upload notes.txt (text/plain): 12 bytes, starting #\\H"
```

#### `file-name` `object` — generic function

Reads the filename of an uploaded-file.  The name the browser gave, without directories.

*Example:* A file chooser needs a form with `:multipart` T.  Its `:callback` receives an `uploaded-file`, whose bytes are an octet vector, and is not called when no file was chosen.

```lisp
(defclass uploader (component)
  ((report :initform "Nothing yet" :accessor report-of)))
(defmethod render ((self uploader))
  (form (:multipart t)
    (file-input (:id "file" :accept "text/*"
                 :callback (lambda (file)
                             (setf (report-of self)
                                   (format nil "~A (~A): ~D bytes, starting ~S"
                                           (file-name file) (file-content-type file)
                                           (length (file-contents file))
                                           (code-char (aref (file-contents file) 0)))))))
    (submit-button () "Upload"))
  (p () (text (report-of self))))
(with-fresh-applications (("/upload" 'uploader :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/upload")))
    (attach-file b "file" "notes.txt" "text/plain" "Hello, world")
    (press b "Upload")
    (body-text b)))
;; ⇒ "Upload notes.txt (text/plain): 12 bytes, starting #\\H"
```

#### `file-content-type` `object` — generic function

Reads the content-type of an uploaded-file.  The MIME type the browser gave.

*Example:* A file chooser needs a form with `:multipart` T.  Its `:callback` receives an `uploaded-file`, whose bytes are an octet vector, and is not called when no file was chosen.

```lisp
(defclass uploader (component)
  ((report :initform "Nothing yet" :accessor report-of)))
(defmethod render ((self uploader))
  (form (:multipart t)
    (file-input (:id "file" :accept "text/*"
                 :callback (lambda (file)
                             (setf (report-of self)
                                   (format nil "~A (~A): ~D bytes, starting ~S"
                                           (file-name file) (file-content-type file)
                                           (length (file-contents file))
                                           (code-char (aref (file-contents file) 0)))))))
    (submit-button () "Upload"))
  (p () (text (report-of self))))
(with-fresh-applications (("/upload" 'uploader :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/upload")))
    (attach-file b "file" "notes.txt" "text/plain" "Hello, world")
    (press b "Upload")
    (body-text b)))
;; ⇒ "Upload notes.txt (text/plain): 12 bytes, starting #\\H"
```

#### `file-contents` `object` — generic function

Reads the contents of an uploaded-file.  The file's bytes, an (`unsigned-byte` 8) vector.

*Example:* A file chooser needs a form with `:multipart` T.  Its `:callback` receives an `uploaded-file`, whose bytes are an octet vector, and is not called when no file was chosen.

```lisp
(defclass uploader (component)
  ((report :initform "Nothing yet" :accessor report-of)))
(defmethod render ((self uploader))
  (form (:multipart t)
    (file-input (:id "file" :accept "text/*"
                 :callback (lambda (file)
                             (setf (report-of self)
                                   (format nil "~A (~A): ~D bytes, starting ~S"
                                           (file-name file) (file-content-type file)
                                           (length (file-contents file))
                                           (code-char (aref (file-contents file) 0)))))))
    (submit-button () "Upload"))
  (p () (text (report-of self))))
(with-fresh-applications (("/upload" 'uploader :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/upload")))
    (attach-file b "file" "notes.txt" "text/plain" "Hello, world")
    (press b "Upload")
    (body-text b)))
;; ⇒ "Upload notes.txt (text/plain): 12 bytes, starting #\\H"
```

## Package `littoral.test`

Test Littoral applications in-process with a fake browser.

### A browser and its state

#### `browser` — class

A fake browser driving a Lack application in-process.  `:app`
is the application (by default every registered one); `:headers` are sent with
every request.

*Example:* A browser calls the application in-process, with no server.  `visit` follows redirects and returns the browser; the URL it ends on carries the session and page keys.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello))
  (h1 () "Hello"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/hello")))
    (list (browser-status b)
          (not (null (search "/hello?_s=" (browser-url b))))
          (browser-status (visit b "/nowhere")))))
;; ⇒ (200 T 404)
```

#### `browser-app` `object` — generic function

Reads the app of a browser.  The Lack application requests go to; by default `make-lack-app`'s,
which serves every registered application.

*Example:* By default a browser drives every registered application, through `make-lack-app`.  `:app` gives it any Lack application instead, such as one wrapped in middleware.

```lisp
(let ((b (make-instance 'browser
                        :app (lambda (env)
                               (list 200 '(:content-type "text/plain")
                                     (list (format nil "You asked for ~A" (getf env :path-info))))))))
  (visit b "/ping")
  (browser-html b))
;; ⇒ "You asked for /ping"
```

#### `browser-url` `object` — generic function

Reads the url of a browser.  The current page's URL, after redirects, or `nil` before the first visit.

*Example:* A browser calls the application in-process, with no server.  `visit` follows redirects and returns the browser; the URL it ends on carries the session and page keys.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello))
  (h1 () "Hello"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/hello")))
    (list (browser-status b)
          (not (null (search "/hello?_s=" (browser-url b))))
          (browser-status (visit b "/nowhere")))))
;; ⇒ (200 T 404)
```

#### `browser-status` `object` — generic function

Reads the status of a browser.  The current page's HTTP status, or `nil` before the first visit.

*Example:* A browser calls the application in-process, with no server.  `visit` follows redirects and returns the browser; the URL it ends on carries the session and page keys.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello))
  (h1 () "Hello"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/hello")))
    (list (browser-status b)
          (not (null (search "/hello?_s=" (browser-url b))))
          (browser-status (visit b "/nowhere")))))
;; ⇒ (200 T 404)
```

#### `browser-html` `object` — generic function

Reads the html of a browser.  The current page's body, as served.

*Example:* `browser-html` is the page as served; `page-text` is all its text, the title in the head included; `has-text-p` searches that text.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello))
  (h1 () "Hello & welcome"))
(with-fresh-applications (("/hello" 'hello :mode :deployment :title "Greeter"))
  (let ((b (visit (make-instance 'browser) "/hello")))
    (list (not (null (search "<h1>Hello &amp; welcome</h1>" (browser-html b))))
          (not (null (has-text-p b "Hello & welcome")))
          (not (null (search "<title>Greeter</title>" (browser-html b))))
          (not (null (has-text-p b "Greeter"))))))
;; ⇒ (T T T T)
```

#### `browser-cookies` `object` — generic function

Reads the cookies of a browser.  Alist of cookie name → value, sent with every request.

*Example:* The cookies the browser keeps, an alist of name and value, sent with each request.  A cookie set with `max-age` 0 is dropped.

```lisp
(defclass theme-picker (component) ())
(defmethod render ((self theme-picker))
  (anchor (:callback (lambda () (set-cookie "theme" "dark" :max-age 3600))) "Dark")
  (anchor (:callback (lambda () (set-cookie "theme" "" :max-age 0))) "Default"))
(with-fresh-applications (("/theme" 'theme-picker :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/theme")))
    (click b "Dark")
    (let ((chosen (assoc "theme" (browser-cookies b) :test #'string=)))
      (click b "Default")
      (list chosen (assoc "theme" (browser-cookies b) :test #'string=)))))
;; ⇒ (("theme" . "dark") NIL)
```

#### `browser-headers` `object` — generic function

Reads the headers of a browser.  Alist of header name → value sent with every request,
such as ("accept-language" . "fr").

*Example:* `:headers` are sent with every request, here to ask for French; the application offers it with `:languages`.

```lisp
(defclass trash (component) ())
(defmethod render ((self trash))
  (submit-button () (translate "Remove")))
(with-fresh-applications (("/trash" 'trash :mode :deployment :languages '("fr")))
  (let ((b (make-instance 'browser :headers '(("accept-language" . "fr-CA,fr;q=0.9")))))
    (visit b "/trash")
    (body-text b)))
;; ⇒ "Supprimer"
```

#### `browser-fields` `object` — generic function

Reads the fields of a browser.  Alist of field name → value that `press` submits: the current
page's fields as served, changed by `fill-in`, `set-checkbox` and `select-option`.

*Example:* A field's name is its callback's id, which changes from page to page, so tests find fields by `dom` id.  `browser-fields` holds what the next `press` submits: the page's own values, then what was typed.

```lisp
(defclass profile (component)
  ((city :initform "Lyon" :accessor city-of)))
(defmethod render ((self profile))
  (form ()
    (text-input (:id "city" :value (city-of self) :callback (lambda (v) (setf (city-of self) v))))
    (submit-button () "Save")))
(with-fresh-applications (("/profile" 'profile :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/profile"))
         (name (element-name b "city")))
    (flet ((city () (rest (assoc name (browser-fields b) :test #'string=))))
      (let ((before (city)))
        (fill-in b "city" "Nantes")
        (list before (city))))))
;; ⇒ ("Lyon" "Nantes")
```

#### `browser-files` `object` — generic function

Reads the files of a browser.  Alist of field name → (`filename` `content-type` `octets`).

*Example:* Files chosen with `attach-file` wait in `browser-files`, as (`filename` `content-type` `octets`) under the field's name, until the next `press` sends them.

```lisp
(defclass avatar (component) ())
(defmethod render ((self avatar))
  (form (:multipart t)
    (file-input (:id "picture" :callback (lambda (file) (declare (ignore file)))))
    (submit-button () "Upload")))
(with-fresh-applications (("/avatar" 'avatar :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/avatar")))
    (attach-file b "picture" "me.png" "image/png" #(137 80 78 71))
    (let ((waiting (rest (first (browser-files b)))))
      (press b "Upload")
      (list (subseq waiting 0 2) (length (third waiting)) (browser-files b)))))
;; ⇒ (("me.png" "image/png") 4 NIL)
```

### Requests

#### `visit` `browser url &key (method :get) body content-type` — function

Request URL (by `method`, sending `body` as `content-type`), following redirects
with GETs, and make the result the current page.  Returns `browser`; signals
an error after ten redirects.

*Example:* A browser calls the application in-process, with no server.  `visit` follows redirects and returns the browser; the URL it ends on carries the session and page keys.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello))
  (h1 () "Hello"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/hello")))
    (list (browser-status b)
          (not (null (search "/hello?_s=" (browser-url b))))
          (browser-status (visit b "/nowhere")))))
;; ⇒ (200 T 404)
```

#### `back-to` `browser url` — function

Return to an earlier page, as the back button (with no cache) would.

*Example:* Going back to an earlier page and acting on it, as the back button does.  The counter's `states` make its count backtrack, so the earlier page acts on the count it showed.

```lisp
(defclass counter (component)
  ((count :initform 0 :accessor count-of)))
(defmethod states ((self counter))
  (list self))
(defmethod render ((self counter))
  (p () (text (count-of self)))
  (anchor (:callback (lambda () (incf (count-of self)))) "Add one"))
(with-fresh-applications (("/counter" 'counter :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/counter")))
    (click b "Add one")
    (let ((at-one (browser-url b)))
      (click b "Add one")
      (click b "Add one")
      (back-to b at-one)
      (click b "Add one")
      (body-text b))))
;; ⇒ "2 Add one"
```

#### `raw-request` `browser method url &key body content-type` — function

One `method` request to URL, sending `body` as `content-type`, with no redirect
followed.  Keeps the cookies it sets.  Returns the status, the header plist
and the body as a string.

*Example:* One request with no redirects followed, returning the status, the header plist and the body.  Cookies are kept as `visit` keeps them.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello))
  (p () "Hi"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let ((b (make-instance 'browser)))
    (multiple-value-bind (status headers body) (raw-request b :get "/hello")
      (list status
            (not (null (search "/hello?_s=" (response-header headers :location))))
            body
            (response-header headers :cache-control)))))
;; ⇒ (302 T "" "no-store")
```

#### `make-env` `method url &key body cookies extra-headers (content-type "application/x-www-form-urlencoded")` — function

A Lack environment for a `method` request to URL.  `body`, a string or
octets, is sent as `content-type` (form-encoded by default); `cookies` is an
alist of name → value, and `extra-headers` an alist of header name → value.

*Example:* The Lack environment a request would make, to call an application with directly.

```lisp
(let ((env (make-env :post "/search?page=2" :body "q=lisp"
                     :extra-headers '(("Accept-Language" . "de")))))
  (list (getf env :request-method) (getf env :path-info) (getf env :query-string)
        (getf env :content-length) (gethash "accept-language" (getf env :headers))))
;; ⇒ (:POST "/search" "page=2" 6 "de")
```

#### `response-header` `headers name` — function

The header `name` from a Lack response's `headers` plist.

*Example:* One request with no redirects followed, returning the status, the header plist and the body.  Cookies are kept as `visit` keeps them.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello))
  (p () "Hi"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let ((b (make-instance 'browser)))
    (multiple-value-bind (status headers body) (raw-request b :get "/hello")
      (list status
            (not (null (search "/hello?_s=" (response-header headers :location))))
            body
            (response-header headers :cache-control)))))
;; ⇒ (302 T "" "no-store")
```

### Reading the page

#### `page-text` `browser` — function

The current page's text without markup.

*Example:* `browser-html` is the page as served; `page-text` is all its text, the title in the head included; `has-text-p` searches that text.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello))
  (h1 () "Hello & welcome"))
(with-fresh-applications (("/hello" 'hello :mode :deployment :title "Greeter"))
  (let ((b (visit (make-instance 'browser) "/hello")))
    (list (not (null (search "<h1>Hello &amp; welcome</h1>" (browser-html b))))
          (not (null (has-text-p b "Hello & welcome")))
          (not (null (search "<title>Greeter</title>" (browser-html b))))
          (not (null (has-text-p b "Greeter"))))))
;; ⇒ (T T T T)
```

#### `body-text` `browser` — function

The text of the current page's body without markup, as a reader sees
it: a space where a block, cell or form control begins or ends, and each
run of whitespace made one space.

*Example:* The text of the body alone, as a reader sees it: a space where a block, list item, cell or form control starts or ends, none around inline elements such as strong and a, and each run of whitespace made one space.

```lisp
(defclass planets (component) ())
(defmethod render ((self planets))
  (h1 () "Planets")
  (p () "The " (strong () "inner") " ones:")
  (ul () (li () "Mercury") (li () "Venus"))
  (table () (tr () (th () "Largest") (td () "Jupiter")))
  (anchor (:href "/more") "More…"))
(with-fresh-applications (("/planets" 'planets :mode :deployment :title "Space"))
  (body-text (visit (make-instance 'browser) "/planets")))
;; ⇒ "Planets The inner ones: Mercury Venus Largest Jupiter More…"
```

#### `has-text-p` `browser text` — function

True when the current page's text contains `text`.

*Example:* `browser-html` is the page as served; `page-text` is all its text, the title in the head included; `has-text-p` searches that text.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello))
  (h1 () "Hello & welcome"))
(with-fresh-applications (("/hello" 'hello :mode :deployment :title "Greeter"))
  (let ((b (visit (make-instance 'browser) "/hello")))
    (list (not (null (search "<h1>Hello &amp; welcome</h1>" (browser-html b))))
          (not (null (has-text-p b "Hello & welcome")))
          (not (null (search "<title>Greeter</title>" (browser-html b))))
          (not (null (has-text-p b "Greeter"))))))
;; ⇒ (T T T T)
```

#### `find-link` `browser text` — function

The href of the first link whose text contains `text`.

*Example:* `find-link` gives the href of the first link whose text contains a string; `find-links` those whose text is exactly it.  `click-nth` follows one of the latter, counting from 0.

```lisp
(defclass shopping-list (component)
  ((items :initform (list "Bread" "Milk" "Eggs") :accessor items-of)))
(defmethod render ((self shopping-list))
  (ul ()
    (dolist (item (items-of self))
      (li () (text item) " "
        (anchor (:callback (lambda () (setf (items-of self) (remove item (items-of self) :test #'string=))))
          "Remove"))))
  (anchor (:href "/help") "Help with lists"))
(with-fresh-applications (("/list" 'shopping-list :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/list")))
    (let ((help (find-link b "Help"))
          (removes (length (find-links b "Remove"))))
      (click-nth b "Remove" 1)
      (list help removes (body-text b)))))
;; ⇒ ("/help" 3 "Bread Remove Eggs Remove Help with lists")
```

#### `find-links` `browser text` — function

The hrefs of every link whose text is exactly `text`, in page order.

*Example:* `find-link` gives the href of the first link whose text contains a string; `find-links` those whose text is exactly it.  `click-nth` follows one of the latter, counting from 0.

```lisp
(defclass shopping-list (component)
  ((items :initform (list "Bread" "Milk" "Eggs") :accessor items-of)))
(defmethod render ((self shopping-list))
  (ul ()
    (dolist (item (items-of self))
      (li () (text item) " "
        (anchor (:callback (lambda () (setf (items-of self) (remove item (items-of self) :test #'string=))))
          "Remove"))))
  (anchor (:href "/help") "Help with lists"))
(with-fresh-applications (("/list" 'shopping-list :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/list")))
    (let ((help (find-link b "Help"))
          (removes (length (find-links b "Remove"))))
      (click-nth b "Remove" 1)
      (list help removes (body-text b)))))
;; ⇒ ("/help" 3 "Bread Remove Eggs Remove Help with lists")
```

#### `element-name` `browser id` — function

The name of the field with `dom` id `id` or, failing that, the field whose
aria-label is `id` (a brush's `:label`); an error when there is none.

*Example:* A field's name is its callback's id, which changes from page to page, so tests find fields by `dom` id.  `browser-fields` holds what the next `press` submits: the page's own values, then what was typed.

```lisp
(defclass profile (component)
  ((city :initform "Lyon" :accessor city-of)))
(defmethod render ((self profile))
  (form ()
    (text-input (:id "city" :value (city-of self) :callback (lambda (v) (setf (city-of self) v))))
    (submit-button () "Save")))
(with-fresh-applications (("/profile" 'profile :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/profile"))
         (name (element-name b "city")))
    (flet ((city () (rest (assoc name (browser-fields b) :test #'string=))))
      (let ((before (city)))
        (fill-in b "city" "Nantes")
        (list before (city))))))
;; ⇒ ("Lyon" "Nantes")
```

#### `form-action` `browser` — function

The action URL of the first form on the page.

*Example:* `:default-action` runs when the form is submitted without a button, as when Enter is pressed in a field of a form whose buttons all have callbacks.  The fake browser's `press` always names a button, so the test posts the fields itself.

```lisp
(defclass search-box (component)
  ((query :initform "" :accessor query-of)
   (results :initform nil :accessor results-of)))
(defmethod render ((self search-box))
  (form (:role "search" :default-action (lambda () (setf (results-of self) (format nil "Results for ~A" (query-of self)))))
    (text-input (:id "q" :callback (lambda (value) (setf (query-of self) value))))
    (submit-button (:callback (lambda () (setf (results-of self) "Feeling lucky"))) "Lucky"))
  (p () (text (results-of self))))
(with-fresh-applications (("/search" 'search-box :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/search")))
    (fill-in b "q" "lisp")
    (visit b (form-action b) :method :post :body (encode-fields (browser-fields b)))
    (body-text b)))
;; ⇒ "Lucky Results for lisp"
```

#### `attributes` `tag` — function

The attributes in `tag`, the part of an HTML start tag after its name, as an
alist of lower-cased name → unescaped value, `nil` for a bare attribute.

*Example:* Reading the attributes of a start tag, the part after its name, as the fake browser's own regular expressions capture it: an alist of lower-cased names to unescaped values, with `nil` for a bare attribute.

```lisp
(let ((a (attributes " type=\"checkbox\" name=\"7\" title=\"Fish &amp; chips\" checked")))
  (list a (attr a "title")))
;; ⇒ ((("type" . "checkbox") ("name" . "7") ("title" . "Fish & chips") ("checked")) "Fish & chips")
```

#### `attr` `attributes name` — function

The value of attribute `name` in `attributes`.

*Example:* Reading the attributes of a start tag, the part after its name, as the fake browser's own regular expressions capture it: an alist of lower-cased names to unescaped values, with `nil` for a bare attribute.

```lisp
(let ((a (attributes " type=\"checkbox\" name=\"7\" title=\"Fish &amp; chips\" checked")))
  (list a (attr a "title")))
;; ⇒ ((("type" . "checkbox") ("name" . "7") ("title" . "Fish & chips") ("checked")) "Fish & chips")
```

#### `unescape` `string` — function

`string` with the HTML escapes littoral writes undone.

*Example:* `strip-tags` removes markup, scripts and style sheets, then undoes the escapes Littoral writes, which is what `unescape` does alone.

```lisp
(list (strip-tags "<p>Fish &amp; <b>chips</b></p><script>if (a < b) go();</script>")
      (unescape "&lt;a href=&quot;/&quot;&gt; &#39;home&#39;"))
;; ⇒ ("Fish & chips" "<a href=\"/\"> 'home'")
```

#### `strip-tags` `html` — function

HTML with its tags removed and escapes undone.  Scripts and style sheets
go whole, as they aren't text (and a < in them isn't a tag).

*Example:* `strip-tags` removes markup, scripts and style sheets, then undoes the escapes Littoral writes, which is what `unescape` does alone.

```lisp
(list (strip-tags "<p>Fish &amp; <b>chips</b></p><script>if (a < b) go();</script>")
      (unescape "&lt;a href=&quot;/&quot;&gt; &#39;home&#39;"))
;; ⇒ ("Fish & chips" "<a href=\"/\"> 'home'")
```

### Acting on it

#### `click` `browser text` — function

Follow the first link whose text contains `text`; an error when there is none.

*Example:* A link whose `:callback`, a function of no arguments, runs when it is followed; the page is then rendered again.

```lisp
(defclass counter (component)
  ((count :initform 0 :accessor count-of)))
(defmethod render ((self counter))
  (p () (text (count-of self)))
  (anchor (:callback (lambda () (incf (count-of self)))) "Add one"))
(with-fresh-applications (("/counter" 'counter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/counter")
    (click b "Add one")
    (click b "Add one")
    (body-text b)))
;; ⇒ "2 Add one"
```

#### `click-nth` `browser text n` — function

Follow the Nth (from 0) link whose text is exactly `text`.

*Example:* `find-link` gives the href of the first link whose text contains a string; `find-links` those whose text is exactly it.  `click-nth` follows one of the latter, counting from 0.

```lisp
(defclass shopping-list (component)
  ((items :initform (list "Bread" "Milk" "Eggs") :accessor items-of)))
(defmethod render ((self shopping-list))
  (ul ()
    (dolist (item (items-of self))
      (li () (text item) " "
        (anchor (:callback (lambda () (setf (items-of self) (remove item (items-of self) :test #'string=))))
          "Remove"))))
  (anchor (:href "/help") "Help with lists"))
(with-fresh-applications (("/list" 'shopping-list :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/list")))
    (let ((help (find-link b "Help"))
          (removes (length (find-links b "Remove"))))
      (click-nth b "Remove" 1)
      (list help removes (body-text b)))))
;; ⇒ ("/help" 3 "Bread Remove Eggs Remove Help with lists")
```

#### `fill-in` `browser id value` — function

Type `value` into the field with `dom` id `id`, or else with label `id` (see
`element-name`); an error when there is none.
Returns `browser`.

*Example:* A form posts back to the session.  Each field's `:callback` receives what was typed; then the `:callback` of the button pressed runs.  Fields are found in tests by their `:id`.

```lisp
(defclass greeter (component)
  ((name :initform "" :accessor name-of)
   (greeting :initform nil :accessor greeting-of)))
(defmethod render ((self greeter))
  (form ()
    (label (:for "name") "Name")
    (text-input (:id "name" :value (name-of self)
                 :callback (lambda (value) (setf (name-of self) value))))
    (submit-button (:callback (lambda () (setf (greeting-of self) (format nil "Hello, ~A!" (name-of self)))))
      "Greet"))
  (when (greeting-of self)
    (p () (text (greeting-of self)))))
(with-fresh-applications (("/greet" 'greeter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greet")
    (fill-in b "name" "Ada")
    (press b "Greet")
    (body-text b)))
;; ⇒ "Name Greet Hello, Ada!"
```

#### `set-checkbox` `browser index checked` — function

Check (`checked` true) or uncheck the INDEXth checkbox on the page,
counting from 0.

*Example:* `:value` is whether the box is checked; `:callback` receives T or `nil`.  An unchecked box still reports `nil`, as the brush writes a hidden twin.  In tests, `set-checkbox` picks boxes by their position on the page.

```lisp
(defclass preferences (component)
  ((newsletter :initform nil :accessor newsletter-p)
   (digest :initform t :accessor digest-p)))
(defmethod render ((self preferences))
  (form ()
    (label () (checkbox (:value (newsletter-p self) :callback (lambda (on) (setf (newsletter-p self) on))))
      "Newsletter")
    (label () (checkbox (:value (digest-p self) :callback (lambda (on) (setf (digest-p self) on))))
      "Weekly digest")
    (submit-button () "Save"))
  (p () (text (list (newsletter-p self) (digest-p self)))))
(with-fresh-applications (("/prefs" 'preferences :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/prefs")
    (set-checkbox b 0 t)
    (set-checkbox b 1 nil)
    (press b "Save")
    (body-text b)))
;; ⇒ "Newsletter Weekly digest Save (T NIL)"
```

#### `select-option` `browser id label` — function

Choose the option labelled exactly `label` in the select with `dom` id `id`,
or else with label `id` (see `element-name`); an error when there is none.
Returns `browser`.

*Example:* A drop-down of `:items`, which may be any objects: `:labels` turns one into its text, `:selected` is the one shown chosen (compared with `:test`, default `eql`), and `:callback` receives the item chosen.

```lisp
(defclass shipping (component)
  ((carrier :initform :post :accessor carrier-of)))
(defmethod render ((self shipping))
  (form ()
    (select-list (:id "method" :items '(:post :courier :collect)
                  :labels (lambda (item) (string-capitalize item))
                  :selected (carrier-of self)
                  :callback (lambda (item) (setf (carrier-of self) item))))
    (submit-button () "Choose"))
  (p () "Shipping by " (text (string-downcase (carrier-of self)))))
(with-fresh-applications (("/ship" 'shipping :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/ship")
    (select-option b "method" "Courier")
    (press b "Choose")
    (body-text b)))
;; ⇒ "Post Courier Collect Choose Shipping by courier"
```

#### `choose-radio` `browser label` — function

Choose the radio button labelled exactly `label` (the text of its
<label>), as clicking it would.  An error when there is none.  Returns
`browser`.

*Example:* The submitted choice reaches `:callback` as the item itself.  The fake browser's choose-radio clicks a button by its label.

```lisp
(defclass size-picker (component)
  ((size :initform :small :accessor size-of)))
(defmethod render ((self size-picker))
  (form ()
    (radio-group (:id "size" :items '(:small :medium :large) :selected (size-of self)
                  :labels #'string-downcase
                  :callback (lambda (size) (setf (size-of self) size))))
    (submit-button () "Pick"))
  (p () "Size: " (text (size-of self))))
(with-fresh-applications (("/size" 'size-picker :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/size")))
    (choose-radio b "large")
    (press b "Pick")
    (body-text b)))
;; ⇒ "small medium large Pick Size: LARGE"
```

#### `attach-file` `browser id filename content-type contents` — function

Choose a file for the file input with `dom` id `id`.  `contents` is a string
or a vector of octets.

*Example:* A file chooser needs a form with `:multipart` T.  Its `:callback` receives an `uploaded-file`, whose bytes are an octet vector, and is not called when no file was chosen.

```lisp
(defclass uploader (component)
  ((report :initform "Nothing yet" :accessor report-of)))
(defmethod render ((self uploader))
  (form (:multipart t)
    (file-input (:id "file" :accept "text/*"
                 :callback (lambda (file)
                             (setf (report-of self)
                                   (format nil "~A (~A): ~D bytes, starting ~S"
                                           (file-name file) (file-content-type file)
                                           (length (file-contents file))
                                           (code-char (aref (file-contents file) 0)))))))
    (submit-button () "Upload"))
  (p () (text (report-of self))))
(with-fresh-applications (("/upload" 'uploader :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/upload")))
    (attach-file b "file" "notes.txt" "text/plain" "Hello, world")
    (press b "Upload")
    (body-text b)))
;; ⇒ "Upload notes.txt (text/plain): 12 bytes, starting #\\H"
```

#### `press` `browser text` — function

Submit the form with the first button whose label contains `text`, sending
`browser-fields`, and `browser-files` as multipart when there are any; an error
when there is no such button.

*Example:* A form posts back to the session.  Each field's `:callback` receives what was typed; then the `:callback` of the button pressed runs.  Fields are found in tests by their `:id`.

```lisp
(defclass greeter (component)
  ((name :initform "" :accessor name-of)
   (greeting :initform nil :accessor greeting-of)))
(defmethod render ((self greeter))
  (form ()
    (label (:for "name") "Name")
    (text-input (:id "name" :value (name-of self)
                 :callback (lambda (value) (setf (name-of self) value))))
    (submit-button (:callback (lambda () (setf (greeting-of self) (format nil "Hello, ~A!" (name-of self)))))
      "Greet"))
  (when (greeting-of self)
    (p () (text (greeting-of self)))))
(with-fresh-applications (("/greet" 'greeter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greet")
    (fill-in b "name" "Ada")
    (press b "Greet")
    (body-text b)))
;; ⇒ "Name Greet Hello, Ada!"
```

#### `encode-fields` `fields` — function

`fields`, an alist, as a URL-encoded form body.

*Example:* `:default-action` runs when the form is submitted without a button, as when Enter is pressed in a field of a form whose buttons all have callbacks.  The fake browser's `press` always names a button, so the test posts the fields itself.

```lisp
(defclass search-box (component)
  ((query :initform "" :accessor query-of)
   (results :initform nil :accessor results-of)))
(defmethod render ((self search-box))
  (form (:role "search" :default-action (lambda () (setf (results-of self) (format nil "Results for ~A" (query-of self)))))
    (text-input (:id "q" :callback (lambda (value) (setf (query-of self) value))))
    (submit-button (:callback (lambda () (setf (results-of self) "Feeling lucky"))) "Lucky"))
  (p () (text (results-of self))))
(with-fresh-applications (("/search" 'search-box :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/search")))
    (fill-in b "q" "lisp")
    (visit b (form-action b) :method :post :body (encode-fields (browser-fields b)))
    (body-text b)))
;; ⇒ "Lucky Results for lisp"
```

### AJAX and server push

#### `ajax-request` `browser callback targets &key fields` — function

Post an AJAX request the way littoral.js does, running the callback with
id `callback` (none when `nil` or "") and re-rendering `targets`, a string of
component ids, as `ajax-specs` gives them.  `fields`, an alist, is posted too.
Returns the JSON text and the status.

*Example:* A button that submits nothing; it is for an AJAX `:on-click`, which runs its callback in the background and re-renders the components to `:update`.  Those components must be `updatable`.

```lisp
(defclass likes (updatable component)
  ((count :initform 0 :accessor count-of)))
(defmethod render ((self likes))
  (span () (text (count-of self)) " likes")
  (button (:class "like" :on-click (ajax :callback (lambda () (incf (count-of self))) :update self))
    "Like"))
(with-fresh-applications (("/likes" 'likes :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/likes"))
         (spec (first (ajax-specs b "on-click"))))
    (ajax-request b (first spec) (rest spec))
    (ajax-request b (first spec) (rest spec))
    (visit b (browser-url b))             ; reload: the change stayed
    (body-text b)))
;; ⇒ "2 likes Like"
```

#### `ajax-specs` `browser attribute` — function

The (`callback` . `targets`) of each element with data-lt-ATTRIBUTE, in page
order, for `ajax-request`.  `attribute` is the event, such as "on-click".

*Example:* A button that submits nothing; it is for an AJAX `:on-click`, which runs its callback in the background and re-renders the components to `:update`.  Those components must be `updatable`.

```lisp
(defclass likes (updatable component)
  ((count :initform 0 :accessor count-of)))
(defmethod render ((self likes))
  (span () (text (count-of self)) " likes")
  (button (:class "like" :on-click (ajax :callback (lambda () (incf (count-of self))) :update self))
    "Like"))
(with-fresh-applications (("/likes" 'likes :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/likes"))
         (spec (first (ajax-specs b "on-click"))))
    (ajax-request b (first spec) (rest spec))
    (ajax-request b (first spec) (rest spec))
    (visit b (browser-url b))             ; reload: the change stayed
    (body-text b)))
;; ⇒ "2 likes Like"
```

#### `sink` — class

Collects what an event stream writes.

*Example:* Server push in a test: `open-stream` opens the page's event stream in a thread writing into a `sink`, and `wait-for` polls until what was pushed arrives.  `close-event-streams` ends the stream and its thread.

```lisp
(defvar *scores* (make-channel "scores"))
(defvar *score* 0)
(defclass scoreboard (updatable component) ())
(defmethod subscriptions ((self scoreboard))
  (list *scores*))
(defmethod render ((self scoreboard))
  (p () "Score: " (text *score*)))
(with-fresh-applications (("/score" 'scoreboard :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/score"))
         (sink (make-instance 'sink))
         (thread (open-stream b sink)))
    (unwind-protect
         (list (wait-for (lambda () (search "retry:" (sink-text sink))) 2)
               (progn (setf *score* 3)
                      (publish *scores*)
                      (wait-for (lambda () (search "Score: 3" (sink-text sink))) 2))
               (not (null (search "event: update" (sink-text sink)))))
      (close-event-streams)
      (sb-thread:join-thread thread :default nil :timeout 2))))
;; ⇒ (T T T)
```

#### `sink-text` `sink` — function

Everything written to `sink` so far.

*Example:* Server push in a test: `open-stream` opens the page's event stream in a thread writing into a `sink`, and `wait-for` polls until what was pushed arrives.  `close-event-streams` ends the stream and its thread.

```lisp
(defvar *scores* (make-channel "scores"))
(defvar *score* 0)
(defclass scoreboard (updatable component) ())
(defmethod subscriptions ((self scoreboard))
  (list *scores*))
(defmethod render ((self scoreboard))
  (p () "Score: " (text *score*)))
(with-fresh-applications (("/score" 'scoreboard :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/score"))
         (sink (make-instance 'sink))
         (thread (open-stream b sink)))
    (unwind-protect
         (list (wait-for (lambda () (search "retry:" (sink-text sink))) 2)
               (progn (setf *score* 3)
                      (publish *scores*)
                      (wait-for (lambda () (search "Score: 3" (sink-text sink))) 2))
               (not (null (search "event: update" (sink-text sink)))))
      (close-event-streams)
      (sb-thread:join-thread thread :default nil :timeout 2))))
;; ⇒ (T T T)
```

#### `open-stream` `browser sink` — function

Open the current page's event stream in a thread, writing into `sink`, and
wait (up to 10 seconds) until it is open: its first line, retry:, written.
From then on it is among the open streams, so `publish` reaches it and
`close-event-streams` closes it.  Returns the thread; an error when the page
has no stream.

*Example:* Server push in a test: `open-stream` opens the page's event stream in a thread writing into a `sink`, and `wait-for` polls until what was pushed arrives.  `close-event-streams` ends the stream and its thread.

```lisp
(defvar *scores* (make-channel "scores"))
(defvar *score* 0)
(defclass scoreboard (updatable component) ())
(defmethod subscriptions ((self scoreboard))
  (list *scores*))
(defmethod render ((self scoreboard))
  (p () "Score: " (text *score*)))
(with-fresh-applications (("/score" 'scoreboard :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/score"))
         (sink (make-instance 'sink))
         (thread (open-stream b sink)))
    (unwind-protect
         (list (wait-for (lambda () (search "retry:" (sink-text sink))) 2)
               (progn (setf *score* 3)
                      (publish *scores*)
                      (wait-for (lambda () (search "Score: 3" (sink-text sink))) 2))
               (not (null (search "event: update" (sink-text sink)))))
      (close-event-streams)
      (sb-thread:join-thread thread :default nil :timeout 2))))
;; ⇒ (T T T)
```

#### `wait-for` `predicate &optional (seconds 10)` — function

Poll `predicate` for up to `seconds`; true when it came true.

*Example:* Server push in a test: `open-stream` opens the page's event stream in a thread writing into a `sink`, and `wait-for` polls until what was pushed arrives.  `close-event-streams` ends the stream and its thread.

```lisp
(defvar *scores* (make-channel "scores"))
(defvar *score* 0)
(defclass scoreboard (updatable component) ())
(defmethod subscriptions ((self scoreboard))
  (list *scores*))
(defmethod render ((self scoreboard))
  (p () "Score: " (text *score*)))
(with-fresh-applications (("/score" 'scoreboard :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/score"))
         (sink (make-instance 'sink))
         (thread (open-stream b sink)))
    (unwind-protect
         (list (wait-for (lambda () (search "retry:" (sink-text sink))) 2)
               (progn (setf *score* 3)
                      (publish *scores*)
                      (wait-for (lambda () (search "Score: 3" (sink-text sink))) 2))
               (not (null (search "event: update" (sink-text sink)))))
      (close-event-streams)
      (sb-thread:join-thread thread :default nil :timeout 2))))
;; ⇒ (T T T)
```

### Test fixtures

#### `with-fresh-applications` `(&rest registrations) &body body` — macro

Run `body` with only the applications `registrations` names registered, each
registration a list of `register-application`'s arguments.

*Example:* Registers applications for the body only, each with `register-application`'s arguments, hiding any others.

```lisp
(defclass hello (component) ())
(defmethod render ((self hello))
  (p () "Hi"))
(list (with-fresh-applications (("/one" 'hello :mode :deployment)
                                ("/two" 'hello :mode :deployment))
        (mapcar #'application-path (list-applications)))
      (find-application "/one"))
;; ⇒ (("/one" "/two") NIL)
```

## Package `littoral.browser-test`

Load with `(asdf:load-system :littoral/browser-test)`.  Drives headless
Chrome (or Chromium) from Lisp tests, so that pages run their JavaScript:
AJAX, server push, dialogs and passkeys.  The application must be served
(START) where WITH-CHROME's :base points.  VISIT, TEXT and PAGE-URL are also
names in littoral.test, littoral.html and littoral, so write this package's
with its prefix, as in `(littoral.browser-test:visit page "/")`.

### General

#### `with-chrome` `(page &rest options &key base width height) &body body` — macro

Run `body` with `page` a tab of a new headless Chrome, with a fresh profile,
its paths relative to `base` ("http://127.0.0.1:8080" by default) and its
window `width` by `height` pixels (1280 by 800).  Chrome is killed and its
profile deleted afterwards.  Returns `body`'s value; signals `browser-error`
when Chrome can't be found or doesn't start.

#### `chrome-path` — function

The path of Chrome or Chromium: $`chrome`, $LITTORAL_TEST_CHROME, or the
first of the usual places on macOS and Linux that exists.  Signals
`browser-error` when there is none.

#### `page` — class

A Chrome tab, driven over the DevTools protocol.

#### `visit` `page path` — function

Open `path` in `page`: relative to `with-chrome`'s :base, or a whole URL
starting with http.  Returns when the page has loaded.

#### `evaluate` `page javascript` — function

The value of the JavaScript expression `javascript` in `page` (promises
awaited), as com.inuoe.jzon parses its JSON: strings, numbers, T and `nil`
for true and false, the symbol `null` for null, vectors and hash tables; `nil`
for undefined.  Signals `browser-error` when it throws.

#### `click-text` `page text &key (among "a, button")` — function

Click the first link or button (or element the CSS selector `among`
selects) whose text is `text`, or failing that contains it, and wait for any
page it loads.  Signals `browser-error` when there is none.

#### `click-css` `page selector` — function

Click the first element the CSS `selector` matches, and wait for any page
it loads.  Signals `browser-error` when nothing matches.

#### `type-into` `page selector string` — function

Put `string` in the field the CSS `selector` matches, replacing its text: the
field is clicked and focused, its text selected, and `string` inserted as
typing does (an input event, but no key events).  Signals `browser-error`
when nothing matches.

#### `text` `page &optional (selector "body")` — function

The visible text of the first element the CSS `selector` matches (the
whole body by default), or "" when nothing matches.

#### `page-url` `page` — function

Where `page` is: its whole URL, as a string.

#### `back` `page` — function

Go back in `page`'s history, as the browser's back button does, and wait
for the page to load.

#### `wait-until` `page javascript &key (timeout 10)` — function

Wait until the JavaScript expression `javascript` is true in `page`, checking
ten times a second; returns T.  Signals `browser-error` after `timeout`
seconds.

#### `screenshot` `page pathname` — function

Save what `page` shows as a PNG at `pathname`, replacing any file there;
returns `pathname`.

#### `add-virtual-authenticator` `page` — function

Give `page` a platform authenticator (`ctap2`, with resident keys and user
verification) that always says yes, for passkey tests.

#### `browser-error` — condition

Chrome couldn't do what a test asked: no such element, a timeout, a JavaScript error.

## Package `littoral.mail`

Load it with `(asdf:load-system :littoral/mail)`.  Sending mail: MIME messages,
SMTP, templates and an outbox that retries.

### Messages

#### `mail` — class

A mail to send: `make-mail` makes one.

*Example:* A mail with a plain-text body.  Its recipients are everyone it goes to, Bcc included, as bare addresses.

```lisp
(let ((mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                     :to "Ada Lovelace <ada@example.org>"
                                     :bcc "orders@example.org"
                                     :subject "Your order has shipped"
                                     :text "It should arrive on Friday.")))
  (list (littoral.mail:mail-to mail)
        (littoral.mail:mail-bcc mail)
        (littoral.mail:mail-subject mail)
        (littoral.mail:mail-text mail)
        (littoral.mail:mail-recipients mail)))
;; ⇒ (("Ada Lovelace <ada@example.org>") ("orders@example.org") "Your order has shipped" "It should arrive on Friday." ("ada@example.org" "orders@example.org"))
```

#### `make-mail` `&key to cc bcc (from *mail-from*) reply-to (subject "") text html attachments headers` — function

A mail.  `to`, `cc` and `bcc` are addresses ("ada@example.org" or "Ada <ada@example.org>")
or lists of them; `from` an address (`*mail-from*`) and `reply-to` one or `nil`; `text`
and HTML its plain and HTML bodies (one is enough: the plain one is made from
the HTML when missing); `attachments` (`file-name` `content-type` `data`) lists, `data`
octets or a string (sent as UTF-8); `headers` (`name` . `value`) pairs.  Signals an
error without a recipient or a body, and an `smtp-error` for a bad address or a
line break in a header.

*Example:* A mail with a plain-text body.  Its recipients are everyone it goes to, Bcc included, as bare addresses.

```lisp
(let ((mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                     :to "Ada Lovelace <ada@example.org>"
                                     :bcc "orders@example.org"
                                     :subject "Your order has shipped"
                                     :text "It should arrive on Friday.")))
  (list (littoral.mail:mail-to mail)
        (littoral.mail:mail-bcc mail)
        (littoral.mail:mail-subject mail)
        (littoral.mail:mail-text mail)
        (littoral.mail:mail-recipients mail)))
;; ⇒ (("Ada Lovelace <ada@example.org>") ("orders@example.org") "Your order has shipped" "It should arrive on Friday." ("ada@example.org" "orders@example.org"))
```

*Example:* With only an HTML body, the plain one is made from it.

```lisp
(let ((mail (littoral.mail:make-mail :to "ada@example.org" :subject "Hello"
                                     :html "<p>Your <b>order</b> is <a href=\"https://example.org/orders/42\">here</a>.</p>")))
  (list (littoral.mail:mail-html mail) (littoral.mail:mail-text mail)))
;; ⇒ ("<p>Your <b>order</b> is <a href=\"https://example.org/orders/42\">here</a>.</p>" "Your order is here (https://example.org/orders/42).")
```

*Example:* A mail needs someone to send it to and a body, and its addresses and headers can't smuggle in line breaks: each is refused when the mail is made.

```lisp
(flet ((refused-p (&rest arguments)
         (handler-case (progn (apply #'littoral.mail:make-mail arguments) nil)
           (error () t))))
  (list (refused-p :to "ada@example.org" :subject "No body")
        (refused-p :subject "Nobody" :text "Hello")
        (refused-p :to "not an address" :text "Hello")
        (refused-p :to "ada@example.org" :subject (format nil "Hi~%Bcc: everyone@example.org") :text "Hello")))
;; ⇒ (T T T T)
```

#### `mail-to` `object` — generic function

Reads the to of a mail.  A list of addresses.

*Example:* A mail with a plain-text body.  Its recipients are everyone it goes to, Bcc included, as bare addresses.

```lisp
(let ((mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                     :to "Ada Lovelace <ada@example.org>"
                                     :bcc "orders@example.org"
                                     :subject "Your order has shipped"
                                     :text "It should arrive on Friday.")))
  (list (littoral.mail:mail-to mail)
        (littoral.mail:mail-bcc mail)
        (littoral.mail:mail-subject mail)
        (littoral.mail:mail-text mail)
        (littoral.mail:mail-recipients mail)))
;; ⇒ (("Ada Lovelace <ada@example.org>") ("orders@example.org") "Your order has shipped" "It should arrive on Friday." ("ada@example.org" "orders@example.org"))
```

#### `mail-cc` `object` — generic function

Reads the cc of a mail.  A list of addresses.

*Example:* Copies, a Reply-To address, extra headers and an attachment, read back from the message `mail-string` writes.

```lisp
(let* ((mail (littoral.mail:make-mail :from "Accounts <accounts@example.org>"
                                      :to "ada@example.org" :cc "bob@example.org"
                                      :reply-to "help@example.org"
                                      :subject "Invoice 42" :text "Your invoice is attached."
                                      :headers '(("X-Invoice" . "42"))
                                      :attachments '(("invoice.txt" "text/plain" "Total: 12.50"))))
       (message (littoral.mail:mail-string mail)))
  (list (littoral.mail:mail-from mail)
        (littoral.mail:mail-cc mail)
        (littoral.mail:message-header message "Cc")
        (littoral.mail:message-header message "Reply-To")
        (littoral.mail:message-header message "X-Invoice")
        (mapcar #'first (littoral.mail:mail-attachments mail))))
;; ⇒ ("Accounts <accounts@example.org>" ("bob@example.org") "bob@example.org" "help@example.org" "42" ("invoice.txt"))
```

#### `mail-bcc` `object` — generic function

Reads the bcc of a mail.  A list of addresses, which the message doesn't show.

*Example:* A mail with a plain-text body.  Its recipients are everyone it goes to, Bcc included, as bare addresses.

```lisp
(let ((mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                     :to "Ada Lovelace <ada@example.org>"
                                     :bcc "orders@example.org"
                                     :subject "Your order has shipped"
                                     :text "It should arrive on Friday.")))
  (list (littoral.mail:mail-to mail)
        (littoral.mail:mail-bcc mail)
        (littoral.mail:mail-subject mail)
        (littoral.mail:mail-text mail)
        (littoral.mail:mail-recipients mail)))
;; ⇒ (("Ada Lovelace <ada@example.org>") ("orders@example.org") "Your order has shipped" "It should arrive on Friday." ("ada@example.org" "orders@example.org"))
```

#### `mail-from` `object` — generic function

Reads the from of a mail.  An address.

*Example:* Copies, a Reply-To address, extra headers and an attachment, read back from the message `mail-string` writes.

```lisp
(let* ((mail (littoral.mail:make-mail :from "Accounts <accounts@example.org>"
                                      :to "ada@example.org" :cc "bob@example.org"
                                      :reply-to "help@example.org"
                                      :subject "Invoice 42" :text "Your invoice is attached."
                                      :headers '(("X-Invoice" . "42"))
                                      :attachments '(("invoice.txt" "text/plain" "Total: 12.50"))))
       (message (littoral.mail:mail-string mail)))
  (list (littoral.mail:mail-from mail)
        (littoral.mail:mail-cc mail)
        (littoral.mail:message-header message "Cc")
        (littoral.mail:message-header message "Reply-To")
        (littoral.mail:message-header message "X-Invoice")
        (mapcar #'first (littoral.mail:mail-attachments mail))))
;; ⇒ ("Accounts <accounts@example.org>" ("bob@example.org") "bob@example.org" "help@example.org" "42" ("invoice.txt"))
```

#### `mail-reply-to` `object` — generic function

Reads the reply-to of a mail.  An address, or `nil`.

*Example:* Copies, a Reply-To address, extra headers and an attachment, read back from the message `mail-string` writes.

```lisp
(let* ((mail (littoral.mail:make-mail :from "Accounts <accounts@example.org>"
                                      :to "ada@example.org" :cc "bob@example.org"
                                      :reply-to "help@example.org"
                                      :subject "Invoice 42" :text "Your invoice is attached."
                                      :headers '(("X-Invoice" . "42"))
                                      :attachments '(("invoice.txt" "text/plain" "Total: 12.50"))))
       (message (littoral.mail:mail-string mail)))
  (list (littoral.mail:mail-from mail)
        (littoral.mail:mail-cc mail)
        (littoral.mail:message-header message "Cc")
        (littoral.mail:message-header message "Reply-To")
        (littoral.mail:message-header message "X-Invoice")
        (mapcar #'first (littoral.mail:mail-attachments mail))))
;; ⇒ ("Accounts <accounts@example.org>" ("bob@example.org") "bob@example.org" "help@example.org" "42" ("invoice.txt"))
```

#### `mail-subject` `object` — generic function

Reads the subject of a mail.

*Example:* A mail with a plain-text body.  Its recipients are everyone it goes to, Bcc included, as bare addresses.

```lisp
(let ((mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                     :to "Ada Lovelace <ada@example.org>"
                                     :bcc "orders@example.org"
                                     :subject "Your order has shipped"
                                     :text "It should arrive on Friday.")))
  (list (littoral.mail:mail-to mail)
        (littoral.mail:mail-bcc mail)
        (littoral.mail:mail-subject mail)
        (littoral.mail:mail-text mail)
        (littoral.mail:mail-recipients mail)))
;; ⇒ (("Ada Lovelace <ada@example.org>") ("orders@example.org") "Your order has shipped" "It should arrive on Friday." ("ada@example.org" "orders@example.org"))
```

#### `mail-text` `object` — generic function

Reads the text of a mail.  The plain-text body, made from the HTML one when not given.

*Example:* A mail with a plain-text body.  Its recipients are everyone it goes to, Bcc included, as bare addresses.

```lisp
(let ((mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                     :to "Ada Lovelace <ada@example.org>"
                                     :bcc "orders@example.org"
                                     :subject "Your order has shipped"
                                     :text "It should arrive on Friday.")))
  (list (littoral.mail:mail-to mail)
        (littoral.mail:mail-bcc mail)
        (littoral.mail:mail-subject mail)
        (littoral.mail:mail-text mail)
        (littoral.mail:mail-recipients mail)))
;; ⇒ (("Ada Lovelace <ada@example.org>") ("orders@example.org") "Your order has shipped" "It should arrive on Friday." ("ada@example.org" "orders@example.org"))
```

*Example:* With only an HTML body, the plain one is made from it.

```lisp
(let ((mail (littoral.mail:make-mail :to "ada@example.org" :subject "Hello"
                                     :html "<p>Your <b>order</b> is <a href=\"https://example.org/orders/42\">here</a>.</p>")))
  (list (littoral.mail:mail-html mail) (littoral.mail:mail-text mail)))
;; ⇒ ("<p>Your <b>order</b> is <a href=\"https://example.org/orders/42\">here</a>.</p>" "Your order is here (https://example.org/orders/42).")
```

#### `mail-html` `object` — generic function

Reads the html of a mail.  The HTML body, or `nil`.

*Example:* With only an HTML body, the plain one is made from it.

```lisp
(let ((mail (littoral.mail:make-mail :to "ada@example.org" :subject "Hello"
                                     :html "<p>Your <b>order</b> is <a href=\"https://example.org/orders/42\">here</a>.</p>")))
  (list (littoral.mail:mail-html mail) (littoral.mail:mail-text mail)))
;; ⇒ ("<p>Your <b>order</b> is <a href=\"https://example.org/orders/42\">here</a>.</p>" "Your order is here (https://example.org/orders/42).")
```

#### `mail-attachments` `object` — generic function

Reads the attachments of a mail.  (`file-name` `content-type` `octets-or-string`) lists.

*Example:* Copies, a Reply-To address, extra headers and an attachment, read back from the message `mail-string` writes.

```lisp
(let* ((mail (littoral.mail:make-mail :from "Accounts <accounts@example.org>"
                                      :to "ada@example.org" :cc "bob@example.org"
                                      :reply-to "help@example.org"
                                      :subject "Invoice 42" :text "Your invoice is attached."
                                      :headers '(("X-Invoice" . "42"))
                                      :attachments '(("invoice.txt" "text/plain" "Total: 12.50"))))
       (message (littoral.mail:mail-string mail)))
  (list (littoral.mail:mail-from mail)
        (littoral.mail:mail-cc mail)
        (littoral.mail:message-header message "Cc")
        (littoral.mail:message-header message "Reply-To")
        (littoral.mail:message-header message "X-Invoice")
        (mapcar #'first (littoral.mail:mail-attachments mail))))
;; ⇒ ("Accounts <accounts@example.org>" ("bob@example.org") "bob@example.org" "help@example.org" "42" ("invoice.txt"))
```

#### `mail-headers` `object` — generic function

Reads the headers of a mail.  Extra headers, as (`name` . `value`) pairs.

*Example:* Copies, a Reply-To address, extra headers and an attachment, read back from the message `mail-string` writes.

```lisp
(let* ((mail (littoral.mail:make-mail :from "Accounts <accounts@example.org>"
                                      :to "ada@example.org" :cc "bob@example.org"
                                      :reply-to "help@example.org"
                                      :subject "Invoice 42" :text "Your invoice is attached."
                                      :headers '(("X-Invoice" . "42"))
                                      :attachments '(("invoice.txt" "text/plain" "Total: 12.50"))))
       (message (littoral.mail:mail-string mail)))
  (list (littoral.mail:mail-from mail)
        (littoral.mail:mail-cc mail)
        (littoral.mail:message-header message "Cc")
        (littoral.mail:message-header message "Reply-To")
        (littoral.mail:message-header message "X-Invoice")
        (mapcar #'first (littoral.mail:mail-attachments mail))))
;; ⇒ ("Accounts <accounts@example.org>" ("bob@example.org") "bob@example.org" "help@example.org" "42" ("invoice.txt"))
```

#### `mail-string` `mail &key (date (get-universal-time))` — function

`mail` as a MIME message, with `crlf` line breaks, dated `date` (a universal
time, now by default); Bcc isn't written.

*Example:* `mail-string` writes the MIME message a mailer sends; the message functions read one back, decoding what MIME encoded.

```lisp
(let* ((mail (littoral.mail:make-mail :to "Zoë <zoe@example.org>" :bcc "orders@example.org"
                                      :subject "Ça va? Order №42"
                                      :text "Thank you, Zoë."
                                      :html "<p>Thank you, <b>Zoë</b>.</p>"))
       (message (littoral.mail:mail-string mail)))
  (list (littoral.mail:message-header message "Subject")
        (littoral.mail:message-header message "To")
        (string-right-trim '(#\Newline) (littoral.mail:message-text message))
        (string-right-trim '(#\Newline) (littoral.mail:message-html message))
        (every (lambda (c) (< (char-code c) 128)) message)
        (null (search "orders@example.org" message))))
;; ⇒ ("Ça va? Order №42" "Zoë <zoe@example.org>" "Thank you, Zoë." "<p>Thank you, <b>Zoë</b>.</p>" T T)
```

#### `mail-recipients` `mail` — function

Everyone `mail` goes to, Bcc included, as bare addresses.

*Example:* A mail with a plain-text body.  Its recipients are everyone it goes to, Bcc included, as bare addresses.

```lisp
(let ((mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                     :to "Ada Lovelace <ada@example.org>"
                                     :bcc "orders@example.org"
                                     :subject "Your order has shipped"
                                     :text "It should arrive on Friday.")))
  (list (littoral.mail:mail-to mail)
        (littoral.mail:mail-bcc mail)
        (littoral.mail:mail-subject mail)
        (littoral.mail:mail-text mail)
        (littoral.mail:mail-recipients mail)))
;; ⇒ (("Ada Lovelace <ada@example.org>") ("orders@example.org") "Your order has shipped" "It should arrive on Friday." ("ada@example.org" "orders@example.org"))
```

#### `*mail-from*` — variable

The From address of mail that doesn't give one.

*Example:* The From address of mail that doesn't give one.

```lisp
(let ((littoral.mail:*mail-from* "Bookshop <hello@example.org>"))
  (littoral.mail:mail-from (littoral.mail:make-mail :to "ada@example.org" :text "Hello")))
;; ⇒ "Bookshop <hello@example.org>"
```

#### `address-spec` `address` — function

The bare address in `address`: "Ada <ada@example.org>" → "ada@example.org".
Signals an `smtp-error` when `address` isn't one.

```lisp
(littoral.mail:address-spec "Ada Lovelace <ada@example.org>")
;; ⇒ "ada@example.org"
```

### Reading messages back

#### `message-header` `message name` — function

The header `name` of `message` (a MIME string), decoded, or `nil`.

*Example:* `mail-string` writes the MIME message a mailer sends; the message functions read one back, decoding what MIME encoded.

```lisp
(let* ((mail (littoral.mail:make-mail :to "Zoë <zoe@example.org>" :bcc "orders@example.org"
                                      :subject "Ça va? Order №42"
                                      :text "Thank you, Zoë."
                                      :html "<p>Thank you, <b>Zoë</b>.</p>"))
       (message (littoral.mail:mail-string mail)))
  (list (littoral.mail:message-header message "Subject")
        (littoral.mail:message-header message "To")
        (string-right-trim '(#\Newline) (littoral.mail:message-text message))
        (string-right-trim '(#\Newline) (littoral.mail:message-html message))
        (every (lambda (c) (< (char-code c) 128)) message)
        (null (search "orders@example.org" message))))
;; ⇒ ("Ça va? Order №42" "Zoë <zoe@example.org>" "Thank you, Zoë." "<p>Thank you, <b>Zoë</b>.</p>" T T)
```

#### `message-text` `message` — function

The plain text of `message` (a MIME string), with plain newlines, or `nil`.

*Example:* `mail-string` writes the MIME message a mailer sends; the message functions read one back, decoding what MIME encoded.

```lisp
(let* ((mail (littoral.mail:make-mail :to "Zoë <zoe@example.org>" :bcc "orders@example.org"
                                      :subject "Ça va? Order №42"
                                      :text "Thank you, Zoë."
                                      :html "<p>Thank you, <b>Zoë</b>.</p>"))
       (message (littoral.mail:mail-string mail)))
  (list (littoral.mail:message-header message "Subject")
        (littoral.mail:message-header message "To")
        (string-right-trim '(#\Newline) (littoral.mail:message-text message))
        (string-right-trim '(#\Newline) (littoral.mail:message-html message))
        (every (lambda (c) (< (char-code c) 128)) message)
        (null (search "orders@example.org" message))))
;; ⇒ ("Ça va? Order №42" "Zoë <zoe@example.org>" "Thank you, Zoë." "<p>Thank you, <b>Zoë</b>.</p>" T T)
```

#### `message-html` `message` — function

The HTML part of `message` (a MIME string), or `nil`.

*Example:* `mail-string` writes the MIME message a mailer sends; the message functions read one back, decoding what MIME encoded.

```lisp
(let* ((mail (littoral.mail:make-mail :to "Zoë <zoe@example.org>" :bcc "orders@example.org"
                                      :subject "Ça va? Order №42"
                                      :text "Thank you, Zoë."
                                      :html "<p>Thank you, <b>Zoë</b>.</p>"))
       (message (littoral.mail:mail-string mail)))
  (list (littoral.mail:message-header message "Subject")
        (littoral.mail:message-header message "To")
        (string-right-trim '(#\Newline) (littoral.mail:message-text message))
        (string-right-trim '(#\Newline) (littoral.mail:message-html message))
        (every (lambda (c) (< (char-code c) 128)) message)
        (null (search "orders@example.org" message))))
;; ⇒ ("Ça va? Order №42" "Zoë <zoe@example.org>" "Thank you, Zoë." "<p>Thank you, <b>Zoë</b>.</p>" T T)
```

### Mailers

#### `*mailer*` — variable

What sends mail: an `smtp-mailer`, or by default a `log-mailer` that prints it.

*Example:* `send-mail` uses `*mailer*` unless given one.

```lisp
(let ((littoral.mail:*mailer* (littoral.mail:make-memory-mailer :keep 10)))
  (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :text "One"))
  (littoral.mail:send-mail (littoral.mail:make-mail :to "bob@example.org" :text "Two"))
  (list (length (littoral.mail:mailer-messages littoral.mail:*mailer*))
        (progn (littoral.mail:clear-mailer littoral.mail:*mailer*)
               (littoral.mail:mailer-messages littoral.mail:*mailer*))))
;; ⇒ (2 NIL)
```

#### `send-message` `mailer from recipients message` — generic function

Send `message`, a MIME string, from the address `from` to the addresses
`recipients`.  Signals on failure; an `smtp-error` that is `smtp-error-permanent-p`
won't succeed if tried again.

*Example:* A mailer is anything with a `send-message` method.  This one, for a staging server, sends everything to one address through another mailer.

```lisp
(defclass staging-mailer ()
  ((inner :initarg :inner :reader inner-mailer)))
(defmethod littoral.mail:send-message ((mailer staging-mailer) from recipients message)
  (declare (ignore recipients))
  (littoral.mail:send-message (inner-mailer mailer) from '("staging@example.org") message))
(let* ((kept (littoral.mail:make-memory-mailer))
       (littoral.mail:*mailer* (make-instance 'staging-mailer :inner kept)))
  (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :subject "Hello" :text "Hi"))
  (littoral.mail:sent-message-recipients (first (littoral.mail:mailer-messages kept))))
;; ⇒ ("staging@example.org")
```

#### `send-mail` `mail &key (mailer *mailer*)` — function

Send `mail` now with `mailer`, waiting for it, and signal what it signals when
sending fails.  `queue-mail` sends it in the background instead, and tries
again when it fails.

*Example:* A memory mailer keeps what it is given, newest first, so a test can look at what was sent.

```lisp
(let ((mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:send-mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                                    :to "Ada <ada@example.org>" :bcc "orders@example.org"
                                                    :subject "Shipped" :text "On its way.")
                           :mailer mailer)
  (let ((sent (first (littoral.mail:mailer-messages mailer))))
    (list (littoral.mail:sent-message-from sent)
          (littoral.mail:sent-message-recipients sent)
          (littoral.mail:message-header (littoral.mail:sent-message-text sent) "Subject")
          (integerp (littoral.mail:sent-message-time sent)))))
;; ⇒ ("shop@example.org" ("ada@example.org" "orders@example.org") "Shipped" T)
```

#### `smtp-mailer` — class

Sends mail through an SMTP server: `make-smtp-mailer` makes one.

*Example:* Making a mailer doesn't connect: it connects when it first sends, over STARTTLS on port 587 unless told otherwise.

```lisp
(littoral.mail:make-smtp-mailer :host "smtp.example.org" :username "app" :password "secret")
;; ⇒ #<LITTORAL.MAIL:SMTP-MAILER smtp.example.org:587 starttls>
(littoral.mail:make-smtp-mailer :host "smtp.example.org" :security :tls :pool-size nil)
;; ⇒ #<LITTORAL.MAIL:SMTP-MAILER smtp.example.org:465 tls>
```

#### `make-smtp-mailer` `&key (host "localhost") port (security :starttls) username password (helo (machine-instance)) (verify t) ca-file (timeout 30) allow-insecure-auth dkim (pool-size 2)` — function

A mailer sending through the SMTP server at `host`.  `security` is `:starttls`
(port 587 by default), `:tls` (465) or `:none` (25, for a relay on this machine).
With `username`, signs in with the strongest `auth` method the server offers;
without TLS only when `allow-insecure-auth` is true.  The server's certificate
is checked against the system's authorities, or `ca-file`'s, unless `verify` is `nil`.
`helo` is the name it gives the server (this machine's).  `timeout`, in seconds,
bounds connecting and each step of the conversation.
DKIM, a signer from SMTP/`dkim:make-dkim-signer` or a list of them (`rsa` and
Ed25519, say), signs each message as it is sent.  Up to `pool-size`
connections are kept open and reused, so a batch of mail doesn't connect
for each message; `nil` connects for each one.

*Example:* Making a mailer doesn't connect: it connects when it first sends, over STARTTLS on port 587 unless told otherwise.

```lisp
(littoral.mail:make-smtp-mailer :host "smtp.example.org" :username "app" :password "secret")
;; ⇒ #<LITTORAL.MAIL:SMTP-MAILER smtp.example.org:587 starttls>
(littoral.mail:make-smtp-mailer :host "smtp.example.org" :security :tls :pool-size nil)
;; ⇒ #<LITTORAL.MAIL:SMTP-MAILER smtp.example.org:465 tls>
```

#### `smtp-mailer-from-url` `url &rest options` — function

A mailer from URL: smtp://user:password@host:port (STARTTLS), smtps://… (TLS)
or smtp+insecure://… (neither); the user name and password are URL-decoded,
and the port defaults as `make-smtp-mailer`'s does.  `options` go to
`make-smtp-mailer`.  Signals an error for any other scheme.

*Example:* The scheme says how to connect: smtp (STARTTLS), smtps (TLS) or smtp+insecure (neither).  The user name and password are URL-decoded.

```lisp
(littoral.mail:smtp-mailer-from-url "smtps://app:s%40cret@smtp.example.org")
;; ⇒ #<LITTORAL.MAIL:SMTP-MAILER smtp.example.org:465 tls>
(littoral.mail:smtp-mailer-from-url "smtp+insecure://localhost:2525" :timeout 5)
;; ⇒ #<LITTORAL.MAIL:SMTP-MAILER localhost:2525 none>
```

#### `smtp-error` — condition

The root of every condition this library signals.

*Example:* A server's refusal is an `smtp-error` with its reply code; a 5xx refusal is permanent, so trying again won't help.  (Tests make a refusal with the smtp library's `make-reply`.)

```lisp
(defclass refusing-mailer () ((code :initarg :code :reader refusal-code)))
(defmethod littoral.mail:send-message ((mailer refusing-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error (if (>= (refusal-code mailer) 500) 'smtp:smtp-permanent-error 'smtp:smtp-transient-error)
         :reply (smtp::make-reply (refusal-code mailer) '("Refused"))))
(flet ((try (code)
         (handler-case (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hi")
                                                :mailer (make-instance 'refusing-mailer :code code))
           (littoral.mail:smtp-error (e)
             (list (littoral.mail:smtp-error-code e) (littoral.mail:smtp-error-permanent-p e))))))
  (list (try 550) (try 421)))
;; ⇒ ((550 T) (421 NIL))
```

#### `smtp-error-code` `condition` — function

The server's reply code in `condition`, such as 550, or `nil` when the
conversation itself failed.  When recipients were refused, the first refusal's.

*Example:* A server's refusal is an `smtp-error` with its reply code; a 5xx refusal is permanent, so trying again won't help.  (Tests make a refusal with the smtp library's `make-reply`.)

```lisp
(defclass refusing-mailer () ((code :initarg :code :reader refusal-code)))
(defmethod littoral.mail:send-message ((mailer refusing-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error (if (>= (refusal-code mailer) 500) 'smtp:smtp-permanent-error 'smtp:smtp-transient-error)
         :reply (smtp::make-reply (refusal-code mailer) '("Refused"))))
(flet ((try (code)
         (handler-case (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hi")
                                                :mailer (make-instance 'refusing-mailer :code code))
           (littoral.mail:smtp-error (e)
             (list (littoral.mail:smtp-error-code e) (littoral.mail:smtp-error-permanent-p e))))))
  (list (try 550) (try 421)))
;; ⇒ ((550 T) (421 NIL))
```

*Example:* A mail that can't be sent as it is fails for good too, though no server replied.

```lisp
(handler-case (littoral.mail:address-spec "not an address")
  (littoral.mail:smtp-error (e)
    (list (littoral.mail:smtp-error-code e) (littoral.mail:smtp-error-permanent-p e))))
;; ⇒ (NIL T)
```

#### `smtp-error-permanent-p` `condition` — function

True when trying `condition`'s mail again won't change anything: a refusal
(a 5xx reply, or every recipient refused with one), or a mail that can't be
sent as it is.

*Example:* A server's refusal is an `smtp-error` with its reply code; a 5xx refusal is permanent, so trying again won't help.  (Tests make a refusal with the smtp library's `make-reply`.)

```lisp
(defclass refusing-mailer () ((code :initarg :code :reader refusal-code)))
(defmethod littoral.mail:send-message ((mailer refusing-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error (if (>= (refusal-code mailer) 500) 'smtp:smtp-permanent-error 'smtp:smtp-transient-error)
         :reply (smtp::make-reply (refusal-code mailer) '("Refused"))))
(flet ((try (code)
         (handler-case (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hi")
                                                :mailer (make-instance 'refusing-mailer :code code))
           (littoral.mail:smtp-error (e)
             (list (littoral.mail:smtp-error-code e) (littoral.mail:smtp-error-permanent-p e))))))
  (list (try 550) (try 421)))
;; ⇒ ((550 T) (421 NIL))
```

*Example:* A mail that can't be sent as it is fails for good too, though no server replied.

```lisp
(handler-case (littoral.mail:address-spec "not an address")
  (littoral.mail:smtp-error (e)
    (list (littoral.mail:smtp-error-code e) (littoral.mail:smtp-error-permanent-p e))))
;; ⇒ (NIL T)
```

#### `log-mailer` — class

Prints each message's addresses, subject and text, instead of sending it,
to its `:stream`, or else `*error-output*`.

*Example:* The default mailer prints each mail instead of sending it, to `*error-output*` unless given a `:stream`.

```lisp
(uiop:split-string
 (with-output-to-string (out)
   (littoral.mail:send-mail (littoral.mail:make-mail :from "shop@example.org" :to "ada@example.org"
                                                     :subject "Shipped" :text "On its way.")
                            :mailer (make-instance 'littoral.mail:log-mailer :stream out)))
 :separator '(#\Newline))
;; ⇒ ("--- mail from shop@example.org to ada@example.org: Shipped" "On its way." "---" "")
```

#### `memory-mailer` — class

Keeps the messages it is given, newest first, instead of sending them.

*Example:* A memory mailer keeps what it is given, newest first, so a test can look at what was sent.

```lisp
(let ((mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:send-mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                                    :to "Ada <ada@example.org>" :bcc "orders@example.org"
                                                    :subject "Shipped" :text "On its way.")
                           :mailer mailer)
  (let ((sent (first (littoral.mail:mailer-messages mailer))))
    (list (littoral.mail:sent-message-from sent)
          (littoral.mail:sent-message-recipients sent)
          (littoral.mail:message-header (littoral.mail:sent-message-text sent) "Subject")
          (integerp (littoral.mail:sent-message-time sent)))))
;; ⇒ ("shop@example.org" ("ada@example.org" "orders@example.org") "Shipped" T)
```

#### `make-memory-mailer` `&key (keep 50)` — function

A mailer that keeps the last `keep` messages, for tests and demos.

*Example:* A memory mailer keeps what it is given, newest first, so a test can look at what was sent.

```lisp
(let ((mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:send-mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                                    :to "Ada <ada@example.org>" :bcc "orders@example.org"
                                                    :subject "Shipped" :text "On its way.")
                           :mailer mailer)
  (let ((sent (first (littoral.mail:mailer-messages mailer))))
    (list (littoral.mail:sent-message-from sent)
          (littoral.mail:sent-message-recipients sent)
          (littoral.mail:message-header (littoral.mail:sent-message-text sent) "Subject")
          (integerp (littoral.mail:sent-message-time sent)))))
;; ⇒ ("shop@example.org" ("ada@example.org" "orders@example.org") "Shipped" T)
```

#### `mailer-messages` `mailer` — function

The messages `mailer` (a `memory-mailer`) has kept, newest first.

*Example:* A memory mailer keeps what it is given, newest first, so a test can look at what was sent.

```lisp
(let ((mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:send-mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                                    :to "Ada <ada@example.org>" :bcc "orders@example.org"
                                                    :subject "Shipped" :text "On its way.")
                           :mailer mailer)
  (let ((sent (first (littoral.mail:mailer-messages mailer))))
    (list (littoral.mail:sent-message-from sent)
          (littoral.mail:sent-message-recipients sent)
          (littoral.mail:message-header (littoral.mail:sent-message-text sent) "Subject")
          (integerp (littoral.mail:sent-message-time sent)))))
;; ⇒ ("shop@example.org" ("ada@example.org" "orders@example.org") "Shipped" T)
```

#### `clear-mailer` `mailer` — function

Forget the messages `mailer` (a `memory-mailer`) has kept.

*Example:* `send-mail` uses `*mailer*` unless given one.

```lisp
(let ((littoral.mail:*mailer* (littoral.mail:make-memory-mailer :keep 10)))
  (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :text "One"))
  (littoral.mail:send-mail (littoral.mail:make-mail :to "bob@example.org" :text "Two"))
  (list (length (littoral.mail:mailer-messages littoral.mail:*mailer*))
        (progn (littoral.mail:clear-mailer littoral.mail:*mailer*)
               (littoral.mail:mailer-messages littoral.mail:*mailer*))))
;; ⇒ (2 NIL)
```

#### `sent-message` — class

A message a `memory-mailer` was given.

*Example:* A memory mailer keeps what it is given, newest first, so a test can look at what was sent.

```lisp
(let ((mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:send-mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                                    :to "Ada <ada@example.org>" :bcc "orders@example.org"
                                                    :subject "Shipped" :text "On its way.")
                           :mailer mailer)
  (let ((sent (first (littoral.mail:mailer-messages mailer))))
    (list (littoral.mail:sent-message-from sent)
          (littoral.mail:sent-message-recipients sent)
          (littoral.mail:message-header (littoral.mail:sent-message-text sent) "Subject")
          (integerp (littoral.mail:sent-message-time sent)))))
;; ⇒ ("shop@example.org" ("ada@example.org" "orders@example.org") "Shipped" T)
```

#### `sent-message-from` `object` — generic function

Reads the from of a sent-message.  The envelope's sender, a bare address.

*Example:* A memory mailer keeps what it is given, newest first, so a test can look at what was sent.

```lisp
(let ((mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:send-mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                                    :to "Ada <ada@example.org>" :bcc "orders@example.org"
                                                    :subject "Shipped" :text "On its way.")
                           :mailer mailer)
  (let ((sent (first (littoral.mail:mailer-messages mailer))))
    (list (littoral.mail:sent-message-from sent)
          (littoral.mail:sent-message-recipients sent)
          (littoral.mail:message-header (littoral.mail:sent-message-text sent) "Subject")
          (integerp (littoral.mail:sent-message-time sent)))))
;; ⇒ ("shop@example.org" ("ada@example.org" "orders@example.org") "Shipped" T)
```

#### `sent-message-recipients` `object` — generic function

Reads the recipients of a sent-message.  The envelope's recipients, bare addresses, Bcc included.

*Example:* A memory mailer keeps what it is given, newest first, so a test can look at what was sent.

```lisp
(let ((mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:send-mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                                    :to "Ada <ada@example.org>" :bcc "orders@example.org"
                                                    :subject "Shipped" :text "On its way.")
                           :mailer mailer)
  (let ((sent (first (littoral.mail:mailer-messages mailer))))
    (list (littoral.mail:sent-message-from sent)
          (littoral.mail:sent-message-recipients sent)
          (littoral.mail:message-header (littoral.mail:sent-message-text sent) "Subject")
          (integerp (littoral.mail:sent-message-time sent)))))
;; ⇒ ("shop@example.org" ("ada@example.org" "orders@example.org") "Shipped" T)
```

#### `sent-message-text` `object` — generic function

Reads the text of a sent-message.  The MIME message.

*Example:* A memory mailer keeps what it is given, newest first, so a test can look at what was sent.

```lisp
(let ((mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:send-mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                                    :to "Ada <ada@example.org>" :bcc "orders@example.org"
                                                    :subject "Shipped" :text "On its way.")
                           :mailer mailer)
  (let ((sent (first (littoral.mail:mailer-messages mailer))))
    (list (littoral.mail:sent-message-from sent)
          (littoral.mail:sent-message-recipients sent)
          (littoral.mail:message-header (littoral.mail:sent-message-text sent) "Subject")
          (integerp (littoral.mail:sent-message-time sent)))))
;; ⇒ ("shop@example.org" ("ada@example.org" "orders@example.org") "Shipped" T)
```

#### `sent-message-time` `object` — generic function

Reads the time of a sent-message.  When the mailer was given it, a universal time.

*Example:* A memory mailer keeps what it is given, newest first, so a test can look at what was sent.

```lisp
(let ((mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:send-mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                                    :to "Ada <ada@example.org>" :bcc "orders@example.org"
                                                    :subject "Shipped" :text "On its way.")
                           :mailer mailer)
  (let ((sent (first (littoral.mail:mailer-messages mailer))))
    (list (littoral.mail:sent-message-from sent)
          (littoral.mail:sent-message-recipients sent)
          (littoral.mail:message-header (littoral.mail:sent-message-text sent) "Subject")
          (integerp (littoral.mail:sent-message-time sent)))))
;; ⇒ ("shop@example.org" ("ada@example.org" "orders@example.org") "Shipped" T)
```

### Templates

#### `define-mail` `name lambda-list &key to cc bcc from reply-to subject text html attachments headers` — macro

Define `name`, a function of `lambda-list` making a mail.  The keyword forms are
evaluated each time, with `lambda-list`'s variables bound, and given to
`make-mail` (`from` defaults to `*mail-from*`).  HTML is a list of forms written
with Littoral's HTML tags (as in `render`), inside `*mail-layout*`.  Without
`text`, the plain text is made from the HTML.

*Example:* A template is a function making a mail.  Its HTML is written with the tags `render` uses, so text is escaped; the plain-text body is made from it.

```lisp
(littoral.mail:define-mail welcome-mail (name address)
  :to (format nil "~A <~A>" name address)
  :subject (format nil "Welcome, ~A" name)
  :html ((p () "Hello " (strong () (text name)) ",")
         (p () (anchor (:href "https://example.org/start") "Get started"))))
(let ((mail (welcome-mail "Ada" "ada@example.org")))
  (list (littoral.mail:mail-to mail)
        (littoral.mail:mail-subject mail)
        (uiop:split-string (littoral.mail:mail-text mail) :separator '(#\Newline))
        (not (null (search "<strong>Ada</strong>" (littoral.mail:mail-html mail))))))
;; ⇒ (("Ada <ada@example.org>") "Welcome, Ada" ("Hello Ada," "" "Get started (https://example.org/start)") T)
```

#### `*mail-layout*` — variable

A function of (`subject` `body-thunk`) that writes the HTML around a template's content.

*Example:* A layout of its own adds a footer to every template's mail, inside the default layout.

```lisp
(littoral.mail:define-mail shipped-mail (address)
  :to address
  :subject "Your order has shipped"
  :html ((p () "It should arrive on Friday.")))
(let ((littoral.mail:*mail-layout*
        (lambda (subject body)
          (littoral.mail:default-mail-layout
           subject
           (lambda ()
             (funcall body)
             (p (:class "footer") "Bookshop, 1 High Street"))))))
  (let ((mail (shipped-mail "ada@example.org")))
    (list (uiop:split-string (littoral.mail:mail-text mail) :separator '(#\Newline))
          (not (null (search "<title>Your order has shipped</title>" (littoral.mail:mail-html mail)))))))
;; ⇒ (("It should arrive on Friday." "" "Bookshop, 1 High Street") T)
```

#### `default-mail-layout` `subject body` — function

Write an HTML mail around `body`, a thunk writing its content: a plain,
readable page that mail programs show well.

*Example:* A layout of its own adds a footer to every template's mail, inside the default layout.

```lisp
(littoral.mail:define-mail shipped-mail (address)
  :to address
  :subject "Your order has shipped"
  :html ((p () "It should arrive on Friday.")))
(let ((littoral.mail:*mail-layout*
        (lambda (subject body)
          (littoral.mail:default-mail-layout
           subject
           (lambda ()
             (funcall body)
             (p (:class "footer") "Bookshop, 1 High Street"))))))
  (let ((mail (shipped-mail "ada@example.org")))
    (list (uiop:split-string (littoral.mail:mail-text mail) :separator '(#\Newline))
          (not (null (search "<title>Your order has shipped</title>" (littoral.mail:mail-html mail)))))))
;; ⇒ (("It should arrive on Friday." "" "Bookshop, 1 High Street") T)
```

#### `html-to-text` `html` — function

A plain-text version of HTML: paragraphs and line breaks kept, links
written out after their text, tags dropped, entities decoded.

*Example:* Paragraphs and list items become lines; links are written out after their text.

```lisp
(uiop:split-string
 (littoral.mail:html-to-text
  "<h1>Hello <b>Ada</b></h1><ul><li>One book</li><li>Two pens</li></ul><p><a href=\"https://example.org/orders/42\">Your order</a> &amp; its invoice.</p>")
 :separator '(#\Newline))
;; ⇒ ("Hello Ada" "" "- One book" "- Two pens" "" "Your order (https://example.org/orders/42) & its invoice.")
```

### The outbox

#### `outbox-mail` — class

A message in the outbox, and how sending it has gone.

*Example:* What the outbox keeps of a message: the envelope, the MIME message itself, and when it was queued and sent.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail
          (littoral.mail:make-mail :from "Shop <shop@example.org>" :to "Ada <ada@example.org>"
                                   :cc "bob@example.org" :subject "Your order" :text "Shipped."))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (integerp (littoral.mail:outbox-id row))
                 (littoral.mail:outbox-sender-address row)
                 (littoral.mail:outbox-recipients row)
                 (littoral.mail:outbox-subject row)
                 (littoral.mail:message-header (littoral.mail:outbox-message row) "To")
                 (<= (littoral.mail:outbox-created row) (littoral.mail:outbox-sent row) (get-universal-time))
                 (integerp (littoral.mail:outbox-next-attempt row)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T "shop@example.org" "ada@example.org bob@example.org" "Your order" "Ada <ada@example.org>" T T)
```

#### `create-mail-tables` — function

Create or bring up to date the outbox table (migrations `:littoral-mail`),
and the job queue that sends it.

*Example:* Queued mail waits in the outbox until it is delivered; a test can deliver it at once.  Dropping the tables (and the job queue `create-mail-tables` made) puts things back as they were.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((row (littoral.mail:queue-mail
                   (littoral.mail:make-mail :to "ada@example.org" :subject "Welcome" :text "Hello, Ada."))))
         (list (littoral.mail:outbox-status row)
               (littoral.mail:deliver-queued-mail :mailer mailer)
               (littoral.mail:outbox-status (first (littoral.mail:outbox-messages)))
               (length (littoral.mail:mailer-messages mailer))
               (littoral.mail:deliver-queued-mail :mailer mailer)))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "sent" 1 0)
```

#### `drop-mail-tables` — function

Drop the outbox table.  The job queue `create-mail-tables` made stays:
`littoral.jobs:drop-job-tables` drops it.

*Example:* Queued mail waits in the outbox until it is delivered; a test can deliver it at once.  Dropping the tables (and the job queue `create-mail-tables` made) puts things back as they were.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((row (littoral.mail:queue-mail
                   (littoral.mail:make-mail :to "ada@example.org" :subject "Welcome" :text "Hello, Ada."))))
         (list (littoral.mail:outbox-status row)
               (littoral.mail:deliver-queued-mail :mailer mailer)
               (littoral.mail:outbox-status (first (littoral.mail:outbox-messages)))
               (length (littoral.mail:mailer-messages mailer))
               (littoral.mail:deliver-queued-mail :mailer mailer)))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "sent" 1 0)
```

#### `queue-mail` `mail` — function

Put `mail` in the outbox, in the current database, with a job to send it;
returns its `outbox-mail`.

*Example:* Queued mail waits in the outbox until it is delivered; a test can deliver it at once.  Dropping the tables (and the job queue `create-mail-tables` made) puts things back as they were.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((row (littoral.mail:queue-mail
                   (littoral.mail:make-mail :to "ada@example.org" :subject "Welcome" :text "Hello, Ada."))))
         (list (littoral.mail:outbox-status row)
               (littoral.mail:deliver-queued-mail :mailer mailer)
               (littoral.mail:outbox-status (first (littoral.mail:outbox-messages)))
               (length (littoral.mail:mailer-messages mailer))
               (littoral.mail:deliver-queued-mail :mailer mailer)))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "sent" 1 0)
```

*Example:* Mail queued in a transaction is kept only if the transaction commits.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (ignore-errors
          (littoral.db:with-transaction ()
            (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "Your order"))
            (error "The order couldn't be saved.")))
         (littoral.mail:outbox-messages))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ NIL
```

#### `outbox-sender` `&key (from *mail-from*)` — function

A function of (`to` `subject` `body`) that queues a plain-text mail, for
`littoral.auth:*send-mail*`.

*Example:* A function that queues plain-text mail, as `littoral.auth:*send-mail*` wants for password resets.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (send (littoral.mail:outbox-sender :from "Shop <shop@example.org>")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((row (funcall send "ada@example.org" "Reset your password" "Follow this link.")))
         (list (littoral.mail:outbox-sender-address row)
               (littoral.mail:outbox-recipients row)
               (littoral.mail:outbox-subject row)
               (littoral.mail:outbox-status row)))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("shop@example.org" "ada@example.org" "Reset your password" "queued")
```

#### `deliver-queued-mail` `&key (mailer (delivery-mailer)) (limit 50)` — function

Send at most `limit` messages in the current database's outbox that are due,
with `mailer` (by default `start-mail-delivery`'s, or else `*mailer*`); returns how
many were sent.  A failure is recorded and tried again later, as by the job
runner.  Their jobs do this one at a time; a test can call it to send what's
queued without waiting.

*Example:* Queued mail waits in the outbox until it is delivered; a test can deliver it at once.  Dropping the tables (and the job queue `create-mail-tables` made) puts things back as they were.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((row (littoral.mail:queue-mail
                   (littoral.mail:make-mail :to "ada@example.org" :subject "Welcome" :text "Hello, Ada."))))
         (list (littoral.mail:outbox-status row)
               (littoral.mail:deliver-queued-mail :mailer mailer)
               (littoral.mail:outbox-status (first (littoral.mail:outbox-messages)))
               (length (littoral.mail:mailer-messages mailer))
               (littoral.mail:deliver-queued-mail :mailer mailer)))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "sent" 1 0)
```

#### `start-mail-delivery` `&key (database *database*) (mailer *mailer*) (interval 10) (attempts *mail-attempts*) (retry-seconds *mail-retry-seconds*)` — function

Send the outbox of `database` (a spec, as `littoral.db:*database*` holds) with
`mailer`.  The job runner (`littoral`.JOBS) sends it, at once when mail is queued
in this process, and within `interval` seconds for retries and other processes'
mail; this starts one for `database` unless one is running.  `attempts` and
`retry-seconds` set `*mail-attempts*` and `*mail-retry-seconds*`.

*Example:* Delivery in the background, by a job runner thread.  That thread has its own connection, so the database is a file here rather than ":memory:".

```lisp
(let* ((file (merge-pathnames (format nil "outbox-~36R.sqlite3" (random (expt 36 8))) (uiop:temporary-directory)))
       (littoral.db:*database* (list :sqlite3 :database-name (namestring file)))
       (mailer (littoral.mail:make-memory-mailer)))
  (unwind-protect
       (progn
         (littoral.mail:create-mail-tables)
         (littoral.mail:start-mail-delivery :mailer mailer :interval 1)
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :subject "Soon" :text "Hello"))
         (loop repeat 50 until (littoral.mail:mailer-messages mailer) do (sleep 0.1))
         (list (littoral.mail:mail-delivery-running-p)
               (length (littoral.mail:mailer-messages mailer))
               (progn (littoral.mail:stop-mail-delivery)
                      (littoral.mail:mail-delivery-running-p))))
    (littoral.mail:stop-mail-delivery)
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string (namestring file) suffix)))))
;; ⇒ (T 1 NIL)
```

#### `stop-mail-delivery` — function

Stop sending mail: the job runner too, if `start-mail-delivery` started it,
letting it finish the message it is sending.  An `smtp-mailer`'s open
connections are closed.

*Example:* Delivery in the background, by a job runner thread.  That thread has its own connection, so the database is a file here rather than ":memory:".

```lisp
(let* ((file (merge-pathnames (format nil "outbox-~36R.sqlite3" (random (expt 36 8))) (uiop:temporary-directory)))
       (littoral.db:*database* (list :sqlite3 :database-name (namestring file)))
       (mailer (littoral.mail:make-memory-mailer)))
  (unwind-protect
       (progn
         (littoral.mail:create-mail-tables)
         (littoral.mail:start-mail-delivery :mailer mailer :interval 1)
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :subject "Soon" :text "Hello"))
         (loop repeat 50 until (littoral.mail:mailer-messages mailer) do (sleep 0.1))
         (list (littoral.mail:mail-delivery-running-p)
               (length (littoral.mail:mailer-messages mailer))
               (progn (littoral.mail:stop-mail-delivery)
                      (littoral.mail:mail-delivery-running-p))))
    (littoral.mail:stop-mail-delivery)
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string (namestring file) suffix)))))
;; ⇒ (T 1 NIL)
```

#### `mail-delivery-running-p` — function

True while `start-mail-delivery`'s mailer is set and a job runner runs.

*Example:* Delivery in the background, by a job runner thread.  That thread has its own connection, so the database is a file here rather than ":memory:".

```lisp
(let* ((file (merge-pathnames (format nil "outbox-~36R.sqlite3" (random (expt 36 8))) (uiop:temporary-directory)))
       (littoral.db:*database* (list :sqlite3 :database-name (namestring file)))
       (mailer (littoral.mail:make-memory-mailer)))
  (unwind-protect
       (progn
         (littoral.mail:create-mail-tables)
         (littoral.mail:start-mail-delivery :mailer mailer :interval 1)
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :subject "Soon" :text "Hello"))
         (loop repeat 50 until (littoral.mail:mailer-messages mailer) do (sleep 0.1))
         (list (littoral.mail:mail-delivery-running-p)
               (length (littoral.mail:mailer-messages mailer))
               (progn (littoral.mail:stop-mail-delivery)
                      (littoral.mail:mail-delivery-running-p))))
    (littoral.mail:stop-mail-delivery)
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string (namestring file) suffix)))))
;; ⇒ (T 1 NIL)
```

#### `outbox-messages` `&key status (limit 50)` — function

The outbox's messages, newest first; only those with `status` (a string) if given.

*Example:* Queued mail waits in the outbox until it is delivered; a test can deliver it at once.  Dropping the tables (and the job queue `create-mail-tables` made) puts things back as they were.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((row (littoral.mail:queue-mail
                   (littoral.mail:make-mail :to "ada@example.org" :subject "Welcome" :text "Hello, Ada."))))
         (list (littoral.mail:outbox-status row)
               (littoral.mail:deliver-queued-mail :mailer mailer)
               (littoral.mail:outbox-status (first (littoral.mail:outbox-messages)))
               (length (littoral.mail:mailer-messages mailer))
               (littoral.mail:deliver-queued-mail :mailer mailer)))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "sent" 1 0)
```

*Example:* `outbox-messages` can pick out one status; `purge-sent-mail` deletes sent mail once it is a week old.

```lisp
(defclass unreachable-mailer () ())
(defmethod littoral.mail:send-message ((mailer unreachable-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error "Connection refused"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :subject "First" :text "1"))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "bob@example.org" :subject "Second" :text "2"))
         (littoral.mail:deliver-queued-mail :mailer (make-instance 'unreachable-mailer))
         (list (mapcar #'littoral.mail:outbox-subject (littoral.mail:outbox-messages))
               (mapcar #'littoral.mail:outbox-subject (littoral.mail:outbox-messages :status "sent"))
               (littoral.mail:purge-sent-mail)
               (progn
                 ;; As if it had been sent a month ago.
                 (littoral.db:db-execute "UPDATE mail_outbox SET sent = sent - 2592000 WHERE status = 'sent'")
                 (littoral.mail:purge-sent-mail))
               (mapcar #'littoral.mail:outbox-subject (littoral.mail:outbox-messages))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (("Second" "First") ("First") 0 1 ("Second"))
```

#### `retry-mail` `id` — function

Send the message `id` again now, with its attempts counted afresh, unless it
was sent.

*Example:* A failure that may pass leaves the message queued for a later try; `retry-mail` makes it due now.

```lisp
(defclass unreachable-mailer () ())
(defmethod littoral.mail:send-message ((mailer unreachable-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error "Connection refused"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((id (littoral.mail:outbox-id
                  (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hello")))))
         (littoral.mail:deliver-queued-mail :mailer (make-instance 'unreachable-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (littoral.mail:outbox-status row)
                 (littoral.mail:outbox-attempts row)
                 (littoral.mail:outbox-last-error row)
                 (> (littoral.mail:outbox-next-attempt row) (get-universal-time))
                 (progn (littoral.mail:retry-mail id)
                        (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer)))
                 (littoral.mail:outbox-status (first (littoral.mail:outbox-messages))))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "Connection refused" T 1 "sent")
```

#### `purge-sent-mail` `&key (older-than (* 7 24 3600))` — function

Delete sent messages more than `older-than` seconds old; returns how many.

*Example:* `outbox-messages` can pick out one status; `purge-sent-mail` deletes sent mail once it is a week old.

```lisp
(defclass unreachable-mailer () ())
(defmethod littoral.mail:send-message ((mailer unreachable-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error "Connection refused"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :subject "First" :text "1"))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "bob@example.org" :subject "Second" :text "2"))
         (littoral.mail:deliver-queued-mail :mailer (make-instance 'unreachable-mailer))
         (list (mapcar #'littoral.mail:outbox-subject (littoral.mail:outbox-messages))
               (mapcar #'littoral.mail:outbox-subject (littoral.mail:outbox-messages :status "sent"))
               (littoral.mail:purge-sent-mail)
               (progn
                 ;; As if it had been sent a month ago.
                 (littoral.db:db-execute "UPDATE mail_outbox SET sent = sent - 2592000 WHERE status = 'sent'")
                 (littoral.mail:purge-sent-mail))
               (mapcar #'littoral.mail:outbox-subject (littoral.mail:outbox-messages))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (("Second" "First") ("First") 0 1 ("Second"))
```

#### `*mail-attempts*` — variable

Times a message is tried before it is marked failed.

*Example:* A message is tried `*mail-attempts*` times, waiting `*mail-retry-seconds*` after the first failure and twice as long after each one since.

```lisp
(defclass unreachable-mailer () ())
(defmethod littoral.mail:send-message ((mailer unreachable-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error "Connection refused"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.mail:*mail-attempts* 2)
      (littoral.mail:*mail-retry-seconds* 300))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (flet ((try ()
                (littoral.mail:deliver-queued-mail :mailer (make-instance 'unreachable-mailer))
                (let ((row (first (littoral.mail:outbox-messages))))
                  (list (littoral.mail:outbox-status row)
                        (- (littoral.mail:outbox-next-attempt row) (get-universal-time))))))
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hello"))
         (let ((first-try (try)))
           ;; As if the wait were over.
           (littoral.db:db-execute "UPDATE mail_outbox SET next_attempt = 0")
           (list (first first-try) (<= 299 (second first-try) 300) (first (try)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" T "failed")
```

#### `*mail-retry-seconds*` — variable

Seconds before a failed message is tried again, doubling with each attempt.

*Example:* A message is tried `*mail-attempts*` times, waiting `*mail-retry-seconds*` after the first failure and twice as long after each one since.

```lisp
(defclass unreachable-mailer () ())
(defmethod littoral.mail:send-message ((mailer unreachable-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error "Connection refused"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.mail:*mail-attempts* 2)
      (littoral.mail:*mail-retry-seconds* 300))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (flet ((try ()
                (littoral.mail:deliver-queued-mail :mailer (make-instance 'unreachable-mailer))
                (let ((row (first (littoral.mail:outbox-messages))))
                  (list (littoral.mail:outbox-status row)
                        (- (littoral.mail:outbox-next-attempt row) (get-universal-time))))))
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hello"))
         (let ((first-try (try)))
           ;; As if the wait were over.
           (littoral.db:db-execute "UPDATE mail_outbox SET next_attempt = 0")
           (list (first first-try) (<= 299 (second first-try) 300) (first (try)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" T "failed")
```

#### `outbox-id` `message` — function

`message`'s id in the outbox, for `retry-mail`.

*Example:* What the outbox keeps of a message: the envelope, the MIME message itself, and when it was queued and sent.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail
          (littoral.mail:make-mail :from "Shop <shop@example.org>" :to "Ada <ada@example.org>"
                                   :cc "bob@example.org" :subject "Your order" :text "Shipped."))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (integerp (littoral.mail:outbox-id row))
                 (littoral.mail:outbox-sender-address row)
                 (littoral.mail:outbox-recipients row)
                 (littoral.mail:outbox-subject row)
                 (littoral.mail:message-header (littoral.mail:outbox-message row) "To")
                 (<= (littoral.mail:outbox-created row) (littoral.mail:outbox-sent row) (get-universal-time))
                 (integerp (littoral.mail:outbox-next-attempt row)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T "shop@example.org" "ada@example.org bob@example.org" "Your order" "Ada <ada@example.org>" T T)
```

#### `outbox-sender-address` `object` — generic function

Reads the sender of an outbox-mail.  The envelope's sender, a bare address.

*Example:* What the outbox keeps of a message: the envelope, the MIME message itself, and when it was queued and sent.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail
          (littoral.mail:make-mail :from "Shop <shop@example.org>" :to "Ada <ada@example.org>"
                                   :cc "bob@example.org" :subject "Your order" :text "Shipped."))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (integerp (littoral.mail:outbox-id row))
                 (littoral.mail:outbox-sender-address row)
                 (littoral.mail:outbox-recipients row)
                 (littoral.mail:outbox-subject row)
                 (littoral.mail:message-header (littoral.mail:outbox-message row) "To")
                 (<= (littoral.mail:outbox-created row) (littoral.mail:outbox-sent row) (get-universal-time))
                 (integerp (littoral.mail:outbox-next-attempt row)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T "shop@example.org" "ada@example.org bob@example.org" "Your order" "Ada <ada@example.org>" T T)
```

#### `outbox-recipients` `object` — generic function

Reads the recipients of an outbox-mail.  The addresses it goes to, separated by spaces.

*Example:* What the outbox keeps of a message: the envelope, the MIME message itself, and when it was queued and sent.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail
          (littoral.mail:make-mail :from "Shop <shop@example.org>" :to "Ada <ada@example.org>"
                                   :cc "bob@example.org" :subject "Your order" :text "Shipped."))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (integerp (littoral.mail:outbox-id row))
                 (littoral.mail:outbox-sender-address row)
                 (littoral.mail:outbox-recipients row)
                 (littoral.mail:outbox-subject row)
                 (littoral.mail:message-header (littoral.mail:outbox-message row) "To")
                 (<= (littoral.mail:outbox-created row) (littoral.mail:outbox-sent row) (get-universal-time))
                 (integerp (littoral.mail:outbox-next-attempt row)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T "shop@example.org" "ada@example.org bob@example.org" "Your order" "Ada <ada@example.org>" T T)
```

#### `outbox-subject` `object` — generic function

Reads the subject of an outbox-mail.

*Example:* What the outbox keeps of a message: the envelope, the MIME message itself, and when it was queued and sent.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail
          (littoral.mail:make-mail :from "Shop <shop@example.org>" :to "Ada <ada@example.org>"
                                   :cc "bob@example.org" :subject "Your order" :text "Shipped."))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (integerp (littoral.mail:outbox-id row))
                 (littoral.mail:outbox-sender-address row)
                 (littoral.mail:outbox-recipients row)
                 (littoral.mail:outbox-subject row)
                 (littoral.mail:message-header (littoral.mail:outbox-message row) "To")
                 (<= (littoral.mail:outbox-created row) (littoral.mail:outbox-sent row) (get-universal-time))
                 (integerp (littoral.mail:outbox-next-attempt row)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T "shop@example.org" "ada@example.org bob@example.org" "Your order" "Ada <ada@example.org>" T T)
```

#### `outbox-message` `object` — generic function

Reads the message of an outbox-mail.  The MIME message.

*Example:* What the outbox keeps of a message: the envelope, the MIME message itself, and when it was queued and sent.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail
          (littoral.mail:make-mail :from "Shop <shop@example.org>" :to "Ada <ada@example.org>"
                                   :cc "bob@example.org" :subject "Your order" :text "Shipped."))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (integerp (littoral.mail:outbox-id row))
                 (littoral.mail:outbox-sender-address row)
                 (littoral.mail:outbox-recipients row)
                 (littoral.mail:outbox-subject row)
                 (littoral.mail:message-header (littoral.mail:outbox-message row) "To")
                 (<= (littoral.mail:outbox-created row) (littoral.mail:outbox-sent row) (get-universal-time))
                 (integerp (littoral.mail:outbox-next-attempt row)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T "shop@example.org" "ada@example.org bob@example.org" "Your order" "Ada <ada@example.org>" T T)
```

#### `outbox-status` `object` — generic function

Reads the status of an outbox-mail.  "queued", "sending", "sent" or "failed".

*Example:* A failure that may pass leaves the message queued for a later try; `retry-mail` makes it due now.

```lisp
(defclass unreachable-mailer () ())
(defmethod littoral.mail:send-message ((mailer unreachable-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error "Connection refused"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((id (littoral.mail:outbox-id
                  (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hello")))))
         (littoral.mail:deliver-queued-mail :mailer (make-instance 'unreachable-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (littoral.mail:outbox-status row)
                 (littoral.mail:outbox-attempts row)
                 (littoral.mail:outbox-last-error row)
                 (> (littoral.mail:outbox-next-attempt row) (get-universal-time))
                 (progn (littoral.mail:retry-mail id)
                        (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer)))
                 (littoral.mail:outbox-status (first (littoral.mail:outbox-messages))))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "Connection refused" T 1 "sent")
```

#### `outbox-attempts` `object` — generic function

Reads the attempts of an outbox-mail.  Tries so far.

*Example:* A failure that may pass leaves the message queued for a later try; `retry-mail` makes it due now.

```lisp
(defclass unreachable-mailer () ())
(defmethod littoral.mail:send-message ((mailer unreachable-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error "Connection refused"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((id (littoral.mail:outbox-id
                  (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hello")))))
         (littoral.mail:deliver-queued-mail :mailer (make-instance 'unreachable-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (littoral.mail:outbox-status row)
                 (littoral.mail:outbox-attempts row)
                 (littoral.mail:outbox-last-error row)
                 (> (littoral.mail:outbox-next-attempt row) (get-universal-time))
                 (progn (littoral.mail:retry-mail id)
                        (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer)))
                 (littoral.mail:outbox-status (first (littoral.mail:outbox-messages))))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "Connection refused" T 1 "sent")
```

#### `outbox-next-attempt` `object` — generic function

Reads the next-attempt of an outbox-mail.  When it is next due, a universal time.

*Example:* What the outbox keeps of a message: the envelope, the MIME message itself, and when it was queued and sent.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail
          (littoral.mail:make-mail :from "Shop <shop@example.org>" :to "Ada <ada@example.org>"
                                   :cc "bob@example.org" :subject "Your order" :text "Shipped."))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (integerp (littoral.mail:outbox-id row))
                 (littoral.mail:outbox-sender-address row)
                 (littoral.mail:outbox-recipients row)
                 (littoral.mail:outbox-subject row)
                 (littoral.mail:message-header (littoral.mail:outbox-message row) "To")
                 (<= (littoral.mail:outbox-created row) (littoral.mail:outbox-sent row) (get-universal-time))
                 (integerp (littoral.mail:outbox-next-attempt row)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T "shop@example.org" "ada@example.org bob@example.org" "Your order" "Ada <ada@example.org>" T T)
```

#### `outbox-last-error` `object` — generic function

Reads the last-error of an outbox-mail.  Why the last try failed, or `nil`.

*Example:* A failure that may pass leaves the message queued for a later try; `retry-mail` makes it due now.

```lisp
(defclass unreachable-mailer () ())
(defmethod littoral.mail:send-message ((mailer unreachable-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error "Connection refused"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((id (littoral.mail:outbox-id
                  (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hello")))))
         (littoral.mail:deliver-queued-mail :mailer (make-instance 'unreachable-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (littoral.mail:outbox-status row)
                 (littoral.mail:outbox-attempts row)
                 (littoral.mail:outbox-last-error row)
                 (> (littoral.mail:outbox-next-attempt row) (get-universal-time))
                 (progn (littoral.mail:retry-mail id)
                        (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer)))
                 (littoral.mail:outbox-status (first (littoral.mail:outbox-messages))))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "Connection refused" T 1 "sent")
```

#### `outbox-created` `object` — generic function

Reads the created of an outbox-mail.  When it was queued, a universal time.

*Example:* What the outbox keeps of a message: the envelope, the MIME message itself, and when it was queued and sent.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail
          (littoral.mail:make-mail :from "Shop <shop@example.org>" :to "Ada <ada@example.org>"
                                   :cc "bob@example.org" :subject "Your order" :text "Shipped."))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (integerp (littoral.mail:outbox-id row))
                 (littoral.mail:outbox-sender-address row)
                 (littoral.mail:outbox-recipients row)
                 (littoral.mail:outbox-subject row)
                 (littoral.mail:message-header (littoral.mail:outbox-message row) "To")
                 (<= (littoral.mail:outbox-created row) (littoral.mail:outbox-sent row) (get-universal-time))
                 (integerp (littoral.mail:outbox-next-attempt row)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T "shop@example.org" "ada@example.org bob@example.org" "Your order" "Ada <ada@example.org>" T T)
```

#### `outbox-sent` `object` — generic function

Reads the sent of an outbox-mail.  When it was sent, a universal time, or `nil`.

*Example:* What the outbox keeps of a message: the envelope, the MIME message itself, and when it was queued and sent.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail
          (littoral.mail:make-mail :from "Shop <shop@example.org>" :to "Ada <ada@example.org>"
                                   :cc "bob@example.org" :subject "Your order" :text "Shipped."))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (integerp (littoral.mail:outbox-id row))
                 (littoral.mail:outbox-sender-address row)
                 (littoral.mail:outbox-recipients row)
                 (littoral.mail:outbox-subject row)
                 (littoral.mail:message-header (littoral.mail:outbox-message row) "To")
                 (<= (littoral.mail:outbox-created row) (littoral.mail:outbox-sent row) (get-universal-time))
                 (integerp (littoral.mail:outbox-next-attempt row)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T "shop@example.org" "ada@example.org bob@example.org" "Your order" "Ada <ada@example.org>" T T)
```

## Package `littoral.jobs`

Load it with `(asdf:load-system :littoral/jobs)`.  Background jobs kept in the
database: retried, scheduled, and run by any process.

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

*Example:* A job is a name and readable arguments, kept in the job_queue table until a runner runs it; `run-due-jobs` runs what is due here and now.  Its own queue keeps these jobs apart from other code's.

```lisp
(defvar *greeted* '())
(littoral.jobs:define-job (greet :queue "examples") (name)
  (push name *greeted*))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (progn
         (littoral.jobs:enqueue-job (list 'greet "Ada"))
         (littoral.jobs:enqueue-job (list 'greet "Bob"))
         (list (littoral.jobs:run-due-jobs :queues '("examples"))
               *greeted*
               (littoral.jobs:run-due-jobs :queues '("examples"))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (2 ("Bob" "Ada") 0)
```

*Example:* `define-job` also defines a function, which runs the job's body at once.

```lisp
(littoral.jobs:define-job (add-up :queue "examples") (a b)
  (+ a b))
(add-up 2 3)
;; ⇒ 5
```

*Example:* With `:transaction`, a job's database work and its being marked done commit together: a job that fails leaves nothing behind.

```lisp
(littoral.jobs:define-job (record-payment :queue "examples" :transaction t :attempts 1) (amount)
  (littoral.db:db-execute "INSERT INTO payments (amount) VALUES (?)" amount)
  (when (minusp amount)
    (error "A payment can't be negative.")))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (littoral.db:db-execute "CREATE TABLE payments (amount INTEGER)")
  (unwind-protect
       (progn
         (littoral.jobs:enqueue-job (list 'record-payment 10))
         (littoral.jobs:enqueue-job (list 'record-payment -5))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (list (mapcar (lambda (row) (getf row :|amount|))
                       (littoral.db:db-query "SELECT amount FROM payments"))
               (littoral.jobs:durable-job-counts)))
    (littoral.db:db-execute "DROP TABLE payments")
    (littoral.jobs:drop-job-tables)))
;; ⇒ ((10) (("done" . 1) ("failed" . 1)))
```

*Example:* A job defined with `:every` schedules itself: `run-due-jobs` queues its next run, and it can't be enqueued by hand.

```lisp
(littoral.jobs:define-job (nightly-report :queue "examples-nightly" :every (littoral.jobs:daily-at 3)) ()
  t)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (list (littoral.jobs:run-due-jobs :queues '("examples-nightly"))
             (let ((job (first (littoral.jobs:durable-jobs :queue "examples-nightly"))))
               (list (littoral.jobs:durable-job-status job)
                     (nth 2 (multiple-value-list (decode-universal-time (littoral.jobs:durable-job-run-at job))))))
             (handler-case (littoral.jobs:enqueue-job (list 'nightly-report))
               (error () :refused)))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (0 ("queued" 3) :REFUSED)
```

#### `enqueue-job` `call &key at in key queue` — function

Queue `call`, (`name` . `arguments`), in the current database, to run at once,
`in` seconds, or `at` a universal time; its id.  With `key` (a string), nothing is
queued while a job with that key waits untried, and the value is `nil`.  `queue`
overrides the job's own.  Signals an error when `name` isn't a job `define-job`
defined, when it is defined with `:every`, or when `arguments` don't print
readably and read back as themselves.

*Example:* A job is a name and readable arguments, kept in the job_queue table until a runner runs it; `run-due-jobs` runs what is due here and now.  Its own queue keeps these jobs apart from other code's.

```lisp
(defvar *greeted* '())
(littoral.jobs:define-job (greet :queue "examples") (name)
  (push name *greeted*))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (progn
         (littoral.jobs:enqueue-job (list 'greet "Ada"))
         (littoral.jobs:enqueue-job (list 'greet "Bob"))
         (list (littoral.jobs:run-due-jobs :queues '("examples"))
               *greeted*
               (littoral.jobs:run-due-jobs :queues '("examples"))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (2 ("Bob" "Ada") 0)
```

*Example:* `in` delays a job; with `key`, a second job with that key isn't queued while the first waits.

```lisp
(littoral.jobs:define-job (remind :queue "examples") (user-id)
  user-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((first-id (littoral.jobs:enqueue-job (list 'remind 7) :in 3600 :key "remind:7"))
              (second-id (littoral.jobs:enqueue-job (list 'remind 7) :in 3600 :key "remind:7"))
              (job (littoral.jobs:find-durable-job first-id)))
         (list (integerp first-id)
               second-id
               (littoral.jobs:durable-job-key job)
               (<= 3599 (- (littoral.jobs:durable-job-run-at job) (get-universal-time)) 3600)
               (littoral.jobs:run-due-jobs :queues '("examples"))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T NIL "remind:7" T 0)
```

*Example:* Only defined jobs are queued, and only with arguments that print readably: pass ids, not objects.

```lisp
(littoral.jobs:define-job (resize-image :queue "examples") (image-id)
  image-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (flet ((refused-p (call)
                (handler-case (progn (littoral.jobs:enqueue-job call) nil)
                  (error () t))))
         (list (refused-p (list 'resize-image 12))
               (refused-p (list 'resize-image (make-hash-table)))
               (refused-p (list 'no-such-job 12))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (NIL T T)
```

#### `daily-at` `hour &optional (minute 0)` — function

For `:every`: once a day, at `hour:minute` local time.

*Example:* A function from a time to the next `hour:minute` after it, local time.

```lisp
(let ((next (funcall (littoral.jobs:daily-at 3 30) (encode-universal-time 0 0 12 1 6 2026))))
  (subseq (multiple-value-list (decode-universal-time next)) 0 6))
;; ⇒ (0 30 3 2 6 2026)
```

*Example:* A job defined with `:every` schedules itself: `run-due-jobs` queues its next run, and it can't be enqueued by hand.

```lisp
(littoral.jobs:define-job (nightly-report :queue "examples-nightly" :every (littoral.jobs:daily-at 3)) ()
  t)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (list (littoral.jobs:run-due-jobs :queues '("examples-nightly"))
             (let ((job (first (littoral.jobs:durable-jobs :queue "examples-nightly"))))
               (list (littoral.jobs:durable-job-status job)
                     (nth 2 (multiple-value-list (decode-universal-time (littoral.jobs:durable-job-run-at job))))))
             (handler-case (littoral.jobs:enqueue-job (list 'nightly-report))
               (error () :refused)))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (0 ("queued" 3) :REFUSED)
```

#### `create-job-tables` — function

Create or bring up to date the job_queue table (migrations `:littoral-jobs`).

*Example:* A job is a name and readable arguments, kept in the job_queue table until a runner runs it; `run-due-jobs` runs what is due here and now.  Its own queue keeps these jobs apart from other code's.

```lisp
(defvar *greeted* '())
(littoral.jobs:define-job (greet :queue "examples") (name)
  (push name *greeted*))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (progn
         (littoral.jobs:enqueue-job (list 'greet "Ada"))
         (littoral.jobs:enqueue-job (list 'greet "Bob"))
         (list (littoral.jobs:run-due-jobs :queues '("examples"))
               *greeted*
               (littoral.jobs:run-due-jobs :queues '("examples"))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (2 ("Bob" "Ada") 0)
```

#### `drop-job-tables` — function

Drop the job_queue table, and forget it for `job-tables-p`.

*Example:* A job is a name and readable arguments, kept in the job_queue table until a runner runs it; `run-due-jobs` runs what is due here and now.  Its own queue keeps these jobs apart from other code's.

```lisp
(defvar *greeted* '())
(littoral.jobs:define-job (greet :queue "examples") (name)
  (push name *greeted*))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (progn
         (littoral.jobs:enqueue-job (list 'greet "Ada"))
         (littoral.jobs:enqueue-job (list 'greet "Bob"))
         (list (littoral.jobs:run-due-jobs :queues '("examples"))
               *greeted*
               (littoral.jobs:run-due-jobs :queues '("examples"))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (2 ("Bob" "Ada") 0)
```

#### `job-tables-p` — function

True when `create-job-tables` ran for the current database in this process,
as it does through `create-mail-tables`: the admin then shows the job queue.

*Example:* True once `create-job-tables` has run for the current database in this process; the admin then shows its job queue.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (list (littoral.jobs:job-tables-p)
        (progn (littoral.jobs:drop-job-tables)
               (littoral.jobs:job-tables-p))))
;; ⇒ (T NIL)
```

#### `run-due-jobs` `&key (queues (quote ("default"))) (limit 100)` — function

Run the jobs in `queues` of the current database that are due, here and now,
at most `limit` of them; how many ran.  Runners call this; so can a test.

*Example:* A job is a name and readable arguments, kept in the job_queue table until a runner runs it; `run-due-jobs` runs what is due here and now.  Its own queue keeps these jobs apart from other code's.

```lisp
(defvar *greeted* '())
(littoral.jobs:define-job (greet :queue "examples") (name)
  (push name *greeted*))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (progn
         (littoral.jobs:enqueue-job (list 'greet "Ada"))
         (littoral.jobs:enqueue-job (list 'greet "Bob"))
         (list (littoral.jobs:run-due-jobs :queues '("examples"))
               *greeted*
               (littoral.jobs:run-due-jobs :queues '("examples"))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (2 ("Bob" "Ada") 0)
```

#### `start-job-runner` `&key (database *database*) (threads 1) (queues (quote ("default"))) (interval 5)` — function

Run the jobs in `queues` of `database` (a spec, as `littoral.db:*database*` holds)
on `threads` background threads: at once when a job is enqueued in this
process, and every `interval` seconds for scheduled jobs, retries and other
processes' jobs.  Stops any runner already started.

*Example:* Runner threads run jobs as they are queued.  Each thread has its own connection, so the database is a file here rather than ":memory:".

```lisp
(defvar *done* nil)
(littoral.jobs:define-job (make-thumbnail :queue "examples") (image-id)
  (setf *done* image-id))
(let* ((file (merge-pathnames (format nil "jobs-~36R.sqlite3" (random (expt 36 8))) (uiop:temporary-directory)))
       (littoral.db:*database* (list :sqlite3 :database-name (namestring file))))
  (unwind-protect
       (progn
         (littoral.jobs:create-job-tables)
         (littoral.jobs:start-job-runner :queues '("examples") :threads 2)
         (littoral.jobs:enqueue-job (list 'make-thumbnail 12))
         (loop repeat 50 until *done* do (sleep 0.1))
         (list (littoral.jobs:job-runner-running-p)
               *done*
               (progn (littoral.jobs:stop-job-runner)
                      (littoral.jobs:job-runner-running-p))))
    (littoral.jobs:stop-job-runner)
    (littoral.jobs:drop-job-tables)
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string (namestring file) suffix)))))
;; ⇒ (T 12 NIL)
```

#### `stop-job-runner` — function

Stop the runner threads, letting each finish the job it is running (waiting
up to 30 seconds for each).

*Example:* Runner threads run jobs as they are queued.  Each thread has its own connection, so the database is a file here rather than ":memory:".

```lisp
(defvar *done* nil)
(littoral.jobs:define-job (make-thumbnail :queue "examples") (image-id)
  (setf *done* image-id))
(let* ((file (merge-pathnames (format nil "jobs-~36R.sqlite3" (random (expt 36 8))) (uiop:temporary-directory)))
       (littoral.db:*database* (list :sqlite3 :database-name (namestring file))))
  (unwind-protect
       (progn
         (littoral.jobs:create-job-tables)
         (littoral.jobs:start-job-runner :queues '("examples") :threads 2)
         (littoral.jobs:enqueue-job (list 'make-thumbnail 12))
         (loop repeat 50 until *done* do (sleep 0.1))
         (list (littoral.jobs:job-runner-running-p)
               *done*
               (progn (littoral.jobs:stop-job-runner)
                      (littoral.jobs:job-runner-running-p))))
    (littoral.jobs:stop-job-runner)
    (littoral.jobs:drop-job-tables)
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string (namestring file) suffix)))))
;; ⇒ (T 12 NIL)
```

#### `job-runner-running-p` — function

True while this process's runner threads run.

*Example:* Runner threads run jobs as they are queued.  Each thread has its own connection, so the database is a file here rather than ":memory:".

```lisp
(defvar *done* nil)
(littoral.jobs:define-job (make-thumbnail :queue "examples") (image-id)
  (setf *done* image-id))
(let* ((file (merge-pathnames (format nil "jobs-~36R.sqlite3" (random (expt 36 8))) (uiop:temporary-directory)))
       (littoral.db:*database* (list :sqlite3 :database-name (namestring file))))
  (unwind-protect
       (progn
         (littoral.jobs:create-job-tables)
         (littoral.jobs:start-job-runner :queues '("examples") :threads 2)
         (littoral.jobs:enqueue-job (list 'make-thumbnail 12))
         (loop repeat 50 until *done* do (sleep 0.1))
         (list (littoral.jobs:job-runner-running-p)
               *done*
               (progn (littoral.jobs:stop-job-runner)
                      (littoral.jobs:job-runner-running-p))))
    (littoral.jobs:stop-job-runner)
    (littoral.jobs:drop-job-tables)
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string (namestring file) suffix)))))
;; ⇒ (T 12 NIL)
```

#### `*durable-job*` — variable

The `durable-job` this thread is running.

*Example:* Inside a job, `*durable-job*` is the job being run, and `note-job-progress` records how it is going.

```lisp
(defvar *tries* '())
(littoral.jobs:define-job (import-rows :queue "examples") (count)
  (push (littoral.jobs:durable-job-attempts littoral.jobs:*durable-job*) *tries*)
  (dotimes (i count)
    (littoral.jobs:note-job-progress (format nil "~D of ~D rows" (1+ i) count))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'import-rows 3))))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (list *tries*
               (littoral.jobs:durable-job-progress (littoral.jobs:find-durable-job id))
               littoral.jobs:*durable-job*))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ((1) "3 of 3 rows" NIL)
```

#### `note-job-progress` `text` — function

From inside a job: record `text` as how it's going (`durable-job-progress`),
and hold on to the job for another `timeout`.

*Example:* Inside a job, `*durable-job*` is the job being run, and `note-job-progress` records how it is going.

```lisp
(defvar *tries* '())
(littoral.jobs:define-job (import-rows :queue "examples") (count)
  (push (littoral.jobs:durable-job-attempts littoral.jobs:*durable-job*) *tries*)
  (dotimes (i count)
    (littoral.jobs:note-job-progress (format nil "~D of ~D rows" (1+ i) count))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'import-rows 3))))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (list *tries*
               (littoral.jobs:durable-job-progress (littoral.jobs:find-durable-job id))
               littoral.jobs:*durable-job*))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ((1) "3 of 3 rows" NIL)
```

#### `abandon-job` `control &rest arguments` — function

From inside a job: fail it now, for the reason `control` and `arguments`
format, without trying again.

*Example:* `abandon-job` fails a job without trying again.  A failed job can be retried by hand, and a queued one cancelled before it starts.

```lisp
(littoral.jobs:define-job (charge-order :queue "examples") (order-id)
  (littoral.jobs:abandon-job "Order ~D was cancelled." order-id))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'charge-order 7))))
         (flet ((status () (littoral.jobs:durable-job-status (littoral.jobs:find-durable-job id))))
           (littoral.jobs:run-due-jobs :queues '("examples"))
           (list (status)
                 (first (uiop:split-string (littoral.jobs:durable-job-last-error (littoral.jobs:find-durable-job id))
                                           :separator '(#\Newline)))
                 (littoral.jobs:retry-durable-job id)
                 (status)
                 (littoral.jobs:cancel-durable-job id)
                 (status)
                 (littoral.jobs:cancel-durable-job id))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("failed" "Order 7 was cancelled." T "queued" T "cancelled" NIL)
```

#### `job-abandoned` — condition

Signalled by `abandon-job`: the job fails without being tried again.

*Example:* `abandon-job` fails a job without trying again.  A failed job can be retried by hand, and a queued one cancelled before it starts.

```lisp
(littoral.jobs:define-job (charge-order :queue "examples") (order-id)
  (littoral.jobs:abandon-job "Order ~D was cancelled." order-id))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'charge-order 7))))
         (flet ((status () (littoral.jobs:durable-job-status (littoral.jobs:find-durable-job id))))
           (littoral.jobs:run-due-jobs :queues '("examples"))
           (list (status)
                 (first (uiop:split-string (littoral.jobs:durable-job-last-error (littoral.jobs:find-durable-job id))
                                           :separator '(#\Newline)))
                 (littoral.jobs:retry-durable-job id)
                 (status)
                 (littoral.jobs:cancel-durable-job id)
                 (status)
                 (littoral.jobs:cancel-durable-job id))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("failed" "Order 7 was cancelled." T "queued" T "cancelled" NIL)
```

*Example:* The condition `abandon-job` signals; its report is the reason.

```lisp
(handler-case (littoral.jobs:abandon-job "No order ~D." 7)
  (littoral.jobs:job-abandoned (condition)
    (princ-to-string condition)))
;; ⇒ "No order 7."
```

#### `durable-job` — class

A job in the job_queue table, as it was when read.

*Example:* A job as it was when read: before it runs, and after.

```lisp
(littoral.jobs:define-job (send-receipt :queue "examples") (order-id)
  order-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((id (littoral.jobs:enqueue-job (list 'send-receipt 42)))
              (job (littoral.jobs:find-durable-job id)))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((done (littoral.jobs:find-durable-job id)))
           (list (= id (littoral.jobs:durable-job-id job))
                 (littoral.jobs:durable-job-name job)
                 (littoral.jobs:durable-job-arguments job)
                 (littoral.jobs:durable-job-queue job)
                 (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (integerp (littoral.jobs:durable-job-created job))
                 (littoral.jobs:durable-job-finished job)
                 (littoral.jobs:durable-job-status done)
                 (littoral.jobs:durable-job-attempts done)
                 (integerp (littoral.jobs:durable-job-finished done)))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T SEND-RECEIPT (42) "examples" "queued" 0 T NIL "done" 1 T)
```

#### `durable-job-id` `object` — generic function

Reads the id of a durable-job.  Its id, as `enqueue-job` returned it.

*Example:* A job as it was when read: before it runs, and after.

```lisp
(littoral.jobs:define-job (send-receipt :queue "examples") (order-id)
  order-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((id (littoral.jobs:enqueue-job (list 'send-receipt 42)))
              (job (littoral.jobs:find-durable-job id)))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((done (littoral.jobs:find-durable-job id)))
           (list (= id (littoral.jobs:durable-job-id job))
                 (littoral.jobs:durable-job-name job)
                 (littoral.jobs:durable-job-arguments job)
                 (littoral.jobs:durable-job-queue job)
                 (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (integerp (littoral.jobs:durable-job-created job))
                 (littoral.jobs:durable-job-finished job)
                 (littoral.jobs:durable-job-status done)
                 (littoral.jobs:durable-job-attempts done)
                 (integerp (littoral.jobs:durable-job-finished done)))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T SEND-RECEIPT (42) "examples" "queued" 0 T NIL "done" 1 T)
```

#### `durable-job-name` `object` — generic function

Reads the name of a durable-job.  The job's name, a symbol (or its text, when unreadable here).

*Example:* A job as it was when read: before it runs, and after.

```lisp
(littoral.jobs:define-job (send-receipt :queue "examples") (order-id)
  order-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((id (littoral.jobs:enqueue-job (list 'send-receipt 42)))
              (job (littoral.jobs:find-durable-job id)))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((done (littoral.jobs:find-durable-job id)))
           (list (= id (littoral.jobs:durable-job-id job))
                 (littoral.jobs:durable-job-name job)
                 (littoral.jobs:durable-job-arguments job)
                 (littoral.jobs:durable-job-queue job)
                 (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (integerp (littoral.jobs:durable-job-created job))
                 (littoral.jobs:durable-job-finished job)
                 (littoral.jobs:durable-job-status done)
                 (littoral.jobs:durable-job-attempts done)
                 (integerp (littoral.jobs:durable-job-finished done)))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T SEND-RECEIPT (42) "examples" "queued" 0 T NIL "done" 1 T)
```

#### `durable-job-arguments` `object` — generic function

Reads the arguments of a durable-job.  The list of arguments it is run with (or its text, when unreadable here).

*Example:* A job as it was when read: before it runs, and after.

```lisp
(littoral.jobs:define-job (send-receipt :queue "examples") (order-id)
  order-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((id (littoral.jobs:enqueue-job (list 'send-receipt 42)))
              (job (littoral.jobs:find-durable-job id)))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((done (littoral.jobs:find-durable-job id)))
           (list (= id (littoral.jobs:durable-job-id job))
                 (littoral.jobs:durable-job-name job)
                 (littoral.jobs:durable-job-arguments job)
                 (littoral.jobs:durable-job-queue job)
                 (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (integerp (littoral.jobs:durable-job-created job))
                 (littoral.jobs:durable-job-finished job)
                 (littoral.jobs:durable-job-status done)
                 (littoral.jobs:durable-job-attempts done)
                 (integerp (littoral.jobs:durable-job-finished done)))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T SEND-RECEIPT (42) "examples" "queued" 0 T NIL "done" 1 T)
```

#### `durable-job-queue` `object` — generic function

Reads the queue of a durable-job.  The queue it is in, a string.

*Example:* A job as it was when read: before it runs, and after.

```lisp
(littoral.jobs:define-job (send-receipt :queue "examples") (order-id)
  order-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((id (littoral.jobs:enqueue-job (list 'send-receipt 42)))
              (job (littoral.jobs:find-durable-job id)))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((done (littoral.jobs:find-durable-job id)))
           (list (= id (littoral.jobs:durable-job-id job))
                 (littoral.jobs:durable-job-name job)
                 (littoral.jobs:durable-job-arguments job)
                 (littoral.jobs:durable-job-queue job)
                 (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (integerp (littoral.jobs:durable-job-created job))
                 (littoral.jobs:durable-job-finished job)
                 (littoral.jobs:durable-job-status done)
                 (littoral.jobs:durable-job-attempts done)
                 (integerp (littoral.jobs:durable-job-finished done)))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T SEND-RECEIPT (42) "examples" "queued" 0 T NIL "done" 1 T)
```

#### `durable-job-status` `object` — generic function

Reads the status of a durable-job.  "queued", "running", "done", "failed" or "cancelled".

*Example:* A job as it was when read: before it runs, and after.

```lisp
(littoral.jobs:define-job (send-receipt :queue "examples") (order-id)
  order-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((id (littoral.jobs:enqueue-job (list 'send-receipt 42)))
              (job (littoral.jobs:find-durable-job id)))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((done (littoral.jobs:find-durable-job id)))
           (list (= id (littoral.jobs:durable-job-id job))
                 (littoral.jobs:durable-job-name job)
                 (littoral.jobs:durable-job-arguments job)
                 (littoral.jobs:durable-job-queue job)
                 (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (integerp (littoral.jobs:durable-job-created job))
                 (littoral.jobs:durable-job-finished job)
                 (littoral.jobs:durable-job-status done)
                 (littoral.jobs:durable-job-attempts done)
                 (integerp (littoral.jobs:durable-job-finished done)))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T SEND-RECEIPT (42) "examples" "queued" 0 T NIL "done" 1 T)
```

#### `durable-job-attempts` `object` — generic function

Reads the attempts of a durable-job.  Tries so far; inside the job, which try this is.

*Example:* A job as it was when read: before it runs, and after.

```lisp
(littoral.jobs:define-job (send-receipt :queue "examples") (order-id)
  order-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((id (littoral.jobs:enqueue-job (list 'send-receipt 42)))
              (job (littoral.jobs:find-durable-job id)))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((done (littoral.jobs:find-durable-job id)))
           (list (= id (littoral.jobs:durable-job-id job))
                 (littoral.jobs:durable-job-name job)
                 (littoral.jobs:durable-job-arguments job)
                 (littoral.jobs:durable-job-queue job)
                 (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (integerp (littoral.jobs:durable-job-created job))
                 (littoral.jobs:durable-job-finished job)
                 (littoral.jobs:durable-job-status done)
                 (littoral.jobs:durable-job-attempts done)
                 (integerp (littoral.jobs:durable-job-finished done)))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T SEND-RECEIPT (42) "examples" "queued" 0 T NIL "done" 1 T)
```

#### `durable-job-run-at` `object` — generic function

Reads the run-at of a durable-job.  When it is due; while running, when another runner may take it over.

*Example:* `in` delays a job; with `key`, a second job with that key isn't queued while the first waits.

```lisp
(littoral.jobs:define-job (remind :queue "examples") (user-id)
  user-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((first-id (littoral.jobs:enqueue-job (list 'remind 7) :in 3600 :key "remind:7"))
              (second-id (littoral.jobs:enqueue-job (list 'remind 7) :in 3600 :key "remind:7"))
              (job (littoral.jobs:find-durable-job first-id)))
         (list (integerp first-id)
               second-id
               (littoral.jobs:durable-job-key job)
               (<= 3599 (- (littoral.jobs:durable-job-run-at job) (get-universal-time)) 3600)
               (littoral.jobs:run-due-jobs :queues '("examples"))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T NIL "remind:7" T 0)
```

*Example:* A job that signals is tried again after `retry-seconds`, twice as long after each failure since, and marked failed after `attempts` tries.  The error is kept, with a backtrace after its first line.

```lisp
(littoral.jobs:define-job (call-service :queue "examples" :attempts 3 :retry-seconds 60) ()
  (error "The service is unavailable."))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'call-service))))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((job (littoral.jobs:find-durable-job id)))
           (list (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (first (uiop:split-string (littoral.jobs:durable-job-last-error job) :separator '(#\Newline)))
                 (<= 59 (- (littoral.jobs:durable-job-run-at job) (get-universal-time)) 60)
                 (littoral.jobs:run-due-jobs :queues '("examples")))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "The service is unavailable." T 0)
```

#### `durable-job-key` `object` — generic function

Reads the key of a durable-job.  The `key` it was enqueued with, or `nil`.

*Example:* `in` delays a job; with `key`, a second job with that key isn't queued while the first waits.

```lisp
(littoral.jobs:define-job (remind :queue "examples") (user-id)
  user-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((first-id (littoral.jobs:enqueue-job (list 'remind 7) :in 3600 :key "remind:7"))
              (second-id (littoral.jobs:enqueue-job (list 'remind 7) :in 3600 :key "remind:7"))
              (job (littoral.jobs:find-durable-job first-id)))
         (list (integerp first-id)
               second-id
               (littoral.jobs:durable-job-key job)
               (<= 3599 (- (littoral.jobs:durable-job-run-at job) (get-universal-time)) 3600)
               (littoral.jobs:run-due-jobs :queues '("examples"))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T NIL "remind:7" T 0)
```

#### `durable-job-progress` `object` — generic function

Reads the progress of a durable-job.  What `note-job-progress` said last.

*Example:* Inside a job, `*durable-job*` is the job being run, and `note-job-progress` records how it is going.

```lisp
(defvar *tries* '())
(littoral.jobs:define-job (import-rows :queue "examples") (count)
  (push (littoral.jobs:durable-job-attempts littoral.jobs:*durable-job*) *tries*)
  (dotimes (i count)
    (littoral.jobs:note-job-progress (format nil "~D of ~D rows" (1+ i) count))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'import-rows 3))))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (list *tries*
               (littoral.jobs:durable-job-progress (littoral.jobs:find-durable-job id))
               littoral.jobs:*durable-job*))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ((1) "3 of 3 rows" NIL)
```

#### `durable-job-last-error` `object` — generic function

Reads the last-error of a durable-job.  Why its last try failed: the error's text, then a backtrace; or `nil`.

*Example:* A job that signals is tried again after `retry-seconds`, twice as long after each failure since, and marked failed after `attempts` tries.  The error is kept, with a backtrace after its first line.

```lisp
(littoral.jobs:define-job (call-service :queue "examples" :attempts 3 :retry-seconds 60) ()
  (error "The service is unavailable."))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'call-service))))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((job (littoral.jobs:find-durable-job id)))
           (list (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (first (uiop:split-string (littoral.jobs:durable-job-last-error job) :separator '(#\Newline)))
                 (<= 59 (- (littoral.jobs:durable-job-run-at job) (get-universal-time)) 60)
                 (littoral.jobs:run-due-jobs :queues '("examples")))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "The service is unavailable." T 0)
```

#### `durable-job-created` `object` — generic function

Reads the created of a durable-job.  When it was queued, a universal time.

*Example:* A job as it was when read: before it runs, and after.

```lisp
(littoral.jobs:define-job (send-receipt :queue "examples") (order-id)
  order-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((id (littoral.jobs:enqueue-job (list 'send-receipt 42)))
              (job (littoral.jobs:find-durable-job id)))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((done (littoral.jobs:find-durable-job id)))
           (list (= id (littoral.jobs:durable-job-id job))
                 (littoral.jobs:durable-job-name job)
                 (littoral.jobs:durable-job-arguments job)
                 (littoral.jobs:durable-job-queue job)
                 (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (integerp (littoral.jobs:durable-job-created job))
                 (littoral.jobs:durable-job-finished job)
                 (littoral.jobs:durable-job-status done)
                 (littoral.jobs:durable-job-attempts done)
                 (integerp (littoral.jobs:durable-job-finished done)))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T SEND-RECEIPT (42) "examples" "queued" 0 T NIL "done" 1 T)
```

#### `durable-job-finished` `object` — generic function

Reads the finished of a durable-job.  When it was done, failed or cancelled, a universal time; or `nil`.

*Example:* A job as it was when read: before it runs, and after.

```lisp
(littoral.jobs:define-job (send-receipt :queue "examples") (order-id)
  order-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((id (littoral.jobs:enqueue-job (list 'send-receipt 42)))
              (job (littoral.jobs:find-durable-job id)))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((done (littoral.jobs:find-durable-job id)))
           (list (= id (littoral.jobs:durable-job-id job))
                 (littoral.jobs:durable-job-name job)
                 (littoral.jobs:durable-job-arguments job)
                 (littoral.jobs:durable-job-queue job)
                 (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (integerp (littoral.jobs:durable-job-created job))
                 (littoral.jobs:durable-job-finished job)
                 (littoral.jobs:durable-job-status done)
                 (littoral.jobs:durable-job-attempts done)
                 (integerp (littoral.jobs:durable-job-finished done)))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T SEND-RECEIPT (42) "examples" "queued" 0 T NIL "done" 1 T)
```

#### `find-durable-job` `id` — function

The job `id`, or `nil`.

*Example:* A job as it was when read: before it runs, and after.

```lisp
(littoral.jobs:define-job (send-receipt :queue "examples") (order-id)
  order-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((id (littoral.jobs:enqueue-job (list 'send-receipt 42)))
              (job (littoral.jobs:find-durable-job id)))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((done (littoral.jobs:find-durable-job id)))
           (list (= id (littoral.jobs:durable-job-id job))
                 (littoral.jobs:durable-job-name job)
                 (littoral.jobs:durable-job-arguments job)
                 (littoral.jobs:durable-job-queue job)
                 (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (integerp (littoral.jobs:durable-job-created job))
                 (littoral.jobs:durable-job-finished job)
                 (littoral.jobs:durable-job-status done)
                 (littoral.jobs:durable-job-attempts done)
                 (integerp (littoral.jobs:durable-job-finished done)))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T SEND-RECEIPT (42) "examples" "queued" 0 T NIL "done" 1 T)
```

#### `durable-jobs` `&key status queue (limit 50) (offset 0)` — function

Jobs, newest first; only those with `status` and in `queue` (strings) if
given.  At most `limit`, skipping the first `offset`.

*Example:* Listing jobs, newest first, counting them by status, and deleting finished ones once they are a week old.

```lisp
(littoral.jobs:define-job (welcome :queue "examples") (name)
  name)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (progn
         (dolist (name '("Ada" "Bob" "Cy"))
           (littoral.jobs:enqueue-job (list 'welcome name)))
         (littoral.jobs:run-due-jobs :queues '("examples") :limit 2)
         (list (mapcar #'littoral.jobs:durable-job-arguments (littoral.jobs:durable-jobs))
               (mapcar #'littoral.jobs:durable-job-arguments (littoral.jobs:durable-jobs :status "done" :limit 1))
               (littoral.jobs:durable-job-counts)
               (littoral.jobs:purge-durable-jobs)
               (progn
                 ;; As if they had finished a month ago.
                 (littoral.db:db-execute "UPDATE job_queue SET finished = finished - 2592000 WHERE status = 'done'")
                 (littoral.jobs:purge-durable-jobs))
               (littoral.jobs:durable-job-counts)))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ((("Cy") ("Bob") ("Ada")) (("Bob")) (("done" . 2) ("queued" . 1)) 0 2 (("queued" . 1)))
```

#### `durable-job-counts` — function

How many jobs have each status: (("queued" . 3) ("done" . 40) …).

*Example:* Listing jobs, newest first, counting them by status, and deleting finished ones once they are a week old.

```lisp
(littoral.jobs:define-job (welcome :queue "examples") (name)
  name)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (progn
         (dolist (name '("Ada" "Bob" "Cy"))
           (littoral.jobs:enqueue-job (list 'welcome name)))
         (littoral.jobs:run-due-jobs :queues '("examples") :limit 2)
         (list (mapcar #'littoral.jobs:durable-job-arguments (littoral.jobs:durable-jobs))
               (mapcar #'littoral.jobs:durable-job-arguments (littoral.jobs:durable-jobs :status "done" :limit 1))
               (littoral.jobs:durable-job-counts)
               (littoral.jobs:purge-durable-jobs)
               (progn
                 ;; As if they had finished a month ago.
                 (littoral.db:db-execute "UPDATE job_queue SET finished = finished - 2592000 WHERE status = 'done'")
                 (littoral.jobs:purge-durable-jobs))
               (littoral.jobs:durable-job-counts)))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ((("Cy") ("Bob") ("Ada")) (("Bob")) (("done" . 2) ("queued" . 1)) 0 2 (("queued" . 1)))
```

#### `retry-durable-job` `id` — function

Run the failed or cancelled job `id` again now, its tries counted afresh;
true unless it wasn't failed or cancelled, or a job with its key waits already.

*Example:* `abandon-job` fails a job without trying again.  A failed job can be retried by hand, and a queued one cancelled before it starts.

```lisp
(littoral.jobs:define-job (charge-order :queue "examples") (order-id)
  (littoral.jobs:abandon-job "Order ~D was cancelled." order-id))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'charge-order 7))))
         (flet ((status () (littoral.jobs:durable-job-status (littoral.jobs:find-durable-job id))))
           (littoral.jobs:run-due-jobs :queues '("examples"))
           (list (status)
                 (first (uiop:split-string (littoral.jobs:durable-job-last-error (littoral.jobs:find-durable-job id))
                                           :separator '(#\Newline)))
                 (littoral.jobs:retry-durable-job id)
                 (status)
                 (littoral.jobs:cancel-durable-job id)
                 (status)
                 (littoral.jobs:cancel-durable-job id))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("failed" "Order 7 was cancelled." T "queued" T "cancelled" NIL)
```

#### `cancel-durable-job` `id` — function

Cancel the job `id` unless it has started; true if it was cancelled.

*Example:* `abandon-job` fails a job without trying again.  A failed job can be retried by hand, and a queued one cancelled before it starts.

```lisp
(littoral.jobs:define-job (charge-order :queue "examples") (order-id)
  (littoral.jobs:abandon-job "Order ~D was cancelled." order-id))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'charge-order 7))))
         (flet ((status () (littoral.jobs:durable-job-status (littoral.jobs:find-durable-job id))))
           (littoral.jobs:run-due-jobs :queues '("examples"))
           (list (status)
                 (first (uiop:split-string (littoral.jobs:durable-job-last-error (littoral.jobs:find-durable-job id))
                                           :separator '(#\Newline)))
                 (littoral.jobs:retry-durable-job id)
                 (status)
                 (littoral.jobs:cancel-durable-job id)
                 (status)
                 (littoral.jobs:cancel-durable-job id))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("failed" "Order 7 was cancelled." T "queued" T "cancelled" NIL)
```

#### `purge-durable-jobs` `&key (older-than (* 7 24 3600)) (statuses (quote ("done" "cancelled")))` — function

Delete jobs with one of `statuses` that finished more than `older-than`
seconds ago; how many.

*Example:* Listing jobs, newest first, counting them by status, and deleting finished ones once they are a week old.

```lisp
(littoral.jobs:define-job (welcome :queue "examples") (name)
  name)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (progn
         (dolist (name '("Ada" "Bob" "Cy"))
           (littoral.jobs:enqueue-job (list 'welcome name)))
         (littoral.jobs:run-due-jobs :queues '("examples") :limit 2)
         (list (mapcar #'littoral.jobs:durable-job-arguments (littoral.jobs:durable-jobs))
               (mapcar #'littoral.jobs:durable-job-arguments (littoral.jobs:durable-jobs :status "done" :limit 1))
               (littoral.jobs:durable-job-counts)
               (littoral.jobs:purge-durable-jobs)
               (progn
                 ;; As if they had finished a month ago.
                 (littoral.db:db-execute "UPDATE job_queue SET finished = finished - 2592000 WHERE status = 'done'")
                 (littoral.jobs:purge-durable-jobs))
               (littoral.jobs:durable-job-counts)))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ((("Cy") ("Bob") ("Ada")) (("Bob")) (("done" . 2) ("queued" . 1)) 0 2 (("queued" . 1)))
```

## Package `littoral.audit`

Load it with `(asdf:load-system :littoral/audit)`.  An audit log: who did what,
and when, kept in the database.

### General

#### `audit` `action &key subject subject-label details (actor-id () actor-given) actor-name` — function

Record that `action` (a string such as "invoice.sent") happened to `subject`
(a string such as "invoice:42", named `subject-label` for people), with
`details`, a plist of short values (strings, numbers, T and `nil`, symbols, lists
of them).  The actor is `actor-id` and `actor-name` when `actor-id` is given, even
as `nil` for none, or else whoever `*audit-actor*` finds.  Returns `action`.  The
event is written only where `audit-enabled-p`, and passed to `*audit-hook*`.

*Example:* An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))
```

*Example:* An event is written in the current transaction, so it goes when its action rolls back.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (ignore-errors
          (littoral.db:with-transaction ()
            (littoral.audit:audit "invoice.sent" :subject "invoice:42" :actor-id nil)
            (error "The mail couldn't be queued.")))
         (littoral.audit:audit-events))
    (littoral.audit:drop-audit-tables)))
;; ⇒ NIL
```

#### `create-audit-tables` — function

Create or bring up to date the audit_log table (migrations
`:littoral-audit`), and record events in this database.

*Example:* An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))
```

#### `drop-audit-tables` — function

Drop the audit_log table, and stop recording events in this database.

*Example:* An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))
```

#### `audit-enabled-p` — function

True when events are recorded in the current database.

*Example:* The hook sees every event as a plist, even where no audit table records it.

```lisp
(let* ((littoral.db:*database* nil)
       (seen '())
       (littoral.audit:*audit-hook* (lambda (event) (push event seen))))
  (list (littoral.audit:audit-enabled-p)
        (littoral.audit:audit "cache.cleared" :details '(:entries 120) :actor-id nil)
        (getf (first seen) :action)
        (getf (first seen) :details)))
;; ⇒ (NIL "cache.cleared" "cache.cleared" (:ENTRIES 120))
```

*Example:* Events are recorded only in a database whose audit tables were made in this process.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (list (littoral.audit:audit-enabled-p)
        (progn (littoral.audit:drop-audit-tables)
               (littoral.audit:audit-enabled-p))))
;; ⇒ (T NIL)
```

#### `*audit-actor*` — variable

A function of no arguments: the id and name (two values, strings or `nil`)
of whoever is acting now.  littoral/auth makes it the signed-in user.

*Example:* Who is acting, when an event doesn't say.  littoral/auth makes it the signed-in user; here it is fixed.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.audit:*audit-actor* (lambda () (values "7" "Zoë"))))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "report.exported")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-actor-id event) (littoral.audit:audit-event-actor-name event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("7" "Zoë")
```

#### `*audit-hook*` — variable

A function of each event as a plist (`:time` `:actor-id` `:actor-name` `:action`
`:subject` `:subject-label` `:details` `:address`), or `nil`.  Called even where
there's no audit table; errors it signals are ignored.

*Example:* The hook sees every event as a plist, even where no audit table records it.

```lisp
(let* ((littoral.db:*database* nil)
       (seen '())
       (littoral.audit:*audit-hook* (lambda (event) (push event seen))))
  (list (littoral.audit:audit-enabled-p)
        (littoral.audit:audit "cache.cleared" :details '(:entries 120) :actor-id nil)
        (getf (first seen) :action)
        (getf (first seen) :details)))
;; ⇒ (NIL "cache.cleared" "cache.cleared" (:ENTRIES 120))
```

#### `audit-events` `&key action actor subject search since until (limit 50) (offset 0)` — function

Events, newest first.  `action` matches itself and the actions under it
("sign-in" matches "sign-in.failed"); `actor` is an actor id and `subject`
a subject; `search` looks in the actor's and subject's names, ignoring case
(on SQLite, the case of ASCII letters only);
`since` and `until` are universal times.  At most `limit`, skipping the first
`offset`.

*Example:* An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))
```

*Example:* Finding events: an action matches itself and the actions under it, newest first; `search` looks in the names of who and what.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :actor-id "7" :actor-name "Zoë")
         (littoral.audit:audit "invoice.paid" :subject "invoice:42" :actor-id "8" :actor-name "Bob")
         (littoral.audit:audit "invoices" :subject "invoice:43" :actor-id "7" :actor-name "Zoë")
         (flet ((actions (&rest filters)
                  (mapcar #'littoral.audit:audit-event-action (apply #'littoral.audit:audit-events filters))))
           (list (actions :action "invoice")
                 (actions :subject "invoice:42")
                 (actions :actor "7")
                 (actions :search "bob")
                 (actions :limit 1)
                 (actions :since (+ (get-universal-time) 60))
                 (littoral.audit:audit-actions))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ (("invoice.paid" "invoice.sent") ("invoice.paid" "invoice.sent") ("invoices" "invoice.sent") ("invoice.paid") ("invoices") NIL ("invoice.paid" "invoice.sent" "invoices"))
```

#### `audit-actions` — function

The actions recorded so far, in order.  Sorted here: PostgreSQL's
collation would put "invoices" before "invoice.sent".

*Example:* Finding events: an action matches itself and the actions under it, newest first; `search` looks in the names of who and what.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :actor-id "7" :actor-name "Zoë")
         (littoral.audit:audit "invoice.paid" :subject "invoice:42" :actor-id "8" :actor-name "Bob")
         (littoral.audit:audit "invoices" :subject "invoice:43" :actor-id "7" :actor-name "Zoë")
         (flet ((actions (&rest filters)
                  (mapcar #'littoral.audit:audit-event-action (apply #'littoral.audit:audit-events filters))))
           (list (actions :action "invoice")
                 (actions :subject "invoice:42")
                 (actions :actor "7")
                 (actions :search "bob")
                 (actions :limit 1)
                 (actions :since (+ (get-universal-time) 60))
                 (littoral.audit:audit-actions))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ (("invoice.paid" "invoice.sent") ("invoice.paid" "invoice.sent") ("invoices" "invoice.sent") ("invoice.paid") ("invoices") NIL ("invoice.paid" "invoice.sent" "invoices"))
```

#### `purge-audit-log` `&key (older-than (* 365 24 3600))` — function

Delete events more than `older-than` seconds old (a year); how many.

*Example:* Deletes events more than a year old, unless told otherwise.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :actor-id nil)
         (list (littoral.audit:purge-audit-log)
               (littoral.audit:purge-audit-log :older-than -60)
               (littoral.audit:audit-events)))
    (littoral.audit:drop-audit-tables)))
;; ⇒ (0 1 NIL)
```

#### `audit-event` — class

An event read from the audit log.

*Example:* An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))
```

#### `audit-event-id` `object` — generic function

Reads the id of an audit-event.  Its row's id, larger for later events.

*Example:* Each event has an id and a time; its address is the client's, so `nil` outside a request.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "report.exported" :actor-id nil)
         (let ((event (first (littoral.audit:audit-events))))
           (list (integerp (littoral.audit:audit-event-id event))
                 (<= (- (get-universal-time) 2) (littoral.audit:audit-event-time event) (get-universal-time))
                 (littoral.audit:audit-event-address event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ (T T NIL)
```

#### `audit-event-time` `object` — generic function

Reads the time of an audit-event.  A universal time.

*Example:* Each event has an id and a time; its address is the client's, so `nil` outside a request.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "report.exported" :actor-id nil)
         (let ((event (first (littoral.audit:audit-events))))
           (list (integerp (littoral.audit:audit-event-id event))
                 (<= (- (get-universal-time) 2) (littoral.audit:audit-event-time event) (get-universal-time))
                 (littoral.audit:audit-event-address event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ (T T NIL)
```

#### `audit-event-actor-id` `object` — generic function

Reads the actor-id of an audit-event.  Who acted, a string, or `nil`.

*Example:* An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))
```

#### `audit-event-actor-name` `object` — generic function

Reads the actor-name of an audit-event.  Who acted, named for people, or `nil`.

*Example:* An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))
```

#### `audit-event-action` `object` — generic function

Reads the action of an audit-event.  What was done, such as "invoice.sent".

*Example:* An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))
```

#### `audit-event-subject` `object` — generic function

Reads the subject of an audit-event.  What it was done to, such as "invoice:42", or `nil`.

*Example:* An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))
```

#### `audit-event-subject-label` `object` — generic function

Reads the subject-label of an audit-event.  What it was done to, named for people, or `nil`.

*Example:* An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))
```

#### `audit-event-details` `object` — generic function

Reads the details of an audit-event.  An alist of ("key" . value), sorted by key; a list value
is a list of strings, and `nil` reads back as the symbol `null`.

*Example:* An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))
```

#### `audit-event-address` `object` — generic function

Reads the address of an audit-event.  The client's IP address, or `nil` outside a request.

*Example:* Each event has an id and a time; its address is the client's, so `nil` outside a request.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "report.exported" :actor-id nil)
         (let ((event (first (littoral.audit:audit-events))))
           (list (integerp (littoral.audit:audit-event-id event))
                 (<= (- (get-universal-time) 2) (littoral.audit:audit-event-time event) (get-universal-time))
                 (littoral.audit:audit-event-address event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ (T T NIL)
```

#### `audit-log-view` — class

The audit log, newest first, filtered by action and by
who or what.  Shows everything: put it where only those who may see it can.

*Example:* A page to look through the log, newest first, filtered by action and by who or what.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (with-fresh-applications (("/audit" 'littoral.audit:audit-log-view :mode :deployment))
         (let ((b (make-instance 'browser)))
           (visit b "/audit")
           (let ((empty (not (null (has-text-p b "Nothing has been recorded.")))))
             (littoral.audit:audit "invoice.sent" :subject-label "Invoice 42" :actor-id "7" :actor-name "Zoë")
             (visit b "/audit")
             (list empty
                   (not (null (search "Zoë invoice.sent Invoice 42" (body-text b))))))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ (T T)
```

## Package `littoral.auth`

Users, signing in, roles and password reset for Littoral.  Load it with
`(asdf:load-system :littoral/auth)`.

### Users

#### `user` — class

Someone who can sign in, in the built-in users table.

*Example:* A user in the built-in users table.  Only the password's hash is kept.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (list (type-of ada)
          (littoral.auth:user-id ada)
          (littoral.auth:user-name ada)
          (littoral.auth:user-email ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:user-active-p ada)
          (subseq (littoral.auth:user-password-hash ada) 0 19))))
;; ⇒ (LITTORAL.AUTH:USER 1 "ada" "ada@example.org" (:ADMIN :EDITOR) T "PBKDF2$SHA256:1000$")
```

#### `user-id` `user` — generic function

`user`'s key in its store, kept in the session while they are signed in.

*Example:* A user in the built-in users table.  Only the password's hash is kept.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (list (type-of ada)
          (littoral.auth:user-id ada)
          (littoral.auth:user-name ada)
          (littoral.auth:user-email ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:user-active-p ada)
          (subseq (littoral.auth:user-password-hash ada) 0 19))))
;; ⇒ (LITTORAL.AUTH:USER 1 "ada" "ada@example.org" (:ADMIN :EDITOR) T "PBKDF2$SHA256:1000$")
```

#### `user-name` `user` — generic function

The name `user` signs in with.

*Example:* A user in the built-in users table.  Only the password's hash is kept.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (list (type-of ada)
          (littoral.auth:user-id ada)
          (littoral.auth:user-name ada)
          (littoral.auth:user-email ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:user-active-p ada)
          (subseq (littoral.auth:user-password-hash ada) 0 19))))
;; ⇒ (LITTORAL.AUTH:USER 1 "ada" "ada@example.org" (:ADMIN :EDITOR) T "PBKDF2$SHA256:1000$")
```

#### `user-email` `user` — generic function

`user`'s email address, or `nil`.

*Example:* A user in the built-in users table.  Only the password's hash is kept.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (list (type-of ada)
          (littoral.auth:user-id ada)
          (littoral.auth:user-name ada)
          (littoral.auth:user-email ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:user-active-p ada)
          (subseq (littoral.auth:user-password-hash ada) 0 19))))
;; ⇒ (LITTORAL.AUTH:USER 1 "ada" "ada@example.org" (:ADMIN :EDITOR) T "PBKDF2$SHA256:1000$")
```

#### `user-roles` `user` — generic function

`user`'s roles, as keywords.

*Example:* A user in the built-in users table.  Only the password's hash is kept.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (list (type-of ada)
          (littoral.auth:user-id ada)
          (littoral.auth:user-name ada)
          (littoral.auth:user-email ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:user-active-p ada)
          (subseq (littoral.auth:user-password-hash ada) 0 19))))
;; ⇒ (LITTORAL.AUTH:USER 1 "ada" "ada@example.org" (:ADMIN :EDITOR) T "PBKDF2$SHA256:1000$")
```

#### `user-active-p` `user` — generic function

True when `user` may sign in.

*Example:* A user in the built-in users table.  Only the password's hash is kept.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (list (type-of ada)
          (littoral.auth:user-id ada)
          (littoral.auth:user-name ada)
          (littoral.auth:user-email ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:user-active-p ada)
          (subseq (littoral.auth:user-password-hash ada) 0 19))))
;; ⇒ (LITTORAL.AUTH:USER 1 "ada" "ada@example.org" (:ADMIN :EDITOR) T "PBKDF2$SHA256:1000$")
```

#### `user-password-hash` `user` — generic function

`user`'s stored password hash, or `nil` when they have none.

*Example:* A user in the built-in users table.  Only the password's hash is kept.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (list (type-of ada)
          (littoral.auth:user-id ada)
          (littoral.auth:user-name ada)
          (littoral.auth:user-email ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:user-active-p ada)
          (subseq (littoral.auth:user-password-hash ada) 0 19))))
;; ⇒ (LITTORAL.AUTH:USER 1 "ada" "ada@example.org" (:ADMIN :EDITOR) T "PBKDF2$SHA256:1000$")
```

### User stores

#### `user-store` — class

Where users are found.  Specialise the STORE- generic functions.

*Example:* Any class can be a store: specialise the STORE- generic functions.  Its users are any objects with methods for the user generic functions; here, users kept in a list.

```lisp
(defclass staff-member ()
  ((id :initarg :id :reader staff-id)
   (name :initarg :name :reader staff-name)
   (hash :initarg :hash :reader staff-hash)))
(defmethod littoral.auth:user-id ((user staff-member)) (staff-id user))
(defmethod littoral.auth:user-name ((user staff-member)) (staff-name user))
(defmethod littoral.auth:user-password-hash ((user staff-member)) (staff-hash user))
(defclass staff-list (littoral.auth:user-store)
  ((members :initarg :members :reader staff-members)))
(defmethod littoral.auth:store-find-user ((store staff-list) name)
  (find name (staff-members store) :key #'staff-name :test #'string-equal))
(defmethod littoral.auth:store-find-user-by-id ((store staff-list) id)
  (find (princ-to-string id) (staff-members store)
        :key (lambda (user) (princ-to-string (staff-id user))) :test #'string=))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables :users nil)
  (let ((littoral.auth:*user-store*
          (make-instance 'staff-list
                         :members (list (make-instance 'staff-member :id 7 :name "carol"
                                                                     :hash (littoral.auth:hash-password "carol's secret"))))))
    (list (littoral.auth:user-name (littoral.auth:authenticate "Carol" "carol's secret"))
          (littoral.auth:user-name (littoral.auth:find-user-by-id "7"))
          ;; Without a method for it, the store finds no one by email.
          (littoral.auth:find-user-by-email "carol@example.org")
          (littoral.auth:user-roles (littoral.auth:find-user "carol")))))
;; ⇒ ("carol" "carol" NIL NIL)
```

#### `users-table-store` — class

The built-in users table, through littoral/db.

*Example:* By default users come from the built-in users table.

```lisp
(type-of littoral.auth:*user-store*)
;; ⇒ LITTORAL.AUTH:USERS-TABLE-STORE
```

#### `*user-store*` — variable

Where users come from.  Bind it per application with `using-user-store`.

*Example:* By default users come from the built-in users table.

```lisp
(type-of littoral.auth:*user-store*)
;; ⇒ LITTORAL.AUTH:USERS-TABLE-STORE
```

#### `using-user-store` `store &optional around` — function

An `:around-request` function binding `*user-store*` to `store`, then calling
`around` (another such function, such as `using-database`'s) if given.

*Example:* Give one application its own store, by binding `*user-store*` around its requests.

```lisp
(defclass who-is-ada (component) ())
(defmethod render ((self who-is-ada))
  (p () (text (littoral.auth:user-email (littoral.auth:find-user "ada")))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:db-execute "CREATE TABLE members (id INTEGER PRIMARY KEY, name TEXT, email TEXT, password_hash TEXT)")
  (littoral.db:db-execute "INSERT INTO members (name, email) VALUES ('ada', 'ada@members.example')")
  (with-fresh-applications
      (("/members" 'who-is-ada :mode :deployment
                               :around-request (littoral.auth:using-user-store
                                                (littoral.auth:make-sql-user-store :table "members" :email "email"))))
    (let ((b (make-instance 'browser)))
      (visit b "/members")
      (body-text b))))
;; ⇒ "ada@members.example"
```

#### `store-find-user` `store name` — generic function

The user `store` knows by `name`, or `nil`.

*Example:* Any class can be a store: specialise the STORE- generic functions.  Its users are any objects with methods for the user generic functions; here, users kept in a list.

```lisp
(defclass staff-member ()
  ((id :initarg :id :reader staff-id)
   (name :initarg :name :reader staff-name)
   (hash :initarg :hash :reader staff-hash)))
(defmethod littoral.auth:user-id ((user staff-member)) (staff-id user))
(defmethod littoral.auth:user-name ((user staff-member)) (staff-name user))
(defmethod littoral.auth:user-password-hash ((user staff-member)) (staff-hash user))
(defclass staff-list (littoral.auth:user-store)
  ((members :initarg :members :reader staff-members)))
(defmethod littoral.auth:store-find-user ((store staff-list) name)
  (find name (staff-members store) :key #'staff-name :test #'string-equal))
(defmethod littoral.auth:store-find-user-by-id ((store staff-list) id)
  (find (princ-to-string id) (staff-members store)
        :key (lambda (user) (princ-to-string (staff-id user))) :test #'string=))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables :users nil)
  (let ((littoral.auth:*user-store*
          (make-instance 'staff-list
                         :members (list (make-instance 'staff-member :id 7 :name "carol"
                                                                     :hash (littoral.auth:hash-password "carol's secret"))))))
    (list (littoral.auth:user-name (littoral.auth:authenticate "Carol" "carol's secret"))
          (littoral.auth:user-name (littoral.auth:find-user-by-id "7"))
          ;; Without a method for it, the store finds no one by email.
          (littoral.auth:find-user-by-email "carol@example.org")
          (littoral.auth:user-roles (littoral.auth:find-user "carol")))))
;; ⇒ ("carol" "carol" NIL NIL)
```

#### `store-find-user-by-email` `store email` — generic function

The user `store` knows by `email`, or `nil`.

*Example:* Any class can be a store: specialise the STORE- generic functions.  Its users are any objects with methods for the user generic functions; here, users kept in a list.

```lisp
(defclass staff-member ()
  ((id :initarg :id :reader staff-id)
   (name :initarg :name :reader staff-name)
   (hash :initarg :hash :reader staff-hash)))
(defmethod littoral.auth:user-id ((user staff-member)) (staff-id user))
(defmethod littoral.auth:user-name ((user staff-member)) (staff-name user))
(defmethod littoral.auth:user-password-hash ((user staff-member)) (staff-hash user))
(defclass staff-list (littoral.auth:user-store)
  ((members :initarg :members :reader staff-members)))
(defmethod littoral.auth:store-find-user ((store staff-list) name)
  (find name (staff-members store) :key #'staff-name :test #'string-equal))
(defmethod littoral.auth:store-find-user-by-id ((store staff-list) id)
  (find (princ-to-string id) (staff-members store)
        :key (lambda (user) (princ-to-string (staff-id user))) :test #'string=))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables :users nil)
  (let ((littoral.auth:*user-store*
          (make-instance 'staff-list
                         :members (list (make-instance 'staff-member :id 7 :name "carol"
                                                                     :hash (littoral.auth:hash-password "carol's secret"))))))
    (list (littoral.auth:user-name (littoral.auth:authenticate "Carol" "carol's secret"))
          (littoral.auth:user-name (littoral.auth:find-user-by-id "7"))
          ;; Without a method for it, the store finds no one by email.
          (littoral.auth:find-user-by-email "carol@example.org")
          (littoral.auth:user-roles (littoral.auth:find-user "carol")))))
;; ⇒ ("carol" "carol" NIL NIL)
```

#### `store-find-user-by-id` `store id` — generic function

The user whose `user-id` is `id`, which may be given as its printed form; `nil` if none.

*Example:* Any class can be a store: specialise the STORE- generic functions.  Its users are any objects with methods for the user generic functions; here, users kept in a list.

```lisp
(defclass staff-member ()
  ((id :initarg :id :reader staff-id)
   (name :initarg :name :reader staff-name)
   (hash :initarg :hash :reader staff-hash)))
(defmethod littoral.auth:user-id ((user staff-member)) (staff-id user))
(defmethod littoral.auth:user-name ((user staff-member)) (staff-name user))
(defmethod littoral.auth:user-password-hash ((user staff-member)) (staff-hash user))
(defclass staff-list (littoral.auth:user-store)
  ((members :initarg :members :reader staff-members)))
(defmethod littoral.auth:store-find-user ((store staff-list) name)
  (find name (staff-members store) :key #'staff-name :test #'string-equal))
(defmethod littoral.auth:store-find-user-by-id ((store staff-list) id)
  (find (princ-to-string id) (staff-members store)
        :key (lambda (user) (princ-to-string (staff-id user))) :test #'string=))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables :users nil)
  (let ((littoral.auth:*user-store*
          (make-instance 'staff-list
                         :members (list (make-instance 'staff-member :id 7 :name "carol"
                                                                     :hash (littoral.auth:hash-password "carol's secret"))))))
    (list (littoral.auth:user-name (littoral.auth:authenticate "Carol" "carol's secret"))
          (littoral.auth:user-name (littoral.auth:find-user-by-id "7"))
          ;; Without a method for it, the store finds no one by email.
          (littoral.auth:find-user-by-email "carol@example.org")
          (littoral.auth:user-roles (littoral.auth:find-user "carol")))))
;; ⇒ ("carol" "carol" NIL NIL)
```

#### `store-set-password-hash` `store user hash` — generic function

Keep `hash` as `user`'s password hash.

*Example:* Only a writable store can change passwords; a SQL store is read-only unless made with `:writable` T.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.db:db-execute "CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, password_hash TEXT)")
  (littoral.db:db-execute "INSERT INTO people (name, password_hash) VALUES ('ada', NULL)")
  (littoral.auth:create-auth-tables :users nil)
  (let* ((read-only (littoral.auth:make-sql-user-store :table "people"))
         (writable (littoral.auth:make-sql-user-store :table "people" :writable t))
         (ada (littoral.auth:store-find-user writable "ada")))
    (littoral.auth:store-set-password-hash writable ada (littoral.auth:hash-password "a passphrase"))
    (list (littoral.auth:store-writable-p read-only)
          (littoral.auth:store-writable-p writable)
          (littoral.auth:verify-password "a passphrase" (littoral.auth:user-password-hash ada))
          (handler-case (littoral.auth:store-set-password-hash read-only ada "x")
            (error (e) (princ-to-string e))))))
;; ⇒ (NIL T T "This user store is read-only: it can't change passwords.")
```

#### `store-create-user` `store &key name email password-hash roles` — generic function

A new user in `store`, or `nil` when `store` doesn't create users
(OAuth then signs in only users it already has).

*Example:* OAuth sign-in creates users through the store; a SQL store does only when made with `:create` T, and returns `nil` otherwise.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:db-execute "CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, email TEXT, password_hash TEXT)")
  (let ((closed (littoral.auth:make-sql-user-store :table "people" :email "email"))
        (open (littoral.auth:make-sql-user-store :table "people" :email "email" :create t)))
    (list (littoral.auth:store-create-user closed :name "dave" :email "dave@example.org")
          (littoral.auth:user-email (littoral.auth:store-create-user open :name "dave" :email "dave@example.org")))))
;; ⇒ (NIL "dave@example.org")
```

#### `store-writable-p` `store` — generic function

True when `store-set-password-hash` works.

*Example:* Only a writable store can change passwords; a SQL store is read-only unless made with `:writable` T.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.db:db-execute "CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, password_hash TEXT)")
  (littoral.db:db-execute "INSERT INTO people (name, password_hash) VALUES ('ada', NULL)")
  (littoral.auth:create-auth-tables :users nil)
  (let* ((read-only (littoral.auth:make-sql-user-store :table "people"))
         (writable (littoral.auth:make-sql-user-store :table "people" :writable t))
         (ada (littoral.auth:store-find-user writable "ada")))
    (littoral.auth:store-set-password-hash writable ada (littoral.auth:hash-password "a passphrase"))
    (list (littoral.auth:store-writable-p read-only)
          (littoral.auth:store-writable-p writable)
          (littoral.auth:verify-password "a passphrase" (littoral.auth:user-password-hash ada))
          (handler-case (littoral.auth:store-set-password-hash read-only ada "x")
            (error (e) (princ-to-string e))))))
;; ⇒ (NIL T T "This user store is read-only: it can't change passwords.")
```

#### `store-verify-password` `store password hash` — generic function

True when `password` matches `hash` as `store` keeps them.

*Example:* `:verify` replaces the built-in hash formats, for a table whose hashes Littoral can't read.

```lisp
(let ((store (littoral.auth:make-sql-user-store
              :table "people"
              :verify (lambda (password hash) (string= hash (reverse password))))))
  (list (littoral.auth:store-verify-password store "secret" "terces")
        (littoral.auth:store-verify-password store "secret" "secret")))
;; ⇒ (T NIL)
```

#### `sql-user-store` — class

Users kept in an application's own table, described by its column names.

#### `sql-user-store` `object` — generic function

Reads the store of a sql-user.

*Example:* Sign in against an application's own accounts table, naming its columns.  Its bcrypt hashes verify as they are, and its roles come from a query.  Littoral's own tables are made without a users table.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.db:db-execute "CREATE TABLE accounts (account_id INTEGER PRIMARY KEY, login TEXT,
                           email TEXT, pw_hash TEXT, enabled INTEGER)")
  (littoral.db:db-execute "CREATE TABLE account_roles (account_id INTEGER, role TEXT)")
  (littoral.db:db-execute "INSERT INTO accounts (login, email, pw_hash, enabled) VALUES (?, ?, ?, 1)"
                          "ada" "ada@example.org" (littoral.auth:bcrypt-hash "ada's long secret" :cost 4))
  (littoral.db:db-execute "INSERT INTO account_roles VALUES (1, 'admin')")
  (littoral.auth:create-auth-tables :users nil)
  (let ((littoral.auth:*user-store*
          (littoral.auth:make-sql-user-store
           :table "accounts" :id "account_id" :name "login" :email "email"
           :password "pw_hash" :active "enabled"
           :roles-query "SELECT role FROM account_roles WHERE account_id = ?")))
    (let ((ada (littoral.auth:authenticate "ADA" "ada's long secret")))
      (list (type-of ada)
            (littoral.auth:user-id ada)
            (littoral.auth:user-name ada)
            (littoral.auth:user-roles ada)))))
;; ⇒ (LITTORAL.AUTH:SQL-USER 1 "ada" (:ADMIN))
```

#### `make-sql-user-store` `&key table (id "id") (name "name") email (password "password_hash") active roles-column roles-query writable create (case-insensitive t) verify` — function

A user store over `table`, whose columns are `id`, `name`, `email` (optional),
`password` (the hash) and `active` (optional: a boolean or 0/1 column).  Roles
come from `roles-column` (comma-separated names) or `roles-query` (SQL with one
?, the user's id, returning role names in its first column).  `name` and
`email` match regardless of case unless `case-insensitive` is `nil`.  `verify`, a
function of (`password` `hash`), replaces the built-in hash formats.  With
`writable`, password changes and resets write the password column; with
`create`, OAuth sign-in may add users (name and email).  Signals an error
when `table` or a column isn't a plain SQL name.

*Example:* Sign in against an application's own accounts table, naming its columns.  Its bcrypt hashes verify as they are, and its roles come from a query.  Littoral's own tables are made without a users table.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.db:db-execute "CREATE TABLE accounts (account_id INTEGER PRIMARY KEY, login TEXT,
                           email TEXT, pw_hash TEXT, enabled INTEGER)")
  (littoral.db:db-execute "CREATE TABLE account_roles (account_id INTEGER, role TEXT)")
  (littoral.db:db-execute "INSERT INTO accounts (login, email, pw_hash, enabled) VALUES (?, ?, ?, 1)"
                          "ada" "ada@example.org" (littoral.auth:bcrypt-hash "ada's long secret" :cost 4))
  (littoral.db:db-execute "INSERT INTO account_roles VALUES (1, 'admin')")
  (littoral.auth:create-auth-tables :users nil)
  (let ((littoral.auth:*user-store*
          (littoral.auth:make-sql-user-store
           :table "accounts" :id "account_id" :name "login" :email "email"
           :password "pw_hash" :active "enabled"
           :roles-query "SELECT role FROM account_roles WHERE account_id = ?")))
    (let ((ada (littoral.auth:authenticate "ADA" "ada's long secret")))
      (list (type-of ada)
            (littoral.auth:user-id ada)
            (littoral.auth:user-name ada)
            (littoral.auth:user-roles ada)))))
;; ⇒ (LITTORAL.AUTH:SQL-USER 1 "ada" (:ADMIN))
```

*Example:* Table and column names must be plain SQL names: they are written into queries.

```lisp
(handler-case (littoral.auth:make-sql-user-store :table "accounts; DROP TABLE accounts")
  (error (e) (princ-to-string e)))
;; ⇒ "The table must be a plain SQL name, not \"accounts; DROP TABLE accounts\"."
```

#### `sql-user` — class

A user read from a `sql-user-store`'s table.

*Example:* Sign in against an application's own accounts table, naming its columns.  Its bcrypt hashes verify as they are, and its roles come from a query.  Littoral's own tables are made without a users table.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.db:db-execute "CREATE TABLE accounts (account_id INTEGER PRIMARY KEY, login TEXT,
                           email TEXT, pw_hash TEXT, enabled INTEGER)")
  (littoral.db:db-execute "CREATE TABLE account_roles (account_id INTEGER, role TEXT)")
  (littoral.db:db-execute "INSERT INTO accounts (login, email, pw_hash, enabled) VALUES (?, ?, ?, 1)"
                          "ada" "ada@example.org" (littoral.auth:bcrypt-hash "ada's long secret" :cost 4))
  (littoral.db:db-execute "INSERT INTO account_roles VALUES (1, 'admin')")
  (littoral.auth:create-auth-tables :users nil)
  (let ((littoral.auth:*user-store*
          (littoral.auth:make-sql-user-store
           :table "accounts" :id "account_id" :name "login" :email "email"
           :password "pw_hash" :active "enabled"
           :roles-query "SELECT role FROM account_roles WHERE account_id = ?")))
    (let ((ada (littoral.auth:authenticate "ADA" "ada's long secret")))
      (list (type-of ada)
            (littoral.auth:user-id ada)
            (littoral.auth:user-name ada)
            (littoral.auth:user-roles ada)))))
;; ⇒ (LITTORAL.AUTH:SQL-USER 1 "ada" (:ADMIN))
```

### Passwords

#### `hash-password` `password` — function

A new hash of `password`: salted `pbkdf2-sha256`, as one string.

*Example:* A new hash is salted, so hashing the same password twice gives different strings; each verifies.

```lisp
(let ((littoral.auth:*pbkdf2-iterations* 1000))
  (let ((one (littoral.auth:hash-password "correct horse battery"))
        (two (littoral.auth:hash-password "correct horse battery")))
    (list (subseq one 0 19)
          (string= one two)
          (littoral.auth:verify-password "correct horse battery" one)
          (littoral.auth:verify-password "Correct horse battery" one))))
;; ⇒ ("PBKDF2$SHA256:1000$" NIL T NIL)
```

#### `verify-password` `password hash` — function

True when `password` matches `hash`, in Littoral's own format, bcrypt, or
Django's or Werkzeug's PBKDF2.  False for anything else, never an error.

*Example:* A new hash is salted, so hashing the same password twice gives different strings; each verifies.

```lisp
(let ((littoral.auth:*pbkdf2-iterations* 1000))
  (let ((one (littoral.auth:hash-password "correct horse battery"))
        (two (littoral.auth:hash-password "correct horse battery")))
    (list (subseq one 0 19)
          (string= one two)
          (littoral.auth:verify-password "correct horse battery" one)
          (littoral.auth:verify-password "Correct horse battery" one))))
;; ⇒ ("PBKDF2$SHA256:1000$" NIL T NIL)
```

*Example:* Hashes from other frameworks verify too: here Werkzeug's (Flask) and Django's PBKDF2.  Anything else is simply false.

```lisp
(list (littoral.auth:verify-password
       "correct horse battery"
       "pbkdf2:sha256:1000$seasalt1234$7550ac791a251d65e7ddd282ac996a427107369b72fe00b683aa5462d0864ffe")
      (littoral.auth:verify-password
       "correct horse battery"
       "pbkdf2_sha256$1000$seasalt1234$dVCseRolHWXn3dKCrJlqQnEHNpty/gC2g6pUYtCGT/4=")
      (littoral.auth:verify-password "correct horse battery" "plain text")
      (littoral.auth:verify-password "correct horse battery" nil))
;; ⇒ (T T NIL NIL)
```

#### `password-needs-rehash-p` `hash` — function

True unless `hash` is Littoral's `pbkdf2-sha256` with at least `*pbkdf2-iterations*`.

*Example:* False only for Littoral's own hashes with at least `*pbkdf2-iterations*`: a hash made with fewer, or in another format, is upgraded when its owner next signs in.

```lisp
(let ((hash (let ((littoral.auth:*pbkdf2-iterations* 1000))
              (littoral.auth:hash-password "s3cret pass"))))
  (list (let ((littoral.auth:*pbkdf2-iterations* 1000))
          (littoral.auth:password-needs-rehash-p hash))
        (let ((littoral.auth:*pbkdf2-iterations* 5000))
          (littoral.auth:password-needs-rehash-p hash))
        (littoral.auth:password-needs-rehash-p (littoral.auth:bcrypt-hash "s3cret pass" :cost 4))))
;; ⇒ (NIL T T)
```

#### `bcrypt-hash` `password &key (cost 12) (salt (random-data 16))` — function

A $2b$ bcrypt hash of `password` with `cost` (12) and `salt` (16 random bytes),
for seeding a table that expects them.

*Example:* A bcrypt hash, as Rails, Laravel or `php` make them, for seeding a table an older application also reads.  `cost` 4 is the quickest bcrypt allows.

```lisp
(let ((hash (littoral.auth:bcrypt-hash "made here" :cost 4)))
  (list (subseq hash 0 7)
        (length hash)
        (littoral.auth:verify-password "made here" hash)))
;; ⇒ ("$2b$04$" 60 T)
```

#### `*pbkdf2-iterations*` — variable

`pbkdf2-sha256` iterations for new password hashes (`owasp`'s 2023 advice).
Hashes with fewer are upgraded when their owner next signs in.

*Example:* False only for Littoral's own hashes with at least `*pbkdf2-iterations*`: a hash made with fewer, or in another format, is upgraded when its owner next signs in.

```lisp
(let ((hash (let ((littoral.auth:*pbkdf2-iterations* 1000))
              (littoral.auth:hash-password "s3cret pass"))))
  (list (let ((littoral.auth:*pbkdf2-iterations* 1000))
          (littoral.auth:password-needs-rehash-p hash))
        (let ((littoral.auth:*pbkdf2-iterations* 5000))
          (littoral.auth:password-needs-rehash-p hash))
        (littoral.auth:password-needs-rehash-p (littoral.auth:bcrypt-hash "s3cret pass" :cost 4))))
;; ⇒ (NIL T T)
```

#### `*rehash-on-sign-in*` — variable

When true, signing in re-hashes a password kept in another format (bcrypt,
Django's) or with fewer than `*pbkdf2-iterations*`, where the store can write.

*Example:* Signing in re-hashes a weaker hash, where the store can write; binding it to `nil` leaves hashes as they are.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")))
    (littoral.auth:store-set-password-hash littoral.auth:*user-store* ada
                                           (littoral.auth:bcrypt-hash "correct horse battery" :cost 4))
    (let ((littoral.auth:*rehash-on-sign-in* nil))
      (littoral.auth:authenticate "ada" "correct horse battery"))
    (let ((kept (subseq (littoral.auth:user-password-hash (littoral.auth:find-user "ada")) 0 4)))
      (littoral.auth:authenticate "ada" "correct horse battery")
      (list kept (subseq (littoral.auth:user-password-hash (littoral.auth:find-user "ada")) 0 7)))))
;; ⇒ ("$2b$" "PBKDF2$")
```

### Tables and users

#### `create-auth-tables` `&key (users t)` — function

Create or bring up to date the tables signing in needs, by their
migrations (`:littoral-users`, `:littoral-auth`): the users table (names and
emails unique whatever their case) unless `users` is `nil`, as when users come
from an application's own table, the tokens, sign-ins, roles and
permissions tables, and the audit log.

*Example:* Make the tables in a database, add users, and find them by name, whatever its case.  A low `*pbkdf2-iterations*` keeps hashing quick while trying things out.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin))
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (let ((ada (littoral.auth:find-user "ADA")))
    (list (littoral.auth:user-name ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:find-user "nobody"))))
;; ⇒ ("ada" (:ADMIN) NIL)
```

#### `drop-auth-tables` `&key (users t)` — function

Drop the tables `create-auth-tables` makes, the audit log too, for tests:
everything is lost.  With `users` `nil`, the users table stays.

*Example:* For tests: drop every table `create-auth-tables` made, users and all, then make them afresh.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (littoral.auth:drop-auth-tables)
  (littoral.auth:create-auth-tables)
  (littoral.auth:find-user "ada"))
;; ⇒ NIL
```

#### `purge-expired-auth-rows` — function

Delete sign-in failures and reset mails too old to count, expired
sign-ins, and expired reset links and API tokens; how many rows.  Run it
from a nightly job: signing in tidies up only now and then.

*Example:* Run nightly, it deletes what no longer counts, and says how many rows went.  Here, a sign-in failure from two hours ago.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:authenticate "nobody" "guess")
  (littoral.db:db-execute "UPDATE auth_events SET happened = happened - 7200")
  (list (littoral.auth:purge-expired-auth-rows)
        (littoral.auth:purge-expired-auth-rows)))
;; ⇒ (1 0)
```

#### `add-user` `name email password &key roles` — function

Store a new user called `name`, with `email` and `password` (hashed; `nil` for
none, so they can't sign in with one), and return it.  `roles` are keywords.
Signals an error when `name` is taken, case aside, or the store doesn't
create users.

*Example:* Make the tables in a database, add users, and find them by name, whatever its case.  A low `*pbkdf2-iterations*` keeps hashing quick while trying things out.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin))
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (let ((ada (littoral.auth:find-user "ADA")))
    (list (littoral.auth:user-name ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:find-user "nobody"))))
;; ⇒ ("ada" (:ADMIN) NIL)
```

*Example:* Names are unique, case aside.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (handler-case (littoral.auth:add-user "Ada" "other@example.org" "a passphrase")
    (error (e) (princ-to-string e))))
;; ⇒ "The name Ada is taken."
```

#### `find-user` `name` — function

The user called `name` (case aside, in the built-in store), or `nil`.

*Example:* Make the tables in a database, add users, and find them by name, whatever its case.  A low `*pbkdf2-iterations*` keeps hashing quick while trying things out.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin))
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (let ((ada (littoral.auth:find-user "ADA")))
    (list (littoral.auth:user-name ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:find-user "nobody"))))
;; ⇒ ("ada" (:ADMIN) NIL)
```

#### `find-user-by-email` `email` — function

The user whose email is `email`, or `nil`.

*Example:* Emails match whatever their case.  An id may be given as its printed form, as cookies and tables keep it.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (list (littoral.auth:user-name (littoral.auth:find-user-by-email "ADA@example.org"))
        (littoral.auth:user-name (littoral.auth:find-user-by-id 1))
        (littoral.auth:user-name (littoral.auth:find-user-by-id "1"))
        (littoral.auth:find-user-by-id 2)))
;; ⇒ ("ada" "ada" "ada" NIL)
```

#### `find-user-by-id` `id` — function

The user whose `user-id` is `id`, or `nil`.

*Example:* Emails match whatever their case.  An id may be given as its printed form, as cookies and tables keep it.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (list (littoral.auth:user-name (littoral.auth:find-user-by-email "ADA@example.org"))
        (littoral.auth:user-name (littoral.auth:find-user-by-id 1))
        (littoral.auth:user-name (littoral.auth:find-user-by-id "1"))
        (littoral.auth:find-user-by-id 2)))
;; ⇒ ("ada" "ada" "ada" NIL)
```

#### `set-password` `user password` — function

Give `user` the new `password`, and void their outstanding reset links.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")))
    (littoral.auth:set-password ada "a new passphrase")
    (list (littoral.auth:check-password ada "correct horse battery")
          (littoral.auth:check-password ada "a new passphrase"))))
;; ⇒ (NIL T)
```

#### `check-password` `user password` — function

True when `password` is `user`'s.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")))
    (littoral.auth:set-password ada "a new passphrase")
    (list (littoral.auth:check-password ada "correct horse battery")
          (littoral.auth:check-password ada "a new passphrase"))))
;; ⇒ (NIL T)
```

#### `authenticate` `name password` — function

The active user `name` if `password` is theirs and neither the name nor the
client's address is locked out; otherwise `nil` and, as a second value, why.

*Example:* The user, when the password is right; otherwise `nil` and why, in words for the sign-in form.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (list (littoral.auth:user-name (littoral.auth:authenticate "ada" "correct horse battery"))
        (multiple-value-list (littoral.auth:authenticate "ada" "wrong"))
        (multiple-value-list (littoral.auth:authenticate "nobody" "wrong"))))
;; ⇒ ("ada" (NIL "Unknown user or wrong password.") (NIL "Unknown user or wrong password."))
```

*Example:* After `*lockout-failures*` wrong passwords for a name, even the right one is refused until `*lockout-seconds*` pass.  Failures are kept in the database, so every process sees them.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*lockout-failures* 3)
      (littoral.auth:*lockout-seconds* 60))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (dotimes (i 3) (littoral.auth:authenticate "bob" "guess"))
  (nth-value 1 (littoral.auth:authenticate "bob" "another passphrase")))
;; ⇒ "Too many failed attempts; try again in a minute."
```

### Signing in

#### `current-user` — function

The user signed in to this session, or `nil`; `nil` outside a request.

*Example:* A `restricted` component shows a sign-in prompt in its place until someone signs in.  The root is an `auth-root`, so a sign-in comes back in a new session.

```lisp
(defclass members-news (littoral.auth:restricted component) ())
(defmethod render ((self members-news))
  (p () "Members' news"))
(defclass club (littoral.auth:auth-root component)
  ((news :initform (make-instance 'members-news) :reader club-news)))
(defmethod children ((self club)) (list (club-news self)))
(defmethod render ((self club))
  (let ((user (littoral.auth:current-user)))
    (p () (text (if user (format nil "Hello, ~A." (littoral.auth:user-name user)) "Hello, stranger."))))
  (render-component (club-news self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/club" 'club :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/club")
      (let ((before (body-text b)))
        (click b "Sign in")
        (fill-in b "sign-in-name" "bob")
        (fill-in b "sign-in-password" "another passphrase")
        (press b "Sign in")
        (list before (body-text b))))))
;; ⇒ ("Hello, stranger. Please sign in to see this. Sign in" "Hello, bob. Members' news")
```

#### `log-in` `user &key remember (method "password")` — function

Sign `user` in to this session, recording the sign-in in the database so
it survives restarts; with `remember`, for `*remember-days*` rather than until
the browser closes.  The session gets a new key, so a link to it that
someone else had beforehand no longer reaches it.  `method`, how they proved
who they are, goes in the audit log.

*Example:* Sign a user in from a callback, without the form: here, a demo account.

```lisp
(defclass demo-door (littoral.auth:auth-root component) ())
(defmethod render ((self demo-door))
  (if (littoral.auth:signed-in-p)
      (progn (p () (text (format nil "Signed in as ~A." (littoral.auth:user-name (littoral.auth:current-user)))))
             (anchor (:callback (lambda () (littoral.auth:log-out))) "Leave"))
      (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "demo")))) "Try the demo")))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "demo" "demo@example.org" nil)
  (with-fresh-applications (("/demo" 'demo-door :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/demo")
      (click b "Try the demo")
      (let ((in (body-text b)))
        (click b "Leave")
        (list in (body-text b))))))
;; ⇒ ("Signed in as demo. Leave" "Try the demo")
```

#### `log-out` — function

Sign the session's user out, end its sign-in, and give the session a new key.

*Example:* Sign a user in from a callback, without the form: here, a demo account.

```lisp
(defclass demo-door (littoral.auth:auth-root component) ())
(defmethod render ((self demo-door))
  (if (littoral.auth:signed-in-p)
      (progn (p () (text (format nil "Signed in as ~A." (littoral.auth:user-name (littoral.auth:current-user)))))
             (anchor (:callback (lambda () (littoral.auth:log-out))) "Leave"))
      (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "demo")))) "Try the demo")))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "demo" "demo@example.org" nil)
  (with-fresh-applications (("/demo" 'demo-door :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/demo")
      (click b "Try the demo")
      (let ((in (body-text b)))
        (click b "Leave")
        (list in (body-text b))))))
;; ⇒ ("Signed in as demo. Leave" "Try the demo")
```

#### `signed-in-p` — function

True when someone is signed in to this session.

*Example:* Sign a user in from a callback, without the form: here, a demo account.

```lisp
(defclass demo-door (littoral.auth:auth-root component) ())
(defmethod render ((self demo-door))
  (if (littoral.auth:signed-in-p)
      (progn (p () (text (format nil "Signed in as ~A." (littoral.auth:user-name (littoral.auth:current-user)))))
             (anchor (:callback (lambda () (littoral.auth:log-out))) "Leave"))
      (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "demo")))) "Try the demo")))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "demo" "demo@example.org" nil)
  (with-fresh-applications (("/demo" 'demo-door :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/demo")
      (click b "Try the demo")
      (let ((in (body-text b)))
        (click b "Leave")
        (list in (body-text b))))))
;; ⇒ ("Signed in as demo. Leave" "Try the demo")
```

#### `has-role-p` `role &optional (user (current-user))` — function

True when `user` has `role` (a keyword); with `role` `nil`, when there is a user.

*Example:* Show what only some may use with `has-role-p`; guard the callback itself with `require-role`, which refuses with a 403.

```lisp
(defclass report-page (littoral.auth:auth-root component) ())
(defmethod render ((self report-page))
  (when (littoral.auth:has-role-p :admin)
    (p () "Admin tools"))
  (anchor (:callback (lambda () (littoral.auth:require-role :admin))) "Delete everything")
  (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "bob")))) "Be bob"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/reports" 'report-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/reports")
      (click b "Be bob")
      (let ((tools (has-text-p b "Admin tools")))
        (click b "Delete everything")
        (list tools (browser-status b))))))
;; ⇒ (NIL 403)
```

#### `require-role` `role` — function

Refuse the request (403) unless the current user has `role`; with `role`
`nil`, unless someone is signed in.

*Example:* Show what only some may use with `has-role-p`; guard the callback itself with `require-role`, which refuses with a 403.

```lisp
(defclass report-page (littoral.auth:auth-root component) ())
(defmethod render ((self report-page))
  (when (littoral.auth:has-role-p :admin)
    (p () "Admin tools"))
  (anchor (:callback (lambda () (littoral.auth:require-role :admin))) "Delete everything")
  (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "bob")))) "Be bob"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/reports" 'report-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/reports")
      (click b "Be bob")
      (let ((tools (has-text-p b "Admin tools")))
        (click b "Delete everything")
        (list tools (browser-status b))))))
;; ⇒ (NIL 403)
```

#### `*remember-days*` — variable

How long "Keep me signed in" lasts, renewed by use.

*Example:* A sign-in lasts `*sign-in-idle-hours*` unused, and its cookie until the browser closes; "Keep me signed in" makes it last `*remember-days*`.

```lisp
(defclass remembering (littoral.auth:auth-root component) ())
(defmethod render ((self remembering))
  (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "ada") :remember t))) "Remember me"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*remember-days* 7))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (with-fresh-applications (("/r" 'remembering :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/r")
      (multiple-value-bind (status headers) (raw-request b :get (find-link b "Remember me"))
        (declare (ignore status))
        (let ((cookie (find-if (lambda (c) (search "_lta" c))
                               (loop for (key value) on headers by #'cddr
                                     when (eq key :set-cookie) collect value))))
          (not (null (search (format nil "Max-Age=~D" (* 7 86400)) cookie))))))))
;; ⇒ T
```

#### `*sign-in-idle-hours*` — variable

How long an unremembered sign-in lasts unused.

*Example:* A sign-in lasts `*sign-in-idle-hours*` unused, and its cookie until the browser closes; "Keep me signed in" makes it last `*remember-days*`.

```lisp
(defclass remembering (littoral.auth:auth-root component) ())
(defmethod render ((self remembering))
  (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "ada") :remember t))) "Remember me"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*remember-days* 7))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (with-fresh-applications (("/r" 'remembering :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/r")
      (multiple-value-bind (status headers) (raw-request b :get (find-link b "Remember me"))
        (declare (ignore status))
        (let ((cookie (find-if (lambda (c) (search "_lta" c))
                               (loop for (key value) on headers by #'cddr
                                     when (eq key :set-cookie) collect value))))
          (not (null (search (format nil "Max-Age=~D" (* 7 86400)) cookie))))))))
;; ⇒ T
```

#### `*auth-session-check-seconds*` — variable

How often a signed-in session checks that its sign-in still stands.

*Example:* Each sign-in is a row in the database, listed by `user-sessions` as plists.  Revoking one signs that browser out within `*auth-session-check-seconds*`.

```lisp
(defclass account-page (littoral.auth:auth-root component) ())
(defmethod render ((self account-page))
  (let ((user (littoral.auth:current-user)))
    (if user
        (let ((sessions (littoral.auth:user-sessions user)))
          (p () (text (format nil "~A has ~D sign-in~:P." (littoral.auth:user-name user) (length sessions))))
          (anchor (:callback (lambda ()
                               (dolist (session sessions)
                                 (unless (getf session :current)
                                   (littoral.auth:revoke-session (getf session :id))))))
            "End the others"))
        (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "ada")))) "Sign in"))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*auth-session-check-seconds* 0))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (with-fresh-applications (("/account" 'account-page :mode :deployment))
    (let ((laptop (make-instance 'browser)) (phone (make-instance 'browser)))
      (visit laptop "/account") (click laptop "Sign in")
      (visit phone "/account") (click phone "Sign in")
      (let ((before (body-text phone)))
        (click phone "End the others")
        (visit laptop (browser-url laptop))
        (list before (body-text phone) (body-text laptop))))))
;; ⇒ ("ada has 2 sign-ins. End the others" "ada has 1 sign-in. End the others" "Sign in")
```

#### `*offer-remember-me*` — variable

Whether the sign-in form offers "Keep me signed in".

*Example:* What the sign-in form offers, besides a name and password.

```lisp
(defclass sign-in-page (component) ())
(defmethod render ((self sign-in-page))
  (render-component (make-instance 'littoral.auth:sign-in)))
(with-fresh-applications (("/sign-in" 'sign-in-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (list (progn (visit b "/sign-in") (body-text b))
          (let ((littoral.auth:*offer-remember-me* nil)
                (littoral.auth:*offer-passkeys* nil))
            (visit b "/sign-in")
            (body-text b)))))
;; ⇒ ("Sign in Name Password Keep me signed in Sign in Cancel Forgot your password? Sign in with a passkey" "Sign in Name Password Sign in Cancel Forgot your password?")
```

#### `user-sessions` `user` — function

`user`'s standing sign-ins, newest first, as plists of `:id` `:created`
`:last-seen` `:remember` `:user-agent` `:address` and `:current` (this session's).

*Example:* Each sign-in is a row in the database, listed by `user-sessions` as plists.  Revoking one signs that browser out within `*auth-session-check-seconds*`.

```lisp
(defclass account-page (littoral.auth:auth-root component) ())
(defmethod render ((self account-page))
  (let ((user (littoral.auth:current-user)))
    (if user
        (let ((sessions (littoral.auth:user-sessions user)))
          (p () (text (format nil "~A has ~D sign-in~:P." (littoral.auth:user-name user) (length sessions))))
          (anchor (:callback (lambda ()
                               (dolist (session sessions)
                                 (unless (getf session :current)
                                   (littoral.auth:revoke-session (getf session :id))))))
            "End the others"))
        (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "ada")))) "Sign in"))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*auth-session-check-seconds* 0))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (with-fresh-applications (("/account" 'account-page :mode :deployment))
    (let ((laptop (make-instance 'browser)) (phone (make-instance 'browser)))
      (visit laptop "/account") (click laptop "Sign in")
      (visit phone "/account") (click phone "Sign in")
      (let ((before (body-text phone)))
        (click phone "End the others")
        (visit laptop (browser-url laptop))
        (list before (body-text phone) (body-text laptop))))))
;; ⇒ ("ada has 2 sign-ins. End the others" "ada has 1 sign-in. End the others" "Sign in")
```

#### `revoke-session` `id &optional (user (current-user))` — function

End `user`'s sign-in `id` wherever it is; that browser is signed out within
`*auth-session-check-seconds*`, this one at once.

*Example:* Each sign-in is a row in the database, listed by `user-sessions` as plists.  Revoking one signs that browser out within `*auth-session-check-seconds*`.

```lisp
(defclass account-page (littoral.auth:auth-root component) ())
(defmethod render ((self account-page))
  (let ((user (littoral.auth:current-user)))
    (if user
        (let ((sessions (littoral.auth:user-sessions user)))
          (p () (text (format nil "~A has ~D sign-in~:P." (littoral.auth:user-name user) (length sessions))))
          (anchor (:callback (lambda ()
                               (dolist (session sessions)
                                 (unless (getf session :current)
                                   (littoral.auth:revoke-session (getf session :id))))))
            "End the others"))
        (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "ada")))) "Sign in"))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*auth-session-check-seconds* 0))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (with-fresh-applications (("/account" 'account-page :mode :deployment))
    (let ((laptop (make-instance 'browser)) (phone (make-instance 'browser)))
      (visit laptop "/account") (click laptop "Sign in")
      (visit phone "/account") (click phone "Sign in")
      (let ((before (body-text phone)))
        (click phone "End the others")
        (visit laptop (browser-url laptop))
        (list before (body-text phone) (body-text laptop))))))
;; ⇒ ("ada has 2 sign-ins. End the others" "ada has 1 sign-in. End the others" "Sign in")
```

#### `log-out-everywhere` `&optional (user (current-user))` — function

End all of `user`'s sign-ins, this one too.

*Example:* End every sign-in of a user, this browser's too: say, after their password was stolen.

```lisp
(defclass lost-phone (littoral.auth:auth-root component) ())
(defmethod render ((self lost-phone))
  (if (littoral.auth:signed-in-p)
      (anchor (:callback (lambda () (littoral.auth:log-out-everywhere))) "Sign out everywhere")
      (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "ada")))) "Sign in")))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")))
    (with-fresh-applications (("/lost" 'lost-phone :mode :deployment))
      (let ((laptop (make-instance 'browser)) (phone (make-instance 'browser)))
        (visit laptop "/lost") (click laptop "Sign in")
        (visit phone "/lost") (click phone "Sign in")
        (let ((before (length (littoral.auth:user-sessions ada))))
          (click phone "Sign out everywhere")
          (list before (length (littoral.auth:user-sessions ada)) (body-text phone)))))))
;; ⇒ (2 0 "Sign in")
```

### Limits on signing in

#### `*lockout-failures*` — variable

Failed attempts on one name, within `*failure-window-seconds*`, before it is locked.

*Example:* After `*lockout-failures*` wrong passwords for a name, even the right one is refused until `*lockout-seconds*` pass.  Failures are kept in the database, so every process sees them.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*lockout-failures* 3)
      (littoral.auth:*lockout-seconds* 60))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (dotimes (i 3) (littoral.auth:authenticate "bob" "guess"))
  (nth-value 1 (littoral.auth:authenticate "bob" "another passphrase")))
;; ⇒ "Too many failed attempts; try again in a minute."
```

#### `*lockout-seconds*` — variable

How long a name stays locked after its latest failure.

*Example:* After `*lockout-failures*` wrong passwords for a name, even the right one is refused until `*lockout-seconds*` pass.  Failures are kept in the database, so every process sees them.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*lockout-failures* 3)
      (littoral.auth:*lockout-seconds* 60))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (dotimes (i 3) (littoral.auth:authenticate "bob" "guess"))
  (nth-value 1 (littoral.auth:authenticate "bob" "another passphrase")))
;; ⇒ "Too many failed attempts; try again in a minute."
```

#### `*failure-window-seconds*` — variable

How long a failed attempt counts against a name or an address.

*Example:* Limits per client address apply to public addresses only: a loopback or private one is usually a proxy every visitor shares.  Here one public address tries many names, and is stopped even for a name it hasn't tried.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*failures-per-address* 3)
      (littoral.auth:*failure-window-seconds* 900)
      (*request* (lack/request:make-request
                  (let ((env (make-env :get "/")))
                    (setf (getf env :remote-addr) "203.0.113.5")
                    env))))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (dolist (name '("carol" "dave" "erin"))
    (littoral.auth:authenticate name "password1"))
  (multiple-value-list (littoral.auth:authenticate "bob" "another passphrase")))
;; ⇒ (NIL "Too many failed attempts; try again in a minute.")
```

#### `*failures-per-address*` — variable

Failed sign-ins from one public client address, within
`*failure-window-seconds*`, before it may try no more names for
`*lockout-seconds*`.  Stops one address guessing a common password across
many names.  Loopback and private addresses, usually a proxy's, are not
limited: behind a proxy, set `*trust-forwarded-for*` so the limit sees clients.

*Example:* Limits per client address apply to public addresses only: a loopback or private one is usually a proxy every visitor shares.  Here one public address tries many names, and is stopped even for a name it hasn't tried.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*failures-per-address* 3)
      (littoral.auth:*failure-window-seconds* 900)
      (*request* (lack/request:make-request
                  (let ((env (make-env :get "/")))
                    (setf (getf env :remote-addr) "203.0.113.5")
                    env))))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (dolist (name '("carol" "dave" "erin"))
    (littoral.auth:authenticate name "password1"))
  (multiple-value-list (littoral.auth:authenticate "bob" "another passphrase")))
;; ⇒ (NIL "Too many failed attempts; try again in a minute.")
```

#### `*reset-mails-per-address*` — variable

Reset mails one client address may have sent, within `*failure-window-seconds*`.

### Password reset

#### `*public-url*` — variable

This site's address as its users reach it, such as "https://example.org",
for links in mail and OAuth redirects.  Required in deployment mode: the
request's Host header is the client's to choose, and a reset link built
from a forged one would send its token to someone else's site.

*Example:* "Forgot your password?" on the sign-in form mails a link built from `*public-url*`.  Following it, at the `auth-root` application, shows the form for a new password, which then signs the user in.

```lisp
(defclass reading-room (littoral.auth:auth-root component) ())
(defmethod render ((self reading-room))
  (let ((user (littoral.auth:current-user)))
    (if user
        (p () (text (format nil "Hello, ~A." (littoral.auth:user-name user))))
        (anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in)))) "Sign in"))))
(let* ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
       (littoral.auth:*pbkdf2-iterations* 1000)
       (littoral.auth:*public-url* "https://library.example")
       (mails '())
       (littoral.auth:*send-mail* (lambda (to subject body) (push (list to subject body) mails))))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/library" 'reading-room :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/library")
      (click b "Sign in")
      (click b "Forgot your password?")
      (fill-in b "reset-email" "bob@example.org")
      (press b "Send me a link")
      (destructuring-bind (to subject body) (first mails)
        (let ((link (cl-ppcre:scan-to-strings "https://library.example/library/reset\\?token=\\S+" body))
              (other (make-instance 'browser)))
          (visit other link)
          (fill-in other "new-password" "a brand new passphrase")
          (fill-in other "new-password-again" "a brand new passphrase")
          (press other "Save and sign in")
          (list to subject (body-text other)
                (littoral.auth:check-password (littoral.auth:find-user "bob") "a brand new passphrase")))))))
;; ⇒ ("bob@example.org" "Choose a new password" "Hello, bob." T)
```

#### `*reset-link-seconds*` — variable

How long a password reset link works.

*Example:* How long a reset link works: an hour, unless bound.  Here the link is aged two hours before it is followed.

```lisp
(defclass short-links (littoral.auth:auth-root component) ())
(defmethod render ((self short-links))
  (anchor (:callback (lambda () (show self (make-instance 'littoral.auth:password-reset-request)))) "Reset"))
(let* ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
       (littoral.auth:*pbkdf2-iterations* 1000)
       (littoral.auth:*public-url* "https://short.example")
       (littoral.auth:*reset-link-seconds* 3600)
       (littoral.auth:*send-mail* (lambda (to subject body) (declare (ignore to subject body)))))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/short" 'short-links :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/short")
      (click b "Reset")
      (fill-in b "reset-email" "bob@example.org")
      (press b "Send me a link")
      (littoral.db:db-execute "UPDATE auth_tokens SET expires = expires - 7200")
      (visit b (cl-ppcre:scan-to-strings "https://\\S+" (third littoral.auth:*last-mail*)))
      (body-text b))))
;; ⇒ "That link has expired or been used. Ask for a new one. OK"
```

#### `*send-mail*` — variable

A function of (`to` `subject` `body`) that sends mail.  The default prints it;
plug in your mailer.

*Example:* "Forgot your password?" on the sign-in form mails a link built from `*public-url*`.  Following it, at the `auth-root` application, shows the form for a new password, which then signs the user in.

```lisp
(defclass reading-room (littoral.auth:auth-root component) ())
(defmethod render ((self reading-room))
  (let ((user (littoral.auth:current-user)))
    (if user
        (p () (text (format nil "Hello, ~A." (littoral.auth:user-name user))))
        (anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in)))) "Sign in"))))
(let* ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
       (littoral.auth:*pbkdf2-iterations* 1000)
       (littoral.auth:*public-url* "https://library.example")
       (mails '())
       (littoral.auth:*send-mail* (lambda (to subject body) (push (list to subject body) mails))))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/library" 'reading-room :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/library")
      (click b "Sign in")
      (click b "Forgot your password?")
      (fill-in b "reset-email" "bob@example.org")
      (press b "Send me a link")
      (destructuring-bind (to subject body) (first mails)
        (let ((link (cl-ppcre:scan-to-strings "https://library.example/library/reset\\?token=\\S+" body))
              (other (make-instance 'browser)))
          (visit other link)
          (fill-in other "new-password" "a brand new passphrase")
          (fill-in other "new-password-again" "a brand new passphrase")
          (press other "Save and sign in")
          (list to subject (body-text other)
                (littoral.auth:check-password (littoral.auth:find-user "bob") "a brand new passphrase")))))))
;; ⇒ ("bob@example.org" "Choose a new password" "Hello, bob." T)
```

#### `*last-mail*` — variable

The last mail sent, as (`to` `subject` `body`), for development and tests.

*Example:* An address without an account gets the same answer, and no mail.  `*last-mail*` holds the last mail sent, for development.

```lisp
(defclass reset-page (component)
  ((form :initform (make-instance 'littoral.auth:password-reset-request) :reader reset-form)))
(defmethod children ((self reset-page)) (list (reset-form self)))
(defmethod render ((self reset-page))
  (render-component (reset-form self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*send-mail* (lambda (to subject body) (declare (ignore to subject body))))
      (littoral.auth:*last-mail* nil))
  (littoral.auth:create-auth-tables)
  (with-fresh-applications (("/reset-page" 'reset-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/reset-page")
      (fill-in b "reset-email" "nobody@example.org")
      (press b "Send me a link")
      (list (body-text b) littoral.auth:*last-mail*))))
;; ⇒ ("Reset your password If that address belongs to an account, a link to choose a new password is on its way. Back" NIL)
```

### API tokens

#### `endpoint-user` — function

In a JSON endpoint: the user the request comes from, or `nil`.

*Example:* A JSON endpoint knows who calls it: a script sends an API token as "Authorization: Bearer `token`"; a signed-in browser's cookie works too.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let* ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery"))
         (token (littoral.auth:create-api-token ada :days 30)))
    (with-fresh-applications (("/notes" 'component :mode :deployment))
      (define-endpoint "/notes" :get "/api/me" ()
        (list :name (littoral.auth:user-name (littoral.auth:require-endpoint-user))))
      (define-endpoint "/notes" :get "/api/hello" ()
        (let ((user (littoral.auth:endpoint-user)))
          (list :hello (if user (littoral.auth:user-name user) "stranger"))))
      (flet ((call-as (headers path)
               (multiple-value-bind (status response-headers body)
                   (raw-request (make-instance 'browser :headers headers) :get path)
                 (declare (ignore response-headers))
                 (list status body))))
        (list (call-as '() "/notes/api/me")
              (call-as `(("authorization" . ,(format nil "Bearer ~A" token))) "/notes/api/me")
              (call-as '() "/notes/api/hello"))))))
;; ⇒ ((401 "{\"error\":\"Sign in, or send an API token.\"}") (200 "{\"name\":\"ada\"}") (200 "{\"hello\":\"stranger\"}"))
```

#### `require-endpoint-user` `&optional role` — function

In a JSON endpoint: the user the request comes from, answering 401 when
there is none and 403 when they lack `role`.

*Example:* A JSON endpoint knows who calls it: a script sends an API token as "Authorization: Bearer `token`"; a signed-in browser's cookie works too.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let* ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery"))
         (token (littoral.auth:create-api-token ada :days 30)))
    (with-fresh-applications (("/notes" 'component :mode :deployment))
      (define-endpoint "/notes" :get "/api/me" ()
        (list :name (littoral.auth:user-name (littoral.auth:require-endpoint-user))))
      (define-endpoint "/notes" :get "/api/hello" ()
        (let ((user (littoral.auth:endpoint-user)))
          (list :hello (if user (littoral.auth:user-name user) "stranger"))))
      (flet ((call-as (headers path)
               (multiple-value-bind (status response-headers body)
                   (raw-request (make-instance 'browser :headers headers) :get path)
                 (declare (ignore response-headers))
                 (list status body))))
        (list (call-as '() "/notes/api/me")
              (call-as `(("authorization" . ,(format nil "Bearer ~A" token))) "/notes/api/me")
              (call-as '() "/notes/api/hello"))))))
;; ⇒ ((401 "{\"error\":\"Sign in, or send an API token.\"}") (200 "{\"name\":\"ada\"}") (200 "{\"hello\":\"stranger\"}"))
```

#### `create-api-token` `user &key (days 365)` — function

A new API token for `user`, valid `days` days (for good, with `days` `nil`): send
it as "Authorization: Bearer `token`".  Only its hash is kept, so show it once.

*Example:* A JSON endpoint knows who calls it: a script sends an API token as "Authorization: Bearer `token`"; a signed-in browser's cookie works too.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let* ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery"))
         (token (littoral.auth:create-api-token ada :days 30)))
    (with-fresh-applications (("/notes" 'component :mode :deployment))
      (define-endpoint "/notes" :get "/api/me" ()
        (list :name (littoral.auth:user-name (littoral.auth:require-endpoint-user))))
      (define-endpoint "/notes" :get "/api/hello" ()
        (let ((user (littoral.auth:endpoint-user)))
          (list :hello (if user (littoral.auth:user-name user) "stranger"))))
      (flet ((call-as (headers path)
               (multiple-value-bind (status response-headers body)
                   (raw-request (make-instance 'browser :headers headers) :get path)
                 (declare (ignore response-headers))
                 (list status body))))
        (list (call-as '() "/notes/api/me")
              (call-as `(("authorization" . ,(format nil "Bearer ~A" token))) "/notes/api/me")
              (call-as '() "/notes/api/hello"))))))
;; ⇒ ((401 "{\"error\":\"Sign in, or send an API token.\"}") (200 "{\"name\":\"ada\"}") (200 "{\"hello\":\"stranger\"}"))
```

#### `revoke-api-tokens` `user` — function

Void all of `user`'s API tokens; how many there were.

*Example:* Void every token of a user; how many there were.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")))
    (littoral.auth:create-api-token ada)
    (littoral.auth:create-api-token ada :days nil)
    (littoral.auth:revoke-api-tokens ada)))
;; ⇒ 2
```

### Second factors

#### `security-settings` — class

Second factors for the signed-in user: an authenticator app,
passkeys and recovery codes.

*Example:* A signed-in user sets up an authenticator app from the security settings: the page shows a QR code and the key, and the app's code turns it on.  From then on, signing in with a password asks for a code too.

```lisp
(defclass account (littoral.auth:auth-root component)
  ((security :initform (make-instance 'littoral.auth:security-settings) :reader account-security)))
(defmethod children ((self account)) (list (account-security self)))
(defmethod render ((self account))
  (let ((user (littoral.auth:current-user)))
    (p () (text (if user (format nil "Hello, ~A." (littoral.auth:user-name user)) "Hello, stranger."))))
  (render-component (account-security self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((bob (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")))
    (with-fresh-applications (("/account" 'account :mode :deployment))
      (flet ((sign-in (b)
               (visit b "/account")
               (click b "Sign in")
               (fill-in b "sign-in-name" "bob")
               (fill-in b "sign-in-password" "another passphrase")
               (press b "Sign in")))
        (let ((b (make-instance 'browser)))
          (sign-in b)
          (click b "Set up an authenticator app")
          (let ((secret (cl-ppcre:register-groups-bind (key) ("Key: <code>([A-Z2-7]+)</code>" (browser-html b)) key)))
            (fill-in b "totp-code" (littoral.auth:totp-code secret))
            (press b "Turn on")
            (let ((other (make-instance 'browser)))
              (sign-in other)
              (let ((asked (body-text other)))
                (fill-in other "sign-in-code" (littoral.auth:totp-code secret (+ (get-universal-time) 30)))
                (press other "Verify")
                (list asked (littoral.auth:second-factor-p bob)
                      (littoral.auth::factor-kind (first (littoral.auth:user-factors bob)))
                      (body-text other))))))))))
;; ⇒ ("Hello, stranger. Check it's you The code from your authenticator app Verify Cancel Use a recovery code instead" T "totp" "Hello, bob. Authenticator app On: signing in with your password also asks for its code. Turn off Passkeys None yet. A passkey signs you in with your fingerprint, face or device PIN, without a password. Add a passkey Recovery codes 10 codes left Make new codes")
```

#### `second-factor-p` `user` — function

True when signing in as `user` with a password needs a second step.

*Example:* A signed-in user sets up an authenticator app from the security settings: the page shows a QR code and the key, and the app's code turns it on.  From then on, signing in with a password asks for a code too.

```lisp
(defclass account (littoral.auth:auth-root component)
  ((security :initform (make-instance 'littoral.auth:security-settings) :reader account-security)))
(defmethod children ((self account)) (list (account-security self)))
(defmethod render ((self account))
  (let ((user (littoral.auth:current-user)))
    (p () (text (if user (format nil "Hello, ~A." (littoral.auth:user-name user)) "Hello, stranger."))))
  (render-component (account-security self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((bob (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")))
    (with-fresh-applications (("/account" 'account :mode :deployment))
      (flet ((sign-in (b)
               (visit b "/account")
               (click b "Sign in")
               (fill-in b "sign-in-name" "bob")
               (fill-in b "sign-in-password" "another passphrase")
               (press b "Sign in")))
        (let ((b (make-instance 'browser)))
          (sign-in b)
          (click b "Set up an authenticator app")
          (let ((secret (cl-ppcre:register-groups-bind (key) ("Key: <code>([A-Z2-7]+)</code>" (browser-html b)) key)))
            (fill-in b "totp-code" (littoral.auth:totp-code secret))
            (press b "Turn on")
            (let ((other (make-instance 'browser)))
              (sign-in other)
              (let ((asked (body-text other)))
                (fill-in other "sign-in-code" (littoral.auth:totp-code secret (+ (get-universal-time) 30)))
                (press other "Verify")
                (list asked (littoral.auth:second-factor-p bob)
                      (littoral.auth::factor-kind (first (littoral.auth:user-factors bob)))
                      (body-text other))))))))))
;; ⇒ ("Hello, stranger. Check it's you The code from your authenticator app Verify Cancel Use a recovery code instead" T "totp" "Hello, bob. Authenticator app On: signing in with your password also asks for its code. Turn off Passkeys None yet. A passkey signs you in with your fingerprint, face or device PIN, without a password. Add a passkey Recovery codes 10 codes left Make new codes")
```

#### `user-factors` `user &optional kind` — function

`user`'s second factors, oldest first, of `kind` ("totp", "passkey") if given.

*Example:* A signed-in user sets up an authenticator app from the security settings: the page shows a QR code and the key, and the app's code turns it on.  From then on, signing in with a password asks for a code too.

```lisp
(defclass account (littoral.auth:auth-root component)
  ((security :initform (make-instance 'littoral.auth:security-settings) :reader account-security)))
(defmethod children ((self account)) (list (account-security self)))
(defmethod render ((self account))
  (let ((user (littoral.auth:current-user)))
    (p () (text (if user (format nil "Hello, ~A." (littoral.auth:user-name user)) "Hello, stranger."))))
  (render-component (account-security self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((bob (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")))
    (with-fresh-applications (("/account" 'account :mode :deployment))
      (flet ((sign-in (b)
               (visit b "/account")
               (click b "Sign in")
               (fill-in b "sign-in-name" "bob")
               (fill-in b "sign-in-password" "another passphrase")
               (press b "Sign in")))
        (let ((b (make-instance 'browser)))
          (sign-in b)
          (click b "Set up an authenticator app")
          (let ((secret (cl-ppcre:register-groups-bind (key) ("Key: <code>([A-Z2-7]+)</code>" (browser-html b)) key)))
            (fill-in b "totp-code" (littoral.auth:totp-code secret))
            (press b "Turn on")
            (let ((other (make-instance 'browser)))
              (sign-in other)
              (let ((asked (body-text other)))
                (fill-in other "sign-in-code" (littoral.auth:totp-code secret (+ (get-universal-time) 30)))
                (press other "Verify")
                (list asked (littoral.auth:second-factor-p bob)
                      (littoral.auth::factor-kind (first (littoral.auth:user-factors bob)))
                      (body-text other))))))))))
;; ⇒ ("Hello, stranger. Check it's you The code from your authenticator app Verify Cancel Use a recovery code instead" T "totp" "Hello, bob. Authenticator app On: signing in with your password also asks for its code. Turn off Passkeys None yet. A passkey signs you in with your fingerprint, face or device PIN, without a password. Add a passkey Recovery codes 10 codes left Make new codes")
```

#### `*offer-passkeys*` — variable

Whether the sign-in form offers signing in with a passkey.

*Example:* What the sign-in form offers, besides a name and password.

```lisp
(defclass sign-in-page (component) ())
(defmethod render ((self sign-in-page))
  (render-component (make-instance 'littoral.auth:sign-in)))
(with-fresh-applications (("/sign-in" 'sign-in-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (list (progn (visit b "/sign-in") (body-text b))
          (let ((littoral.auth:*offer-remember-me* nil)
                (littoral.auth:*offer-passkeys* nil))
            (visit b "/sign-in")
            (body-text b)))))
;; ⇒ ("Sign in Name Password Keep me signed in Sign in Cancel Forgot your password? Sign in with a passkey" "Sign in Name Password Sign in Cancel Forgot your password?")
```

#### `hotp` `key counter &key (digits 6)` — function

The HOTP code (RFC 4226) of `key` (octets) for `counter`, as a string of `digits`.

*Example:* RFC 4226's own test values: a key and a counter give a code.

```lisp
(let ((key (sb-ext:string-to-octets "12345678901234567890")))
  (list (littoral.auth:hotp key 0)
        (littoral.auth:hotp key 1)
        (littoral.auth:hotp key 1 :digits 8)))
;; ⇒ ("755224" "287082" "94287082")
```

#### `totp-code` `secret &optional (universal-time (get-universal-time))` — function

The six-digit code `secret` (base 32) gives at `universal-time`, by default now.

*Example:* A code lasts 30 seconds.  `verify-totp` accepts one step either way, and returns the step it matched: pass it back as `:after` so the same code doesn't work twice.

```lisp
(let* ((secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
       (time (encode-universal-time 0 0 12 1 1 2026 0))
       (code (littoral.auth:totp-code secret time))
       (step (littoral.auth:verify-totp secret code :universal-time time)))
  (list code
        step
        (littoral.auth:verify-totp secret code :universal-time (+ time 30))
        (littoral.auth:verify-totp secret code :universal-time (+ time 300))
        (littoral.auth:verify-totp secret code :after step :universal-time time)))
;; ⇒ ("082995" 58908960 58908960 NIL NIL)
```

#### `verify-totp` `secret code &key (after -1) (universal-time (get-universal-time))` — function

The time step at which `code` is `secret`'s, within one step either way and
later than `after` (so a code works once), or `nil`.

*Example:* A code lasts 30 seconds.  `verify-totp` accepts one step either way, and returns the step it matched: pass it back as `:after` so the same code doesn't work twice.

```lisp
(let* ((secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
       (time (encode-universal-time 0 0 12 1 1 2026 0))
       (code (littoral.auth:totp-code secret time))
       (step (littoral.auth:verify-totp secret code :universal-time time)))
  (list code
        step
        (littoral.auth:verify-totp secret code :universal-time (+ time 30))
        (littoral.auth:verify-totp secret code :universal-time (+ time 300))
        (littoral.auth:verify-totp secret code :after step :universal-time time)))
;; ⇒ ("082995" 58908960 58908960 NIL NIL)
```

#### `new-totp-secret` — function

A new random authenticator-app secret: 160 bits, in base 32.

*Example:* A new secret, and the address an authenticator app reads from a QR code.

```lisp
(let ((secret (littoral.auth:new-totp-secret)))
  (list (length secret)
        (littoral.auth:totp-uri "JBSWY3DPEHPK3PXP" "ada@example.org" "The Shop")))
;; ⇒ (32 "otpauth://totp/The%20Shop:ada%40example.org?secret=JBSWY3DPEHPK3PXP&issuer=The%20Shop&algorithm=SHA1&digits=6&period=30")
```

#### `totp-uri` `secret account issuer` — function

The otpauth:// address an authenticator app reads, from a QR code or a link.

*Example:* A new secret, and the address an authenticator app reads from a QR code.

```lisp
(let ((secret (littoral.auth:new-totp-secret)))
  (list (length secret)
        (littoral.auth:totp-uri "JBSWY3DPEHPK3PXP" "ada@example.org" "The Shop")))
;; ⇒ (32 "otpauth://totp/The%20Shop:ada%40example.org?secret=JBSWY3DPEHPK3PXP&issuer=The%20Shop&algorithm=SHA1&digits=6&period=30")
```

#### `base32-encode` `octets` — function

`octets` in RFC 4648 base 32, without padding, as authenticator apps take secrets.

```lisp
(list (littoral.auth:base32-encode (sb-ext:string-to-octets "Hello!"))
      (sb-ext:octets-to-string (littoral.auth:base32-decode "jbsw y3dp ee")))
;; ⇒ ("JBSWY3DPEE" "Hello!")
```

#### `base32-decode` `string` — function

The octets `string` encodes in base 32, ignoring case, spaces, dashes and padding.

```lisp
(list (littoral.auth:base32-encode (sb-ext:string-to-octets "Hello!"))
      (sb-ext:octets-to-string (littoral.auth:base32-decode "jbsw y3dp ee")))
;; ⇒ ("JBSWY3DPEE" "Hello!")
```

#### `make-recovery-codes` `user &key (count 10)` — function

`count` (ten) new single-use recovery codes for `user`, replacing any others;
only their hashes are kept, so show them once.

*Example:* Ten single-use codes, for when the other ways in are lost.  Only their hashes are kept, so show them once.  Case and spaces around them don't matter.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let* ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery"))
         (codes (littoral.auth:make-recovery-codes ada)))
    (list (length codes)
          (every (lambda (code) (cl-ppcre:scan "^[a-z2-7]{5}-[a-z2-7]{5}$" code)) codes)
          (littoral.auth:use-recovery-code ada (string-upcase (first codes)))
          (littoral.auth:use-recovery-code ada (first codes))
          (littoral.auth:recovery-codes-left ada))))
;; ⇒ (10 T T NIL 9)
```

#### `use-recovery-code` `user code` — function

True, using it up, when `code` is one of `user`'s recovery codes.

*Example:* Ten single-use codes, for when the other ways in are lost.  Only their hashes are kept, so show them once.  Case and spaces around them don't matter.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let* ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery"))
         (codes (littoral.auth:make-recovery-codes ada)))
    (list (length codes)
          (every (lambda (code) (cl-ppcre:scan "^[a-z2-7]{5}-[a-z2-7]{5}$" code)) codes)
          (littoral.auth:use-recovery-code ada (string-upcase (first codes)))
          (littoral.auth:use-recovery-code ada (first codes))
          (littoral.auth:recovery-codes-left ada))))
;; ⇒ (10 T T NIL 9)
```

#### `recovery-codes-left` `user` — function

How many of `user`'s recovery codes are still unused.

*Example:* Ten single-use codes, for when the other ways in are lost.  Only their hashes are kept, so show them once.  Case and spaces around them don't matter.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let* ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery"))
         (codes (littoral.auth:make-recovery-codes ada)))
    (list (length codes)
          (every (lambda (code) (cl-ppcre:scan "^[a-z2-7]{5}-[a-z2-7]{5}$" code)) codes)
          (littoral.auth:use-recovery-code ada (string-upcase (first codes)))
          (littoral.auth:use-recovery-code ada (first codes))
          (littoral.auth:recovery-codes-left ada))))
;; ⇒ (10 T T NIL 9)
```

#### `add-passkey` `user challenge response-json &key (name "Passkey")` — function

Keep, as `name`, the passkey a navigator.credentials.create response
(`response-json`, a string) made for `user` against `challenge`.  Signals
`passkey-error` when the response fails a check.

*Example:* `add-passkey` checks the browser's navigator.credentials.create response with `verify-registration`, then keeps the passkey.  A response for another challenge than the one the page sent is refused.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*public-url* "https://example.org")
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let* ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery"))
         (client-data (cl-base64:string-to-base64-string
                       "{\"type\":\"webauthn.create\",\"challenge\":\"old\",\"origin\":\"https://example.org\"}"
                       :uri t))
         (response (format nil "{\"response\": {\"clientDataJSON\": ~S, \"attestationObject\": \"oA\"}}"
                           (string-right-trim "." client-data))))
    (handler-case (littoral.auth:add-passkey ada "new" response)
      (littoral.auth:passkey-error (e) (princ-to-string e)))))
;; ⇒ "Passkey refused: the challenge doesn't match"
```

#### `verify-registration` `challenge client-data-b64 attestation-b64` — function

Check a navigator.credentials.create response, its client data and
attestation object in base 64 URL, against `challenge`: (`values` `credential-id` X
Y `count`).  Signals `passkey-error` when a check fails.

*Example:* `add-passkey` checks the browser's navigator.credentials.create response with `verify-registration`, then keeps the passkey.  A response for another challenge than the one the page sent is refused.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*public-url* "https://example.org")
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let* ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery"))
         (client-data (cl-base64:string-to-base64-string
                       "{\"type\":\"webauthn.create\",\"challenge\":\"old\",\"origin\":\"https://example.org\"}"
                       :uri t))
         (response (format nil "{\"response\": {\"clientDataJSON\": ~S, \"attestationObject\": \"oA\"}}"
                           (string-right-trim "." client-data))))
    (handler-case (littoral.auth:add-passkey ada "new" response)
      (littoral.auth:passkey-error (e) (princ-to-string e)))))
;; ⇒ "Passkey refused: the challenge doesn't match"
```

#### `verify-assertion` `challenge response &optional user` — function

Check a navigator.credentials.get `response` (a parsed JSON hash table)
against `challenge`; the user it signs in, its passkey's signature count
advanced.  With `user`, only `user`'s passkeys count.  Signals `passkey-error` when
a check fails.

*Example:* Every check a passkey fails signals `passkey-error`, with the reason.  The security settings and the sign-in form handle it; here, a response from a passkey this site doesn't know.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.auth:create-auth-tables)
  (handler-case
      (littoral.auth:verify-assertion "the-challenge"
                                      (com.inuoe.jzon:parse "{\"id\": \"unknown\", \"response\": {}}"))
    (littoral.auth:passkey-error (e) (princ-to-string e))))
;; ⇒ "Passkey refused: that passkey isn't known here"
```

#### `passkey-error` — condition

A passkey registration or assertion that fails a check, with the reason.

*Example:* Every check a passkey fails signals `passkey-error`, with the reason.  The security settings and the sign-in form handle it; here, a response from a passkey this site doesn't know.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.auth:create-auth-tables)
  (handler-case
      (littoral.auth:verify-assertion "the-challenge"
                                      (com.inuoe.jzon:parse "{\"id\": \"unknown\", \"response\": {}}"))
    (littoral.auth:passkey-error (e) (princ-to-string e))))
;; ⇒ "Passkey refused: that passkey isn't known here"
```

#### `cbor-decode` `octets &optional (start 0)` — function

The CBOR item at `start` in `octets`, and where the next begins.  Maps become
alists, byte strings octet vectors.

*Example:* As much CBOR as WebAuthn uses: maps become alists, byte strings octet vectors.  The second value is where the next item starts.

```lisp
(multiple-value-list
 (littoral.auth:cbor-decode
  (coerce #(#xA2 #x63 #x66 #x6D #x74 #x64 #x6E #x6F #x6E #x65 #x01 #x42 #x01 #x02) '(vector (unsigned-byte 8)))))
;; ⇒ ((("fmt" . "none") (1 . #(1 2))) 14)
```

#### `qr-svg` `text &key (module 4) (label "QR code")` — function

`text` as a QR code, as a string of inline SVG: `module` pixels a square, and
`label` for screen readers.

*Example:* Text as a QR code, as inline SVG for `raw` to write into a page.

```lisp
(let ((svg (littoral.auth:qr-svg "otpauth://totp/Shop:ada?secret=JBSWY3DPEHPK3PXP" :label "Scan me")))
  (list (subseq svg 0 18)
        (not (null (search "aria-label=\"Scan me\"" svg)))))
;; ⇒ ("<svg class=\"lt-qr\"" T)
```

### Roles and permissions

#### `grant-role` `user role` — function

Give `user` the `role` (a keyword), whatever their store.

*Example:* Roles granted here add to whatever roles a user's store gives them.  Granting twice is granting once.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((bob (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")))
    (littoral.auth:grant-role bob :editor)
    (littoral.auth:grant-role bob :editor)
    (littoral.auth:grant-role bob :reviewer)
    (let ((granted (littoral.auth:user-roles bob)))
      (littoral.auth:revoke-role bob :reviewer)
      (list granted (littoral.auth:user-roles bob)))))
;; ⇒ ((:EDITOR :REVIEWER) (:EDITOR))
```

#### `revoke-role` `user role` — function

Take `role` from `user` (only a role granted here: a store's own roles stay).

*Example:* Roles granted here add to whatever roles a user's store gives them.  Granting twice is granting once.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((bob (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")))
    (littoral.auth:grant-role bob :editor)
    (littoral.auth:grant-role bob :editor)
    (littoral.auth:grant-role bob :reviewer)
    (let ((granted (littoral.auth:user-roles bob)))
      (littoral.auth:revoke-role bob :reviewer)
      (list granted (littoral.auth:user-roles bob)))))
;; ⇒ ((:EDITOR :REVIEWER) (:EDITOR))
```

#### `grant-permission` `role permission` — function

Let users with `role` do `permission` (both keywords).

*Example:* Permissions belong to roles; a user may do what any of their roles may.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (littoral.auth:grant-permission :editor :edit-posts)
    (littoral.auth:grant-permission :admin :delete-posts)
    (littoral.auth:grant-permission :admin :edit-posts)
    (let ((before (list (littoral.auth:role-permissions :admin)
                        (sort (littoral.auth:user-permissions ada) #'string<)
                        (littoral.auth:has-permission-p :delete-posts ada))))
      (littoral.auth:revoke-permission :admin :delete-posts)
      (append before (list (littoral.auth:has-permission-p :delete-posts ada))))))
;; ⇒ ((:DELETE-POSTS :EDIT-POSTS) (:DELETE-POSTS :EDIT-POSTS) T NIL)
```

#### `revoke-permission` `role permission` — function

Stop letting users with `role` do `permission`.

*Example:* Permissions belong to roles; a user may do what any of their roles may.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (littoral.auth:grant-permission :editor :edit-posts)
    (littoral.auth:grant-permission :admin :delete-posts)
    (littoral.auth:grant-permission :admin :edit-posts)
    (let ((before (list (littoral.auth:role-permissions :admin)
                        (sort (littoral.auth:user-permissions ada) #'string<)
                        (littoral.auth:has-permission-p :delete-posts ada))))
      (littoral.auth:revoke-permission :admin :delete-posts)
      (append before (list (littoral.auth:has-permission-p :delete-posts ada))))))
;; ⇒ ((:DELETE-POSTS :EDIT-POSTS) (:DELETE-POSTS :EDIT-POSTS) T NIL)
```

#### `role-permissions` `role` — function

What users with `role` may do, as keywords.

*Example:* Permissions belong to roles; a user may do what any of their roles may.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (littoral.auth:grant-permission :editor :edit-posts)
    (littoral.auth:grant-permission :admin :delete-posts)
    (littoral.auth:grant-permission :admin :edit-posts)
    (let ((before (list (littoral.auth:role-permissions :admin)
                        (sort (littoral.auth:user-permissions ada) #'string<)
                        (littoral.auth:has-permission-p :delete-posts ada))))
      (littoral.auth:revoke-permission :admin :delete-posts)
      (append before (list (littoral.auth:has-permission-p :delete-posts ada))))))
;; ⇒ ((:DELETE-POSTS :EDIT-POSTS) (:DELETE-POSTS :EDIT-POSTS) T NIL)
```

#### `user-permissions` `user` — function

What `user` may do through all their roles, as keywords.

*Example:* Permissions belong to roles; a user may do what any of their roles may.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (littoral.auth:grant-permission :editor :edit-posts)
    (littoral.auth:grant-permission :admin :delete-posts)
    (littoral.auth:grant-permission :admin :edit-posts)
    (let ((before (list (littoral.auth:role-permissions :admin)
                        (sort (littoral.auth:user-permissions ada) #'string<)
                        (littoral.auth:has-permission-p :delete-posts ada))))
      (littoral.auth:revoke-permission :admin :delete-posts)
      (append before (list (littoral.auth:has-permission-p :delete-posts ada))))))
;; ⇒ ((:DELETE-POSTS :EDIT-POSTS) (:DELETE-POSTS :EDIT-POSTS) T NIL)
```

#### `has-permission-p` `permission &optional (user (current-user))` — function

True when `user` may do `permission` (a keyword) through one of their roles.

*Example:* Permissions belong to roles; a user may do what any of their roles may.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (littoral.auth:grant-permission :editor :edit-posts)
    (littoral.auth:grant-permission :admin :delete-posts)
    (littoral.auth:grant-permission :admin :edit-posts)
    (let ((before (list (littoral.auth:role-permissions :admin)
                        (sort (littoral.auth:user-permissions ada) #'string<)
                        (littoral.auth:has-permission-p :delete-posts ada))))
      (littoral.auth:revoke-permission :admin :delete-posts)
      (append before (list (littoral.auth:has-permission-p :delete-posts ada))))))
;; ⇒ ((:DELETE-POSTS :EDIT-POSTS) (:DELETE-POSTS :EDIT-POSTS) T NIL)
```

#### `require-permission` `permission` — function

Refuse the request (403) unless the current user may do `permission`.

*Example:* In a callback: refuse the request with a 403 unless the signed-in user may do it.

```lisp
(defclass post-page (littoral.auth:auth-root component)
  ((deleted :initform nil :accessor post-deleted)))
(defmethod render ((self post-page))
  (p () (text (if (post-deleted self) "Deleted." "A post.")))
  (p ()
    (anchor (:callback (lambda ()
                         (littoral.auth:require-permission :delete-posts)
                         (setf (post-deleted self) t)))
      "Delete")
    " "
    (dolist (name '("ada" "bob"))
      (let ((name name))
        (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user name))))
          (text (format nil "Be ~A " name)))))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" nil :roles '(:admin))
  (littoral.auth:add-user "bob" "bob@example.org" nil)
  (littoral.auth:grant-permission :admin :delete-posts)
  (with-fresh-applications (("/post" 'post-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/post")
      (click b "Be bob")
      (click b "Delete")
      (let ((bob (browser-status b)))
        (visit b "/post")
        (click b "Be ada")
        (click b "Delete")
        (list bob (browser-status b) (body-text b))))))
;; ⇒ (403 200 "Deleted. Delete Be ada Be bob")
```

### Restricted components

#### `restricted` — class

Mixin for components only some users may see.  Specialise
`required-role`; the default lets anyone signed in see it.

*Example:* A `restricted` component shows a sign-in prompt in its place until someone signs in.  The root is an `auth-root`, so a sign-in comes back in a new session.

```lisp
(defclass members-news (littoral.auth:restricted component) ())
(defmethod render ((self members-news))
  (p () "Members' news"))
(defclass club (littoral.auth:auth-root component)
  ((news :initform (make-instance 'members-news) :reader club-news)))
(defmethod children ((self club)) (list (club-news self)))
(defmethod render ((self club))
  (let ((user (littoral.auth:current-user)))
    (p () (text (if user (format nil "Hello, ~A." (littoral.auth:user-name user)) "Hello, stranger."))))
  (render-component (club-news self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/club" 'club :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/club")
      (let ((before (body-text b)))
        (click b "Sign in")
        (fill-in b "sign-in-name" "bob")
        (fill-in b "sign-in-password" "another passphrase")
        (press b "Sign in")
        (list before (body-text b))))))
;; ⇒ ("Hello, stranger. Please sign in to see this. Sign in" "Hello, bob. Members' news")
```

#### `required-role` `component` — generic function

The role needed to see `component`, or `nil` for any signed-in user.

*Example:* A restricted component names the role, or permission, it needs.  Signed in without it, a user sees a refusal in its place.

```lisp
(defclass staff-room (littoral.auth:restricted component) ())
(defmethod littoral.auth:required-role ((self staff-room)) :staff)
(defmethod render ((self staff-room)) (p () "Staff only"))
(defclass editors-desk (littoral.auth:restricted component) ())
(defmethod littoral.auth:required-permission ((self editors-desk)) :edit-posts)
(defmethod render ((self editors-desk)) (p () "The editor's desk"))
(defclass office (littoral.auth:auth-root component)
  ((rooms :initform (list (make-instance 'staff-room) (make-instance 'editors-desk)) :reader office-rooms)))
(defmethod children ((self office)) (office-rooms self))
(defmethod render ((self office))
  (p () (text (format nil "~D of 2 rooms open." (count-if #'littoral.auth:permitted-p (office-rooms self)))))
  (mapc #'render-component (office-rooms self))
  (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "eve")))) "Be eve"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "eve" "eve@example.org" nil :roles '(:editor))
  (littoral.auth:grant-permission :editor :edit-posts)
  (with-fresh-applications (("/office" 'office :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/office")
      (click b "Be eve")
      (body-text b))))
;; ⇒ "1 of 2 rooms open. You don't have permission to see this. The editor's desk Be eve"
```

#### `required-permission` `component` — generic function

The permission needed to see `component`, or `nil` for none beyond its role.

*Example:* A restricted component names the role, or permission, it needs.  Signed in without it, a user sees a refusal in its place.

```lisp
(defclass staff-room (littoral.auth:restricted component) ())
(defmethod littoral.auth:required-role ((self staff-room)) :staff)
(defmethod render ((self staff-room)) (p () "Staff only"))
(defclass editors-desk (littoral.auth:restricted component) ())
(defmethod littoral.auth:required-permission ((self editors-desk)) :edit-posts)
(defmethod render ((self editors-desk)) (p () "The editor's desk"))
(defclass office (littoral.auth:auth-root component)
  ((rooms :initform (list (make-instance 'staff-room) (make-instance 'editors-desk)) :reader office-rooms)))
(defmethod children ((self office)) (office-rooms self))
(defmethod render ((self office))
  (p () (text (format nil "~D of 2 rooms open." (count-if #'littoral.auth:permitted-p (office-rooms self)))))
  (mapc #'render-component (office-rooms self))
  (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "eve")))) "Be eve"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "eve" "eve@example.org" nil :roles '(:editor))
  (littoral.auth:grant-permission :editor :edit-posts)
  (with-fresh-applications (("/office" 'office :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/office")
      (click b "Be eve")
      (body-text b))))
;; ⇒ "1 of 2 rooms open. You don't have permission to see this. The editor's desk Be eve"
```

#### `permitted-p` `component` — function

True when the current user may see `component`: has its role, and its permission.

*Example:* A restricted component names the role, or permission, it needs.  Signed in without it, a user sees a refusal in its place.

```lisp
(defclass staff-room (littoral.auth:restricted component) ())
(defmethod littoral.auth:required-role ((self staff-room)) :staff)
(defmethod render ((self staff-room)) (p () "Staff only"))
(defclass editors-desk (littoral.auth:restricted component) ())
(defmethod littoral.auth:required-permission ((self editors-desk)) :edit-posts)
(defmethod render ((self editors-desk)) (p () "The editor's desk"))
(defclass office (littoral.auth:auth-root component)
  ((rooms :initform (list (make-instance 'staff-room) (make-instance 'editors-desk)) :reader office-rooms)))
(defmethod children ((self office)) (office-rooms self))
(defmethod render ((self office))
  (p () (text (format nil "~D of 2 rooms open." (count-if #'littoral.auth:permitted-p (office-rooms self)))))
  (mapc #'render-component (office-rooms self))
  (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "eve")))) "Be eve"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "eve" "eve@example.org" nil :roles '(:editor))
  (littoral.auth:grant-permission :editor :edit-posts)
  (with-fresh-applications (("/office" 'office :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/office")
      (click b "Be eve")
      (body-text b))))
;; ⇒ "1 of 2 rooms open. You don't have permission to see this. The editor's desk Be eve"
```

### Sign-in pages

#### `sign-in` — class

Asks for a name and password; signs the user in and answers them.

*Example:* A `restricted` component shows a sign-in prompt in its place until someone signs in.  The root is an `auth-root`, so a sign-in comes back in a new session.

```lisp
(defclass members-news (littoral.auth:restricted component) ())
(defmethod render ((self members-news))
  (p () "Members' news"))
(defclass club (littoral.auth:auth-root component)
  ((news :initform (make-instance 'members-news) :reader club-news)))
(defmethod children ((self club)) (list (club-news self)))
(defmethod render ((self club))
  (let ((user (littoral.auth:current-user)))
    (p () (text (if user (format nil "Hello, ~A." (littoral.auth:user-name user)) "Hello, stranger."))))
  (render-component (club-news self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/club" 'club :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/club")
      (let ((before (body-text b)))
        (click b "Sign in")
        (fill-in b "sign-in-name" "bob")
        (fill-in b "sign-in-password" "another passphrase")
        (press b "Sign in")
        (list before (body-text b))))))
;; ⇒ ("Hello, stranger. Please sign in to see this. Sign in" "Hello, bob. Members' news")
```

*Example:* The sign-in form answers the user it signed in, or `nil` when cancelled; show it with `show` to act on the answer.

```lisp
(defclass front-door (component)
  ((greeting :initform "Welcome." :accessor greeting)))
(defmethod render ((self front-door))
  (p () (text (greeting self)))
  (anchor (:callback (lambda ()
                       (show self (make-instance 'littoral.auth:sign-in)
                             :on-answer (lambda (user)
                                          (when user
                                            (setf (greeting self)
                                                  (format nil "Welcome back, ~A." (littoral.auth:user-name user))))))))
    "Sign in"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (with-fresh-applications (("/door" 'front-door :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/door")
      (click b "Sign in")
      (fill-in b "sign-in-name" "ada")
      (fill-in b "sign-in-password" "wrong")
      (press b "Sign in")
      (let ((refused (has-text-p b "Unknown user or wrong password.")))
        (fill-in b "sign-in-name" "ada")
        (fill-in b "sign-in-password" "correct horse battery")
        (press b "Sign in")
        (list (not (null refused)) (body-text b))))))
;; ⇒ (T "Welcome back, ada. Sign in")
```

*Example:* What the sign-in form offers, besides a name and password.

```lisp
(defclass sign-in-page (component) ())
(defmethod render ((self sign-in-page))
  (render-component (make-instance 'littoral.auth:sign-in)))
(with-fresh-applications (("/sign-in" 'sign-in-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (list (progn (visit b "/sign-in") (body-text b))
          (let ((littoral.auth:*offer-remember-me* nil)
                (littoral.auth:*offer-passkeys* nil))
            (visit b "/sign-in")
            (body-text b)))))
;; ⇒ ("Sign in Name Password Keep me signed in Sign in Cancel Forgot your password? Sign in with a passkey" "Sign in Name Password Sign in Cancel Forgot your password?")
```

#### `sign-out-link` `&key (label "Sign out") then` — function

Write a link that signs the user out, then calls `then`, a thunk.

*Example:* A link that signs out, then does more: here, says goodbye.

```lisp
(defclass farewell (littoral.auth:auth-root component)
  ((message :initform nil :accessor farewell-message)))
(defmethod render ((self farewell))
  (when (farewell-message self) (p () (text (farewell-message self))))
  (if (littoral.auth:signed-in-p)
      (littoral.auth:sign-out-link :then (lambda () (setf (farewell-message self) "Goodbye.")))
      (anchor (:callback (lambda () (littoral.auth:log-in (littoral.auth:find-user "ada")))) "Come in")))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (with-fresh-applications (("/bye" 'farewell :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/bye")
      (click b "Come in")
      (click b "Sign out")
      (body-text b))))
;; ⇒ "Goodbye. Come in"
```

#### `password-reset-request` — class

Asks for an email address and sends a reset link to it.

*Example:* "Forgot your password?" on the sign-in form mails a link built from `*public-url*`.  Following it, at the `auth-root` application, shows the form for a new password, which then signs the user in.

```lisp
(defclass reading-room (littoral.auth:auth-root component) ())
(defmethod render ((self reading-room))
  (let ((user (littoral.auth:current-user)))
    (if user
        (p () (text (format nil "Hello, ~A." (littoral.auth:user-name user))))
        (anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in)))) "Sign in"))))
(let* ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
       (littoral.auth:*pbkdf2-iterations* 1000)
       (littoral.auth:*public-url* "https://library.example")
       (mails '())
       (littoral.auth:*send-mail* (lambda (to subject body) (push (list to subject body) mails))))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/library" 'reading-room :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/library")
      (click b "Sign in")
      (click b "Forgot your password?")
      (fill-in b "reset-email" "bob@example.org")
      (press b "Send me a link")
      (destructuring-bind (to subject body) (first mails)
        (let ((link (cl-ppcre:scan-to-strings "https://library.example/library/reset\\?token=\\S+" body))
              (other (make-instance 'browser)))
          (visit other link)
          (fill-in other "new-password" "a brand new passphrase")
          (fill-in other "new-password-again" "a brand new passphrase")
          (press other "Save and sign in")
          (list to subject (body-text other)
                (littoral.auth:check-password (littoral.auth:find-user "bob") "a brand new passphrase")))))))
;; ⇒ ("bob@example.org" "Choose a new password" "Hello, bob." T)
```

*Example:* An address without an account gets the same answer, and no mail.  `*last-mail*` holds the last mail sent, for development.

```lisp
(defclass reset-page (component)
  ((form :initform (make-instance 'littoral.auth:password-reset-request) :reader reset-form)))
(defmethod children ((self reset-page)) (list (reset-form self)))
(defmethod render ((self reset-page))
  (render-component (reset-form self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*send-mail* (lambda (to subject body) (declare (ignore to subject body))))
      (littoral.auth:*last-mail* nil))
  (littoral.auth:create-auth-tables)
  (with-fresh-applications (("/reset-page" 'reset-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/reset-page")
      (fill-in b "reset-email" "nobody@example.org")
      (press b "Send me a link")
      (list (body-text b) littoral.auth:*last-mail*))))
;; ⇒ ("Reset your password If that address belongs to an account, a link to choose a new password is on its way. Back" NIL)
```

#### `password-reset` — class

Lets the holder of a reset link choose a new password; answers the user.

*Example:* "Forgot your password?" on the sign-in form mails a link built from `*public-url*`.  Following it, at the `auth-root` application, shows the form for a new password, which then signs the user in.

```lisp
(defclass reading-room (littoral.auth:auth-root component) ())
(defmethod render ((self reading-room))
  (let ((user (littoral.auth:current-user)))
    (if user
        (p () (text (format nil "Hello, ~A." (littoral.auth:user-name user))))
        (anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in)))) "Sign in"))))
(let* ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
       (littoral.auth:*pbkdf2-iterations* 1000)
       (littoral.auth:*public-url* "https://library.example")
       (mails '())
       (littoral.auth:*send-mail* (lambda (to subject body) (push (list to subject body) mails))))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/library" 'reading-room :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/library")
      (click b "Sign in")
      (click b "Forgot your password?")
      (fill-in b "reset-email" "bob@example.org")
      (press b "Send me a link")
      (destructuring-bind (to subject body) (first mails)
        (let ((link (cl-ppcre:scan-to-strings "https://library.example/library/reset\\?token=\\S+" body))
              (other (make-instance 'browser)))
          (visit other link)
          (fill-in other "new-password" "a brand new passphrase")
          (fill-in other "new-password-again" "a brand new passphrase")
          (press other "Save and sign in")
          (list to subject (body-text other)
                (littoral.auth:check-password (littoral.auth:find-user "bob") "a brand new passphrase")))))))
;; ⇒ ("bob@example.org" "Choose a new password" "Hello, bob." T)
```

#### `auth-root` — class

Mixin for an application's root component: it answers
password reset links and, with littoral/oauth, sign-in callbacks.

*Example:* A `restricted` component shows a sign-in prompt in its place until someone signs in.  The root is an `auth-root`, so a sign-in comes back in a new session.

```lisp
(defclass members-news (littoral.auth:restricted component) ())
(defmethod render ((self members-news))
  (p () "Members' news"))
(defclass club (littoral.auth:auth-root component)
  ((news :initform (make-instance 'members-news) :reader club-news)))
(defmethod children ((self club)) (list (club-news self)))
(defmethod render ((self club))
  (let ((user (littoral.auth:current-user)))
    (p () (text (if user (format nil "Hello, ~A." (littoral.auth:user-name user)) "Hello, stranger."))))
  (render-component (club-news self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/club" 'club :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/club")
      (let ((before (body-text b)))
        (click b "Sign in")
        (fill-in b "sign-in-name" "bob")
        (fill-in b "sign-in-password" "another passphrase")
        (press b "Sign in")
        (list before (body-text b))))))
;; ⇒ ("Hello, stranger. Please sign in to see this. Sign in" "Hello, bob. Members' news")
```

#### `define-auth-path` `segment (root rest request) &body body` — macro

Run `body`, instead of the root's `initial-request`, when a session of an
`auth-root` application starts at /`segment`/…: with `root` the root component,
`rest` the remaining segments and `request` the request.  Defining `segment` again
replaces it.

*Example:* Answer a path of an `auth-root` application when a session starts there, as /reset does: here, /welcome/`name`.

```lisp
(littoral.auth:define-auth-path "welcome" (root rest request)
  (show root (make-instance 'message-dialog :message (format nil "Welcome, ~A!" (first rest)))))
(defclass guest-house (littoral.auth:auth-root component) ())
(defmethod render ((self guest-house)) (p () "The front page"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.auth:create-auth-tables)
  (with-fresh-applications (("/house" 'guest-house :mode :deployment))
    (let ((b (make-instance 'browser)))
      (list (progn (visit b "/house/welcome/ada") (body-text b))
            (progn (visit b "/house") (body-text b))))))
;; ⇒ ("Welcome, ada! OK" "The front page")
```

#### `request-base-url` `&optional (request *request*)` — function

This site's address, such as https://example.org: `*public-url*` without a
trailing slash, or in development mode `request`'s own host.  Signals an error
in deployment mode when `*public-url*` is unset.

*Example:* The site's address for links in mail and OAuth redirects: `*public-url*`, without a trailing slash.

```lisp
(let ((littoral.auth:*public-url* "https://example.org/"))
  (littoral.auth:request-base-url))
;; ⇒ "https://example.org"
```

#### `*sign-in-extras*` — variable

Functions of the `sign-in` component writing more ways to sign in (OAuth
buttons, from littoral/oauth).

*Example:* Add to the sign-in form: each function is called with the form, while it renders.

```lisp
(defclass desk-sign-in (component) ())
(defmethod render ((self desk-sign-in))
  (render-component (make-instance 'littoral.auth:sign-in)))
(let ((littoral.auth:*offer-passkeys* nil)
      (littoral.auth:*sign-in-extras*
        (cons (lambda (sign-in)
                (declare (ignore sign-in))
                (p () "No account? Ask at the front desk."))
              littoral.auth:*sign-in-extras*)))
  (with-fresh-applications (("/desk" 'desk-sign-in :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/desk")
      (body-text b))))
;; ⇒ "Sign in Name Password Keep me signed in Sign in Cancel Forgot your password? No account? Ask at the front desk."
```

### Applications for signed-in users

#### `signed-in-root` — class

Mixin for the root of an application only signed-in users
may use, with the role `restrict-application` gave it.  A new visitor is shown
the sign-in form.

*Example:* A whole application for signed-in users with a role: its root is a `signed-in-root`, and `restrict-application` names the role.  A new visitor gets the sign-in form; someone without the role, a refusal.

```lisp
(defclass back-office (littoral.auth:signed-in-root component) ())
(defmethod render ((self back-office))
  (p () (text (format nil "The back office, for ~(~A~) users." (littoral.auth:application-role)))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:staff))
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (littoral.auth:restrict-application "/office" :staff)
  (with-fresh-applications (("/office" 'back-office :mode :deployment))
    (flet ((visit-as (name password)
             (let ((b (make-instance 'browser)))
               (visit b "/office")
               (fill-in b "sign-in-name" name)
               (fill-in b "sign-in-password" password)
               (press b "Sign in")
               (body-text b))))
      (list (visit-as "bob" "another passphrase")
            (visit-as "ada" "correct horse battery")))))
;; ⇒ ("You don't have permission to see this." "The back office, for staff users.")
```

#### `restrict-application` `path role` — function

Let only signed-in users with `role` (anyone signed in, when `role` is T)
use the application at `path`, whose root is a `signed-in-root`; with `role` `nil`,
forget the restriction.

*Example:* A whole application for signed-in users with a role: its root is a `signed-in-root`, and `restrict-application` names the role.  A new visitor gets the sign-in form; someone without the role, a refusal.

```lisp
(defclass back-office (littoral.auth:signed-in-root component) ())
(defmethod render ((self back-office))
  (p () (text (format nil "The back office, for ~(~A~) users." (littoral.auth:application-role)))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:staff))
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (littoral.auth:restrict-application "/office" :staff)
  (with-fresh-applications (("/office" 'back-office :mode :deployment))
    (flet ((visit-as (name password)
             (let ((b (make-instance 'browser)))
               (visit b "/office")
               (fill-in b "sign-in-name" name)
               (fill-in b "sign-in-password" password)
               (press b "Sign in")
               (body-text b))))
      (list (visit-as "bob" "another passphrase")
            (visit-as "ada" "correct horse battery")))))
;; ⇒ ("You don't have permission to see this." "The back office, for staff users.")
```

#### `application-role` `&optional (application *application*)` — function

The role `application`'s users need, `nil` for anyone signed in; and, second,
whether `restrict-application` restricted it.

*Example:* A whole application for signed-in users with a role: its root is a `signed-in-root`, and `restrict-application` names the role.  A new visitor gets the sign-in form; someone without the role, a refusal.

```lisp
(defclass back-office (littoral.auth:signed-in-root component) ())
(defmethod render ((self back-office))
  (p () (text (format nil "The back office, for ~(~A~) users." (littoral.auth:application-role)))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:staff))
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (littoral.auth:restrict-application "/office" :staff)
  (with-fresh-applications (("/office" 'back-office :mode :deployment))
    (flet ((visit-as (name password)
             (let ((b (make-instance 'browser)))
               (visit b "/office")
               (fill-in b "sign-in-name" name)
               (fill-in b "sign-in-password" password)
               (press b "Sign in")
               (body-text b))))
      (list (visit-as "bob" "another passphrase")
            (visit-as "ada" "correct horse battery")))))
;; ⇒ ("You don't have permission to see this." "The back office, for staff users.")
```

#### `check-application-role` — function

Refuse the request (403) unless the current user may use this
application, when `restrict-application` restricted it.  Call it in actions
that change things: a page from before a sign-out, or before a role was
revoked, keeps its links.

*Example:* Callbacks that change things check again: a page kept from before the user's role was revoked still has its links.

```lisp
(defclass ledger (littoral.auth:signed-in-root component)
  ((entries :initform 0 :accessor ledger-entries)))
(defmethod render ((self ledger))
  (p () (text (format nil "~D entr~:@P" (ledger-entries self))))
  (anchor (:callback (lambda ()
                       (littoral.auth:check-application-role)
                       (incf (ledger-entries self))))
    "Add an entry"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:accounts))))
    (littoral.auth:restrict-application "/ledger" :accounts)
    (with-fresh-applications (("/ledger" 'ledger :mode :deployment))
      (let ((b (make-instance 'browser)))
        (visit b "/ledger")
        (fill-in b "sign-in-name" "ada")
        (fill-in b "sign-in-password" "correct horse battery")
        (press b "Sign in")
        (click b "Add an entry")
        (let ((before (body-text b)))
          (littoral.auth:revoke-role ada :accounts)
          (click b "Add an entry")
          (list before (browser-status b)))))))
;; ⇒ ("1 entry Add an entry" 403)
```

#### `configure-signed-in-admin` `&key (path "/config") (role :admin) database` — function

Serve the configuration application at `path` to signed-in users with `role`,
from wherever they are, instead of only to this machine as `configure-admin`
does.  `database` (as `connect-database` takes it) holds the users, unless the
current one does.

*Example:* The configuration application, for signed-in users with the admin role, from anywhere.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin))
  (with-fresh-applications ()
    (littoral.auth:configure-signed-in-admin :path "/config" :role :admin)
    (let ((b (make-instance 'browser)))
      (visit b "/config")
      (let ((asked (not (null (has-text-p b "Sign in")))))
        (fill-in b "sign-in-name" "ada")
        (fill-in b "sign-in-password" "correct horse battery")
        (press b "Sign in")
        (list asked (not (null (has-text-p b "Applications"))))))))
;; ⇒ (T T)
```

## Package `littoral.admin`

An administration interface generated from descriptions.  Load it with
`(asdf:load-system :littoral/admin)`.

### General

#### `register-admin` `path classes &key (title "Admin") database role credentials (mode :deployment) (audit t)` — function

Serve an admin for `classes` (stored classes, see `define-table`) at `path`.
`database` (a driver and parameters, as `connect-database` takes them) gives
it its own database; otherwise it uses the current one.  With `role`, users
with that role (any signed-in user, for T) sign in to it, from anywhere: the
database must hold littoral/auth's tables.  With `credentials` instead, it asks
for HTTP basic auth.  With neither, it answers only requests from this machine.  With `audit` (the
default), it records what it creates, changes and deletes in the audit log
(creating its table) and shows the log.

*Example:* An admin over stored classes: a menu of tables, a searchable list of each, and a page per record to edit or delete it.  Without `:role` or `:credentials` it answers only requests from this machine, as the fake browser's are.

```lisp
(defclass book (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (pages :initarg :pages :initform nil)))
(define-description book
  ((title :required t)
   (pages :type :integer :min 1)))
(littoral.db:define-table book)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'book)
  (littoral.db:db-save (make-instance 'book :title "Moby-Dick" :pages 635))
  (littoral.db:db-save (make-instance 'book :title "Walden" :pages 352))
  (with-fresh-applications ()
    (littoral.admin:register-admin "/admin" '(book) :title "Library admin")
    (let ((b (make-instance 'browser)))
      (visit b "/admin")
      (let ((list (body-text b)))
        (click-nth b "2" 0)               ; record #2
        (click b "Edit")
        (fill-in b "pages" "354")
        (press b "Save")
        (list list (slot-value (littoral.db:db-find 'book 2) 'pages))))))
;; ⇒ ("Library admin Books Audit log Books New book 2 books # Title Pages 1 Moby-Dick 635 2 Walden 352" 354)
```

*Example:* With `:role`, users of littoral/auth with that role sign in to it, from anywhere; the database holds their tables too.  The audit log names who changed what.

```lisp
(defclass genre (littoral.db:persistent)
  ((name :initarg :name :initform nil)))
(define-description genre ((name :required t)))
(littoral.db:define-table genre)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:librarian))
  (littoral.db:create-table 'genre)
  (with-fresh-applications ()
    (littoral.admin:register-admin "/genres" '(genre) :role :librarian)
    (let ((b (make-instance 'browser)))
      (visit b "/genres")
      (fill-in b "sign-in-name" "ada")
      (fill-in b "sign-in-password" "correct horse battery")
      (press b "Sign in")
      (click b "New genre")
      (fill-in b "name" "Poetry")
      (press b "Create")
      (let ((event (first (littoral.audit:audit-events :action "record.created"))))
        (list (not (null (has-text-p b "Created Genre #1.")))
              (littoral.audit:audit-event-subject-label event)
              (littoral.audit:audit-event-actor-name event))))))
;; ⇒ (T "Genre #1 Poetry" "ada")
```

*Example:* With `:credentials`, a (`user` . `password`) pair, it asks for HTTP basic auth instead.

```lisp
(defclass note (littoral.db:persistent)
  ((text :initarg :text :initform nil)))
(define-description note ((text :required t)))
(littoral.db:define-table note)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'note)
  (with-fresh-applications ()
    (littoral.admin:register-admin "/notes-admin" '(note) :credentials '("admin" . "s3cret"))
    (list (browser-status (visit (make-instance 'browser) "/notes-admin"))
          (let ((b (make-instance 'browser
                                  :headers `(("authorization" . ,(format nil "Basic ~A"
                                                                         (cl-base64:string-to-base64-string "admin:s3cret")))))))
            (visit b "/notes-admin")
            (browser-status b)))))
;; ⇒ (401 200)
```

#### `admin` — class

The root of an admin application: header, messages and
menu stay; pages replace the main area.

*Example:* An admin over stored classes: a menu of tables, a searchable list of each, and a page per record to edit or delete it.  Without `:role` or `:credentials` it answers only requests from this machine, as the fake browser's are.

```lisp
(defclass book (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (pages :initarg :pages :initform nil)))
(define-description book
  ((title :required t)
   (pages :type :integer :min 1)))
(littoral.db:define-table book)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'book)
  (littoral.db:db-save (make-instance 'book :title "Moby-Dick" :pages 635))
  (littoral.db:db-save (make-instance 'book :title "Walden" :pages 352))
  (with-fresh-applications ()
    (littoral.admin:register-admin "/admin" '(book) :title "Library admin")
    (let ((b (make-instance 'browser)))
      (visit b "/admin")
      (let ((list (body-text b)))
        (click-nth b "2" 0)               ; record #2
        (click b "Edit")
        (fill-in b "pages" "354")
        (press b "Save")
        (list list (slot-value (littoral.db:db-find 'book 2) 'pages))))))
;; ⇒ ("Library admin Books Audit log Books New book 2 books # Title Pages 1 Moby-Dick 635 2 Walden 352" 354)
```

#### `job-queue-view` — class

The durable jobs of the current database, newest first, by
status, with Retry for failed and cancelled jobs and Cancel for waiting ones.
Shows everything: put it where only those who may see it can.

*Example:* The durable jobs of the current database, by status, with Retry and Cancel.  The admin shows it as "Job queue" where the job tables are; put it in an application of your own only where those who may see every job can.

```lisp
(littoral.jobs:define-job send-digest (list-id)
  (format nil "Sent digest ~D" list-id))
(defclass operations (component)
  ((jobs :initform (make-instance 'littoral.admin:job-queue-view) :reader operations-jobs)))
(defmethod children ((self operations)) (list (operations-jobs self)))
(defmethod render ((self operations)) (render-component (operations-jobs self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (let ((id (littoral.jobs:enqueue-job '(send-digest 42))))
    (with-fresh-applications (("/ops" 'operations :mode :deployment))
      (let ((b (make-instance 'browser)))
        (visit b "/ops")
        (let ((shown (not (null (has-text-p b "(send-digest 42)")))))
          (click-nth b "Cancel" 0)
          (list shown
                (littoral.jobs:durable-job-status (littoral.jobs:find-durable-job id))
                (not (null (has-text-p b "Cancelled (1)")))))))))
;; ⇒ (T "cancelled" T)
```

## Package `littoral.db`

Load with `(asdf:load-system :littoral/db)` and a cl-dbi driver, such as
`:dbd-sqlite3` or `:dbd-postgres`.  Keeps described objects in a SQL database
(SQLite or PostgreSQL): tables, queries, full-text search, transactions,
optimistic locking and migrations.

### General

#### `connect-database` `driver &rest parameters` — function

Use the database `driver` (:sqlite3, :postgres) reaches with `parameters`,
as cl-dbi's `connect` takes them (`:database-name`, and `:host`, `:port`, `:username` and
`:password` for PostgreSQL).  For SQLite, `parameters` may also give
`:busy-timeout`, `:journal-mode` and `:synchronous` (see `*sqlite-busy-timeout*`,
`*sqlite-journal-mode*` and `*sqlite-synchronous*`).
Sets `*database*`, for every thread that doesn't bind it, and returns this
thread's connection.  Each thread gets its own connection, made when first
needed.

*Example:* A program connects once at start-up; here the `let` keeps the setting to the example.  Each thread then makes its own connection when it first needs one.

```lisp
(let ((littoral.db:*database* nil))
  (littoral.db:connect-database :sqlite3 :database-name ":memory:")
  (list littoral.db:*database*
        (littoral.db:db-query "SELECT 1 + 1 AS two")
        (progn (littoral.db:disconnect-database) littoral.db:*database*)))
;; ⇒ ((:SQLITE3 :DATABASE-NAME ":memory:") ((:|two| 2)) NIL)
```

#### `disconnect-database` — function

Forget the database: `*database*` becomes `nil`.  Connections already made
stay open until their threads end (`dbi` closes them when it next connects).

*Example:* A program connects once at start-up; here the `let` keeps the setting to the example.  Each thread then makes its own connection when it first needs one.

```lisp
(let ((littoral.db:*database* nil))
  (littoral.db:connect-database :sqlite3 :database-name ":memory:")
  (list littoral.db:*database*
        (littoral.db:db-query "SELECT 1 + 1 AS two")
        (progn (littoral.db:disconnect-database) littoral.db:*database*)))
;; ⇒ ((:SQLITE3 :DATABASE-NAME ":memory:") ((:|two| 2)) NIL)
```

#### `database-connection` — function

This thread's connection to `*database*`, made the first time it is
needed.  Signals an error when `*database*` is `nil`.

*Example:* This thread's connection, made the first time and kept.  With no database there is none to make.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (eq (littoral.db:database-connection) (littoral.db:database-connection)))
;; ⇒ T
(let ((littoral.db:*database* nil))
  (handler-case (littoral.db:database-connection)
    (error (e) (princ-to-string e))))
;; ⇒ "No database: call CONNECT-DATABASE first."
```

#### `*database*` — variable

The arguments of the last `connect-database`: a driver keyword and its
connection parameters, as cl-dbi's `connect` takes them; `nil` for none.  Binding it
uses another database for a while (see also `using-database`).

*Example:* A program connects once at start-up; here the `let` keeps the setting to the example.  Each thread then makes its own connection when it first needs one.

```lisp
(let ((littoral.db:*database* nil))
  (littoral.db:connect-database :sqlite3 :database-name ":memory:")
  (list littoral.db:*database*
        (littoral.db:db-query "SELECT 1 + 1 AS two")
        (progn (littoral.db:disconnect-database) littoral.db:*database*)))
;; ⇒ ((:SQLITE3 :DATABASE-NAME ":memory:") ((:|two| 2)) NIL)
```

#### `*sqlite-busy-timeout*` — variable

Milliseconds a SQLite connection waits for another's lock before giving up,
unless the database spec gives `:busy-timeout`.  Threads (requests, mail
delivery) each have a connection, and SQLite allows one writer at a time.

*Example:* A SQLite file is switched to write-ahead logging when Littoral first connects to it, so readers and the writer don't wait for each other.  A database spec's `:journal-mode`, `:synchronous` and `:busy-timeout` override these variables for that database.

```lisp
(let* ((file (namestring (merge-pathnames "littoral-example-journal.db" (uiop:temporary-directory))))
       (littoral.db:*database* (list :sqlite3 :database-name file)))
  (unwind-protect
       (list littoral.db:*sqlite-journal-mode* littoral.db:*sqlite-synchronous* littoral.db:*sqlite-busy-timeout*
             (littoral.db:db-query "PRAGMA journal_mode")
             (littoral.db:db-query "PRAGMA synchronous"))
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string file suffix)))))
;; ⇒ (:WAL :NORMAL 5000 ((:|journal_mode| "wal")) ((:|synchronous| 1)))
```

#### `*sqlite-journal-mode*` — variable

The journal mode Littoral sets on a SQLite database file when it first
connects, unless the database spec gives `:journal-mode`: `:wal` (write-ahead
logging, so readers and the writer don't wait for each other), another of
SQLite's modes such as `:delete`, or `nil` to leave the file as it is.  The
mode is kept in the file.

*Example:* A SQLite file is switched to write-ahead logging when Littoral first connects to it, so readers and the writer don't wait for each other.  A database spec's `:journal-mode`, `:synchronous` and `:busy-timeout` override these variables for that database.

```lisp
(let* ((file (namestring (merge-pathnames "littoral-example-journal.db" (uiop:temporary-directory))))
       (littoral.db:*database* (list :sqlite3 :database-name file)))
  (unwind-protect
       (list littoral.db:*sqlite-journal-mode* littoral.db:*sqlite-synchronous* littoral.db:*sqlite-busy-timeout*
             (littoral.db:db-query "PRAGMA journal_mode")
             (littoral.db:db-query "PRAGMA synchronous"))
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string file suffix)))))
;; ⇒ (:WAL :NORMAL 5000 ((:|journal_mode| "wal")) ((:|synchronous| 1)))
```

#### `*sqlite-synchronous*` — variable

How hard SQLite connections make sure commits reach the disk, unless the
database spec gives `:synchronous`: `:normal` (with WAL, a power cut may lose
the last commits but never corrupts the file), `:full`, or `nil` for SQLite's
default.

*Example:* A SQLite file is switched to write-ahead logging when Littoral first connects to it, so readers and the writer don't wait for each other.  A database spec's `:journal-mode`, `:synchronous` and `:busy-timeout` override these variables for that database.

```lisp
(let* ((file (namestring (merge-pathnames "littoral-example-journal.db" (uiop:temporary-directory))))
       (littoral.db:*database* (list :sqlite3 :database-name file)))
  (unwind-protect
       (list littoral.db:*sqlite-journal-mode* littoral.db:*sqlite-synchronous* littoral.db:*sqlite-busy-timeout*
             (littoral.db:db-query "PRAGMA journal_mode")
             (littoral.db:db-query "PRAGMA synchronous"))
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string file suffix)))))
;; ⇒ (:WAL :NORMAL 5000 ((:|journal_mode| "wal")) ((:|synchronous| 1)))
```

#### `database-label` `&optional (spec *database*)` — function

`spec` named for logs and metrics, without credentials: a SQLite file's
name, or a PostgreSQL server's host, port and database.

*Example:* How logs and /metrics name a database: never with its password.

```lisp
(littoral.db:database-label '(:postgres :database-name "shop" :host "db.internal" :port 5433
                              :username "shop" :password "secret"))
;; ⇒ "postgres://db.internal:5433/shop"
(littoral.db:database-label '(:sqlite3 :database-name "/var/lib/shop/shop.db"))
;; ⇒ "/var/lib/shop/shop.db"
```

#### `persistent` — class

Mixin for objects kept in a table.

*Example:* A class with the `persistent` mixin and a description is kept in a table with a column for each field.  Saving a new object inserts it and gives it an id; `db-find` reads it back.

```lisp
(defclass book (littoral.db:persistent)
  ((title :initarg :title :initform nil :accessor book-title)
   (pages :initarg :pages :initform nil :accessor book-pages)))
(define-description book
  ((title :required t)
   (pages :type :integer :min 1)))
(littoral.db:define-table book)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'book)
  (let ((saved (littoral.db:db-save (make-instance 'book :title "Dune" :pages 412))))
    (let ((found (littoral.db:db-find 'book (littoral.db:object-id saved))))
      (list (book-title found) (book-pages found) (littoral.db:db-find 'book 99)))))
;; ⇒ ("Dune" 412 NIL)
```

#### `object-id` `object` — generic function

Reads the id of a persistent.  The row's key, or `nil` until the object is first saved.

*Example:* An object has no id until it is first saved.  Each update adds one to its version, which is how a conflicting save is noticed (see `stale-object`).  `db-save` calls `db-insert` or `db-update` as the object needs.

```lisp
(defclass note (littoral.db:persistent)
  ((text :initarg :text :initform nil :accessor note-text)))
(define-description note ((text :required t)))
(littoral.db:define-table note)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'note)
  (let ((note (make-instance 'note :text "Buy milk")))
    (list (littoral.db:object-id note)
          (progn (littoral.db:db-insert note)
                 (list (littoral.db:object-id note) (littoral.db:object-version note)))
          (progn (setf (note-text note) "Buy oat milk")
                 (littoral.db:db-update note)
                 (list (littoral.db:object-id note) (littoral.db:object-version note))))))
;; ⇒ (NIL (1 0) (1 1))
```

#### `object-version` `object` — generic function

Reads the version of a persistent.  Incremented by every update; how conflicting saves are noticed.

*Example:* An object has no id until it is first saved.  Each update adds one to its version, which is how a conflicting save is noticed (see `stale-object`).  `db-save` calls `db-insert` or `db-update` as the object needs.

```lisp
(defclass note (littoral.db:persistent)
  ((text :initarg :text :initform nil :accessor note-text)))
(define-description note ((text :required t)))
(littoral.db:define-table note)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'note)
  (let ((note (make-instance 'note :text "Buy milk")))
    (list (littoral.db:object-id note)
          (progn (littoral.db:db-insert note)
                 (list (littoral.db:object-id note) (littoral.db:object-version note)))
          (progn (setf (note-text note) "Buy oat milk")
                 (littoral.db:db-update note)
                 (list (littoral.db:object-id note) (littoral.db:object-version note))))))
;; ⇒ (NIL (1 0) (1 1))
```

#### `define-table` `class &key name description search` — macro

Keep objects of `class` (a `persistent` class) in the table `name` (a string;
by default the class name, lower case, with underscores for dashes), with a
column for each field of the description `description` names (by default
`class`), which must be defined first.  `search` names text fields to keep in a
full-text index, for `db-search`.  `create-table` makes the table.

*Example:* A class with the `persistent` mixin and a description is kept in a table with a column for each field.  Saving a new object inserts it and gives it an id; `db-find` reads it back.

```lisp
(defclass book (littoral.db:persistent)
  ((title :initarg :title :initform nil :accessor book-title)
   (pages :initarg :pages :initform nil :accessor book-pages)))
(define-description book
  ((title :required t)
   (pages :type :integer :min 1)))
(littoral.db:define-table book)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'book)
  (let ((saved (littoral.db:db-save (make-instance 'book :title "Dune" :pages 412))))
    (let ((found (littoral.db:db-find 'book (littoral.db:object-id saved))))
      (list (book-title found) (book-pages found) (littoral.db:db-find 'book 99)))))
;; ⇒ ("Dune" 412 NIL)
```

#### `find-table` `designator` — function

The table of `designator`, a class name or an object.  Signals an error
when `define-table` hasn't defined one.

*Example:* `define-table`'s `:name` names the table; by default it is the class's name, with underscores for dashes.

```lisp
(defclass line-item (littoral.db:persistent) ((sku :initarg :sku :initform nil)))
(define-description line-item ((sku :required t)))
(littoral.db:define-table line-item)
(defclass invoice (littoral.db:persistent) ((number :initarg :number :initform nil)))
(define-description invoice ((number :required t)))
(littoral.db:define-table invoice :name "invoices")
(list (littoral.db:table-name (littoral.db:find-table 'line-item))
      (littoral.db:table-name (littoral.db:find-table (make-instance 'invoice)))
      (littoral.db:table-class (littoral.db:find-table 'invoice)))
;; ⇒ ("line_item" "invoices" INVOICE)
```

#### `table-name` `object` — generic function

Reads the name of a table.

*Example:* `define-table`'s `:name` names the table; by default it is the class's name, with underscores for dashes.

```lisp
(defclass line-item (littoral.db:persistent) ((sku :initarg :sku :initform nil)))
(define-description line-item ((sku :required t)))
(littoral.db:define-table line-item)
(defclass invoice (littoral.db:persistent) ((number :initarg :number :initform nil)))
(define-description invoice ((number :required t)))
(littoral.db:define-table invoice :name "invoices")
(list (littoral.db:table-name (littoral.db:find-table 'line-item))
      (littoral.db:table-name (littoral.db:find-table (make-instance 'invoice)))
      (littoral.db:table-class (littoral.db:find-table 'invoice)))
;; ⇒ ("line_item" "invoices" INVOICE)
```

#### `table-class` `object` — generic function

Reads the class of a table.

*Example:* `define-table`'s `:name` names the table; by default it is the class's name, with underscores for dashes.

```lisp
(defclass line-item (littoral.db:persistent) ((sku :initarg :sku :initform nil)))
(define-description line-item ((sku :required t)))
(littoral.db:define-table line-item)
(defclass invoice (littoral.db:persistent) ((number :initarg :number :initform nil)))
(define-description invoice ((number :required t)))
(littoral.db:define-table invoice :name "invoices")
(list (littoral.db:table-name (littoral.db:find-table 'line-item))
      (littoral.db:table-name (littoral.db:find-table (make-instance 'invoice)))
      (littoral.db:table-class (littoral.db:find-table 'invoice)))
;; ⇒ ("line_item" "invoices" INVOICE)
```

#### `create-table` `class` — function

Create `class`'s table unless it exists, with the columns id, version and
one for each field, and its full-text index if it has search fields.  An
existing table is left as it is, columns and all: change it with a
migration (see `define-migrations`).  Returns `class`.

*Example:* A class with the `persistent` mixin and a description is kept in a table with a column for each field.  Saving a new object inserts it and gives it an id; `db-find` reads it back.

```lisp
(defclass book (littoral.db:persistent)
  ((title :initarg :title :initform nil :accessor book-title)
   (pages :initarg :pages :initform nil :accessor book-pages)))
(define-description book
  ((title :required t)
   (pages :type :integer :min 1)))
(littoral.db:define-table book)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'book)
  (let ((saved (littoral.db:db-save (make-instance 'book :title "Dune" :pages 412))))
    (let ((found (littoral.db:db-find 'book (littoral.db:object-id saved))))
      (list (book-title found) (book-pages found) (littoral.db:db-find 'book 99)))))
;; ⇒ ("Dune" 412 NIL)
```

#### `drop-table` `class` — function

Drop `class`'s table if it exists, with its full-text index.

*Example:* Dropping a table that isn't there does nothing.

```lisp
(defclass draft (littoral.db:persistent) ((text :initarg :text :initform nil)))
(define-description draft ((text)))
(littoral.db:define-table draft)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (flet ((tables () (mapcar #'second (littoral.db:db-query "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'draft'"))))
    (littoral.db:create-table 'draft)
    (list (tables)
          (progn (littoral.db:drop-table 'draft) (tables))
          (progn (littoral.db:drop-table 'draft) (tables)))))
;; ⇒ (("draft") NIL NIL)
```

#### `db-find` `class id` — function

The object of `class` whose id is `id`, or `nil`.

*Example:* A class with the `persistent` mixin and a description is kept in a table with a column for each field.  Saving a new object inserts it and gives it an id; `db-find` reads it back.

```lisp
(defclass book (littoral.db:persistent)
  ((title :initarg :title :initform nil :accessor book-title)
   (pages :initarg :pages :initform nil :accessor book-pages)))
(define-description book
  ((title :required t)
   (pages :type :integer :min 1)))
(littoral.db:define-table book)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'book)
  (let ((saved (littoral.db:db-save (make-instance 'book :title "Dune" :pages 412))))
    (let ((found (littoral.db:db-find 'book (littoral.db:object-id saved))))
      (list (book-title found) (book-pages found) (littoral.db:db-find 'book 99)))))
;; ⇒ ("Dune" 412 NIL)
```

#### `db-select` `class &key where params order-by limit offset` — function

Objects of `class`: those `where` (SQL with ? for `params`) holds, in `order-by`
order (SQL, default by id), at most `limit` of them after skipping `offset`.

*Example:* `where` and `order-by` are SQL, with ? for each of `params`.  `limit` and `offset` page through the results.

```lisp
(defclass city (littoral.db:persistent)
  ((name :initarg :name :initform nil)
   (people :initarg :people :initform nil)))
(define-description city ((name :required t) (people :type :integer)))
(littoral.db:define-table city)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'city)
  (loop for (name people) in '(("Lyon" 522000) ("Nantes" 320000) ("Paris" 2100000) ("Lille" 236000))
        do (littoral.db:db-save (make-instance 'city :name name :people people)))
  (flet ((names (cities) (mapcar (lambda (c) (slot-value c 'name)) cities)))
    (list (names (littoral.db:db-select 'city))
          (names (littoral.db:db-select 'city :where "people > ?" :params '(300000)
                                              :order-by "people DESC"))
          (names (littoral.db:db-select 'city :order-by "name" :limit 2 :offset 1))
          (names (littoral.db:db-select 'city :order-by "name" :offset 2))
          (littoral.db:db-count 'city)
          (littoral.db:db-count 'city :where "name LIKE ?" :params '("L%")))))
;; ⇒ (("Lyon" "Nantes" "Paris" "Lille") ("Paris" "Lyon" "Nantes") ("Lyon" "Nantes") ("Nantes" "Paris") 4 2)
```

#### `db-count` `class &key where params` — function

How many objects of `class` `where` (SQL with ? for `params`) holds; all of
them without `where`.

*Example:* `where` and `order-by` are SQL, with ? for each of `params`.  `limit` and `offset` page through the results.

```lisp
(defclass city (littoral.db:persistent)
  ((name :initarg :name :initform nil)
   (people :initarg :people :initform nil)))
(define-description city ((name :required t) (people :type :integer)))
(littoral.db:define-table city)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'city)
  (loop for (name people) in '(("Lyon" 522000) ("Nantes" 320000) ("Paris" 2100000) ("Lille" 236000))
        do (littoral.db:db-save (make-instance 'city :name name :people people)))
  (flet ((names (cities) (mapcar (lambda (c) (slot-value c 'name)) cities)))
    (list (names (littoral.db:db-select 'city))
          (names (littoral.db:db-select 'city :where "people > ?" :params '(300000)
                                              :order-by "people DESC"))
          (names (littoral.db:db-select 'city :order-by "name" :limit 2 :offset 1))
          (names (littoral.db:db-select 'city :order-by "name" :offset 2))
          (littoral.db:db-count 'city)
          (littoral.db:db-count 'city :where "name LIKE ?" :params '("L%")))))
;; ⇒ (("Lyon" "Nantes" "Paris" "Lille") ("Paris" "Lyon" "Nantes") ("Lyon" "Nantes") ("Nantes" "Paris") 4 2)
```

#### `db-insert` `object` — function

Store `object` as a new row; it gets its id, and version 0.  Returns `object`.

*Example:* An object has no id until it is first saved.  Each update adds one to its version, which is how a conflicting save is noticed (see `stale-object`).  `db-save` calls `db-insert` or `db-update` as the object needs.

```lisp
(defclass note (littoral.db:persistent)
  ((text :initarg :text :initform nil :accessor note-text)))
(define-description note ((text :required t)))
(littoral.db:define-table note)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'note)
  (let ((note (make-instance 'note :text "Buy milk")))
    (list (littoral.db:object-id note)
          (progn (littoral.db:db-insert note)
                 (list (littoral.db:object-id note) (littoral.db:object-version note)))
          (progn (setf (note-text note) "Buy oat milk")
                 (littoral.db:db-update note)
                 (list (littoral.db:object-id note) (littoral.db:object-version note))))))
;; ⇒ (NIL (1 0) (1 1))
```

#### `db-update` `object` — function

Write `object`'s fields to its row and add one to its version.  Signals
`stale-object` when the row changed (or went) since `object` was read.  Returns
`object`.

*Example:* An object has no id until it is first saved.  Each update adds one to its version, which is how a conflicting save is noticed (see `stale-object`).  `db-save` calls `db-insert` or `db-update` as the object needs.

```lisp
(defclass note (littoral.db:persistent)
  ((text :initarg :text :initform nil :accessor note-text)))
(define-description note ((text :required t)))
(littoral.db:define-table note)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'note)
  (let ((note (make-instance 'note :text "Buy milk")))
    (list (littoral.db:object-id note)
          (progn (littoral.db:db-insert note)
                 (list (littoral.db:object-id note) (littoral.db:object-version note)))
          (progn (setf (note-text note) "Buy oat milk")
                 (littoral.db:db-update note)
                 (list (littoral.db:object-id note) (littoral.db:object-version note))))))
;; ⇒ (NIL (1 0) (1 1))
```

#### `db-save` `object` — function

Insert `object` if it has no id yet (`db-insert`), else update its row
(`db-update`, which signals `stale-object` when someone else changed it).
Returns `object`.

*Example:* A class with the `persistent` mixin and a description is kept in a table with a column for each field.  Saving a new object inserts it and gives it an id; `db-find` reads it back.

```lisp
(defclass book (littoral.db:persistent)
  ((title :initarg :title :initform nil :accessor book-title)
   (pages :initarg :pages :initform nil :accessor book-pages)))
(define-description book
  ((title :required t)
   (pages :type :integer :min 1)))
(littoral.db:define-table book)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'book)
  (let ((saved (littoral.db:db-save (make-instance 'book :title "Dune" :pages 412))))
    (let ((found (littoral.db:db-find 'book (littoral.db:object-id saved))))
      (list (book-title found) (book-pages found) (littoral.db:db-find 'book 99)))))
;; ⇒ ("Dune" 412 NIL)
```

#### `db-delete` `object` — function

Delete `object`'s row; `object`'s id becomes `nil`.  Signals `stale-object`
when the row changed (or went) since `object` was read.  Returns `object`.

*Example:* Deleting forgets the object's id.  Reloading a copy whose row has gone gives `nil`.

```lisp
(defclass reminder (littoral.db:persistent) ((text :initarg :text :initform nil)))
(define-description reminder ((text :required t)))
(littoral.db:define-table reminder)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'reminder)
  (let* ((reminder (littoral.db:db-save (make-instance 'reminder :text "Call the plumber")))
         (copy (littoral.db:db-find 'reminder (littoral.db:object-id reminder))))
    (list (slot-value (littoral.db:db-reload copy) 'text)
          (littoral.db:object-id (littoral.db:db-delete reminder))
          (littoral.db:db-reload copy)
          (littoral.db:db-count 'reminder))))
;; ⇒ ("Call the plumber" NIL NIL 0)
```

#### `db-reload` `object` — function

`object` as its row now holds it, or `nil` when the row has gone.

*Example:* Deleting forgets the object's id.  Reloading a copy whose row has gone gives `nil`.

```lisp
(defclass reminder (littoral.db:persistent) ((text :initarg :text :initform nil)))
(define-description reminder ((text :required t)))
(littoral.db:define-table reminder)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'reminder)
  (let* ((reminder (littoral.db:db-save (make-instance 'reminder :text "Call the plumber")))
         (copy (littoral.db:db-find 'reminder (littoral.db:object-id reminder))))
    (list (slot-value (littoral.db:db-reload copy) 'text)
          (littoral.db:object-id (littoral.db:db-delete reminder))
          (littoral.db:db-reload copy)
          (littoral.db:db-count 'reminder))))
;; ⇒ ("Call the plumber" NIL NIL 0)
```

#### `db-query` `sql &rest parameters` — function

Run SQL, with ? for each of `parameters`; the rows, as plists keyed by
column name ("login" → :|login|), `null` as `nil`.

*Example:* Plain SQL, with ? for each parameter.  `db-execute` answers how many rows changed; `db-query` the rows, as plists keyed by column name, `null` as `nil`.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:db-execute "CREATE TABLE visits (page TEXT, n INTEGER, note TEXT)")
  (list (littoral.db:db-execute "INSERT INTO visits (page, n) VALUES (?, ?), (?, ?)" "/" 10 "/about" 2)
        (littoral.db:db-execute "UPDATE visits SET n = n + 1 WHERE page = ?" "/about")
        (littoral.db:db-query "SELECT page, n, note FROM visits WHERE n > ? ORDER BY n" 0)))
;; ⇒ (2 1 ((:|page| "/about" :|n| 3 :|note| NIL) (:|page| "/" :|n| 10 :|note| NIL)))
```

#### `db-execute` `sql &rest parameters` — function

Run SQL, with ? for each of `parameters`; how many rows it changed.

*Example:* Plain SQL, with ? for each parameter.  `db-execute` answers how many rows changed; `db-query` the rows, as plists keyed by column name, `null` as `nil`.

```lisp
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:db-execute "CREATE TABLE visits (page TEXT, n INTEGER, note TEXT)")
  (list (littoral.db:db-execute "INSERT INTO visits (page, n) VALUES (?, ?), (?, ?)" "/" 10 "/about" 2)
        (littoral.db:db-execute "UPDATE visits SET n = n + 1 WHERE page = ?" "/about")
        (littoral.db:db-query "SELECT page, n, note FROM visits WHERE n > ? ORDER BY n" 0)))
;; ⇒ (2 1 ((:|page| "/about" :|n| 3 :|note| NIL) (:|page| "/" :|n| 10 :|note| NIL)))
```

#### `db-search` `class query &key limit offset` — function

`class`'s objects that `query` finds in its search fields (`define-table`'s
`:search`), the best first, at most `limit` of them after skipping `offset`.  Each of `query`'s words (letters and digits,
the first ten) matches words starting with it, and all are required; `nil`
when `query` has no words.  Signals an error when `class` has no search fields.

*Example:* `define-table`'s `:search` fields are kept in a full-text index.  Each word of a query matches words starting with it, and all are required.  `search-condition` gives the same test as a `where` clause, to combine with others in `db-select` or `db-count`.

```lisp
(defclass recipe (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (method :initarg :method :initform nil)))
(define-description recipe ((title :required t) (method :type :text)))
(littoral.db:define-table recipe :search (title method))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'recipe)
  (loop for (title method) in '(("Pancakes" "Whisk flour, eggs and milk; fry.")
                                ("Omelette" "Whisk the eggs and fry them in butter.")
                                ("Toast" "Grill the bread."))
        do (littoral.db:db-save (make-instance 'recipe :title title :method method)))
  (flet ((titles (recipes) (sort (mapcar (lambda (r) (slot-value r 'title)) recipes) #'string<)))
    (list (titles (littoral.db:db-search 'recipe "whisk egg"))
          (titles (littoral.db:db-search 'recipe "egg bread"))
          (multiple-value-bind (where params) (littoral.db:search-condition 'recipe "fry")
            (littoral.db:db-count 'recipe :where (format nil "~A AND title <> ?" where)
                                          :params (append params '("Omelette"))))
          (littoral.db:search-condition 'recipe "?!"))))
;; ⇒ (("Omelette" "Pancakes") NIL 1 NIL)
```

#### `search-condition` `class query` — function

A `where` clause matching `class`'s objects that `query` finds, and its
parameters, for `db-select`; `nil` when `query` has no words.

*Example:* `define-table`'s `:search` fields are kept in a full-text index.  Each word of a query matches words starting with it, and all are required.  `search-condition` gives the same test as a `where` clause, to combine with others in `db-select` or `db-count`.

```lisp
(defclass recipe (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (method :initarg :method :initform nil)))
(define-description recipe ((title :required t) (method :type :text)))
(littoral.db:define-table recipe :search (title method))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'recipe)
  (loop for (title method) in '(("Pancakes" "Whisk flour, eggs and milk; fry.")
                                ("Omelette" "Whisk the eggs and fry them in butter.")
                                ("Toast" "Grill the bread."))
        do (littoral.db:db-save (make-instance 'recipe :title title :method method)))
  (flet ((titles (recipes) (sort (mapcar (lambda (r) (slot-value r 'title)) recipes) #'string<)))
    (list (titles (littoral.db:db-search 'recipe "whisk egg"))
          (titles (littoral.db:db-search 'recipe "egg bread"))
          (multiple-value-bind (where params) (littoral.db:search-condition 'recipe "fry")
            (littoral.db:db-count 'recipe :where (format nil "~A AND title <> ?" where)
                                          :params (append params '("Omelette"))))
          (littoral.db:search-condition 'recipe "?!"))))
;; ⇒ (("Omelette" "Pancakes") NIL 1 NIL)
```

#### `highlight-matches` `text query` — function

`text` as HTML, escaped, with the words `query` finds marked <mark>: words of
`text` that start with one of `query`'s words.

*Example:* For showing search results: the text escaped, with the words a query finds marked.

```lisp
(littoral.db:highlight-matches "Fish & chips, fishcakes and chicken" "fish ch")
;; ⇒ "<mark>Fish</mark> &amp; <mark>chips</mark>, <mark>fishcakes</mark> and <mark>chicken</mark>"
```

#### `with-transaction` `() &body body` — macro

Run `body` in a transaction on `*database*`: committed if it returns, rolled
back if it signals.  Inside another on the same database, just `body`.
Returns `body`'s value.

*Example:* A transaction that signals is rolled back: the first account is not kept.

```lisp
(defclass account (littoral.db:persistent) ((owner :initarg :owner :initform nil)))
(define-description account ((owner :required t)))
(littoral.db:define-table account)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'account)
  (ignore-errors
   (littoral.db:with-transaction ()
     (littoral.db:db-save (make-instance 'account :owner "Ada"))
     (error "The bank is closed.")))
  (littoral.db:with-transaction ()
    (littoral.db:db-save (make-instance 'account :owner "Grace")))
  (mapcar (lambda (a) (slot-value a 'owner)) (littoral.db:db-select 'account)))
;; ⇒ ("Grace")
```

#### `transactional` — function

An `:around-actions` function running each request's callbacks in one
transaction, for `register-application`.

*Example:* With `:around-actions` (`transactional`), a request's callbacks share one transaction: when one fails, what the others saved is rolled back too.

```lisp
(defclass vote (littoral.db:persistent) ((choice :initarg :choice :initform nil)))
(define-description vote ((choice :required t)))
(littoral.db:define-table vote)
(defclass ballot (component) ())
(defmethod render ((self ballot))
  (p () (text (format nil "~D vote~:P" (littoral.db:db-count 'vote))))
  (anchor (:callback (lambda ()
                       (littoral.db:db-save (make-instance 'vote :choice "yes"))
                       (error "Counting failed.")))
    "Vote"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'vote)
  (with-fresh-applications (("/ballot" 'ballot :mode :deployment
                                               :around-actions (littoral.db:transactional)))
    (let ((b (make-instance 'browser)))
      (visit b "/ballot")
      (click b "Vote")
      (list (browser-status b) (littoral.db:db-count 'vote)))))
;; ⇒ (500 0)
```

#### `using-database` `driver &rest parameters` — function

An `:around-request` function giving an application its own database,
whatever else the process connects to: `driver` and `parameters` as for
`connect-database`.

*Example:* An application with a database of its own, whatever `*database*` says (here it is `nil`).

```lisp
(defclass memo (littoral.db:persistent) ((text :initarg :text :initform nil)))
(define-description memo ((text :required t)))
(littoral.db:define-table memo)
(defclass memo-count (component) ())
(defmethod render ((self memo-count))
  (p () (text (format nil "~D memo~:P" (littoral.db:db-count 'memo)))))
(let ((spec '(:sqlite3 :database-name ":memory:")))
  (let ((littoral.db:*database* spec))
    (littoral.db:create-table 'memo)
    (littoral.db:db-save (make-instance 'memo :text "Buy milk")))
  (let ((littoral.db:*database* nil))
    (with-fresh-applications (("/memos" 'memo-count :mode :deployment
                                                    :around-request (apply #'littoral.db:using-database spec)))
      (let ((b (make-instance 'browser)))
        (visit b "/memos")
        (body-text b)))))
;; ⇒ "1 memo"
```

#### `stale-object` — condition

Signalled when saving or deleting an object whose row has
changed (or gone) since the object was read.

*Example:* Two people edit the same row.  The second save would overwrite the first one's change, so it signals `stale-object` instead; reloading gives the current row to show or merge.

```lisp
(defclass wiki-page (littoral.db:persistent) ((body :initarg :body :initform nil)))
(define-description wiki-page ((body :type :text)))
(littoral.db:define-table wiki-page)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'wiki-page)
  (let* ((id (littoral.db:object-id (littoral.db:db-save (make-instance 'wiki-page :body "Draft"))))
         (mine (littoral.db:db-find 'wiki-page id))
         (theirs (littoral.db:db-find 'wiki-page id)))
    (setf (slot-value theirs 'body) "Theirs")
    (littoral.db:db-save theirs)
    (setf (slot-value mine 'body) "Mine")
    (handler-case (littoral.db:db-save mine)
      (littoral.db:stale-object (condition)
        (list (eq mine (littoral.db:stale-object-object condition))
              (slot-value (littoral.db:db-reload mine) 'body))))))
;; ⇒ (T "Theirs")
```

#### `stale-object-object` `condition` — generic function

The object whose save or delete `stale-object` refused.

*Example:* Two people edit the same row.  The second save would overwrite the first one's change, so it signals `stale-object` instead; reloading gives the current row to show or merge.

```lisp
(defclass wiki-page (littoral.db:persistent) ((body :initarg :body :initform nil)))
(define-description wiki-page ((body :type :text)))
(littoral.db:define-table wiki-page)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'wiki-page)
  (let* ((id (littoral.db:object-id (littoral.db:db-save (make-instance 'wiki-page :body "Draft"))))
         (mine (littoral.db:db-find 'wiki-page id))
         (theirs (littoral.db:db-find 'wiki-page id)))
    (setf (slot-value theirs 'body) "Theirs")
    (littoral.db:db-save theirs)
    (setf (slot-value mine 'body) "Mine")
    (handler-case (littoral.db:db-save mine)
      (littoral.db:stale-object (condition)
        (list (eq mine (littoral.db:stale-object-object condition))
              (slot-value (littoral.db:db-reload mine) 'body))))))
;; ⇒ (T "Theirs")
```

#### `reference-field` — class

Another stored object, chosen from its table; kept as its id.

*Example:* A `:reference` field holds another stored object, kept as its id.  Its choices are that table's objects, named by their first string field.

```lisp
(defclass author (littoral.db:persistent) ((name :initarg :name :initform nil)))
(define-description author ((name :required t)))
(littoral.db:define-table author)
(defclass novel (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (author :initarg :author :initform nil)))
(define-description novel ((title :required t) (author :type :reference :to 'author)))
(littoral.db:define-table novel)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'author)
  (littoral.db:create-table 'novel)
  (let* ((le-guin (littoral.db:db-save (make-instance 'author :name "Ursula K. Le Guin")))
         (novel (littoral.db:db-save (make-instance 'novel :title "The Dispossessed" :author le-guin)))
         (field (find-field 'novel 'author)))
    (list (littoral.db:reference-class field)
          (mapcar #'littoral.db:object-label (field-choices field))
          (littoral.db:object-label (slot-value (littoral.db:db-reload novel) 'author))
          (littoral.db:db-query "SELECT author FROM novel"))))
;; ⇒ (AUTHOR ("Ursula K. Le Guin") "Ursula K. Le Guin" ((:|author| 1)))
```

#### `reference-class` `object` — generic function

Reads the to of a reference-field.  The class of the objects referred to.

*Example:* A `:reference` field holds another stored object, kept as its id.  Its choices are that table's objects, named by their first string field.

```lisp
(defclass author (littoral.db:persistent) ((name :initarg :name :initform nil)))
(define-description author ((name :required t)))
(littoral.db:define-table author)
(defclass novel (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (author :initarg :author :initform nil)))
(define-description novel ((title :required t) (author :type :reference :to 'author)))
(littoral.db:define-table novel)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'author)
  (littoral.db:create-table 'novel)
  (let* ((le-guin (littoral.db:db-save (make-instance 'author :name "Ursula K. Le Guin")))
         (novel (littoral.db:db-save (make-instance 'novel :title "The Dispossessed" :author le-guin)))
         (field (find-field 'novel 'author)))
    (list (littoral.db:reference-class field)
          (mapcar #'littoral.db:object-label (field-choices field))
          (littoral.db:object-label (slot-value (littoral.db:db-reload novel) 'author))
          (littoral.db:db-query "SELECT author FROM novel"))))
;; ⇒ (AUTHOR ("Ursula K. Le Guin") "Ursula K. Le Guin" ((:|author| 1)))
```

#### `object-label` `object` — function

How `object` is named in choices and links: the value of its first string
field, or "#`id`" when it has none or that value is `nil`.

*Example:* A `:reference` field holds another stored object, kept as its id.  Its choices are that table's objects, named by their first string field.

```lisp
(defclass author (littoral.db:persistent) ((name :initarg :name :initform nil)))
(define-description author ((name :required t)))
(littoral.db:define-table author)
(defclass novel (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (author :initarg :author :initform nil)))
(define-description novel ((title :required t) (author :type :reference :to 'author)))
(littoral.db:define-table novel)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'author)
  (littoral.db:create-table 'novel)
  (let* ((le-guin (littoral.db:db-save (make-instance 'author :name "Ursula K. Le Guin")))
         (novel (littoral.db:db-save (make-instance 'novel :title "The Dispossessed" :author le-guin)))
         (field (find-field 'novel 'author)))
    (list (littoral.db:reference-class field)
          (mapcar #'littoral.db:object-label (field-choices field))
          (littoral.db:object-label (slot-value (littoral.db:db-reload novel) 'author))
          (littoral.db:db-query "SELECT author FROM novel"))))
;; ⇒ (AUTHOR ("Ursula K. Le Guin") "Ursula K. Le Guin" ((:|author| 1)))
```

#### `sql-type` `field` — generic function

The column type that holds `field`'s values.

*Example:* How a field's values are kept: a boolean is an integer column.

```lisp
(defclass chore (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (done :initarg :done :initform nil)))
(define-description chore ((title :required t) (done :type :boolean)))
(let ((field (find-field 'chore 'done)))
  (list (littoral.db:sql-type field) (littoral.db:to-sql field t) (littoral.db:from-sql field 0)))
;; ⇒ ("INTEGER" 1 NIL)
```

*Example:* A field kind of one's own: amounts of money, kept as whole cents so that sums are exact.  Binding `*field-kinds*` lets `define-description` use it without adding it for everyone.

```lisp
(defclass money-field (field) ()
  (:documentation "An amount of money, kept as whole cents."))
(defmethod littoral.db:sql-type ((field money-field)) "BIGINT")
(defmethod littoral.db:to-sql ((field money-field) value)
  (and value (round (* value 100))))
(defmethod littoral.db:from-sql ((field money-field) value)
  (and (integerp value) (/ value 100)))
(defclass product (littoral.db:persistent) ((price :initarg :price :initform nil)))
(let ((*field-kinds* (acons :money 'money-field *field-kinds*)))
  (define-description product ((price :type :money))))
(littoral.db:define-table product)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'product)
  (let ((id (littoral.db:object-id (littoral.db:db-save (make-instance 'product :price 12.5)))))
    (list (littoral.db:db-query "SELECT price FROM product")
          (slot-value (littoral.db:db-find 'product id) 'price))))
;; ⇒ (((:|price| 1250)) 25/2)
```

#### `to-sql` `field value` — generic function

`value` as it is written to `field`'s column.

*Example:* How a field's values are kept: a boolean is an integer column.

```lisp
(defclass chore (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (done :initarg :done :initform nil)))
(define-description chore ((title :required t) (done :type :boolean)))
(let ((field (find-field 'chore 'done)))
  (list (littoral.db:sql-type field) (littoral.db:to-sql field t) (littoral.db:from-sql field 0)))
;; ⇒ ("INTEGER" 1 NIL)
```

*Example:* A field kind of one's own: amounts of money, kept as whole cents so that sums are exact.  Binding `*field-kinds*` lets `define-description` use it without adding it for everyone.

```lisp
(defclass money-field (field) ()
  (:documentation "An amount of money, kept as whole cents."))
(defmethod littoral.db:sql-type ((field money-field)) "BIGINT")
(defmethod littoral.db:to-sql ((field money-field) value)
  (and value (round (* value 100))))
(defmethod littoral.db:from-sql ((field money-field) value)
  (and (integerp value) (/ value 100)))
(defclass product (littoral.db:persistent) ((price :initarg :price :initform nil)))
(let ((*field-kinds* (acons :money 'money-field *field-kinds*)))
  (define-description product ((price :type :money))))
(littoral.db:define-table product)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'product)
  (let ((id (littoral.db:object-id (littoral.db:db-save (make-instance 'product :price 12.5)))))
    (list (littoral.db:db-query "SELECT price FROM product")
          (slot-value (littoral.db:db-find 'product id) 'price))))
;; ⇒ (((:|price| 1250)) 25/2)
```

#### `from-sql` `field value` — generic function

The value `field` holds, from what its column held.

*Example:* How a field's values are kept: a boolean is an integer column.

```lisp
(defclass chore (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (done :initarg :done :initform nil)))
(define-description chore ((title :required t) (done :type :boolean)))
(let ((field (find-field 'chore 'done)))
  (list (littoral.db:sql-type field) (littoral.db:to-sql field t) (littoral.db:from-sql field 0)))
;; ⇒ ("INTEGER" 1 NIL)
```

*Example:* A field kind of one's own: amounts of money, kept as whole cents so that sums are exact.  Binding `*field-kinds*` lets `define-description` use it without adding it for everyone.

```lisp
(defclass money-field (field) ()
  (:documentation "An amount of money, kept as whole cents."))
(defmethod littoral.db:sql-type ((field money-field)) "BIGINT")
(defmethod littoral.db:to-sql ((field money-field) value)
  (and value (round (* value 100))))
(defmethod littoral.db:from-sql ((field money-field) value)
  (and (integerp value) (/ value 100)))
(defclass product (littoral.db:persistent) ((price :initarg :price :initform nil)))
(let ((*field-kinds* (acons :money 'money-field *field-kinds*)))
  (define-description product ((price :type :money))))
(littoral.db:define-table product)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'product)
  (let ((id (littoral.db:object-id (littoral.db:db-save (make-instance 'product :price 12.5)))))
    (list (littoral.db:db-query "SELECT price FROM product")
          (slot-value (littoral.db:db-find 'product id) 'price))))
;; ⇒ (((:|price| 1250)) 25/2)
```

### Migrations

#### `define-migrations` `name directory` — function

Define the migrations `name` (a keyword) as the .sql files in `directory`:
each NNN-description.sql, or NNN-description.sqlite.sql and .postgres.sql
for one driver.  The files are read now, so that an executable saved later
carries them, and read again by `migrate` while `directory` exists.  Defining
`name` again replaces it.  Signals an error when `directory` doesn't exist.
Returns `name`.

*Example:* An application keeps its schema as numbered files, usually in its source tree; here they are written to a temporary directory first.  `migrate` applies those the database lacks, and answers which it applied.

```lisp
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (write-migration directory "001-notes.sql" "CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT);
INSERT INTO notes (title) VALUES ('Welcome');")
         (write-migration directory "002-notes-get-a-due-date.sql" "ALTER TABLE notes ADD COLUMN due BIGINT;")
         (littoral.db:define-migrations :example-notes directory)
         (list (littoral.db:migrate :example-notes)
               (littoral.db:migrate :example-notes)
               (littoral.db:db-query "SELECT * FROM notes")))
    (littoral.db:forget-migrations :example-notes)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (((:EXAMPLE-NOTES 1 "001-notes.sql") (:EXAMPLE-NOTES 2 "002-notes-get-a-due-date.sql")) NIL ((:|id| 1 :|title| "Welcome" :|due| NIL)))
```

*Example:* A file named NNN-description.sqlite.sql or .postgres.sql replaces NNN-description.sql on that driver.  A file whose first comment says "-- littoral: one statement" runs whole, for a statement with semicolons inside, such as a SQLite trigger.  (On PostgreSQL this set would need a 002-touch.postgres.sql too.)

```lisp
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-2/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (write-migration directory "001-pages.sql" "CREATE TABLE pages (id SERIAL PRIMARY KEY, title TEXT, changed BIGINT);")
         (write-migration directory "001-pages.sqlite.sql" "CREATE TABLE pages (id INTEGER PRIMARY KEY, title TEXT, changed BIGINT);")
         (write-migration directory "002-touch.sqlite.sql" "-- littoral: one statement
CREATE TRIGGER pages_touch AFTER UPDATE OF title ON pages BEGIN
  UPDATE pages SET changed = 1 WHERE id = new.id;
END;")
         (littoral.db:define-migrations :example-pages directory)
         (littoral.db:migrate :example-pages)
         (littoral.db:db-execute "INSERT INTO pages (title) VALUES ('Home')")
         (littoral.db:db-execute "UPDATE pages SET title = 'Start'")
         (littoral.db:db-query "SELECT title, changed FROM pages"))
    (littoral.db:forget-migrations :example-pages)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ((:|title| "Start" :|changed| 1))
```

#### `migrate` `&rest names` — function

Apply the new migrations of each set `names` (keywords given to
`define-migrations`) to the current database, in order; the (`name` `version`
`file`) of each applied.  Signals `migration-error` when one fails, having
rolled it back, and `migration-changed` (a warning) for an applied file that
has since changed.  Signals an error when a set isn't defined, or its files
are misnamed, numbered twice, or lack a version for this driver.  /metrics
then reports how many of their migrations the database lacks.

*Example:* An application keeps its schema as numbered files, usually in its source tree; here they are written to a temporary directory first.  `migrate` applies those the database lacks, and answers which it applied.

```lisp
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (write-migration directory "001-notes.sql" "CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT);
INSERT INTO notes (title) VALUES ('Welcome');")
         (write-migration directory "002-notes-get-a-due-date.sql" "ALTER TABLE notes ADD COLUMN due BIGINT;")
         (littoral.db:define-migrations :example-notes directory)
         (list (littoral.db:migrate :example-notes)
               (littoral.db:migrate :example-notes)
               (littoral.db:db-query "SELECT * FROM notes")))
    (littoral.db:forget-migrations :example-notes)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (((:EXAMPLE-NOTES 1 "001-notes.sql") (:EXAMPLE-NOTES 2 "002-notes-get-a-due-date.sql")) NIL ((:|id| 1 :|title| "Welcome" :|due| NIL)))
```

#### `migration-status` `&rest names` — function

Each migration of the sets `names`, as plists of `:set` `:version` `:name` `:file`
and `:applied` (a universal time, or `nil` while it waits).

*Example:* Each migration of a set, with when it was applied (a universal time) or `nil` while it waits.

```lisp
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-3/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (flet ((status ()
                (mapcar (lambda (m) (list (getf m :version) (getf m :name) (integerp (getf m :applied))))
                        (littoral.db:migration-status :example-shop))))
         (write-migration directory "001-products.sql" "CREATE TABLE products (name TEXT);")
         (littoral.db:define-migrations :example-shop directory)
         (let ((before (status)))
           (littoral.db:migrate :example-shop)
           (write-migration directory "002-prices.sql" "ALTER TABLE products ADD COLUMN price BIGINT;")
           (list before (status))))
    (littoral.db:forget-migrations :example-shop)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (((1 "products" NIL)) ((1 "products" T) (2 "prices" NIL)))
```

#### `baseline-migrations` `name &key through` — function

Record `name`'s migrations up to version `through` (all, by default) as
applied without running them, for a database that already has their tables.

*Example:* A database made before the application had migrations already has the tables of the first ones: record those as applied, and `migrate` runs only the rest.

```lisp
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-4/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (littoral.db:db-execute "CREATE TABLE members (name TEXT)")   ; made by hand, long ago
         (write-migration directory "001-members.sql" "CREATE TABLE members (name TEXT);")
         (write-migration directory "002-emails.sql" "ALTER TABLE members ADD COLUMN email TEXT;")
         (littoral.db:define-migrations :example-club directory)
         (littoral.db:baseline-migrations :example-club :through 1)
         (littoral.db:migrate :example-club))
    (littoral.db:forget-migrations :example-club)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ((:EXAMPLE-CLUB 2 "002-emails.sql"))
```

#### `forget-migrations` `name` — function

Forget which of `name`'s migrations the current database has applied, as
when its tables are dropped, so that `migrate` applies them all again.

*Example:* After dropping a set's tables, forgetting its migrations lets `migrate` make them again.

```lisp
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-5/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (write-migration directory "001-scores.sql" "CREATE TABLE scores (n INTEGER);")
         (littoral.db:define-migrations :example-game directory)
         (littoral.db:migrate :example-game)
         (littoral.db:db-execute "DROP TABLE scores")
         (littoral.db:forget-migrations :example-game)
         (littoral.db:migrate :example-game))
    (littoral.db:forget-migrations :example-game)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ((:EXAMPLE-GAME 1 "001-scores.sql"))
```

#### `migration-error` — condition

A migration's statement failed; it was rolled back, and later ones weren't tried.

*Example:* A migration that fails is rolled back whole, and later ones aren't tried; those before it stay applied.

```lisp
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-6/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (write-migration directory "001-tags.sql" "CREATE TABLE tags (tag TEXT);")
         (write-migration directory "002-broken.sql" "CREATE TABLE tag_counts (tag TEXT, n INTEGER);
INSERT INTO no_such_table VALUES (1);")
         (write-migration directory "003-later.sql" "CREATE TABLE later (x TEXT);")
         (littoral.db:define-migrations :example-tags directory)
         (list (handler-case (littoral.db:migrate :example-tags)
                 (littoral.db:migration-error () :failed))
               (mapcar (lambda (row) (getf row :|name|))
                       (littoral.db:db-query "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('tags', 'tag_counts', 'later')"))
               (mapcar (lambda (m) (getf m :version))
                       (remove nil (littoral.db:migration-status :example-tags) :key (lambda (m) (getf m :applied))))))
    (littoral.db:forget-migrations :example-tags)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (:FAILED ("tags") (1))
```

#### `migration-changed` — condition

An applied migration's file is no longer what was applied.

*Example:* Editing a migration after it was applied changes nothing in the database; `migrate` warns instead.  Put the change in a new file.

```lisp
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-7/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (warnings '()))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (write-migration directory "001-events.sql" "CREATE TABLE events (what TEXT);")
         (littoral.db:define-migrations :example-events directory)
         (littoral.db:migrate :example-events)
         (write-migration directory "001-events.sql" "CREATE TABLE events (what TEXT, happened BIGINT);")
         (handler-bind ((littoral.db:migration-changed
                          (lambda (w) (push (princ-to-string w) warnings) (muffle-warning w))))
           (littoral.db:migrate :example-events))
         warnings)
    (littoral.db:forget-migrations :example-events)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ("Migration 001-events.sql of example-events was changed after it was applied; the change won't be applied. Put it in a new migration instead.")
```

## Package `littoral.storage`

Load with `(asdf:load-system :littoral/storage)`.  Stores uploaded files on
disk or in S3, with thumbnails, and gives descriptions the field types :file
and :image.

### General

#### `storage` — class

Somewhere to keep files.  A subclass specialises `storage-put`, `storage-get`,
`storage-delete` and `storage-url`.

*Example:* A storage of one's own: a subclass of `storage` with methods for the four generic functions.  This one keeps files in memory, and its URLs point at a `cdn`.

```lisp
(defclass memory-storage (littoral.storage:storage)
  ((files :initform (make-hash-table :test 'equal) :reader storage-files)))
(defmethod littoral.storage:storage-put ((storage memory-storage) key octets content-type)
  (setf (gethash key (storage-files storage)) (cons octets content-type))
  key)
(defmethod littoral.storage:storage-get ((storage memory-storage) key)
  (let ((entry (gethash key (storage-files storage))))
    (and entry (values (car entry) (cdr entry)))))
(defmethod littoral.storage:storage-delete ((storage memory-storage) key)
  (remhash key (storage-files storage)))
(defmethod littoral.storage:storage-url ((storage memory-storage) key &key filename expires)
  (declare (ignore expires))
  (format nil "https://cdn.example.org/~A~@[?download=~A~]" key filename))
(let* ((storage (make-instance 'memory-storage))
       (file (littoral.storage:store-octets (sb-ext:string-to-octets "%PDF-1.7") "minutes.pdf" :storage storage)))
  (list (nth-value 1 (littoral.storage:storage-get storage (littoral.storage:stored-file-key file)))
        (string= (littoral.storage:stored-file-url file :storage storage)
                 (format nil "https://cdn.example.org/~A?download=minutes.pdf" (littoral.storage:stored-file-key file)))
        (progn (littoral.storage:delete-stored-file file storage)
               (hash-table-count (storage-files storage)))))
;; ⇒ ("application/pdf" T 0)
```

#### `*storage*` — variable

Where description file fields keep their files, unless a field names its own.

*Example:* In a description, `:type` `:file` is an upload (with `:max-size` in bytes) and `:type` `:image` one that must be a PNG, `jpeg`, `gif` or WebP image, kept with a thumbnail.  Editors get a file chooser; files go to `*storage*` unless the field gives `:storage`.

```lisp
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(defclass applicant ()
  ((name :initarg :name :initform nil)
   (photo :initarg :photo :initform nil)
   (letter :initarg :letter :initform nil)))
(define-description applicant
  ((name :required t)
   (photo :type :image)
   (letter :type :file :max-size 1000)))
(defclass application-form (component)
  ((saved :initform nil :accessor saved)))
(defmethod render ((self application-form))
  (if (saved self)
      (p () (text (format nil "Saved: ~A" (littoral.storage:stored-file-name (slot-value (saved self) 'letter)))))
      (anchor (:callback (lambda ()
                           (show self (make-editor (make-instance 'applicant))
                                 :on-answer (lambda (applicant) (setf (saved self) applicant)))))
        "Apply")))
(let* ((directory (merge-pathnames "littoral-example-applicants/" (uiop:temporary-directory)))
       (littoral.storage:*storage* (littoral.storage:make-disk-storage directory :prefix "/applicant-files/")))
  (unwind-protect
       (with-fresh-applications (("/apply" 'application-form :mode :deployment))
         (let ((b (make-instance 'browser)) (messages '()))
           (visit b "/apply")
           (click b "Apply")
           (fill-in b "name" "Ada")
           (attach-file b "photo" "photo.txt" "image/png" "not a picture")
           (attach-file b "letter" "letter.txt" "text/plain" (make-string 2000 :initial-element #\a))
           (press b "Save")
           (push (not (null (has-text-p b "Photo must be a PNG, JPEG, GIF or WebP image."))) messages)
           (push (not (null (has-text-p b "Letter is too large: at most 1,000 bytes."))) messages)
           (setf (browser-files b) '())
           (attach-file b "photo" "ada.png" "image/png" (png 80 60))
           (attach-file b "letter" "letter.txt" "text/plain" "Dear committee,")
           (press b "Save")
           (list (reverse messages) (body-text b))))
    (unmount-handler "/applicant-files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ((T T) "Saved: letter.txt")
```

#### `disk-storage` — class

Files in a directory, served by Littoral under `prefix`.

*Example:* Keeping a file gives a `stored-file`: a new random key, the name it came with (without directories), its type as its bytes say, and its size.  The storage also serves files at its prefix, so the example unmounts it and deletes its directory afterwards.

```lisp
(let* ((directory (merge-pathnames "littoral-example-files/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "letters/ada.txt"
                                                  :storage storage)))
         (list (typep storage 'littoral.storage:disk-storage)
               (typep file 'littoral.storage:stored-file)
               (littoral.storage:stored-file-name file)
               (littoral.storage:stored-file-type file)
               (littoral.storage:stored-file-size file)
               (littoral.storage:stored-file-thumbnail file)
               (length (littoral.storage:stored-file-key file))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T T "ada.txt" "application/octet-stream" 9 NIL 28)
```

#### `make-disk-storage` `directory &key (prefix "/files/") private` — function

A `disk-storage` keeping files under `directory` (created if need be) and
serving them at `prefix`, through `mount-handler` (`unmount-handler` stops it).
With `private`, only signed URLs (`storage-url`) serve them, until they expire;
the signing key is random per process.

*Example:* Keeping a file gives a `stored-file`: a new random key, the name it came with (without directories), its type as its bytes say, and its size.  The storage also serves files at its prefix, so the example unmounts it and deletes its directory afterwards.

```lisp
(let* ((directory (merge-pathnames "littoral-example-files/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "letters/ada.txt"
                                                  :storage storage)))
         (list (typep storage 'littoral.storage:disk-storage)
               (typep file 'littoral.storage:stored-file)
               (littoral.storage:stored-file-name file)
               (littoral.storage:stored-file-type file)
               (littoral.storage:stored-file-size file)
               (littoral.storage:stored-file-thumbnail file)
               (length (littoral.storage:stored-file-key file))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T T "ada.txt" "application/octet-stream" 9 NIL 28)
```

*Example:* With `:private` T a file is served only through a signed URL, until it expires (`:expires` seconds, an hour by default).

```lisp
(defun status (url)
  (nth-value 0 (raw-request (make-instance 'browser) :get url)))
(let* ((directory (merge-pathnames "littoral-example-private/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/private/" :private t)))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Payslip") "payslip.txt" :storage storage)))
         (list (status (littoral.storage:stored-file-url file :storage storage))
               (status (format nil "/private/~A" (littoral.storage:stored-file-key file)))
               (status (littoral.storage:stored-file-url file :storage storage :expires -1))))
    (unmount-handler "/private/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (200 404 404)
```

#### `s3-storage` — class

Files in an `s3` bucket, addressed path-style, signed with `aws` Signature `v4`.
Unless the bucket is public, browsers fetch them through presigned URLs.

*Example:* Files in an `s3` bucket (or MinIO, `r2` and the like, given `:endpoint`).  Private storage, the default, hands out presigned URLs that expire; a public bucket's URLs point straight at it.  Making the storage contacts no server.

```lisp
(let ((public (littoral.storage:make-s3-storage :bucket "photos" :region "eu-west-1" :private nil))
      (private (littoral.storage:make-s3-storage :bucket "photos" :region "eu-west-1"
                                                 :access-key "AKIDEXAMPLE" :secret-key "secret")))
  (list (typep public 'littoral.storage:s3-storage)
        (littoral.storage:storage-url public "beach.png")
        (alexandria:starts-with-subseq
         "https://s3.eu-west-1.amazonaws.com/photos/beach.png?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIDEXAMPLE%2F"
         (littoral.storage:storage-url private "beach.png" :expires 600))))
;; ⇒ (T "https://s3.eu-west-1.amazonaws.com/photos/beach.png" T)
```

#### `make-s3-storage` `&key bucket (region "us-east-1") endpoint access-key secret-key (key-prefix "") (private t) (path-style t)` — function

An `s3-storage` keeping files in `bucket`, with `access-key` and `secret-key`.
`endpoint` defaults to `aws`'s for `region`; give it for MinIO or another service,
with `path-style` `nil` when it names the bucket itself.  `key-prefix` goes before
every key.  With `private` (the default), URLs are presigned and expire;
otherwise they point straight at the bucket.  Contacts no server.

*Example:* Files in an `s3` bucket (or MinIO, `r2` and the like, given `:endpoint`).  Private storage, the default, hands out presigned URLs that expire; a public bucket's URLs point straight at it.  Making the storage contacts no server.

```lisp
(let ((public (littoral.storage:make-s3-storage :bucket "photos" :region "eu-west-1" :private nil))
      (private (littoral.storage:make-s3-storage :bucket "photos" :region "eu-west-1"
                                                 :access-key "AKIDEXAMPLE" :secret-key "secret")))
  (list (typep public 'littoral.storage:s3-storage)
        (littoral.storage:storage-url public "beach.png")
        (alexandria:starts-with-subseq
         "https://s3.eu-west-1.amazonaws.com/photos/beach.png?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIDEXAMPLE%2F"
         (littoral.storage:storage-url private "beach.png" :expires 600))))
;; ⇒ (T "https://s3.eu-west-1.amazonaws.com/photos/beach.png" T)
```

#### `storage-put` `storage key octets content-type` — generic function

Keep `octets` under `key`, with `content-type`.  Returns `key`.

*Example:* A storage of one's own: a subclass of `storage` with methods for the four generic functions.  This one keeps files in memory, and its URLs point at a `cdn`.

```lisp
(defclass memory-storage (littoral.storage:storage)
  ((files :initform (make-hash-table :test 'equal) :reader storage-files)))
(defmethod littoral.storage:storage-put ((storage memory-storage) key octets content-type)
  (setf (gethash key (storage-files storage)) (cons octets content-type))
  key)
(defmethod littoral.storage:storage-get ((storage memory-storage) key)
  (let ((entry (gethash key (storage-files storage))))
    (and entry (values (car entry) (cdr entry)))))
(defmethod littoral.storage:storage-delete ((storage memory-storage) key)
  (remhash key (storage-files storage)))
(defmethod littoral.storage:storage-url ((storage memory-storage) key &key filename expires)
  (declare (ignore expires))
  (format nil "https://cdn.example.org/~A~@[?download=~A~]" key filename))
(let* ((storage (make-instance 'memory-storage))
       (file (littoral.storage:store-octets (sb-ext:string-to-octets "%PDF-1.7") "minutes.pdf" :storage storage)))
  (list (nth-value 1 (littoral.storage:storage-get storage (littoral.storage:stored-file-key file)))
        (string= (littoral.storage:stored-file-url file :storage storage)
                 (format nil "https://cdn.example.org/~A?download=minutes.pdf" (littoral.storage:stored-file-key file)))
        (progn (littoral.storage:delete-stored-file file storage)
               (hash-table-count (storage-files storage)))))
;; ⇒ ("application/pdf" T 0)
```

#### `storage-get` `storage key` — generic function

The octets kept under `key` and their content type, or `nil`.

*Example:* A storage of one's own: a subclass of `storage` with methods for the four generic functions.  This one keeps files in memory, and its URLs point at a `cdn`.

```lisp
(defclass memory-storage (littoral.storage:storage)
  ((files :initform (make-hash-table :test 'equal) :reader storage-files)))
(defmethod littoral.storage:storage-put ((storage memory-storage) key octets content-type)
  (setf (gethash key (storage-files storage)) (cons octets content-type))
  key)
(defmethod littoral.storage:storage-get ((storage memory-storage) key)
  (let ((entry (gethash key (storage-files storage))))
    (and entry (values (car entry) (cdr entry)))))
(defmethod littoral.storage:storage-delete ((storage memory-storage) key)
  (remhash key (storage-files storage)))
(defmethod littoral.storage:storage-url ((storage memory-storage) key &key filename expires)
  (declare (ignore expires))
  (format nil "https://cdn.example.org/~A~@[?download=~A~]" key filename))
(let* ((storage (make-instance 'memory-storage))
       (file (littoral.storage:store-octets (sb-ext:string-to-octets "%PDF-1.7") "minutes.pdf" :storage storage)))
  (list (nth-value 1 (littoral.storage:storage-get storage (littoral.storage:stored-file-key file)))
        (string= (littoral.storage:stored-file-url file :storage storage)
                 (format nil "https://cdn.example.org/~A?download=minutes.pdf" (littoral.storage:stored-file-key file)))
        (progn (littoral.storage:delete-stored-file file storage)
               (hash-table-count (storage-files storage)))))
;; ⇒ ("application/pdf" T 0)
```

#### `storage-delete` `storage key` — generic function

Forget what is kept under `key`.

*Example:* A storage of one's own: a subclass of `storage` with methods for the four generic functions.  This one keeps files in memory, and its URLs point at a `cdn`.

```lisp
(defclass memory-storage (littoral.storage:storage)
  ((files :initform (make-hash-table :test 'equal) :reader storage-files)))
(defmethod littoral.storage:storage-put ((storage memory-storage) key octets content-type)
  (setf (gethash key (storage-files storage)) (cons octets content-type))
  key)
(defmethod littoral.storage:storage-get ((storage memory-storage) key)
  (let ((entry (gethash key (storage-files storage))))
    (and entry (values (car entry) (cdr entry)))))
(defmethod littoral.storage:storage-delete ((storage memory-storage) key)
  (remhash key (storage-files storage)))
(defmethod littoral.storage:storage-url ((storage memory-storage) key &key filename expires)
  (declare (ignore expires))
  (format nil "https://cdn.example.org/~A~@[?download=~A~]" key filename))
(let* ((storage (make-instance 'memory-storage))
       (file (littoral.storage:store-octets (sb-ext:string-to-octets "%PDF-1.7") "minutes.pdf" :storage storage)))
  (list (nth-value 1 (littoral.storage:storage-get storage (littoral.storage:stored-file-key file)))
        (string= (littoral.storage:stored-file-url file :storage storage)
                 (format nil "https://cdn.example.org/~A?download=minutes.pdf" (littoral.storage:stored-file-key file)))
        (progn (littoral.storage:delete-stored-file file storage)
               (hash-table-count (storage-files storage)))))
;; ⇒ ("application/pdf" T 0)
```

#### `storage-url` `storage key &key filename expires` — generic function

A URL the browser can fetch `key`'s file from.  `filename`
names the download; `expires` (seconds) limits how long a private URL works.

*Example:* A storage of one's own: a subclass of `storage` with methods for the four generic functions.  This one keeps files in memory, and its URLs point at a `cdn`.

```lisp
(defclass memory-storage (littoral.storage:storage)
  ((files :initform (make-hash-table :test 'equal) :reader storage-files)))
(defmethod littoral.storage:storage-put ((storage memory-storage) key octets content-type)
  (setf (gethash key (storage-files storage)) (cons octets content-type))
  key)
(defmethod littoral.storage:storage-get ((storage memory-storage) key)
  (let ((entry (gethash key (storage-files storage))))
    (and entry (values (car entry) (cdr entry)))))
(defmethod littoral.storage:storage-delete ((storage memory-storage) key)
  (remhash key (storage-files storage)))
(defmethod littoral.storage:storage-url ((storage memory-storage) key &key filename expires)
  (declare (ignore expires))
  (format nil "https://cdn.example.org/~A~@[?download=~A~]" key filename))
(let* ((storage (make-instance 'memory-storage))
       (file (littoral.storage:store-octets (sb-ext:string-to-octets "%PDF-1.7") "minutes.pdf" :storage storage)))
  (list (nth-value 1 (littoral.storage:storage-get storage (littoral.storage:stored-file-key file)))
        (string= (littoral.storage:stored-file-url file :storage storage)
                 (format nil "https://cdn.example.org/~A?download=minutes.pdf" (littoral.storage:stored-file-key file)))
        (progn (littoral.storage:delete-stored-file file storage)
               (hash-table-count (storage-files storage)))))
;; ⇒ ("application/pdf" T 0)
```

#### `ensure-bucket` `storage` — function

Create `storage`'s bucket unless it exists (for tests and first runs).

#### `store-upload` `upload &rest options &key storage thumbnail` — function

Keep `upload`, an `uploaded-file` from a `file-input`, under the name it was
uploaded with; the `stored-file`.  `storage` and `thumbnail` are as for
`store-octets`.

*Example:* A file from a `file-input`, kept in `*storage*`.

```lisp
(defclass inbox (component)
  ((received :initform '() :accessor received)))
(defmethod render ((self inbox))
  (form (:multipart t)
    (file-input (:id "document"
                 :callback (lambda (upload)
                             (push (littoral.storage:store-upload upload) (received self)))))
    (submit-button () "Send"))
  (ul ()
    (dolist (file (received self))
      (li () (text (format nil "~A, ~D bytes" (littoral.storage:stored-file-name file)
                           (littoral.storage:stored-file-size file)))))))
(let* ((directory (merge-pathnames "littoral-example-inbox/" (uiop:temporary-directory)))
       (littoral.storage:*storage* (littoral.storage:make-disk-storage directory :prefix "/inbox-files/")))
  (unwind-protect
       (with-fresh-applications (("/inbox" 'inbox :mode :deployment))
         (let ((b (make-instance 'browser)))
           (visit b "/inbox")
           (attach-file b "document" "notes.txt" "text/plain" "Remember the milk.")
           (press b "Send")
           (body-text b)))
    (unmount-handler "/inbox-files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ "Send notes.txt, 18 bytes"
```

#### `store-octets` `octets name &key (storage *storage*) thumbnail` — function

Keep `octets`, uploaded as `name`, in `storage` under a new random key; the
`stored-file`.  Its name is `name` without directories, and its type is what
`sniff-type` says.  With `thumbnail`, a PNG, `jpeg` or `gif` image gets a `jpeg`
thumbnail too (see `*thumbnail-size*` and `*max-image-pixels*`).  Signals an
error when `storage` is `nil`.

*Example:* Keeping a file gives a `stored-file`: a new random key, the name it came with (without directories), its type as its bytes say, and its size.  The storage also serves files at its prefix, so the example unmounts it and deletes its directory afterwards.

```lisp
(let* ((directory (merge-pathnames "littoral-example-files/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "letters/ada.txt"
                                                  :storage storage)))
         (list (typep storage 'littoral.storage:disk-storage)
               (typep file 'littoral.storage:stored-file)
               (littoral.storage:stored-file-name file)
               (littoral.storage:stored-file-type file)
               (littoral.storage:stored-file-size file)
               (littoral.storage:stored-file-thumbnail file)
               (length (littoral.storage:stored-file-key file))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T T "ada.txt" "application/octet-stream" 9 NIL 28)
```

*Example:* With `:thumbnail` T an image also gets a `jpeg` thumbnail, at most `*thumbnail-size*` pixels on its longer side.

```lisp
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(let* ((directory (merge-pathnames "littoral-example-photos/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/photos/")))
  (unwind-protect
       (let* ((littoral.storage:*thumbnail-size* 120)
              (photo (littoral.storage:store-octets (png 600 300) "beach.png" :storage storage :thumbnail t))
              (thumbnail (littoral.storage:stored-file-thumbnail photo)))
         (list (littoral.storage:stored-file-type photo)
               (string= (littoral.storage:stored-file-thumbnail-url photo :storage storage)
                        (format nil "/photos/~A" thumbnail))
               (multiple-value-bind (octets type) (littoral.storage:storage-get storage thumbnail)
                 (list type (array-dimensions (flexi-streams:with-input-from-sequence (in octets)
                                                (opticl:read-jpeg-stream in)))))))
    (unmount-handler "/photos/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ("image/png" T ("image/jpeg" (60 120 3)))
```

#### `delete-stored-file` `file &optional (storage *storage*)` — function

Delete `file`, a `stored-file`, and its thumbnail from `storage`.

*Example:* Deleting a stored file deletes its thumbnail too; its URL then answers 404.

```lisp
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(let* ((directory (merge-pathnames "littoral-example-delete/" (uiop:temporary-directory)))
       (littoral.storage:*storage* (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((photo (littoral.storage:store-octets (png 40 30) "cat.png" :thumbnail t)))
         (littoral.storage:delete-stored-file photo)
         (list (littoral.storage:storage-get littoral.storage:*storage* (littoral.storage:stored-file-key photo))
               (littoral.storage:storage-get littoral.storage:*storage* (littoral.storage:stored-file-thumbnail photo))
               (nth-value 0 (raw-request (make-instance 'browser) :get (littoral.storage:stored-file-url photo)))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (NIL NIL 404)
```

#### `stored-file` — class

A file kept in storage: `key`, the `name` it was uploaded with, its `type` (as
sniffed), its `size` in bytes, and its `thumbnail`'s key or `nil`.

*Example:* Keeping a file gives a `stored-file`: a new random key, the name it came with (without directories), its type as its bytes say, and its size.  The storage also serves files at its prefix, so the example unmounts it and deletes its directory afterwards.

```lisp
(let* ((directory (merge-pathnames "littoral-example-files/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "letters/ada.txt"
                                                  :storage storage)))
         (list (typep storage 'littoral.storage:disk-storage)
               (typep file 'littoral.storage:stored-file)
               (littoral.storage:stored-file-name file)
               (littoral.storage:stored-file-type file)
               (littoral.storage:stored-file-size file)
               (littoral.storage:stored-file-thumbnail file)
               (length (littoral.storage:stored-file-key file))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T T "ada.txt" "application/octet-stream" 9 NIL 28)
```

#### `stored-file-key` `instance` — function

The key `file`, a `stored-file`, is kept under in its storage.

*Example:* Keeping a file gives a `stored-file`: a new random key, the name it came with (without directories), its type as its bytes say, and its size.  The storage also serves files at its prefix, so the example unmounts it and deletes its directory afterwards.

```lisp
(let* ((directory (merge-pathnames "littoral-example-files/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "letters/ada.txt"
                                                  :storage storage)))
         (list (typep storage 'littoral.storage:disk-storage)
               (typep file 'littoral.storage:stored-file)
               (littoral.storage:stored-file-name file)
               (littoral.storage:stored-file-type file)
               (littoral.storage:stored-file-size file)
               (littoral.storage:stored-file-thumbnail file)
               (length (littoral.storage:stored-file-key file))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T T "ada.txt" "application/octet-stream" 9 NIL 28)
```

#### `stored-file-name` `instance` — function

The name `file`, a `stored-file`, was uploaded with, without directories.

*Example:* Keeping a file gives a `stored-file`: a new random key, the name it came with (without directories), its type as its bytes say, and its size.  The storage also serves files at its prefix, so the example unmounts it and deletes its directory afterwards.

```lisp
(let* ((directory (merge-pathnames "littoral-example-files/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "letters/ada.txt"
                                                  :storage storage)))
         (list (typep storage 'littoral.storage:disk-storage)
               (typep file 'littoral.storage:stored-file)
               (littoral.storage:stored-file-name file)
               (littoral.storage:stored-file-type file)
               (littoral.storage:stored-file-size file)
               (littoral.storage:stored-file-thumbnail file)
               (length (littoral.storage:stored-file-key file))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T T "ada.txt" "application/octet-stream" 9 NIL 28)
```

#### `stored-file-type` `instance` — function

`file`'s content type, as `sniff-type` found it from its bytes.

*Example:* Keeping a file gives a `stored-file`: a new random key, the name it came with (without directories), its type as its bytes say, and its size.  The storage also serves files at its prefix, so the example unmounts it and deletes its directory afterwards.

```lisp
(let* ((directory (merge-pathnames "littoral-example-files/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "letters/ada.txt"
                                                  :storage storage)))
         (list (typep storage 'littoral.storage:disk-storage)
               (typep file 'littoral.storage:stored-file)
               (littoral.storage:stored-file-name file)
               (littoral.storage:stored-file-type file)
               (littoral.storage:stored-file-size file)
               (littoral.storage:stored-file-thumbnail file)
               (length (littoral.storage:stored-file-key file))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T T "ada.txt" "application/octet-stream" 9 NIL 28)
```

#### `stored-file-size` `instance` — function

`file`'s size in bytes.

*Example:* Keeping a file gives a `stored-file`: a new random key, the name it came with (without directories), its type as its bytes say, and its size.  The storage also serves files at its prefix, so the example unmounts it and deletes its directory afterwards.

```lisp
(let* ((directory (merge-pathnames "littoral-example-files/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "letters/ada.txt"
                                                  :storage storage)))
         (list (typep storage 'littoral.storage:disk-storage)
               (typep file 'littoral.storage:stored-file)
               (littoral.storage:stored-file-name file)
               (littoral.storage:stored-file-type file)
               (littoral.storage:stored-file-size file)
               (littoral.storage:stored-file-thumbnail file)
               (length (littoral.storage:stored-file-key file))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T T "ada.txt" "application/octet-stream" 9 NIL 28)
```

#### `stored-file-thumbnail` `instance` — function

The key of `file`'s thumbnail, or `nil` when it has none.

*Example:* Keeping a file gives a `stored-file`: a new random key, the name it came with (without directories), its type as its bytes say, and its size.  The storage also serves files at its prefix, so the example unmounts it and deletes its directory afterwards.

```lisp
(let* ((directory (merge-pathnames "littoral-example-files/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "letters/ada.txt"
                                                  :storage storage)))
         (list (typep storage 'littoral.storage:disk-storage)
               (typep file 'littoral.storage:stored-file)
               (littoral.storage:stored-file-name file)
               (littoral.storage:stored-file-type file)
               (littoral.storage:stored-file-size file)
               (littoral.storage:stored-file-thumbnail file)
               (length (littoral.storage:stored-file-key file))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T T "ada.txt" "application/octet-stream" 9 NIL 28)
```

*Example:* With `:thumbnail` T an image also gets a `jpeg` thumbnail, at most `*thumbnail-size*` pixels on its longer side.

```lisp
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(let* ((directory (merge-pathnames "littoral-example-photos/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/photos/")))
  (unwind-protect
       (let* ((littoral.storage:*thumbnail-size* 120)
              (photo (littoral.storage:store-octets (png 600 300) "beach.png" :storage storage :thumbnail t))
              (thumbnail (littoral.storage:stored-file-thumbnail photo)))
         (list (littoral.storage:stored-file-type photo)
               (string= (littoral.storage:stored-file-thumbnail-url photo :storage storage)
                        (format nil "/photos/~A" thumbnail))
               (multiple-value-bind (octets type) (littoral.storage:storage-get storage thumbnail)
                 (list type (array-dimensions (flexi-streams:with-input-from-sequence (in octets)
                                                (opticl:read-jpeg-stream in)))))))
    (unmount-handler "/photos/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ("image/png" T ("image/jpeg" (60 120 3)))
```

#### `stored-file-url` `file &key (storage *storage*) (expires 3600)` — function

A URL the browser can fetch `file` from in `storage`, downloading under the
name it was uploaded with.  A private storage's URL works for `expires`
seconds.

*Example:* Where the browser fetches a stored file.  Only PNG, `jpeg`, `gif` and WebP are shown in the page; anything else, such as this text, is served as a download under the name it was uploaded with.

```lisp
(defun fetch (url)
  "The status, Content-Type, Content-Disposition and text of URL, as the fake browser gets them."
  (multiple-value-bind (status headers body) (raw-request (make-instance 'browser) :get url)
    (list status (getf headers :content-type) (getf headers :content-disposition) body)))
(let* ((directory (merge-pathnames "littoral-example-files-2/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let* ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "ada.txt" :storage storage))
              (url (littoral.storage:stored-file-url file :storage storage)))
         (list (string= url (format nil "/files/~A?name=ada.txt" (littoral.storage:stored-file-key file)))
               (fetch url)
               (fetch "/files/nothing-here.txt")))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T (200 "application/octet-stream" "attachment; filename=\"ada.txt\"" "Dear Ada,") (404 "text/plain" NIL "Not found."))
```

*Example:* With `:private` T a file is served only through a signed URL, until it expires (`:expires` seconds, an hour by default).

```lisp
(defun status (url)
  (nth-value 0 (raw-request (make-instance 'browser) :get url)))
(let* ((directory (merge-pathnames "littoral-example-private/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/private/" :private t)))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Payslip") "payslip.txt" :storage storage)))
         (list (status (littoral.storage:stored-file-url file :storage storage))
               (status (format nil "/private/~A" (littoral.storage:stored-file-key file)))
               (status (littoral.storage:stored-file-url file :storage storage :expires -1))))
    (unmount-handler "/private/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (200 404 404)
```

#### `stored-file-thumbnail-url` `file &key (storage *storage*) (expires 3600)` — function

A URL the browser can fetch `file`'s thumbnail from in `storage`, or `nil` when
it has none.  A private storage's URL works for `expires` seconds.

*Example:* With `:thumbnail` T an image also gets a `jpeg` thumbnail, at most `*thumbnail-size*` pixels on its longer side.

```lisp
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(let* ((directory (merge-pathnames "littoral-example-photos/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/photos/")))
  (unwind-protect
       (let* ((littoral.storage:*thumbnail-size* 120)
              (photo (littoral.storage:store-octets (png 600 300) "beach.png" :storage storage :thumbnail t))
              (thumbnail (littoral.storage:stored-file-thumbnail photo)))
         (list (littoral.storage:stored-file-type photo)
               (string= (littoral.storage:stored-file-thumbnail-url photo :storage storage)
                        (format nil "/photos/~A" thumbnail))
               (multiple-value-bind (octets type) (littoral.storage:storage-get storage thumbnail)
                 (list type (array-dimensions (flexi-streams:with-input-from-sequence (in octets)
                                                (opticl:read-jpeg-stream in)))))))
    (unmount-handler "/photos/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ("image/png" T ("image/jpeg" (60 120 3)))
```

#### `file-field` — class

An uploaded file, kept in storage; the value is a `stored-file`.  A
description's `:type` `:file`, with the options `:storage` and `:max-size`.

*Example:* In a description, `:type` `:file` is an upload (with `:max-size` in bytes) and `:type` `:image` one that must be a PNG, `jpeg`, `gif` or WebP image, kept with a thumbnail.  Editors get a file chooser; files go to `*storage*` unless the field gives `:storage`.

```lisp
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(defclass applicant ()
  ((name :initarg :name :initform nil)
   (photo :initarg :photo :initform nil)
   (letter :initarg :letter :initform nil)))
(define-description applicant
  ((name :required t)
   (photo :type :image)
   (letter :type :file :max-size 1000)))
(defclass application-form (component)
  ((saved :initform nil :accessor saved)))
(defmethod render ((self application-form))
  (if (saved self)
      (p () (text (format nil "Saved: ~A" (littoral.storage:stored-file-name (slot-value (saved self) 'letter)))))
      (anchor (:callback (lambda ()
                           (show self (make-editor (make-instance 'applicant))
                                 :on-answer (lambda (applicant) (setf (saved self) applicant)))))
        "Apply")))
(let* ((directory (merge-pathnames "littoral-example-applicants/" (uiop:temporary-directory)))
       (littoral.storage:*storage* (littoral.storage:make-disk-storage directory :prefix "/applicant-files/")))
  (unwind-protect
       (with-fresh-applications (("/apply" 'application-form :mode :deployment))
         (let ((b (make-instance 'browser)) (messages '()))
           (visit b "/apply")
           (click b "Apply")
           (fill-in b "name" "Ada")
           (attach-file b "photo" "photo.txt" "image/png" "not a picture")
           (attach-file b "letter" "letter.txt" "text/plain" (make-string 2000 :initial-element #\a))
           (press b "Save")
           (push (not (null (has-text-p b "Photo must be a PNG, JPEG, GIF or WebP image."))) messages)
           (push (not (null (has-text-p b "Letter is too large: at most 1,000 bytes."))) messages)
           (setf (browser-files b) '())
           (attach-file b "photo" "ada.png" "image/png" (png 80 60))
           (attach-file b "letter" "letter.txt" "text/plain" "Dear committee,")
           (press b "Save")
           (list (reverse messages) (body-text b))))
    (unmount-handler "/applicant-files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ((T T) "Saved: letter.txt")
```

#### `image-field` — class

An uploaded PNG, `jpeg`, `gif` or WebP image, kept with a thumbnail.  A
description's `:type` `:image`, with the options of `file-field`.

*Example:* In a description, `:type` `:file` is an upload (with `:max-size` in bytes) and `:type` `:image` one that must be a PNG, `jpeg`, `gif` or WebP image, kept with a thumbnail.  Editors get a file chooser; files go to `*storage*` unless the field gives `:storage`.

```lisp
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(defclass applicant ()
  ((name :initarg :name :initform nil)
   (photo :initarg :photo :initform nil)
   (letter :initarg :letter :initform nil)))
(define-description applicant
  ((name :required t)
   (photo :type :image)
   (letter :type :file :max-size 1000)))
(defclass application-form (component)
  ((saved :initform nil :accessor saved)))
(defmethod render ((self application-form))
  (if (saved self)
      (p () (text (format nil "Saved: ~A" (littoral.storage:stored-file-name (slot-value (saved self) 'letter)))))
      (anchor (:callback (lambda ()
                           (show self (make-editor (make-instance 'applicant))
                                 :on-answer (lambda (applicant) (setf (saved self) applicant)))))
        "Apply")))
(let* ((directory (merge-pathnames "littoral-example-applicants/" (uiop:temporary-directory)))
       (littoral.storage:*storage* (littoral.storage:make-disk-storage directory :prefix "/applicant-files/")))
  (unwind-protect
       (with-fresh-applications (("/apply" 'application-form :mode :deployment))
         (let ((b (make-instance 'browser)) (messages '()))
           (visit b "/apply")
           (click b "Apply")
           (fill-in b "name" "Ada")
           (attach-file b "photo" "photo.txt" "image/png" "not a picture")
           (attach-file b "letter" "letter.txt" "text/plain" (make-string 2000 :initial-element #\a))
           (press b "Save")
           (push (not (null (has-text-p b "Photo must be a PNG, JPEG, GIF or WebP image."))) messages)
           (push (not (null (has-text-p b "Letter is too large: at most 1,000 bytes."))) messages)
           (setf (browser-files b) '())
           (attach-file b "photo" "ada.png" "image/png" (png 80 60))
           (attach-file b "letter" "letter.txt" "text/plain" "Dear committee,")
           (press b "Save")
           (list (reverse messages) (body-text b))))
    (unmount-handler "/applicant-files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ((T T) "Saved: letter.txt")
```

#### `*thumbnail-size*` — variable

The longest side of a thumbnail, in pixels.

*Example:* With `:thumbnail` T an image also gets a `jpeg` thumbnail, at most `*thumbnail-size*` pixels on its longer side.

```lisp
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(let* ((directory (merge-pathnames "littoral-example-photos/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/photos/")))
  (unwind-protect
       (let* ((littoral.storage:*thumbnail-size* 120)
              (photo (littoral.storage:store-octets (png 600 300) "beach.png" :storage storage :thumbnail t))
              (thumbnail (littoral.storage:stored-file-thumbnail photo)))
         (list (littoral.storage:stored-file-type photo)
               (string= (littoral.storage:stored-file-thumbnail-url photo :storage storage)
                        (format nil "/photos/~A" thumbnail))
               (multiple-value-bind (octets type) (littoral.storage:storage-get storage thumbnail)
                 (list type (array-dimensions (flexi-streams:with-input-from-sequence (in octets)
                                                (opticl:read-jpeg-stream in)))))))
    (unmount-handler "/photos/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ("image/png" T ("image/jpeg" (60 120 3)))
```

#### `*max-image-pixels*` — variable

Images with more pixels than this get no thumbnail: decoding one could
take all the memory (a small file can claim enormous dimensions).

*Example:* An image with more pixels than this gets no thumbnail, as decoding it could take all the memory.

```lisp
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(let* ((directory (merge-pathnames "littoral-example-big/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/big/")))
  (unwind-protect
       (let ((littoral.storage:*max-image-pixels* 10000))
         (list (littoral.storage:stored-file-thumbnail
                (littoral.storage:store-octets (png 200 100) "big.png" :storage storage :thumbnail t))
               (littoral.storage:stored-file-thumbnail-url
                (littoral.storage:store-octets (png 200 100) "big.png" :storage storage :thumbnail t)
                :storage storage)))
    (unmount-handler "/big/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (NIL NIL)
```

#### `sniff-type` `octets` — function

The type `octets`' first bytes say they are, whatever the browser said:
"image/png", "image/jpeg", "image/gif", "image/webp",
"application/pdf" or "application/zip", else
"application/octet-stream".

*Example:* A file's type comes from its first bytes, whatever its name or the browser said.

```lisp
(list (littoral.storage:sniff-type (sb-ext:string-to-octets "%PDF-1.7 …" :external-format :utf-8))
      (littoral.storage:sniff-type (coerce #(#xFF #xD8 #xFF #xE0 0 16) '(vector (unsigned-byte 8))))
      (littoral.storage:sniff-type (sb-ext:string-to-octets "<svg onload=\"alert(1)\">")))
;; ⇒ ("application/pdf" "image/jpeg" "application/octet-stream")
```

#### `*signing-key*` — variable

The key signing private file URLs.  Random per process unless set: set it,
from a secret, to share signed URLs between processes or across restarts.

## Package `littoral.oauth`

Sign in with OAuth 2 / OpenID Connect providers.  Load it with
`(asdf:load-system :littoral/oauth)`.

### General

#### `define-oauth-provider` `name &key (label (string-capitalize name)) authorize-url token-url userinfo-url client-id client-secret (scopes (quote ("openid" "email" "profile")))` — function

Offer signing in with the provider `name` (a keyword) on every sign-in form,
as a button labelled "Sign in with `label`".  `authorize-url`, `token-url` and
`userinfo-url` are the provider's; `client-id` and `client-secret` this
application's registration with it; `scopes` what to ask for (by default
openid, email and profile).  Register /oauth/`name` under the application's
address (from `*public-url*`), lower case, as the redirect address.  Redefining
replaces it.  Returns `name`.

*Example:* Define a provider with the addresses it publishes and this application's registration with it.  The sign-in form then offers it.

```lisp
(littoral.oauth:define-oauth-provider :github
  :label "GitHub"
  :authorize-url "https://github.com/login/oauth/authorize"
  :token-url "https://github.com/login/oauth/access_token"
  :userinfo-url "https://api.github.com/user"
  :client-id "the-client-id" :client-secret "the-client-secret"
  :scopes '("read:user" "user:email"))
;; ⇒ :GITHUB
(defclass oauth-sign-in-page (component) ())
(defmethod render ((self oauth-sign-in-page))
  (render-component (make-instance 'littoral.auth:sign-in)))
(list (length (littoral.oauth:oauth-providers))
      (not (null (littoral.oauth:find-oauth-provider "github")))
      (littoral.oauth:find-oauth-provider :gitlab)
      (let ((littoral.auth:*offer-passkeys* nil))
        (with-fresh-applications (("/sign-in" 'oauth-sign-in-page :mode :deployment))
          (let ((b (make-instance 'browser)))
            (visit b "/sign-in")
            (body-text b)))))
;; ⇒ (1 T NIL "Sign in Name Password Keep me signed in Sign in Cancel Forgot your password? Sign in with GitHub")
```

*Example:* The whole flow, with the provider played by two functions: the button sends the browser to the provider, which sends it back to /oauth/`name` with a code.  The code buys a token, the token the user's details, and the user is found by email, or made, and signed in.

```lisp
(defclass oauth-club (littoral.auth:auth-root component) ())
(defmethod render ((self oauth-club))
  (let ((user (littoral.auth:current-user)))
    (if user
        (p () (text (format nil "Hello, ~A." (littoral.auth:user-name user))))
        (anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in)))) "Sign in"))))
(littoral.oauth:define-oauth-provider :fakeid
  :label "FakeID"
  :authorize-url "https://id.example/authorize"
  :token-url "https://id.example/token"
  :userinfo-url "https://id.example/userinfo"
  :client-id "club" :client-secret "secret")
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*public-url* "https://club.example")
      (littoral.oauth:*http-post*
        (lambda (url parameters)
          (assert (string= url "https://id.example/token"))
          (assert (string= "the-code" (cdr (assoc "code" parameters :test #'string=))))
          "{\"access_token\": \"a-token\", \"token_type\": \"bearer\"}"))
      (littoral.oauth:*http-get*
        (lambda (url token)
          (assert (and (string= url "https://id.example/userinfo") (string= token "a-token")))
          "{\"email\": \"carol@example.org\", \"preferred_username\": \"carol\"}")))
  (littoral.auth:create-auth-tables)
  (with-fresh-applications (("/club" 'oauth-club :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/club")
      (click b "Sign in")
      (press b "Sign in with FakeID")
      (let* ((provider-url (browser-url b))
             (state (cl-ppcre:register-groups-bind (s) ("[?&]state=([^&]+)" provider-url) s)))
        (visit b (format nil "/club/oauth/fakeid?code=the-code&state=~A" state))
        (list (subseq provider-url 0 (position #\? provider-url))
              (not (null (search "redirect_uri=https%3A%2F%2Fclub.example%2Fclub%2Foauth%2Ffakeid" provider-url)))
              (body-text b)
              (littoral.auth:user-name (littoral.auth:find-user-by-email "carol@example.org")))))))
;; ⇒ ("https://id.example/authorize" T "Hello, carol." "carol")
```

#### `find-oauth-provider` `name` — function

The provider defined as `name` (a keyword or string, case aside), or `nil`.

*Example:* Define a provider with the addresses it publishes and this application's registration with it.  The sign-in form then offers it.

```lisp
(littoral.oauth:define-oauth-provider :github
  :label "GitHub"
  :authorize-url "https://github.com/login/oauth/authorize"
  :token-url "https://github.com/login/oauth/access_token"
  :userinfo-url "https://api.github.com/user"
  :client-id "the-client-id" :client-secret "the-client-secret"
  :scopes '("read:user" "user:email"))
;; ⇒ :GITHUB
(defclass oauth-sign-in-page (component) ())
(defmethod render ((self oauth-sign-in-page))
  (render-component (make-instance 'littoral.auth:sign-in)))
(list (length (littoral.oauth:oauth-providers))
      (not (null (littoral.oauth:find-oauth-provider "github")))
      (littoral.oauth:find-oauth-provider :gitlab)
      (let ((littoral.auth:*offer-passkeys* nil))
        (with-fresh-applications (("/sign-in" 'oauth-sign-in-page :mode :deployment))
          (let ((b (make-instance 'browser)))
            (visit b "/sign-in")
            (body-text b)))))
;; ⇒ (1 T NIL "Sign in Name Password Keep me signed in Sign in Cancel Forgot your password? Sign in with GitHub")
```

#### `oauth-providers` — function

The providers `define-oauth-provider` defined, in the order first defined.

*Example:* Define a provider with the addresses it publishes and this application's registration with it.  The sign-in form then offers it.

```lisp
(littoral.oauth:define-oauth-provider :github
  :label "GitHub"
  :authorize-url "https://github.com/login/oauth/authorize"
  :token-url "https://github.com/login/oauth/access_token"
  :userinfo-url "https://api.github.com/user"
  :client-id "the-client-id" :client-secret "the-client-secret"
  :scopes '("read:user" "user:email"))
;; ⇒ :GITHUB
(defclass oauth-sign-in-page (component) ())
(defmethod render ((self oauth-sign-in-page))
  (render-component (make-instance 'littoral.auth:sign-in)))
(list (length (littoral.oauth:oauth-providers))
      (not (null (littoral.oauth:find-oauth-provider "github")))
      (littoral.oauth:find-oauth-provider :gitlab)
      (let ((littoral.auth:*offer-passkeys* nil))
        (with-fresh-applications (("/sign-in" 'oauth-sign-in-page :mode :deployment))
          (let ((b (make-instance 'browser)))
            (visit b "/sign-in")
            (body-text b)))))
;; ⇒ (1 T NIL "Sign in Name Password Keep me signed in Sign in Cancel Forgot your password? Sign in with GitHub")
```

#### `*http-post*` — variable

A function of (URL `parameters`) posting a form and returning the body.

*Example:* The whole flow, with the provider played by two functions: the button sends the browser to the provider, which sends it back to /oauth/`name` with a code.  The code buys a token, the token the user's details, and the user is found by email, or made, and signed in.

```lisp
(defclass oauth-club (littoral.auth:auth-root component) ())
(defmethod render ((self oauth-club))
  (let ((user (littoral.auth:current-user)))
    (if user
        (p () (text (format nil "Hello, ~A." (littoral.auth:user-name user))))
        (anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in)))) "Sign in"))))
(littoral.oauth:define-oauth-provider :fakeid
  :label "FakeID"
  :authorize-url "https://id.example/authorize"
  :token-url "https://id.example/token"
  :userinfo-url "https://id.example/userinfo"
  :client-id "club" :client-secret "secret")
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*public-url* "https://club.example")
      (littoral.oauth:*http-post*
        (lambda (url parameters)
          (assert (string= url "https://id.example/token"))
          (assert (string= "the-code" (cdr (assoc "code" parameters :test #'string=))))
          "{\"access_token\": \"a-token\", \"token_type\": \"bearer\"}"))
      (littoral.oauth:*http-get*
        (lambda (url token)
          (assert (and (string= url "https://id.example/userinfo") (string= token "a-token")))
          "{\"email\": \"carol@example.org\", \"preferred_username\": \"carol\"}")))
  (littoral.auth:create-auth-tables)
  (with-fresh-applications (("/club" 'oauth-club :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/club")
      (click b "Sign in")
      (press b "Sign in with FakeID")
      (let* ((provider-url (browser-url b))
             (state (cl-ppcre:register-groups-bind (s) ("[?&]state=([^&]+)" provider-url) s)))
        (visit b (format nil "/club/oauth/fakeid?code=the-code&state=~A" state))
        (list (subseq provider-url 0 (position #\? provider-url))
              (not (null (search "redirect_uri=https%3A%2F%2Fclub.example%2Fclub%2Foauth%2Ffakeid" provider-url)))
              (body-text b)
              (littoral.auth:user-name (littoral.auth:find-user-by-email "carol@example.org")))))))
;; ⇒ ("https://id.example/authorize" T "Hello, carol." "carol")
```

#### `*http-get*` — variable

A function of (URL `access-token`) returning the body.

*Example:* The whole flow, with the provider played by two functions: the button sends the browser to the provider, which sends it back to /oauth/`name` with a code.  The code buys a token, the token the user's details, and the user is found by email, or made, and signed in.

```lisp
(defclass oauth-club (littoral.auth:auth-root component) ())
(defmethod render ((self oauth-club))
  (let ((user (littoral.auth:current-user)))
    (if user
        (p () (text (format nil "Hello, ~A." (littoral.auth:user-name user))))
        (anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in)))) "Sign in"))))
(littoral.oauth:define-oauth-provider :fakeid
  :label "FakeID"
  :authorize-url "https://id.example/authorize"
  :token-url "https://id.example/token"
  :userinfo-url "https://id.example/userinfo"
  :client-id "club" :client-secret "secret")
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*public-url* "https://club.example")
      (littoral.oauth:*http-post*
        (lambda (url parameters)
          (assert (string= url "https://id.example/token"))
          (assert (string= "the-code" (cdr (assoc "code" parameters :test #'string=))))
          "{\"access_token\": \"a-token\", \"token_type\": \"bearer\"}"))
      (littoral.oauth:*http-get*
        (lambda (url token)
          (assert (and (string= url "https://id.example/userinfo") (string= token "a-token")))
          "{\"email\": \"carol@example.org\", \"preferred_username\": \"carol\"}")))
  (littoral.auth:create-auth-tables)
  (with-fresh-applications (("/club" 'oauth-club :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/club")
      (click b "Sign in")
      (press b "Sign in with FakeID")
      (let* ((provider-url (browser-url b))
             (state (cl-ppcre:register-groups-bind (s) ("[?&]state=([^&]+)" provider-url) s)))
        (visit b (format nil "/club/oauth/fakeid?code=the-code&state=~A" state))
        (list (subseq provider-url 0 (position #\? provider-url))
              (not (null (search "redirect_uri=https%3A%2F%2Fclub.example%2Fclub%2Foauth%2Ffakeid" provider-url)))
              (body-text b)
              (littoral.auth:user-name (littoral.auth:find-user-by-email "carol@example.org")))))))
;; ⇒ ("https://id.example/authorize" T "Hello, carol." "carol")
```

## Package `littoral.websocket`

Load with `(asdf:load-system :littoral/websocket)`, then register an
application with `:websockets t`.  Its pages that have server push open one
WebSocket and carry their AJAX and push over it, falling back to fetch and
server-sent events when it can't open.  On Woo, pages keep server-sent
events.

### General

#### `*max-message-size*` — variable

The largest message, in bytes, a page may send over its socket (1 MiB by
default); a larger one closes the socket.

#### `*allowed-origins*` — variable

Origins (such as "https://app.example.org", compared ignoring case)
allowed to open sockets besides the server's own host, for pages served from
another name.  A socket from any other origin is refused with 403.

## Package `littoral.parenscript`

Load with `(asdf:load-system :littoral/parenscript)`.  Writes Littoral
components' browser behaviour in Parenscript.  A package using both this and
parenscript must shadow one CALL and one LABEL, as the parenscript demo does
with (:shadowing-import-from #:littoral #:call) and
(:shadowing-import-from #:littoral.html #:label).

### General

#### `in-browser` `code` — function

`code`, a string of JavaScript (as `parenscript:ps` makes it), as the value of
an `:on-click`, `:on-change`, `:on-input` or `:on-submit` attribute: the browser runs
it when that event happens, with `this` the element and `event` the event, and
sends no request.  The page's own script defines the code and the attribute
only names it, so use it while rendering.

*Example:* A handler that runs only in the browser, with no request: `this` is the element.  The attribute names code that the page's own script defines, so no code rides in attributes.  (Parenscript's names are written in full here; an application's package would use parenscript.)

```lisp
(defclass light-switch (component) ())
(defmethod render ((self light-switch))
  (button (:on-click (littoral.parenscript:in-browser
                      (parenscript:ps (parenscript:chain this class-list (toggle "on")))))
    "Light"))
(with-fresh-applications (("/switch" 'light-switch :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/switch")
    (list (not (null (cl-ppcre:scan "<button type=\"button\" data-lt-on-click-js=\"@c\\w+\">Light</button>" (browser-html b))))
          (not (null (search "this.classList.toggle('on');" (browser-html b)))))))
;; ⇒ (T T)
```

#### `client-callback` `function &key update` — function

Register `function`, of the string the browser sends ("" when it sends
none), for littoral.call(spec, value) in the browser; returns the spec, a
string.  Call it while rendering.  `update`, a component or a list of them,
is drawn again after `function` runs; `function`'s result, sent as JSON, is the
value of littoral.call's promise.

*Example:* A Lisp function the browser calls with littoral.call(spec, value).  Here the request littoral.js would send is made with `ajax-request`; the function's answer comes back as the JSON's "value".

```lisp
(defclass shouter (component) ())
(defmethod render ((self shouter))
  (let ((spec (littoral.parenscript:client-callback #'string-upcase)))
    (button (:on-click (littoral.parenscript:in-browser
                        (parenscript:ps
                          (parenscript:chain littoral (call (parenscript:lisp spec) "hello")
                                             (then (lambda (answer) (alert answer)))))))
      "Shout")))
(with-fresh-applications (("/shout" 'shouter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/shout")
    (let ((spec (cl-ppcre:register-groups-bind (s) ("littoral.call\\('([^']*)'" (browser-html b)) s)))
      (destructuring-bind (callback targets) (cl-ppcre:split ";" spec :limit 2)
        (ajax-request b callback targets :fields '(("_lt_value" . "quiet please")))))))
;; ⇒ "{\"fragments\":{},\"missing\":[],\"value\":\"QUIET PLEASE\",\"scripts\":[]}"
```

*Example:* With `:update`, the components named are drawn again after the function runs, and the page shows them before the promise resolves.

```lisp
(defclass tally (component updatable)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (let ((spec (littoral.parenscript:client-callback
               (lambda (value) (declare (ignore value)) (incf (tally-count self)))
               :update self)))
    (span () (text (format nil "~D so far" (tally-count self))))
    (button (:on-click (littoral.parenscript:in-browser
                        (parenscript:ps (parenscript:chain littoral (call (parenscript:lisp spec))))))
      "Count")))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tally")
    (let ((spec (cl-ppcre:register-groups-bind (s) ("littoral.call\\('([^']*)'" (browser-html b)) s)))
      (destructuring-bind (callback targets) (cl-ppcre:split ";" spec :limit 2)
        (let ((json (ajax-request b callback targets)))
          (list (not (null (search "1 so far" json)))
                (not (null (search "\"value\":1" json)))))))))
;; ⇒ (T T)
```

#### `define-script` `class (self) &body body` — macro

Give `class`'s pages the JavaScript `body`, written in Parenscript, with
`self` the component (use (`lisp` …) for its values): a `script` method.

*Example:* Page-level JavaScript for a component, written in Parenscript; (`lisp` …) splices in Lisp values.

```lisp
(defclass greeter (component)
  ((name :initarg :name :reader greeter-name)))
(littoral.parenscript:define-script greeter (self)
  (parenscript:chain console (log (+ "Hello, " (parenscript:lisp (greeter-name self))))))
(script (make-instance 'greeter :name "Ada"))
;; ⇒ "console.log('Hello, ' + 'Ada');"
```

## Package `littoral.woo`

Load with `(asdf:load-system :littoral/woo)`, then serve with
`(start :server :woo)` (and `:workers`, 4 by default): Woo's event loops
answer every request, and each open page with server push costs two libev
watchers on its loop instead of a thread.  Exports nothing.

## Package `littoral.generator`

Load with `(asdf:load-system :littoral/generator)`.  Generates the skeleton
of a new Littoral application; `make new NAME=…` in Littoral's checkout
calls it.

### General

#### `make-project` `name &key directory (title (title-from-name name)) (author (git-user-name)) (license "MIT") (port 8080) (template "basic")` — function

Write a new Littoral application called `name` (lower-case letters, digits
and dashes, starting with a letter, and not starting with "littoral") into
`directory`, by default ./`name`/, from `template` (one of `project-templates`,
"basic" by default).  `title` defaults to `name`'s words capitalised, `author` to
git's user.name, `license` to "`mit`" and `port` (where the project's make run serves it) to
8080.  The `license` file is written for the `mit` license only.  Signals an
error for a bad `name` or `template`, and rather than replace existing files.
Prints how to test and run the project; returns the directory.

*Example:* A new project from the basic template, written into a temporary directory (deleted afterwards).  The project's name fills in its file names and contents; `make-project` also prints how to test and run it, which the example discards.

```lisp
(let ((directory (merge-pathnames "littoral-example-bookshop/" (uiop:temporary-directory))))
  (unwind-protect
       (progn
         (let ((*standard-output* (make-broadcast-stream)))
           (littoral.generator:make-project "bookshop" :directory directory :author "Ada Lovelace" :port 8090))
         (list (sort (mapcar #'file-namestring (uiop:directory-files directory)) #'string<)
               (sort (mapcar #'file-namestring (uiop:directory-files (merge-pathnames "src/" directory))) #'string<)
               (find-if (lambda (line) (search ":author" line))
                        (uiop:read-file-lines (merge-pathnames "bookshop.asd" directory)))))
    (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore)))
;; ⇒ ((".gitignore" "LICENSE" "Makefile" "README.md" "bookshop.asd") ("app.lisp" "package.lisp") "  :author \"Ada Lovelace\"")
```

*Example:* A name must be lower-case letters, digits and dashes, starting with a letter.  Existing files are never replaced.

```lisp
(handler-case (littoral.generator:make-project "Book Shop")
  (error () :refused))
;; ⇒ :REFUSED
(let ((directory (merge-pathnames "littoral-example-twice/" (uiop:temporary-directory)))
      (*standard-output* (make-broadcast-stream)))
  (unwind-protect
       (progn
         (littoral.generator:make-project "twice" :directory directory :author "Ada")
         (handler-case (littoral.generator:make-project "twice" :directory directory :author "Ada")
           (error () :refused)))
    (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore)))
;; ⇒ :REFUSED
```

#### `project-templates` — function

The names of the templates `make-project` can start from.

*Example:* The templates there are: "basic" (a root component and its tests) and "app" (with a database, signing in and an admin).

```lisp
(sort (littoral.generator:project-templates) #'string<)
;; ⇒ ("app" "basic")
```
