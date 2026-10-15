;;;; outbox.lisp — mail kept in the database until it has gone
;;;;
;;;;   (create-mail-tables)
;;;;   (start-mail-delivery :database spec :mailer (make-smtp-mailer …))
;;;;   (queue-mail (welcome-mail user))
;;;;
;;;; QUEUE-MAIL writes the message to the mail_outbox table, with a durable
;;;; job (littoral/jobs) to send it, inside the request's transaction when
;;;; there is one, so mail goes only if the action that sent it commits.
;;;; The request doesn't wait for SMTP, and a slow mail server can't show who
;;;; has an account by how long the reset form takes.  The job runner sends
;;;; it; a failure is tried again after *MAIL-RETRY-SECONDS*, doubling, up to
;;;; *MAIL-ATTEMPTS* times, and a refusal (an SMTP 5xx) fails at once.  The
;;;; table keeps each message and how sending it went.  Several processes may
;;;; share it: each message is claimed by one before it is sent.

(in-package #:littoral.mail)

(defvar *mail-attempts* 8 "Times a message is tried before it is marked failed.")
(defvar *mail-retry-seconds* 60
  "Seconds before a failed message is tried again, doubling with each attempt.")
(defvar *mail-claim-seconds* 600
  "How long a process may take over a message before another may take it over.")

(defclass outbox-mail (littoral.db:persistent)
  ((sender :initarg :sender :initform nil :reader outbox-sender-address
           :documentation "The envelope's sender, a bare address.")
   (recipients :initarg :recipients :initform nil :reader outbox-recipients
               :documentation "The addresses it goes to, separated by spaces.")
   (subject :initarg :subject :initform nil :reader outbox-subject)
   (message :initarg :message :initform nil :reader outbox-message :documentation "The MIME message.")
   (status :initarg :status :initform "queued" :reader outbox-status
           :documentation "\"queued\", \"sending\", \"sent\" or \"failed\".")
   (attempts :initarg :attempts :initform 0 :reader outbox-attempts :documentation "Tries so far.")
   (next-attempt :initarg :next-attempt :initform 0 :reader outbox-next-attempt
                 :documentation "When it is next due, a universal time.")
   (last-error :initarg :last-error :initform nil :reader outbox-last-error
               :documentation "Why the last try failed, or NIL.")
   (created :initarg :created :initform nil :reader outbox-created
            :documentation "When it was queued, a universal time.")
   (sent :initarg :sent :initform nil :reader outbox-sent
         :documentation "When it was sent, a universal time, or NIL."))
  (:documentation "A message in the outbox, and how sending it has gone."))

(defun outbox-id (message)
  "MESSAGE's id in the outbox, for RETRY-MAIL."
  (littoral.db:object-id message))

(littoral:define-description outbox-mail
  ((sender) (recipients) (subject) (message) (status)
   (attempts :type :integer) (next-attempt :type :integer) (last-error)
   (created :type :integer) (sent :type :integer)))

(littoral.db:define-table outbox-mail :name "mail_outbox")

(littoral.db:define-migrations :littoral-mail (asdf:system-relative-pathname :littoral "migrations/mail/"))

(defvar *mail-databases* '() "Database specs whose outbox was made in this process.")
(defvar *mail-databases-lock* (sb-thread:make-mutex :name "littoral mail databases"))

(defun create-mail-tables ()
  "Create or bring up to date the outbox table (migrations :LITTORAL-MAIL),
and the job queue that sends it."
  (littoral.db:migrate :littoral-mail)
  (sb-thread:with-mutex (*mail-databases-lock*)
    (pushnew (copy-tree littoral.db:*database*) *mail-databases* :test #'equal))
  (littoral.jobs:create-job-tables))

(defun drop-mail-tables ()
  "Drop the outbox table.  The job queue CREATE-MAIL-TABLES made stays:
LITTORAL.JOBS:DROP-JOB-TABLES drops it."
  (sb-thread:with-mutex (*mail-databases-lock*)
    (setf *mail-databases* (remove littoral.db:*database* *mail-databases* :test #'equal)))
  (littoral.db:drop-table 'outbox-mail)
  (littoral.db:forget-migrations :littoral-mail))

;;; Queueing

(defun queue-mail (mail)
  "Put MAIL in the outbox, in the current database, with a job to send it;
returns its OUTBOX-MAIL."
  (let ((row (make-instance 'outbox-mail
                            :sender (address-spec (mail-from mail))
                            :recipients (format nil "~{~A~^ ~}" (mail-recipients mail))
                            :subject (mail-subject mail)
                            :message (mail-string mail)
                            :created (get-universal-time) :next-attempt (get-universal-time))))
    (littoral.db:db-insert row)
    (schedule-delivery (outbox-id row) (get-universal-time))
    row))

(defun outbox-sender (&key (from *mail-from*))
  "A function of (TO SUBJECT BODY) that queues a plain-text mail, for
LITTORAL.AUTH:*SEND-MAIL*."
  (lambda (to subject body)
    (queue-mail (make-mail :to to :from from :subject subject :text body))))

;;; Delivering: each message has a job, DELIVER-MAIL, that tries it once and
;;; schedules the next try when that fails.

(defvar *delivery-mailer* nil
  "What START-MAIL-DELIVERY was told to send with; NIL for *MAILER*.")

(defun delivery-mailer () (or *delivery-mailer* *mailer*))

(defun schedule-delivery (id at)
  "Have the job runner try the outbox message ID at AT, a universal time.
One job waits per message, however often this is asked."
  (let ((key (format nil "mail:~D" id)))
    (unless (littoral.jobs:enqueue-job (list 'deliver-mail id) :at at :key key)
      ;; One already waits: bring it forward if it waits longer.
      (when (plusp (littoral.db:db-execute "UPDATE job_queue SET run_at = ? WHERE unique_key = ? AND status = 'queued' AND attempts = 0 AND run_at > ?"
                                           at key at))
        (littoral.jobs::wake-runner)))))

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
  "Send ROW, and record how it went; true when it was sent.  A failure that
may pass is scheduled to be tried again."
  (handler-case
      (progn
        (send-counted mailer (outbox-sender-address row)
                      (cl-ppcre:split " " (outbox-recipients row)) (outbox-message row))
        (littoral.db:db-execute "UPDATE mail_outbox SET status = 'sent', attempts = attempts + 1, sent = ?, last_error = ? WHERE id = ?"
                                (get-universal-time) nil (outbox-id row))
        t)
    (error (e)
      (let* ((attempts (1+ (or (outbox-attempts row) 0)))
             (give-up (or (smtp-error-permanent-p e) (>= attempts *mail-attempts*)))
             (next (+ (get-universal-time) (* *mail-retry-seconds* (expt 2 (1- attempts))))))
        (littoral.db:db-execute "UPDATE mail_outbox SET status = ?, attempts = ?, next_attempt = ?, last_error = ? WHERE id = ?"
                                (if give-up "failed" "queued") attempts next (error-text e) (outbox-id row))
        (unless give-up (schedule-delivery (outbox-id row) next))
        nil))))

(defun due-p (row)
  (and (member (outbox-status row) '("queued" "sending") :test #'string=)
       (<= (outbox-next-attempt row) (get-universal-time))))

(littoral.jobs:define-job (deliver-mail :attempts 3) (id)
  "Send the outbox message ID with the delivery mailer, if it's due."
  (let ((row (littoral.db:db-find 'outbox-mail id)))
    (cond ((null row))
          ((due-p row) (and (claim row) (deliver-one row (delivery-mailer))))
          ;; Not yet (it was retried by hand, or another process has it): come back then.
          ((member (outbox-status row) '("queued" "sending") :test #'string=)
           (schedule-delivery id (outbox-next-attempt row))))))

(littoral.jobs:define-job deliver-due-mail ()
  "Send whatever in the outbox is due, such as mail queued before its jobs were."
  (deliver-queued-mail))

(defun deliver-queued-mail (&key (mailer (delivery-mailer)) (limit 50))
  "Send at most LIMIT messages in the current database's outbox that are due,
with MAILER (by default START-MAIL-DELIVERY's, or else *MAILER*); returns how
many were sent.  A failure is recorded and tried again later, as by the job
runner.  Their jobs do this one at a time; a test can call it to send what's
queued without waiting."
  (let ((due (littoral.db:db-select 'outbox-mail
                                    :where "status IN ('queued', 'sending') AND next_attempt <= ?"
                                    :params (list (get-universal-time)) :order-by "id" :limit limit)))
    (count-if (lambda (row) (and (claim row) (deliver-one row mailer))) due)))

(defvar *delivery-runner* nil "The job runner threads START-MAIL-DELIVERY started, if it did.")

(defun mail-delivery-running-p ()
  "True while START-MAIL-DELIVERY's mailer is set and a job runner runs."
  (and *delivery-mailer* (littoral.jobs:job-runner-running-p)))

(defun start-mail-delivery (&key (database littoral.db:*database*) (mailer *mailer*) (interval 10)
                              (attempts *mail-attempts*) (retry-seconds *mail-retry-seconds*))
  "Send the outbox of DATABASE (a spec, as LITTORAL.DB:*DATABASE* holds) with
MAILER.  The job runner (LITTORAL.JOBS) sends it, at once when mail is queued
in this process, and within INTERVAL seconds for retries and other processes'
mail; this starts one for DATABASE unless one is running.  ATTEMPTS and
RETRY-SECONDS set *MAIL-ATTEMPTS* and *MAIL-RETRY-SECONDS*."
  (unless database (error "START-MAIL-DELIVERY needs a database."))
  (setf *delivery-mailer* mailer
        *mail-attempts* attempts
        *mail-retry-seconds* retry-seconds)
  (unless (littoral.jobs:job-runner-running-p)
    (littoral.jobs:start-job-runner :database database :interval interval)
    (setf *delivery-runner* littoral.jobs::*runner-threads*))
  ;; Mail queued before now, or whose job was lost, goes too.
  (let ((littoral.db:*database* database))
    (littoral.jobs:enqueue-job (list 'deliver-due-mail) :key "deliver-due-mail"))
  t)

(defun stop-mail-delivery ()
  "Stop sending mail: the job runner too, if START-MAIL-DELIVERY started it,
letting it finish the message it is sending.  An SMTP-MAILER's open
connections are closed."
  (when (and *delivery-runner* (eq *delivery-runner* littoral.jobs::*runner-threads*))
    (littoral.jobs:stop-job-runner))
  (let ((mailer (shiftf *delivery-mailer* nil)))
    (when (typep mailer 'smtp-mailer) (close-smtp-mailer mailer)))
  (setf *delivery-runner* nil))

;;; Looking at the outbox

(defun outbox-messages (&key status (limit 50))
  "The outbox's messages, newest first; only those with STATUS (a string) if given."
  (if status
      (littoral.db:db-select 'outbox-mail :where "status = ?" :params (list status) :order-by "id DESC" :limit limit)
      (littoral.db:db-select 'outbox-mail :order-by "id DESC" :limit limit)))

(defun retry-mail (id)
  "Send the message ID again now, with its attempts counted afresh, unless it
was sent."
  (when (plusp (littoral.db:db-execute "UPDATE mail_outbox SET status = 'queued', attempts = 0, next_attempt = ? WHERE id = ? AND status <> 'sent'"
                                       (get-universal-time) id))
    (schedule-delivery id (get-universal-time))))

(defun purge-sent-mail (&key (older-than (* 7 24 3600)))
  "Delete sent messages more than OLDER-THAN seconds old; returns how many."
  (littoral.db:db-execute "DELETE FROM mail_outbox WHERE status = 'sent' AND sent < ?"
                          (- (get-universal-time) older-than)))

;;; Metrics: /metrics reports each database whose outbox was made here

(defun write-mail-metrics (out)
  "Write the outboxes' metrics to OUT, in Prometheus's format."
  (let ((now (get-universal-time))
        (reports '()))
    (dolist (spec (sb-thread:with-mutex (*mail-databases-lock*) (copy-list *mail-databases*)))
      (push (cons (littoral.db:database-label spec)
                  (handler-case
                      (let ((littoral.db:*database* spec))
                        (list (littoral.db:db-query "SELECT status, COUNT(*) AS n FROM mail_outbox
GROUP BY status ORDER BY status")
                              (getf (first (littoral.db:db-query "SELECT MIN(created) AS oldest FROM mail_outbox
WHERE status IN ('queued', 'sending')"))
                                    :|oldest|)))
                    (error () :down)))
            reports))
    (setf reports (nreverse reports))
    (flet ((head (name help)
             (format out "# HELP ~A ~A~%# TYPE ~A gauge~%" name help name)))
      (head "littoral_mail_outbox" "Mail in the outbox, by database and status.")
      (loop for (database . report) in reports
            unless (eq report :down)
              do (dolist (row (first report))
                   (format out "littoral_mail_outbox{database=\"~A\",status=\"~A\"} ~D~%"
                           (littoral:metric-label database) (littoral:metric-label (getf row :|status|))
                           (getf row :|n|))))
      (head "littoral_mail_oldest_unsent_seconds"
            "How long the oldest mail still to be sent has waited, by database: 0 when there is none.")
      (loop for (database . report) in reports
            unless (eq report :down)
              do (format out "littoral_mail_oldest_unsent_seconds{database=\"~A\"} ~D~%"
                         (littoral:metric-label database)
                         (if (second report) (max 0 (- now (second report))) 0)))
      (head "littoral_mail_outbox_database_up" "Whether each database's outbox could be read.")
      (loop for (database . report) in reports
            do (format out "littoral_mail_outbox_database_up{database=\"~A\"} ~D~%"
                       (littoral:metric-label database) (if (eq report :down) 0 1))))))

(littoral:add-metrics-source "mail" 'write-mail-metrics)
