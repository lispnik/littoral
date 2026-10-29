;;;; durable-jobs.lisp — background jobs kept in the database
;;;;
;;;;   (define-job (send-digest :attempts 5) (user-id)
;;;;     (queue-mail (digest-mail (find-user-by-id user-id))))
;;;;
;;;;   (define-job (tidy-up :every 3600) ()
;;;;     (purge-durable-jobs))
;;;;
;;;;   (create-job-tables)
;;;;   (start-job-runner :database spec :threads 2)
;;;;   (enqueue-job (list 'send-digest 42) :in 600)
;;;;
;;;; ENQUEUE-JOB writes a row to the job_queue table, inside the request's
;;;; transaction when there is one, so the job exists only if the action that
;;;; asked for it commits; it survives restarts, and any process sharing the
;;;; database may run it.  A job is its name and its arguments, which must
;;;; print readably (numbers, strings, symbols, lists): pass ids, not objects.
;;;;
;;;; A runner claims a due job by updating its row, so each is run by one
;;;; process at a time, and holds it for the job's TIMEOUT: a job whose
;;;; process died is taken over once that has passed, so a job may run more
;;;; than once and should be safe to repeat.  With :TRANSACTION its database
;;;; work and being marked done commit together.  A job that signals is tried
;;;; again after RETRY-SECONDS, doubling, up to ATTEMPTS times; ABANDON-JOB
;;;; fails it at once.  A job defined with :EVERY is always scheduled once
;;;; more.  Runners take jobs only from their QUEUES ("default"), and only
;;;; jobs this process defines.
;;;;
;;;; SUBMIT-JOB (in Littoral itself) is the in-memory kind, which reports to
;;;; the page as it goes; these are for work that must not be lost.

(defpackage #:littoral.jobs
  (:use #:cl)
  (:documentation "Load it with `(asdf:load-system :littoral/jobs)`.  Background jobs kept in the
database: retried, scheduled, and run by any process.")
  (:export #:define-job #:enqueue-job #:daily-at
           #:create-job-tables #:drop-job-tables #:job-tables-p
           #:run-due-jobs #:start-job-runner #:stop-job-runner #:job-runner-running-p
           #:*durable-job* #:note-job-progress #:abandon-job #:job-abandoned #:job-cancelled
           #:*durable-jobs-channel* #:durable-job-view #:durable-job-view-id
           #:durable-job #:durable-job-id #:durable-job-name #:durable-job-arguments #:durable-job-queue
           #:durable-job-status #:durable-job-attempts #:durable-job-run-at #:durable-job-key
           #:durable-job-progress #:durable-job-progress-fraction #:durable-job-cancel-requested-p
           #:durable-job-last-error #:durable-job-created #:durable-job-finished
           #:find-durable-job #:durable-jobs #:durable-job-counts
           #:retry-durable-job #:cancel-durable-job #:purge-durable-jobs))

(defpackage #:littoral.jobs.stored
  (:use #:cl)
  (:documentation "The package jobs' names and arguments are printed and read in: CL's
symbols appear bare, all others with their packages."))

(in-package #:littoral.jobs)

;;; Definitions

(defstruct (job-definition (:conc-name definition-))
  name function queue attempts retry-seconds timeout transaction every)

(defvar *definitions* (make-hash-table :test 'equal) "A job's name, as stored → its JOB-DEFINITION.")

(defun stored-text (object)
  "OBJECT printed so that READ-STORED gives it back, symbols with their packages."
  (with-standard-io-syntax
    (let ((*package* (find-package '#:littoral.jobs.stored)))
      (prin1-to-string object))))

(defun read-stored (text)
  (with-standard-io-syntax
    (let ((*package* (find-package '#:littoral.jobs.stored))
          (*read-eval* nil))
      (read-from-string text))))

(defun register-job (name function &key (queue "default") (attempts 5) (retry-seconds 30)
                                        (timeout 600) transaction every)
  (check-type every (or null (integer 1) function symbol))
  (setf (gethash (stored-text name) *definitions*)
        (make-job-definition :name name :function function :queue queue :attempts attempts
                             :retry-seconds retry-seconds :timeout timeout
                             :transaction transaction :every every))
  name)

(defmacro define-job (name-and-options lambda-list &body body)
  "Define the job NAME, run with arguments as LAMBDA-LIST takes them; also a
function NAME that runs BODY at once.  NAME-AND-OPTIONS is NAME or (NAME
&key QUEUE ATTEMPTS RETRY-SECONDS TIMEOUT TRANSACTION EVERY):
  QUEUE          the queue it goes to, \"default\"
  ATTEMPTS       tries before it is marked failed, 5
  RETRY-SECONDS  the wait before the second try, doubling after, 30
  TIMEOUT        seconds a runner holds it before another may take it over, 600
  TRANSACTION    true to run it, and mark it done, in one transaction
  EVERY          seconds between runs, or a function from a universal time to
                 the next time to run (see DAILY-AT): it then takes no arguments,
                 is scheduled by the runners, and is never enqueued by hand."
  (destructuring-bind (name &rest options) (if (listp name-and-options) name-and-options (list name-and-options))
    `(progn
       (defun ,name ,lambda-list ,@body)
       (register-job ',name ',name ,@options))))

(defun find-definition (name)
  (gethash (if (stringp name) name (stored-text name)) *definitions*))

(defun daily-at (hour &optional (minute 0))
  "For :EVERY: once a day, at HOUR:MINUTE local time."
  (lambda (time)
    (loop for day from 0
          for next = (multiple-value-bind (s m h date month year) (decode-universal-time (+ time (* day 86400)))
                       (declare (ignore s m h))
                       (encode-universal-time 0 minute hour date month year))
          when (> next time) return next)))

(defun next-run (definition after)
  "When DEFINITION's recurring job runs next, after one due at AFTER."
  (let ((every (definition-every definition))
        (now (get-universal-time)))
    (if (integerp every)
        (let ((next (+ after every)))
          (if (> next now) next (+ now every)))
        (funcall every (max now after)))))

;;; The table

(littoral.db:define-migrations :littoral-jobs (asdf:system-relative-pathname :littoral "migrations/jobs/"))

(defvar *job-databases* '() "Database specs whose job tables were made in this process.")
(defvar *job-databases-lock* (sb-thread:make-mutex :name "littoral job databases"))

(defun job-tables-p ()
  "True when CREATE-JOB-TABLES ran for the current database in this process,
as it does through CREATE-MAIL-TABLES: the admin then shows the job queue."
  (and littoral.db:*database*
       (sb-thread:with-mutex (*job-databases-lock*)
         (member littoral.db:*database* *job-databases* :test #'equal))
       t))

(defun create-job-tables ()
  "Create or bring up to date the job_queue table (migrations :LITTORAL-JOBS)."
  (littoral.db:migrate :littoral-jobs)
  (sb-thread:with-mutex (*job-databases-lock*)
    (pushnew (copy-tree littoral.db:*database*) *job-databases* :test #'equal))
  t)

(defun drop-job-tables ()
  "Drop the job_queue table, and forget it for JOB-TABLES-P."
  (sb-thread:with-mutex (*job-databases-lock*)
    (setf *job-databases* (remove littoral.db:*database* *job-databases* :test #'equal)))
  (littoral.db:db-execute "DROP TABLE IF EXISTS job_queue")
  (littoral.db:forget-migrations :littoral-jobs))

(defclass durable-job ()
  ((id :initarg :id :reader durable-job-id :documentation "Its id, as ENQUEUE-JOB returned it.")
   (name :initarg :name :reader durable-job-name :documentation "The job's name, a symbol (or its text, when unreadable here).")
   (arguments :initarg :arguments :reader durable-job-arguments
              :documentation "The list of arguments it is run with (or its text, when unreadable here).")
   (queue :initarg :queue :reader durable-job-queue :documentation "The queue it is in, a string.")
   (status :initarg :status :reader durable-job-status
           :documentation "\"queued\", \"running\", \"done\", \"failed\" or \"cancelled\".")
   (attempts :initarg :attempts :reader durable-job-attempts
             :documentation "Tries so far; inside the job, which try this is.")
   (run-at :initarg :run-at :reader durable-job-run-at
           :documentation "When it is due; while running, when another runner may take it over.")
   (key :initarg :key :reader durable-job-key :documentation "The KEY it was enqueued with, or NIL.")
   (progress :initarg :progress :reader durable-job-progress :documentation "What NOTE-JOB-PROGRESS said last.")
   (progress-fraction :initarg :progress-fraction :reader durable-job-progress-fraction
                      :documentation "How far it has got, from 0 to 1, as NOTE-JOB-PROGRESS's :FRACTION said last; or NIL.")
   (cancel-requested :initarg :cancel-requested :reader durable-job-cancel-requested-p
                     :documentation "True when CANCEL-DURABLE-JOB has asked it, running, to stop.")
   (last-error :initarg :last-error :reader durable-job-last-error
               :documentation "Why its last try failed: the error's text, then a backtrace; or NIL.")
   (created :initarg :created :reader durable-job-created :documentation "When it was queued, a universal time.")
   (finished :initarg :finished :reader durable-job-finished
             :documentation "When it was done, failed or cancelled, a universal time; or NIL."))
  (:documentation "A job in the job_queue table, as it was when read."))

(defmethod print-object ((job durable-job) stream)
  (print-unreadable-object (job stream :type t)
    (format stream "~D ~A ~A" (durable-job-id job) (durable-job-name job) (durable-job-status job))))

(defun stored-or-text (text)
  (handler-case (read-stored text) (error () text)))

(defun job-from-row (row)
  (flet ((column (name) (getf row (intern name :keyword))))
    (make-instance 'durable-job
                   :id (column "id") :name (stored-or-text (column "name"))
                   :arguments (stored-or-text (column "arguments")) :queue (column "queue")
                   :status (column "status") :attempts (column "attempts") :run-at (column "run_at")
                   :key (column "unique_key") :progress (column "progress")
                   :progress-fraction (let ((f (column "progress_fraction"))) (and f (float f 1d0)))
                   :cancel-requested (eql 1 (column "cancel_requested"))
                   :last-error (column "last_error") :created (column "created") :finished (column "finished"))))

(defun select-jobs (where &rest parameters)
  (mapcar #'job-from-row
          (apply #'littoral.db:db-query (format nil "SELECT * FROM job_queue ~A" where) parameters)))

(defun placeholders (list)
  (format nil "(~{~A~^, ~})" (mapcar (constantly "?") list)))

;;; Enqueueing

(defvar *runner-lock* (sb-thread:make-mutex :name "littoral job runner"))
(defvar *runner-wanted* (sb-thread:make-waitqueue))
(defvar *runner-generation* 0 "Counts ENQUEUE-JOBs, so a runner busy at the time looks again.")

(defun wake-runner ()
  (sb-thread:with-mutex (*runner-lock*)
    (incf *runner-generation*)
    (sb-thread:condition-broadcast *runner-wanted*)))

(defun insert-job (name-text arguments-text queue run-at key)
  "Insert a queued job; its id, or NIL when an untried job with KEY is queued already."
  (getf (first (littoral.db:db-query
                "INSERT INTO job_queue (name, arguments, queue, status, attempts, run_at, unique_key, created)
VALUES (?, ?, ?, 'queued', 0, ?, ?, ?) ON CONFLICT DO NOTHING RETURNING id"
                name-text arguments-text queue run-at key (get-universal-time)))
        :|id|))

(defun enqueue-job (call &key at in key queue)
  "Queue CALL, (NAME . ARGUMENTS), in the current database, to run at once,
IN seconds, or AT a universal time; its id.  With KEY (a string), nothing is
queued while a job with that key waits untried, and the value is NIL.  QUEUE
overrides the job's own.  Signals an error when NAME isn't a job DEFINE-JOB
defined, when it is defined with :EVERY, or when ARGUMENTS don't print
readably and read back as themselves."
  (destructuring-bind (name &rest arguments) call
    (let ((definition (or (find-definition name) (error "No job named ~S: see DEFINE-JOB." name)))
          (text (handler-case (stored-text arguments)
                  (print-not-readable ()
                    (error "~S's arguments must print readably (numbers, strings, symbols, lists): ~S"
                           name arguments)))))
      (unless (equalp arguments (read-stored text))
        (error "~S's arguments don't read back as themselves: ~S" name arguments))
      (when (definition-every definition)
        (error "~S runs every ~A by itself, and isn't enqueued." name (definition-every definition)))
      (prog1 (insert-job (stored-text name) text (or queue (definition-queue definition))
                         (cond (at at) (in (+ (get-universal-time) in)) (t (get-universal-time)))
                         key)
        (wake-runner)))))

(defun ensure-recurring-jobs (queues)
  "Queue the next run of each recurring job in QUEUES that has none.  Looks
before inserting: runners call this often, and SQLite has one writer."
  (maphash (lambda (text definition)
             (let ((key (format nil "every:~A" text)))
               (when (and (definition-every definition)
                          (member (definition-queue definition) queues :test #'string=)
                          (null (littoral.db:db-query "SELECT id FROM job_queue WHERE unique_key = ? AND status = 'queued' AND attempts = 0" key)))
                 (insert-job text (stored-text '()) (definition-queue definition)
                             (next-run definition (get-universal-time)) key))))
           *definitions*))

;;; Running

(define-condition job-abandoned (error)
  ((reason :initarg :reason :reader job-abandoned-reason))
  (:report (lambda (c s) (write-string (job-abandoned-reason c) s)))
  (:documentation "Signalled by ABANDON-JOB: the job fails without being tried again."))

(defun abandon-job (control &rest arguments)
  "From inside a job: fail it now, for the reason CONTROL and ARGUMENTS
format, without trying again."
  (error 'job-abandoned :reason (apply #'format nil control arguments)))

(define-condition job-cancelled (error) ()
  (:report "The job was cancelled.")
  (:documentation "Signalled by NOTE-JOB-PROGRESS in a job that CANCEL-DURABLE-JOB
has asked to stop: the job ends, marked cancelled, and isn't tried again."))

(defvar *durable-job* nil "The DURABLE-JOB this thread is running.")

;;; Pages showing jobs hear of changes made in this process by server push.

(defvar *durable-jobs-channel* (littoral:make-channel "durable jobs")
  "Published when a job changes in this process: it starts, notes progress,
ends, or is cancelled or retried.  DURABLE-JOB-VIEW subscribes to it.")

(defvar *last-progress-publish* 0
  "When NOTE-JOB-PROGRESS last published, in internal real time.")

(defun publish-job-change (&key progress)
  "Publish *DURABLE-JOBS-CHANNEL*; for PROGRESS, at most ten times a second,
since jobs may note their progress far more often than pages can show it."
  (let ((now (get-internal-real-time)))
    (when (or (not progress)
              (>= (- now *last-progress-publish*) (floor internal-time-units-per-second 10)))
      (when progress (setf *last-progress-publish* now))
      (littoral:publish *durable-jobs-channel*))))

(defun note-job-progress (text &key fraction)
  "From inside a job: record TEXT as how it's going (DURABLE-JOB-PROGRESS),
and FRACTION, when given, as how far it has got, from 0 to 1
(DURABLE-JOB-PROGRESS-FRACTION); and hold on to the job for another
TIMEOUT.  When CANCEL-DURABLE-JOB has asked the job to stop, signal
JOB-CANCELLED instead, ending it: call this between steps that may be
abandoned."
  (let ((job *durable-job*))
    (when job
      (when (eql 1 (getf (first (littoral.db:db-query "SELECT cancel_requested FROM job_queue WHERE id = ?"
                                                         (durable-job-id job)))
                         :|cancel_requested|))
        (error 'job-cancelled))
      (littoral.db:db-execute "UPDATE job_queue SET progress = ?, progress_fraction = COALESCE(CAST(? AS DOUBLE PRECISION), progress_fraction), run_at = ?
WHERE id = ? AND status = 'running' AND attempts = ?"
                              text (and fraction (float (max 0 (min 1 fraction)) 1d0))
                              (+ (get-universal-time) (definition-timeout (find-definition (durable-job-name job))))
                              (durable-job-id job) (durable-job-attempts job))
      (publish-job-change :progress t))))

(defun claim (job definition)
  "Take JOB, which was due, for this runner: the job as claimed, or NIL when
another runner got there first.  A job whose runner died having used its
last try is marked failed instead."
  (let ((now (get-universal-time))
        (attempts (durable-job-attempts job)))
    (if (and (string= (durable-job-status job) "running") (>= attempts (definition-attempts definition)))
        (progn
          (littoral.db:db-execute "UPDATE job_queue SET status = 'failed', finished = ?, last_error = ?
WHERE id = ? AND status = 'running' AND run_at = ? AND attempts = ?"
                                  now (format nil "Its runner stopped, or it ran longer than ~D seconds."
                                              (definition-timeout definition))
                                  (durable-job-id job) (durable-job-run-at job) attempts)
          nil)
        (when (= 1 (littoral.db:db-execute "UPDATE job_queue SET status = 'running', attempts = attempts + 1, run_at = ?
WHERE id = ? AND status = ? AND run_at = ? AND attempts = ?"
                                           (+ now (definition-timeout definition)) (durable-job-id job)
                                           (durable-job-status job) (durable-job-run-at job) attempts))
          (when (and (definition-every definition) (string= (durable-job-status job) "queued") (zerop attempts))
            (insert-job (stored-text (definition-name definition)) (stored-text '()) (definition-queue definition)
                        (next-run definition (durable-job-run-at job))
                        (format nil "every:~A" (stored-text (definition-name definition)))))
          (publish-job-change)
          (first (select-jobs "WHERE id = ?" (durable-job-id job)))))))

(defun mark-done (job)
  (prog1 (= 1 (littoral.db:db-execute "UPDATE job_queue SET status = 'done', finished = ?, last_error = NULL,
progress_fraction = CASE WHEN progress_fraction IS NULL THEN NULL ELSE 1 END
WHERE id = ? AND status = 'running' AND attempts = ?"
                                      (get-universal-time) (durable-job-id job) (durable-job-attempts job)))
    (publish-job-change)))

(defun mark-cancelled (job)
  "Record that JOB stopped when asked to."
  (littoral.db:db-execute "UPDATE job_queue SET status = 'cancelled', finished = ?, cancel_requested = 0
WHERE id = ? AND status = 'running' AND attempts = ?"
                          (get-universal-time) (durable-job-id job) (durable-job-attempts job))
  (publish-job-change)
  "cancelled")

(defun failure-text (condition backtrace)
  (let ((text (format nil "~A~@[~2%~A~]"
                      (handler-case (princ-to-string condition) (error () "an error")) backtrace)))
    (subseq text 0 (min 4000 (length text)))))

(defun mark-failed (job definition condition backtrace)
  "Record that JOB failed with CONDITION; how it ended, for the metrics:
\"retried\", \"failed\" or \"abandoned\"."
  (let* ((attempts (durable-job-attempts job))
         (abandoned (typep condition 'job-abandoned))
         (give-up (or abandoned (>= attempts (definition-attempts definition))))
         (now (get-universal-time)))
    ;; A job asked to stop isn't tried again: it is cancelled.
    (littoral.db:db-execute "UPDATE job_queue SET status = CASE WHEN cancel_requested = 1 THEN 'cancelled' ELSE CAST(? AS TEXT) END,
run_at = ?, finished = CASE WHEN cancel_requested = 1 THEN CAST(? AS BIGINT) ELSE CAST(? AS BIGINT) END,
last_error = ?, cancel_requested = 0
WHERE id = ? AND status = 'running' AND attempts = ?"
                            (if give-up "failed" "queued")
                            (+ now (* (definition-retry-seconds definition) (expt 2 (1- attempts))))
                            now (and give-up now) (failure-text condition backtrace)
                            (durable-job-id job) attempts)
    (publish-job-change)
    (cond (abandoned "abandoned") (give-up "failed") (t "retried"))))

(littoral:define-metric "littoral_durable_job_runs_total" :counter
  "Durable job runs in this process, by job and how they ended: done, retried, failed, abandoned or cancelled."
  :labels '("job" "result"))
(littoral:define-metric "littoral_durable_job_seconds" :histogram
  "How long durable job runs took, by job."
  :labels '("job") :buckets '(0.01 0.05 0.1 0.5 1 5 10 30 60 300 600))

(defun job-metric-name (definition)
  "The job's name as metrics label it: record-job."
  (string-downcase (princ-to-string (definition-name definition))))

(defun run-claimed (job definition)
  "Run JOB, claimed, and record how it went; true when it succeeded."
  (let ((name (job-metric-name definition))
        (outcome "failed"))
    (littoral:timing-metric ("littoral_durable_job_seconds" (list name))
      (unwind-protect (eq t (setf outcome (run-claimed-job job definition)))
        (littoral:count-metric "littoral_durable_job_runs_total"
                               (list name (if (eq outcome t) "done" outcome)))))))

(defun run-claimed-job (job definition)
  "Run JOB; T when it succeeded, otherwise how it ended (see MARK-FAILED)."
  (let ((backtrace nil))
    (handler-case
        ;; The backtrace is taken where the error is signalled, and kept
        ;; with its condition: the job may handle errors of its own.
        (handler-bind ((error (lambda (c)
                                (setf backtrace (cons c (with-output-to-string (s)
                                                          (sb-debug:print-backtrace :stream s :count 15)))))))
          (let ((*durable-job* job)
                (function (definition-function definition))
                (arguments (durable-job-arguments job)))
            (unless (listp arguments)
              (abandon-job "Its arguments can't be read here: ~A" arguments))
            (if (definition-transaction definition)
                (littoral.db:with-transaction ()
                  (apply function arguments)
                  (unless (mark-done job)
                    (error "Another runner took the job over; its work is rolled back.")))
                (progn (apply function arguments)
                       (mark-done job))))
          t)
      (job-cancelled ()
        (or (ignore-errors (mark-cancelled job)) "failed"))
      (error (e)
        (or (ignore-errors (mark-failed job definition e (and (eq (car backtrace) e) (cdr backtrace))))
            "failed")))))

(defun due-jobs (queues limit)
  (let ((names (loop for text being the hash-keys of *definitions* using (hash-value definition)
                     when (member (definition-queue definition) queues :test #'string=) collect text)))
    (when names
      (apply #'select-jobs
             (format nil "WHERE status IN ('queued', 'running') AND run_at <= ? AND queue IN ~A AND name IN ~A
ORDER BY run_at, id LIMIT ~D"
                     (placeholders queues) (placeholders names) limit)
             (get-universal-time) (append queues names)))))

(defun run-next-job (queues)
  "Claim and run one due job from QUEUES; true when there was one."
  (dolist (job (due-jobs queues 10) nil)
    (let* ((definition (find-definition (durable-job-name job)))
           (claimed (and definition (claim job definition))))
      (when claimed
        (run-claimed claimed definition)
        (return t)))))

(defun run-due-jobs (&key (queues '("default")) (limit 100))
  "Run the jobs in QUEUES of the current database that are due, here and now,
at most LIMIT of them; how many ran.  Runners call this; so can a test."
  (ensure-recurring-jobs queues)
  (loop for count from 0 below limit
        while (run-next-job queues)
        finally (return count)))

;;; Runners

(defvar *runner-threads* '())
(defvar *runner-stop* nil)

(defun job-runner-running-p ()
  "True while this process's runner threads run."
  (some #'sb-thread:thread-alive-p *runner-threads*))

(defun runner-loop (database queues interval)
  (let ((littoral.db:*database* database))
    (loop until *runner-stop*
          do (let ((seen (sb-thread:with-mutex (*runner-lock*) *runner-generation*)))
               (handler-case (littoral::with-sane-printing ()
                               (ensure-recurring-jobs queues)
                               (loop until *runner-stop* while (run-next-job queues)))
                 ;; A busy or vanished database: try again next time.
                 (error () nil))
               (when (sb-thread:with-mutex (*runner-lock*)
                       (when (and (= seen *runner-generation*) (not *runner-stop*))
                         (littoral::wait-on *runner-wanted* *runner-lock* interval))
                       (/= seen *runner-generation*))
                 ;; Woken by ENQUEUE-JOB, which may be inside a request's
                 ;; transaction: give it a moment to commit.
                 (sleep 0.2))))))

(defun start-job-runner (&key (database littoral.db:*database*) (threads 1) (queues '("default")) (interval 5))
  "Run the jobs in QUEUES of DATABASE (a spec, as LITTORAL.DB:*DATABASE* holds)
on THREADS background threads: at once when a job is enqueued in this
process, and every INTERVAL seconds for scheduled jobs, retries and other
processes' jobs.  Stops any runner already started."
  (stop-job-runner)
  (unless database (error "START-JOB-RUNNER needs a database."))
  (setf *runner-stop* nil
        *runner-threads* (loop for i from 1 to threads
                               collect (sb-thread:make-thread #'runner-loop :name (format nil "littoral job runner ~D" i)
                                                                            :arguments (list database queues interval))))
  t)

(defun stop-job-runner ()
  "Stop the runner threads, letting each finish the job it is running (waiting
up to 30 seconds for each)."
  (when *runner-threads*
    (setf *runner-stop* t)
    (wake-runner)
    (dolist (thread *runner-threads*)
      (sb-thread:join-thread thread :default nil :timeout 30)))
  (setf *runner-threads* '()))

;;; Looking at the queue

(defun find-durable-job (id)
  "The job ID, or NIL."
  (first (select-jobs "WHERE id = ?" id)))

(defun durable-jobs (&key status queue (limit 50) (offset 0))
  "Jobs, newest first; only those with STATUS and in QUEUE (strings) if
given.  At most LIMIT, skipping the first OFFSET."
  (check-type limit (integer 0))
  (check-type offset (integer 0))
  (apply #'select-jobs
         (format nil "~@[WHERE ~{~A~^ AND ~}~] ORDER BY id DESC LIMIT ~D OFFSET ~D"
                 (remove nil (list (and status "status = ?") (and queue "queue = ?")))
                 limit offset)
         (remove nil (list status queue))))

(defun durable-job-counts ()
  "How many jobs have each status: ((\"queued\" . 3) (\"done\" . 40) …)."
  (mapcar (lambda (row) (cons (getf row :|status|) (getf row :|n|)))
          (littoral.db:db-query "SELECT status, COUNT(*) AS n FROM job_queue GROUP BY status ORDER BY status")))

(defun retry-durable-job (id)
  "Run the failed or cancelled job ID again now, its tries counted afresh;
true unless it wasn't failed or cancelled, or a job with its key waits already."
  (prog1 (= 1 (littoral.db:db-execute "UPDATE job_queue SET status = 'queued', attempts = 0, run_at = ?, finished = NULL,
progress = NULL, progress_fraction = NULL, cancel_requested = 0
WHERE id = ? AND status IN ('failed', 'cancelled')
AND (unique_key IS NULL OR NOT EXISTS (SELECT 1 FROM job_queue q WHERE q.unique_key = job_queue.unique_key
                                       AND q.status = 'queued' AND q.attempts = 0))"
                                      (get-universal-time) id))
    (publish-job-change)
    (wake-runner)))

(defun cancel-durable-job (id)
  "Cancel the job ID.  A queued job is cancelled at once: T.  A running job
is asked to stop, and does at its next NOTE-JOB-PROGRESS (a job that never
calls it runs to the end): :REQUESTED.  NIL when the job has finished."
  (prog1 (cond ((= 1 (littoral.db:db-execute "UPDATE job_queue SET status = 'cancelled', finished = ?
WHERE id = ? AND status = 'queued'"
                                             (get-universal-time) id))
                t)
               ((= 1 (littoral.db:db-execute "UPDATE job_queue SET cancel_requested = 1 WHERE id = ? AND status = 'running'" id))
                :requested))
    (publish-job-change)))

;;; Metrics: /metrics reports each database whose job tables were made here

(defun write-job-metrics (out)
  "Write the durable job queues' metrics to OUT, in Prometheus's format."
  (let ((now (get-universal-time))
        (reports '()))
    (dolist (spec (sb-thread:with-mutex (*job-databases-lock*) (copy-list *job-databases*)))
      (push (cons (littoral.db:database-label spec)
                  (handler-case
                      (let ((littoral.db:*database* spec))
                        (list (littoral.db:db-query "SELECT queue, status, COUNT(*) AS n FROM job_queue
GROUP BY queue, status ORDER BY queue, status")
                              (littoral.db:db-query "SELECT queue, MIN(run_at) AS due FROM job_queue
WHERE status = 'queued' AND run_at <= ? GROUP BY queue" now)))
                    (error () :down)))
            reports))
    (setf reports (nreverse reports))
    (flet ((head (name help)
             (format out "# HELP ~A ~A~%# TYPE ~A gauge~%" name help name)))
      (head "littoral_durable_jobs" "Durable jobs, by database, queue and status.")
      (loop for (database . report) in reports
            unless (eq report :down)
              do (dolist (row (first report))
                   (format out "littoral_durable_jobs{database=\"~A\",queue=\"~A\",status=\"~A\"} ~D~%"
                           (littoral:metric-label database) (littoral:metric-label (getf row :|queue|))
                           (littoral:metric-label (getf row :|status|)) (getf row :|n|))))
      (head "littoral_durable_jobs_oldest_due_seconds"
            "How long the longest-waiting due job has waited, by database and queue: 0 when none is due.")
      (loop for (database . report) in reports
            unless (eq report :down)
              do (dolist (queue (remove-duplicates (mapcar (lambda (row) (getf row :|queue|)) (first report))
                                                   :test #'string=))
                   (let ((due (getf (find queue (second report) :key (lambda (row) (getf row :|queue|))
                                                                :test #'string=)
                                    :|due|)))
                     (format out "littoral_durable_jobs_oldest_due_seconds{database=\"~A\",queue=\"~A\"} ~D~%"
                             (littoral:metric-label database) (littoral:metric-label queue)
                             (if due (max 0 (- now due)) 0)))))
      (head "littoral_durable_jobs_database_up" "Whether each database's job queue could be read.")
      (loop for (database . report) in reports
            do (format out "littoral_durable_jobs_database_up{database=\"~A\"} ~D~%"
                       (littoral:metric-label database) (if (eq report :down) 0 1)))
      (head "littoral_job_runner_threads" "Job runner threads alive in this process.")
      (format out "littoral_job_runner_threads ~D~%" (count-if #'sb-thread:thread-alive-p *runner-threads*)))))

(littoral:add-metrics-source "durable-jobs" 'write-job-metrics)

;; A draining process leaves the queue to the process replacing it.
(littoral:add-drain-hook "durable-jobs" 'stop-job-runner)

(defun purge-durable-jobs (&key (older-than (* 7 24 3600)) (statuses '("done" "cancelled")))
  "Delete jobs with one of STATUSES that finished more than OLDER-THAN
seconds ago; how many."
  (apply #'littoral.db:db-execute
         (format nil "DELETE FROM job_queue WHERE status IN ~A AND finished < ?" (placeholders statuses))
         (append statuses (list (- (get-universal-time) older-than)))))
