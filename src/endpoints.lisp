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
  "Application path → list of (METHOD SEGMENTS FUNCTION DOCUMENTATION), the
last a plist of the pattern and what OPENAPI-DESCRIPTION says about it.")

(defvar *endpoint-parameters* nil "The path parameters of the endpoint being answered.")

(define-condition endpoint-error (error)
  ((status :initarg :status :reader endpoint-error-status)
   (message :initarg :message :reader endpoint-error-message))
  (:report (lambda (c s) (format s "~D: ~A" (endpoint-error-status c) (endpoint-error-message c))))
  (:documentation "Signalled by ENDPOINT-ERROR: answered as {\"error\": message} with its status."))

(defun endpoint-error (status message &rest arguments)
  "Answer the current endpoint request with STATUS and {\"error\": MESSAGE},
MESSAGE being a FORMAT control string for ARGUMENTS.  Signals ENDPOINT-ERROR."
  (error 'endpoint-error :status status :message (apply #'format nil message arguments)))

(defun path-segments (path)
  (remove "" (cl-ppcre:split "/" path) :test #'string=))

(defun register-endpoint (application-path method pattern function
                          &key summary description tags responses request-body query hidden)
  "Serve FUNCTION for METHOD requests to PATTERN under APPLICATION-PATH,
replacing any endpoint with the same method and pattern.  PATTERN's :NAME
segments become FUNCTION's arguments, URL-decoded strings, in order.
Returns (METHOD PATTERN).  The keywords describe it for OPENAPI-DESCRIPTION:
SUMMARY and DESCRIPTION are strings, TAGS a list of strings, RESPONSES a
list of (STATUS DESCRIPTION), REQUEST-BODY a description of the JSON sent,
QUERY a list of (NAME DESCRIPTION) for query parameters; HIDDEN leaves it out."
  (let ((application-path (normalize-path application-path))
        (segments (path-segments pattern))
        (method (intern (string-upcase method) :keyword)))
    (setf (gethash application-path *endpoints*)
          (append (remove-if (lambda (e) (and (eq (first e) method) (equal (second e) segments)))
                             (gethash application-path *endpoints*))
                  (list (list method segments function
                              (list :pattern pattern :summary summary :description description
                                    :tags tags :responses responses :request-body request-body
                                    :query query :hidden hidden)))))
    (list method pattern)))

;; DEFINE-ENDPOINT calls these as it expands.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun docstring-summary (documentation)
    "DOCUMENTATION's first sentence, and the whole of it unwrapped when it
says more (or NIL): paragraphs stay apart, lines within them are joined."
    (let* ((paragraphs (mapcar (lambda (paragraph)
                                 (cl-ppcre:regex-replace-all "\\s+" (string-trim '(#\Space #\Newline #\Tab) paragraph) " "))
                               (cl-ppcre:split "\\n\\s*\\n" documentation)))
           (whole (format nil "~{~A~^~%~%~}" paragraphs))
           (end (cl-ppcre:scan "[.!?](\\s|$)" whole))
           (summary (if end (subseq whole 0 (1+ end)) (first paragraphs))))
      (values summary (and (string/= summary whole) whole))))

  (defun endpoint-options (body)
    "BODY's leading docstring and keyword options, and the forms after them:
a docstring or an option is only one when forms follow it."
    (let ((documentation (when (and (stringp (first body)) (rest body)) (pop body)))
          (options '()))
      (loop while (and (keywordp (first body)) (cddr body))
            do (push (pop body) options) (push (pop body) options))
      (values documentation (nreverse options) body))))

(defmacro define-endpoint (application-path method pattern (&rest parameters) &body body)
  "Serve BODY as JSON for METHOD (:GET, :POST, :PUT, :PATCH, :DELETE)
requests to PATTERN, such as \"/api/items/:id\", under the application at
APPLICATION-PATH; a :GET endpoint answers HEAD too.  PARAMETERS are bound to
PATTERN's :NAME segments, in order, as strings.  BODY's value is the
response: hash tables and keyword plists are objects, other lists and
vectors arrays (#() for an empty one: NIL is null, as :NULL is), T true,
:FALSE false.  A second value is the status (200 by default), a third a
plist of extra headers.  ENDPOINT-ERROR answers with its status, another
error with 500, and a method PATTERN doesn't serve with 405.

BODY may start with a docstring, whose first sentence is the endpoint's
summary in OPENAPI-DESCRIPTION and the whole its description, and then
options, unevaluated: :TAGS (\"notes\"), :RESPONSES ((201 \"Created\") (422
\"No text\")), :REQUEST-BODY \"The note, with its text\" and :QUERY ((\"q\"
\"Words to find\")), as for REGISTER-ENDPOINT."
  (multiple-value-bind (documentation options body) (endpoint-options body)
    (destructuring-bind (&key tags responses request-body query) options
      (multiple-value-bind (summary description) (and documentation (docstring-summary documentation))
        `(register-endpoint ,application-path ,method ,pattern
                            (lambda (,@parameters) ,@body)
                            ,@(when documentation `(:summary ,summary :description ,description))
                            ,@(when tags `(:tags ',tags))
                            ,@(when responses `(:responses ',responses))
                            ,@(when request-body `(:request-body ,request-body))
                            ,@(when query `(:query ',query)))))))

(defun match-endpoint (app method path)
  "The endpoint of APP for METHOD and the PATH under it, and its arguments; or NIL."
  (let ((segments (path-segments path)))
    (dolist (endpoint (gethash (application-path app) *endpoints*))
      (destructuring-bind (endpoint-method pattern function &rest documentation) endpoint
        (declare (ignore documentation))
        (when (and (or (eq endpoint-method method) (and (eq method :head) (eq endpoint-method :get)))
                   (= (length pattern) (length segments)))
          (let ((arguments '()))
            (when (every (lambda (want have)
                           (cond ((char= (char want 0) #\:) (push (quri:url-decode have) arguments) t)
                                 (t (string= want have))))
                         pattern segments)
              (return (values function (nreverse arguments))))))))))

(defun endpoint-serves-path-p (application-path path)
  "True when the application at APPLICATION-PATH has an endpoint for PATH,
under it, whatever its method."
  (let ((segments (path-segments path)))
    (some (lambda (endpoint) (let ((pattern (second endpoint)))
                               (and (= (length pattern) (length segments))
                                    (every (lambda (want have) (or (char= (char want 0) #\:) (string= want have)))
                                           pattern segments))))
          (gethash application-path *endpoints*))))

(defun endpoint-path-p (app)
  "True when the request is for one of APP's endpoint paths, whatever its method."
  (endpoint-serves-path-p (application-path app) (request-extra-path-string app)))

(defun request-extra-path-string (app)
  (let* ((path (or (request-path) "/"))
         (base (application-path app)))
    (if (string= base "/") path (subseq path (min (length path) (length base))))))

(defvar *endpoint-authenticator* nil
  "A function of no arguments answering who an endpoint request comes from,
and how (:TOKEN or :COOKIE), or NIL for nobody; littoral/auth sets it.  A
write (any method but GET, HEAD and OPTIONS) that comes :COOKIE must send
Content-Type application/json, or gets 415: a cross-site form can't.")

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
                       headers (security-headers))
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

;;; OpenAPI: a description of an application's endpoints

(defun openapi-path (pattern)
  "PATTERN, such as /notes/:id, as OpenAPI writes it: /notes/{id}."
  (format nil "/~{~A~^/~}"
          (mapcar (lambda (segment) (if (char= (char segment 0) #\:) (format nil "{~A}" (subseq segment 1)) segment))
                  (path-segments pattern))))

(defun openapi-operation-id (method segments)
  "A name for the endpoint, as tools generating clients want: getNotesById."
  (with-output-to-string (out)
    (write-string (string-downcase method) out)
    (dolist (segment segments)
      (let ((parameter (char= (char segment 0) #\:)))
        (when parameter (write-string "By" out))
        (dolist (word (cl-ppcre:split "[^A-Za-z0-9]+" (if parameter (subseq segment 1) segment)))
          (when (plusp (length word))
            (write-string (string-capitalize word :end 1) out)))))))

(defun json-object (&rest pairs)
  "A hash table of PAIRS, string keys in order, leaving out NIL values: a
JSON object as OpenAPI spells it."
  (let ((table (make-hash-table :test 'equal)))
    (loop for (key value) on pairs by #'cddr
          when value do (setf (gethash key table) value))
    table))

(defun openapi-content (&optional (schema (json-object)))
  (json-object "application/json" (json-object "schema" schema)))

(defun openapi-error-response (description)
  (json-object "description" description
               "content" (openapi-content (json-object "$ref" "#/components/schemas/Error"))))

(defun openapi-operation (method segments documentation)
  (destructuring-bind (&key summary description tags responses request-body query &allow-other-keys) documentation
    (let ((parameters (append
                       (loop for segment in segments
                             when (char= (char segment 0) #\:)
                               collect (json-object "name" (subseq segment 1) "in" "path" "required" t
                                                    "schema" (json-object "type" "string")))
                       (loop for (name text) in query
                             collect (json-object "name" name "in" "query" "description" text
                                                  "schema" (json-object "type" "string")))))
          (answers (json-object)))
      (if responses
          (loop for (status text) in responses
                do (setf (gethash (princ-to-string status) answers)
                         (cond ((>= status 400) (openapi-error-response text))
                               ((= status 204) (json-object "description" text))
                               (t (json-object "description" text "content" (openapi-content))))))
          (setf (gethash "200" answers) (json-object "description" "OK" "content" (openapi-content))))
      (setf (gethash "default" answers) (openapi-error-response "An error, as {\"error\": message}"))
      (json-object "operationId" (openapi-operation-id method segments)
                   "summary" (or summary (format nil "~A ~A" method (openapi-path (format nil "~{/~A~}" segments))))
                   "description" description
                   "tags" (and tags (coerce tags 'vector))
                   "parameters" (and parameters (coerce parameters 'vector))
                   "requestBody" (when (or request-body (member method '(:post :put :patch)))
                                   (json-object "description" request-body
                                                "content" (openapi-content)))
                   "responses" answers))))

(defun openapi-description (application-path &key (title (format nil "~A API" (normalize-path application-path)))
                                                   (version "1") description license)
  "An OpenAPI 3.1 description of the endpoints of the application at
APPLICATION-PATH, as a hash table, which an endpoint answers as JSON: their
paths, path and query parameters, request bodies and responses, from what
DEFINE-ENDPOINT's docstrings and options say.  TITLE, VERSION (the API's,
\"1\" by default), DESCRIPTION and LICENSE (an SPDX identifier, such as
\"MIT\") are its info.  With littoral/auth loaded,
it says requests may carry a bearer API token."
  (let* ((application-path (normalize-path application-path))
         (paths (json-object)))
    (dolist (endpoint (gethash application-path *endpoints*))
      (destructuring-bind (method segments function &optional documentation) endpoint
        (declare (ignore function))
        (unless (getf documentation :hidden)
          (let* ((path (openapi-path (format nil "~{/~A~}" segments)))
                 (item (or (gethash path paths) (setf (gethash path paths) (json-object)))))
            (setf (gethash (string-downcase method) item) (openapi-operation method segments documentation))))))
    (json-object
     "openapi" "3.1.0"
     "info" (json-object "title" title "version" version "description" description
                         "license" (and license (json-object "name" license "identifier" license)))
     "servers" (vector (json-object "url" (url-for (if (string= application-path "/") "" application-path))))
     "paths" paths
     "components" (json-object
                   "schemas" (json-object "Error" (json-object "type" "object"
                                                               "properties" (json-object "error" (json-object "type" "string"))
                                                               "required" (vector "error")))
                   "securitySchemes" (when *endpoint-authenticator*
                                       (json-object "bearer" (json-object "type" "http" "scheme" "bearer"
                                                                          "description" "An API token; a browser signed in sends its cookie instead."))))
     "security" (when *endpoint-authenticator* (vector (json-object) (json-object "bearer" #()))))))

(defun serve-openapi (application-path &key (pattern "/openapi.json") title version description license)
  "Answer GET requests to PATTERN under APPLICATION-PATH with
OPENAPI-DESCRIPTION of its endpoints, with TITLE, VERSION, DESCRIPTION and
LICENSE, made afresh each time, so it covers endpoints defined later.  Returns (:GET PATTERN), as REGISTER-ENDPOINT does."
  (register-endpoint application-path :get pattern
                     (lambda ()
                       (apply #'openapi-description application-path
                              :description description :license license
                              (append (and title (list :title title)) (and version (list :version version)))))
                     :hidden t))
