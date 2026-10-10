;;;; chrome.lisp — Littoral's examples in a real Chrome
;;;;
;;;;   make test-chrome
;;;;
;;;; What the fake browser can't show: JavaScript running, AJAX updating the
;;;; page in place, the back button with Chrome's caches, and passkeys.  Also
;;;; an example of testing an application with littoral/browser-test.  Needs
;;;; Chrome (or set CHROME); without it the suite is skipped.

(defpackage #:littoral/chrome-tests
  (:use #:cl #:fiveam #:littoral.browser-test)
  (:export #:run-chrome-tests))

(in-package #:littoral/chrome-tests)

(def-suite chrome :description "The examples in headless Chrome.")
(in-suite chrome)

(defvar *base* nil "The test server's URL.  localhost, not 127.0.0.1: WebAuthn won't take an IP.")

(defun free-port ()
  (let ((socket (usocket:socket-listen "127.0.0.1" 0)))
    (prog1 (usocket:get-local-port socket) (usocket:socket-close socket))))

(defmacro with-page ((page) &body body)
  `(with-chrome (,page :base *base*) ,@body))

(test ajax-updates-in-place
  (with-page (page)
    (visit page "/examples/ajax")
    (evaluate page "window.marker = 42")
    (click-css page "[data-lt-on-click]")
    (wait-until page "document.querySelector('.ajax-count').textContent === '1'")
    (is (equal "1" (text page ".ajax-count")))
    (is (eql 42 (evaluate page "window.marker")) "AJAX doesn't reload the page")))

(test back-button
  (with-page (page)
    (visit page "/examples/counter")
    (dotimes (i 3) (click-text page "++"))
    (is (equal "3" (text page "h1")))
    (back page)
    (back page)
    (is (equal "1" (text page "h1")))
    (click-text page "++")
    (is (equal "2" (text page "h1")) "Counting goes on from the page you went back to")))

(test passkey-sign-in
  (with-page (page)
    (add-virtual-authenticator page)
    (visit page "/examples/members")
    (click-text page "Sign in")
    (type-into page "#sign-in-name" "ada")
    (type-into page "#sign-in-password" "correct horse battery")
    (click-text page "Sign in" :among "button")
    (is (search "Signed in as ada" (text page)))
    (click-text page "Add a passkey")
    (wait-until page "document.body.innerText.includes('Passkey 1')")
    (click-text page "Sign out")
    (click-text page "Sign in")
    (click-text page "Sign in with a passkey")
    (wait-until page "document.body.innerText.includes('Signed in as ada')")
    (is (search "Signed in as ada" (text page)) "Signed in with no password")))

(defun run-chrome-tests ()
  "Serve the examples on a free port and run the suite in Chrome; true when it passes."
  (unless (ignore-errors (chrome-path))
    (format t "~&No Chrome: skipping the Chrome tests.~%")
    (return-from run-chrome-tests t))
  ;; A database of its own: users here gain passkeys.
  (littoral-members-demo:register :file (merge-pathnames (format nil "littoral-chrome-members-~36R.sqlite3"
                                                                 (random (expt 36 8) (make-random-state t)))
                                                         (uiop:temporary-directory)))
  (setf littoral:*new-sessions-per-minute* nil)
  (let ((port (free-port)))
    (littoral:start :port port)
    (unwind-protect
         (let ((*base* (format nil "http://localhost:~D" port)))
           (run! 'chrome))
      (littoral:stop))))
