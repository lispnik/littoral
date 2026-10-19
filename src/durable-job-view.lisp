;;;; durable-job-view.lisp — a durable job's progress bar, status and Cancel button
;;;;
;;;; Like core's JOB-VIEW, for jobs in the job_queue table.  The view reads
;;;; the job each time it renders, and re-renders by server push whenever a
;;;; job changes in this process (*DURABLE-JOBS-CHANNEL*); for jobs run by
;;;; another process, :POLL has it look again every few seconds.

(in-package #:littoral.jobs)

(defclass durable-job-view (littoral:component littoral:updatable)
  ((id :initarg :id :initform nil :accessor durable-job-view-id
       :documentation "The id of the job shown, as ENQUEUE-JOB returned it, or NIL for none.")
   (poll :initarg :poll :initform nil :reader view-poll
         :documentation "Seconds between looks at the job while it is unfinished, or NIL.")
   (database :initarg :database :initform nil :reader view-database
             :documentation "The database spec the job is in, or NIL for the current one."))
  (:documentation "A durable job's progress bar, status and Cancel button.
:ID is the job's id (setf DURABLE-JOB-VIEW-ID to show another).  The bar
shows NOTE-JOB-PROGRESS's :FRACTION, and the status its text.  Cancel stops
a queued job at once and asks a running one to stop (see
CANCEL-DURABLE-JOB).  The page hears by server push of changes made in this
process; when the job runs elsewhere, give :POLL, the seconds between looks.
:DATABASE is the job's database spec, when it isn't the current one."))

(defmethod littoral:subscriptions ((self durable-job-view))
  (list *durable-jobs-channel*))

(defmacro in-view-database ((view) &body body)
  `(let ((littoral.db:*database* (or (view-database ,view) littoral.db:*database*)))
     ,@body))

(defun finished-status-p (status)
  (member status '("done" "failed" "cancelled") :test #'string=))

(defun error-line (text)
  (subseq text 0 (or (position #\Newline text) (length text))))

(defun durable-job-status-text (job)
  "What JOB is doing, for people."
  (let ((status (durable-job-status job))
        (fraction (durable-job-progress-fraction job))
        (progress (durable-job-progress job)))
    (cond ((string= status "queued")
           (if (plusp (durable-job-attempts job))
               (littoral:translate "Trying again soon.")
               (littoral:translate "Waiting to start.")))
          ((string= status "running")
           (cond ((durable-job-cancel-requested-p job) (littoral:translate "Stopping…"))
                 ((and progress fraction) (format nil "~A ~D%" progress (round (* 100 fraction))))
                 (progress progress)
                 (fraction (littoral:translate "Working… ~D%" (round (* 100 fraction))))
                 (t (littoral:translate "Working…"))))
          ((string= status "done") (littoral:translate "Done."))
          ((string= status "failed")
           (littoral:translate "Failed: ~A" (error-line (or (durable-job-last-error job) ""))))
          (t (littoral:translate "Cancelled.")))))

(defmethod littoral:render ((self durable-job-view))
  (let* ((id (durable-job-view-id self))
         (job (and id (in-view-database (self) (find-durable-job id)))))
    (when job
      (let* ((status (durable-job-status job))
             (finished (finished-status-p status))
             (fraction (or (durable-job-progress-fraction job) (and (string= status "done") 1)))
             (percent (and fraction (round (* 100 fraction)))))
        (littoral.html:div (:class (list "lt-job" (format nil "lt-job-~A" status))
                            :periodical (and (not finished) (view-poll self)
                                             (littoral:periodical (view-poll self) :update self)))
          (when percent
            (littoral.html:div (:class "lt-job-track" :role "progressbar" :aria-valuemin "0" :aria-valuemax "100"
                                :aria-valuenow (princ-to-string percent)
                                :aria-label (string-downcase (princ-to-string (durable-job-name job))))
              (littoral.html:div (:class "lt-job-fill" :style (format nil "width: ~D%" percent)))))
          (littoral.html:p (:class "lt-job-status") (littoral.html:text (durable-job-status-text job)))
          (unless (or finished (durable-job-cancel-requested-p job))
            (littoral.html:button (:on-click (littoral:ajax :callback (lambda ()
                                                                        (in-view-database (self)
                                                                          (cancel-durable-job id)))
                                                            :update self))
              (littoral:translate "Cancel"))))))))
