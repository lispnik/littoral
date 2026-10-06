;;;; register.lisp — serve the examples under /examples

(in-package #:littoral-examples)

(defun register-examples ()
  (register-application "/examples/counter" 'counter :title "Counter")
  (register-application "/examples/multi-counter" 'multi-counter :title "Multi-Counter")
  (register-application "/examples/guess" 'guess-game :title "Guess the Number")
  (register-application "/examples/login" 'login-demo :title "Login")
  (register-application "/examples/ajax" 'ajax-demo :title "AJAX")
  (register-application "/examples/todo" 'todo-list :title "To Do")
  (register-application "/examples/upload" 'upload-demo :title "Upload"))

(register-examples)
