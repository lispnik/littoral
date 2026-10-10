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
  (:documentation "Background jobs kept in the database: retried, scheduled, and run by any process.")
  (:export #:define-job #:enqueue-job #:daily-at
           #:create-job-tables #:drop-job-tables
           #:run-due-jobs #:start-job-runner #:stop-job-runner #:job-runner-running-p
           #:*durable-job* #:note-job-progress #:abandon-job #:job-abandoned
           #:durable-job #:durable-job-id #:durable-job-name #:durable-job-arguments #:durable-job-queue
           #:durable-job-status #:durable-job-attempts #:durable-job-run-at #:durable-job-key
           #:durable-job-progress #:durable-job-last-error #:durable-job-created #:durable-job-finished
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

(defun create-job-tables ()
  "Create the job_queue table unless it exists."
  (littoral.db:db-execute
   (format nil "CREATE TABLE IF NOT EXISTS job_queue (id ~A, name TEXT NOT NULL, arguments TEXT NOT NULL,
queue TEXT NOT NULL, status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, run_at BIGINT NOT NULL,
unique_key TEXT, progress TEXT, last_error TEXT, created BIGINT NOT NULL, finished BIGINT)"
           (if (eq (first littoral.db:*database*) :postgres) "BIGSERIAL PRIMARY KEY" "INTEGER PRIMARY KEY AUTOINCREMENT")))
  (littoral.db:db-execute "CREATE INDEX IF NOT EXISTS job_queue_due ON job_queue (status, run_at)")
  ;; One untried job per key: ENQUEUE-JOB's :KEY, and each recurring job.
  (littoral.db:db-execute "CREATE UNIQUE INDEX IF NOT EXISTS job_queue_key ON job_queue (unique_key)
WHERE status = 'queued' AND attempts = 0")
  t)

(defun drop-job-tables ()
  "Drop the job_queue table."
  (littoral.db:db-execute "DROP TABLE IF EXISTS job_queue"))

(defclass durable-job ()
  ((id :initarg :id :reader durable-job-id)
   (name :initarg :name :reader durable-job-name :documentation "The job's name, a symbol (or its text, when unreadable here).")
   (arguments :initarg :arguments :reader durable-job-arguments)
   (queue :initarg :queue :reader durable-job-queue)
   (status :initarg :status :reader durable-job-status
           :documentation "\"queued\", \"running\", \"done\", \"failed\" or \"cancelled\".")
   (attempts :initarg :attempts :reader durable-job-attempts
             :documentation "Tries so far; inside the job, which try this is.")
   (run-at :initarg :run-at :reader durable-job-run-at
           :documentation "When it is due; while running, when another runner may take it over.")
   (key :initarg :key :reader durable-job-key)
   (progress :initarg :progress :reader durable-job-progress :documentation "What NOTE-JOB-PROGRESS said last.")
   (last-error :initarg :last-error :reader durable-job-last-error)
   (created :initarg :created :reader durable-job-created)
   (finished :initarg :finished :reader durable-job-finished))
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
overrides the job's own."
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

(defvar *durable-job* nil "The DURABLE-JOB this thread is running.")

(defun note-job-progress (text)
  "From inside a job: record TEXT as how it's going (DURABLE-JOB-PROGRESS),
and hold on to the job for another TIMEOUT."
  (let ((job *durable-job*))
    (when job
      (littoral.db:db-execute "UPDATE job_queue SET progress = ?, run_at = ? WHERE id = ? AND status = 'running' AND attempts = ?"
                              text (+ (get-universal-time) (definition-timeout (find-definition (durable-job-name job))))
                              (durable-job-id job) (durable-job-attempts job)))))

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
          (first (select-jobs "WHERE id = ?" (durable-job-id job)))))))

(defun mark-done (job)
  (= 1 (littoral.db:db-execute "UPDATE job_queue SET status = 'done', finished = ?, last_error = NULL
WHERE id = ? AND status = 'running' AND attempts = ?"
                               (get-universal-time) (durable-job-id job) (durable-job-attempts job))))

(defun failure-text (condition backtrace)
  (let ((text (format nil "~A~@[~2%~A~]"
                      (handler-case (princ-to-string condition) (error () "an error")) backtrace)))
    (subseq text 0 (min 4000 (length text)))))

(defun mark-failed (job definition condition backtrace)
  (let* ((attempts (durable-job-attempts job))
         (give-up (or (typep condition 'job-abandoned) (>= attempts (definition-attempts definition))))
         (now (get-universal-time)))
    (littoral.db:db-execute "UPDATE job_queue SET status = ?, run_at = ?, finished = ?, last_error = ?
WHERE id = ? AND status = 'running' AND attempts = ?"
                            (if give-up "failed" "queued")
                            (+ now (* (definition-retry-seconds definition) (expt 2 (1- attempts))))
                            (and give-up now) (failure-text condition backtrace)
                            (durable-job-id job) attempts)))

(defun run-claimed (job definition)
  "Run JOB, claimed, and record how it went; true when it succeeded."
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
      (error (e)
        (ignore-errors (mark-failed job definition e (and (eq (car backtrace) e) (cdr backtrace))))
        nil))))

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
  "Stop the runner threads, letting each finish the job it is running."
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

(defun durable-jobs (&key status queue (limit 50))
  "Jobs, newest first; only those with STATUS and in QUEUE (strings) if given."
  (apply #'select-jobs
         (format nil "~@[WHERE ~{~A~^ AND ~}~] ORDER BY id DESC LIMIT ~D"
                 (remove nil (list (and status "status = ?") (and queue "queue = ?")))
                 limit)
         (remove nil (list status queue))))

(defun durable-job-counts ()
  "How many jobs have each status: ((\"queued\" . 3) (\"done\" . 40) …)."
  (mapcar (lambda (row) (cons (getf row :|status|) (getf row :|n|)))
          (littoral.db:db-query "SELECT status, COUNT(*) AS n FROM job_queue GROUP BY status ORDER BY status")))

(defun retry-durable-job (id)
  "Run the failed or cancelled job ID again now, its tries counted afresh;
true unless it wasn't failed or cancelled, or a job with its key waits already."
  (prog1 (= 1 (littoral.db:db-execute "UPDATE job_queue SET status = 'queued', attempts = 0, run_at = ?, finished = NULL
WHERE id = ? AND status IN ('failed', 'cancelled')
AND (unique_key IS NULL OR NOT EXISTS (SELECT 1 FROM job_queue q WHERE q.unique_key = job_queue.unique_key
                                       AND q.status = 'queued' AND q.attempts = 0))"
                                      (get-universal-time) id))
    (wake-runner)))

(defun cancel-durable-job (id)
  "Cancel the job ID unless it has started; true if it was cancelled."
  (= 1 (littoral.db:db-execute "UPDATE job_queue SET status = 'cancelled', finished = ? WHERE id = ? AND status = 'queued'"
                               (get-universal-time) id)))

(defun purge-durable-jobs (&key (older-than (* 7 24 3600)) (statuses '("done" "cancelled")))
  "Delete jobs with one of STATUSES that finished more than OLDER-THAN
seconds ago; how many."
  (apply #'littoral.db:db-execute
         (format nil "DELETE FROM job_queue WHERE status IN ~A AND finished < ?" (placeholders statuses))
         (append statuses (list (- (get-universal-time) older-than)))))
