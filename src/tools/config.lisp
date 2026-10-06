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

(defun find-component-class (name)
  "The component class NAME (\"package::symbol\" or a symbol in CL-USER)
names, or NIL."
  (let ((symbol (ignore-errors
                 (let ((*read-eval* nil) (*package* (find-package :cl-user)))
                   (read-from-string name)))))
    (and symbol (symbolp symbol)
         (let ((class (find-class symbol nil)))
           (and class (subtypep class 'component) symbol)))))

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
              (anchor (:callback (lambda () (show self (make-instance 'application-editor :application app))))
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
                                                (setf (config-message self)
                                                      (format nil "Removed ~A." (application-path app))))))))
                  "remove")))))))
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
   (cookie-sessions-p :accessor editor-cookie-sessions-p)
   (error-message :initform nil :accessor editor-error)))

(defmethod initialize-instance :after ((self application-editor) &key application)
  (setf (editor-title self) (or (application-title application) "")
        (editor-root-class self) (let ((*package* (find-package :keyword)))
                                   (prin1-to-string (application-root-class application)))
        (editor-mode self) (application-mode application)
        (editor-timeout self) (application-session-timeout application)
        (editor-max-continuations self) (application-max-continuations application)
        (editor-cookie-sessions-p self) (application-cookie-sessions-p application)))

(defun save-application (self)
  (let ((app (editor-application self))
        (class (find-component-class (editor-root-class self))))
    (cond ((null class)
           (setf (editor-error self)
                 (format nil "~S does not name a component class." (editor-root-class self))))
          ((not (and (integerp (editor-timeout self)) (plusp (editor-timeout self))
                     (integerp (editor-max-continuations self)) (plusp (editor-max-continuations self))))
           (setf (editor-error self) "Timeout and pages must be positive integers."))
          (t
           (setf (application-title app) (unless (string= (editor-title self) "") (editor-title self))
                 (application-root-class app) class
                 (application-mode app) (editor-mode self)
                 (application-session-timeout app) (editor-timeout self)
                 (application-max-continuations app) (editor-max-continuations self)
                 (application-cookie-sessions-p app) (editor-cookie-sessions-p self))
           (answer self t)))))

(defmethod render ((self application-editor))
  (div (:class "lt-application-editor")
    (h2 () "Configure " (text (application-path (editor-application self))))
    (when (editor-error self)
      (p (:class "lt-validation-error") (text (editor-error self))))
    (form ()
      (table (:class "lt-table")
        (tr () (th () "Title")
          (td () (text-input (:id "title" :value (editor-title self)
                              :callback (lambda (v) (setf (editor-title self) v))))))
        (tr () (th () "Root class")
          (td () (text-input (:id "root-class" :value (editor-root-class self)
                              :callback (lambda (v) (setf (editor-root-class self) v))))))
        (tr () (th () "Mode")
          (td () (select-list (:id "mode" :items '(:development :deployment)
                               :labels #'string-downcase
                               :selected (editor-mode self)
                               :callback (lambda (v) (when v (setf (editor-mode self) v)))))))
        (tr () (th () "Session timeout (s)")
          (td () (number-input (:id "timeout" :value (editor-timeout self)
                                :callback (lambda (v) (setf (editor-timeout self) v))))))
        (tr () (th () "Pages kept per session")
          (td () (number-input (:id "max-continuations" :value (editor-max-continuations self)
                                :callback (lambda (v) (setf (editor-max-continuations self) v))))))
        (tr () (th () "Session in cookie")
          (td () (checkbox (:id "cookie-sessions" :value (editor-cookie-sessions-p self)
                            :callback (lambda (v) (setf (editor-cookie-sessions-p self) v)))))))
      (div (:class "lt-buttons")
        (submit-button (:callback (lambda () (save-application self))) "Save")
        (submit-button (:callback (lambda () (answer self nil))) "Cancel")))))

;;; Registration

(defun configure-admin (&key user password (path "/config"))
  "Serve the configuration application at PATH, behind HTTP basic auth
when USER and PASSWORD are given."
  (register-application path 'config-root
                        :title "Littoral Configuration"
                        :mode :deployment
                        :credentials (when (and user password) (cons user password))))

(configure-admin)
