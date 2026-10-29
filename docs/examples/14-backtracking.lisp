;;;; The examples for backtracking: snapshots, deep state and isolation.

;;;; Example: littoral:take-snapshot littoral:restore-snapshot littoral:snapshot littoral:snapshot-entries
;;; Littoral snapshots the page after every action and restores it when an old page is used.  A snapshot holds one entry for each object named in the visible components' states (and one for the decorations of each component not named).
(defclass fuel-gauge (component)
  ((litres :initform 40 :accessor litres)))
(defmethod states ((self fuel-gauge)) (list self))
(let* ((gauge (make-instance 'fuel-gauge))
       (full (take-snapshot gauge)))
  (setf (litres gauge) 5)
  (restore-snapshot full)
  (list (litres gauge) (length (snapshot-entries full))))
;; ⇒ (40 1)

;;;; Example: littoral:deep
;;; Snapshots keep slot values as they are, so a list or hash table changed in place would change in every snapshot.  Naming the object as (deep object) copies them instead, and going back shows the table as it was.
(defclass stock (component)
  ((counts :initform (make-hash-table :test 'equal) :reader counts)))
(defmethod states ((self stock)) (list (deep self)))
(defmethod render ((self stock))
  (h:p () "Rope: " (h:text (princ-to-string (gethash "rope" (counts self) 0))))
  (h:anchor (:callback (lambda () (incf (gethash "rope" (counts self) 0)))) "Add rope"))
(with-fresh-applications (("/stock" 'stock :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/stock")
    (click b "Add rope")
    (let ((one (browser-url b)))
      (click b "Add rope")
      (click b "Add rope")
      (back-to b one)
      (body-text b))))
;; ⇒ "Rope: 1 Add rope"

;;;; Example: littoral:state-changed-in-place littoral:state-changed-object littoral:state-changed-slot littoral:*check-state-changed-in-place*
;;; In development mode, a list, vector or hash table that a snapshot saved and an action then changed in place is noticed: the back button can't undo such a change, so Littoral signals this warning (once per slot) and the toolbar names the slot.  *check-state-changed-in-place* is :development by default; T checks in deployment mode too, NIL never.
(defclass logbook (component)
  ((entries :initform (list "Cast off") :accessor entries)))
(defmethod states ((self logbook)) (list self))
(defmethod render ((self logbook))
  (h:anchor (:callback (lambda () (nconc (entries self) (list "Anchored")))) "Log"))
(with-fresh-applications (("/log" 'logbook :mode :development))
  (let ((b (make-instance 'browser))
        (noticed '()))
    (visit b "/log")
    (handler-bind ((state-changed-in-place
                     (lambda (warning)
                       (push (list (type-of (state-changed-object warning))
                                   (state-changed-slot warning))
                             noticed)
                       (muffle-warning warning))))
      (click b "Log"))
    noticed))
;; ⇒ ((LOGBOOK ENTRIES))

;;;; Example: littoral:shared-state-slots
;;; A slot whose value is shared and changed in place on purpose, such as a cache, is listed by shared-state-slots, and changing it isn't warned of.  The back button doesn't undo it, which for a cache is what's wanted.
(defclass chart-table (component)
  ((soundings :initform (make-hash-table) :reader soundings)))
(defmethod states ((self chart-table)) (list self))
(defmethod shared-state-slots ((self chart-table)) '(soundings))
(defmethod render ((self chart-table))
  (h:anchor (:callback (lambda () (setf (gethash :harbour (soundings self)) 12))) "Sound"))
(with-fresh-applications (("/chart" 'chart-table :mode :development))
  (let ((b (make-instance 'browser))
        (warnings 0))
    (visit b "/chart")
    (handler-bind ((state-changed-in-place (lambda (w) (incf warnings) (muffle-warning w))))
      (click b "Sound"))
    warnings))
;; ⇒ 0

;;;; Example: littoral:deep-copy
;;; Lists, vectors, strings and hash tables are copied; shared structure stays shared, and other objects are not copied.
(let* ((buoy (make-instance 'component))
       (pair (list 1 2))
       (value (list pair pair buoy))
       (copy (deep-copy value)))
  (list (eq (first copy) pair)
        (eq (first copy) (second copy))
        (eq (third copy) buoy)
        (equal (subseq copy 0 2) (subseq value 0 2))))
;; ⇒ (NIL T T T)

;;;; Example: littoral:begin-isolation littoral:end-isolation
;;; Once the order is placed, end-isolation forgets the pages of the checkout, so the back button cannot place it twice: an old page's link shows the session as it is now.
(defclass ferry-booking (task)
  ((tickets :initform 0 :accessor tickets)))
(define-flow ferry-booking (self)
  (let ((isolation (begin-isolation)))
    (when (confirm self "Book a ticket?")
      (incf (tickets self))
      (end-isolation isolation)
      (inform self (format nil "Booked ~D ticket~:P." (tickets self))))))
(with-fresh-applications (("/ferry" 'ferry-booking :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/ferry")
    (let ((asked (browser-url b)))
      (press b "Yes")
      (let ((booked (body-text b)))
        (back-to b asked)
        (list booked (body-text b))))))
;; ⇒ ("Booked 1 ticket. OK" "Booked 1 ticket. OK")
