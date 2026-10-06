;;;; register.lisp — serve the examples under /examples

(in-package #:littoral-examples)

(defun register-examples ()
  (register-application "/examples" 'example-index :title "Littoral Examples")
  (register-application "/examples/counter" 'counter :title "Counter")
  (register-application "/examples/multi-counter" 'multi-counter :title "Multi-Counter")
  (register-application "/examples/guess" 'guess-game :title "Guess the Number")
  (register-application "/examples/login" 'login-demo :title "Login")
  (register-application "/examples/ajax" 'ajax-demo :title "AJAX")
  (register-application "/examples/todo" 'todo-list :title "To Do")
  (register-application "/examples/upload" 'upload-demo :title "Upload")
  (register-application "/examples/topics" 'topics :title "Topics")
  (register-application "/examples/report" 'element-table :title "Report")
  (register-application "/examples/store" 'store :title "Sushi Store")
  (register-application "/examples/wiki" 'wiki :title "Wiki")
  (register-application "/examples/chat" 'chat :title "Chat")
  (register-application "/examples/progress" 'progress-demo :title "Progress"))

(register-examples)
