;;;; call-answer.lisp — call, answer, show and decorations

(in-package #:littoral/tests)

(def-suite call-answer :in littoral)
(in-suite call-answer)

(defclass parent (component)
  ((result :initform nil :accessor result)))

(defmethod states ((self parent)) (list self))

(defmethod render ((self parent))
  (p () "Parent. Result: " (text (prin1-to-string (result self))))
  (anchor (:callback (lambda ()
                       (show self (make-instance 'input-dialog :message "Name?")
                             :on-answer (lambda (v) (setf (result self) v)))))
    "ask"))

(test show-and-answer
  (with-fresh-applications (("/p" 'parent :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/p")
      (is (has-text-p b "Result: NIL"))
      (click b "ask")
      (is (has-text-p b "Name?"))
      (is (not (has-text-p b "Parent.")))
      (let ((name (cl-ppcre:register-groups-bind (n) ("<input type=\"text\" name=\"(\\d+)\"" (browser-html b)) n)))
        (setf (browser-fields b) (list (cons name "Ada"))))
      (press b "OK")
      (is (has-text-p b "Result: \"Ada\"")))))

(test decoration-order
  (let ((c (make-instance 'component))
        (local (make-instance 'message-decoration :message "m"))
        (global (make-instance 'littoral::answer-handler))
        (delegation (make-instance 'delegation :delegate (make-instance 'component))))
    (add-decoration c local)
    (add-decoration c delegation)
    (add-decoration c global)
    (is (equal (list global delegation local) (decorations c)))
    (remove-decoration c delegation)
    (is (equal (list global local) (decorations c)))))

(test answer-without-caller-is-harmless
  (is (null (answer (make-instance 'component) 42))))

(test call-outside-a-flow-shows
  (let ((a (make-instance 'component)) (b (make-instance 'component)))
    (call a b)
    (is (eq b (active-component a)))
    (answer b :done)
    (is (eq a (active-component a)))))

(test home-dismisses
  (let ((a (make-instance 'component)))
    (show a (make-instance 'component))
    (home a)
    (is (eq a (active-component a)))))

(test validation
  (with-fresh-applications (("/login" 'littoral-examples:login-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/login")
      (is (has-text-p b "Nobody is logged in"))
      (click b "Log in")
      (fill-in b "username" "admin")
      (fill-in b "password" "wrong")
      (press b "Log in")
      (is (has-text-p b "wrong password"))
      (fill-in b "username" "admin")
      (fill-in b "password" "secret")
      (press b "Log in")
      (is (has-text-p b "Welcome, admin"))
      (click b "Log out")
      (press b "No")
      (is (has-text-p b "Welcome, admin"))
      (click b "Log out")
      (press b "Yes")
      (is (has-text-p b "Nobody is logged in")))))

(test form-decoration
  (let* ((c (make-instance 'component))
         (registry (make-instance 'littoral::callback-registry))
         (answered :none))
    (add-decoration c (make-instance 'form-decoration :buttons '(("Save" . :save) ("Cancel" . nil))))
    (show (make-instance 'component) c :on-answer (lambda (v) (setf answered v)))
    (let* ((littoral:*render-context* (make-instance 'littoral::render-context
                                                     :callbacks registry :action-url "/"))
           (out (with-canvas-to-string () (render-component c))))
      (is (search "<form" out))
      (is (search ">Save</button>" out)))
    (littoral::process-callbacks '(("1" . "1")) registry)
    (is (eq :save answered))))
