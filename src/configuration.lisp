;;;; configuration.lisp — applications saved to a file and read back
;;;;
;;;; The file holds one plist per application, in plain Lisp:
;;;;
;;;;   (:path "/shop" :root-class "SHOP::STOREFRONT" :title "Shop"
;;;;    :mode :deployment :session-timeout 1800 …)
;;;;
;;;; Classes are written as strings, so a file naming a system that is not
;;;; loaded still reads; such applications are skipped with a warning.
;;;; Error handlers are functions and are not saved.

(in-package #:littoral)

(defvar *configuration-file* nil
  "Where SAVE-CONFIGURATION writes, and the /config application saves after
each change.  Set by START's :CONFIGURATION-FILE.")

(defun class-designator (symbol)
  "SYMBOL as \"PACKAGE::NAME\", or NIL."
  (when symbol
    (let ((*package* (find-package :keyword)))
      (prin1-to-string symbol))))

(defun find-component-class (name)
  "The component class NAME (\"package::symbol\", or a symbol in CL-USER)
names, or NIL."
  (let ((symbol (ignore-errors
                 (let ((*read-eval* nil) (*package* (find-package :cl-user)))
                   (read-from-string name)))))
    (and symbol (symbolp symbol)
         (let ((class (find-class symbol nil)))
           (and class (subtypep class 'component) symbol)))))

(defun application-settings (app)
  "APP's configuration as a plist, as SAVE-CONFIGURATION writes it."
  (list :path (application-path app)
        :root-class (class-designator (application-root-class app))
        :title (application-title app)
        :language (application-language app)
        :languages (application-languages app)
        :mode (application-mode app)
        :session-timeout (application-session-timeout app)
        :max-continuations (application-max-continuations app)
        :cookie-sessions (application-cookie-sessions-p app)
        :stylesheets (application-stylesheets app)
        :scripts (application-scripts app)
        :credentials (application-credentials app)
        :max-sessions (application-max-sessions app)
        :expired-notice (class-designator (application-expired-notice app))))

(defun configure-application (path &rest settings
                              &key root-class title language languages mode session-timeout max-continuations
                                cookie-sessions stylesheets scripts credentials max-sessions
                                expired-notice)
  "Change the settings given for the application at PATH, registering it
when there is none.  Sessions, and settings not given, are kept."
  (declare (ignore root-class title language languages mode session-timeout max-continuations cookie-sessions
                   stylesheets scripts credentials max-sessions expired-notice))
  (let ((app (find-application path)))
    (if (null app)
        (apply #'register-application path (getf settings :root-class)
               (alexandria:remove-from-plist settings :root-class))
        (loop for (key value) on settings by #'cddr
              do (ecase key
                   (:root-class (setf (application-root-class app) value))
                   (:title (setf (application-title app) value))
                   (:language (setf (application-language app) value))
                   (:languages (setf (application-languages app) value))
                   (:mode (setf (application-mode app) value))
                   (:session-timeout (setf (application-session-timeout app) value))
                   (:max-continuations (setf (application-max-continuations app) value))
                   (:cookie-sessions (setf (application-cookie-sessions-p app) value))
                   (:stylesheets (setf (application-stylesheets app) value))
                   (:scripts (setf (application-scripts app) value))
                   (:credentials (setf (application-credentials app) value))
                   (:max-sessions (setf (application-max-sessions app) value))
                   (:expired-notice (setf (application-expired-notice app) value)))
              finally (return app)))))

(defun save-configuration (&optional (file *configuration-file*))
  "Write every registered application's settings to FILE, readable only by
its owner since it may hold credentials.  Returns FILE, or NIL when there
is none."
  (when file
    (let ((temporary (format nil "~A.tmp" (namestring file))))
      (with-open-file (out temporary :direction :output :if-exists :supersede
                                     :external-format :utf-8)
        (sb-posix:chmod temporary #o600)
        (with-standard-io-syntax
          (let ((*package* (find-package :keyword))
                (*print-readably* nil))
            (format out ";;;; Littoral configuration, written by littoral:save-configuration.~%")
            (dolist (app (list-applications))
              (terpri out)
              (prin1 (application-settings app) out)
              (terpri out)))))
      (rename-file temporary (merge-pathnames file))
      file)))

(defun read-configuration (file)
  "The settings plists in FILE."
  (with-open-file (in file :external-format :utf-8)
    (with-standard-io-syntax
      (let ((*package* (find-package :keyword))
            (*read-eval* nil))
        (loop for form = (read in nil in)
              until (eq form in)
              collect form)))))

(defun load-configuration (&optional (file *configuration-file*))
  "Configure applications from FILE.  Applications whose classes are not
loaded are skipped with a warning.  Returns the applications configured."
  (when (and file (probe-file file))
    (loop for settings in (read-configuration file)
          for path = (getf settings :path)
          for root = (find-component-class (or (getf settings :root-class) ""))
          for notice = (and (getf settings :expired-notice)
                            (find-component-class (getf settings :expired-notice)))
          if (null root)
            do (warn "Littoral configuration: skipping ~A, ~A is not a loaded component class."
                     path (getf settings :root-class))
          else
            collect (apply #'configure-application path
                           :root-class root
                           :expired-notice notice
                           (alexandria:remove-from-plist settings :path :root-class :expired-notice)))))
