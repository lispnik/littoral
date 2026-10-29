;;;; backtracking.lisp — the back button

(in-package #:littoral/tests)

(def-suite backtracking :in littoral)
(in-suite backtracking)

(test back-button-restores-state
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (click b "++")
      (let ((at-one (browser-url b)))
        (click b "++") (click b "++")
        (is (= 3 (count-shown b)))
        ;; Back to the page showing 1, then ++ on it: 2, not 4.
        (back-to b at-one)
        (is (= 1 (count-shown b)))
        (click b "++")
        (is (= 2 (count-shown b)))))))

(test back-button-restores-call
  (with-fresh-applications (("/p" 'parent :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/p")
      (let ((before (browser-url b)))
        (click b "ask")
        (is (has-text-p b "Name?"))
        (back-to b before)
        (is (has-text-p b "Parent."))
        (is (not (has-text-p b "Name?")))))))

(test unregistered-state-is-not-restored
  ;; Only STATES backtrack: a plain slot keeps its latest value.
  (let ((c (make-instance 'parent)))
    (setf (result c) 1)
    (let ((snap (take-snapshot c)))
      (setf (result c) 2)
      (restore-snapshot snap)
      (is (= 1 (result c)))))
  (let ((c (make-instance 'littoral-examples:multi-counter)))
    (let ((snap (take-snapshot c)))
      (incf (slot-value (first (slot-value c 'littoral-examples::counters)) 'littoral-examples::count))
      (restore-snapshot snap)
      ;; Children's STATES are included.
      (is (zerop (slot-value (first (slot-value c 'littoral-examples::counters)) 'littoral-examples::count))))))

(test hash-tables-backtrack
  (let ((table (make-hash-table)))
    (setf (gethash :a table) 1)
    (let ((saved (littoral::capture-state table)))
      (setf (gethash :a table) 2 (gethash :b table) 3)
      (littoral::restore-state table saved)
      (is (= 1 (gethash :a table)))
      (is (null (gethash :b table))))))

(test continuation-limit
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment :max-continuations 3))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (let ((first-url (browser-url b)))
        (dotimes (i 5) (click b "++"))
        (let ((session (first (littoral::list-sessions (find-application "/counter")))))
          (is (= 3 (littoral::session-continuation-count session))))
        ;; The forgotten page leads to the present state.
        (back-to b first-url)
        (is (= 5 (count-shown b)))))))

;;; Noticing state changed in place

(defclass in-place-list (component)
  ((items :initform (list 1) :accessor in-place-items)
   (table :initform (make-hash-table) :reader in-place-table)
   (cache :initform (list :cached) :accessor in-place-cache)))

(defmethod states ((self in-place-list)) (list self))
(defmethod shared-state-slots ((self in-place-list)) '(cache))

(defmethod render ((self in-place-list))
  (h:p () (h:text (format nil "items ~{~A~^ ~}" (in-place-items self))))
  (h:anchor (:callback (lambda () (nconc (in-place-items self) (list 2)))) "nconc")
  (h:anchor (:callback (lambda () (setf (gethash :k (in-place-table self)) t))) "gethash")
  (h:anchor (:callback (lambda () (setf (in-place-items self) (append (in-place-items self) (list 3))))) "replace")
  (h:anchor (:callback (lambda () (nconc (in-place-cache self) (list :more)))) "cache")
  (h:button (:on-click (ajax :callback (lambda () (nconc (in-place-items self) (list 4))))) "ajax"))

(defclass deep-in-place-list (in-place-list) ())
(defmethod states ((self deep-in-place-list)) (list (deep self)))

(defun slots-changed-in-place (thunk)
  "The slots STATE-CHANGED-IN-PLACE named while THUNK ran, muffled."
  (let ((slots '()))
    (handler-bind ((state-changed-in-place
                     (lambda (w) (push (state-changed-slot w) slots) (muffle-warning w))))
      (funcall thunk))
    (nreverse slots)))

(test changes-in-place-are-noticed
  (littoral::forget-state-changes-warned)
  (with-fresh-applications (("/list" 'in-place-list :mode :development))
    (let ((b (make-instance 'browser)))
      (visit b "/list")
      (is (equal '(items) (slots-changed-in-place (lambda () (click b "nconc")))))
      (is (search "changed in place: in-place-list.items" (browser-html b)))
      (is (equal '(table) (slots-changed-in-place (lambda () (click b "gethash")))))
      ;; New values, and slots shared on purpose, aren't changes in place.
      (is (null (slots-changed-in-place (lambda () (click b "replace")))))
      (is (not (search "changed in place" (browser-html b))))
      (is (null (slots-changed-in-place (lambda () (click b "cache")))))
      ;; Each slot warns once, but the toolbar keeps saying so.
      (is (null (slots-changed-in-place (lambda () (click b "nconc")))))
      (is (search "changed in place: in-place-list.items" (browser-html b))))))

(test ajax-changes-in-place-are-noticed
  (littoral::forget-state-changes-warned)
  (with-fresh-applications (("/list" 'in-place-list :mode :development))
    (let ((b (make-instance 'browser)))
      (visit b "/list")
      (let ((spec (first (ajax-specs b "on-click"))))
        (is (equal '(items) (slots-changed-in-place
                             (lambda () (ajax-request b (first spec) (rest spec))))))))))

(test changes-in-place-are-not-checked-when-copied-or-deployed
  (littoral::forget-state-changes-warned)
  (let ((*check-state-changed-in-place* :development))
    (with-fresh-applications (("/deep" 'deep-in-place-list :mode :development)
                              ("/list" 'in-place-list :mode :deployment))
      (dolist (path '("/deep" "/list"))
        (let ((b (make-instance 'browser)))
          (visit b path)
          (is (null (slots-changed-in-place (lambda () (click b "nconc") (click b "gethash"))))))))
    ;; Outside a request, snapshots copy nothing unless asked.
    (is (null (littoral::snapshot-fingerprints (take-snapshot (make-instance 'in-place-list))))))
  (let ((*check-state-changed-in-place* t))
    (is (= 3 (length (littoral::snapshot-fingerprints (take-snapshot (make-instance 'in-place-list))))))))

(test state-fingerprints-are-bounded-and-keep-cycles
  (let ((cycle (list 1 2 3)))
    (setf (cdr (last cycle)) cycle)
    (let ((copy (littoral::state-fingerprint cycle)))
      (is (littoral::state-contents-equal copy cycle))
      (setf (second cycle) 20)
      (is (not (littoral::state-contents-equal copy cycle)))))
  (let ((v (vector "a" (list 1 2))) (h (make-hash-table :test 'equal)))
    (setf (gethash "k" h) v)
    (let ((copy (littoral::state-fingerprint h)))
      (is (littoral::state-contents-equal copy h))
      (setf (char (aref v 0) 0) #\b)
      (is (not (littoral::state-contents-equal copy h)))))
  (let ((littoral::*state-check-limit* 10))
    (is (eq :too-big (littoral::state-fingerprint (make-list 11))))
    (is (listp (littoral::state-fingerprint (make-list 10))))))
