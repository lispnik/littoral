;;;; reading-list-tests.lisp — step 12 of docs/tutorial.md: testing the reading list
;;;;
;;;; FiveAM tests that use the reading list through littoral/test's fake
;;;; browser, as a reader of the tutorial writes them.

(defpackage #:reading-list/tests
  (:use #:cl #:fiveam #:littoral #:littoral.test)
  (:documentation "Tests of the tutorial's reading list."))

(in-package #:reading-list/tests)

(def-suite reading-list-tests :description "The reading list, used as a visitor uses it.")
(in-suite reading-list-tests)

(test adding-a-book
  (with-fresh-applications (("/tutorial/reading-list" 'reading-list:reading-list :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/tutorial/reading-list")
      (fill-in b "new-title" "On Lisp")
      (press b "Add")
      (is (has-text-p b "On Lisp")))))

(test removing-asks-first
  (with-fresh-applications (("/tutorial/reading-list" 'reading-list:reading-list :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/tutorial/reading-list")
      (click-nth b "remove" 0)
      (is (has-text-p b "Remove Structure and Interpretation of Computer Programs?"))
      (press b "No")
      (is (= 2 (length (find-links b "remove"))))
      (click-nth b "remove" 0)
      (press b "Yes")
      (is (= 1 (length (find-links b "remove"))))
      (is (has-text-p b "Paradigms of Artificial Intelligence Programming")))))

(test the-back-button
  (with-fresh-applications (("/tutorial/counter" 'reading-list:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/tutorial/counter")
      (click b "++")
      (let ((one (browser-url b)))
        (click b "++")
        (click b "++")
        (back-to b one)
        (click b "++")
        (is (string= "2 ++ --" (body-text b)))))))
