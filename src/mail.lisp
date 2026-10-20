;;;; mail.lisp — messages, mailers and templates
;;;;
;;;;   (setf *mailer* (make-smtp-mailer :host "smtp.example.org" :username "app" :password "…")
;;;;         *mail-from* "Bookshop <hello@example.org>")
;;;;   (define-mail welcome-mail (user)
;;;;     :to (user-email user)
;;;;     :subject (format nil "Welcome, ~A" (user-name user))
;;;;     :html ((h:p () "We're glad you're here.")))
;;;;   (queue-mail (welcome-mail user))      ; sent by the outbox, retried until it goes
;;;;
;;;; A mail is MAKE-MAIL's object; MAIL-STRING writes it as MIME, through the
;;;; smtp library (github.com/lispnik/smtp).  A mailer sends it: an SMTP-MAILER, a LOG-MAILER (the default,
;;;; which prints) or a MEMORY-MAILER (which keeps them, for tests and demos).

(defpackage #:littoral.mail
  (:use #:cl)
  (:import-from #:smtp #:smtp-error)
  (:documentation "Load it with `(asdf:load-system :littoral/mail)`.  Sending mail: MIME messages,
SMTP, templates and an outbox that retries.")
  (:export
   ;; Messages
   #:mail #:make-mail #:mail-to #:mail-cc #:mail-bcc #:mail-from #:mail-reply-to #:mail-subject
   #:mail-text #:mail-html #:mail-attachments #:mail-headers #:mail-string #:mail-recipients
   #:*mail-from* #:address-spec
   ;; Reading messages back
   #:message-header #:message-text #:message-html
   ;; Mailers
   #:*mailer* #:send-message #:send-mail
   #:smtp-mailer #:make-smtp-mailer #:smtp-mailer-from-url #:smtp-error #:smtp-error-code
   #:smtp-error-permanent-p
   #:log-mailer #:memory-mailer #:make-memory-mailer #:mailer-messages #:clear-mailer
   #:sent-message #:sent-message-from #:sent-message-recipients #:sent-message-text #:sent-message-time
   ;; Templates
   #:define-mail #:*mail-layout* #:default-mail-layout #:html-to-text
   ;; The outbox
   #:outbox-mail #:create-mail-tables #:drop-mail-tables #:queue-mail #:outbox-sender
   #:deliver-queued-mail #:start-mail-delivery #:stop-mail-delivery #:mail-delivery-running-p
   #:outbox-messages #:retry-mail #:purge-sent-mail #:*mail-attempts* #:*mail-retry-seconds*
   #:outbox-id #:outbox-sender-address #:outbox-recipients #:outbox-subject #:outbox-message
   #:outbox-status #:outbox-attempts #:outbox-next-attempt #:outbox-last-error #:outbox-created
   #:outbox-sent))

(in-package #:littoral.mail)

;;; Messages

(defvar *mail-from* "Littoral <littoral@localhost>"
  "The From address of mail that doesn't give one.")

(defclass mail ()
  ((to :initarg :to :initform '() :reader mail-to :documentation "A list of addresses.")
   (cc :initarg :cc :initform '() :reader mail-cc :documentation "A list of addresses.")
   (bcc :initarg :bcc :initform '() :reader mail-bcc
        :documentation "A list of addresses, which the message doesn't show.")
   (from :initarg :from :reader mail-from :documentation "An address.")
   (reply-to :initarg :reply-to :initform nil :reader mail-reply-to :documentation "An address, or NIL.")
   (subject :initarg :subject :initform "" :reader mail-subject)
   (text :initarg :text :initform nil :reader mail-text
         :documentation "The plain-text body, made from the HTML one when not given.")
   (html :initarg :html :initform nil :reader mail-html :documentation "The HTML body, or NIL.")
   (attachments :initarg :attachments :initform '() :reader mail-attachments
                :documentation "(FILE-NAME CONTENT-TYPE OCTETS-OR-STRING) lists.")
   (headers :initarg :headers :initform '() :reader mail-headers
            :documentation "Extra headers, as (NAME . VALUE) pairs."))
  (:documentation "A mail to send: MAKE-MAIL makes one."))

(defun listify (x) (if (listp x) (remove nil x) (list x)))

(defun make-mail (&key to cc bcc (from *mail-from*) reply-to (subject "") text html attachments headers)
  "A mail.  TO, CC and BCC are addresses (\"ada@example.org\" or \"Ada <ada@example.org>\")
or lists of them; FROM an address (*MAIL-FROM*) and REPLY-TO one or NIL; TEXT
and HTML its plain and HTML bodies (one is enough: the plain one is made from
the HTML when missing); ATTACHMENTS (FILE-NAME CONTENT-TYPE DATA) lists, DATA
octets or a string (sent as UTF-8); HEADERS (NAME . VALUE) pairs.  Signals an
error without a recipient or a body, and an SMTP-ERROR for a bad address or a
line break in a header."
  (let ((to (listify to)) (cc (listify cc)) (bcc (listify bcc)))
    (unless (or to cc bcc) (error "A mail needs someone to send it to."))
    (unless (or text html) (error "A mail needs a TEXT or an HTML body."))
    (let ((mail (make-instance 'mail :to to :cc cc :bcc bcc :from from :reply-to reply-to :subject subject
                                     :text (or text (html-to-text html)) :html html
                                     :attachments attachments :headers headers)))
      (smtp-message mail)
      mail)))

(defun utf-8 (string) (sb-ext:string-to-octets string :external-format :utf-8))

(defun smtp-message (mail &key date)
  "MAIL as an SMTP:MESSAGE, which checks every address and header."
  (smtp:make-message :from (mail-from mail) :to (mail-to mail) :cc (mail-cc mail) :bcc (mail-bcc mail)
                     :reply-to (mail-reply-to mail) :subject (mail-subject mail)
                     :text (mail-text mail) :html (mail-html mail)
                     :attachments (loop for (name type data) in (mail-attachments mail)
                                        collect (smtp:make-attachment (if (stringp data) (utf-8 data) data)
                                                                      :filename name :content-type type))
                     :headers (mail-headers mail) :date date))

(defun address-spec (address)
  "The bare address in ADDRESS: \"Ada <ada@example.org>\" → \"ada@example.org\".
Signals an SMTP-ERROR when ADDRESS isn't one."
  (smtp:mailbox-address (smtp:parse-mailbox address)))

(defun mail-recipients (mail)
  "Everyone MAIL goes to, Bcc included, as bare addresses."
  (remove-duplicates (mapcar #'address-spec (append (mail-to mail) (mail-cc mail) (mail-bcc mail)))
                     :test #'string-equal :from-end t))

(defun mail-string (mail &key (date (get-universal-time)))
  "MAIL as a MIME message, with CRLF line breaks, dated DATE (a universal
time, now by default); Bcc isn't written."
  (sb-ext:octets-to-string (smtp:render-message (smtp-message mail :date date)) :external-format :utf-8))

(defun crlf-lines (string)
  "STRING's lines, however they were broken."
  (let ((lines (cl-ppcre:split "\\r\\n|\\r|\\n" string :limit most-positive-fixnum)))
    (if (and lines (string= (car (last lines)) "")) (butlast lines) lines)))

;;; Reading a message back, for tests, demos and the outbox page

(defun split-message (message)
  "MESSAGE's headers (unfolded, (NAME . VALUE)) and its body."
  (let* ((break (or (search (format nil "~C~C~C~C" #\Return #\Newline #\Return #\Newline) message)
                    (length message)))
         (head (cl-ppcre:regex-replace-all "\\r\\n[ \\t]+" (subseq message 0 break) " "))
         (headers (loop for line in (crlf-lines head)
                        for colon = (position #\: line)
                        when colon collect (cons (subseq line 0 colon) (string-trim " " (subseq line (1+ colon)))))))
    (values headers (subseq message (min (length message) (+ break 4))))))

(defun decode-words (value)
  "VALUE with RFC 2047 B and Q encoded words decoded."
  (cl-ppcre:regex-replace-all
   "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?=(\\s+(?==\\?))?" value
   (lambda (match charset kind data space)
     (declare (ignore match charset space))
     (sb-ext:octets-to-string
      (if (string-equal kind "B")
          (smtp:base64-decode data)
          (smtp:quoted-printable-decode (substitute #\Space #\_ data)))
      :external-format :utf-8))
   :simple-calls t))

(defun message-header (message name)
  "The header NAME of MESSAGE (a MIME string), decoded, or NIL."
  (let ((value (cdr (assoc name (split-message message) :test #'string-equal))))
    (and value (decode-words value))))

(defun find-part (message type)
  "The decoded body of MESSAGE's first part of content type TYPE."
  (multiple-value-bind (headers body) (split-message message)
    (let* ((content-type (or (cdr (assoc "Content-Type" headers :test #'string-equal)) "text/plain"))
           (boundary (nth-value 1 (cl-ppcre:scan-to-strings "(?i)boundary=\"?([^\";]+)" content-type))))
      (if boundary
          (loop for part in (rest (cl-ppcre:split (format nil "--~A(?:--)?\\r\\n" (cl-ppcre:quote-meta-chars (aref boundary 0))) body))
                thereis (find-part part type))
          (when (alexandria:starts-with-subseq type (string-downcase content-type))
            (let ((encoding (cdr (assoc "Content-Transfer-Encoding" headers :test #'string-equal))))
              (cond ((string-equal encoding "quoted-printable")
                     (sb-ext:octets-to-string (smtp:quoted-printable-decode body) :external-format :utf-8))
                    ((string-equal encoding "base64")
                     (sb-ext:octets-to-string (smtp:base64-decode body) :external-format :utf-8))
                    (t body))))))))

(defun message-text (message)
  "The plain text of MESSAGE (a MIME string), with plain newlines, or NIL."
  (let ((text (find-part message "text/plain")))
    (and text (remove #\Return text))))

(defun message-html (message)
  "The HTML part of MESSAGE (a MIME string), or NIL."
  (let ((html (find-part message "text/html")))
    (and html (remove #\Return html))))

;;; Mailers

(defgeneric send-message (mailer from recipients message)
  (:documentation "Send MESSAGE, a MIME string, from the address FROM to the addresses
RECIPIENTS.  Signals on failure; an SMTP-ERROR that is SMTP-ERROR-PERMANENT-P
won't succeed if tried again."))

(defclass log-mailer () ((stream :initarg :stream :initform nil))
  (:documentation "Prints each message's addresses, subject and text, instead of sending it,
to its :STREAM, or else *ERROR-OUTPUT*."))

(defmethod send-message ((mailer log-mailer) from recipients message)
  (format (or (slot-value mailer 'stream) *error-output*)
          "~&--- mail from ~A to ~{~A~^, ~}: ~A~%~A~&---~%"
          from recipients (message-header message "Subject") (message-text message)))

(defclass sent-message ()
  ((from :initarg :from :reader sent-message-from :documentation "The envelope's sender, a bare address.")
   (recipients :initarg :recipients :reader sent-message-recipients
               :documentation "The envelope's recipients, bare addresses, Bcc included.")
   (text :initarg :text :reader sent-message-text :documentation "The MIME message.")
   (time :initform (get-universal-time) :reader sent-message-time
         :documentation "When the mailer was given it, a universal time."))
  (:documentation "A message a MEMORY-MAILER was given."))

(defclass memory-mailer ()
  ((messages :initform '() :accessor memory-messages)
   (keep :initarg :keep :initform 50 :reader memory-keep)
   (lock :initform (sb-thread:make-mutex :name "memory mailer") :reader memory-lock))
  (:documentation "Keeps the messages it is given, newest first, instead of sending them."))

(defun make-memory-mailer (&key (keep 50))
  "A mailer that keeps the last KEEP messages, for tests and demos."
  (make-instance 'memory-mailer :keep keep))

(defmethod send-message ((mailer memory-mailer) from recipients message)
  (sb-thread:with-mutex ((memory-lock mailer))
    (let ((all (cons (make-instance 'sent-message :from from :recipients recipients :text message)
                     (memory-messages mailer))))
      (setf (memory-messages mailer) (subseq all 0 (min (length all) (memory-keep mailer)))))))

(defun mailer-messages (mailer)
  "The messages MAILER (a MEMORY-MAILER) has kept, newest first."
  (sb-thread:with-mutex ((memory-lock mailer)) (copy-list (memory-messages mailer))))

(defun clear-mailer (mailer)
  "Forget the messages MAILER (a MEMORY-MAILER) has kept."
  (sb-thread:with-mutex ((memory-lock mailer)) (setf (memory-messages mailer) '())))

(defvar *mailer* (make-instance 'log-mailer)
  "What sends mail: an SMTP-MAILER, or by default a LOG-MAILER that prints it.")

(littoral:define-metric "littoral_mail_sends_total" :counter
  "Messages handed to a mailer, by result: sent, transient (it may pass) or permanent (refused for good)."
  :labels '("result"))

(defun send-counted (mailer from recipients message)
  "SEND-MESSAGE, counted in littoral_mail_sends_total."
  (handler-bind ((error (lambda (e)
                          (littoral:count-metric "littoral_mail_sends_total"
                                                 (list (if (smtp-error-permanent-p e) "permanent" "transient"))))))
    (prog1 (send-message mailer from recipients message)
      (littoral:count-metric "littoral_mail_sends_total" (list "sent")))))

(defun send-mail (mail &key (mailer *mailer*))
  "Send MAIL now with MAILER, waiting for it, and signal what it signals when
sending fails.  QUEUE-MAIL sends it in the background instead, and tries
again when it fails."
  (send-counted mailer (address-spec (mail-from mail)) (mail-recipients mail) (mail-string mail)))

;;; Templates

(defun default-mail-layout (subject body)
  "Write an HTML mail around BODY, a thunk writing its content: a plain,
readable page that mail programs show well."
  (littoral.html:raw (format nil "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>~A</title></head><body style=\"margin:0;padding:24px;background:#f6f6f4;font:16px/1.5 -apple-system,'Segoe UI',Helvetica,Arial,sans-serif;color:#1d1d1b\"><div style=\"max-width:560px;margin:0 auto;background:#fff;padding:24px 28px;border-radius:8px\">"
                             (littoral.html:html-escape subject)))
  (funcall body)
  (littoral.html:raw "</div></body></html>"))

(defvar *mail-layout* 'default-mail-layout
  "A function of (SUBJECT BODY-THUNK) that writes the HTML around a template's content.")

(defun render-mail-html (subject thunk)
  (littoral.html:with-canvas-to-string ()
    (funcall *mail-layout* subject thunk)))

(defmacro define-mail (name lambda-list &key to cc bcc from reply-to subject text html attachments headers)
  "Define NAME, a function of LAMBDA-LIST making a mail.  The keyword forms are
evaluated each time, with LAMBDA-LIST's variables bound, and given to
MAKE-MAIL (FROM defaults to *MAIL-FROM*).  HTML is a list of forms written
with Littoral's HTML tags (as in RENDER), inside *MAIL-LAYOUT*.  Without
TEXT, the plain text is made from the HTML."
  (let ((subject-var (gensym "SUBJECT")))
    `(defun ,name ,lambda-list
       (let ((,subject-var ,subject))
         (make-mail :to ,to :cc ,cc :bcc ,bcc ,@(when from `(:from ,from)) :reply-to ,reply-to
                    :subject ,subject-var :text ,text
                    :html ,(when html `(render-mail-html ,subject-var (lambda () ,@html)))
                    :attachments ,attachments :headers ,headers)))))

(defun html-to-text (html)
  "A plain-text version of HTML: paragraphs and line breaks kept, links
written out after their text, tags dropped, entities decoded."
  (let* ((s (cl-ppcre:regex-replace-all "(?is)<(head|style|script)\\b.*?</\\1>" html ""))
         (s (cl-ppcre:regex-replace-all "(?is)<a\\s[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>" s
                                        (lambda (match href body)
                                          (declare (ignore match))
                                          (if (string= (string-trim " " body) href) body (format nil "~A (~A)" body href)))
                                        :simple-calls t))
         (s (cl-ppcre:regex-replace-all "(?i)<br\\s*/?>" s (string #\Newline)))
         (s (cl-ppcre:regex-replace-all "(?i)<li\\b[^>]*>" s (format nil "~%- ")))
         (s (cl-ppcre:regex-replace-all "(?i)</(p|div|h[1-6]|ul|ol|table|tr|blockquote|pre)>" s (format nil "~%~%")))
         (s (cl-ppcre:regex-replace-all "<[^>]*>" s ""))
         (s (cl-ppcre:regex-replace-all "&nbsp;" s " "))
         (s (cl-ppcre:regex-replace-all "&lt;" s "<"))
         (s (cl-ppcre:regex-replace-all "&gt;" s ">"))
         (s (cl-ppcre:regex-replace-all "&quot;" s "\""))
         (s (cl-ppcre:regex-replace-all "&#39;" s "'"))
         (s (cl-ppcre:regex-replace-all "&amp;" s "&"))
         (s (cl-ppcre:regex-replace-all "[ \\t]+\\n" s (string #\Newline)))
         (s (cl-ppcre:regex-replace-all "\\n[ \\t]+" s (string #\Newline)))
         (s (cl-ppcre:regex-replace-all "\\n{3,}" s (format nil "~%~%"))))
    (string-trim '(#\Space #\Newline #\Tab) s)))
