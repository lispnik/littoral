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
