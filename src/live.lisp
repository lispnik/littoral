;;;; live.lisp — redefine a render method, see every open page redrawn
;;;;
;;;; In development mode every page keeps an event stream open.  A watcher
;;;; thread notices when a method of RENDER (or STYLE, SCRIPT, UPDATE-ROOT,
;;;; CHILDREN, RENDER-DECORATION) is added or replaced, as recompiling one
;;;; in Emacs does, and tells the open pages showing an instance of the
;;;; class it is specialised on to reload.  A page's URL names its state, so
;;;; reloading keeps the state and draws it with the new code.
;;;;
;;;; For other changes (a helper function, a stylesheet), call RELOAD-PAGES.

(in-package #:littoral)

(defparameter *watched-generics*
  '(render style script update-root children render-decoration)
  "Generic functions whose methods, when redefined, redraw open pages.")

(defvar *live-watcher* nil)

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
them, or those showing an instance of one of CLASSES.  Returns how many."
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
  (when (and *live-watcher* (sb-thread:thread-alive-p *live-watcher*))
    (sb-thread:terminate-thread *live-watcher*))
  (setf *live-watcher* nil))
