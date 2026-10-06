;;;; login.lisp — call/answer with validation, without a task

(in-package #:littoral-examples)

(defclass login-demo (component)
  ((user :initform nil :accessor user)))

(defmethod states ((self login-demo))
  (list self))

(defun check-credentials (answer)
  (cond ((null answer) nil)               ; Cancel is always fine
        ((and (string= (car answer) "admin") (string= (cdr answer) "secret")) nil)
        (t "Unknown user or wrong password.")))

(defun log-in (self)
  (show self (validate-with (make-instance 'login-dialog :message "Try admin / secret.")
                            #'check-credentials)
        :on-answer (lambda (answer)
                     (when answer (setf (user self) (car answer))))))

(defun log-out (self)
  (show self (make-instance 'confirm-dialog :message "Really log out?")
        :on-answer (lambda (yes) (when yes (setf (user self) nil)))))

(defmethod render ((self login-demo))
  (if (user self)
      (p () "Welcome, " (strong () (text (user self))) ". "
        (anchor (:callback (lambda () (log-out self))) "Log out"))
      (p () "Nobody is logged in. "
        (anchor (:callback (lambda () (log-in self))) "Log in"))))
