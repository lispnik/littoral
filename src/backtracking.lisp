;;;; backtracking.lisp — making the back button work
;;;;
;;;; After each action the visible tree is walked and a snapshot taken of
;;;; every component's decorations (so call/answer backtracks) and of the
;;;; slots of every object its STATES method names.  Slot values are kept
;;;; as they are, so a list changed in place changes in every snapshot too;
;;;; name the object as (DEEP object) to copy its lists, vectors, strings
;;;; and hash tables as well.  Each page's links
;;;; lead back to that page's snapshot, so acting on an old page first puts
;;;; the state back the way the page showed it.

(in-package #:littoral)

(defclass snapshot ()
  ((entries :initarg :entries :reader snapshot-entries
            :documentation "List of (OBJECT . SAVED) where SAVED is what
CAPTURE-STATE returned for it."))
  (:documentation "The saved state of a page: what TAKE-SNAPSHOT captured and RESTORE-SNAPSHOT puts back."))

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

(defstruct (deep-state (:constructor deep (object)))
  "Wrap an object in DEEP in STATES to snapshot its slots deeply."
  object)

(setf (documentation 'deep 'function)
      "Name OBJECT in STATES as (DEEP OBJECT) to snapshot its lists, vectors,
strings and hash tables by copying them, not sharing them.")

(defun deep-copy (value &optional (seen (make-hash-table :test 'eq)))
  "A copy of VALUE's lists, vectors, strings and hash tables, all the way
down.  Other objects (instances, structures, symbols, numbers) are shared;
shared structure and cycles are kept."
  (typecase value
    ((or cons vector hash-table)
     (or (gethash value seen)
         (typecase value
           (cons (let ((copy (list nil)))
                   (setf (gethash value seen) copy
                         (first copy) (deep-copy (first value) seen)
                         (rest copy) (deep-copy (rest value) seen))
                   copy))
           (string (setf (gethash value seen) (copy-seq value)))
           (vector (let ((copy (make-array (length value)
                                           :element-type (array-element-type value))))
                     (setf (gethash value seen) copy)
                     (dotimes (i (length value) copy)
                       (setf (aref copy i) (deep-copy (aref value i) seen)))))
           (hash-table (let ((copy (make-hash-table :test (hash-table-test value)
                                                    :size (hash-table-size value))))
                         (setf (gethash value seen) copy)
                         (maphash (lambda (k v) (setf (gethash k copy) (deep-copy v seen))) value)
                         copy))
           (otherwise value))))
    (otherwise value)))

(defun deep-copy-saved (saved)
  "SAVED, a slot alist from CAPTURE-STATE, with its values deep-copied."
  (let ((seen (make-hash-table :test 'eq)))
    (mapcar (lambda (entry) (cons (first entry) (deep-copy (rest entry) seen))) saved)))

(defun take-snapshot (root)
  "Capture the state of everything visible from ROOT."
  (let ((entries '())
        (seen (make-hash-table :test 'eq)))
    (flet ((note (object saved)
             (push (cons object saved) entries)))
      (map-visible (lambda (component)
                     (dolist (state (states component))
                       (let* ((deep (deep-state-p state))
                              (object (if deep (deep-state-object state) state)))
                         (unless (gethash object seen)
                           (setf (gethash object seen) t)
                           (note object (if deep
                                            (list :deep (deep-copy-saved (capture-state object)))
                                            (capture-state object))))))
                     ;; A component in its own STATES already has its
                     ;; decorations saved with its other slots.
                     (unless (gethash component seen)
                       (note component (list :decorations (decorations component)))))
                   root))
    (make-instance 'snapshot :entries (nreverse entries))))

(defun restore-snapshot (snapshot)
  "Put back what SNAPSHOT captured."
  (loop for (object . saved) in (snapshot-entries snapshot)
        do (case (first saved)
             (:decorations (setf (decorations object) (second saved)))
             ;; Copy again, so later changes cannot reach the snapshot.
             (:deep (restore-state object (deep-copy-saved (second saved))))
             (otherwise (restore-state object saved)))))
