;;;; durable-jobs.lisp — jobs in the database: retries, schedules, claims and runners

(in-package #:littoral/tests)

(def-suite durable-jobs :in littoral)
(in-suite durable-jobs)

(defvar *job-calls* '() "What the test jobs were called with, newest first.")
(defvar *job-calls-lock* (sb-thread:make-mutex :name "test job calls"))

(defun note-call (&rest call)
  (sb-thread:with-mutex (*job-calls-lock*) (push call *job-calls*)))

(littoral.jobs:define-job record-job (a b)
  (note-call 'record a b))

(littoral.jobs:define-job (failing-job :attempts 3 :retry-seconds 10) (failures)
  (note-call 'failing (littoral.jobs:durable-job-attempts littoral.jobs:*durable-job*))
  (when (<= (littoral.jobs:durable-job-attempts littoral.jobs:*durable-job*) failures)
    (error "Failure number ~D" (littoral.jobs:durable-job-attempts littoral.jobs:*durable-job*))))

(littoral.jobs:define-job hopeless-job (id)
  (littoral.jobs:abandon-job "No record ~D" id))

(littoral.jobs:define-job (writing-job :transaction t) (text fail)
  (littoral.db:db-execute "INSERT INTO job_notes (text) VALUES (?)" text)
  (littoral.jobs:note-job-progress "written")
  (when fail (error "after writing")))

(littoral.jobs:define-job (other-queue-job :queue "other") ()
  (note-call 'other))

(littoral.jobs:define-job (ticking-job :queue "every-test" :every 60) ()
  (note-call 'tick))

(defun test-job-definitions ()
  "The jobs defined here, without those of whatever else is loaded (the
generated app's recurring job would otherwise be scheduled too)."
  (let ((table (make-hash-table :test 'equal)))
    (maphash (lambda (name definition)
               (when (eq (symbol-package (littoral.jobs::definition-name definition)) (find-package '#:littoral/tests))
                 (setf (gethash name table) definition)))
             littoral.jobs::*definitions*)
    table))

(defmacro with-job-queue (() &body body)
  `(let ((littoral.jobs::*definitions* (test-job-definitions)))
     (connect-test-database)
     (ignore-errors (littoral.jobs:drop-job-tables))
     (littoral.jobs:create-job-tables)
     (setf *job-calls* '())
     ,@body))

(defun due-now (id)
  "Make the job ID due, as if its wait were over."
  (littoral.db:db-execute "UPDATE job_queue SET run_at = 0 WHERE id = ?" id))

(defun queued-status (id) (littoral.jobs:durable-job-status (littoral.jobs:find-durable-job id)))

(test jobs-run-with-their-arguments
  (with-job-queue ()
    (let ((id (littoral.jobs:enqueue-job (list 'record-job "Zoë" '(1 2.5d0 :k)))))
      (is (string= "queued" (queued-status id)))
      (is (= 1 (littoral.jobs:run-due-jobs)))
      (is (equal '((record "Zoë" (1 2.5d0 :k))) *job-calls*))
      (let ((job (littoral.jobs:find-durable-job id)))
        (is (string= "done" (littoral.jobs:durable-job-status job)))
        (is (eq 'record-job (littoral.jobs:durable-job-name job)))
        (is (= 1 (littoral.jobs:durable-job-attempts job)))
        (is (integerp (littoral.jobs:durable-job-finished job))))
      (is (= 0 (littoral.jobs:run-due-jobs)) "Run once"))))

(test job-arguments-must-print-readably
  (with-job-queue ()
    (signals error (littoral.jobs:enqueue-job (list 'record-job (make-hash-table) 1)))
    (signals error (littoral.jobs:enqueue-job (list 'record-job (lambda ()) 1)))
    (signals error (littoral.jobs:enqueue-job (list 'no-such-job 1)) "Only defined jobs")
    (signals error (littoral.jobs:enqueue-job (list 'ticking-job)) "Recurring jobs schedule themselves")
    (is (null (littoral.jobs:durable-jobs)))))

(test jobs-retry-then-succeed
  (with-job-queue ()
    (let ((id (littoral.jobs:enqueue-job (list 'failing-job 2))))
      (littoral.jobs:run-due-jobs)
      (let ((job (littoral.jobs:find-durable-job id)))
        (is (string= "queued" (littoral.jobs:durable-job-status job)))
        (is (search "Failure number 1" (littoral.jobs:durable-job-last-error job)))
        (is (search "FAILING-JOB" (littoral.jobs:durable-job-last-error job)) "With a backtrace")
        (is (<= 9 (- (littoral.jobs:durable-job-run-at job) (get-universal-time)) 10) "Waits RETRY-SECONDS"))
      (is (= 0 (littoral.jobs:run-due-jobs)) "Not before its time")
      (due-now id)
      (littoral.jobs:run-due-jobs)
      (let ((job (littoral.jobs:find-durable-job id)))
        (is (<= 19 (- (littoral.jobs:durable-job-run-at job) (get-universal-time)) 20) "Then twice as long"))
      (due-now id)
      (littoral.jobs:run-due-jobs)
      (is (string= "done" (queued-status id)))
      (is (null (littoral.jobs:durable-job-last-error (littoral.jobs:find-durable-job id))))
      (is (equal '(3 2 1) (mapcar #'second *job-calls*))))))

(test jobs-give-up
  (with-job-queue ()
    (let ((id (littoral.jobs:enqueue-job (list 'failing-job 10))))
      (dotimes (i 3) (due-now id) (littoral.jobs:run-due-jobs))
      (is (string= "failed" (queued-status id)))
      (is (= 3 (length *job-calls*)) "ATTEMPTS tries")
      (due-now id)
      (is (= 0 (littoral.jobs:run-due-jobs)))
      ;; Retried by hand, tries counted afresh.
      (is (littoral.jobs:retry-durable-job id))
      (littoral.jobs:run-due-jobs)
      (is (string= "queued" (queued-status id)))
      (is (= 1 (littoral.jobs:durable-job-attempts (littoral.jobs:find-durable-job id)))))
    (let ((id (littoral.jobs:enqueue-job (list 'hopeless-job 7))))
      (littoral.jobs:run-due-jobs)
      (is (string= "failed" (queued-status id)) "ABANDON-JOB fails it at once")
      (is (search "No record 7" (littoral.jobs:durable-job-last-error (littoral.jobs:find-durable-job id)))))))

(test jobs-wait-for-their-time
  (with-job-queue ()
    (let ((later (littoral.jobs:enqueue-job (list 'record-job 1 2) :in 300))
          (at (littoral.jobs:enqueue-job (list 'record-job 3 4) :at (+ (get-universal-time) 60))))
      (is (= 0 (littoral.jobs:run-due-jobs)))
      (due-now later)
      (is (= 1 (littoral.jobs:run-due-jobs)))
      (is (string= "queued" (queued-status at)))
      (is (littoral.jobs:cancel-durable-job at))
      (due-now at)
      (is (= 0 (littoral.jobs:run-due-jobs)))
      (is (string= "cancelled" (queued-status at)))
      (is (not (littoral.jobs:cancel-durable-job later)) "Too late: it ran"))))

(test jobs-with-a-key-are-queued-once
  (with-job-queue ()
    (let ((waiting (littoral.jobs:enqueue-job (list 'record-job 1 1) :key "feed-7")))
      (is (integerp waiting))
      (is (null (littoral.jobs:enqueue-job (list 'record-job 1 1) :key "feed-7")) "Already waiting")
      (is (integerp (littoral.jobs:enqueue-job (list 'record-job 1 1) :key "feed-8")))
      (littoral.jobs:run-due-jobs)
      (is (integerp (littoral.jobs:enqueue-job (list 'record-job 1 1) :key "feed-7")) "Once it has run"))))

(test jobs-run-only-from-their-queues
  (with-job-queue ()
    (let ((id (littoral.jobs:enqueue-job (list 'other-queue-job))))
      (is (= 0 (littoral.jobs:run-due-jobs)))
      (is (= 1 (littoral.jobs:run-due-jobs :queues '("other"))))
      (is (string= "done" (queued-status id))))
    ;; A job this process doesn't define is left for one that does.
    (littoral.db:db-execute "INSERT INTO job_queue (name, arguments, queue, status, attempts, run_at, created)
VALUES ('SOMEONE-ELSES::JOB', 'NIL', 'default', 'queued', 0, 0, 0)")
    (is (= 0 (littoral.jobs:run-due-jobs)))
    (is (string= "queued" (littoral.jobs:durable-job-status (first (littoral.jobs:durable-jobs)))))))

(test jobs-are-claimed-once
  (with-job-queue ()
    (let* ((id (littoral.jobs:enqueue-job (list 'record-job 1 2)))
           (job (littoral.jobs:find-durable-job id))
           (definition (littoral.jobs::find-definition 'record-job)))
      (is (littoral.jobs::claim job definition))
      (is (null (littoral.jobs::claim job definition)) "Another runner loses the race")
      (is (= 0 (littoral.jobs:run-due-jobs)) "Held by the first")
      ;; The first runner's process dies: once its hold expires, another takes over.
      (due-now id)
      (is (= 1 (littoral.jobs:run-due-jobs)))
      (is (string= "done" (queued-status id)))
      (is (= 2 (littoral.jobs:durable-job-attempts (littoral.jobs:find-durable-job id))))))
  (with-job-queue ()
    ;; A job that keeps killing its runner fails once its tries are used.
    (let ((id (littoral.jobs:enqueue-job (list 'failing-job 0))))
      (littoral.db:db-execute "UPDATE job_queue SET status = 'running', attempts = 3, run_at = 0 WHERE id = ?" id)
      (is (= 0 (littoral.jobs:run-due-jobs)))
      (is (string= "failed" (queued-status id)))
      (is (search "runner stopped" (littoral.jobs:durable-job-last-error (littoral.jobs:find-durable-job id)))))))

(test jobs-only-exist-if-their-transaction-commits
  (with-job-queue ()
    (ignore-errors
     (littoral.db:with-transaction ()
       (littoral.jobs:enqueue-job (list 'record-job 1 2))
       (error "the action failed")))
    (is (null (littoral.jobs:durable-jobs)))))

(test transactional-jobs-roll-back
  (with-job-queue ()
    (littoral.db:db-execute "DROP TABLE IF EXISTS job_notes")
    (littoral.db:db-execute "CREATE TABLE job_notes (text TEXT)")
    (unwind-protect
         (let ((good (littoral.jobs:enqueue-job (list 'writing-job "kept" nil)))
               (bad (littoral.jobs:enqueue-job (list 'writing-job "lost" t))))
           (littoral.jobs:run-due-jobs)
           (is (equal '("kept") (mapcar (lambda (row) (getf row :|text|))
                                        (littoral.db:db-query "SELECT text FROM job_notes"))))
           (is (string= "done" (queued-status good)))
           (is (string= "written" (littoral.jobs:durable-job-progress (littoral.jobs:find-durable-job good))))
           (is (string= "queued" (queued-status bad)))
           (is (search "after writing" (littoral.jobs:durable-job-last-error (littoral.jobs:find-durable-job bad)))))
      (littoral.db:db-execute "DROP TABLE IF EXISTS job_notes"))))

(test recurring-jobs-schedule-themselves
  (with-job-queue ()
    (flet ((ticks () (littoral.jobs:durable-jobs :queue "every-test")))
      (is (= 0 (littoral.jobs:run-due-jobs :queues '("every-test"))))
      (is (= 1 (length (ticks))) "The first run is scheduled")
      (let ((first (first (ticks))))
        (is (<= 59 (- (littoral.jobs:durable-job-run-at first) (get-universal-time)) 60))
        (littoral.jobs:run-due-jobs :queues '("every-test"))
        (is (= 1 (length (ticks))) "Only once")
        (littoral.db:db-execute "UPDATE job_queue SET run_at = ? WHERE id = ?"
                                (- (get-universal-time) 10) (littoral.jobs:durable-job-id first))
        (is (= 1 (littoral.jobs:run-due-jobs :queues '("every-test"))))
        (is (equal '((tick)) *job-calls*))
        (let ((next (first (ticks))))
          (is (string= "queued" (littoral.jobs:durable-job-status next)))
          (is (<= 49 (- (littoral.jobs:durable-job-run-at next) (get-universal-time)) 50)
              "Every 60 seconds from when it was due, not from when it ran")
          (is (equal '("done" "queued") (sort (mapcar #'littoral.jobs:durable-job-status (ticks)) #'string<))))))))

(test daily-at-the-hour
  (let* ((noon (encode-universal-time 0 0 12 10 10 2026))
         (three (funcall (littoral.jobs:daily-at 3) noon)))
    (is (= (encode-universal-time 0 0 3 11 10 2026) three) "Tomorrow at three")
    (is (= (encode-universal-time 0 30 15 10 10 2026) (funcall (littoral.jobs:daily-at 15 30) noon)) "Today")))

(test purging-finished-jobs
  (with-job-queue ()
    (let ((done (littoral.jobs:enqueue-job (list 'record-job 1 2)))
          (failed (littoral.jobs:enqueue-job (list 'hopeless-job 1))))
      (littoral.jobs:run-due-jobs)
      (is (= 0 (littoral.jobs:purge-durable-jobs)) "Not old enough")
      (littoral.db:db-execute "UPDATE job_queue SET finished = 0")
      (is (= 1 (littoral.jobs:purge-durable-jobs)))
      (is (null (littoral.jobs:find-durable-job done)))
      (is (littoral.jobs:find-durable-job failed) "Failed jobs are kept for a look")
      (is (equal '(("failed" . 1)) (littoral.jobs:durable-job-counts))))))

(test job-runner-threads
  ;; Runner threads have their own connections, so this uses a file, not :memory:.
  (let* ((file (merge-pathnames (format nil "littoral-jobs-~36R.sqlite3" (random (expt 36 8)))
                                (uiop:temporary-directory)))
         (spec (list :sqlite3 :database-name (namestring file))))
    (setf *job-calls* '())
    (unwind-protect
         (let ((littoral.db:*database* spec))
           (littoral.jobs:create-job-tables)
           (littoral.jobs:start-job-runner :database spec :threads 3 :interval 1)
           (is (littoral.jobs:job-runner-running-p))
           (let ((ids (loop for i below 20 collect (littoral.jobs:enqueue-job (list 'record-job i i)))))
             (loop repeat 100 until (= 20 (length *job-calls*)) do (sleep 0.1))
             (is (= 20 (length *job-calls*)))
             (is (= 20 (length (remove-duplicates *job-calls* :test #'equal))) "Each ran once")
             (is (every (lambda (id) (string= "done" (queued-status id))) ids))))
      (littoral.jobs:stop-job-runner)
      (ignore-errors (delete-file file)))
    (is (not (littoral.jobs:job-runner-running-p)))))
