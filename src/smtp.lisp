;;;; smtp.lisp — sending mail over SMTP
;;;;
;;;;   (make-smtp-mailer :host "smtp.example.org" :username "app" :password "…")   ; STARTTLS on 587
;;;;   (smtp-mailer-from-url "smtps://app:secret@smtp.example.org")             ; TLS on 465
;;;;
;;;; With :STARTTLS (the default) the connection must turn into TLS before
;;;; anything else is said, and the server's certificate must match its name;
;;;; a server that doesn't offer STARTTLS is refused, never used in the clear.
;;;; :NONE is for a relay on the same machine.

(in-package #:littoral.mail)

(define-condition smtp-error (error)
  ((code :initarg :code :initform nil :reader smtp-error-code
         :documentation "The server's reply code, such as 550, or NIL when the conversation itself failed.")
   (message :initarg :message :reader smtp-error-message))
  (:report (lambda (c s)
             (format s "SMTP~@[ ~D~]: ~A" (smtp-error-code c) (smtp-error-message c))))
  (:documentation "The SMTP server refused, or the conversation went wrong."))

(setf (documentation 'smtp-error-code 'function)
      "The server's reply code in an SMTP-ERROR, such as 550, or NIL when the conversation itself failed.")

(defun smtp-error-permanent-p (condition)
  "True when CONDITION is a refusal (a 5xx reply) that trying again won't change."
  (let ((code (and (typep condition 'smtp-error) (smtp-error-code condition))))
    (and code (>= code 500))))

(defclass smtp-mailer ()
  ((host :initarg :host :reader smtp-host)
   (port :initarg :port :reader smtp-port)
   (security :initarg :security :reader smtp-security :documentation ":STARTTLS, :TLS or :NONE.")
   (username :initarg :username :initform nil :reader smtp-username)
   (password :initarg :password :initform nil :reader smtp-password)
   (helo :initarg :helo :reader smtp-helo)
   (verify :initarg :verify :initform t :reader smtp-verify)
   (ca-file :initarg :ca-file :initform nil :reader smtp-ca-file)
   (timeout :initarg :timeout :initform 30 :reader smtp-timeout))
  (:documentation "Sends mail through an SMTP server: MAKE-SMTP-MAILER makes one."))

(defmethod print-object ((mailer smtp-mailer) stream)
  (print-unreadable-object (mailer stream :type t)
    (format stream "~A:~D ~(~A~)" (smtp-host mailer) (smtp-port mailer) (smtp-security mailer))))

(defun make-smtp-mailer (&key (host "localhost") port (security :starttls) username password
                           (helo (machine-instance)) (verify t) ca-file (timeout 30))
  "A mailer sending through the SMTP server at HOST.  SECURITY is :STARTTLS
(port 587 by default), :TLS (465) or :NONE (25, for a relay on this machine).
With USERNAME, signs in with AUTH PLAIN (or LOGIN).  The server's certificate
is checked against the system's authorities, or CA-FILE's, unless VERIFY is NIL.
TIMEOUT, in seconds, bounds each send."
  (check-type security (member :starttls :tls :none))
  (make-instance 'smtp-mailer :host host :security security :username username :password password
                              :helo helo :verify verify :ca-file ca-file :timeout timeout
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

;;; The conversation

(defun read-octet-line (stream)
  "A line from STREAM without its CRLF, or NIL at the end."
  (let ((octets (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (loop for byte = (read-byte stream nil nil)
          do (cond ((null byte) (return (and (plusp (length octets)) (decode-line octets))))
                   ((= byte 10) (return (decode-line octets)))
                   ((> (length octets) 4096) (error 'smtp-error :message "Reply line too long"))
                   (t (vector-push-extend byte octets))))))

(defun decode-line (octets)
  (string-right-trim '(#\Return)
                     (sb-ext:octets-to-string (coerce octets '(vector (unsigned-byte 8)))
                                              :external-format '(:utf-8 :replacement #\?))))

(defun read-reply (stream)
  "The server's reply: its code and its lines' texts."
  (let ((lines '()) (code nil))
    (loop for line = (read-octet-line stream)
          do (unless (and line (>= (length line) 3) (every #'digit-char-p (subseq line 0 3)))
               (error 'smtp-error :message (format nil "Unexpected reply ~S" line)))
             (setf code (parse-integer line :end 3))
             (push (if (> (length line) 4) (subseq line 4) "") lines)
          until (or (= (length line) 3) (char= (char line 3) #\Space)))
    (values code (nreverse lines))))

(defun write-line-crlf (stream string)
  (write-sequence (utf-8 string) stream)
  (write-sequence #(13 10) stream))

(defun command-verb (control)
  "The command a format CONTROL sends, for error messages: never its
arguments, which may be credentials."
  (let ((verb (and control (subseq control 0 (or (position-if-not #'alpha-char-p control) (length control))))))
    (and (member verb '("EHLO" "STARTTLS" "AUTH" "MAIL" "RCPT" "DATA" "QUIT") :test #'string=) verb)))

(defun command (stream expected control &rest arguments)
  "Send a command and read the reply, which must have a code in EXPECTED;
returns the reply's lines."
  (when control
    (write-line-crlf stream (apply #'format nil control arguments))
    (force-output stream))
  (multiple-value-bind (code lines) (read-reply stream)
    (unless (member code expected)
      (error 'smtp-error :code code
                         :message (format nil "~{~A~^ ~}~@[ (after ~A)~]" lines (command-verb control))))
    lines))

(defun tls-stream (socket mailer)
  "SOCKET's stream wrapped in TLS, the certificate checked unless VERIFY is NIL."
  (if (smtp-verify mailer)
      (let ((context (cl+ssl:make-context :verify-location (or (smtp-ca-file mailer) :default))))
        (unwind-protect
             (cl+ssl:with-global-context (context)
               (cl+ssl:make-ssl-client-stream (usocket:socket-stream socket)
                                              :hostname (smtp-host mailer) :verify :required))
          (cl+ssl:ssl-ctx-free context)))
      (cl+ssl:make-ssl-client-stream (usocket:socket-stream socket)
                                     :hostname (smtp-host mailer) :verify nil)))

(defun capabilities (lines)
  "The EHLO reply's keywords, upper-cased: (\"STARTTLS\" \"AUTH PLAIN LOGIN\" …)."
  (mapcar #'string-upcase (rest lines)))

(defun capability (name capabilities)
  (find-if (lambda (line) (or (string= line name) (alexandria:starts-with-subseq (format nil "~A " name) line)))
           capabilities))

(defun authenticate (stream mailer capabilities)
  (let ((auth (capability "AUTH" capabilities))
        (user (smtp-username mailer)) (password (or (smtp-password mailer) "")))
    (flet ((b64 (string) (cl-base64:usb8-array-to-base64-string (utf-8 string))))
      (cond ((null auth) (error 'smtp-error :message "The server doesn't offer AUTH"))
            ((search " PLAIN" auth)
             (command stream '(235) "AUTH PLAIN ~A" (b64 (format nil "~C~A~C~A" (code-char 0) user (code-char 0) password))))
            ((search " LOGIN" auth)
             (command stream '(334) "AUTH LOGIN")
             (command stream '(334) "~A" (b64 user))
             (command stream '(235) "~A" (b64 password)))
            (t (error 'smtp-error :message (format nil "No AUTH method in common: ~A" auth)))))))

(defun write-data (stream message)
  "MESSAGE's lines, dot-stuffed, then the lone dot that ends it."
  (dolist (line (crlf-lines message))
    (write-line-crlf stream (if (and (plusp (length line)) (char= (char line 0) #\.))
                                (concatenate 'string "." line)
                                line)))
  (write-line-crlf stream ".")
  (force-output stream))

(defmethod send-message ((mailer smtp-mailer) from recipients message)
  (let ((socket (usocket:socket-connect (smtp-host mailer) (smtp-port mailer)
                                        :element-type '(unsigned-byte 8) :timeout (smtp-timeout mailer)))
        (stream nil))
    (unwind-protect
         (sb-sys:with-deadline (:seconds (smtp-timeout mailer))
           (setf stream (if (eq (smtp-security mailer) :tls)
                            (tls-stream socket mailer)
                            (usocket:socket-stream socket)))
           (command stream '(220) nil)
           (let ((capabilities (capabilities (command stream '(250) "EHLO ~A" (smtp-helo mailer)))))
             (when (eq (smtp-security mailer) :starttls)
               (unless (capability "STARTTLS" capabilities)
                 (error 'smtp-error :message "The server doesn't offer STARTTLS; not sending in the clear"))
               (command stream '(220) "STARTTLS")
               (setf stream (tls-stream socket mailer)
                     capabilities (capabilities (command stream '(250) "EHLO ~A" (smtp-helo mailer)))))
             (when (smtp-username mailer)
               (authenticate stream mailer capabilities))
             (command stream '(250) "MAIL FROM:<~A>" from)
             (dolist (recipient recipients)
               (command stream '(250 251) "RCPT TO:<~A>" recipient))
             (command stream '(354) "DATA")
             (write-data stream message)
             (command stream '(250) nil)
             (ignore-errors (command stream '(221) "QUIT"))))
      (ignore-errors (when stream (close stream)))
      (ignore-errors (usocket:socket-close socket)))))
