;;;; outbox.lisp — mail kept in the database until it has gone
;;;;
;;;;   (create-mail-tables)
;;;;   (start-mail-delivery :database spec :mailer (make-smtp-mailer …))
;;;;   (queue-mail (welcome-mail user))
;;;;
;;;; QUEUE-MAIL writes the message to the mail_outbox table, inside the
;;;; request's transaction when there is one, so mail goes only if the
;;;; action that sent it commits.  The request doesn't wait for SMTP, and a
;;;; slow mail server can't show who has an account by how long the reset
;;;; form takes.  A delivery thread sends what's due; a failure is tried
;;;; again after *MAIL-RETRY-SECONDS*, doubling, up to *MAIL-ATTEMPTS* times,
;;;; and a refusal (an SMTP 5xx) fails at once.  Several processes may share
;;;; the table: each message is claimed by one before it is sent.

(in-package #:littoral.mail)

(defvar *mail-attempts* 8 "Times a message is tried before it is marked failed.")
(defvar *mail-retry-seconds* 60
  "Seconds before a failed message is tried again, doubling with each attempt.")
(defvar *mail-claim-seconds* 600
  "How long a process may take over a message before another may take it over.")

(defclass outbox-mail (littoral.db:persistent)
  ((sender :initarg :sender :initform nil :reader outbox-sender-address)
   (recipients :initarg :recipients :initform nil :reader outbox-recipients
               :documentation "The addresses it goes to, separated by spaces.")
   (subject :initarg :subject :initform nil :reader outbox-subject)
   (message :initarg :message :initform nil :reader outbox-message :documentation "The MIME message.")
   (status :initarg :status :initform "queued" :reader outbox-status
           :documentation "\"queued\", \"sending\", \"sent\" or \"failed\".")
   (attempts :initarg :attempts :initform 0 :reader outbox-attempts)
   (next-attempt :initarg :next-attempt :initform 0 :reader outbox-next-attempt)
   (last-error :initarg :last-error :initform nil :reader outbox-last-error)
   (created :initarg :created :initform nil :reader outbox-created)
   (sent :initarg :sent :initform nil :reader outbox-sent))
  (:documentation "A message in the outbox, and how sending it has gone."))

(defun outbox-id (message)
  "MESSAGE's id in the outbox, for RETRY-MAIL."
  (littoral.db:object-id message))

(littoral:define-description outbox-mail
  ((sender) (recipients) (subject) (message) (status)
   (attempts :type :integer) (next-attempt :type :integer) (last-error)
   (created :type :integer) (sent :type :integer)))

(littoral.db:define-table outbox-mail :name "mail_outbox")

(defun create-mail-tables ()
  "Create the outbox table unless it exists."
  (littoral.db:create-table 'outbox-mail))

(defun drop-mail-tables ()
  "Drop the outbox table."
  (littoral.db:drop-table 'outbox-mail))

;;; Queueing

(defvar *delivery-lock* (sb-thread:make-mutex :name "mail delivery"))
(defvar *delivery-wanted* (sb-thread:make-waitqueue))
(defvar *delivery-pending* nil "True when mail was queued since the delivery thread last looked.")

(defun wake-delivery ()
  (sb-thread:with-mutex (*delivery-lock*)
    (setf *delivery-pending* t)
    (sb-thread:condition-broadcast *delivery-wanted*)))

(defun queue-mail (mail)
  "Put MAIL in the outbox, in the current database, for the delivery thread
to send; returns its OUTBOX-MAIL."
  (let ((row (make-instance 'outbox-mail
                            :sender (address-spec (mail-from mail))
                            :recipients (format nil "~{~A~^ ~}" (mail-recipients mail))
                            :subject (mail-subject mail)
                            :message (mail-string mail)
                            :created (get-universal-time) :next-attempt (get-universal-time))))
    (littoral.db:db-insert row)
    (wake-delivery)
    row))

(defun outbox-sender (&key (from *mail-from*))
  "A function of (TO SUBJECT BODY) that queues a plain-text mail, for
LITTORAL.AUTH:*SEND-MAIL*."
  (lambda (to subject body)
    (queue-mail (make-mail :to to :from from :subject subject :text body))))

;;; Delivering

(defun claim (row)
  "Take ROW for this process; true unless another got there first."
  (let ((now (get-universal-time)))
    (= 1 (littoral.db:db-execute
          "UPDATE mail_outbox SET status = 'sending', next_attempt = ? WHERE id = ? AND status = ? AND next_attempt = ?"
          (+ now *mail-claim-seconds*) (outbox-id row) (outbox-status row) (outbox-next-attempt row)))))

(defun error-text (condition)
  (let ((text (handler-case (princ-to-string condition) (error () "an error"))))
    (subseq text 0 (min 500 (length text)))))

(defun deliver-one (row mailer)
  "Send ROW, and record how it went; true when it was sent."
  (handler-case
      (progn
        (send-message mailer (outbox-sender-address row)
                      (cl-ppcre:split " " (outbox-recipients row)) (outbox-message row))
        (littoral.db:db-execute "UPDATE mail_outbox SET status = 'sent', attempts = attempts + 1, sent = ?, last_error = ? WHERE id = ?"
                                (get-universal-time) nil (outbox-id row))
        t)
    (error (e)
      (let* ((attempts (1+ (or (outbox-attempts row) 0)))
             (give-up (or (smtp-error-permanent-p e) (>= attempts *mail-attempts*))))
        (littoral.db:db-execute "UPDATE mail_outbox SET status = ?, attempts = ?, next_attempt = ?, last_error = ? WHERE id = ?"
                                (if give-up "failed" "queued") attempts
                                (+ (get-universal-time) (* *mail-retry-seconds* (expt 2 (1- attempts))))
                                (error-text e) (outbox-id row))
        nil))))

(defun deliver-queued-mail (&key (mailer *mailer*) (limit 50))
  "Send the messages in the current database's outbox that are due, with
MAILER; returns how many were sent.  The delivery thread calls this; so can
a test, to send what's queued without waiting."
  (let ((due (littoral.db:db-select 'outbox-mail
                                    :where "status IN ('queued', 'sending') AND next_attempt <= ?"
                                    :params (list (get-universal-time)) :order-by "id" :limit limit)))
    (count-if (lambda (row) (and (claim row) (deliver-one row mailer))) due)))

(defvar *delivery-thread* nil)
(defvar *delivery-stop* nil)

(defun mail-delivery-running-p ()
  "True while the delivery thread runs."
  (and *delivery-thread* (sb-thread:thread-alive-p *delivery-thread*)))

(defun start-mail-delivery (&key (database littoral.db:*database*) (mailer *mailer*) (interval 10)
                              (attempts *mail-attempts*) (retry-seconds *mail-retry-seconds*))
  "Send the outbox of DATABASE (a spec, as LITTORAL.DB:*DATABASE* holds) with
MAILER from a background thread: at once when mail is queued in this process,
and every INTERVAL seconds for retries and other processes' mail.  ATTEMPTS
and RETRY-SECONDS stand for *MAIL-ATTEMPTS* and *MAIL-RETRY-SECONDS* there."
  (stop-mail-delivery)
  (unless database (error "START-MAIL-DELIVERY needs a database."))
  (setf *delivery-stop* nil
        *delivery-thread*
        (sb-thread:make-thread
         (lambda ()
           (let ((littoral.db:*database* database)
                 (*mail-attempts* attempts)
                 (*mail-retry-seconds* retry-seconds))
             (loop until *delivery-stop*
                   do (handler-case (littoral::with-sane-printing () (deliver-queued-mail :mailer mailer))
                        ;; A busy or vanished database: try again next time.
                        (error () nil))
                      (sb-thread:with-mutex (*delivery-lock*)
                        (unless (or *delivery-pending* *delivery-stop*)
                          (littoral::wait-on *delivery-wanted* *delivery-lock* interval))
                        (when *delivery-pending*
                          (setf *delivery-pending* nil)
                          ;; QUEUE-MAIL runs inside the request's transaction:
                          ;; give it a moment to commit before looking.
                          (sb-thread:release-mutex *delivery-lock*)
                          (unwind-protect (sleep 0.2)
                            (sb-thread:grab-mutex *delivery-lock*)))))))
         :name "littoral mail delivery"))
  *delivery-thread*)

(defun stop-mail-delivery ()
  "Stop the delivery thread, letting it finish the message it is sending."
  (when (mail-delivery-running-p)
    (setf *delivery-stop* t)
    (wake-delivery)
    (sb-thread:join-thread *delivery-thread* :default nil :timeout 30))
  (setf *delivery-thread* nil))

;;; Looking at the outbox

(defun outbox-messages (&key status (limit 50))
  "The outbox's messages, newest first; only those with STATUS (a string) if given."
  (if status
      (littoral.db:db-select 'outbox-mail :where "status = ?" :params (list status) :order-by "id DESC" :limit limit)
      (littoral.db:db-select 'outbox-mail :order-by "id DESC" :limit limit)))

(defun retry-mail (id)
  "Send the message ID again now, with its attempts counted afresh."
  (littoral.db:db-execute "UPDATE mail_outbox SET status = 'queued', attempts = 0, next_attempt = ? WHERE id = ? AND status <> 'sent'"
                          (get-universal-time) id)
  (wake-delivery))

(defun purge-sent-mail (&key (older-than (* 7 24 3600)))
  "Delete sent messages more than OLDER-THAN seconds old; returns how many."
  (littoral.db:db-execute "DELETE FROM mail_outbox WHERE status = 'sent' AND sent < ?"
                          (- (get-universal-time) older-than)))
