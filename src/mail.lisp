;;;; mail.lisp — messages, mailers and templates
;;;;
;;;;   (setf *mailer* (make-smtp-mailer :host "smtp.example.org" :username "app" :password "…")
;;;;         *mail-from* "Bookshop <hello@example.org>")
;;;;   (define-mail welcome-mail (user)
;;;;     :to (user-email user)
;;;;     :subject (format nil "Welcome, ~A" (user-name user))
;;;;     :html ((p () "We're glad you're here.")))
;;;;   (queue-mail (welcome-mail user))      ; sent by the outbox, retried until it goes
;;;;
;;;; A mail is MAKE-MAIL's object; MAIL-STRING writes it as MIME (UTF-8,
;;;; quoted-printable, multipart/alternative when it has HTML, attachments in
;;;; base64).  A mailer sends it: an SMTP-MAILER, a LOG-MAILER (the default,
;;;; which prints) or a MEMORY-MAILER (which keeps them, for tests and demos).

(defpackage #:littoral.mail
  (:use #:cl)
  (:documentation "Sending mail: MIME messages, SMTP, templates and an outbox that retries.")
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
  ((to :initarg :to :initform '() :reader mail-to)
   (cc :initarg :cc :initform '() :reader mail-cc)
   (bcc :initarg :bcc :initform '() :reader mail-bcc)
   (from :initarg :from :reader mail-from)
   (reply-to :initarg :reply-to :initform nil :reader mail-reply-to)
   (subject :initarg :subject :initform "" :reader mail-subject)
   (text :initarg :text :initform nil :reader mail-text)
   (html :initarg :html :initform nil :reader mail-html)
   (attachments :initarg :attachments :initform '() :reader mail-attachments
                :documentation "(FILE-NAME CONTENT-TYPE OCTETS-OR-STRING) lists.")
   (headers :initarg :headers :initform '() :reader mail-headers
            :documentation "Extra headers, as (NAME . VALUE) pairs."))
  (:documentation "A mail to send: MAKE-MAIL makes one."))

(defun listify (x) (if (listp x) (remove nil x) (list x)))

(defun check-header-value (value)
  "VALUE, unless it holds a line break: a header can't be allowed to start another."
  (when (and value (find-if (lambda (c) (member c '(#\Return #\Newline))) value))
    (error "A line break in a mail header: ~S" value))
  value)

(defun make-mail (&key to cc bcc (from *mail-from*) reply-to (subject "") text html attachments headers)
  "A mail.  TO, CC and BCC are addresses (\"ada@example.org\" or \"Ada <ada@example.org>\")
or lists of them; TEXT and HTML its plain and HTML bodies (one is enough: the
plain one is made from the HTML when missing); ATTACHMENTS (FILE-NAME
CONTENT-TYPE DATA) lists, DATA octets or a string; HEADERS (NAME . VALUE) pairs."
  (let ((to (listify to)) (cc (listify cc)) (bcc (listify bcc)))
    (unless (or to cc bcc) (error "A mail needs someone to send it to."))
    (unless (or text html) (error "A mail needs a TEXT or an HTML body."))
    (mapc #'check-header-value (append to cc bcc (list from reply-to subject)))
    (loop for (name . value) in headers do (check-header-value name) (check-header-value value))
    (make-instance 'mail :to to :cc cc :bcc bcc :from from :reply-to reply-to :subject subject
                         :text (or text (html-to-text html)) :html html
                         :attachments attachments :headers headers)))

(defun address-spec (address)
  "The bare address in ADDRESS: \"Ada <ada@example.org>\" → \"ada@example.org\"."
  (let* ((open (position #\< address :from-end t))
         (close (and open (position #\> address :start open)))
         (spec (string-trim " " (if close (subseq address (1+ open) close) address))))
    (when (or (zerop (length spec)) (find-if (lambda (c) (member c '(#\Space #\Tab #\< #\> #\Return #\Newline))) spec))
      (error "Not a mail address: ~S" address))
    spec))

(defun mail-recipients (mail)
  "Everyone MAIL goes to, Bcc included, as bare addresses."
  (remove-duplicates (mapcar #'address-spec (append (mail-to mail) (mail-cc mail) (mail-bcc mail)))
                     :test #'string-equal :from-end t))

;;; Encodings

(defun utf-8 (string) (sb-ext:string-to-octets string :external-format :utf-8))

(defun ascii-p (string) (every (lambda (c) (< (char-code c) 128)) string))

(defun encoded-words (string)
  "STRING as RFC 2047 encoded words when it isn't plain ASCII, each short
enough for a header line and never splitting a character."
  (if (ascii-p string)
      string
      (let ((words '()) (chunk '()) (size 0))
        (flet ((flush ()
                 (when chunk
                   (push (format nil "=?UTF-8?B?~A?=" (cl-base64:usb8-array-to-base64-string
                                                     (utf-8 (coerce (reverse chunk) 'string))))
                         words)
                   (setf chunk '() size 0))))
          (loop for c across string
                for n = (length (utf-8 (string c)))
                do (when (> (+ size n) 45) (flush))
                   (push c chunk) (incf size n))
          (flush))
        (format nil "~{~A~^~%  ~}" (reverse words)))))

(defun encode-address (address)
  "ADDRESS for a header: a display name encoded or quoted as it needs."
  (let ((open (position #\< address :from-end t)))
    (if (null open)
        (address-spec address)
        (let ((name (string-trim " \"" (subseq address 0 open)))
              (spec (address-spec address)))
          (cond ((zerop (length name)) spec)
                ((not (ascii-p name)) (format nil "~A <~A>" (encoded-words name) spec))
                ((find-if (lambda (c) (find c "()<>[]:;@\\,.\"")) name)
                 (format nil "\"~A\" <~A>" (remove #\" (remove #\\ name)) spec))
                (t (format nil "~A <~A>" name spec)))))))

(defun crlf-lines (string)
  "STRING's lines, however they were broken."
  (let ((lines (cl-ppcre:split "\\r\\n|\\r|\\n" string :limit most-positive-fixnum)))
    (if (and lines (string= (car (last lines)) "")) (butlast lines) lines)))

(defun quoted-printable (string)
  "STRING as UTF-8 quoted-printable, lines under 77 characters, CRLF breaks."
  (with-output-to-string (out)
    (dolist (line (crlf-lines string))
      (let ((column 0)
            (octets (utf-8 line)))
        (loop for i from 0 below (length octets)
              for byte = (aref octets i)
              for last = (= i (1- (length octets)))
              for piece = (if (or (> byte 126) (= byte 61) (and (< byte 32) (/= byte 9))
                                  ;; Spaces at the end of a line would be stripped on the way.
                                  (and last (member byte '(9 32))))
                              (format nil "=~2,'0X" byte)
                              (string (code-char byte)))
              do (when (> (+ column (length piece)) 75)
                   (format out "=~C~C" #\Return #\Newline)
                   (setf column 0))
                 (write-string piece out)
                 (incf column (length piece))))
      (format out "~C~C" #\Return #\Newline))))

(defun base64-lines (octets)
  (with-output-to-string (out)
    (let ((encoded (cl-base64:usb8-array-to-base64-string octets)))
      (loop for start from 0 below (length encoded) by 76
            do (format out "~A~C~C" (subseq encoded start (min (length encoded) (+ start 76))) #\Return #\Newline)))))

(defun rfc-5322-date (&optional (time (get-universal-time)))
  (multiple-value-bind (s m h day month year weekday) (decode-universal-time time 0)
    (format nil "~A, ~D ~A ~D ~2,'0D:~2,'0D:~2,'0D +0000"
            (nth weekday '("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun")) day
            (nth (1- month) '("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))
            year h m s)))

(defun random-token (n) (littoral::random-key n))

(defun mail-domain (mail)
  (let* ((spec (address-spec (mail-from mail))) (at (position #\@ spec)))
    (if at (subseq spec (1+ at)) "localhost")))

(defun write-part (out content-type body)
  (format out "Content-Type: ~A; charset=UTF-8~C~CContent-Transfer-Encoding: quoted-printable~C~C~C~C~A"
          content-type #\Return #\Newline #\Return #\Newline #\Return #\Newline (quoted-printable body)))

(defun write-body (out mail)
  "The body of MAIL with its Content-Type headers: text, or text and HTML."
  (if (mail-html mail)
      (let ((boundary (format nil "=_alt_~A" (random-token 20))))
        (format out "Content-Type: multipart/alternative; boundary=\"~A\"~C~C~C~C" boundary #\Return #\Newline #\Return #\Newline)
        (format out "--~A~C~C" boundary #\Return #\Newline)
        (write-part out "text/plain" (mail-text mail))
        (format out "--~A~C~C" boundary #\Return #\Newline)
        (write-part out "text/html" (mail-html mail))
        (format out "--~A--~C~C" boundary #\Return #\Newline))
      (write-part out "text/plain" (mail-text mail))))

(defun mail-string (mail &key (date (get-universal-time)))
  "MAIL as a MIME message, with CRLF line breaks; Bcc isn't written."
  ;; Long header values are folded with ~% below; FOLD-NEWLINES makes them CRLF.
  (fold-newlines (write-message mail date)))

(defun write-message (mail date)
  (with-output-to-string (out)
    (flet ((header (name value)
             (format out "~A: ~A~C~C" name value #\Return #\Newline)))
      (header "Date" (rfc-5322-date date))
      (header "From" (encode-address (mail-from mail)))
      (when (mail-to mail) (header "To" (format nil "~{~A~^,~%  ~}" (mapcar #'encode-address (mail-to mail)))))
      (when (mail-cc mail) (header "Cc" (format nil "~{~A~^,~%  ~}" (mapcar #'encode-address (mail-cc mail)))))
      (when (mail-reply-to mail) (header "Reply-To" (encode-address (mail-reply-to mail))))
      (header "Subject" (encoded-words (mail-subject mail)))
      (header "Message-ID" (format nil "<~A@~A>" (random-token 24) (mail-domain mail)))
      (header "MIME-Version" "1.0")
      (loop for (name . value) in (mail-headers mail) do (header name (encoded-words value))))
    (if (mail-attachments mail)
        (let ((boundary (format nil "=_mixed_~A" (random-token 20))))
          (format out "Content-Type: multipart/mixed; boundary=\"~A\"~C~C~C~C" boundary #\Return #\Newline #\Return #\Newline)
          (format out "--~A~C~C" boundary #\Return #\Newline)
          (write-body out mail)
          (loop for (name type data) in (mail-attachments mail)
                do (check-header-value name) (check-header-value type)
                   (format out "--~A~C~CContent-Type: ~A; name=\"~A\"~C~CContent-Disposition: attachment; filename=\"~A\"~C~CContent-Transfer-Encoding: base64~C~C~C~C~A"
                           boundary #\Return #\Newline type (encoded-words name) #\Return #\Newline
                           (encoded-words name) #\Return #\Newline #\Return #\Newline #\Return #\Newline
                           (base64-lines (if (stringp data) (utf-8 data) data))))
          (format out "--~A--~C~C" boundary #\Return #\Newline))
        (write-body out mail))))

(defun fold-newlines (string)
  "STRING with lone newlines made CRLF, for header folding done with ~%."
  (cl-ppcre:regex-replace-all "(?<!\\r)\\n" string (format nil "~C~C" #\Return #\Newline)))

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
          (cl-base64:base64-string-to-usb8-array data)
          (decode-qp-octets (substitute #\Space #\_ data)))
      :external-format :utf-8))
   :simple-calls t))

(defun decode-qp-octets (string)
  (let ((out (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))
        (string (cl-ppcre:regex-replace-all "=\\r?\\n" string "")))
    (loop with i = 0 while (< i (length string))
          do (let ((c (char string i)))
               (if (and (char= c #\=) (< (+ i 2) (length string)))
                   (progn (vector-push-extend (parse-integer string :start (1+ i) :end (+ i 3) :radix 16) out)
                          (incf i 3))
                   (progn (loop for b across (utf-8 (string c)) do (vector-push-extend b out))
                          (incf i)))))
    out))

(defun message-header (message name)
  "The header NAME of MESSAGE (a MIME string), decoded, or NIL."
  (let ((value (cdr (assoc name (split-message message) :test #'string-equal))))
    (and value (decode-words value))))

(defun find-part (message type)
  "The decoded body of MESSAGE's first part of content type TYPE."
  (multiple-value-bind (headers body) (split-message message)
    (let* ((content-type (or (cdr (assoc "Content-Type" headers :test #'string-equal)) "text/plain"))
           (boundary (nth-value 1 (cl-ppcre:scan-to-strings "boundary=\"([^\"]+)\"" content-type))))
      (if boundary
          (loop for part in (rest (cl-ppcre:split (format nil "--~A(?:--)?\\r\\n" (cl-ppcre:quote-meta-chars (aref boundary 0))) body))
                thereis (find-part part type))
          (when (alexandria:starts-with-subseq type (string-downcase content-type))
            (let ((encoding (cdr (assoc "Content-Transfer-Encoding" headers :test #'string-equal))))
              (cond ((string-equal encoding "quoted-printable")
                     (sb-ext:octets-to-string (decode-qp-octets body) :external-format :utf-8))
                    ((string-equal encoding "base64")
                     (sb-ext:octets-to-string (cl-base64:base64-string-to-usb8-array (remove-if (lambda (c) (member c '(#\Return #\Newline))) body))
                                              :external-format :utf-8))
                    (t body))))))))

(defun message-text (message)
  "The plain text of MESSAGE (a MIME string), with plain newlines."
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
  (:documentation "Prints each message's addresses, subject and text, instead of sending it."))

(defmethod send-message ((mailer log-mailer) from recipients message)
  (format (or (slot-value mailer 'stream) *error-output*)
          "~&--- mail from ~A to ~{~A~^, ~}: ~A~%~A~&---~%"
          from recipients (message-header message "Subject") (message-text message)))

(defclass sent-message ()
  ((from :initarg :from :reader sent-message-from)
   (recipients :initarg :recipients :reader sent-message-recipients)
   (text :initarg :text :reader sent-message-text :documentation "The MIME message.")
   (time :initform (get-universal-time) :reader sent-message-time))
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

(defun send-mail (mail &key (mailer *mailer*))
  "Send MAIL now, waiting for the mailer.  QUEUE-MAIL sends it in the
background instead, and tries again when it fails."
  (send-message mailer (address-spec (mail-from mail)) (mail-recipients mail) (mail-string mail)))

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
evaluated each time, with LAMBDA-LIST's variables bound; HTML is a list of
forms written with Littoral's HTML tags (as in RENDER), inside *MAIL-LAYOUT*.
Without TEXT, the plain text is made from the HTML."
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
