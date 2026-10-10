;;;; mail.lisp — messages, SMTP (against a pretend server), templates and the outbox

(in-package #:littoral/tests)

(def-suite mail :in littoral)
(in-suite mail)

(defun crlf (&rest lines)
  (format nil "~{~A~C~C~}" (loop for line in lines append (list line #\Return #\Newline))))

(test mime-messages
  (let* ((mail (littoral.mail:make-mail :from "Zoë Café <zoe@example.org>"
                                        :to '("Ada Lovelace <ada@example.org>" "bob@example.org")
                                        :bcc "secret@example.org"
                                        :subject "Ça va? Your order — №42"
                                        :text (format nil "Hello Ada,~%~%A = sign, ünïcödé, and a line ~A end.~%.starts with a dot  "
                                                      (make-string 120 :initial-element #\x))
                                        :html "<p>Hello <b>Ada</b></p>"))
         (message (littoral.mail:mail-string mail)))
    ;; CRLF throughout, no line too long for SMTP, no raw 8-bit.
    (is (null (cl-ppcre:scan "[^\\r]\\n" message)))
    (is (every (lambda (line) (<= (length line) 78)) (cl-ppcre:split "\\r\\n" message)))
    (is (every (lambda (c) (< (char-code c) 128)) message))
    (is (string= "Ça va? Your order — №42" (littoral.mail:message-header message "Subject")))
    (is (search "Ada Lovelace <ada@example.org>" (littoral.mail:message-header message "To")))
    (is (search "Zoë Café" (littoral.mail:message-header message "From")))
    (is (null (search "secret" message)) "Bcc isn't written")
    (is (equal '("ada@example.org" "bob@example.org" "secret@example.org") (littoral.mail:mail-recipients mail)))
    (is (string= (format nil "~A~%" (littoral.mail:mail-text mail))
                 (littoral.mail:message-text message))
        "The text comes back exactly, trailing spaces and all")
    (is (string= "<p>Hello <b>Ada</b></p>" (string-right-trim '(#\Newline) (littoral.mail:message-html message))))))

(test mail-headers-refuse-line-breaks
  (signals error (littoral.mail:make-mail :to "ada@example.org" :subject (format nil "Hi~%Bcc: all@example.org") :text "x"))
  (signals error (littoral.mail:make-mail :to (format nil "ada@example.org~C~CRCPT TO:<x>" #\Return #\Newline) :text "x"))
  (signals error (littoral.mail:make-mail :to "ada@example.org" :subject "no body"))
  (signals error (littoral.mail:address-spec "not an address")))

(test attachments
  (let* ((data (coerce (loop for i below 300 collect (mod i 256)) '(vector (unsigned-byte 8))))
         (message (littoral.mail:mail-string
                   (littoral.mail:make-mail :to "ada@example.org" :subject "Report" :text "Attached."
                                            :attachments (list (list "report.bin" "application/octet-stream" data))))))
    (is (search "Content-Disposition: attachment; filename=\"report.bin\"" message))
    (is (string= "Attached." (string-right-trim '(#\Newline) (littoral.mail:message-text message))))
    (let* ((start (+ 4 (search (crlf "" "") message :start2 (search "filename=" message))))
           (end (search "--=_mixed" message :start2 start)))
      (is (equalp data (cl-base64:base64-string-to-usb8-array
                        (remove-if (lambda (c) (member c '(#\Return #\Newline))) (subseq message start end))))))))

(test plain-text-from-html
  (is (string= (format nil "Hello Ada~%~%- one~%- two~%~%Open it (https://example.org/x?a=1&b=2)")
               (littoral.mail:html-to-text
                "<h1>Hello <b>Ada</b></h1><ul><li>one</li><li>two</li></ul><p><a href=\"https://example.org/x?a=1&amp;b=2\">Open it</a></p>"))))

(littoral.mail:define-mail welcome-mail (name address)
  :to (format nil "~A <~A>" name address)
  :subject (format nil "Welcome, ~A" name)
  :html ((p () "Hello " (strong () (text name)) ",")
         (p () (anchor (:href "https://example.org/start") "Get started"))))

(test mail-templates
  (let ((mail (welcome-mail "Ada <script>" "ada@example.org")))
    (is (string= "Welcome, Ada <script>" (littoral.mail:mail-subject mail)))
    (is (search "<strong>Ada &lt;script&gt;</strong>" (littoral.mail:mail-html mail)) "Text is escaped")
    (is (search "<!DOCTYPE html>" (littoral.mail:mail-html mail)) "Inside the layout")
    (is (search "Get started (https://example.org/start)" (littoral.mail:mail-text mail)))))

;;; A pretend SMTP server

(defclass fake-smtp ()
  ((socket :accessor fake-socket)
   (thread :accessor fake-thread)
   (capabilities :initarg :capabilities :initform '("PIPELINING" "AUTH PLAIN LOGIN") :reader fake-capabilities)
   (replies :initarg :replies :initform '() :reader fake-replies :documentation "(VERB . REPLY) overrides.")
   (commands :initform '() :accessor fake-commands)
   (data :initform '() :accessor fake-data)))

(defun fake-port (server) (usocket:get-local-port (fake-socket server)))

(defun serve-fake-smtp (server connection)
  (let ((stream (usocket:socket-stream connection)))
    (flet ((say (line) (write-string line stream) (write-char #\Return stream) (write-char #\Newline stream) (force-output stream))
           (hear () (let ((line (read-line stream nil))) (and line (string-right-trim '(#\Return) line)))))
      (say "220 fake.example ESMTP")
      (loop for line = (hear)
            while line
            do (push line (fake-commands server))
               (let* ((verb (string-upcase (subseq line 0 (or (position-if-not #'alpha-char-p line) (length line)))))
                      (override (cdr (assoc verb (fake-replies server) :test #'string=))))
                 (cond (override (say override))
                       ((string= verb "EHLO")
                        (say "250-fake.example")
                        (loop for (c . more) on (fake-capabilities server)
                              do (say (format nil "250~:[ ~;-~]~A" more c))))
                       ((string= verb "AUTH") (say "235 2.7.0 Authenticated"))
                       ((string= verb "DATA")
                        (say "354 Go ahead")
                        (push (with-output-to-string (out)
                                (loop for l = (hear)
                                      until (or (null l) (string= l "."))
                                      do (write-string (if (alexandria:starts-with-subseq "." l) (subseq l 1) l) out)
                                         (write-char #\Return out) (write-char #\Newline out)))
                              (fake-data server))
                        (say "250 2.0.0 Queued"))
                       ((string= verb "QUIT") (say "221 Bye") (return))
                       (t (say "250 OK"))))))))

(defun start-fake-smtp (&rest options)
  (let ((server (apply #'make-instance 'fake-smtp options)))
    (setf (fake-socket server) (usocket:socket-listen "127.0.0.1" 0 :reuse-address t :element-type 'character)
          (fake-thread server)
          (sb-thread:make-thread
           (lambda ()
             (loop (let ((connection (handler-case (usocket:socket-accept (fake-socket server))
                                       (error () (return)))))
                     (unwind-protect (ignore-errors (serve-fake-smtp server connection))
                       (usocket:socket-close connection)))))
           :name "fake smtp"))
    server))

(defun stop-fake-smtp (server)
  (ignore-errors (usocket:socket-close (fake-socket server)))
  (ignore-errors (sb-thread:join-thread (fake-thread server) :default nil :timeout 5)))

(defmacro with-fake-smtp ((server &rest options) &body body)
  `(let ((,server (start-fake-smtp ,@options)))
     (unwind-protect (progn ,@body) (stop-fake-smtp ,server))))

(defun fake-mailer (server &rest options)
  ;; OPTIONS first: the first of repeated keywords wins.
  (apply #'littoral.mail:make-smtp-mailer (append options (list :host "127.0.0.1" :port (fake-port server)
                                                                :security :none :timeout 5))))

(test smtp-delivery
  (with-fake-smtp (server)
    (let ((mail (littoral.mail:make-mail :from "Shop <shop@example.org>" :to "ada@example.org" :cc "bob@example.org"
                                         :subject "Hi" :text (format nil "First line~%.a line starting with a dot~%."))))
      (littoral.mail:send-mail mail :mailer (fake-mailer server :username "shop" :password "s3cret"))
      (let ((commands (reverse (fake-commands server))))
        (is (alexandria:starts-with-subseq "EHLO " (first commands)))
        (is (string= (format nil "AUTH PLAIN ~A" (cl-base64:string-to-base64-string
                                                  (format nil "~Cshop~Cs3cret" (code-char 0) (code-char 0))))
                     (second commands)))
        (is (member "MAIL FROM:<shop@example.org>" commands :test #'string=))
        (is (member "RCPT TO:<ada@example.org>" commands :test #'string=))
        (is (member "RCPT TO:<bob@example.org>" commands :test #'string=)))
      (let ((received (first (fake-data server))))
        (is (string= (format nil "First line~%.a line starting with a dot~%.~%")
                     (littoral.mail:message-text received))
            "Dot-stuffing keeps lines that start with a dot")))))

(test smtp-refusals
  (with-fake-smtp (server :replies '(("RCPT" . "550 5.1.1 No such user")))
    (let ((condition (handler-case (progn (littoral.mail:send-mail (littoral.mail:make-mail :to "nobody@example.org" :text "x")
                                                                   :mailer (fake-mailer server))
                                          nil)
                       (littoral.mail:smtp-error (e) e))))
      (is (typep condition 'littoral.mail:smtp-error))
      (is (eql 550 (littoral.mail:smtp-error-code condition)))
      (is (littoral.mail:smtp-error-permanent-p condition))))
  (with-fake-smtp (server :replies '(("DATA" . "451 4.3.0 Try again later")))
    (let ((condition (handler-case (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :text "x")
                                                            :mailer (fake-mailer server))
                       (littoral.mail:smtp-error (e) e))))
      (is (eql 451 (littoral.mail:smtp-error-code condition)))
      (is (not (littoral.mail:smtp-error-permanent-p condition))))))

(test smtp-never-falls-back-to-plain-text
  (with-fake-smtp (server)                ; offers no STARTTLS
    (signals littoral.mail:smtp-error
      (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :text "x")
                               :mailer (fake-mailer server :security :starttls :username "u" :password "p")))
    (is (notany (lambda (c) (or (search "AUTH" c) (search "MAIL" c))) (fake-commands server))
        "Nothing is said after STARTTLS is found missing")))

(test smtp-errors-keep-passwords-out
  (is (null (littoral.mail::command-verb "~A")) "AUTH LOGIN's name and password lines")
  (is (string= "AUTH" (littoral.mail::command-verb "AUTH PLAIN ~A")))
  (with-fake-smtp (server :replies '(("AUTH" . "535 5.7.8 Bad credentials")))
    (let ((condition (handler-case
                         (littoral.mail:send-mail (littoral.mail:make-mail :to "ada@example.org" :text "x")
                                                  :mailer (fake-mailer server :username "shop" :password "hunter2"))
                       (error (e) e))))
      (is (eql 535 (littoral.mail:smtp-error-code condition)))
      (is (search "Bad credentials" (princ-to-string condition)))
      (is (null (search (cl-base64:string-to-base64-string (format nil "~Cshop~Chunter2" (code-char 0) (code-char 0)))
                        (princ-to-string condition)))))))

(test smtp-urls
  (let ((m (littoral.mail:smtp-mailer-from-url "smtp://app%40example.org:p%3Ass@mail.example.org")))
    (is (equal '("mail.example.org" 587 :starttls "app@example.org" "p:ss")
               (list (littoral.mail::smtp-host m) (littoral.mail::smtp-port m) (littoral.mail::smtp-security m)
                     (littoral.mail::smtp-username m) (littoral.mail::smtp-password m)))))
  (let ((m (littoral.mail:smtp-mailer-from-url "smtps://mail.example.org")))
    (is (equal '(465 :tls nil) (list (littoral.mail::smtp-port m) (littoral.mail::smtp-security m)
                                     (littoral.mail::smtp-username m)))))
  (is (eq :none (littoral.mail::smtp-security (littoral.mail:smtp-mailer-from-url "smtp+insecure://localhost:2525"))))
  (signals error (littoral.mail:smtp-mailer-from-url "http://example.org")))

;;; A real server: CI runs Mailpit, requiring STARTTLS, with a certificate of its own

(test real-smtp-server
  (let ((server (uiop:getenv "LITTORAL_TEST_SMTP")))
    (if (zerop (length server))
        (skip "LITTORAL_TEST_SMTP is not set")
        (let* ((colon (position #\: server))
               (host (subseq server 0 colon))
               (port (parse-integer server :start (1+ colon)))
               (subject (format nil "Littoral CI ~A — ünïcödé" (random 1000000000)))
               (mail (littoral.mail:make-mail :from "CI <ci@example.org>" :to "ada@example.org" :subject subject
                                              :text "Sent over STARTTLS." :html "<p>Sent over <b>STARTTLS</b>.</p>")))
          (flet ((mailer (&rest options)
                   (apply #'littoral.mail:make-smtp-mailer :host host :port port :username "ci" :password "secret"
                                                           :timeout 10 options)))
            (littoral.mail:send-mail mail :mailer (mailer :ca-file (uiop:getenv "LITTORAL_TEST_SMTP_CA")))
            (let* ((json (com.inuoe.jzon:parse (dex:get (format nil "~A/api/v1/messages" (uiop:getenv "LITTORAL_TEST_SMTP_API")))))
                   (subjects (map 'list (lambda (m) (gethash "Subject" m)) (gethash "messages" json))))
              (is (member subject subjects :test #'equal)))
            ;; Its certificate isn't from an authority the system trusts: refused.
            (signals error (littoral.mail:send-mail mail :mailer (mailer)))
            ;; And it won't take mail in the clear.
            (signals littoral.mail:smtp-error (littoral.mail:send-mail mail :mailer (mailer :security :none))))))))

;;; The outbox

(def-suite outbox :in littoral)
(in-suite outbox)

(defclass flaky-mailer ()
  ((condition :initarg :condition :accessor flaky-condition)
   (inner :initform (littoral.mail:make-memory-mailer) :reader flaky-inner)))

(defmethod littoral.mail:send-message ((mailer flaky-mailer) from recipients message)
  (if (flaky-condition mailer)
      (error (flaky-condition mailer))
      (littoral.mail:send-message (flaky-inner mailer) from recipients message)))

(defmacro with-outbox (() &body body)
  `(progn
     (connect-test-database)
     (ignore-errors (littoral.mail:drop-mail-tables))
     (littoral.mail:create-mail-tables)
     ,@body))

(defun outbox-row () (first (littoral.mail:outbox-messages)))

(test outbox-delivers-and-retries
  (with-outbox ()
    (let ((mailer (make-instance 'flaky-mailer :condition (make-condition 'simple-error :format-control "connection refused"))))
      (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :subject "Hello" :text "Hi"))
      (is (string= "queued" (littoral.mail:outbox-status (outbox-row))))
      ;; Down: tried, kept, and not tried again until its time.
      (is (= 0 (littoral.mail:deliver-queued-mail :mailer mailer)))
      (let ((row (outbox-row)))
        (is (string= "queued" (littoral.mail:outbox-status row)))
        (is (= 1 (littoral.mail:outbox-attempts row)))
        (is (search "connection refused" (littoral.mail:outbox-last-error row)))
        (is (> (littoral.mail:outbox-next-attempt row) (get-universal-time))))
      (is (= 0 (littoral.mail:deliver-queued-mail :mailer mailer)) "Not due yet")
      ;; Up again, and due: sent.
      (setf (flaky-condition mailer) nil)
      (littoral.db:db-execute "UPDATE mail_outbox SET next_attempt = 0")
      (is (= 1 (littoral.mail:deliver-queued-mail :mailer mailer)))
      (let ((row (outbox-row)))
        (is (string= "sent" (littoral.mail:outbox-status row)))
        (is (= 2 (littoral.mail:outbox-attempts row)))
        (is (integerp (littoral.mail:outbox-sent row))))
      (let ((sent (first (littoral.mail:mailer-messages (flaky-inner mailer)))))
        (is (equal '("ada@example.org") (littoral.mail:sent-message-recipients sent)))
        (is (string= "Hello" (littoral.mail:message-header (littoral.mail:sent-message-text sent) "Subject"))))
      (is (= 0 (littoral.mail:deliver-queued-mail :mailer mailer)) "Sent once only"))))

(test outbox-gives-up
  (with-outbox ()
    ;; A refusal fails at once.
    (littoral.mail:queue-mail (littoral.mail:make-mail :to "nobody@example.org" :text "x"))
    (littoral.mail:deliver-queued-mail
     :mailer (make-instance 'flaky-mailer :condition (make-condition 'littoral.mail:smtp-error :code 550 :message "No such user")))
    (is (string= "failed" (littoral.mail:outbox-status (outbox-row))))
    ;; Trouble that might pass is tried *MAIL-ATTEMPTS* times.
    (let ((littoral.mail:*mail-attempts* 3)
          (mailer (make-instance 'flaky-mailer :condition (make-condition 'littoral.mail:smtp-error :code 421 :message "Busy"))))
      (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "y"))
      (loop repeat 3
            do (littoral.db:db-execute "UPDATE mail_outbox SET next_attempt = 0 WHERE status = 'queued'")
               (littoral.mail:deliver-queued-mail :mailer mailer))
      (is (string= "failed" (littoral.mail:outbox-status (outbox-row))))
      (is (= 3 (littoral.mail:outbox-attempts (outbox-row))))
      ;; Retrying counts afresh.
      (littoral.mail:retry-mail (littoral.mail:outbox-id (outbox-row)))
      (setf (flaky-condition mailer) nil)
      (is (= 1 (littoral.mail:deliver-queued-mail :mailer mailer)))
      (is (string= "sent" (littoral.mail:outbox-status (outbox-row)))))))

(test outbox-claims-each-message-once
  (with-outbox ()
    (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "x"))
    (let ((row (outbox-row)))
      (is (littoral.mail::claim row))
      (is (not (littoral.mail::claim row)) "A second process loses the race")
      (is (= 0 (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer)))
          "Claimed by another, so not sent here"))))

(test outbox-only-sends-what-commits
  (with-outbox ()
    (ignore-errors
     (littoral.db:with-transaction ()
       (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "x"))
       (error "the action failed")))
    (is (null (littoral.mail:outbox-messages)))))

(test password-reset-through-the-outbox
  (with-auth (b)
    (littoral.mail:drop-mail-tables)
    (littoral.mail:create-mail-tables)
    (let ((littoral.auth:*send-mail* (littoral.mail:outbox-sender :from "Shop <shop@example.org>"))
          (mailer (littoral.mail:make-memory-mailer)))
      (click b "Sign in")
      (click b "Forgot your password?")
      (fill-in b "reset-email" "bob@example.org")
      (press b "Send me a link")
      (is (string= "queued" (littoral.mail:outbox-status (outbox-row))))
      (is (= 1 (littoral.mail:deliver-queued-mail :mailer mailer)))
      (let ((message (littoral.mail:sent-message-text (first (littoral.mail:mailer-messages mailer)))))
        (is (string= "bob@example.org" (littoral.mail:message-header message "To")))
        (is (search "/reset?token=" (littoral.mail:message-text message)))))))

(test delivery-thread
  ;; The thread has its own connection, so this uses a file, not :memory:.
  (let* ((file (merge-pathnames (format nil "littoral-outbox-~36R.sqlite3" (random (expt 36 8)))
                                (uiop:temporary-directory)))
         (spec (list :sqlite3 :database-name (namestring file)))
         (mailer (littoral.mail:make-memory-mailer)))
    (unwind-protect
         (let ((littoral.db:*database* spec))
           (littoral.mail:create-mail-tables)
           (littoral.mail:start-mail-delivery :database spec :mailer mailer :interval 1)
           (is (littoral.mail:mail-delivery-running-p))
           (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :subject "Soon" :text "x"))
           (loop repeat 50 until (littoral.mail:mailer-messages mailer) do (sleep 0.1))
           (is (= 1 (length (littoral.mail:mailer-messages mailer))))
           (is (string= "sent" (littoral.mail:outbox-status (outbox-row)))))
      (littoral.mail:stop-mail-delivery)
      (ignore-errors (delete-file file)))
    (is (not (littoral.mail:mail-delivery-running-p)))))
