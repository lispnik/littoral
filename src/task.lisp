;;;; task.lisp — components that are a sequence of other components
;;;;
;;;; A task has no rendering of its own.  Its FLOW calls other components
;;;; one after another, as if each CALL returned the component's answer:
;;;;
;;;;   (defclass checkout (task) ())
;;;;
;;;;   (define-flow checkout (self)
;;;;     (let ((cart (call self (make-instance 'cart-editor))))
;;;;       (when (confirm self "Place the order?")
;;;;         (place-order cart))))
;;;;
;;;; DEFINE-FLOW rewrites the body in continuation-passing style with
;;;; cl-cont, so each CALL suspends the flow until the component answers.
;;;; That rewrite has limits: no UNWIND-PROTECT, CATCH or HANDLER-CASE
;;;; around a CALL, and variables SETQ'd after a CALL are shared by every
;;;; page that resumes from it, so prefer fresh bindings to mutation when
;;;; the back button matters.
;;;;
;;;; When the flow returns, the task answers its value.  A task nobody
;;;; called (a root task) starts its flow again, as in Seaside.

(in-package #:littoral)

(defclass task (component)
  ()
  (:documentation "A component defined by a FLOW of calls."))

(defun task-running-p (task)
  "A task is running while it shows a component it called.  Deriving this
from its decorations keeps it right when the back button restores them."
  (find-decoration task 'delegation))

(defgeneric flow (task)
  (:documentation "The body of TASK.  Define methods with DEFINE-FLOW."))

(defmacro define-flow (class (self) &body body)
  "Define the flow of the task CLASS, with SELF bound to the task."
  (multiple-value-bind (forms declarations doc) (alexandria:parse-body body :documentation t)
    `(defmethod flow ((,self ,class))
       ,@(when doc (list doc))
       ,@declarations
       (with-call/cc
         (finish-task ,self (progn ,@forms))))))

(defun finish-task (task value)
  (answer task value))

(defmethod render ((self task))
  nil)

(defun start-task (task)
  (flow task))

(defun prepare-tasks (root)
  "Start the flow of every visible task not already running."
  ;; A flow that ends at once would restart forever, so each task gets one
  ;; start per pass.
  (let ((started '()))
    (loop
      (let ((idle '()))
        (map-visible (lambda (c)
                       (when (and (typep c 'task)
                                  (not (task-running-p c))
                                  (not (member c started)))
                         (push c idle)))
                     root)
        (when (null idle) (return))
        (dolist (task (nreverse idle))
          (push task started)
          (start-task task))))))
