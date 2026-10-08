;;;; modal.lisp — overlay dialogs and toasts

(in-package #:littoral/tests)

(def-suite modal :in littoral)
(in-suite modal)

(defclass modal-host (component updatable)
  ((answer :initform nil :accessor host-answer))
  (:documentation "A page that opens dialogs over itself and shows toasts."))

(defmethod states ((self modal-host)) (list self))

(defmethod render ((self modal-host))
  (p () "Behind the dialog. Answer: " (text (prin1-to-string (host-answer self))))
  (anchor (:callback (lambda ()
                       (show-modal (make-instance 'confirm-dialog :message "Really?")
                                   :title "Confirm"
                                   :on-answer (lambda (yes) (setf (host-answer self) yes)))))
    "ask")
  (anchor (:callback (lambda ()
                       (show-modal (make-instance 'message-dialog :message "You must read this.")
                                   :closable nil)))
    "insist")
  (anchor (:callback (lambda () (toast "Saved." :kind :success))) "save")
  (button (:id "ajax-toast" :on-click (ajax :callback (lambda () (toast "Saved by AJAX.")) :update self)) "ajax"))

(test modal-over-the-page
  (with-fresh-applications (("/m" 'modal-host :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/m")
      (click b "ask")
      ;; The page stays, inert, behind the dialog.
      (is (has-text-p b "Behind the dialog."))
      (is (search "<div class=\"lt-behind-modal\" inert aria-hidden=\"true\">" (browser-html b)))
      (is (search "<dialog class=\"lt-modal\" open aria-modal=\"true\" aria-label=\"Confirm\"" (browser-html b)))
      (is (has-text-p b "Really?"))
      (press b "Yes")
      (is (has-text-p b "Answer: T"))
      (is (not (search "<dialog" (browser-html b))))
      ;; Closing answers NIL.
      (click b "ask")
      (click b "×")
      (is (has-text-p b "Answer: NIL"))
      ;; A dialog that must be answered has no close button.
      (click b "insist")
      (is (search "data-lt-modal=\"fixed\"" (browser-html b)))
      (is (not (find-link b "×")))
      (press b "OK")
      (is (not (search "<dialog" (browser-html b)))))))

(test modal-backtracks
  (with-fresh-applications (("/m" 'modal-host :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/m")
      (let ((before (browser-url b)))
        (click b "ask")
        (let ((with-dialog (browser-url b)))
          (back-to b before)
          (is (not (search "<dialog" (browser-html b))))
          (back-to b with-dialog)
          (is (has-text-p b "Really?")))))))

(defclass modal-flow (task) ()
  (:documentation "A flow that asks in a dialog over the page."))

(define-flow modal-flow (self)
  (let ((name (call-modal (make-instance 'input-dialog :message "Your name?") "Name")))
    (call self (make-instance 'message-dialog :message (format nil "Hello, ~A." name)))))

(test call-modal-in-a-flow
  (with-fresh-applications (("/f" 'modal-flow :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/f")
      (is (search "<dialog" (browser-html b)))
      (answer-input b "Ada")
      (is (has-text-p b "Hello, Ada."))
      (is (not (search "<dialog" (browser-html b)))))))

(test toasts
  (with-fresh-applications (("/m" 'modal-host :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/m")
      (click b "save")
      (is (search "<div class=\"lt-toast lt-toast-success\">Saved.</div>" (browser-html b)))
      ;; Shown once.
      (visit b (browser-url b))
      (is (not (search "Saved." (browser-html b))))
      ;; AJAX responses carry them.
      (let* ((spec (element-spec b "ajax-toast" "on-click"))
             (json (ajax-request b (first spec) (rest spec))))
        (is (search "\"toasts\":[{\"kind\":\"info\",\"text\":\"Saved by AJAX.\"}]" json))))))

(defclass toast-push-page (component) ()
  (:documentation "Subscribes to something, so it has an event stream."))

(defvar *toast-channel* (make-channel "toast test"))

(defmethod subscriptions ((self toast-push-page)) (list *toast-channel*))

(defmethod render ((self toast-push-page)) (p () "Listening."))

(test toasts-by-push
  (with-fresh-applications (("/t" 'toast-push-page :mode :deployment))
    (let ((b (make-instance 'browser)) (sink (make-instance 'sink)))
      (visit b "/t")
      (let ((stream (open-stream b sink))
            (session (first (list-sessions (find-application "/t")))))
        (is (wait-for (lambda () (search "retry:" (sink-text sink)))))
        ;; From another thread, as a background job would.
        (sb-thread:join-thread
         (sb-thread:make-thread (lambda () (toast "Job finished." :session session))))
        (is (wait-for (lambda () (search "event: toast" (sink-text sink)))))
        (is (search "Job finished." (sink-text sink)))
        (close-event-streams)
        (is (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))))
