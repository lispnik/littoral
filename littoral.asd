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
                             (:file "widgets-more")
                             (:file "descriptions")
                             (:file "session")
                             (:file "application")
                             (:file "configuration")
                             (:file "ajax")
                             (:file "dispatcher")
                             (:file "push")
                             (:file "live")
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
                             (:file "contacts")
                             (:file "widgets")
                             (:file "index")
                             (:file "register")))))

(asdf:defsystem #:littoral/test
  :description "A fake browser for testing Littoral applications in-process."
  :author "Matthew Kennedy"
  :license "MIT"
  :depends-on (#:littoral #:flexi-streams #:cl-ppcre #:quri)
  :serial t
  :components ((:module "testing"
                :serial t
                :components ((:file "package")
                             (:file "browser")))))

(asdf:defsystem #:littoral/tests
  :description "FiveAM test suite for Littoral."
  :depends-on (#:littoral
               #:littoral/examples
               #:littoral/tracker
               #:littoral/tutorial
               #:littoral/test
               #:littoral/db
               #:littoral/admin
               #:littoral/admin-demo
               #:littoral/auth
               #:littoral/oauth
               #:dbd-sqlite3
               #:fiveam
               #:flexi-streams
               #:lack
               #:lack-middleware-mount)
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
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
                             (:file "security")
                             (:file "descriptions")
                             (:file "widgets-more")
                             (:file "tracker")
                             (:file "tutorial")
                             (:file "live")
                             (:file "db")
                             (:file "admin")
                             (:file "auth"))))
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
  :depends-on (#:littoral #:littoral/test #:sb-introspect)
  :components ((:module "tools" :components ((:file "api-docs")))))

(asdf:defsystem #:littoral/tracker
  :description "Tracker: an issue tracker built with Littoral."
  :author "Matthew Kennedy"
  :license "MIT"
  :depends-on (#:littoral)
  :serial t
  :components ((:module "apps/tracker"
                :serial t
                :components ((:file "package")
                             (:file "model")
                             (:file "ui")))))

(asdf:defsystem #:littoral/tutorial
  :description "The reading list application docs/tutorial.md builds."
  :depends-on (#:littoral)
  :components ((:module "docs/tutorial" :components ((:file "reading-list")))))

(asdf:defsystem #:littoral/woo
  :description "Serve Littoral on Woo, with server push from its event loops."
  :depends-on (#:littoral #:clack-handler-woo #:woo #:lev #:cffi)
  :components ((:module "src" :components ((:file "woo")))))

(asdf:defsystem #:littoral/db
  :description "Keep Littoral's described objects in a SQL database (cl-dbi)."
  :author "Matthew Kennedy"
  :license "MIT"
  :depends-on (#:littoral #:dbi)
  :components ((:module "src" :components ((:file "db")))))

(asdf:defsystem #:littoral/admin
  :description "An administration interface generated from descriptions and tables."
  :author "Matthew Kennedy"
  :license "MIT"
  :depends-on (#:littoral #:littoral/db)
  :components ((:module "src" :components ((:file "admin")))))

(asdf:defsystem #:littoral/admin-demo
  :description "A generated admin over projects and tasks in SQLite."
  :depends-on (#:littoral/admin #:dbd-sqlite3)
  :components ((:module "examples" :components ((:file "admin-demo")))))

(asdf:defsystem #:littoral/auth
  :description "Users, signing in, roles and password reset for Littoral."
  :author "Matthew Kennedy"
  :license "MIT"
  :depends-on (#:littoral #:littoral/db)
  :components ((:module "src" :components ((:file "auth")))))

(asdf:defsystem #:littoral/oauth
  :description "Sign in to Littoral applications with OAuth 2 / OpenID Connect providers."
  :author "Matthew Kennedy"
  :license "MIT"
  :depends-on (#:littoral/auth #:dexador #:com.inuoe.jzon #:cl-base64)
  :components ((:module "src" :components ((:file "oauth")))))
