;;;; guess.lisp — a task: the flow reads top to bottom

(in-package #:littoral-examples)

(defclass guess-game (task)
  ((target :initarg :target :initform nil :accessor target
           :documentation "The number to guess; random when NIL.")))

(define-flow guess-game (self)
  (let ((target (or (target self) (1+ (random 100))))
        (guesses 0)
        (guess nil))
    (inform self "I'm thinking of a number between 1 and 100.")
    (loop until (eql guess target)
          do (setf guess (parse-integer (request-input self "Your guess?") :junk-allowed t))
             (incf guesses)
             (cond ((null guess) (inform self "That's not a number."))
                   ((< guess target) (inform self "Higher."))
                   ((> guess target) (inform self "Lower."))))
    (inform self (format nil "Got it in ~D guesses!" guesses))))
