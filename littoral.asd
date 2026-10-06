;;;; littoral.asd

(asdf:defsystem #:littoral
  :description "Littoral: a Seaside-style component web framework for Common Lisp."
  :long-description #.(uiop:read-file-string (uiop:subpathname *load-pathname* "README.md"))
  :author "Matthew Kennedy"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/lispnik/littoral"
  :bug-tracker "https://github.com/lispnik/littoral/issues"
  :source-control (:git "https://github.com/lispnik/littoral.git")
  :serial t
  :depends-on (#:sb-posix
               #:sb-introspect
               #:alexandria
               #:cl-ppcre
               #:closer-mop
               #:cl-cont
               #:ironclad
               #:quri
               #:cl-base64
               #:lack-request
               #:clack
               ;; Clack finds handlers by package; load the default one.
               #:clack-handler-hunchentoot)
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "util")
                             (:file "context")
                             (:file "callbacks")
                             (:module "html"
                              :serial t
                              :components ((:file "canvas")
                                           (:file "tags")
                                           (:file "brushes")))
                             (:file "component")
                             (:file "decoration")
                             (:file "dialogs")
                             (:file "backtracking")
                             (:file "task")
                             (:file "widgets")
                             (:file "session")
                             (:file "application")
                             (:file "configuration")
                             (:file "ajax")
                             (:file "dispatcher")
                             (:file "push")
                             (:module "tools"
                              :serial t
                              :components ((:file "halos")
                                           (:file "config")))))
               (:module "static"
                :components ((:static-file "littoral.js")
                             (:static-file "littoral.css"))))
  :in-order-to ((test-op (test-op #:littoral/tests))))

(asdf:defsystem #:littoral/examples
  :description "Example applications for Littoral."
  :author "Matthew Kennedy"
  :license "MIT"
  :depends-on (#:littoral)
  :serial t
  :components ((:module "examples"
                :serial t
                :components ((:file "package")
                             (:file "counter")
                             (:file "multi-counter")
                             (:file "guess")
                             (:file "login")
                             (:file "ajax")
                             (:file "todo")
                             (:file "upload")
                             (:file "topics")
                             (:file "report")
                             (:file "date-picker")
                             (:file "store")
                             (:file "wiki")
                             (:file "chat")
                             (:file "progress")
                             (:file "index")
                             (:file "register")))))

(asdf:defsystem #:littoral/tests
  :description "FiveAM test suite for Littoral."
  :depends-on (#:littoral
               #:littoral/examples
               #:fiveam
               #:flexi-streams
               #:lack
               #:lack-middleware-mount)
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "browser")
                             (:file "canvas")
                             (:file "request-cycle")
                             (:file "call-answer")
                             (:file "backtracking")
                             (:file "task")
                             (:file "ajax")
                             (:file "tools")
                             (:file "widgets")
                             (:file "examples")
                             (:file "push")
                             (:file "robustness")
                             (:file "security"))))
  :perform (asdf:test-op (op c)
             (unless (uiop:symbol-call :fiveam :run!
                                       (uiop:find-symbol* :littoral :littoral/tests))
               (error "Littoral tests failed."))))

(asdf:defsystem #:littoral/bench
  :description "Benchmarks for Littoral: make bench."
  :depends-on (#:littoral/tests)
  :components ((:module "bench" :components ((:file "bench")))))

(asdf:defsystem #:littoral/docs
  :description "Writes docs/API.md from the docstrings: make docs."
  :depends-on (#:littoral #:sb-introspect)
  :components ((:module "tools" :components ((:file "api-docs")))))
