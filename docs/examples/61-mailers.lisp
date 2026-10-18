;;;; Mailers: sending mail now, keeping it in memory, printing it, and SMTP servers.

;;;; Example: littoral.mail:send-mail littoral.mail:make-memory-mailer littoral.mail:memory-mailer littoral.mail:mailer-messages littoral.mail:sent-message littoral.mail:sent-message-from littoral.mail:sent-message-recipients littoral.mail:sent-message-text littoral.mail:sent-message-time
;;; A memory mailer keeps what it is given, newest first, so a test can look at what was sent.
(let ((mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:send-mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                                    :to "Ada <ada@example.org>" :bcc "orders@example.org"
                                                    :subject "Shipped" :text "On its way.")
                           :mailer mailer)
  (let ((sent (first (littoral.mail:mailer-messages mailer))))
    (list (littoral.mail:sent-message-from sent)
          (littoral.mail:sent-message-recipients sent)
          (littoral.mail:message-header (littoral.mail:sent-message-text sent) "Subject")
          (integerp (littoral.mail:sent-message-time sent)))))
;; ⇒ ("shop@example.org" ("ada@example.org" "orders@example.org") "Shipped" T)

;;;; Example: littoral.mail:*mailer* littoral.mail:clear-mailer
;;; SEND-MAIL uses *MAILER* unless given one.
(let ((littoral.mail:*mailer* (littoral.mail:make-memory-mailer :keep 10)))
  (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :text "One"))
  (littoral.mail:send-mail (littoral.mail:make-mail :to "bob@example.org" :text "Two"))
  (list (length (littoral.mail:mailer-messages littoral.mail:*mailer*))
        (progn (littoral.mail:clear-mailer littoral.mail:*mailer*)
               (littoral.mail:mailer-messages littoral.mail:*mailer*))))
;; ⇒ (2 NIL)

;;;; Example: littoral.mail:log-mailer
;;; The default mailer prints each mail instead of sending it, to *ERROR-OUTPUT* unless given a :STREAM.
(uiop:split-string
 (with-output-to-string (out)
   (littoral.mail:send-mail (littoral.mail:make-mail :from "shop@example.org" :to "ada@example.org"
                                                     :subject "Shipped" :text "On its way.")
                            :mailer (make-instance 'littoral.mail:log-mailer :stream out)))
 :separator '(#\Newline))
;; ⇒ ("--- mail from shop@example.org to ada@example.org: Shipped" "On its way." "---" "")

;;;; Example: littoral.mail:send-message
;;; A mailer is anything with a SEND-MESSAGE method.  This one, for a staging server, sends everything to one address through another mailer.
(defclass staging-mailer ()
  ((inner :initarg :inner :reader inner-mailer)))
(defmethod littoral.mail:send-message ((mailer staging-mailer) from recipients message)
  (declare (ignore recipients))
  (littoral.mail:send-message (inner-mailer mailer) from '("staging@example.org") message))
(let* ((kept (littoral.mail:make-memory-mailer))
       (littoral.mail:*mailer* (make-instance 'staging-mailer :inner kept)))
  (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :subject "Hello" :text "Hi"))
  (littoral.mail:sent-message-recipients (first (littoral.mail:mailer-messages kept))))
;; ⇒ ("staging@example.org")

;;;; Example: littoral.mail:make-smtp-mailer littoral.mail:smtp-mailer
;;; Making a mailer doesn't connect: it connects when it first sends, over STARTTLS on port 587 unless told otherwise.
(littoral.mail:make-smtp-mailer :host "smtp.example.org" :username "app" :password "secret")
;; ⇒ #<LITTORAL.MAIL:SMTP-MAILER smtp.example.org:587 starttls>
(littoral.mail:make-smtp-mailer :host "smtp.example.org" :security :tls :pool-size nil)
;; ⇒ #<LITTORAL.MAIL:SMTP-MAILER smtp.example.org:465 tls>

;;;; Example: littoral.mail:smtp-mailer-from-url
;;; The scheme says how to connect: smtp (STARTTLS), smtps (TLS) or smtp+insecure (neither).  The user name and password are URL-decoded.
(littoral.mail:smtp-mailer-from-url "smtps://app:s%40cret@smtp.example.org")
;; ⇒ #<LITTORAL.MAIL:SMTP-MAILER smtp.example.org:465 tls>
(littoral.mail:smtp-mailer-from-url "smtp+insecure://localhost:2525" :timeout 5)
;; ⇒ #<LITTORAL.MAIL:SMTP-MAILER localhost:2525 none>

;;;; Example: littoral.mail:smtp-error littoral.mail:smtp-error-code littoral.mail:smtp-error-permanent-p
;;; A server's refusal is an SMTP-ERROR with its reply code; a 5xx refusal is permanent, so trying again won't help.  (Tests make a refusal with the smtp library's MAKE-REPLY.)
(defclass refusing-mailer () ((code :initarg :code :reader refusal-code)))
(defmethod littoral.mail:send-message ((mailer refusing-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error (if (>= (refusal-code mailer) 500) 'smtp:smtp-permanent-error 'smtp:smtp-transient-error)
         :reply (smtp:make-reply (refusal-code mailer) '("Refused"))))
(flet ((try (code)
         (handler-case (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hi")
                                                :mailer (make-instance 'refusing-mailer :code code))
           (littoral.mail:smtp-error (e)
             (list (littoral.mail:smtp-error-code e) (littoral.mail:smtp-error-permanent-p e))))))
  (list (try 550) (try 421)))
;; ⇒ ((550 T) (421 NIL))

;;;; Example: littoral.mail:smtp-error-code littoral.mail:smtp-error-permanent-p
;;; A mail that can't be sent as it is fails for good too, though no server replied.
(handler-case (littoral.mail:address-spec "not an address")
  (littoral.mail:smtp-error (e)
    (list (littoral.mail:smtp-error-code e) (littoral.mail:smtp-error-permanent-p e))))
;; ⇒ (NIL T)
