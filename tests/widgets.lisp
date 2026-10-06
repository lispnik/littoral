;;;; widgets.lisp — batched list and report

(in-package #:littoral/tests)

(def-suite widgets :in littoral)
(in-suite widgets)

(defun first-column (browser)
  "The first cell of each body row of the page's report."
  (let ((body (cl-ppcre:scan-to-strings "(?s)<tbody>.*</tbody>" (browser-html browser))))
    (let (cells)
      (cl-ppcre:do-register-groups (cell) ("<tr[^>]*><td[^>]*>([^<]*)</td>" body)
        (push cell cells))
      (nreverse cells))))

(test batching
  (let ((list (make-instance 'batched-list :items (alexandria:iota 25) :batch-size 10)))
    (is (equal (alexandria:iota 10) (batch list)))
    (go-to-page list 2)
    (is (equal '(20 21 22 23 24) (batch list)))
    (go-to-page list 99)
    (is (= 2 (batch-page list)))
    (setf (batch-items list) (alexandria:iota 5))
    (is (= 0 (batch-page list)))
    (is (equal (alexandria:iota 5) (batch list)))))

(test report-sorts-and-pages
  (with-fresh-applications (("/report" 'littoral-examples:element-table :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/report")
      (is (equal '("1" "2" "3" "4" "5" "6" "7" "8" "9" "10") (first-column b)))
      (click b "Next »")
      (is (equal "11" (first (first-column b))))
      (click b "3")
      (is (equal '("21" "22" "23" "24" "25" "26" "27" "28" "29" "30") (first-column b)))
      ;; Sorting by name goes back to the first page.
      (click b "Name")
      (is (search "Name ▲" (page-text b)))
      (is (equal "13" (first (first-column b))))          ; Aluminium
      (click b "Name")
      (is (search "Name ▼" (page-text b)))
      (is (equal "30" (first (first-column b))))          ; Zinc
      ;; Weight is numeric and rendered with three decimals.
      (click b "Weight")
      (is (equal "1" (first (first-column b))))
      (is (search "1.008" (page-text b)))
      ;; Custom cells carry callbacks.
      (click b "select")
      (is (has-text-p b "Selected: Hydrogen"))
      (is (search "class=\"selected\"" (browser-html b))))))

(test report-backtracks-sort
  (with-fresh-applications (("/report" 'littoral-examples:element-table :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/report")
      (let ((unsorted (browser-url b)))
        (click b "Name")
        (back-to b unsorted)
        (is (equal "1" (first (first-column b))))
        (is (not (search "▲" (page-text b))))))))

(test value-ordering
  (is (equal '(1 2 10 nil) (sort (list nil 10 1 2) #'littoral::value<)))
  (is (equal '("apple" "Banana" "cherry")
             (sort (list "cherry" "apple" "Banana") #'littoral::value<))))
