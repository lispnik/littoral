;;;; index.lisp — /examples, a guide to the examples

(in-package #:littoral-examples)

(defparameter *example-guide*
  '(("Basics"
     ("counter" "Counter" "The first Seaside example: callbacks and backtracking.")
     ("multi-counter" "Multi-Counter" "Components embedding components.")
     ("login" "Login" "call/answer without a task, with validation.")
     ("todo" "To Do" "Forms, checkboxes and editing through a dialog."))
    ("Flow and navigation"
     ("guess" "Guess the Number" "A task: a multi-page flow as straight-line code.")
     ("topics" "Topics" "Bookmarkable URLs with update-url and initial-request.")
     ("report" "Report" "A sortable, paged table."))
    ("Applications"
     ("store" "Sushi Store" "Catalog, cart and a checkout task with validation, a date picker and isolation.")
     ("wiki" "Wiki" "Shared pages, links, editing, history and search.")
     ("chat" "Chat" "Many sessions in one room, with AJAX posting and polling."))
    ("Browser features"
     ("ajax" "AJAX" "Updating components in place, a live preview and a clock.")
     ("upload" "Upload" "Receiving files."))))

(defclass example-index (component) ())

(defmethod render ((self example-index))
  (h1 () "Littoral examples")
  (p () "Each example is its own application. In development mode the toolbar at the bottom of every page turns on halos, so you can inspect any component.")
  (loop for (heading . examples) in *example-guide*
        do (h2 () (text heading))
           (dl (:class "example-index")
             (loop for (path title blurb) in examples
                   do (dt () (anchor (:href (url-for (format nil "/examples/~A" path))) (text title)))
                      (dd () (text blurb))))))

(defmethod style ((self example-index))
  ".example-index dt { font-weight: 600; margin-top: .5rem; } .example-index dd { margin-left: 1rem; }")
