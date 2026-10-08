;;;; app.lisp — the front page, through a fake browser
;;;;
;;;; The browser calls the application in-process: VISIT a URL, CLICK a
;;;; link by its text, FILL-IN a field by its id and PRESS a button, then
;;;; ask what the page says with HAS-TEXT-P.

(in-package #:{{name}}/tests)

(in-suite {{name}})

(test counting
  (with-fresh-applications (("/" 'front-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/")
      (is (has-text-p b "Count: 0"))
      (click b "Add one")
      (click b "Add one")
      (is (has-text-p b "Count: 2"))
      (click b "Take one away")
      (is (has-text-p b "Count: 1")))))

(test resetting-asks-first
  (with-fresh-applications (("/" 'front-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/")
      (click b "Add one")
      (click b "Reset")
      (is (has-text-p b "Set the count back to zero?"))
      (press b "No")
      (is (has-text-p b "Count: 1"))
      (click b "Reset")
      (press b "Yes")
      (is (has-text-p b "Count: 0")))))

(test greeting
  (with-fresh-applications (("/" 'front-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/")
      (fill-in b "visitor" "Ada")
      (press b "Greet")
      (is (has-text-p b "Hello, Ada!")))))

(test the-back-button-goes-back
  (with-fresh-applications (("/" 'front-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/")
      (click b "Add one")
      (let ((one (browser-url b)))
        (click b "Add one")
        (is (has-text-p b "Count: 2"))
        (back-to b one)
        (click b "Add one")
        (is (has-text-p b "Count: 2"))))))
