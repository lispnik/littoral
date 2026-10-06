;;;; login.lisp — call/answer with validation, without a task

(in-package #:littoral-examples)

(defclass login-demo (component)
  ((user :initform nil :accessor user))
  (:documentation "Logging in and out through dialogs."))

(defmethod states ((self login-demo))
  (list self))

(defun credentials-problem (answer)
  "NIL when ANSWER, a (USER . PASSWORD) cons or NIL, may log in; else why not."
  (cond ((null answer) nil)               ; Cancel is always fine
        ((and (string= (first answer) "admin") (string= (rest answer) "secret")) nil)
        (t "Unknown user or wrong password.")))

(defun log-in (self)
  "Ask for credentials and remember the user they name."
  (show self (validate-with (make-instance 'login-dialog :message "Try admin / secret.")
                            #'credentials-problem)
        :on-answer (lambda (answer)
                     (when answer (setf (user self) (first answer))))))

(defun log-out (self)
  "Confirm, then forget the user."
  (show self (make-instance 'confirm-dialog :message "Really log out?")
        :on-answer (lambda (yes) (when yes (setf (user self) nil)))))

(defmethod render ((self login-demo))
  (if (user self)
      (p () "Welcome, " (strong () (text (user self))) ". "
        (anchor (:callback (lambda () (log-out self))) "Log out"))
      (p () "Nobody is logged in. "
        (anchor (:callback (lambda () (log-in self))) "Log in"))))
