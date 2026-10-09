;;;; package.lisp

;;; LITTORAL and LITTORAL.HTML export common names (TASK, CALL, SHOW, LABEL,
;;; MAIN, TABLE and the other tags): define functions under other names, or
;;; shadow the symbol here first.  littoral.db and littoral.auth are used
;;; with their prefixes.
(defpackage #:{{name}}
  (:use #:cl #:littoral #:littoral.html)
  (:export #:app-root #:note #:register-app #:serve #:toplevel #:create-user #:database-spec)
  (:documentation "{{title}}, a Littoral application with a database and signing in."))
