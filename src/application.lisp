;;;; application.lisp — a root component class served at a path

(in-package #:littoral)

(defclass application ()
  ((path :initarg :path :accessor application-path)
   (root-class :initarg :root-class :accessor application-root-class)
   (title :initarg :title :initform nil :accessor application-title)
   (language :initarg :language :initform "en" :accessor application-language
             :documentation "The page's language, for the html lang attribute.")
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
   (max-sessions :initarg :max-sessions :initform nil :accessor application-max-sessions
                 :documentation "Most live sessions; the least recently used go first.  NIL for no limit.")
   (error-handler :initarg :error-handler :initform nil :accessor application-error-handler
                  :documentation "Function of a condition returning a component or an HTML
string for the error page, or NIL for the standard one.")
   (max-request-size :initarg :max-request-size :initform nil :accessor application-max-request-size
                     :documentation "Largest request body in bytes, or NIL for *MAX-REQUEST-SIZE*.")
   (around-actions :initarg :around-actions :initform nil :accessor application-around-actions
                   :documentation "A function called with a thunk that runs a request's
callbacks, or NIL.  littoral/db uses it to run them in a transaction.")
   (local-only-p :initarg :local-only :initform nil :accessor application-local-only-p
                 :documentation "Answer only requests from this machine.")
   (expired-notice :initarg :expired-notice :initform nil :accessor application-expired-notice
                   :documentation "Component class shown, before the root, to someone whose
session expired.  NIL starts them over silently.")
   (sessions :initform (make-hash-table :test 'equal) :reader application-sessions)
   (lock :initform (sb-thread:make-mutex :name "littoral application") :reader application-lock))
  (:documentation "A root component class served at a path, with its settings and live sessions."))

(defmethod print-object ((app application) stream)
  (print-unreadable-object (app stream :type t)
    (format stream "~A ~S" (application-path app) (application-root-class app))))

(defvar *applications* (make-hash-table :test 'equal)
  "Path → APPLICATION.")

(defvar *applications-lock* (sb-thread:make-mutex :name "littoral applications"))

(defun normalize-path (path)
  "PATH with a leading slash and no trailing one; \"/\" for the root."
  (let ((path (string-right-trim "/" (if (char= (char path 0) #\/) path (concatenate 'string "/" path)))))
    (if (string= path "") "/" path)))

(defun register-application (path root-class &rest initargs
                             &key title mode session-timeout max-continuations
                               cookie-sessions stylesheets scripts credentials
                               max-sessions error-handler expired-notice
                               max-request-size local-only language around-actions)
  "Serve ROOT-CLASS, a component class, at PATH.  Replaces any application
already there.  Returns the APPLICATION."
  (declare (ignore title mode session-timeout max-continuations cookie-sessions
                   stylesheets scripts credentials max-sessions error-handler expired-notice
                   max-request-size local-only language around-actions))
  (let* ((path (normalize-path path))
         (app (apply #'make-instance 'application :path path :root-class root-class initargs)))
    (sb-thread:with-mutex (*applications-lock*)
      (setf (gethash path *applications*) app))
    app))

(defun unregister-application (path)
  "Stop serving the application at PATH."
  (sb-thread:with-mutex (*applications-lock*)
    (remhash (normalize-path path) *applications*)))

(defun find-application (path)
  "The application registered at exactly PATH, or NIL."
  (gethash (normalize-path path) *applications*))

(defun list-applications ()
  "All registered applications, sorted by path."
  (sort (sb-thread:with-mutex (*applications-lock*)
          (alexandria:hash-table-values *applications*))
        #'string< :key #'application-path))

(defun application-base-url (app)
  "The URL that starts a new session of APP."
  (url-for (application-path app)))

;;; Sessions

(defun create-session (app)
  "A new session of APP with a fresh root component, evicting the least recently used session when APP has a limit."
  (let* ((root (make-instance (application-root-class app)))
         (session (make-instance 'session :application app :root root)))
    (reap-sessions app)
    (sb-thread:with-mutex ((application-lock app))
      (let ((limit (application-max-sessions app))
            (sessions (application-sessions app)))
        (when limit
          ;; Evict the least recently used to make room.
          (loop while (>= (hash-table-count sessions) (max limit 1))
                do (let ((oldest (loop with best = nil
                                       for s being the hash-values of sessions
                                       when (or (null best) (< (session-last-access s)
                                                               (session-last-access best)))
                                         do (setf best s)
                                       finally (return best))))
                     (remhash (session-key oldest) sessions))))
        (setf (gethash (session-key session) sessions) session)))
    session))

(defun find-session (app key)
  "APP's live session with KEY, or NIL; an expired one is forgotten on the way."
  (when key
    (let ((session (sb-thread:with-mutex ((application-lock app))
                     (gethash key (application-sessions app)))))
      (cond ((null session) nil)
            ((session-expired-p session) (expire-session session) nil)
            (t session)))))

(defun expire-session (session)
  "Forget SESSION at once."
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
  "APP's sessions, most recently used first."
  (sort (sb-thread:with-mutex ((application-lock app))
          (alexandria:hash-table-values (application-sessions app)))
        #'> :key #'session-last-access))

(defun session-cookie-name (app)
  "The cookie that carries APP's session key when it uses cookie sessions."
  (format nil "_s~A" (substitute #\_ #\/ (application-path app))))
