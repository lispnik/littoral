;;;; task.lisp — flows written with call

(in-package #:littoral/tests)

(def-suite tasks :in littoral)
(in-suite tasks)

(defclass fixed-guess (littoral-examples:guess-game) ()
  (:default-initargs :target 42)
  (:documentation "A guessing game whose number is 42."))

(defun guess (browser n)
  "Guess N in the guessing game."
  (let ((name (cl-ppcre:register-groups-bind (n) ("<input type=\"text\" name=\"(\\d+)\"" (browser-html browser)) n)))
    (setf (browser-fields browser) (list (cons name (princ-to-string n))))
    (press browser "OK")))

(test guess-game
  (with-fresh-applications (("/guess" 'fixed-guess :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/guess")
      (is (has-text-p b "thinking of a number"))
      (press b "OK")
      (is (has-text-p b "Your guess?"))
      (guess b 50)
      (is (has-text-p b "Lower."))
      (press b "OK")
      (guess b 10)
      (is (has-text-p b "Higher."))
      (press b "OK")
      (guess b 42)
      (is (has-text-p b "Got it in 3 guesses!"))
      ;; A root task starts over when its flow ends.
      (press b "OK")
      (is (has-text-p b "thinking of a number")))))

(defclass two-step (task)
  ((log :initform '() :accessor two-step-log))
  (:documentation "A task asking two questions and answering both."))

(define-flow two-step (self)
  (let ((a (request-input self "First?")))
    (push a (two-step-log self))
    (let ((b (request-input self "Second?")))
      (push b (two-step-log self))
      (list a b))))

(defclass task-host (component)
  ((result :initform nil :accessor result))
  (:documentation "Calls a TWO-STEP task and shows its answer."))

(defmethod render ((self task-host))
  (p () "Host: " (text (prin1-to-string (result self))))
  (anchor (:callback (lambda ()
                       (show self (make-instance 'two-step)
                             :on-answer (lambda (v) (setf (result self) v)))))
    "start"))

(defun answer-input (browser value)
  "Answer the input dialog on the page with VALUE."
  (let ((name (cl-ppcre:register-groups-bind (n) ("<input type=\"text\" name=\"(\\d+)\"" (browser-html browser)) n)))
    (setf (browser-fields browser) (list (cons name value)))
    (press browser "OK")))

(test called-task-answers-its-flow-value
  (with-fresh-applications (("/host" 'task-host :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/host")
      (click b "start")
      (is (has-text-p b "First?"))
      (answer-input b "x")
      (is (has-text-p b "Second?"))
      (answer-input b "y")
      (is (has-text-p b "Host: (\"x\" \"y\")")))))

(test back-button-in-a-flow
  (with-fresh-applications (("/host" 'task-host :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/host")
      (click b "start")
      (answer-input b "x")
      (let ((second-page (browser-url b)))
        (answer-input b "y")
        (back-to b second-page)
        (is (has-text-p b "Second?"))
        (answer-input b "z")
        (is (has-text-p b "Host: (\"x\" \"z\")"))))))
