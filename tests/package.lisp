;;;; package.lisp

(defpackage #:littoral/tests
  (:use #:cl #:littoral #:littoral.html #:fiveam)
  (:export #:littoral)
  (:documentation "The FiveAM suite for Littoral."))

(in-package #:littoral/tests)

(def-suite littoral :description "All Littoral tests.")
