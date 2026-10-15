;;;; Durable jobs: defining, queueing, running and looking after jobs kept in the database.

;;;; Example: littoral.jobs:define-job littoral.jobs:enqueue-job littoral.jobs:run-due-jobs littoral.jobs:create-job-tables littoral.jobs:drop-job-tables
;;; A job is a name and readable arguments, kept in the job_queue table until a runner runs it; RUN-DUE-JOBS runs what is due here and now.  Its own queue keeps these jobs apart from other code's.
(defvar *greeted* '())
(littoral.jobs:define-job (greet :queue "examples") (name)
  (push name *greeted*))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (progn
         (littoral.jobs:enqueue-job (list 'greet "Ada"))
         (littoral.jobs:enqueue-job (list 'greet "Bob"))
         (list (littoral.jobs:run-due-jobs :queues '("examples"))
               *greeted*
               (littoral.jobs:run-due-jobs :queues '("examples"))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (2 ("Bob" "Ada") 0)

;;;; Example: littoral.jobs:define-job
;;; DEFINE-JOB also defines a function, which runs the job's body at once.
(littoral.jobs:define-job (add-up :queue "examples") (a b)
  (+ a b))
(add-up 2 3)
;; ⇒ 5

;;;; Example: littoral.jobs:find-durable-job littoral.jobs:durable-job littoral.jobs:durable-job-id littoral.jobs:durable-job-name littoral.jobs:durable-job-arguments littoral.jobs:durable-job-queue littoral.jobs:durable-job-status littoral.jobs:durable-job-attempts littoral.jobs:durable-job-created littoral.jobs:durable-job-finished
;;; A job as it was when read: before it runs, and after.
(littoral.jobs:define-job (send-receipt :queue "examples") (order-id)
  order-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((id (littoral.jobs:enqueue-job (list 'send-receipt 42)))
              (job (littoral.jobs:find-durable-job id)))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((done (littoral.jobs:find-durable-job id)))
           (list (= id (littoral.jobs:durable-job-id job))
                 (littoral.jobs:durable-job-name job)
                 (littoral.jobs:durable-job-arguments job)
                 (littoral.jobs:durable-job-queue job)
                 (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (integerp (littoral.jobs:durable-job-created job))
                 (littoral.jobs:durable-job-finished job)
                 (littoral.jobs:durable-job-status done)
                 (littoral.jobs:durable-job-attempts done)
                 (integerp (littoral.jobs:durable-job-finished done)))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T SEND-RECEIPT (42) "examples" "queued" 0 T NIL "done" 1 T)

;;;; Example: littoral.jobs:enqueue-job littoral.jobs:durable-job-key littoral.jobs:durable-job-run-at
;;; IN delays a job; with KEY, a second job with that key isn't queued while the first waits.
(littoral.jobs:define-job (remind :queue "examples") (user-id)
  user-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let* ((first-id (littoral.jobs:enqueue-job (list 'remind 7) :in 3600 :key "remind:7"))
              (second-id (littoral.jobs:enqueue-job (list 'remind 7) :in 3600 :key "remind:7"))
              (job (littoral.jobs:find-durable-job first-id)))
         (list (integerp first-id)
               second-id
               (littoral.jobs:durable-job-key job)
               (<= 3599 (- (littoral.jobs:durable-job-run-at job) (get-universal-time)) 3600)
               (littoral.jobs:run-due-jobs :queues '("examples"))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T NIL "remind:7" T 0)

;;;; Example: littoral.jobs:enqueue-job
;;; Only defined jobs are queued, and only with arguments that print readably: pass ids, not objects.
(littoral.jobs:define-job (resize-image :queue "examples") (image-id)
  image-id)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (flet ((refused-p (call)
                (handler-case (progn (littoral.jobs:enqueue-job call) nil)
                  (error () t))))
         (list (refused-p (list 'resize-image 12))
               (refused-p (list 'resize-image (make-hash-table)))
               (refused-p (list 'no-such-job 12))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (NIL T T)

;;;; Example: littoral.jobs:durable-job-last-error littoral.jobs:durable-job-run-at
;;; A job that signals is tried again after RETRY-SECONDS, twice as long after each failure since, and marked failed after ATTEMPTS tries.  The error is kept, with a backtrace after its first line.
(littoral.jobs:define-job (call-service :queue "examples" :attempts 3 :retry-seconds 60) ()
  (error "The service is unavailable."))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'call-service))))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (let ((job (littoral.jobs:find-durable-job id)))
           (list (littoral.jobs:durable-job-status job)
                 (littoral.jobs:durable-job-attempts job)
                 (first (uiop:split-string (littoral.jobs:durable-job-last-error job) :separator '(#\Newline)))
                 (<= 59 (- (littoral.jobs:durable-job-run-at job) (get-universal-time)) 60)
                 (littoral.jobs:run-due-jobs :queues '("examples")))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "The service is unavailable." T 0)

;;;; Example: littoral.jobs:abandon-job littoral.jobs:job-abandoned littoral.jobs:retry-durable-job littoral.jobs:cancel-durable-job
;;; ABANDON-JOB fails a job without trying again.  A failed job can be retried by hand, and a queued one cancelled before it starts.
(littoral.jobs:define-job (charge-order :queue "examples") (order-id)
  (littoral.jobs:abandon-job "Order ~D was cancelled." order-id))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'charge-order 7))))
         (flet ((status () (littoral.jobs:durable-job-status (littoral.jobs:find-durable-job id))))
           (littoral.jobs:run-due-jobs :queues '("examples"))
           (list (status)
                 (first (uiop:split-string (littoral.jobs:durable-job-last-error (littoral.jobs:find-durable-job id))
                                           :separator '(#\Newline)))
                 (littoral.jobs:retry-durable-job id)
                 (status)
                 (littoral.jobs:cancel-durable-job id)
                 (status)
                 (littoral.jobs:cancel-durable-job id))))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("failed" "Order 7 was cancelled." T "queued" T "cancelled" NIL)

;;;; Example: littoral.jobs:job-abandoned
;;; The condition ABANDON-JOB signals; its report is the reason.
(handler-case (littoral.jobs:abandon-job "No order ~D." 7)
  (littoral.jobs:job-abandoned (condition)
    (princ-to-string condition)))
;; ⇒ "No order 7."

;;;; Example: littoral.jobs:*durable-job* littoral.jobs:note-job-progress littoral.jobs:durable-job-progress
;;; Inside a job, *DURABLE-JOB* is the job being run, and NOTE-JOB-PROGRESS records how it is going.
(defvar *tries* '())
(littoral.jobs:define-job (import-rows :queue "examples") (count)
  (push (littoral.jobs:durable-job-attempts littoral.jobs:*durable-job*) *tries*)
  (dotimes (i count)
    (littoral.jobs:note-job-progress (format nil "~D of ~D rows" (1+ i) count))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (let ((id (littoral.jobs:enqueue-job (list 'import-rows 3))))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (list *tries*
               (littoral.jobs:durable-job-progress (littoral.jobs:find-durable-job id))
               littoral.jobs:*durable-job*))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ((1) "3 of 3 rows" NIL)

;;;; Example: littoral.jobs:define-job
;;; With :TRANSACTION, a job's database work and its being marked done commit together: a job that fails leaves nothing behind.
(littoral.jobs:define-job (record-payment :queue "examples" :transaction t :attempts 1) (amount)
  (littoral.db:db-execute "INSERT INTO payments (amount) VALUES (?)" amount)
  (when (minusp amount)
    (error "A payment can't be negative.")))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (littoral.db:db-execute "CREATE TABLE payments (amount INTEGER)")
  (unwind-protect
       (progn
         (littoral.jobs:enqueue-job (list 'record-payment 10))
         (littoral.jobs:enqueue-job (list 'record-payment -5))
         (littoral.jobs:run-due-jobs :queues '("examples"))
         (list (mapcar (lambda (row) (getf row :|amount|))
                       (littoral.db:db-query "SELECT amount FROM payments"))
               (littoral.jobs:durable-job-counts)))
    (littoral.db:db-execute "DROP TABLE payments")
    (littoral.jobs:drop-job-tables)))
;; ⇒ ((10) (("done" . 1) ("failed" . 1)))

;;;; Example: littoral.jobs:daily-at
;;; A function from a time to the next HOUR:MINUTE after it, local time.
(let ((next (funcall (littoral.jobs:daily-at 3 30) (encode-universal-time 0 0 12 1 6 2026))))
  (subseq (multiple-value-list (decode-universal-time next)) 0 6))
;; ⇒ (0 30 3 2 6 2026)

;;;; Example: littoral.jobs:define-job littoral.jobs:daily-at
;;; A job defined with :EVERY schedules itself: RUN-DUE-JOBS queues its next run, and it can't be enqueued by hand.
(littoral.jobs:define-job (nightly-report :queue "examples-nightly" :every (littoral.jobs:daily-at 3)) ()
  t)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (list (littoral.jobs:run-due-jobs :queues '("examples-nightly"))
             (let ((job (first (littoral.jobs:durable-jobs :queue "examples-nightly"))))
               (list (littoral.jobs:durable-job-status job)
                     (nth 2 (multiple-value-list (decode-universal-time (littoral.jobs:durable-job-run-at job))))))
             (handler-case (littoral.jobs:enqueue-job (list 'nightly-report))
               (error () :refused)))
    (littoral.jobs:drop-job-tables)))
;; ⇒ (0 ("queued" 3) :REFUSED)

;;;; Example: littoral.jobs:durable-jobs littoral.jobs:durable-job-counts littoral.jobs:purge-durable-jobs
;;; Listing jobs, newest first, counting them by status, and deleting finished ones once they are a week old.
(littoral.jobs:define-job (welcome :queue "examples") (name)
  name)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (unwind-protect
       (progn
         (dolist (name '("Ada" "Bob" "Cy"))
           (littoral.jobs:enqueue-job (list 'welcome name)))
         (littoral.jobs:run-due-jobs :queues '("examples") :limit 2)
         (list (mapcar #'littoral.jobs:durable-job-arguments (littoral.jobs:durable-jobs))
               (mapcar #'littoral.jobs:durable-job-arguments (littoral.jobs:durable-jobs :status "done" :limit 1))
               (littoral.jobs:durable-job-counts)
               (littoral.jobs:purge-durable-jobs)
               (progn
                 ;; As if they had finished a month ago.
                 (littoral.db:db-execute "UPDATE job_queue SET finished = finished - 2592000 WHERE status = 'done'")
                 (littoral.jobs:purge-durable-jobs))
               (littoral.jobs:durable-job-counts)))
    (littoral.jobs:drop-job-tables)))
;; ⇒ ((("Cy") ("Bob") ("Ada")) (("Bob")) (("done" . 2) ("queued" . 1)) 0 2 (("queued" . 1)))

;;;; Example: littoral.jobs:job-tables-p
;;; True once CREATE-JOB-TABLES has run for the current database in this process; the admin then shows its job queue.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (list (littoral.jobs:job-tables-p)
        (progn (littoral.jobs:drop-job-tables)
               (littoral.jobs:job-tables-p))))
;; ⇒ (T NIL)

;;;; Example: littoral.jobs:start-job-runner littoral.jobs:stop-job-runner littoral.jobs:job-runner-running-p
;;; Runner threads run jobs as they are queued.  Each thread has its own connection, so the database is a file here rather than ":memory:".
(defvar *done* nil)
(littoral.jobs:define-job (make-thumbnail :queue "examples") (image-id)
  (setf *done* image-id))
(let* ((file (merge-pathnames (format nil "jobs-~36R.sqlite3" (random (expt 36 8))) (uiop:temporary-directory)))
       (littoral.db:*database* (list :sqlite3 :database-name (namestring file))))
  (unwind-protect
       (progn
         (littoral.jobs:create-job-tables)
         (littoral.jobs:start-job-runner :queues '("examples") :threads 2)
         (littoral.jobs:enqueue-job (list 'make-thumbnail 12))
         (loop repeat 50 until *done* do (sleep 0.1))
         (list (littoral.jobs:job-runner-running-p)
               *done*
               (progn (littoral.jobs:stop-job-runner)
                      (littoral.jobs:job-runner-running-p))))
    (littoral.jobs:stop-job-runner)
    (littoral.jobs:drop-job-tables)
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string (namestring file) suffix)))))
;; ⇒ (T 12 NIL)
