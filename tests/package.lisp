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
