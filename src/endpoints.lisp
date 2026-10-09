;;;; endpoints.lisp — JSON endpoints beside an application's pages
;;;;
;;;;   (define-endpoint "/notes" :get "/api/notes" ()
;;;;     (mapcar #'note-json (all-notes)))
;;;;   (define-endpoint "/notes" :get "/api/notes/:id" (id)
;;;;     (or (find-note id) (endpoint-error 404 "No such note.")))
;;;;   (define-endpoint "/notes" :post "/api/notes" ()
;;;;     (let ((body (endpoint-body)))          ; the JSON sent, parsed
;;;;       (values (create-note (gethash "title" body)) 201)))
;;;;
;;;; An endpoint belongs to an application: it is served under the
;;;; application's path, through its :AROUND-REQUEST (so it shares its
;;;; database), outside any session.  Its value becomes the JSON response:
;;;; hash tables and keyword plists are objects, lists and vectors arrays
;;;; (#() for an empty one), :NULL or NIL null, T true, :FALSE false.  A
;;;; second value is the status, a third extra headers.  With littoral/auth,
;;;; ENDPOINT-USER is whoever the request comes from: a bearer API token, or
;;;; the browser's sign-in cookie.

(in-package #:littoral)

(defvar *endpoints* (make-hash-table :test 'equal)
  "Application path → list of (METHOD SEGMENTS FUNCTION).")

(defvar *endpoint-parameters* nil "The path parameters of the endpoint being answered.")

(define-condition endpoint-error (error)
  ((status :initarg :status :reader endpoint-error-status)
   (message :initarg :message :reader endpoint-error-message))
  (:report (lambda (c s) (format s "~D: ~A" (endpoint-error-status c) (endpoint-error-message c))))
  (:documentation "Signalled by ENDPOINT-ERROR: answered as {\"error\": message} with its status."))

(defun endpoint-error (status message &rest arguments)
  "Answer the current endpoint request with STATUS and {\"error\": MESSAGE}."
  (error 'endpoint-error :status status :message (apply #'format nil message arguments)))

(defun path-segments (path)
  (remove "" (cl-ppcre:split "/" path) :test #'string=))

(defun register-endpoint (application-path method pattern function)
  "Serve FUNCTION for METHOD requests to PATTERN under APPLICATION-PATH.
PATTERN's :NAME segments become FUNCTION's arguments, as strings."
  (let ((application-path (normalize-path application-path))
        (segments (path-segments pattern))
        (method (intern (string-upcase method) :keyword)))
    (setf (gethash application-path *endpoints*)
          (append (remove-if (lambda (e) (and (eq (first e) method) (equal (second e) segments)))
                             (gethash application-path *endpoints*))
                  (list (list method segments function))))
    (list method pattern)))

(defmacro define-endpoint (application-path method pattern (&rest parameters) &body body)
  "Serve BODY as JSON for METHOD (:GET, :POST, :PUT, :PATCH, :DELETE)
requests to PATTERN, such as \"/api/items/:id\", under the application at
APPLICATION-PATH.  PARAMETERS are bound to PATTERN's :NAME segments, in order."
  `(register-endpoint ,application-path ,method ,pattern
                      (lambda (,@parameters) ,@body)))

(defun match-endpoint (app method path)
  "The endpoint of APP for METHOD and the PATH under it, and its arguments; or NIL."
  (let ((segments (path-segments path)))
    (dolist (endpoint (gethash (application-path app) *endpoints*))
      (destructuring-bind (endpoint-method pattern function) endpoint
        (when (and (or (eq endpoint-method method) (and (eq method :head) (eq endpoint-method :get)))
                   (= (length pattern) (length segments)))
          (let ((arguments '()))
            (when (every (lambda (want have)
                           (cond ((char= (char want 0) #\:) (push (quri:url-decode have) arguments) t)
                                 (t (string= want have))))
                         pattern segments)
              (return (values function (nreverse arguments))))))))))

(defun endpoint-path-p (app)
  "True when the request is for one of APP's endpoint paths, whatever its method."
  (let ((segments (path-segments (request-extra-path-string app))))
    (some (lambda (endpoint) (let ((pattern (second endpoint)))
                               (and (= (length pattern) (length segments))
                                    (every (lambda (want have) (or (char= (char want 0) #\:) (string= want have)))
                                           pattern segments))))
          (gethash (application-path app) *endpoints*))))

(defun request-extra-path-string (app)
  (let* ((path (or (request-path) "/"))
         (base (application-path app)))
    (if (string= base "/") path (subseq path (min (length path) (length base))))))

(defvar *endpoint-authenticator* nil
  "A function of no arguments answering who an endpoint request comes from,
and how (:TOKEN or :COOKIE); littoral/auth sets it.")

(defun endpoint-body ()
  "The request's JSON body, parsed (objects as hash tables), or NIL when empty.
Signals ENDPOINT-ERROR 400 when it isn't JSON."
  (let* ((raw (lack/request:request-raw-body *request*))
         (length (or (lack/request:request-content-length *request*) 0))
         ;; Exactly Content-Length bytes: the body stream needn't end there.
         (octets (and raw (plusp length) (<= length *max-request-size*)
                      (let ((buffer (make-array length :element-type '(unsigned-byte 8))))
                        (subseq buffer 0 (read-sequence buffer raw)))))
         (text (and octets (plusp (length octets)) (sb-ext:octets-to-string octets :external-format :utf-8))))
    (and text
         (handler-case (com.inuoe.jzon:parse text :max-depth 32)
           (error () (endpoint-error 400 "The body isn't JSON."))))))

(defun json-response (status value &optional headers)
  (list status (append (list :content-type "application/json; charset=utf-8" :cache-control "no-store")
                       headers *security-headers*)
        (list (json-value value))))

(defun answer-endpoint (app function arguments)
  "Call FUNCTION with ARGUMENTS and answer with what it returns, as JSON."
  (let ((method (lack/request:request-method *request*)))
    ;; A browser's cookie mustn't be enough to change things from another
    ;; site: writes signed in by cookie must say they send JSON, which a
    ;; plain cross-site form can't.
    (when (and (not (member method '(:get :head :options)))
               *endpoint-authenticator*
               (eq (nth-value 1 (funcall *endpoint-authenticator*)) :cookie)
               (not (search "application/json" (or (gethash "content-type" (lack/request:request-headers *request*)) ""))))
      (return-from answer-endpoint
        (json-response 415 (list :error "Send JSON (Content-Type: application/json)."))))
    (handler-case
        (multiple-value-bind (value status headers) (apply function arguments)
          (json-response (or status 200) value headers))
      (endpoint-error (e)
        (json-response (endpoint-error-status e) (list :error (endpoint-error-message e))))
      (forbidden (e)
        (json-response 403 (list :error (forbidden-message e))))
      (error (e)
        (json-response 500 (list :error (if (development-p app) (princ-to-string e) "The request failed.")))))))

(defun handle-endpoint (app)
  "Answer the request with APP's endpoint for it, or NIL when it has none."
  (when (gethash (application-path app) *endpoints*)
    (let ((method (lack/request:request-method *request*)))
      (multiple-value-bind (function arguments) (match-endpoint app method (request-extra-path-string app))
        (cond (function
               (call-around-request app (lambda () (answer-endpoint app function arguments))))
              ((endpoint-path-p app)
               (json-response 405 (list :error "That method isn't allowed here."))))))))
