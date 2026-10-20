;;;; dialogs.lisp — small components that ask one thing and answer it

(in-package #:littoral)

(defclass dialog (component)
  ((message :initarg :message :initform nil :accessor dialog-message))
  (:documentation "A component that shows an optional MESSAGE and answers one thing."))

(defun render-dialog-message (dialog)
  "Write DIALOG's message, if it has one."
  (when (dialog-message dialog)
    (h:p (:class "lt-dialog-message") (h:text (dialog-message dialog)))))

(defclass message-dialog (dialog) ()
  (:documentation "Shows its :MESSAGE with an OK button; answers T."))

(defmethod render ((self message-dialog))
  (h:div (:class "lt-dialog")
    (render-dialog-message self)
    (h:form ()
      (h:submit-button (:callback (lambda () (answer self t))) (translate "OK")))))

(defclass confirm-dialog (dialog) ()
  (:documentation "Asks the yes/no question in its :MESSAGE; answers T for Yes
or NIL for No."))

(defmethod render ((self confirm-dialog))
  (h:div (:class "lt-dialog")
    (render-dialog-message self)
    (h:form ()
      (h:submit-button (:callback (lambda () (answer self t))) (translate "Yes"))
      (h:submit-button (:callback (lambda () (answer self nil))) (translate "No")))))

(defclass input-dialog (dialog)
  ((value :initarg :value :initform "" :accessor dialog-value))
  (:documentation "Asks for a line of text, with its :MESSAGE as the prompt and
:VALUE (default \"\") as the text to start from; answers the string."))

(defmethod render ((self input-dialog))
  (h:div (:class "lt-dialog")
    (render-dialog-message self)
    (h:form ()
      (h:text-input (:value (dialog-value self) :label (or (dialog-message self) (translate "Answer"))
                   :callback (lambda (v) (setf (dialog-value self) v))
                   :autofocus t))
      (h:submit-button (:callback (lambda () (answer self (dialog-value self)))) (translate "OK")))))

(defclass choice-dialog (dialog)
  ((items :initarg :items :initform '() :reader dialog-items)
   (label-function :initarg :labels :initform #'princ-to-string :reader dialog-labels)
   (selected :initform nil :accessor dialog-selected))
  (:documentation "Asks for one of :ITEMS from a select list, with :MESSAGE as
the prompt; answers the item, or NIL on Cancel.  :LABELS is a function
giving each item's label (default PRINC-TO-STRING)."))

(defmethod render ((self choice-dialog))
  (h:div (:class "lt-dialog")
    (render-dialog-message self)
    (h:form ()
      (h:select-list (:items (dialog-items self) :label (or (dialog-message self) (translate "Choice"))
                    :labels (dialog-labels self)
                    :selected (dialog-selected self)
                    :callback (lambda (item) (setf (dialog-selected self) item))))
      (h:submit-button (:callback (lambda () (answer self (dialog-selected self)))) (translate "OK"))
      (h:cancel-button (:callback (lambda () (answer self nil))) (translate "Cancel")))))

(defclass login-dialog (dialog)
  ((username :initform "" :accessor dialog-username)
   (password :initform "" :accessor dialog-password))
  (:documentation "Asks for a username and password; answers them as a
cons (USERNAME . PASSWORD), or NIL on Cancel.  Its fields have the DOM ids
username and password."))

(defmethod render ((self login-dialog))
  (h:div (:class "lt-dialog lt-login")
    (render-dialog-message self)
    (h:form ()
      (h:label () (translate "Username") " "
        (h:text-input (:id "username" :value (dialog-username self)
                     :callback (lambda (v) (setf (dialog-username self) v)))))
      (h:label () (translate "Password") " "
        (h:password-input (:id "password"
                         :callback (lambda (v) (setf (dialog-password self) v)))))
      (h:submit-button (:callback (lambda ()
                                  (answer self (cons (dialog-username self)
                                                     (dialog-password self)))))
        (translate "Log in"))
      (h:cancel-button (:callback (lambda () (answer self nil))) (translate "Cancel")))))

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
      "Ask for one of ITEMS, with PROMPT; the item chosen, or NIL on Cancel.
Items are labelled with PRINC-TO-STRING.  A CALL.")

(defclass session-expired-notice (dialog) ()
  (:default-initargs
   :message (translate "Your session expired, so you are starting again from the beginning."))
  (:documentation "A ready-made EXPIRED-NOTICE for REGISTER-APPLICATION: it says the
session expired and answers when its Continue button is pressed."))

(defmethod render ((self session-expired-notice))
  (h:div (:class "lt-dialog lt-expired")
    (render-dialog-message self)
    (h:form ()
      (h:submit-button (:callback (lambda () (answer self t))) (translate "Continue")))))
