;;;; {{name}}.asd

(asdf:defsystem #:{{name}}
  :description "{{title}}, a Littoral application with a database and signing in."
  :author "{{author}}"
  :license "{{license}}"
  :version "0.1.0"
  :depends-on (#:littoral #:littoral/db #:littoral/auth #:littoral/admin #:littoral/mail #:dbd-sqlite3 #:dbd-postgres)
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "model")
                             (:file "app")
                             (:file "main"))))
  :in-order-to ((test-op (test-op #:{{name}}/tests))))

(asdf:defsystem #:{{name}}/tests
  :description "Tests for {{name}}."
  :depends-on (#:{{name}} #:littoral/test #:fiveam)
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "app"))))
  :perform (test-op (o c)
             (unless (uiop:symbol-call :fiveam :run! (uiop:find-symbol* '#:{{name}} '#:{{name}}/tests))
               (error "Tests failed."))))
