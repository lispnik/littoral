;;;; config.lisp — /config, the application that configures applications

(in-package #:littoral)

(defclass config-root (tool)
  ((new-path :initform "" :accessor new-path)
   (new-class :initform "" :accessor new-class)
   (new-title :initform "" :accessor new-title)
   (message :initform nil :accessor config-message)))

(defmethod update-root ((self config-root) root)
  (call-next-method)
  (setf (root-title root) "Littoral Configuration"))

(defun add-application (self)
  (let ((class (find-component-class (new-class self)))
        (path (string-trim " " (new-path self))))
    (cond ((string= path "")
           (setf (config-message self) "The path is required."))
          ((null class)
           (setf (config-message self)
                 (format nil "~S does not name a component class." (new-class self))))
          ((find-application path)
           (setf (config-message self) (format nil "~A is already registered." path)))
          (t
           (register-application path class
                                 :title (unless (string= (new-title self) "") (new-title self)))
           (save-configuration)
           (setf (config-message self) (format nil "Registered ~A." (normalize-path path))
                 (new-path self) "" (new-class self) "" (new-title self) "")))))

(defmethod render ((self config-root))
  (div (:class "lt-config")
    (h1 () "Littoral Configuration")
    (when (config-message self)
      (p (:class "lt-message") (text (config-message self))))
    (h2 () "Applications")
    (table (:class "lt-table")
      (tr () (th () "Path") (th () "Title") (th () "Root class") (th () "Mode")
        (th () "Sessions") (th ()))
      (dolist (app (list-applications))
        (let ((app app))
          (tr ()
            (td () (anchor (:href (application-base-url app)) (text (application-path app))))
            (td () (text (or (application-title app) "")))
            (td () (code () (text (prin1-to-string (application-root-class app)))))
            (td () (text (string-downcase (application-mode app))))
            (td () (text (hash-table-count (application-sessions app))))
            (td ()
              (anchor (:callback (lambda ()
                                   (show self (make-instance 'application-editor :application app)
                                         :on-answer (lambda (saved)
                                                      (when saved
                                                        (save-configuration)
                                                        (setf (config-message self)
                                                              (format nil "Saved ~A." (application-path app))))))))
                "configure")
              " "
              (anchor (:callback (lambda () (show self (make-instance 'session-browser :application app))))
                "sessions")
              " "
              (unless (eq app *application*)
                (anchor (:callback
                         (lambda ()
                           (show self (make-instance 'confirm-dialog
                                                     :message (format nil "Remove ~A?" (application-path app)))
                                 :on-answer (lambda (yes)
                                              (when yes
                                                (unregister-application (application-path app))
                                                (save-configuration)
                                                (setf (config-message self)
                                                      (format nil "Removed ~A." (application-path app))))))))
                  "remove")))))))
    (p (:class "lt-config-file")
      (if *configuration-file*
          (progn (text "Changes are saved to ") (code () (text (namestring *configuration-file*))) (text "."))
          (text "Changes last until the image exits: start with :configuration-file to keep them.")))
    (h2 () "Add an application")
    (form (:class "lt-add-application")
      (label () "Path "
        (text-input (:id "new-path" :value (new-path self) :placeholder "/my-app"
                     :callback (lambda (v) (setf (new-path self) v)))))
      (label () "Root class "
        (text-input (:id "new-class" :value (new-class self) :placeholder "my-package::my-root"
                     :callback (lambda (v) (setf (new-class self) v)))))
      (label () "Title "
        (text-input (:id "new-title" :value (new-title self)
                     :callback (lambda (v) (setf (new-title self) v)))))
      (submit-button (:callback (lambda () (add-application self))) "Add"))))

;;; Editing one application

(defclass application-editor (tool)
  ((application :initarg :application :reader editor-application)
   (title :accessor editor-title)
   (root-class :accessor editor-root-class)
   (mode :accessor editor-mode)
   (timeout :accessor editor-timeout)
   (max-continuations :accessor editor-max-continuations)
   (max-sessions :accessor editor-max-sessions)
   (cookie-sessions-p :accessor editor-cookie-sessions-p)
   (expired-notice-p :accessor editor-expired-notice-p)
   (stylesheets :accessor editor-stylesheets)
   (scripts :accessor editor-scripts)
   (user :accessor editor-user)
   (password :accessor editor-password)
   (error-message :initform nil :accessor editor-error)))

(defun lines (string)
  "The non-blank lines of STRING, trimmed."
  (remove "" (mapcar (lambda (line) (string-trim '(#\Space #\Tab #\Return) line))
                     (cl-ppcre:split "\\n" string))
          :test #'string=))

(defmethod initialize-instance :after ((self application-editor) &key application)
  (let ((credentials (application-credentials application)))
    (setf (editor-title self) (or (application-title application) "")
          (editor-root-class self) (class-designator (application-root-class application))
          (editor-mode self) (application-mode application)
          (editor-timeout self) (application-session-timeout application)
          (editor-max-continuations self) (application-max-continuations application)
          (editor-max-sessions self) (application-max-sessions application)
          (editor-cookie-sessions-p self) (application-cookie-sessions-p application)
          (editor-expired-notice-p self) (and (application-expired-notice application) t)
          (editor-stylesheets self) (format nil "~{~A~%~}" (application-stylesheets application))
          (editor-scripts self) (format nil "~{~A~%~}" (application-scripts application))
          (editor-user self) (or (car credentials) "")
          (editor-password self) (or (cdr credentials) ""))))

(defun positive-integer-p (n) (and (integerp n) (plusp n)))

(defun save-application (self)
  (let ((app (editor-application self))
        (class (find-component-class (editor-root-class self))))
    (cond ((null class)
           (setf (editor-error self)
                 (format nil "~S does not name a component class." (editor-root-class self))))
          ((not (and (positive-integer-p (editor-timeout self))
                     (positive-integer-p (editor-max-continuations self))))
           (setf (editor-error self) "Timeout and pages must be positive integers."))
          ((and (editor-max-sessions self) (not (positive-integer-p (editor-max-sessions self))))
           (setf (editor-error self) "The session limit must be a positive integer, or blank."))
          ((and (string= (editor-user self) "") (string/= (editor-password self) ""))
           (setf (editor-error self) "A password needs a user name."))
          (t
           (configure-application
            (application-path app)
            :title (unless (string= (editor-title self) "") (editor-title self))
            :root-class class
            :mode (editor-mode self)
            :session-timeout (editor-timeout self)
            :max-continuations (editor-max-continuations self)
            :max-sessions (editor-max-sessions self)
            :cookie-sessions (editor-cookie-sessions-p self)
            :expired-notice (cond ((not (editor-expired-notice-p self)) nil)
                                  ((application-expired-notice app))
                                  (t 'session-expired-notice))
            :stylesheets (lines (editor-stylesheets self))
            :scripts (lines (editor-scripts self))
            :credentials (unless (string= (editor-user self) "")
                           (cons (editor-user self) (editor-password self))))
           (answer self t)))))

(defmacro editor-row (label &body field)
  `(tr () (th () ,label) (td () ,@field)))

(defmethod render ((self application-editor))
  (div (:class "lt-application-editor")
    (h2 () "Configure " (text (application-path (editor-application self))))
    (when (editor-error self)
      (p (:class "lt-validation-error") (text (editor-error self))))
    (form ()
      (table (:class "lt-table")
        (editor-row "Title"
          (text-input (:id "title" :value (editor-title self)
                       :callback (lambda (v) (setf (editor-title self) v)))))
        (editor-row "Root class"
          (text-input (:id "root-class" :value (editor-root-class self) :size 40
                       :callback (lambda (v) (setf (editor-root-class self) v)))))
        (editor-row "Mode"
          (select-list (:id "mode" :items '(:development :deployment)
                        :labels #'string-downcase
                        :selected (editor-mode self)
                        :callback (lambda (v) (when v (setf (editor-mode self) v))))))
        (editor-row "Session timeout (s)"
          (number-input (:id "timeout" :value (editor-timeout self)
                         :callback (lambda (v) (setf (editor-timeout self) v)))))
        (editor-row "Pages kept per session"
          (number-input (:id "max-continuations" :value (editor-max-continuations self)
                         :callback (lambda (v) (setf (editor-max-continuations self) v)))))
        (editor-row "Most sessions (blank: no limit)"
          (number-input (:id "max-sessions" :value (editor-max-sessions self)
                         :callback (lambda (v) (setf (editor-max-sessions self) v)))))
        (editor-row "Session in cookie"
          (checkbox (:id "cookie-sessions" :value (editor-cookie-sessions-p self)
                     :callback (lambda (v) (setf (editor-cookie-sessions-p self) v)))))
        (editor-row "Say when a session expired"
          (checkbox (:id "expired-notice" :value (editor-expired-notice-p self)
                     :callback (lambda (v) (setf (editor-expired-notice-p self) v)))))
        (editor-row "Stylesheets (one URL a line)"
          (text-area (:id "stylesheets" :rows 3 :cols 50 :value (editor-stylesheets self)
                      :callback (lambda (v) (setf (editor-stylesheets self) v)))))
        (editor-row "Scripts (one URL a line)"
          (text-area (:id "scripts" :rows 3 :cols 50 :value (editor-scripts self)
                      :callback (lambda (v) (setf (editor-scripts self) v)))))
        (editor-row "Basic auth user (blank: none)"
          (text-input (:id "user" :value (editor-user self) :autocomplete "off"
                       :callback (lambda (v) (setf (editor-user self) v)))))
        (editor-row "Basic auth password"
          (password-input (:id "password" :value (editor-password self) :autocomplete "new-password"
                           :callback (lambda (v) (setf (editor-password self) v))))))
      (div (:class "lt-buttons")
        (submit-button (:callback (lambda () (save-application self))) "Save")
        (cancel-button (:callback (lambda () (answer self nil))) "Cancel")))))

;;; Registration

(defun configure-admin (&key user password (path "/config"))
  "Serve the configuration application at PATH.  With USER and PASSWORD it
is behind HTTP basic auth; without, it answers only requests from this
machine."
  (let ((credentials (when (and user password) (cons user password))))
    (register-application path 'config-root
                          :title "Littoral Configuration"
                          :mode :deployment
                          :credentials credentials
                          :local-only (null credentials))))

(configure-admin)
