;;;; app.lisp — the application's root component

(in-package #:{{name}})

(defclass front-page (component)
  ((clicks :initform 0 :accessor clicks)
   (visitor :initform nil :accessor visitor))
  (:documentation "The root of {{title}}: a counter and a greeting."))

(defmethod states ((self front-page))
  ;; Snapshot this component's slots, so the back button brings back
  ;; earlier counts.
  (list self))

(defmethod render ((self front-page))
  (h1 () "{{title}}")
  (p () "Count: " (strong (:id "count") (text (clicks self))))
  (p ()
    (anchor (:callback (lambda () (incf (clicks self)))) "Add one")
    " · "
    (anchor (:callback (lambda () (decf (clicks self)))) "Take one away")
    " · "
    (anchor (:callback (lambda () (reset-clicks self))) "Reset"))
  (form ()
    (label (:for "visitor") "Your name ")
    (text-input (:id "visitor" :value (or (visitor self) "")
                 :callback (lambda (value) (setf (visitor self) (string-trim " " value)))))
    (submit-button () "Greet"))
  (when (and (visitor self) (plusp (length (visitor self))))
    (p (:class "greeting") (text (format nil "Hello, ~A!" (visitor self))))))

(defun reset-clicks (self)
  "Ask before setting the count back to zero.  SHOW puts the dialog in
SELF's place until it answers; the answer arrives in :ON-ANSWER."
  (show self (make-instance 'confirm-dialog :message "Set the count back to zero?")
        :on-answer (lambda (yes) (when yes (setf (clicks self) 0)))))

;;; Serving

(defun register-app (&key (path "/") (mode :development))
  "Serve the application at PATH.  :DEVELOPMENT adds the toolbar and halos."
  (register-application path 'front-page :title "{{title}}" :mode mode))

(defun serve (&key (port {{port}}) (address "127.0.0.1") (mode :development))
  "Register the application and start the web server."
  (register-app :mode mode)
  (start :port port :address address))

(defun toplevel ()
  "The entry point of the executable `make build` writes: serves in
deployment mode on $PORT (default {{port}}) and $ADDRESS until killed."
  (serve :port (parse-integer (or (uiop:getenv "PORT") "{{port}}"))
         :address (or (uiop:getenv "ADDRESS") "127.0.0.1")
         :mode :deployment)
  (loop (sleep 3600)))
