;;;; package.lisp

(defpackage #:littoral/tests
  (:use #:cl #:littoral #:littoral.html #:littoral.test #:fiveam)
  (:export #:littoral)
  (:documentation "The FiveAM suite for Littoral."))

(in-package #:littoral/tests)

(def-suite littoral :description "All Littoral tests.")

;; The suite starts hundreds of sessions from 127.0.0.1 a minute; the rate
;; limit has a test of its own.
(setf littoral:*new-sessions-per-minute* nil)

;; Hashing at full strength takes a good part of a second; tests make many.
(setf littoral.auth:*pbkdf2-iterations* 1000)

;;; The database the database tests use: in-memory SQLite, or the PostgreSQL
;;; that LITTORAL_TEST_DATABASE names (postgres://user:password@host:port/db).

(defun test-database-spec ()
  (let ((url (uiop:getenv "LITTORAL_TEST_DATABASE")))
    (if (and url (plusp (length url)))
        (let* ((uri (quri:uri url))
               (userinfo (quri:uri-userinfo uri))
               (colon (and userinfo (position #\: userinfo))))
          (unless (member (quri:uri-scheme uri) '("postgres" "postgresql") :test #'string=)
            (error "LITTORAL_TEST_DATABASE must be a postgres:// URL: ~A" url))
          (list :postgres
                :database-name (string-left-trim "/" (quri:uri-path uri))
                :host (quri:uri-host uri)
                :port (or (quri:uri-port uri) 5432)
                :username (if colon (subseq userinfo 0 colon) userinfo)
                :password (if colon (quri:url-decode (subseq userinfo (1+ colon))) "")))
        (list :sqlite3 :database-name ":memory:"))))

(defun connect-test-database ()
  "Connect to the test database (see TEST-DATABASE-SPEC)."
  (apply #'littoral.db:connect-database (test-database-spec)))

(defun postgres-test-p ()
  (eq (first (test-database-spec)) :postgres))

(defparameter *database-suites* '(db auth auth-store admin outbox)
  "The suites that use the test database, run again against PostgreSQL.")

(defun run-database-suites ()
  "Run *DATABASE-SUITES*; quit with status 1 if any fails (for make and CI)."
  (let ((ok t))
    (dolist (suite *database-suites*)
      (unless (fiveam:run! suite) (setf ok nil)))
    (uiop:quit (if ok 0 1))))
