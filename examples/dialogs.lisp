;;;; dialogs.lisp — dialogs over the page, and toasts

(in-package #:littoral-examples)

(defclass dialogs-demo (component updatable)
  ((choice :initform nil :accessor demo-choice))
  (:documentation "Opens dialogs over itself and shows toasts."))

(defmethod states ((self dialogs-demo)) (list self))

(defmethod render ((self dialogs-demo))
  (h:h1 () "Dialogs and toasts")
  (h:p () "A dialog over the page keeps the page in view but out of reach until it answers. "
    "Press Esc, or the ×, to close one.")
  (h:p ()
    (h:anchor (:id "open-dialog"
             :callback (lambda ()
                         (show-modal (make-instance 'choice-dialog :message "Pick a colour"
                                                                   :items '("Red" "Green" "Blue"))
                                     :title "Pick a colour"
                                     :on-answer (lambda (colour)
                                                  (setf (demo-choice self) colour)
                                                  (when colour (toast (format nil "You picked ~A." colour)
                                                                      :kind :success))))))
      "Open a dialog"))
  (h:p () "Chosen: " (h:strong () (h:text (or (demo-choice self) "nothing yet"))))
  (h:p () (h:button (:id "toast-button" :on-click (ajax :callback (lambda () (toast "Hello from the server.")) :update self))
          "Show a toast")))
