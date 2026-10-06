;;;; halos.lisp — development tools: toolbar, halos, inspector, sessions
;;;;
;;;; In :DEVELOPMENT mode every page ends with a toolbar.  Turning halos on
;;;; frames each component with its class and buttons to inspect it or to
;;;; see the HTML it renders.

(in-package #:littoral)

(defclass tool (component) ()
  (:documentation "Components of the tools themselves, which get no halo."))

;;; Halos

(defun source-view-p (component)
  (and *session* (member (component-id component) (session-source-views *session*)
                         :test #'string=)))

(defun toggle-source-view (component)
  (let ((id (component-id component)))
    (setf (session-source-views *session*)
          (if (member id (session-source-views *session*) :test #'string=)
              (remove id (session-source-views *session*) :test #'string=)
              (cons id (session-source-views *session*))))))

(defmethod render-component :around ((component component))
  (if (and *render-context* (render-halos-p *render-context*) (not (typep component 'tool)))
      (render-halo component #'call-next-method)
      (call-next-method)))

(defun render-halo (component render)
  (div (:class "lt-halo")
    (div (:class "lt-halo-bar")
      (span (:class "lt-halo-class") (text (class-name (class-of component))))
      (anchor (:class "lt-halo-button" :title "Inspect"
               :callback (lambda () (show component (make-instance 'inspector :object component))))
        "inspect")
      (anchor (:class "lt-halo-button" :title "Toggle source view"
               :callback (lambda () (toggle-source-view component)))
        (text (if (source-view-p component) "render" "source"))))
    (div (:class "lt-halo-body")
      (if (source-view-p component)
          (pre (:class "lt-source")
            (text (with-canvas-to-string () (funcall render))))
          (funcall render)))))

;;; Inspector

(defclass inspector (tool)
  ((object :initarg :object :accessor inspector-object)
   (history :initform '() :accessor inspector-history))
  (:documentation "Shows an object's slots; strings and numbers can be edited."))

(defun object-slots (object)
  (when (typep object '(or standard-object structure-object))
    (mapcar #'closer-mop:slot-definition-name
            (closer-mop:class-slots (class-of object)))))

(defun dive (inspector object)
  (push (inspector-object inspector) (inspector-history inspector))
  (setf (inspector-object inspector) object))

(defun parse-like (old string)
  "STRING read as the same kind of value as OLD, or OLD when it does not parse."
  (typecase old
    (string string)
    (integer (or (parse-number-or-nil string) old))
    (t old)))

(defmethod render ((self inspector))
  (let ((object (inspector-object self)))
    (div (:class "lt-inspector")
      (h2 () "Inspector: " (text (prin1-to-string (type-of object))))
      (form ()
        (table (:class "lt-table")
          (dolist (name (object-slots object))
            (let ((name name))
              (tr ()
                (th () (text (string-downcase name)))
                (td ()
                  (cond ((not (slot-boundp object name))
                         (em () "unbound"))
                        ((typep (slot-value object name) '(or string integer))
                         (text-input (:value (slot-value object name)
                                      :callback (lambda (v)
                                                  (setf (slot-value object name)
                                                        (parse-like (slot-value object name) v))))))
                        ((typep (slot-value object name) '(or standard-object structure-object))
                         (let ((value (slot-value object name)))
                           (anchor (:callback (lambda () (dive self value)))
                             (text (prin1-to-string value)))))
                        (t (code () (text (prin1-to-string (slot-value object name)))))))))))
        (div (:class "lt-buttons")
          (submit-button () "Save")
          (when (inspector-history self)
            (submit-button (:callback (lambda () (setf (inspector-object self)
                                                       (pop (inspector-history self)))))
              "Back"))
          (submit-button (:callback (lambda () (answer self))) "Close"))))))

;;; Session browser

(defclass session-browser (tool)
  ((application :initarg :application :reader browser-application)))

(defun format-age (seconds)
  (cond ((< seconds 60) (format nil "~Ds" seconds))
        ((< seconds 3600) (format nil "~Dm" (floor seconds 60)))
        (t (format nil "~,1Fh" (/ seconds 3600)))))

(defmethod render ((self session-browser))
  (let ((app (browser-application self))
        (now (now-seconds)))
    (div (:class "lt-session-browser")
      (h2 () "Sessions of " (text (application-path app)))
      (table (:class "lt-table")
        (tr () (th () "Key") (th () "Root") (th () "Age") (th () "Idle") (th () "Pages") (th ()))
        (dolist (session (list-sessions app))
          (let ((session session))
            (tr ()
              (td () (code () (text (subseq (session-key session) 0 8))) "…"
                (when (eq session *session*) (em () " (this one)")))
              (td () (text (class-name (class-of (session-root session)))))
              (td () (text (format-age (- now (session-created session)))))
              (td () (text (format-age (- now (session-last-access session)))))
              (td () (text (session-continuation-count session)))
              (td () (unless (eq session *session*)
                       (anchor (:callback (lambda () (expire-session session))) "expire")))))))
      (p () (anchor (:callback (lambda () (answer self))) "Close")))))

;;; Toolbar

(defun render-toolbar (session start)
  (let ((app (session-application session))
        (root (session-root session)))
    (div (:class "lt-toolbar")
      (anchor (:href (application-base-url app)) "New Session")
      (when (find-application "/config")
        (anchor (:href (url-for "/config")) "Configure"))
      (anchor (:callback (lambda () (setf (session-halos-p session) (not (session-halos-p session)))))
        (text (if (session-halos-p session) "Halos off" "Halos")))
      (anchor (:callback (lambda ()
                           (unless (typep (active-component root) 'session-browser)
                             (show root (make-instance 'session-browser :application app)))))
        "Sessions")
      (span (:class "lt-toolbar-time")
        (text (format nil "~D ms" (round (* 1000 (- (get-internal-real-time) start))
                                         internal-time-units-per-second)))))))
