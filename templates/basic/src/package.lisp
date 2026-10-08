;;;; package.lisp

;;; LITTORAL and LITTORAL.HTML export common names (TASK, CALL, SHOW, LABEL,
;;; MAIN, TABLE and the other tags): define functions under other names, or
;;; shadow the symbol here first.
(defpackage #:{{name}}
  (:use #:cl #:littoral #:littoral.html)
  (:export #:front-page #:register-app #:serve #:toplevel)
  (:documentation "{{title}}, a Littoral application."))
