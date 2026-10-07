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

(define-condition forbidden (error)
  ((message :initarg :message :initform "You are not allowed to do that." :reader forbidden-message))
  (:report (lambda (condition stream) (write-string (forbidden-message condition) stream)))
  (:documentation "Signal it to refuse a request: the user sees a 403 page."))

(defvar *debug-errors* nil
  "When true, errors inside a request enter the debugger instead of
rendering an error page.")

(defun request-parameter (name &optional (request *request*))
  "The value of the query or body parameter NAME in REQUEST, or NIL."
  (when request
    (rest (assoc name (lack/request:request-parameters request) :test #'string=))))

(defun request-parameter-p (name &optional (request *request*))
  "True when REQUEST has the parameter NAME, even with no value (?flag)."
  (and request
       (assoc name (lack/request:request-parameters request) :test #'string=)
       t))

(defun request-path (&optional (request *request*))
  "The path of REQUEST below the mount point."
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
  (:documentation "Signalled by CALL, SHOW, ANSWER and HOME during rendering."))

(defun signal-if-rendering (operation)
  "Signal RENDER-PHASE-ERROR, naming OPERATION, when a page is rendering."
  (when *rendering*
    (error 'render-phase-error :operation operation)))

(defclass render-context ()
  ((callbacks :initarg :callbacks :reader render-callbacks)
   (action-url :initarg :action-url :reader render-action-url
               :documentation "Base URL (path plus _s/_k) callbacks are appended to.")
   (halos-p :initarg :halos-p :initform nil :reader render-halos-p)
   (ajax-p :initarg :ajax-p :initform nil :reader render-ajax-p))
  (:documentation "Where callbacks registered while rendering go, and the URL they are appended to."))

(defun action-url-params (session continuation-key)
  "The query parameters that lead back to CONTINUATION-KEY in SESSION."
  (append (unless (application-cookie-sessions-p (session-application session))
            (list (cons "_s" (session-key session))))
          (list (cons "_k" continuation-key))))
