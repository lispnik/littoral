;;;; mail-demo.lisp — the outbox at work: queueing, retries, templates
;;;;
;;;; Served at /examples/mail by the members demo, which shares its database
;;;; and its pretend mail server: password reset mail lands here too.  The
;;;; "mail server" keeps what it is sent (a memory mailer), and can be
;;;; switched off, to watch the outbox try again with growing waits.

(defpackage #:littoral-mail-demo
  (:use #:cl #:littoral #:littoral.html)
  (:documentation "Sending mail through the outbox, with a pretend mail server.")
  (:export #:*mailbox* #:*server-down* #:start-demo-delivery #:deliver-now #:mail-root #:welcome-mail))

(in-package #:littoral-mail-demo)

;;; The pretend mail server

(defvar *mailbox* (littoral.mail:make-memory-mailer :keep 20) "What the pretend server was sent.")
(defvar *server-down* nil "True while the pretend server refuses connections.")

(defclass demo-mailer () ()
  (:documentation "Hands mail to *MAILBOX*, unless *SERVER-DOWN*."))

(defmethod littoral.mail:send-message ((mailer demo-mailer) from recipients message)
  (when *server-down*
    (error "Connection refused: the demo's mail server is switched off"))
  (littoral.mail:send-message *mailbox* from recipients message))

(defvar *demo-database* nil "The database spec the outbox lives in.")

(defun start-demo-delivery (database)
  "Create the outbox in DATABASE (a spec) and send it to the pretend server,
retrying after 5 seconds, then 10, 20…"
  (setf *demo-database* database)
  (let ((littoral.db:*database* database))
    (littoral.mail:create-mail-tables))
  (littoral.mail:start-mail-delivery :database database :mailer (make-instance 'demo-mailer)
                                     :interval 2 :retry-seconds 5 :attempts 5))

(defun deliver-now ()
  "Send what's due at once, without waiting for the delivery thread (for tests)."
  (let ((littoral.db:*database* *demo-database*))
    (littoral.mail:deliver-queued-mail :mailer (make-instance 'demo-mailer))))

;;; A template

(littoral.mail:define-mail welcome-mail (address)
  :from "Littoral demo <demo@example.org>"
  :to address
  :subject "Welcome to the Littoral demo"
  :html ((h1 (:style "font-size:22px;margin:0 0 12px") "Welcome aboard")
         (p () "This mail was made by " (code () "define-mail") ": HTML written with Littoral's tags, "
           "inside a layout, with a plain-text version made from it.")
         (ul () (li () "Queued in the database, in the same transaction as the action that sent it")
                (li () "Sent by a background thread, tried again when the server is down")
                (li () "MIME: UTF-8, quoted-printable, text and HTML — ünïcödé survives"))
         (p () (anchor (:href "https://lispnik.github.io/littoral/") "Read the documentation"))))

;;; The page

(defclass mail-root (component)
  ((to :initform "you@example.org" :accessor compose-to)
   (subject :initform "Hello from Littoral" :accessor compose-subject)
   (body :initform (format nil "Hi,~%~%This went through the outbox.~%") :accessor compose-body)
   (notice :initform nil :accessor mail-notice)
   (live :initform (make-instance 'mail-status) :reader mail-live))
  (:documentation "Compose, the outbox and the mailbox."))

(defmethod children ((self mail-root)) (list (mail-live self)))

(defclass mail-status (component updatable) ()
  (:documentation "The outbox and the mailbox, refreshed every two seconds."))

(defun queue (thunk)
  "Queue the mail THUNK makes, in the demo's database and a transaction, as
an application's action would."
  (let ((littoral.db:*database* *demo-database*))
    (littoral.db:with-transaction ()
      (littoral.mail:queue-mail (funcall thunk)))))

(defmethod render ((self mail-root))
  (h1 () "Mail")
  (p () "Mail is queued in the database and sent by a background thread, so pages never wait for "
    "a mail server, and mail that can't go now goes later. Here the mail server is a pretend one "
    "that keeps what it's sent; switch it off to watch the outbox try again, waiting longer each time.")
  (when (mail-notice self) (p (:class "lt-notice" :role "status") (text (mail-notice self))))
  (section ()
    (h2 () "Send something")
    (form ()
      (div (:class "lt-field")
        (label (:for "mail-to") "To")
        (text-input (:id "mail-to" :value (compose-to self) :callback (lambda (v) (setf (compose-to self) v)))))
      (div (:class "lt-field")
        (label (:for "mail-subject") "Subject")
        (text-input (:id "mail-subject" :value (compose-subject self)
                     :callback (lambda (v) (setf (compose-subject self) v)))))
      (div (:class "lt-field")
        (label (:for "mail-body") "Message")
        (text-area (:id "mail-body" :value (compose-body self) :rows 4
                    :callback (lambda (v) (setf (compose-body self) v)))))
      (div (:class "lt-buttons")
        (submit-button (:callback (lambda ()
                                    (handler-case
                                        (progn
                                          (queue (lambda () (littoral.mail:make-mail :from "Littoral demo <demo@example.org>"
                                                                                     :to (compose-to self)
                                                                                     :subject (compose-subject self)
                                                                                     :text (compose-body self))))
                                          (setf (mail-notice self) "Queued."))
                                      (error (e) (setf (mail-notice self) (princ-to-string e))))))
          "Queue it")
        (submit-button (:callback (lambda ()
                                    (handler-case
                                        (progn (queue (lambda () (welcome-mail (compose-to self))))
                                               (setf (mail-notice self) "Queued the welcome mail."))
                                      (error (e) (setf (mail-notice self) (princ-to-string e))))))
          "Queue the welcome template"))))
  (section ()
    (h2 () "The mail server")
    (p () (text (if *server-down* "Switched off: connections are refused, so mail waits in the outbox." "Running.")) " "
      (anchor (:callback (lambda () (setf *server-down* (not *server-down*))))
        (text (if *server-down* "Switch it on" "Switch it off"))))
    (p (:class "lt-help") "The pretend server is shared by everyone trying the demo."))
  (render (mail-live self)))

(defun relative-time (time)
  (let ((delta (- time (get-universal-time))))
    (cond ((<= delta 0) "now")
          (t (format nil "in ~Ds" delta)))))

(defmethod render ((self mail-status))
  (div (:periodical (periodical 2 :update self))
    (section ()
      (h2 () "Outbox")
      (let ((rows (let ((littoral.db:*database* *demo-database*)) (littoral.mail:outbox-messages :limit 10))))
        (if (null rows)
            (p () "Empty.")
            (table (:class "lt-table mail-outbox")
              (caption (:class "lt-visually-hidden") "Queued and sent mail, newest first")
              (tr () (th () "To") (th () "Subject") (th () "Status") (th () "Tries") (th () "Next try") (th () "Last error") (th () ""))
              (dolist (row rows)
                (let ((id (littoral.mail:outbox-id row))
                      (status (littoral.mail:outbox-status row)))
                  (tr ()
                    (td () (text (littoral.mail:outbox-recipients row)))
                    (td () (text (littoral.mail:outbox-subject row)))
                    (td () (span (:class (list "mail-status" (format nil "mail-~A" status))) (text status)))
                    (td () (text (littoral.mail:outbox-attempts row)))
                    (td () (text (if (string= status "queued") (relative-time (littoral.mail:outbox-next-attempt row)) "")))
                    (td () (text (or (littoral.mail:outbox-last-error row) "")))
                    (td () (unless (string= status "sent")
                             (anchor (:callback (lambda ()
                                                  (let ((littoral.db:*database* *demo-database*))
                                                    (littoral.mail:retry-mail id)))
                                      :aria-label (format nil "Retry the mail to ~A" (littoral.mail:outbox-recipients row)))
                               "Retry"))))))))))
    (section ()
      (h2 () "Delivered")
      (let ((messages (littoral.mail:mailer-messages *mailbox*)))
        (if (null messages)
            (p () "Nothing yet.")
            (dolist (message messages)
              (let* ((mime (littoral.mail:sent-message-text message))
                     (html (littoral.mail:message-html mime)))
                (details (:class "members-mail" :open (and (eq message (first messages)) t))
                  (summary ()
                    (strong () (text (littoral.mail:message-header mime "Subject")))
                    (text (format nil " — to ~{~A~^, ~}" (littoral.mail:sent-message-recipients message))))
                  (pre () (text (littoral.mail:message-text mime)))
                  (when html
                    (tag "iframe" (:class "mail-preview" :sandbox "" :srcdoc html
                                   :title (format nil "HTML version of ~A" (littoral.mail:message-header mime "Subject")))))
                  (let ((link (cl-ppcre:scan-to-strings "https?://\\S+/reset\\?token=\\S+" (littoral.mail:message-text mime))))
                    (when link (p () (anchor (:href link) "Open the reset link"))))
                  (details ()
                    (summary () "The message as sent")
                    (pre (:class "mail-source" :tabindex "0") (text mime)))))))))))

(defmethod style ((self mail-root))
  ".mail-status { padding: .05rem .45rem; border-radius: 99px; font-size: .85rem; background: var(--lt-panel); }
.mail-sent { background: #d9f2df; color: #14532d; }
.mail-failed { background: #fde2e1; color: #7f1d1d; }
.mail-queued, .mail-sending { background: #fff1c2; color: #5c4400; }
.members-mail { border: 1px solid var(--lt-border); border-radius: 6px; padding: .3rem .8rem; margin: .5rem 0; }
.members-mail pre { white-space: pre-wrap; font-size: .85rem; }
.mail-source { max-height: 16rem; overflow: auto; }
.mail-preview { width: 100%; height: 22rem; border: 1px solid var(--lt-border); border-radius: 6px; background: #fff; }
.mail-outbox td { vertical-align: top; }")
