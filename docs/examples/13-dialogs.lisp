;;;; The examples for the ready-made dialogs and Seaside's inform, confirm, request and choose.

;;;; Example: littoral:inform littoral:confirm littoral:message-dialog littoral:confirm-dialog
;;; In a flow, confirm waits for Yes (T) or No (NIL), and inform for OK.  They show a confirm-dialog and a message-dialog.
(defclass pump-out (task)
  ((emptied :initform 0 :accessor emptied)))
(define-flow pump-out (self)
  (when (confirm self "Pump out the bilge?")
    (incf (emptied self))
    (inform self "Bilge pumped.")))
(with-fresh-applications (("/pump" 'pump-out :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/pump")
    (let ((question (body-text b)))
      (press b "Yes")
      (list question (body-text b)))))
;; ⇒ ("Pump out the bilge? Yes No" "Bilge pumped. OK")

;;;; Example: littoral:request-input littoral:input-dialog
;;; request-input shows an input-dialog and answers the text typed.  Its field is labelled with the question, so the fake browser finds it by that.
(defclass sign-on (task) ())
(define-flow sign-on (self)
  (let ((name (request-input self "Your name?" "Sailor")))
    (inform self (format nil "Welcome aboard, ~A." name))))
(with-fresh-applications (("/sign-on" 'sign-on :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/sign-on")
    (let ((default (attr (attributes (cl-ppcre:scan-to-strings "<input[^>]*>" (browser-html b))) "value")))
      (fill-in b "Your name?" "Ada")
      (press b "OK")
      (list default (body-text b)))))
;; ⇒ ("Sailor" "Welcome aboard, Ada. OK")

;;;; Example: littoral:choose-from littoral:choice-dialog
;;; choose-from shows a choice-dialog listing the items; it answers the item chosen, or NIL on Cancel.
(defclass charter (task) ())
(define-flow charter (self)
  (let ((boat (choose-from self '(:dinghy :ketch :yawl) "Which boat?")))
    (inform self (if boat
                     (format nil "You chartered the ~(~A~)." boat)
                     "No boat today."))))
(with-fresh-applications (("/charter" 'charter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/charter")
    (let ((choices (body-text b)))
      (select-option b "Which boat?" "KETCH")
      (press b "OK")
      (let ((chosen (body-text b)))
        (press b "OK")                              ; the flow starts again
        (press b "Cancel")
        (list choices chosen (body-text b))))))
;; ⇒ ("Which boat? DINGHY KETCH YAWL OK Cancel" "You chartered the ketch. OK" "No boat today. OK")

;;;; Example: littoral:choice-dialog
;;; Made directly, a choice-dialog takes :labels, a function naming each item.
(defclass berth-picker (component)
  ((berth :initform nil :accessor berth)))
(defmethod states ((self berth-picker)) (list self))
(defmethod render ((self berth-picker))
  (h:p () "Berth: " (h:text (princ-to-string (berth self))))
  (h:anchor (:callback (lambda ()
                       (show self (make-instance 'choice-dialog
                                                 :message "Which berth?"
                                                 :items '(1 2 3)
                                                 :labels (lambda (n) (format nil "Berth ~D" n)))
                             :on-answer (lambda (n) (setf (berth self) n)))))
    "Choose"))
(with-fresh-applications (("/berth" 'berth-picker :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/berth")
    (click b "Choose")
    (let ((choices (body-text b)))
      (select-option b "Which berth?" "Berth 3")
      (press b "OK")
      (list choices (body-text b)))))
;; ⇒ ("Which berth? Berth 1 Berth 2 Berth 3 OK Cancel" "Berth: 3 Choose")

;;;; Example: littoral:login-dialog
;;; Answers (username . password), or NIL on Cancel.  Its fields have the ids username and password.
(defclass crew-room (component)
  ((user :initform nil :accessor user)))
(defmethod states ((self crew-room)) (list self))
(defmethod render ((self crew-room))
  (h:p () "Signed in: " (h:text (or (user self) "nobody")))
  (h:anchor (:callback (lambda ()
                       (show self (make-instance 'login-dialog :message "Crew only")
                             :on-answer (lambda (credentials)
                                          (when (and credentials (equal (rest credentials) "knots"))
                                            (setf (user self) (first credentials)))))))
    "Sign in"))
(with-fresh-applications (("/crew-room" 'crew-room :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/crew-room")
    (click b "Sign in")
    (fill-in b "username" "ada")
    (fill-in b "password" "knots")
    (press b "Log in")
    (body-text b)))
;; ⇒ "Signed in: ada Sign in"
