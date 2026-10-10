;;;; index.lisp — /examples, a guide to the examples

(in-package #:littoral-examples)

(defparameter *example-guide*
  '(("Basics"
     ("counter" "Counter" "The first Seaside example: callbacks and backtracking.")
     ("multi-counter" "Multi-Counter" "Components embedding components.")
     ("devtools" "Development tools" "History, the component tree, halos and the debugger, to try.")
     ("login" "Login" "call/answer without a task, with validation.")
     ("todo" "To Do" "Forms, checkboxes and editing through a dialog."))
    ("Flow and navigation"
     ("guess" "Guess the Number" "A task: a multi-page flow as straight-line code.")
     ("wizard" "Wizard" "Signing up in steps, from one description, with a review.")
     ("topics" "Topics" "Bookmarkable URLs with update-url and initial-request.")
     ("report" "Report" "A sortable, paged table.")
     ("widgets" "Widgets" "Tabs, a tree, autocomplete, sortable lists, a data grid, charts, a calendar, kanban and Markdown.")
     ("dialogs" "Dialogs" "Dialogs over the page, and toasts."))
    ("Applications"
     ("store" "Sushi Store" "Catalog, cart and a checkout task with validation, a date picker and isolation.")
     ("wiki" "Wiki" "Shared pages, links, editing, history and search.")
     ("chat" "Chat" "Many sessions in one room, updated by server push.")
     ("contacts" "Contacts" "An address book generated from one description, in English, French or German.")
     ("admin" "Admin" "An admin generated from descriptions, over projects and tasks in SQLite.")
     ("members" "Members" "Signing in, roles and permissions, kept sign-ins, password reset and OAuth.")
     ("accounts" "Accounts" "The same, signing in against an existing table with bcrypt hashes.")
     ("gallery" "Gallery" "Uploads kept on disk, with thumbnails and downloads."))
    ("Browser features"
     ("ajax" "AJAX" "Updating components in place, a live preview and a clock.")
     ("upload" "Upload" "Receiving files.")
     ("progress" "Progress" "A background job updating the page through server push.")
     ("monitoring" "Monitoring" "This server's requests, latency and memory, charted live.")
     ("parenscript" "Parenscript" "Browser code written in Lisp.")
     ("csp" "Content security policy" "Injected script, stopped by the page's policy.")
     ("api" "JSON endpoints" "An API beside the pages, called from the browser."))))

(defun example-registered-p (path)
  "True when an application is registered at exactly PATH: the admin,
members and Parenscript examples come in systems of their own."
  (let ((app (find-application path)))
    (and app (string= (application-path app) path))))

(defclass example-index (component) ()
  (:documentation "A guide to the examples."))

(defmethod render ((self example-index))
  (h1 () "Littoral examples")
  (p () "Each example is its own application. In development mode the toolbar at the "
    "bottom of every page turns on halos, so you can inspect any component.")
  (loop for (heading . examples) in *example-guide*
        do (h2 () (text heading))
           (dl (:class "example-index")
             (loop for (path title blurb) in examples
                   when (example-registered-p (format nil "/examples/~A" path))
                   do (dt () (anchor (:href (url-for (format nil "/examples/~A" path))) (text title)))
                      (dd () (text blurb))))))

(defmethod style ((self example-index))
  ".example-index dt { font-weight: 600; margin-top: .5rem; } .example-index dd { margin-left: 1rem; }")
