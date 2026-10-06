;;;; backtracking.lisp — making the back button work
;;;;
;;;; After each action the visible tree is walked and a snapshot taken of
;;;; every component's decorations (so call/answer backtracks) and of the
;;;; slots of every object its STATES method names.  Each page's links
;;;; lead back to that page's snapshot, so acting on an old page first puts
;;;; the state back the way the page showed it.

(in-package #:littoral)

(defclass snapshot ()
  ((entries :initarg :entries :reader snapshot-entries
            :documentation "List of (OBJECT . SAVED) where SAVED is what
CAPTURE-STATE returned for it.")))

(defgeneric capture-state (object)
  (:documentation "A copy of OBJECT's state that RESTORE-STATE can put back.")
  (:method ((object standard-object))
    (loop for slot in (closer-mop:class-slots (class-of object))
          for name = (closer-mop:slot-definition-name slot)
          collect (if (slot-boundp object name)
                      (cons name (slot-value object name))
                      (cons name '%unbound))))
  (:method ((object structure-object))
    (loop for slot in (closer-mop:class-slots (class-of object))
          for name = (closer-mop:slot-definition-name slot)
          collect (cons name (slot-value object name))))
  (:method ((object hash-table))
    (loop for key being the hash-keys of object using (hash-value value)
          collect (cons key value))))

(defgeneric restore-state (object saved)
  (:method ((object standard-object) saved)
    (loop for (name . value) in saved
          do (if (eq value '%unbound)
                 (slot-makunbound object name)
                 (setf (slot-value object name) value))))
  (:method ((object structure-object) saved)
    (loop for (name . value) in saved
          do (setf (slot-value object name) value)))
  (:method ((object hash-table) saved)
    (clrhash object)
    (loop for (key . value) in saved
          do (setf (gethash key object) value))))

(defun take-snapshot (root)
  "Capture the state of everything visible from ROOT."
  (let ((entries '())
        (seen (make-hash-table :test 'eq)))
    (flet ((note (object saved)
             (push (cons object saved) entries)))
      (map-visible (lambda (component)
                     (dolist (object (states component))
                       (unless (gethash object seen)
                         (setf (gethash object seen) t)
                         (note object (capture-state object))))
                     ;; A component in its own STATES already has its
                     ;; decorations saved with its other slots.
                     (unless (gethash component seen)
                       (note component (list :decorations (decorations component)))))
                   root))
    (make-instance 'snapshot :entries (nreverse entries))))

(defun restore-snapshot (snapshot)
  "Put back what SNAPSHOT captured."
  (loop for (object . saved) in (snapshot-entries snapshot)
        do (if (eq (first saved) :decorations)
               (setf (decorations object) (second saved))
               (restore-state object saved))))
