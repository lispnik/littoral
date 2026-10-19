;;;; context.lisp — the dynamic state of one request

(in-package #:littoral)

(defvar *request* nil
  "The lack/request:request being handled.")

(defvar *session* nil
  "The SESSION owning the current request.")

(defvar *application* nil
  "The APPLICATION the current request was dispatched to.")

(defvar *render-context* nil
  "The RENDER-CONTEXT active while rendering: it knows where callbacks go
and how to build URLs back into the session.")

(defvar *base-path* ""
  "Prepended to every URL littoral writes: the mount prefix given to
MAKE-LACK-APP plus the request's script-name.  No trailing slash.")

(defun url-for (path)
  "PATH, absolute within this littoral, as a URL the browser can follow."
  (concatenate 'string *base-path* path))

(defmacro with-sane-printing (() &body body)
  "Run BODY with the printer as littoral expects it.  Some servers start
their threads with standard I/O syntax (Woo, through Bordeaux Threads 2),
where *PRINT-READABLY* is true: strings would print as #A(...) and hex as
#x1A, breaking ~S, object printing and even chunked encoding."
  `(let ((*print-readably* nil)
         (*print-pretty* nil)
         (*print-circle* nil)
         (*read-eval* nil))
     ,@body))

(defvar *async-stream-opener* nil
  "A function of (SOCKET STREAM WRITER) that serves STREAM from an event
loop, set by an optional system such as littoral/woo; NIL when there is
none and each stream gets a waiting thread.")

(defvar *code-version* 0
  "Incremented whenever watched rendering methods change (see live.lisp).")

(defvar *live-reload* t
  "When true, open pages of applications in development mode reload after
their components' rendering methods are redefined (see live.lisp).")

(defvar *redirect* nil
  "A URL a callback asked to send the browser to, with REDIRECT-TO.")

(defun redirect-to (url)
  "From a callback: when the request's callbacks are done, send the browser
to URL (another site, say) instead of the next page."
  (setf *redirect* url))

(defvar *download* nil
  "The response a callback asked for with SEND-DOWNLOAD, or NIL.")

(defun send-download (content &key (filename "download") (content-type "application/octet-stream"))
  "From a callback (not an AJAX one): answer the request with CONTENT, a
string (sent as UTF-8) or octets, as a file named FILENAME for the browser
to save, instead of showing the next page.  The page stays as it was, so
the callback shouldn't change anything else."
  (let ((octets (if (stringp content) (sb-ext:string-to-octets content :external-format :utf-8) content))
        (name (remove-if (lambda (c) (or (char< c #\Space) (find c "\"\\/"))) filename)))
    (setf *download*
          (list 200 (list :content-type content-type
                          :content-length (length octets)
                          :content-disposition (format nil "attachment; filename=\"~A\"" name)
                          :cache-control "no-store"
                          :x-content-type-options "nosniff"
                          :content-security-policy "default-src 'none'; sandbox")
                octets))))

(defun csv-cell (value)
  "VALUE as one CSV field: quoted when it holds a comma, quote or line
break, and with a leading apostrophe when it would otherwise start a
spreadsheet formula (=, +, -, @, tab or carriage return)."
  (let* ((text (cond ((null value) "") ((stringp value) value) (t (princ-to-string value))))
         (text (if (and (plusp (length text)) (find (char text 0) '(#\= #\+ #\- #\@ #\Tab #\Return))
                       (not (every (lambda (c) (or (digit-char-p c) (find c "+-.eE"))) text)))
                   (concatenate 'string "'" text)
                   text)))
    (if (find-if (lambda (c) (find c '(#\, #\" #\Newline #\Return))) text)
        (format nil "\"~A\"" (cl-ppcre:regex-replace-all "\"" text "\"\""))
        text)))

(defun csv-text (header rows)
  "CSV (RFC 4180, lines ending CRLF) of HEADER, a list of titles, then ROWS,
each a list of values; see CSV-CELL."
  (with-output-to-string (out)
    (dolist (line (cons header rows))
      (format out "~{~A~^,~}~C~C" (mapcar #'csv-cell line) #\Return #\Linefeed))))

(define-condition forbidden (error)
  ((message :initarg :message :initform "You are not allowed to do that." :reader forbidden-message))
  (:report (lambda (condition stream) (write-string (forbidden-message condition) stream)))
  (:documentation "Signal it to refuse a request: the user sees a 403 page
showing its :MESSAGE, by default \"You are not allowed to do that.\""))

(setf (documentation 'forbidden-message 'function)
      "The explanation a FORBIDDEN condition shows the user.")

(defvar *websocket-handler* nil
  "A function of (SESSION CONTINUATION) answering a page's WebSocket
request, set by littoral/websocket; NIL when WebSockets are not loaded.")

(defvar *debug-errors* nil
  "When true, errors inside a request enter the debugger instead of
rendering an error page.")

(defvar *request-parameters* nil
  "When non-NIL, the parameters of the request being handled, overriding
the HTTP request's: how a WebSocket message is handled like a POST.")

(defun current-parameters (&optional (request *request*))
  "The parameters of the request being handled, as an alist."
  (or *request-parameters*
      (and request (lack/request:request-parameters request))))

(defun request-parameter (name &optional (request *request*))
  "The value of the query or body parameter NAME in REQUEST, or NIL."
  (rest (assoc name (current-parameters request) :test #'string=)))

(defun request-parameter-p (name &optional (request *request*))
  "True when REQUEST has the parameter NAME, even with no value (?flag)."
  (and (assoc name (current-parameters request) :test #'string=) t))

(defun request-path (&optional (request *request*))
  "The path of REQUEST below the mount point, the application's path
included: \"/shop/items/3\".  REQUEST-EXTRA-PATH gives the segments after
the application's path."
  (lack/request:request-path-info request))

(defvar *render-profile* :off
  "While profiling a render, a list of (COMPONENT SECONDS DEPTH), newest
first; :OFF otherwise.")

(defvar *rendering* nil
  "True while a page or fragment renders, when state must not change.")

(define-condition render-phase-error (error)
  ((operation :initarg :operation :reader render-phase-operation))
  (:report (lambda (condition stream)
             (format stream "~(~A~) was used while rendering.  Rendering must not ~
change state: do it in a callback instead."
                     (render-phase-operation condition))))
  (:documentation "Signalled by CALL, SHOW, ANSWER, HOME and SHOW-MODAL during
rendering, which must not change state."))

(defun signal-if-rendering (operation)
  "Signal RENDER-PHASE-ERROR, naming OPERATION, when a page is rendering."
  (when *rendering*
    (error 'render-phase-error :operation operation)))

(defclass render-context ()
  ((callbacks :initarg :callbacks :reader render-callbacks)
   (action-url :initarg :action-url :reader render-action-url
               :documentation "Base URL (path plus _s/_k) callbacks are appended to.")
   (halos-p :initarg :halos-p :initform nil :reader render-halos-p)
   (ajax-p :initarg :ajax-p :initform nil :reader render-ajax-p)
   (client-code :initform '() :accessor render-client-code
                :documentation "(ID PARAMETERS BODY) for each piece of browser code the
page uses, defined by the page's own script rather than kept in attributes."))
  (:documentation "Where callbacks registered while rendering go, and the URL they are appended to."))

(defun action-url-params (session continuation-key)
  "The query parameters that lead back to CONTINUATION-KEY in SESSION."
  (append (unless (application-cookie-sessions-p (session-application session))
            (list (cons "_s" (session-key session))))
          (list (cons "_k" continuation-key))))
