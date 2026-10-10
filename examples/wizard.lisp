;;;; wizard.lisp — signing up in steps, from one description

(in-package #:littoral-examples)

(defclass subscriber ()
  ((name :initarg :name :initform nil)
   (email :initarg :email :initform nil)
   (plan :initarg :plan :initform :personal)
   (seats :initarg :seats :initform 1)
   (start :initarg :start :initform nil)
   (newsletter :initarg :newsletter :initform t)
   (about :initarg :about :initform nil))
  (:documentation "Someone signing up for a plan."))

(define-description subscriber
  ((name :required t :max-length 60)
   (email :type :email :required t)
   (plan :type :choice :choices '(:personal :team :enterprise) :labels #'string-capitalize)
   (seats :type :integer :min 1 :max 500 :help "How many people will use it.")
   (start :type :date :label "Start date" :help "Year, month and day, like 2026-11-01.")
   (newsletter :type :boolean :label "Send me the newsletter")
   (about :type :markdown :label "About you" :help "Optional; Markdown works."))
  :validate (lambda (values)
              (when (and (eq (getf values :plan) :personal) (> (or (getf values :seats) 1) 1))
                "Personal plans are for one person: choose Team for more seats.")))

(defclass wizard-demo (component)
  ((done :initform nil :accessor demo-done))
  (:documentation "Starts the sign-up wizard, and shows what it answered."))

(defmethod states ((self wizard-demo)) (list self))

(defmethod render ((self wizard-demo))
  (h1 () "Wizard")
  (p () (code () "make-wizard") " shows a description's fields a few at a time: Next checks each step, "
    "Back keeps what was typed, and a review comes before Finish, which runs the description's own check. "
    "It answers like any dialog, so a flow can " (code () "call") " it.")
  (let ((done (demo-done self)))
    (when done
      (div (:class "lt-dialog" :role "status")
        (h2 () "Welcome, " (text (slot-value done 'name)) "!")
        (render-component (make-viewer done)))))
  (p () (anchor (:callback (lambda ()
                             (show self (make-wizard (make-instance 'subscriber) :title "Sign up"
                                                     :steps '(("Account" name email)
                                                              ("Plan" plan seats start)
                                                              ("About you" newsletter about)))
                                   :on-answer (lambda (subscriber) (when subscriber (setf (demo-done self) subscriber))))))
          (text (if (demo-done self) "Sign up someone else" "Sign up")))))
