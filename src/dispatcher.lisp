;;;; dispatcher.lisp — from a Lack request to a response
;;;;
;;;; Seaside's request cycle:
;;;;
;;;;  1. No session (or an expired one): make the root component, start its
;;;;     tasks, snapshot it as the first page and redirect there.
;;;;  2. A request naming a page (_k) and callbacks: restore that page's
;;;;     snapshot, run the callbacks, snapshot the result as a new page and
;;;;     redirect to it, so reloading never repeats an action.
;;;;  3. A request naming a page and no callbacks: restore its snapshot and
;;;;     render it, registering the callbacks its links will name.

(in-package #:littoral)

(defvar *static-directory* (asdf:system-relative-pathname :littoral "static/"))

(defparameter *static-types*
  '(("js" . "text/javascript; charset=utf-8")
    ("css" . "text/css; charset=utf-8")))

(defvar *static-cache* (make-hash-table :test 'equal)
  "Static file name → (WRITE-DATE CONTENTS FINGERPRINT).")

(defun static-file (name)
  "The contents and fingerprint of static file NAME, or NIL.  Re-read when
the file changes on disk."
  (let ((path (merge-pathnames name *static-directory*)))
    (when (and (not (search ".." name)) (probe-file path))
      (let ((date (file-write-date path))
            (cached (gethash name *static-cache*)))
        (unless (eql date (first cached))
          (let ((contents (alexandria:read-file-into-string path :external-format :utf-8)))
            (setf cached (list date contents
                               (subseq (ironclad:byte-array-to-hex-string
                                        (ironclad:digest-sequence
                                         :sha1 (sb-ext:string-to-octets contents :external-format :utf-8)))
                                       0 10))
                  (gethash name *static-cache*) cached)))
        (values (second cached) (third cached))))))

(defun static-url (name)
  "The URL of littoral's static file NAME, fingerprinted with its contents
so browsers may cache it for good yet never run a stale copy."
  (let ((fingerprint (nth-value 1 (static-file name))))
    (url-for (format nil "/littoral/files/~A~@[?v=~A~]" name fingerprint))))

;;; Responses

(defparameter *security-headers*
  '(;; Session keys ride in URLs: never send them to other sites.
    :referrer-policy "same-origin"
    :x-content-type-options "nosniff"
    :x-frame-options "SAMEORIGIN")
  "Headers added to every page, redirect and AJAX response.")

(defun html-response (html &key (status 200) headers)
  "A Lack response carrying HTML, uncached, with the security headers."
  (list status
        (append (list :content-type "text/html; charset=utf-8"
                      :cache-control "no-store")
                headers
                *security-headers*)
        (list html)))

(defun redirect-response (url &key headers)
  "A Lack 302 response to URL."
  (list 302 (append (list :location url :cache-control "no-store") headers *security-headers*)
        (list "")))

(defvar *max-request-size* (* 10 1024 1024)
  "Largest request body littoral reads, in bytes, unless the application
says otherwise.  Larger requests get 413 before their body is read.")

(defvar *new-sessions-per-minute* 120
  "How many sessions one client address may start a minute; more get 429.
NIL for no limit.")

(defvar *max-event-streams* 1000
  "Most event streams open at once; more get 503.")

(defvar *max-event-streams-per-session* 8
  "Most event streams one session may hold open.")

(defvar *trust-forwarded-for* nil
  "When true, take the client address from X-Forwarded-For.  Set it only
behind a proxy that sets that header itself.")

(defun client-address (&optional (request *request*))
  "The address the request came from, by X-Forwarded-For when trusted."
  (let ((forwarded (gethash "x-forwarded-for" (lack/request:request-headers request))))
    (if (and *trust-forwarded-for* forwarded)
        (string-trim " " (first (cl-ppcre:split "," forwarded)))
        (lack/request:request-remote-addr request))))

(defun local-request-p (&optional (request *request*))
  "True when REQUEST comes from this machine and not through a proxy we
were not told to trust."
  (and (member (client-address request) '("127.0.0.1" "::1" "0:0:0:0:0:0:0:1") :test #'equal)
       (or *trust-forwarded-for*
           (null (gethash "x-forwarded-for" (lack/request:request-headers request))))))

(defvar *session-starts* (make-hash-table :test 'equal)
  "Client address → (MINUTE . SESSIONS-STARTED).")

(defvar *session-starts-lock* (sb-thread:make-mutex :name "littoral session starts"))

(defun allow-new-session-p ()
  "Count a new session for this client; NIL when it is over its limit."
  (or (null *new-sessions-per-minute*)
      (let ((address (or (client-address) "unknown"))
            (minute (floor (get-universal-time) 60)))
        (sb-thread:with-mutex (*session-starts-lock*)
          (let ((entry (gethash address *session-starts*)))
            (when (or (null entry) (/= (car entry) minute))
              ;; A new minute: forget the old counts.
              (when (> (hash-table-count *session-starts*) 10000)
                (clrhash *session-starts*))
              (setf entry (cons minute 0)
                    (gethash address *session-starts*) entry))
            (<= (incf (cdr entry)) *new-sessions-per-minute*))))))

(defun browser-cookie-name (app)
  "The cookie that ties APP's URL sessions to the browser that started them."
  (format nil "_ltb~A" (substitute #\_ #\/ (application-path app))))

(defun request-cookie (name)
  "The value of the request's cookie NAME, or NIL."
  (cdr (assoc name (lack/request:request-cookies *request*) :test #'string=)))

(defun session-cookie-header (name value app)
  "A Set-Cookie value for NAME=VALUE scoped to APP, Secure over HTTPS."
  (format nil "~A=~A; Path=~A; HttpOnly; SameSite=Lax~:[~;; Secure~]"
          name value (application-base-url app) (secure-request-p)))

(defun browser-matches-p (session)
  "True when this request may use SESSION: it carries the session's browser
cookie, or the browser has never sent cookies (so cannot be told apart).
Binds the session to its cookie the first time it comes back."
  (let* ((app (session-application session))
         (cookie (request-cookie (browser-cookie-name app))))
    (cond ((application-cookie-sessions-p app) t)
          ((null cookie) (not (session-browser-bound-p session)))
          ((string= cookie (session-browser-key session))
           (setf (session-browser-bound-p session) t))
          (t nil))))

(defun secure-request-p (&optional (request *request*))
  "True when REQUEST came over HTTPS, directly or through a proxy that says so."
  (or (string-equal (princ-to-string (lack/request:request-uri-scheme request)) "https")
      (string-equal (gethash "x-forwarded-proto" (lack/request:request-headers request) "") "https")))

(defun simple-page (status title &optional (message ""))
  "A minimal HTML page with TITLE as its heading and the HTML MESSAGE below."
  (html-response
   (format nil "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>~A</title>~
<link rel=\"stylesheet\" href=\"~A\"></head><body><h1>~A</h1>~A</body></html>"
           (html-escape title) (static-url "littoral.css") (html-escape title) message)
   :status status))

(defun serve-static (name)
  "The response for littoral's static file NAME, cached for good when the request names its current fingerprint."
  (let ((type (rest (assoc (pathname-type (pathname name)) *static-types* :test #'equal))))
    (multiple-value-bind (contents fingerprint) (and type (static-file name))
      (if contents
          (list 200 (list :content-type type
                          :cache-control (if (equal (request-parameter "v") fingerprint)
                                             "public, max-age=31536000, immutable"
                                             "no-cache"))
                (list contents))
          (simple-page 404 "Not Found")))))

(defun page-url (session continuation)
  "The URL of CONTINUATION: the application's path, what UPDATE-URL methods
add, then the session and page keys."
  (let ((url (make-instance 'page-url)))
    (map-visible (lambda (c) (update-url c url)) (session-root session))
    (url-with-params (format nil "~A~{/~A~}"
                             (application-base-url (session-application session))
                             (mapcar #'quri:url-encode (url-path url)))
                     (append (url-parameters url)
                             (action-url-params session (continuation-key continuation))))))

(defun request-extra-path (&optional (app *application*) (request *request*))
  "The decoded path segments of REQUEST after APP's path."
  (let* ((path (normalize-path (or (lack/request:request-path-info request) "/")))
         (base (application-path app))
         (rest (if (string= base "/") path (subseq path (min (length path) (length base))))))
    (mapcar #'quri:url-decode
            (remove "" (cl-ppcre:split "/" rest) :test #'string=))))

;;; Rendering a page

(defun development-p (&optional (app *application*))
  "True when APP shows the toolbar and halos."
  (eql (application-mode app) :development))

(defun render-document (session body-html action-url)
  "The whole HTML document for SESSION's page: head from UPDATE-ROOT, then BODY-HTML."
  (let ((app (session-application session))
        (root (make-instance 'html-root)))
    (setf (root-title root) (or (application-title app) (application-path app)))
    (map-visible (lambda (c) (update-root c root)) (session-root session))
    (with-output-to-string (out)
      (format out "<!DOCTYPE html>~%<html lang=\"~A\"><head><meta charset=\"utf-8\">~
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">~
<title>~A</title>~%" (html-escape (application-language app)) (html-escape (root-title root)))
      (dolist (url (append (list (static-url "littoral.css"))
                           (application-stylesheets app)
                           (reverse (root-stylesheets root))))
        (format out "<link rel=\"stylesheet\" href=\"~A\">~%" (html-escape url)))
      (when (root-styles root)
        (format out "<style>~%~{~A~%~}</style>~%" (reverse (root-styles root))))
      (dolist (url (append (list (static-url "littoral.js"))
                           (application-scripts app)
                           (reverse (root-scripts root))))
        (format out "<script src=\"~A\" defer></script>~%" (html-escape url)))
      (format out "</head>~%<body data-lt-action=\"~A\"~@[ data-lt-events=\"~A\"~]~@[ data-lt-live=\"~A\"~]>~%"
              (html-escape action-url)
              (when (page-listens-p session)
                (html-escape (concatenate 'string action-url "&_lt_events=1")))
              (when (page-polls-p session)
                (html-escape (format nil "~A&_lt_live=~D" action-url *code-version*))))
      (write-string body-html out)
      (when (root-inline-scripts root)
        (format out "~%<script>~%~{~A~%~}</script>" (reverse (root-inline-scripts root))))
      (format out "~%</body></html>~%"))))

(defun render-page (session continuation)
  "Render CONTINUATION's page, registering its callbacks afresh."
  (let* ((app (session-application session))
         (callbacks (continuation-callbacks continuation))
         (action-url (page-url session continuation))
         (start (get-internal-real-time)))
    (clear-callbacks callbacks)
    (let* ((*render-profile* (if (session-profiling-p session) '() :off))
           (*render-context* (make-instance 'render-context
                                            :callbacks callbacks
                                            :action-url action-url
                                            :halos-p (and (development-p app)
                                                          (session-halos-p session))))
           (body (with-canvas-to-string ()
                   (let ((*rendering* t))
                     (render-component (session-root session)))
                   (when (development-p app)
                     (render-toolbar session start))
                   (render-toasts (take-toasts session)))))
      (html-response (render-document session body action-url)))))

;;; The cycle

(defun session-key-from-request (app)
  "The session key the request names, from the URL or APP's cookie."
  (if (application-cookie-sessions-p app)
      (rest (assoc (session-cookie-name app) (lack/request:request-cookies *request*)
                  :test #'string=))
      (request-parameter "_s")))

(defun start-session (app &key expired)
  "Start a session of APP.  EXPIRED is true when the request named a
session that has gone; the application's EXPIRED-NOTICE is shown first."
  (let* ((session (create-session app))
         (*session* session)
         (browser (request-cookie (browser-cookie-name app))))
    ;; A browser that already has an identity keeps it, so its other tabs'
    ;; sessions stay tied to it too.
    (when browser
      (setf (session-browser-key session) browser
            (session-browser-bound-p session) t))
    (sb-thread:with-recursive-lock ((session-lock session))
      (let ((root (session-root session)))
        (initial-request root *request*)
        (prepare-tasks root)
        (when (and expired (application-expired-notice app))
          (show root (make-instance (application-expired-notice app)))))
      (redirect-response (page-url session (new-continuation session))
                         :headers (list :set-cookie
                                        (if (application-cookie-sessions-p app)
                                            (session-cookie-header (session-cookie-name app)
                                                                   (session-key session) app)
                                            (session-cookie-header (browser-cookie-name app)
                                                                   (session-browser-key session) app)))))))

(defun handle-ajax (session continuation)
  "Run an AJAX request's callbacks on CONTINUATION, without making a new
page, and answer the components to update as JSON."
  (let* ((root (session-root session))
         (callbacks (continuation-callbacks continuation))
         (*ajax-result* nil)
         (*ajax-scripts* '())
         (*redirect* nil))
    (call-around-actions session
                         (lambda ()
                           (process-callbacks (lack/request:request-parameters *request*) callbacks)
                           (prepare-tasks root)))
    (setf (continuation-snapshot continuation) (take-snapshot root))
    (let ((*render-context* (make-instance 'render-context
                                           :callbacks callbacks
                                           :action-url (page-url session continuation)
                                           :halos-p (and (development-p)
                                                         (session-halos-p session))
                                           :ajax-p t)))
      (list 200 (list* :content-type "application/json; charset=utf-8" :cache-control "no-store"
                       *security-headers*)
            (list (let ((*rendering* t))
                    (render-fragments (cl-ppcre:split "\\s+" (or (request-parameter "_lt_update") ""))
                                      root
                                      :value *ajax-result*
                                      :scripts (reverse *ajax-scripts*)
                                      :redirect *redirect*
                                      :toasts (take-toasts session))))))))

(defun call-around-request (app thunk)
  "Call THUNK through APP's AROUND-REQUEST, if it has one."
  (let ((around (application-around-request app)))
    (if around (funcall around thunk) (funcall thunk))))

(defun call-around-actions (session thunk)
  "Call THUNK through SESSION's application's AROUND-ACTIONS, if it has any."
  (let ((around (application-around-actions (session-application session))))
    (if around (funcall around thunk) (funcall thunk))))

(defun run-actions (session continuation)
  "Run the callbacks the request names on CONTINUATION's page.  When any
ran, snapshot the result as a new page, note the timings for the toolbar
and return a redirect to it; otherwise NIL."
  (let ((start (get-internal-real-time))
        (*redirect* nil))
    (when (call-around-actions
           session
           (lambda ()
             (when (process-callbacks (lack/request:request-parameters *request*)
                                      (continuation-callbacks continuation))
               (prepare-tasks (session-root session))
               t)))
      (let* ((acted (get-internal-real-time))
             (page (new-continuation session))
             (done (get-internal-real-time)))
        (setf (session-last-action session)
              (list :actions (/ (- acted start) internal-time-units-per-second)
                    :snapshot (/ (- done acted) internal-time-units-per-second)
                    :objects (length (snapshot-entries (continuation-snapshot page)))))
        (redirect-response (or *redirect* (page-url session page)))))))

(defun handle-session-request (session)
  "Answer a request in SESSION: run the callbacks it names and redirect, or
render the page it names."
  (let ((continuation (find-continuation session (request-parameter "_k"))))
    (cond ((and (null continuation) (request-parameter "_lt_events"))
           ;; A stream for a page that is gone: 204 tells EventSource to stop.
           (list 204 *security-headers* (list "")))
          ((null continuation)
           ;; A page forgotten or never made: show the session as it is now.
           (redirect-response (page-url session (new-continuation session))))
          ((request-parameter "_lt_ajax")
           (handle-ajax session continuation))
          ((request-parameter "_lt_events")
           (handle-events session continuation))
          ((request-parameter "_lt_live")
           ;; A development page asking whether code it shows has changed.
           (let ((version (or (ignore-errors (parse-integer (request-parameter "_lt_live"))) 0)))
             (list 200 (list* :content-type "application/json" :cache-control "no-store" *security-headers*)
                   (list (format nil "{\"reload\":~:[false~;true~]}" (live-check session version))))))
          (t
           (restore-snapshot (continuation-snapshot continuation))
           (or (run-actions session continuation)
               (render-page session continuation))))))

(defun backtrace-string ()
  "The current backtrace, as text."
  (with-output-to-string (out)
    (sb-debug:print-backtrace :stream out :count 40)))

(defun render-standalone (component title &key (status 200))
  "A page showing COMPONENT outside any session.  Its callbacks go nowhere,
so it should use plain links."
  (let ((*render-context* nil))
    (html-response
     (format nil "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>~A</title>~
<link rel=\"stylesheet\" href=\"~A\"></head><body>~A</body></html>"
             (html-escape title) (static-url "littoral.css")
             (with-canvas-to-string () (render component)))
     :status status)))

(defun custom-error-page (app condition)
  "The application's own response to CONDITION, or NIL.  An error inside
the handler falls back to the standard page."
  (let ((handler (application-error-handler app)))
    (when handler
      (ignore-errors
       (let ((result (funcall handler condition)))
         (typecase result
           (component (render-standalone result "Error" :status 500))
           (string (html-response result :status 500))
           (otherwise nil)))))))

(defun call-with-error-page (app thunk)
  "Call THUNK, answering an error with APP's error page unless *DEBUG-ERRORS*."
  (if *debug-errors*
      (funcall thunk)
      (block handled
        (handler-bind ((error (lambda (condition)
                                (return-from handled
                                  (or (and (typep condition 'forbidden)
                                           (simple-page 403 "Forbidden"
                                                        (format nil "<p>~A</p>"
                                                                (html-escape (forbidden-message condition)))))
                                      (custom-error-page app condition)
                                   (if (development-p app)
                                      (simple-page 500 "Internal Server Error"
                                                   (format nil "<p class=\"lt-error\">~A</p><pre>~A</pre>"
                                                           (html-escape condition)
                                                           (html-escape (backtrace-string))))
                                      (simple-page 500 "Internal Server Error")))))))
          (funcall thunk)))))

(defun authorized-p (app)
  "True when APP needs no credentials or the request carries them."
  (let ((credentials (application-credentials app)))
    (or (null credentials)
        (let ((header (gethash "authorization" (lack/request:request-headers *request*))))
          (and header
               (> (length header) 6)
               (string-equal "Basic " header :end2 6)
               (let ((given (ignore-errors (cl-base64:base64-string-to-string (subseq header 6))))
                     (expected (format nil "~A:~A" (first credentials) (rest credentials))))
                 (and given
                      (= (length given) (length expected))
                      (ironclad:constant-time-equal
                       (sb-ext:string-to-octets given :external-format :utf-8)
                       (sb-ext:string-to-octets expected :external-format :utf-8)))))))))

(defun handle-application (app)
  "Answer a request for APP: authorise it, then find or start its session."
  (let ((*application* app))
    (cond
      ((and (application-local-only-p app) (not (local-request-p)))
       (list 403 (list* :content-type "text/plain" *security-headers*)
             (list "This application only answers requests from the machine it runs on.")))
      ((not (authorized-p app))
        (list 401 (list :content-type "text/plain"
                        :www-authenticate (format nil "Basic realm=~S" (application-path app)))
              (list "Authorization required.")))
      (t
       (call-with-error-page
         app
         (lambda ()
          (call-around-request
           app
           (lambda ()
           (let* ((key (session-key-from-request app))
                  (found (find-session app key))
                  ;; Someone else's session, reached by a shared link: start
                  ;; this browser its own instead (no session fixation).
                  (session (and found (browser-matches-p found) found)))
             (cond ((and (null session) (not (allow-new-session-p)))
                    (list 429 (list* :content-type "text/plain" :retry-after "60" *security-headers*)
                          (list "Too many new sessions from this address; try again in a minute.")))
                   ((null session)
                    (start-session app :expired (and key (null found) t)))
                   (t
                    (let ((*session* session))
                      (sb-thread:with-recursive-lock ((session-lock session))
                        (setf (session-last-access session) (now-seconds))
                        (handle-session-request session))))))))))))))

;;; Dispatch

(defun application-for-path (path)
  "The application whose path is PATH or the longest prefix of it."
  (let ((path (normalize-path path)))
    (or (find-application path)
        (loop for app in (sort (list-applications) #'> :key (lambda (a) (length (application-path a))))
              for prefix = (application-path app)
              when (and (> (length path) (length prefix))
                        (string= prefix path :end2 (length prefix))
                        (char= (char path (length prefix)) #\/))
                return app))))

(defun index-page ()
  "A page listing the registered applications."
  (simple-page 200 "Littoral"
               (format nil "<ul>~{~A~}</ul>"
                       (loop for app in (list-applications)
                             collect (format nil "<li><a href=\"~A\">~A</a> — ~A</li>"
                                             (html-escape (application-base-url app))
                                             (html-escape (application-path app))
                                             (html-escape (or (application-title app) "")))))))

(defun oversized-response (env)
  "413 or 411 when ENV's body may not be read, else NIL.  Checked before
the body is touched."
  (let* ((app (application-for-path (or (getf env :path-info) "/")))
         (limit (or (and app (application-max-request-size app)) *max-request-size*))
         (length (getf env :content-length))
         (headers (getf env :headers))
         (chunked (and headers (search "chunked" (or (gethash "transfer-encoding" headers) "")))))
    (cond ((and length (> length limit))
           (list 413 (list* :content-type "text/plain" :connection "close" *security-headers*)
                 (list (format nil "The request is larger than the ~:D bytes allowed." limit))))
          ((and chunked (null length))
           (list 411 (list* :content-type "text/plain" *security-headers*)
                 (list "A request body needs a Content-Length.")))
          (t nil))))

(defun handle-request (env &optional (prefix ""))
  "Answer the Lack request ENV, mounted under PREFIX."
  (or (oversized-response env)
      (handle-sized-request env prefix)))

(defun handle-sized-request (env prefix)
  "Answer the Lack request ENV, whose size has been checked."
  (let* ((*request* (lack/request:make-request env))
         (*base-path* (string-right-trim
                       "/" (concatenate 'string prefix (or (getf env :script-name) ""))))
         (path (or (request-path) "/")))
    (cond ((alexandria:starts-with-subseq "/littoral/files/" path)
           (serve-static (subseq path (length "/littoral/files/"))))
          ((application-for-path path)
           (handle-application (application-for-path path)))
          ((string= path "/") (index-page))
          (t (simple-page 404 "Not Found")))))

(defun make-lack-app (&key (prefix ""))
  "A Lack application serving every registered littoral application.
PREFIX is the path it is mounted under when the mounting middleware does
not set :SCRIPT-NAME (lack's mount middleware does not)."
  (let ((prefix (string-right-trim "/" prefix)))
    (lambda (env) (with-sane-printing () (handle-request env prefix)))))

(defvar *handler* nil)

(defvar *reaper* nil)

(defun reap-all-sessions ()
  "Forget the idle sessions of every application."
  (mapc #'reap-sessions (list-applications)))

(defun start-reaper (&key (interval 60))
  "Reap idle sessions every INTERVAL seconds in a background thread."
  (stop-reaper)
  (setf *reaper*
        (sb-thread:make-thread
         (lambda ()
           (loop (sleep interval)
                 (ignore-errors (reap-all-sessions))))
         :name "littoral session reaper")))

(defun stop-reaper ()
  "Stop the session reaper thread, if it is running."
  (when (and *reaper* (sb-thread:thread-alive-p *reaper*))
    (sb-thread:terminate-thread *reaper*))
  (setf *reaper* nil))

(defun start (&key (port 8080) (address "127.0.0.1") (server :hunchentoot) (prefix "")
                configuration-file (instance-id *instance-id*) (max-threads 100) (workers 4))
  "Serve all registered applications with Clack on PORT, under PREFIX, and
reap idle sessions in the background.  With CONFIGURATION-FILE, first load
the applications saved there; /config then saves its changes to it.
INSTANCE-ID prefixes session keys, for routing several processes.
MAX-THREADS caps Hunchentoot's worker threads; every open page with server
push holds one, so raise it when many pages subscribe.  With SERVER :WOO
(load littoral/woo first) WORKERS event loops serve everything, push included,
without a thread per page."
  (when *handler* (stop))
  (setf *instance-id* instance-id)
  (when configuration-file
    (setf *configuration-file* configuration-file)
    (load-configuration configuration-file))
  (start-reaper)
  (start-live-watcher)
  (unless (member address '("127.0.0.1" "localhost" "::1") :test #'equal)
    (let ((open (remove-if-not #'development-p (list-applications))))
      (when open
        (warn "Littoral: serving ~{~A~^, ~} in development mode on ~A: halos let anyone ~
who can reach them inspect and change component state."
              (mapcar #'application-path open) address))))
  (when (and (eq server :woo) (null *async-stream-opener*))
    (warn "Littoral: serving on Woo without littoral/woo loaded, so every open ~
page with server push ties up a Woo worker.  Load littoral/woo."))
  (setf *handler* (apply #'clack:clackup (make-lack-app :prefix prefix)
                         :server server :port port :address address
                         :use-default-middlewares nil :silent t :debug nil
                         (case server
                           (:hunchentoot (list :max-thread-count max-threads
                                               :max-accept-count (+ max-threads 20)))
                           (:woo (list :worker-num workers))
                           (otherwise '()))))
  (format t "~&Littoral listening on http://~A:~D/~%" address port)
  *handler*)

(defun stop ()
  "Stop serving, close open event streams and stop reaping sessions."
  (stop-reaper)
  (stop-live-watcher)
  (close-event-streams)
  (when *handler*
    (clack:stop *handler*)
    (setf *handler* nil)))
