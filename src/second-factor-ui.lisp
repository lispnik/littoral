;;;; second-factor-ui.lisp — the second step of signing in, and security settings

(in-package #:littoral.auth)

;;; The second step

(defun finish-second-step (self user)
  (setf (sign-in-pending self) nil (sign-in-code self) "")
  (log-in user :remember (sign-in-remember self))
  (answer self user))

(defun try-second-step (self)
  "Check the code typed: the authenticator app's, or a recovery code."
  (let* ((user (find-user-by-id (sign-in-pending self)))
         (code (string-trim " " (sign-in-code self)))
         (name (user-name user)))
    (setf (sign-in-code self) "")
    (cond ((locked-p name)
           (setf (sign-in-message self) (translate "Too many failed attempts; try again in a minute.")))
          ((sign-in-recovery-p self)
           (if (use-recovery-code user code)
               (finish-second-step self user)
               (progn (note-attempt name nil)
                      (setf (sign-in-message self) (translate "That code isn't right.")))))
          (t
           (let* ((factor (first (user-factors user "totp")))
                  (step (and factor (verify-totp (factor-data factor) code :after (factor-counter factor)))))
             (if step
                 (progn (setf (factor-counter factor) step)
                        (db-save factor)
                        (note-attempt name t)
                        (finish-second-step self user))
                 (progn (note-attempt name nil)
                        (setf (sign-in-message self) (translate "That code isn't right.")))))))))

(defun passkey-signs-in (self &optional expected-user)
  "A callback for a passkey response: check it, then sign its user in."
  (passkey-callback
   (lambda (json)
     (let ((challenge (shiftf (sign-in-challenge self) (new-challenge))))
       (handler-case
           (let ((user (verify-assertion challenge (com.inuoe.jzon:parse json) expected-user)))
             (finish-second-step self user))
         (error (e)
           (declare (ignorable e))
           (setf (sign-in-message self) (translate "That passkey didn't work."))))))))

(defun render-second-step (self)
  (let* ((user (find-user-by-id (sign-in-pending self)))
         (totp (and user (user-factors user "totp")))
         (passkeys (and user (user-factors user "passkey"))))
    (h2 () (translate "Check it's you"))
    (when (sign-in-message self)
      (p (:class "lt-validation-error" :role "alert") (text (sign-in-message self))))
    (when (or totp (sign-in-recovery-p self))
      (form ()
        (div (:class "lt-field")
          (label (:for "sign-in-code")
            (if (sign-in-recovery-p self) (translate "A recovery code") (translate "The code from your authenticator app")))
          (text-input (:id "sign-in-code" :value "" :autocomplete "one-time-code" :required t :autofocus t
                       :inputmode (unless (sign-in-recovery-p self) "numeric")
                       :callback (lambda (v) (setf (sign-in-code self) v)))))
        (div (:class "lt-buttons")
          (submit-button (:callback (lambda () (try-second-step self))) (translate "Verify"))
          (cancel-button (:callback (lambda () (setf (sign-in-pending self) nil (sign-in-message self) nil)))
            (translate "Cancel")))))
    (when passkeys
      (p () (passkey-button :get (assertion-options (sign-in-challenge self) user)
                            (passkey-signs-in self user) (translate "Use your passkey")
                            :status-id "lt-passkey-status"))
      (p (:id "lt-passkey-status" :role "status")))
    (unless (sign-in-recovery-p self)
      (p () (anchor (:callback (lambda () (setf (sign-in-recovery-p self) t (sign-in-message self) nil)))
              (translate "Use a recovery code instead"))))))

;;; Security settings

(defclass security-settings (restricted component littoral:updatable)
  ((totp-secret :initform nil :accessor settings-totp-secret :documentation "A secret being set up.")
   (code :initform "" :accessor settings-code)
   (codes :initform nil :accessor settings-codes :documentation "Recovery codes just made, shown once.")
   (challenge :initform (new-challenge) :accessor settings-challenge)
   (message :initform nil :accessor settings-message))
  (:documentation "Second factors for the signed-in user: an authenticator app,
passkeys and recovery codes."))

(defmethod states ((self security-settings)) (list self))

(defun confirm-totp (self)
  (let* ((user (current-user))
         (secret (settings-totp-secret self))
         (step (verify-totp secret (settings-code self))))
    (setf (settings-code self) "")
    (if step
        (progn
          (db-insert (make-instance 'auth-factor :user-id (princ-to-string (user-id user)) :kind "totp"
                                                 :name (translate "Authenticator app") :data secret :counter step
                                                 :created (get-universal-time)))
          (setf (settings-totp-secret self) nil (settings-message self) nil)
          (when (zerop (recovery-codes-left user))
            (setf (settings-codes self) (make-recovery-codes user)))
          (littoral:toast (translate "Your authenticator app is set up.") :kind :success))
        (setf (settings-message self) (translate "That code isn't right.")))))

(defun remove-factor (factor)
  (db-delete factor)
  (littoral:toast (translate "Removed.")))

(defmethod render ((self security-settings))
  (let* ((user (current-user))
         (totp (first (user-factors user "totp")))
         (passkeys (user-factors user "passkey")))
    (div (:class "lt-security")
      (when (settings-message self)
        (p (:class "lt-validation-error" :role "alert") (text (settings-message self))))
      ;; Recovery codes just made: shown this once.
      (when (settings-codes self)
        (div (:class "lt-dialog")
          (p () (strong () (translate "Your recovery codes.")) " "
            (translate "Keep them somewhere safe: each signs you in once if you lose your other ways in. They won't be shown again."))
          (ul (:class "lt-recovery-codes") (dolist (code (settings-codes self)) (li () (code () (text code)))))
          (p () (anchor (:callback (lambda () (setf (settings-codes self) nil))) (translate "I've kept them")))))
      (h3 () (translate "Authenticator app"))
      (cond (totp
             (p () (translate "On: signing in with your password also asks for its code.") " "
               (anchor (:callback (lambda () (remove-factor totp))) (translate "Turn off"))))
            ((settings-totp-secret self)
             (let ((secret (settings-totp-secret self)))
               (p () (translate "Scan this with your authenticator app, or type in the key, then enter the code it shows."))
               (littoral.html:raw (qr-svg (totp-uri secret (user-name user)
                                                    (or (application-title *application*) "Littoral"))
                                          :label (translate "QR code for your authenticator app")))
               (p () (translate "Key:") " " (code () (text secret)))
               (form ()
                 (div (:class "lt-field")
                   (label (:for "totp-code") (translate "The code from your authenticator app"))
                   (text-input (:id "totp-code" :value "" :autocomplete "one-time-code" :inputmode "numeric"
                                :callback (lambda (v) (setf (settings-code self) v)))))
                 (div (:class "lt-buttons")
                   (submit-button (:callback (lambda () (confirm-totp self))) (translate "Turn on"))
                   (cancel-button (:callback (lambda () (setf (settings-totp-secret self) nil))) (translate "Cancel"))))))
            (t (p () (translate "Off.") " "
                 (anchor (:callback (lambda () (setf (settings-totp-secret self) (new-totp-secret))))
                   (translate "Set up an authenticator app")))))
      (h3 () (translate "Passkeys"))
      (if passkeys
          (ul ()
            (dolist (factor passkeys)
              (let ((factor factor))
                (li () (text (factor-name factor)) " "
                  (anchor (:callback (lambda () (remove-factor factor))) (translate "Remove"))))))
          (p () (translate "None yet. A passkey signs you in with your fingerprint, face or device PIN, without a password.")))
      (p () (passkey-button :create (registration-options user (settings-challenge self))
                            (passkey-callback
                             (lambda (json)
                               (let ((challenge (shiftf (settings-challenge self) (new-challenge))))
                                 (handler-case
                                     (progn (add-passkey user challenge json
                                                         :name (format nil "~A ~D" (translate "Passkey") (1+ (length passkeys))))
                                            (littoral:toast (translate "Passkey added.") :kind :success))
                                   (error () (setf (settings-message self) (translate "That passkey couldn't be added.")))))))
                            (translate "Add a passkey") :status-id "lt-passkey-status" :update self))
      (p (:id "lt-passkey-status" :role "status"))
      (h3 () (translate "Recovery codes"))
      (p () (text (translate-plural (recovery-codes-left user) "~D code left" "~D codes left")) " "
        (anchor (:callback (lambda () (setf (settings-codes self) (make-recovery-codes user))))
          (translate "Make new codes"))))))
