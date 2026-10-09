;;;; halos.lisp — development tools: toolbar, halos, inspector, sessions
;;;;
;;;; In :DEVELOPMENT mode every page ends with a toolbar.  Turning halos on
;;;; frames each component with its class and buttons to inspect it or to
;;;; see the HTML it renders.

(in-package #:littoral)

(defclass tool (component) ()
  (:documentation "Components of the tools themselves, which get no halo."))

;;; Halos

(defun halo-view (component)
  "How COMPONENT's halo shows it: :RENDERED, :HTML or :CODE."
  (or (and *session*
           (cdr (assoc (component-id component) (session-source-views *session*) :test #'string=)))
      :rendered))

(defun (setf halo-view) (view component)
  (let ((id (component-id component)))
    (setf (session-source-views *session*)
          (if (eq view :rendered)
              (remove id (session-source-views *session*) :key #'car :test #'string=)
              (acons id view (remove id (session-source-views *session*) :key #'car :test #'string=))))
    view))

(defun toggle-halo-view (component view)
  (setf (halo-view component) (if (eq (halo-view component) view) :rendered view)))

(defvar *profile-depth* 0)

(defmethod render-component :around ((component component))
  (flet ((render-it ()
           (if (and *render-context* (render-halos-p *render-context*) (not (typep component 'tool)))
               (render-halo component #'call-next-method)
               (call-next-method))))
    (if (listp *render-profile*)
        (let ((start (get-internal-real-time))
              (entry (list component 0 *profile-depth*)))
          (push entry *render-profile*)
          (let ((*profile-depth* (1+ *profile-depth*)))
            (prog1 (render-it)
              (setf (second entry) (/ (- (get-internal-real-time) start)
                                      internal-time-units-per-second)))))
        (render-it))))

;;; Finding a component's source

(defun toplevel-form-bounds (text)
  "The (START . END) character positions of each top-level form in TEXT."
  (with-input-from-string (in text)
    (let ((*read-suppress* t) (bounds '()))
      (loop
        ;; Skip whitespace and comments to find where the next form starts.
        (loop for c = (peek-char t in nil nil)
              while (eql c #\;)
              do (read-line in nil))
        (let ((start (file-position in)))
          (when (eq (read-preserving-whitespace in nil in) in)
            (return (nreverse bounds)))
          (push (cons start (file-position in)) bounds))))))

(defun definition-location (source)
  "The pathname, start and end of the form an sb-introspect definition
SOURCE names, or NIL."
  (let ((pathname (sb-introspect:definition-source-pathname source))
        (path (sb-introspect:definition-source-form-path source)))
    (when (and pathname path (probe-file pathname))
      (let ((bounds (nth (first path)
                         (toplevel-form-bounds
                          (alexandria:read-file-into-string pathname :external-format :utf-8)))))
        (when bounds
          (values pathname (car bounds) (cdr bounds)))))))

(defun component-definitions (component)
  "(TITLE PATHNAME START END) for COMPONENT's class and its RENDER method."
  (let ((class (class-of component))
        (results '()))
    (let ((source (first (sb-introspect:find-definition-sources-by-name (class-name class) :class))))
      (when source
        (multiple-value-bind (pathname start end) (definition-location source)
          (when pathname
            (push (list (format nil "Class ~(~A~)" (class-name class)) pathname start end) results)))))
    (let ((method (first (compute-applicable-methods #'render (list component)))))
      (when method
        (let ((source (sb-introspect:find-definition-source method)))
          (multiple-value-bind (pathname start end) (definition-location source)
            (when pathname
              (push (list (format nil "Method render on ~(~A~)"
                                  (class-name (first (closer-mop:method-specializers method))))
                          pathname start end)
                    results))))))
    (nreverse results)))

(defvar *source-editor* nil
  "A function of a pathname and a 1-based character position that opens the
source there, for the halos' edit button.  NIL uses the Emacs connected
through Swank, when there is one.")

(defun swank-connected-p ()
  (let ((package (find-package :swank)))
    (and package
         (let ((default (find-symbol "DEFAULT-CONNECTION" package)))
           (and default (fboundp default) (funcall default))))))

(defun edit-in-emacs (pathname position)
  "Open PATHNAME at POSITION in the Emacs connected through Swank."
  (let* ((package (find-package :swank))
         (connection (funcall (find-symbol "DEFAULT-CONNECTION" package))))
    (progv (list (find-symbol "*EMACS-CONNECTION*" package)) (list connection)
      (funcall (find-symbol "ED-IN-EMACS" package)
               (list (namestring pathname) :position position)))))

(defun source-editor ()
  "The function the edit button calls, or NIL when there is none."
  (or *source-editor* (and (swank-connected-p) #'edit-in-emacs)))

(defun render-code-view (component)
  (let ((definitions (component-definitions component)))
    (if (null definitions)
        (p (:class "lt-source") "No source found: was it compiled from a file?")
        (loop for (title pathname start end) in definitions
              do (let ((pathname pathname) (start start))
                   (div (:class "lt-code")
                     (div (:class "lt-code-title")
                       (strong () (text title)) " "
                       (code () (text (format nil "~A" (file-namestring pathname))))
                       (let ((editor (source-editor)))
                         (when editor
                           (text " ")
                           (anchor (:class "lt-halo-button"
                                    :callback (lambda () (funcall editor pathname (1+ start))))
                             "edit"))))
                     (pre (:class "lt-source")
                       (text (subseq (alexandria:read-file-into-string pathname :external-format :utf-8)
                                     start end)))))))))

(defun render-halo (component render)
  (let ((view (halo-view component)))
    (div (:class "lt-halo")
      (div (:class "lt-halo-bar")
        (span (:class "lt-halo-class") (text (class-name (class-of component))))
        (anchor (:class "lt-halo-button" :title "Inspect"
                 :callback (lambda () (show component (make-instance 'inspector :object component))))
          "inspect")
        (anchor (:class "lt-halo-button" :title "Toggle the HTML this component writes"
                 :callback (lambda () (toggle-halo-view component :html)))
          (text (if (eq view :html) "render" "html")))
        (anchor (:class "lt-halo-button" :title "Toggle the Lisp source of this component"
                 :callback (lambda () (toggle-halo-view component :code)))
          (text (if (eq view :code) "render" "code"))))
      (div (:class "lt-halo-body")
        (case view
          (:html (pre (:class "lt-source")
                   (text (with-canvas-to-string () (funcall render)))))
          (:code (render-code-view component))
          (t (funcall render)))))))

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
        (tr () (th () "Key") (th () "Root") (th () "Age") (th () "Idle") (th () "Pages")
          (th (:title "Objects in the newest page's snapshot") "Objects")
          (th (:title "Snapshot entries held across all its pages") "Held") (th ()))
        (dolist (session (list-sessions app))
          (let ((session session))
            (tr ()
              (td () (code () (text (subseq (session-key session) 0 8))) "…"
                (when (eq session *session*) (em () " (this one)")))
              (td () (text (class-name (class-of (session-root session)))))
              (td () (text (format-age (- now (session-created session)))))
              (td () (text (format-age (- now (session-last-access session)))))
              (td () (text (session-continuation-count session)))
              (multiple-value-bind (latest held) (session-snapshot-sizes session)
                (td () (text latest))
                (td () (text held)))
              (td () (unless (eq session *session*)
                       (anchor (:callback (lambda () (expire-session session))) "expire")))))))
      (p () (anchor (:callback (lambda () (answer self))) "Close")))))

;;; Toolbar and profiler

(defun milliseconds (seconds)
  (format nil "~,1F ms" (* 1000 seconds)))

(defun render-profile (profile)
  (div (:class "lt-profile")
    (h3 () "Render profile")
    (table (:class "lt-table")
      (tr () (th () "Component") (th () "Inclusive"))
      (dolist (entry (reverse profile))
        (destructuring-bind (component seconds depth) entry
          (tr ()
            (td (:style (format nil "padding-left: ~,1Frem" (+ 0.6 (* 1.2 depth))))
              (text (string-downcase (class-name (class-of component)))))
            (td (:class "number") (text (milliseconds seconds)))))))))

(defun render-toolbar (session start)
  (let ((app (session-application session))
        (root (session-root session))
        (stats (session-last-action session)))
    (when (and (session-profiling-p session) (listp *render-profile*))
      (render-profile *render-profile*))
    (div (:class "lt-toolbar")
      (anchor (:href (application-base-url app)) "New Session")
      (when (find-application "/config")
        (anchor (:href (url-for "/config")) "Configure"))
      (anchor (:callback (lambda () (setf (session-halos-p session) (not (session-halos-p session)))))
        (text (if (session-halos-p session) "Halos off" "Halos")))
      (anchor (:callback (lambda () (setf (session-profiling-p session) (not (session-profiling-p session)))))
        (text (if (session-profiling-p session) "Profile off" "Profile")))
      (anchor (:callback (lambda ()
                           (unless (typep (active-component root) 'session-browser)
                             (show root (make-instance 'session-browser :application app)))))
        "Sessions")
      (anchor (:callback (lambda ()
                           (unless (typep (active-component root) 'history-browser)
                             (show root (make-instance 'history-browser)))))
        "History")
      (anchor (:callback (lambda ()
                           (unless (typep (active-component root) 'component-tree)
                             (show root (make-instance 'component-tree)))))
        "Components")
      (span (:class "lt-toolbar-time")
        (when stats
          (text (format nil "actions ~A · snapshot ~A (~D objects) · "
                        (milliseconds (getf stats :actions))
                        (milliseconds (getf stats :snapshot))
                        (getf stats :objects))))
        (text (format nil "render ~A"
                      (milliseconds (/ (- (get-internal-real-time) start)
                                       internal-time-units-per-second))))))))
