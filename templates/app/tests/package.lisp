;;;; package.lisp

(defpackage #:{{name}}/tests
  (:use #:cl #:fiveam #:littoral #:littoral.test #:{{name}})
  (:documentation "Tests for {{name}}, driving it with Littoral's fake browser."))

(in-package #:{{name}}/tests)

(def-suite {{name}} :description "All of {{name}}'s tests.")

;; Hashing passwords at full strength takes a good part of a second each.
(setf littoral.auth:*pbkdf2-iterations* 1000)
