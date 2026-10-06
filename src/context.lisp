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

(defvar *debug-errors* nil
  "When true, errors inside a request enter the debugger instead of
rendering an error page.")

(defun request-parameter (name &optional (request *request*))
  "The value of the query or body parameter NAME in REQUEST, or NIL."
  (when request
    (cdr (assoc name (lack/request:request-parameters request) :test #'string=))))

(defun request-path (&optional (request *request*))
  (lack/request:request-path-info request))

(defclass render-context ()
  ((callbacks :initarg :callbacks :reader render-callbacks)
   (action-url :initarg :action-url :reader render-action-url
               :documentation "Base URL (path plus _s/_k) callbacks are appended to.")
   (halos-p :initarg :halos-p :initform nil :reader render-halos-p)
   (ajax-p :initarg :ajax-p :initform nil :reader render-ajax-p)))

(defun action-url-params (session continuation-key)
  "The query parameters that lead back to CONTINUATION-KEY in SESSION."
  (append (unless (application-cookie-sessions-p (session-application session))
            (list (cons "_s" (session-key session))))
          (list (cons "_k" continuation-key))))
