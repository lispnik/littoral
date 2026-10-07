;;;; live.lisp — redefine a render method, see every open page redrawn
;;;;
;;;; A watcher thread notices when a method of RENDER (or STYLE, SCRIPT,
;;;; UPDATE-ROOT, CHILDREN, RENDER-DECORATION) is added or replaced, as
;;;; recompiling one in Emacs does, and records which classes changed.  Open
;;;; pages of applications in development mode showing an instance of one
;;;; reload: those with an event stream are told through it; the others
;;;; poll a cheap endpoint, so live reloading holds no connection (on
;;;; Hunchentoot, no thread) open.  A page's URL names its state, so
;;;; reloading keeps the state and draws it with the new code.
;;;;
;;;; For other changes (a helper function, a stylesheet), call RELOAD-PAGES.

(in-package #:littoral)

(defparameter *watched-generics*
  '(render style script update-root children render-decoration)
  "Generic functions whose methods, when redefined, redraw open pages.")

(defvar *live-watcher* nil)

(defvar *code-changes* '()
  "Recent changes, newest first: (VERSION . CLASSES), CLASSES being T for all.")

(defvar *code-changes-lock* (sb-thread:make-mutex :name "littoral code changes"))

(defun note-code-change (classes)
  "Record that rendering code for CLASSES (or T, everything) changed."
  (sb-thread:with-mutex (*code-changes-lock*)
    (push (cons (incf *code-version*) classes) *code-changes*)
    (when (> (length *code-changes*) 100)
      (setf *code-changes* (subseq *code-changes* 0 100)))))

(defun classes-changed-since (version)
  "The classes changed after VERSION: a list, T for all, or NIL for none."
  (sb-thread:with-mutex (*code-changes-lock*)
    (let ((classes '()))
      (dolist (change *code-changes* classes)
        (when (<= (car change) version) (return classes))
        (if (eq (cdr change) t)
            (return t)
            (setf classes (union classes (cdr change))))))))

(defun live-check (session version)
  "Whether SESSION's page, drawn at code VERSION, should reload."
  (let ((classes (classes-changed-since version)))
    (and classes
         (sb-thread:with-recursive-lock ((session-lock session))
           (shows-class-p (session-root session) classes)))))

(defun method-snapshot ()
  "The methods of the watched generic functions, as a list."
  (loop for name in *watched-generics*
        when (fboundp name)
          append (copy-list (closer-mop:generic-function-methods (fdefinition name)))))

(defun method-classes (methods)
  "The classes METHODS specialise their first argument on; T when one is
not a plain class (an EQL specialiser), meaning every page."
  (let ((classes '()))
    (dolist (method methods classes)
      (let ((specializer (first (closer-mop:method-specializers method))))
        (if (typep specializer 'class)
            (pushnew specializer classes)
            (return t))))))

(defun shows-class-p (root classes)
  "True when something visible from ROOT is an instance of one of CLASSES."
  (or (eq classes t)
      (map-visible (lambda (c)
                     (when (some (lambda (class) (typep c class)) classes)
                       (return-from shows-class-p t)))
                   root)
      nil))

(defun reload-pages (&optional (classes t))
  "Have the open pages of applications in development mode reload: all of
them, or those showing an instance of one of CLASSES.  Pages that poll see
it on their next poll; returns how many pages with event streams were told."
  (note-code-change classes)
  (let ((count 0))
    (dolist (stream (open-event-streams) count)
      (let ((session (stream-session stream)))
        (when (and (development-p (session-application session))
                   (sb-thread:with-recursive-lock ((session-lock session))
                     (shows-class-p (session-root session) classes)))
          (wake stream :reload)
          (incf count))))))

(defun start-live-watcher (&key (interval 0.5))
  "Watch for redefined rendering methods every INTERVAL seconds."
  (stop-live-watcher)
  (setf *live-watcher*
        (sb-thread:make-thread
         (lambda ()
           (let ((known (method-snapshot)))
             (loop
               (sleep interval)
               (ignore-errors
                (let* ((now (method-snapshot))
                       (changed (set-difference now known)))
                  (setf known now)
                  (when (and changed *live-reload*)
                    (reload-pages (method-classes changed))))))))
         :name "littoral live reload")))

(defun stop-live-watcher ()
  "Stop watching for redefined rendering methods."
  (when (and *live-watcher* (sb-thread:thread-alive-p *live-watcher*))
    (sb-thread:terminate-thread *live-watcher*))
  (setf *live-watcher* nil))
