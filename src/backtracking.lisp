;;;; backtracking.lisp — making the back button work
;;;;
;;;; After each action the visible tree is walked and a snapshot taken of
;;;; every component's decorations (so call/answer backtracks) and of the
;;;; slots of every object its STATES method names.  Slot values are kept
;;;; as they are, so a list changed in place changes in every snapshot too;
;;;; name the object as (DEEP object) to copy its lists, vectors, strings
;;;; and hash tables as well.  In development mode, values changed in
;;;; place are noticed after the actions that changed them (see
;;;; CHECK-STATE-CHANGED-IN-PLACE).  Each page's links
;;;; lead back to that page's snapshot, so acting on an old page first puts
;;;; the state back the way the page showed it.

(in-package #:littoral)

(defclass snapshot ()
  ((entries :initarg :entries :reader snapshot-entries
            :documentation "List of (OBJECT . SAVED) where SAVED is what
CAPTURE-STATE returned for it.")
   (fingerprints :initarg :fingerprints :initform '() :reader snapshot-fingerprints
                 :documentation "When state checking was on, a list of (OBJECT KEY
VALUE COPY): a saved value that can be changed in place, and a copy of its
contents at the time."))
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

(defun take-snapshot (root &key (check (state-checks-on-p)))
  "Capture the state of everything visible from ROOT: the slots of each
object the visible components' STATES name, and the decorations of every
visible component.  Returns a SNAPSHOT.  With CHECK (by default, in
development mode), also copy the contents of saved lists, vectors and hash
tables, so CHECK-STATE-CHANGED-IN-PLACE can tell when they change."
  (let ((entries '())
        (to-check '())
        (seen (make-hash-table :test 'eq)))
    (flet ((note (object saved)
             (push (cons object saved) entries)))
      (map-visible (lambda (component)
                     (dolist (state (append (states component)
                                            (mapcan (lambda (d) (copy-list (states d)))
                                                    (decorations component))))
                       (let* ((deep (deep-state-p state))
                              (object (if deep (deep-state-object state) state)))
                         (unless (gethash object seen)
                           (setf (gethash object seen) t)
                           (let ((saved (capture-state object)))
                             (when (and check (not deep))
                               (push (cons object saved) to-check))
                             (note object (if deep
                                              (list :deep (deep-copy-saved saved))
                                              saved))))))
                     ;; A component in its own STATES already has its
                     ;; decorations saved with its other slots.
                     (unless (gethash component seen)
                       (note component (list :decorations (decorations component)))))
                   root))
    ;; Copied once the walk is over, since walking can fill caches.  A value
    ;; that is itself in STATES has its contents saved already.
    (make-instance 'snapshot
                   :entries (nreverse entries)
                   :fingerprints (loop with fingerprints = '()
                                       for (object . saved) in to-check
                                       do (setf fingerprints (fingerprint-state object saved fingerprints seen))
                                       finally (return fingerprints)))))

(defun restore-snapshot (snapshot)
  "Put back what SNAPSHOT captured."
  (loop for (object . saved) in (snapshot-entries snapshot)
        do (case (first saved)
             (:decorations (setf (decorations object) (second saved)))
             ;; Copy again, so later changes cannot reach the snapshot.
             (:deep (restore-state object (deep-copy-saved (second saved))))
             (otherwise (restore-state object saved)))))

;;; Noticing state changed in place

(defvar *check-state-changed-in-place* :development
  "Whether snapshots notice saved values changed in place: :DEVELOPMENT
\(the default) in applications in development mode, T always, NIL never.")

(defvar *state-check-limit* 10000
  "The most conses, vector elements and hash-table entries a value may have
for STATE-CHANGED-IN-PLACE checks; larger values aren't checked.")

(defvar *state-changes-warned* (make-hash-table :test 'equal)
  "The \"class.slot\" name of each slot already warned about.")

(defvar *state-changes-lock* (sb-thread:make-mutex :name "state changes warned"))

(defgeneric shared-state-slots (object)
  (:documentation "Names of OBJECT's slots whose values are shared and
changed in place on purpose, such as a cache, so changing them in place
doesn't signal STATE-CHANGED-IN-PLACE.  The back button doesn't undo such
changes.")
  (:method ((object t)) '()))

(define-condition state-changed-in-place (warning)
  ((object :initarg :object :reader state-changed-object)
   (slot :initarg :slot :reader state-changed-slot))
  (:report (lambda (condition stream)
             (format stream "Littoral: ~A's slot ~S was changed in place, so the back ~\
button can't undo it.  Give it a new value instead, name the object as ~\
\(deep object) in STATES, or list the slot in SHARED-STATE-SLOTS."
                     (state-owner-name (state-changed-object condition))
                     (state-changed-slot condition))))
  (:documentation "Signalled (as a warning) when a list, vector, string or
hash table that a snapshot saved was changed in place by a page's actions,
which the back button can't undo."))

(setf (documentation 'state-changed-object 'function)
      "The object whose slot a STATE-CHANGED-IN-PLACE warning names: a
component, another object in STATES, or a hash table."
      (documentation 'state-changed-slot 'function)
      "The slot a STATE-CHANGED-IN-PLACE warning names, or the key when its object is a hash table.")

(defun state-owner-name (object)
  "OBJECT's class name for STATE-CHANGED-IN-PLACE's report."
  (if (hash-table-p object) "A hash table" (class-name (class-of object))))

(defun state-checks-on-p ()
  "True when snapshots should notice values changed in place."
  (case *check-state-changed-in-place*
    ((nil) nil)
    (:development (and *application* (development-p *application*)))
    (otherwise t)))

(defun state-fingerprint (value)
  "A copy of VALUE's lists, vectors, strings and hash tables, sharing other
objects, or :TOO-BIG when it has more than *STATE-CHECK-LIMIT* parts."
  (let ((budget *state-check-limit*)
        (seen (make-hash-table :test 'eq)))
    (labels ((spend (n)
               (when (minusp (decf budget n))
                 (return-from state-fingerprint :too-big)))
             (copy-cons (value)
               (spend 1)
               (let ((cell (list nil)))
                 (setf (gethash value seen) cell
                       (first cell) (copy (first value))
                       (rest cell) (copy (rest value)))
                 cell))
             (copy-vector (value)
               (spend (length value))
               (let ((new (make-array (length value))))
                 (setf (gethash value seen) new)
                 (dotimes (i (length value) new)
                   (setf (aref new i) (copy (aref value i))))))
             (copy-table (value)
               (spend (hash-table-count value))
               (let ((new (make-hash-table :test (hash-table-test value))))
                 (setf (gethash value seen) new)
                 (maphash (lambda (k v) (setf (gethash k new) (copy v))) value)
                 new))
             (copy (value)
               (multiple-value-bind (copied found) (gethash value seen)
                 (cond (found copied)
                       ((consp value) (copy-cons value))
                       ((stringp value) (spend (length value))
                        (setf (gethash value seen) (copy-seq value)))
                       ((vectorp value) (copy-vector value))
                       ((hash-table-p value) (copy-table value))
                       (t value)))))
      (copy value))))

(defun state-contents-equal (copy value)
  "True when VALUE has the contents COPY, a STATE-FINGERPRINT, recorded:
the same lists, vectors, strings and hash tables, holding EQL leaves."
  (let ((seen (make-hash-table :test 'eq)))
    (labels ((same-table (a b)
               (and (hash-table-p b)
                    (eq (hash-table-test a) (hash-table-test b))
                    (= (hash-table-count a) (hash-table-count b))
                    (loop for k being the hash-keys of a using (hash-value v)
                          always (multiple-value-bind (w present) (gethash k b)
                                   (and present (same v w))))))
             (same-parts (a b)
               (cond ((consp a) (and (consp b) (same (first a) (first b)) (same (rest a) (rest b))))
                     ((stringp a) (and (stringp b) (string= a b)))
                     ((vectorp a) (and (vectorp b) (not (stringp b))
                                       (= (length a) (length b))
                                       (every #'same a b)))
                     (t (same-table a b))))
             (same (a b)
               (if (typep a '(or cons vector hash-table))
                   (multiple-value-bind (paired found) (gethash a seen)
                     (cond (found (eq paired b))
                           (t (setf (gethash a seen) b)
                              (same-parts a b))))
                   (eql a b))))
      (same copy value))))

(defun fingerprint-state (object saved fingerprints saved-objects)
  "FINGERPRINTS with an entry added for each value in SAVED (what
CAPTURE-STATE returned for OBJECT) that can be changed in place, unless
it's in SAVED-OBJECTS, a table of the objects the snapshot saves."
  (let ((shared (shared-state-slots object)))
    (loop for (key . value) in saved
          when (and (typep value '(or cons vector hash-table))
                    (not (gethash value saved-objects))
                    (not (member key shared)))
            do (let ((copy (state-fingerprint value)))
                 (unless (eql copy :too-big)
                   (push (list object key value copy) fingerprints))))
    fingerprints))

(defun current-state-value (object key)
  "What OBJECT holds under KEY now (a slot name, or a hash table's key), and
whether it holds anything."
  (cond ((hash-table-p object) (gethash key object))
        ((slot-boundp object key) (values (slot-value object key) t))
        (t (values nil nil))))

(defun warn-of-state-changed-in-place (snapshot)
  "Signal STATE-CHANGED-IN-PLACE, once per class and slot, for each value
SNAPSHOT saved that its object still holds but whose contents have changed.
Returns \"class.slot\" names for every such value, warned about before or not."
  (let ((changed '()))
    (loop for (object key value copy) in (snapshot-fingerprints snapshot)
          do (multiple-value-bind (now present) (current-state-value object key)
               (when (and present (eq now value) (not (state-contents-equal copy value)))
                 (let ((name (format nil "~(~A.~A~)" (if (hash-table-p object)
                                                          "hash-table"
                                                          (class-name (class-of object)))
                                     key)))
                   (pushnew name changed :test #'string=)
                   (when (sb-thread:with-mutex (*state-changes-lock*)
                           (unless (gethash name *state-changes-warned*)
                             (setf (gethash name *state-changes-warned*) t)))
                     (warn 'state-changed-in-place :object object :slot key))))))
    (nreverse changed)))

(defun forget-state-changes-warned ()
  "Forget which slots STATE-CHANGED-IN-PLACE has warned about, so each warns again."
  (sb-thread:with-mutex (*state-changes-lock*)
    (clrhash *state-changes-warned*)))
