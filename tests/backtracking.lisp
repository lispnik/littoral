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
