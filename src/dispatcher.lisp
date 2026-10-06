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

(defun html-response (html &key (status 200) headers)
  (list status
        (list* :content-type "text/html; charset=utf-8"
               :cache-control "no-store"
               headers)
        (list html)))

(defun redirect-response (url &key headers)
  (list 302 (list* :location url :cache-control "no-store" headers) (list "")))

(defun simple-page (status title &optional (message ""))
  (html-response
   (format nil "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>~A</title>~
<link rel=\"stylesheet\" href=\"~A\"></head><body><h1>~A</h1>~A</body></html>"
           (html-escape title) (static-url "littoral.css") (html-escape title) message)
   :status status))

(defun serve-static (name)
  (let ((type (cdr (assoc (pathname-type (pathname name)) *static-types* :test #'equal))))
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
  (eq (application-mode app) :development))

(defun render-document (session body-html action-url)
  (let ((app (session-application session))
        (root (make-instance 'html-root)))
    (setf (root-title root) (or (application-title app) (application-path app)))
    (map-visible (lambda (c) (update-root c root)) (session-root session))
    (with-output-to-string (out)
      (format out "<!DOCTYPE html>~%<html><head><meta charset=\"utf-8\">~
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">~
<title>~A</title>~%" (html-escape (root-title root)))
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
      (format out "</head>~%<body data-lt-action=\"~A\">~%" (html-escape action-url))
      (write-string body-html out)
      (when (root-inline-scripts root)
        (format out "~%<script>~%~{~A~%~}</script>" (reverse (root-inline-scripts root))))
      (format out "~%</body></html>~%"))))

(defun render-page (session continuation)
  (let* ((app (session-application session))
         (callbacks (continuation-callbacks continuation))
         (action-url (page-url session continuation))
         (start (get-internal-real-time)))
    (clear-callbacks callbacks)
    (let* ((*render-context* (make-instance 'render-context
                                            :callbacks callbacks
                                            :action-url action-url
                                            :halos-p (and (development-p app)
                                                          (session-halos-p session))))
           (body (with-canvas-to-string ()
                   (let ((*rendering* t))
                     (render-component (session-root session)))
                   (when (development-p app)
                     (render-toolbar session start)))))
      (html-response (render-document session body action-url)))))

;;; The cycle

(defun session-key-from-request (app)
  (if (application-cookie-sessions-p app)
      (cdr (assoc (session-cookie-name app) (lack/request:request-cookies *request*)
                  :test #'string=))
      (request-parameter "_s")))

(defun start-session (app)
  (let* ((session (create-session app))
         (*session* session))
    (sb-thread:with-recursive-lock ((session-lock session))
      (let ((root (session-root session)))
        (initial-request root *request*)
        (prepare-tasks root))
      (redirect-response (page-url session (new-continuation session))
                         :headers (when (application-cookie-sessions-p app)
                                    (list :set-cookie
                                          (format nil "~A=~A; Path=~A; HttpOnly; SameSite=Lax"
                                                  (session-cookie-name app)
                                                  (session-key session)
                                                  (application-base-url app))))))))

(defun handle-ajax (session continuation)
  (let* ((root (session-root session))
         (callbacks (continuation-callbacks continuation)))
    (process-callbacks (lack/request:request-parameters *request*) callbacks)
    (prepare-tasks root)
    (setf (continuation-snapshot continuation) (take-snapshot root))
    (let ((*render-context* (make-instance 'render-context
                                           :callbacks callbacks
                                           :action-url (page-url session continuation)
                                           :halos-p (and (development-p)
                                                         (session-halos-p session))
                                           :ajax-p t)))
      (list 200 (list :content-type "application/json; charset=utf-8" :cache-control "no-store")
            (list (let ((*rendering* t))
                    (render-fragments (cl-ppcre:split "\\s+" (or (request-parameter "_lt_update") ""))
                                      root)))))))

(defun handle-session-request (session)
  (let* ((root (session-root session))
         (continuation (find-continuation session (request-parameter "_k"))))
    (cond ((null continuation)
           ;; A page forgotten or never made: show the session as it is now.
           (redirect-response (page-url session (new-continuation session))))
          ((request-parameter "_lt_ajax")
           (handle-ajax session continuation))
          (t
           (restore-snapshot (continuation-snapshot continuation))
           (cond ((process-callbacks (lack/request:request-parameters *request*)
                                     (continuation-callbacks continuation))
                  (prepare-tasks root)
                  (redirect-response (page-url session (new-continuation session))))
                 (t
                  (render-page session continuation)))))))

(defun backtrace-string ()
  (with-output-to-string (out)
    (sb-debug:print-backtrace :stream out :count 40)))

(defun call-with-error-page (app thunk)
  (if *debug-errors*
      (funcall thunk)
      (block handled
        (handler-bind ((error (lambda (condition)
                                (return-from handled
                                  (if (development-p app)
                                      (simple-page 500 "Internal Server Error"
                                                   (format nil "<p class=\"lt-error\">~A</p><pre>~A</pre>"
                                                           (html-escape condition)
                                                           (html-escape (backtrace-string))))
                                      (simple-page 500 "Internal Server Error"))))))
          (funcall thunk)))))

(defun authorized-p (app)
  (let ((credentials (application-credentials app)))
    (or (null credentials)
        (let ((header (gethash "authorization" (lack/request:request-headers *request*))))
          (and header
               (> (length header) 6)
               (string-equal "Basic " header :end2 6)
               (string= (ignore-errors (cl-base64:base64-string-to-string (subseq header 6)))
                        (format nil "~A:~A" (car credentials) (cdr credentials))))))))

(defun handle-application (app)
  (let ((*application* app))
    (if (not (authorized-p app))
        (list 401 (list :content-type "text/plain"
                        :www-authenticate (format nil "Basic realm=~S" (application-path app)))
              (list "Authorization required."))
        (call-with-error-page
         app
         (lambda ()
           (let ((session (find-session app (session-key-from-request app))))
             (if (null session)
                 (start-session app)
                 (let ((*session* session))
                   (sb-thread:with-recursive-lock ((session-lock session))
                     (setf (session-last-access session) (now-seconds))
                     (handle-session-request session))))))))))

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
  (simple-page 200 "Littoral"
               (format nil "<ul>~{~A~}</ul>"
                       (loop for app in (list-applications)
                             collect (format nil "<li><a href=\"~A\">~A</a> — ~A</li>"
                                             (html-escape (application-base-url app))
                                             (html-escape (application-path app))
                                             (html-escape (or (application-title app) "")))))))

(defun handle-request (env &optional (prefix ""))
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
    (lambda (env) (handle-request env prefix))))

(defvar *handler* nil)

(defun start (&key (port 8080) (address "127.0.0.1") (server :hunchentoot) (prefix ""))
  "Serve all registered applications with Clack on PORT, under PREFIX."
  (when *handler* (stop))
  (setf *handler* (clack:clackup (make-lack-app :prefix prefix)
                                 :server server :port port :address address
                                 :use-default-middlewares nil :silent t :debug nil))
  (format t "~&Littoral listening on http://~A:~D/~%" address port)
  *handler*)

(defun stop ()
  (when *handler*
    (clack:stop *handler*)
    (setf *handler* nil)))
