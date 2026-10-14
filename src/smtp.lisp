;;;; smtp.lisp — sending mail over SMTP
;;;;
;;;;   (make-smtp-mailer :host "smtp.example.org" :username "app" :password "…")   ; STARTTLS on 587
;;;;   (smtp-mailer-from-url "smtps://app:secret@smtp.example.org")             ; TLS on 465
;;;;
;;;; The conversation is the smtp library's (github.com/lispnik/smtp).  With
;;;; :STARTTLS (the default) the connection must turn into TLS before anything
;;;; else is said, and the server's certificate must match its name; a server
;;;; that doesn't offer STARTTLS is refused, never used in the clear.  :NONE is
;;;; for a relay on the same machine, and won't send a password unless
;;;; ALLOW-INSECURE-AUTH is true.  With :DKIM, each message is signed as it
;;;; goes:
;;;;
;;;;   (make-smtp-mailer :host … :dkim (smtp/dkim:make-dkim-signer :domain "example.org" :selector "mail"
;;;;                                                              :private-key #p"dkim.pem"))

(in-package #:littoral.mail)

(defun smtp-error-code (condition)
  "The server's reply code in CONDITION, such as 550, or NIL when the
conversation itself failed.  When recipients were refused, the first refusal's."
  (typecase condition
    (smtp:smtp-reply-error
     (let ((reply (smtp:smtp-error-reply condition)))
       (and reply (smtp:reply-code reply))))
    (smtp:smtp-recipients-rejected
     (let ((rejected (smtp:smtp-recipients-rejected-rejected condition)))
       (and rejected (smtp:reply-code (cdr (first rejected))))))))

(defun smtp-error-permanent-p (condition)
  "True when trying CONDITION's mail again won't change anything: a refusal
(a 5xx reply, or every recipient refused with one), or a mail that can't be
sent as it is."
  (typecase condition
    (smtp:smtp-recipients-rejected
     (every (lambda (rejection) (>= (smtp:reply-code (cdr rejection)) 500))
            (smtp:smtp-recipients-rejected-rejected condition)))
    (smtp:smtp-reply-error
     (let ((code (smtp-error-code condition)))
       (and code (>= code 500))))
    ((or smtp:mail-format-error smtp:smtp-message-too-large) t)))

(defclass smtp-mailer ()
  ((host :initarg :host :reader smtp-host)
   (port :initarg :port :reader smtp-port)
   (security :initarg :security :reader smtp-security :documentation ":STARTTLS, :TLS or :NONE.")
   (username :initarg :username :initform nil :reader smtp-username)
   (password :initarg :password :initform nil :reader smtp-password)
   (helo :initarg :helo :reader smtp-helo)
   (verify :initarg :verify :initform t :reader smtp-verify)
   (ca-file :initarg :ca-file :initform nil :reader smtp-ca-file)
   (timeout :initarg :timeout :initform 30 :reader smtp-timeout)
   (allow-insecure-auth :initarg :allow-insecure-auth :initform nil :reader smtp-allow-insecure-auth)
   (dkim :initarg :dkim :initform nil :reader smtp-dkim
         :documentation "A DKIM signer from SMTP/DKIM:MAKE-DKIM-SIGNER, a list of them, or NIL.")
   (pool-size :initarg :pool-size :initform 2 :reader smtp-pool-size
              :documentation "How many connections to keep for reuse; NIL for one per message.")
   (pool :initform nil :accessor smtp-pool)
   (pool-lock :initform (sb-thread:make-mutex :name "smtp mailer pool") :reader smtp-pool-lock))
  (:documentation "Sends mail through an SMTP server: MAKE-SMTP-MAILER makes one."))

(defmethod print-object ((mailer smtp-mailer) stream)
  (print-unreadable-object (mailer stream :type t)
    (format stream "~A:~D ~(~A~)" (smtp-host mailer) (smtp-port mailer) (smtp-security mailer))))

(defun make-smtp-mailer (&key (host "localhost") port (security :starttls) username password
                           (helo (machine-instance)) (verify t) ca-file (timeout 30) allow-insecure-auth dkim
                           (pool-size 2))
  "A mailer sending through the SMTP server at HOST.  SECURITY is :STARTTLS
(port 587 by default), :TLS (465) or :NONE (25, for a relay on this machine).
With USERNAME, signs in with the strongest AUTH method the server offers;
without TLS only when ALLOW-INSECURE-AUTH is true.  The server's certificate
is checked against the system's authorities, or CA-FILE's, unless VERIFY is NIL.
TIMEOUT, in seconds, bounds connecting and each step of the conversation.
DKIM, a signer from SMTP/DKIM:MAKE-DKIM-SIGNER or a list of them (RSA and
Ed25519, say), signs each message as it is sent.  Up to POOL-SIZE
connections are kept open and reused, so a batch of mail doesn't connect
for each message; NIL connects for each one."
  (check-type security (member :starttls :tls :none))
  (make-instance 'smtp-mailer :host host :security security :username username :password password
                              :helo helo :verify verify :ca-file ca-file :timeout timeout
                              :allow-insecure-auth allow-insecure-auth :dkim dkim :pool-size pool-size
                              :port (or port (ecase security (:starttls 587) (:tls 465) (:none 25)))))

(defun smtp-mailer-from-url (url &rest options)
  "A mailer from URL: smtp://user:password@host:port (STARTTLS), smtps://… (TLS)
or smtp+insecure://… (neither).  OPTIONS go to MAKE-SMTP-MAILER."
  (let* ((uri (quri:uri url))
         (userinfo (quri:uri-userinfo uri))
         (colon (and userinfo (position #\: userinfo)))
         (security (cond ((string-equal (quri:uri-scheme uri) "smtp") :starttls)
                         ((string-equal (quri:uri-scheme uri) "smtps") :tls)
                         ((string-equal (quri:uri-scheme uri) "smtp+insecure") :none)
                         (t (error "Not an SMTP URL: ~A" url)))))
    (apply #'make-smtp-mailer :host (quri:uri-host uri) :port (quri:uri-port uri) :security security
                              :username (and userinfo (quri:url-decode (if colon (subseq userinfo 0 colon) userinfo)))
                              :password (and colon (quri:url-decode (subseq userinfo (1+ colon))))
                              options)))

(defun connection-options (mailer)
  "OPEN-CONNECTION's options for MAILER's server."
  (list :port (smtp-port mailer)
        :tls (ecase (smtp-security mailer) (:starttls :starttls) (:tls :implicit) (:none :none))
        :credentials (and (smtp-username mailer)
                          (list :username (smtp-username mailer) :password (or (smtp-password mailer) "")))
        :allow-insecure-auth (smtp-allow-insecure-auth mailer)
        :verify (smtp-verify mailer) :ca-file (smtp-ca-file mailer)
        :local-name (smtp-helo mailer)
        :connect-timeout (smtp-timeout mailer) :timeout (smtp-timeout mailer)
        :data-timeout (smtp-timeout mailer)))

(defun mailer-pool (mailer)
  "MAILER's connection pool, made when first needed."
  (sb-thread:with-mutex ((smtp-pool-lock mailer))
    (or (smtp-pool mailer)
        (setf (smtp-pool mailer)
              (apply #'smtp:make-connection-pool (smtp-host mailer)
                     :max-connections (smtp-pool-size mailer)
                     :wait-timeout (smtp-timeout mailer)
                     (connection-options mailer))))))

(defun close-smtp-mailer (mailer)
  "Close the connections MAILER keeps open; it opens new ones when next used."
  (let ((pool (sb-thread:with-mutex ((smtp-pool-lock mailer))
                (shiftf (smtp-pool mailer) nil))))
    (when pool (ignore-errors (smtp:close-connection-pool pool)))))

(defmethod send-message ((mailer smtp-mailer) from recipients message)
  (let ((data (if (smtp-dkim mailer)
                  (smtp:sign-message-octets (smtp-dkim mailer) (utf-8 message))
                  message)))
    (flet ((send (connection)
             (smtp:send-raw-message connection data :envelope-from from :recipients recipients)))
      (if (smtp-pool-size mailer)
          ;; A connection the server dropped meanwhile fails this send; the
          ;; outbox tries again, over a new one.
          (smtp:with-pooled-connection (connection (mailer-pool mailer))
            (send connection))
          (let ((connection (apply #'smtp:open-connection (smtp-host mailer) (connection-options mailer))))
            (unwind-protect (send connection)
              ;; A connection that failed partway can't always say QUIT; the first error is the one to report.
              (ignore-errors (smtp:close-connection connection))))))))
