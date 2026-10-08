;;;; dialogs.lisp — small components that ask one thing and answer it

(in-package #:littoral)

(defclass dialog (component)
  ((message :initarg :message :initform nil :accessor dialog-message))
  (:documentation "A component that shows an optional MESSAGE and answers one thing."))

(defun render-dialog-message (dialog)
  "Write DIALOG's message, if it has one."
  (when (dialog-message dialog)
    (p (:class "lt-dialog-message") (text (dialog-message dialog)))))

(defclass message-dialog (dialog) ()
  (:documentation "Shows a message; answers T."))

(defmethod render ((self message-dialog))
  (div (:class "lt-dialog")
    (render-dialog-message self)
    (form ()
      (submit-button (:callback (lambda () (answer self t))) "OK"))))

(defclass confirm-dialog (dialog) ()
  (:documentation "Asks a yes/no question; answers T or NIL."))

(defmethod render ((self confirm-dialog))
  (div (:class "lt-dialog")
    (render-dialog-message self)
    (form ()
      (submit-button (:callback (lambda () (answer self t))) "Yes")
      (submit-button (:callback (lambda () (answer self nil))) "No"))))

(defclass input-dialog (dialog)
  ((value :initarg :value :initform "" :accessor dialog-value))
  (:documentation "Asks for a line of text; answers the string."))

(defmethod render ((self input-dialog))
  (div (:class "lt-dialog")
    (render-dialog-message self)
    (form ()
      (text-input (:value (dialog-value self) :label (or (dialog-message self) "Answer")
                   :callback (lambda (v) (setf (dialog-value self) v))
                   :autofocus t))
      (submit-button (:callback (lambda () (answer self (dialog-value self)))) "OK"))))

(defclass choice-dialog (dialog)
  ((items :initarg :items :initform '() :reader dialog-items)
   (label-function :initarg :labels :initform #'princ-to-string :reader dialog-labels)
   (selected :initform nil :accessor dialog-selected))
  (:documentation "Asks for one of ITEMS; answers it, or NIL on Cancel."))

(defmethod render ((self choice-dialog))
  (div (:class "lt-dialog")
    (render-dialog-message self)
    (form ()
      (select-list (:items (dialog-items self) :label (or (dialog-message self) "Choice")
                    :labels (dialog-labels self)
                    :selected (dialog-selected self)
                    :callback (lambda (item) (setf (dialog-selected self) item))))
      (submit-button (:callback (lambda () (answer self (dialog-selected self)))) "OK")
      (cancel-button (:callback (lambda () (answer self nil))) "Cancel"))))

(defclass login-dialog (dialog)
  ((username :initform "" :accessor dialog-username)
   (password :initform "" :accessor dialog-password))
  (:documentation "Asks for a username and password; answers them as a
cons, or NIL on Cancel."))

(defmethod render ((self login-dialog))
  (div (:class "lt-dialog lt-login")
    (render-dialog-message self)
    (form ()
      (label () "Username "
        (text-input (:id "username" :value (dialog-username self)
                     :callback (lambda (v) (setf (dialog-username self) v)))))
      (label () "Password "
        (password-input (:id "password"
                         :callback (lambda (v) (setf (dialog-password self) v)))))
      (submit-button (:callback (lambda ()
                                  (answer self (cons (dialog-username self)
                                                     (dialog-password self)))))
        "Log in")
      (cancel-button (:callback (lambda () (answer self nil))) "Cancel"))))

;;; Seaside's inform:, confirm:, request: and chooseFrom:

(defun/cc inform (self message)
  (call self (make-instance 'message-dialog :message message)))

(defun/cc confirm (self question)
  (call self (make-instance 'confirm-dialog :message question)))

(defun/cc request-input (self prompt &optional (default ""))
  (call self (make-instance 'input-dialog :message prompt :value default)))

(defun/cc choose-from (self items &optional prompt)
  (call self (make-instance 'choice-dialog :message prompt :items items)))

;; DEFUN/CC drops docstrings, so they are set here.
(setf (documentation 'inform 'function)
      "Show MESSAGE in place of SELF until it is acknowledged.  A CALL: blocking inside a flow."
      (documentation 'confirm 'function)
      "Ask QUESTION in place of SELF; T for yes, NIL for no.  A CALL: blocking inside a flow."
      (documentation 'request-input 'function)
      "Ask for a line of text with PROMPT, starting from DEFAULT; the string typed.  A CALL."
      (documentation 'choose-from 'function)
      "Ask for one of ITEMS, with PROMPT; the item chosen, or NIL.  A CALL.")

(defclass session-expired-notice (dialog) ()
  (:default-initargs
   :message "Your session expired, so you are starting again from the beginning.")
  (:documentation "A ready-made EXPIRED-NOTICE for REGISTER-APPLICATION."))

(defmethod render ((self session-expired-notice))
  (div (:class "lt-dialog lt-expired")
    (render-dialog-message self)
    (form ()
      (submit-button (:callback (lambda () (answer self t))) "Continue"))))
