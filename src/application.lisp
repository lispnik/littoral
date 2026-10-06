;;;; application.lisp — a root component class served at a path

(in-package #:littoral)

(defclass application ()
  ((path :initarg :path :accessor application-path)
   (root-class :initarg :root-class :accessor application-root-class)
   (title :initarg :title :initform nil :accessor application-title)
   (mode :initarg :mode :initform :development :accessor application-mode
         :type (member :development :deployment)
         :documentation ":DEVELOPMENT adds the toolbar and halos.")
   (session-timeout :initarg :session-timeout :initform 1800
                    :accessor application-session-timeout
                    :documentation "Seconds a session may sit idle.")
   (max-continuations :initarg :max-continuations :initform 50
                      :accessor application-max-continuations
                      :documentation "Pages per session the back button can reach.")
   (cookie-sessions-p :initarg :cookie-sessions :initform nil
                      :accessor application-cookie-sessions-p
                      :documentation "Track the session in a cookie instead of the URL.")
   (stylesheets :initarg :stylesheets :initform '() :accessor application-stylesheets)
   (scripts :initarg :scripts :initform '() :accessor application-scripts)
   (credentials :initarg :credentials :initform nil :accessor application-credentials
                :documentation "(USER . PASSWORD) required by HTTP basic auth, or NIL.")
   (sessions :initform (make-hash-table :test 'equal) :reader application-sessions)
   (lock :initform (sb-thread:make-mutex :name "littoral application") :reader application-lock)))

(defmethod print-object ((app application) stream)
  (print-unreadable-object (app stream :type t)
    (format stream "~A ~S" (application-path app) (application-root-class app))))

(defvar *applications* (make-hash-table :test 'equal)
  "Path → APPLICATION.")

(defvar *applications-lock* (sb-thread:make-mutex :name "littoral applications"))

(defun normalize-path (path)
  (let ((path (string-right-trim "/" (if (char= (char path 0) #\/) path (concatenate 'string "/" path)))))
    (if (string= path "") "/" path)))

(defun register-application (path root-class &rest initargs
                             &key title mode session-timeout max-continuations
                               cookie-sessions stylesheets scripts credentials)
  "Serve ROOT-CLASS, a component class, at PATH.  Replaces any application
already there.  Returns the APPLICATION."
  (declare (ignore title mode session-timeout max-continuations cookie-sessions
                   stylesheets scripts credentials))
  (let* ((path (normalize-path path))
         (app (apply #'make-instance 'application :path path :root-class root-class initargs)))
    (sb-thread:with-mutex (*applications-lock*)
      (setf (gethash path *applications*) app))
    app))

(defun unregister-application (path)
  (sb-thread:with-mutex (*applications-lock*)
    (remhash (normalize-path path) *applications*)))

(defun find-application (path)
  (gethash (normalize-path path) *applications*))

(defun list-applications ()
  (sort (sb-thread:with-mutex (*applications-lock*)
          (alexandria:hash-table-values *applications*))
        #'string< :key #'application-path))

(defun application-base-url (app)
  "The URL that starts a new session of APP."
  (url-for (application-path app)))

;;; Sessions

(defun create-session (app)
  (let* ((root (make-instance (application-root-class app)))
         (session (make-instance 'session :application app :root root)))
    (reap-sessions app)
    (sb-thread:with-mutex ((application-lock app))
      (setf (gethash (session-key session) (application-sessions app)) session))
    session))

(defun find-session (app key)
  (when key
    (let ((session (sb-thread:with-mutex ((application-lock app))
                     (gethash key (application-sessions app)))))
      (cond ((null session) nil)
            ((session-expired-p session) (expire-session session) nil)
            (t session)))))

(defun expire-session (session)
  (let ((app (session-application session)))
    (sb-thread:with-mutex ((application-lock app))
      (remhash (session-key session) (application-sessions app)))))

(defun reap-sessions (app)
  "Forget APP's idle sessions."
  (let ((now (now-seconds)))
    (sb-thread:with-mutex ((application-lock app))
      (loop for key being the hash-keys of (application-sessions app) using (hash-value session)
            when (session-expired-p session now)
              do (remhash key (application-sessions app))))))

(defun list-sessions (app)
  (sort (sb-thread:with-mutex ((application-lock app))
          (alexandria:hash-table-values (application-sessions app)))
        #'> :key #'session-last-access))

(defun session-cookie-name (app)
  "The cookie that carries APP's session key when it uses cookie sessions."
  (format nil "_s~A" (substitute #\_ #\/ (application-path app))))
