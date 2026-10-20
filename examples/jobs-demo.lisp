;;;; jobs-demo.lisp — durable jobs at work: retries, schedules, progress
;;;;
;;;; Served at /examples/jobs by the members demo, which shares its database.
;;;; The jobs live in the job_queue table, so they survive a restart; a
;;;; runner thread takes them from the "demo" queue.

(defpackage #:littoral-jobs-demo
  (:use #:cl #:littoral)
  (:local-nicknames (#:h #:littoral.html))
  (:documentation "Background jobs kept in the database: retries, schedules and progress.")
  (:export #:start-demo-jobs #:run-now #:jobs-root))

(in-package #:littoral-jobs-demo)

;;; The jobs

(littoral.jobs:define-job (build-report :queue "demo" :timeout 60) (seconds)
  "Work for SECONDS seconds, saying how far it has got.  Cancel stops it
between steps."
  (dotimes (i seconds)
    (littoral.jobs:note-job-progress (format nil "Step ~D of ~D" (1+ i) seconds) :fraction (/ i seconds))
    (sleep 1))
  (littoral.jobs:note-job-progress "Finished" :fraction 1))

(littoral.jobs:define-job (flaky-job :queue "demo" :attempts 4 :retry-seconds 3) (failures)
  "Fail the first FAILURES tries, then succeed."
  (let ((try (littoral.jobs:durable-job-attempts littoral.jobs:*durable-job*)))
    (when (<= try failures)
      (error "The service it calls was down (try ~D)" try))
    (littoral.jobs:note-job-progress (format nil "Worked on try ~D" try))))

(littoral.jobs:define-job (doomed-job :queue "demo" :attempts 3 :retry-seconds 2) ()
  "Always fail, until it is marked failed."
  (error "This job always fails"))

(littoral.jobs:define-job (send-digest :queue "demo" :transaction t) (address)
  "Queue the welcome mail to ADDRESS: in the job's transaction, so the mail
goes only if the job finishes."
  (littoral.mail:queue-mail (littoral-mail-demo:welcome-mail address)))

(littoral.jobs:define-job (tidy-up :queue "demo" :every 30) ()
  "Every 30 seconds, delete jobs that finished more than ten minutes ago."
  (littoral.jobs:note-job-progress
   (format nil "Deleted ~D old jobs" (littoral.jobs:purge-durable-jobs :older-than 600))))

(defvar *demo-database* nil "The database spec the jobs live in.")

(defun start-demo-jobs (database)
  "Create the job table in DATABASE (a spec) and run the demo queue there."
  (setf *demo-database* database)
  (let ((littoral.db:*database* database))
    (littoral.jobs:create-job-tables))
  (littoral.jobs:start-job-runner :database database :queues '("demo") :threads 2 :interval 1))

(defun run-now ()
  "Run the demo jobs that are due at once, without the runner (for tests)."
  (let ((littoral.db:*database* *demo-database*))
    (littoral.jobs:run-due-jobs :queues '("demo"))))

(defmacro in-demo-database (&body body)
  `(let ((littoral.db:*database* *demo-database*)) ,@body))

;;; The page

(defclass jobs-root (component)
  ((address :initform "you@example.org" :accessor digest-address)
   (notice :initform nil :accessor jobs-notice)
   (live :initform (make-instance 'jobs-status) :reader jobs-live)
   (report :initform (make-instance 'littoral.jobs:durable-job-view :database *demo-database*)
           :reader jobs-report :documentation "The last report asked for, with its progress."))
  (:documentation "Buttons that enqueue jobs, the last report's progress, and the queue."))

(defmethod children ((self jobs-root)) (list (jobs-report self) (jobs-live self)))

(defclass jobs-status (component updatable) ()
  (:documentation "The queue, refreshed every second."))

(defun enqueue (self call notice &rest options)
  "Enqueue CALL and say NOTICE; the job's id, or NIL when it couldn't be queued."
  (handler-case
      (prog1 (in-demo-database
               (littoral.db:with-transaction ()
                 (apply #'littoral.jobs:enqueue-job call options)))
        (setf (jobs-notice self) notice))
    (error (e) (setf (jobs-notice self) (princ-to-string e)) nil)))

(defmethod render ((self jobs-root))
  (h:h1 () "Jobs")
  (h:p () "Jobs are kept in the database until they're done, so they survive a restart and any "
    "process sharing the database can run them. A job that fails is tried again later, waiting "
    "longer each time; one that keeps failing is marked failed, with its error, for a person to look at.")
  (when (jobs-notice self) (h:p (:class "lt-notice" :role "status") (h:text (jobs-notice self))))
  (h:section ()
    (h:h2 () "Start something")
    (h:form ()
      (h:div (:class "lt-buttons")
        (h:submit-button (:callback (lambda ()
                                    (let ((id (enqueue self (list 'build-report 8) "Queued a report.")))
                                      (when id (setf (littoral.jobs:durable-job-view-id (jobs-report self)) id)))))
          "Build a report (8 s)")
        (h:submit-button (:callback (lambda () (enqueue self (list 'flaky-job 2) "Queued a flaky job.")))
          "A job that fails twice")
        (h:submit-button (:callback (lambda () (enqueue self (list 'doomed-job) "Queued a doomed job.")))
          "A job that always fails")))
    (h:form ()
      (h:div (:class "lt-field")
        (h:label (:for "digest-address") "Mail a welcome to")
        (h:text-input (:id "digest-address" :value (digest-address self)
                     :callback (lambda (v) (setf (digest-address self) v)))))
      (h:div (:class "lt-buttons")
        (h:submit-button (:callback (lambda ()
                                    (enqueue self (list 'send-digest (digest-address self))
                                             "It will be queued for the mail demo in 10 seconds."
                                             :in 10)))
          "Send it in 10 seconds")))
    (h:p (:class "lt-help") "The welcome mail arrives at " (h:anchor (:href (url-for "/examples/mail")) "the mail demo") "."))
  (when (littoral.jobs:durable-job-view-id (jobs-report self))
    (h:section ()
      (h:h2 () "The report")
      (h:p () "A " (h:code () "durable-job-view") ": the runner's progress notes arrive by server push, "
        "and Cancel stops the job between steps.")
      (render-component (jobs-report self))))
  (render (jobs-live self)))

(defun when-text (job)
  (let ((status (littoral.jobs:durable-job-status job))
        (now (get-universal-time)))
    (cond ((string= status "queued")
           (let ((wait (- (littoral.jobs:durable-job-run-at job) now)))
             (if (plusp wait) (format nil "in ~Ds" wait) "now")))
          ((littoral.jobs:durable-job-finished job)
           (format nil "~Ds ago" (- now (littoral.jobs:durable-job-finished job))))
          (t ""))))

(defun first-line (text)
  (and text (subseq text 0 (or (position #\Newline text) (length text)))))

(defmethod render ((self jobs-status))
  (h:div (:periodical (periodical 1 :update self))
    (h:section ()
      (h:h2 () "The queue")
      (let ((jobs (in-demo-database (littoral.jobs:durable-jobs :queue "demo" :limit 15))))
        (if (null jobs)
            (h:p () "Empty.")
            (h:table (:class "lt-table demo-jobs")
              (h:caption (:class "lt-visually-hidden") "Jobs, newest first")
              (h:tr () (h:th () "Job") (h:th () "Status") (h:th () "Tries") (h:th () "When") (h:th () "Progress or error") (h:th () ""))
              (dolist (job jobs)
                (let ((id (littoral.jobs:durable-job-id job))
                      (status (littoral.jobs:durable-job-status job))
                      (name (string-downcase (princ-to-string (littoral.jobs:durable-job-name job)))))
                  (h:tr ()
                    (h:td () (h:code () (h:text (format nil "~A~{ ~S~}" name (littoral.jobs:durable-job-arguments job)))))
                    (h:td () (h:span (:class (list "demo-job-status" (format nil "demo-job-~A" status))) (h:text status)))
                    (h:td () (h:text (littoral.jobs:durable-job-attempts job)))
                    (h:td () (h:text (when-text job)))
                    (h:td () (h:text (or (first-line (littoral.jobs:durable-job-last-error job))
                                     (littoral.jobs:durable-job-progress job) "")))
                    (h:td () (cond ((member status '("failed" "cancelled") :test #'string=)
                                  (h:anchor (:callback (lambda () (in-demo-database (littoral.jobs:retry-durable-job id)))
                                           :aria-label (format nil "Retry ~A" name))
                                    "Retry"))
                                 ((and (string= status "queued") (not (eq (littoral.jobs:durable-job-name job) 'tidy-up)))
                                  (h:anchor (:callback (lambda () (in-demo-database (littoral.jobs:cancel-durable-job id)))
                                           :aria-label (format nil "Cancel ~A" name))
                                    "Cancel"))))))))))
      (h:p (:class "lt-help") "The queue is shared by everyone trying the demo. "
        (h:code () "tidy-up") " runs every 30 seconds and deletes jobs that finished over ten minutes ago."))))

(defmethod style ((self jobs-root))
  ".demo-job-status { padding: .05rem .45rem; border-radius: 99px; font-size: .85rem; background: var(--lt-panel); }
.demo-job-done { background: #d9f2df; color: #14532d; }
.demo-job-failed { background: #fde2e1; color: #7f1d1d; }
.demo-job-queued, .demo-job-running { background: #fff1c2; color: #5c4400; }
.demo-jobs td { vertical-align: top; }")
