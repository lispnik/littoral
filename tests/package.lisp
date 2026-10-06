;;;; package.lisp

(defpackage #:littoral/tests
  (:use #:cl #:littoral #:littoral.html #:fiveam)
  (:export #:littoral))

(in-package #:littoral/tests)

(def-suite littoral :description "All Littoral tests.")
