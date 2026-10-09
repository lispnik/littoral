;;;; jobs.lisp — background jobs, retried on failure, reporting to the page
;;;;
;;;;   (let ((job (submit-job (lambda ()
;;;;                            (dotimes (i 10)
;;;;                              (resize-photo i)
;;;;                              (job-progress (/ (1+ i) 10) "Resizing…")))
;;;;                          :name "Resize photos" :attempts 3)))
;;;;     (watch-job job (make-instance 'job-view :job job)))
;;;;
;;;; Jobs run on a pool of *JOB-WORKERS* threads, in the order submitted.
;;;; One that signals is tried again, up to ATTEMPTS times, after BACKOFF
;;;; seconds, doubling each time.  JOB-PROGRESS records how far it has got
;;;; and re-renders the components watching it on their pages (server push);
;;;; it is also where CANCEL-JOB takes effect.  A JOB-VIEW shows a job with a
;;;; progress bar.  Jobs live in memory: a restart forgets them.

(in-package #:littoral)

(defvar *job-workers* 4 "Threads running jobs at once.")
(defvar *jobs-kept* 200 "Finished jobs remembered for LIST-JOBS.")

(defclass job ()
  ((id :initform (random-key 12) :reader job-id)
   (name :initarg :name :initform "Job" :reader job-name)
   (function :initarg :function :reader job-function)
   (status :initform :queued :accessor job-status
           :documentation ":QUEUED, :RUNNING, :WAITING (to retry), :DONE, :FAILED or :CANCELLED.")
   (progress :initform 0 :accessor job-progress-fraction)
   (message :initform nil :accessor job-message)
   (result :initform nil :accessor job-result)
   (error :initform nil :accessor job-error :documentation "The last failure, as text.")
   (attempts :initarg :attempts :initform 1 :reader job-attempts)
   (attempt :initform 0 :accessor job-attempt)
   (backoff :initarg :backoff :initform 2 :reader job-backoff)
   (retry-at :initform nil :accessor job-retry-at)
   (cancel-p :initform nil :accessor job-cancel-requested-p)
   (watchers :initform '() :accessor job-watchers :documentation "(COMPONENT . SESSION) pairs.")
   (created :initform (get-universal-time) :reader job-created)
   (finished :initform nil :accessor job-finished)
   (lock :initform (sb-thread:make-mutex :name "littoral job") :reader job-lock)
   (done :initform (sb-thread:make-waitqueue) :reader job-done-queue))
  (:documentation "Work done in the background, and how it is going."))

(defmethod print-object ((job job) stream)
  (print-unreadable-object (job stream :type t)
    (format stream "~A ~(~A~)" (job-name job) (job-status job))))

(define-condition job-cancelled (error) ()
  (:report "The job was cancelled.")
  (:documentation "Signalled by JOB-PROGRESS in a job that CANCEL-JOB was called on."))

(defvar *current-job* nil "The job this thread is running.")

;;; The queue and its workers

(defun wait-on (queue mutex timeout)
  "CONDITION-WAIT on QUEUE for at most TIMEOUT seconds, holding MUTEX
afterwards: when it times out, SBCL may return without it."
  (sb-thread:condition-wait queue mutex :timeout timeout)
  (unless (sb-thread:holding-mutex-p mutex)
    (sb-thread:grab-mutex mutex)))

(defvar *job-queue* '() "Jobs ready to run, oldest first.")
(defvar *waiting-jobs* '() "Jobs waiting to retry.")
(defvar *recent-jobs* '() "Every job, newest first, up to *JOBS-KEPT* finished ones.")
(defvar *jobs-lock* (sb-thread:make-mutex :name "littoral jobs"))
(defvar *jobs-ready* (sb-thread:make-waitqueue))
(defvar *job-threads* '())

(defun finished-p (job)
  (member (job-status job) '(:done :failed :cancelled)))

(defun tell-watchers (job)
  "Re-render the components watching JOB."
  (dolist (watcher (sb-thread:with-mutex ((job-lock job)) (copy-list (job-watchers job))))
    (ignore-errors (notify (car watcher) (cdr watcher)))))

(defun next-job ()
  "The next job to run, waiting for one; moves jobs whose retry time has come."
  (sb-thread:with-mutex (*jobs-lock*)
    (loop
      (let ((now (get-universal-time)))
        (dolist (job *waiting-jobs*)
          (when (<= (job-retry-at job) now)
            (setf *waiting-jobs* (remove job *waiting-jobs*)
                  *job-queue* (append *job-queue* (list job))))))
      (when *job-queue*
        (return (pop *job-queue*)))
      (wait-on *jobs-ready* *jobs-lock* (if *waiting-jobs* 0.25 5)))))

(defun finish-job (job status)
  (sb-thread:with-mutex ((job-lock job))
    (setf (job-status job) status
          (job-finished job) (get-universal-time))
    (sb-thread:condition-broadcast (job-done-queue job)))
  (tell-watchers job))

(defun run-job (job)
  "Run JOB once; on failure, schedule another attempt or give up."
  (when (job-cancel-requested-p job)
    (return-from run-job (finish-job job :cancelled)))
  (setf (job-status job) :running)
  (incf (job-attempt job))
  (tell-watchers job)
  (handler-case
      (let ((*current-job* job))
        (with-sane-printing ()
          (let ((result (funcall (job-function job))))
            (setf (job-result job) result
                  (job-progress-fraction job) 1)
            (finish-job job :done))))
    (job-cancelled ()
      (finish-job job :cancelled))
    (error (e)
      (setf (job-error job) (handler-case (princ-to-string e) (error () "an error")))
      (if (< (job-attempt job) (job-attempts job))
          ;; Whole seconds: a fraction would make the time a float, too
          ;; coarse at this size.
          (let ((delay (max 1 (ceiling (* (job-backoff job) (expt 2 (1- (job-attempt job))))))))
            (setf (job-status job) :waiting
                  (job-retry-at job) (+ (get-universal-time) delay))
            (sb-thread:with-mutex (*jobs-lock*)
              (push job *waiting-jobs*)
              (sb-thread:condition-notify *jobs-ready*))
            (tell-watchers job))
          (finish-job job :failed)))))

(defun job-worker ()
  (loop (let ((job (next-job)))
          (ignore-errors (run-job job)))))

(defun ensure-job-workers ()
  (sb-thread:with-mutex (*jobs-lock*)
    (setf *job-threads* (remove-if-not #'sb-thread:thread-alive-p *job-threads*))
    (loop while (< (length *job-threads*) *job-workers*)
          do (push (sb-thread:make-thread #'job-worker :name "littoral job worker") *job-threads*))))

;;; The interface

(defun submit-job (function &key (name "Job") (attempts 1) (backoff 2))
  "Run FUNCTION, of no arguments, in the background; the JOB.  It is tried
up to ATTEMPTS times, waiting BACKOFF seconds before the second and twice
as long before each after.  Its value becomes the JOB-RESULT."
  (let ((job (make-instance 'job :function function :name name :attempts attempts :backoff backoff)))
    (sb-thread:with-mutex (*jobs-lock*)
      (setf *job-queue* (append *job-queue* (list job)))
      (push job *recent-jobs*)
      (let ((finished (remove-if-not #'finished-p *recent-jobs*)))
        (when (> (length finished) *jobs-kept*)
          (setf *recent-jobs* (set-difference *recent-jobs* (nthcdr *jobs-kept* finished)))))
      (sb-thread:condition-notify *jobs-ready*))
    (ensure-job-workers)
    job))

(defun job-progress (fraction &optional message (job *current-job*))
  "From inside a job: it is FRACTION (0 to 1) done, with MESSAGE to show.
Re-renders the components watching it.  Signals JOB-CANCELLED once the job
has been cancelled, ending it."
  (when job
    (when (job-cancel-requested-p job)
      (error 'job-cancelled))
    (setf (job-progress-fraction job) (max 0 (min 1 fraction)))
    (when message (setf (job-message job) message))
    (tell-watchers job)))

(defun cancel-job (job)
  "Stop JOB: at once if it hasn't started or is waiting to retry, otherwise
at its next JOB-PROGRESS."
  (setf (job-cancel-requested-p job) t)
  (let ((pending (sb-thread:with-mutex (*jobs-lock*)
                   (when (or (member job *job-queue*) (member job *waiting-jobs*))
                     (setf *job-queue* (remove job *job-queue*)
                           *waiting-jobs* (remove job *waiting-jobs*))
                     t))))
    (when pending (finish-job job :cancelled)))
  job)

(defun watch-job (job component &optional (session *session*))
  "Re-render COMPONENT on SESSION's pages whenever JOB changes.  The page
must listen for pushes: a JOB-VIEW does; another component can subscribe
to *JOBS-CHANNEL*."
  (sb-thread:with-mutex ((job-lock job))
    (pushnew (cons component session) (job-watchers job) :test #'equal))
  component)

(defun wait-for-job (job &optional (timeout 60))
  "Wait until JOB has finished, at most TIMEOUT seconds; its status."
  (sb-thread:with-mutex ((job-lock job))
    (loop with deadline = (+ (get-internal-real-time) (* timeout internal-time-units-per-second))
          until (or (finished-p job) (> (get-internal-real-time) deadline))
          do (wait-on (job-done-queue job) (job-lock job) 0.5)))
  (job-status job))

(defun list-jobs ()
  "Recent jobs, newest first."
  (sb-thread:with-mutex (*jobs-lock*) (copy-list *recent-jobs*)))

;;; Showing a job

(defvar *jobs-channel* (make-channel "jobs")
  "Subscribed to by JOB-VIEW so that its page listens for pushes; never published.")

(defclass job-view (component updatable)
  ((job :initarg :job :initform nil :accessor job-view-job))
  (:documentation "A job's progress bar, status and Cancel button, kept up to
date by server push once WATCH-JOB has been called on it."))

(defmethod subscriptions ((self job-view)) (list *jobs-channel*))

(defun job-status-text (job)
  (let ((percent (round (* 100 (job-progress-fraction job)))))
    (ecase (job-status job)
      (:queued (translate "Waiting to start."))
      (:running (if (job-message job)
                    (format nil "~A ~D%" (translate-label (job-message job)) percent)
                    (translate "Working… ~D%" percent)))
      (:waiting (translate "Failed (~A); trying again in ~D s, attempt ~D of ~D."
                           (job-error job) (max 0 (- (job-retry-at job) (get-universal-time)))
                           (1+ (job-attempt job)) (job-attempts job)))
      (:done (translate "Done."))
      (:failed (translate "Failed: ~A" (job-error job)))
      (:cancelled (translate "Cancelled.")))))

(defmethod render ((self job-view))
  (let ((job (job-view-job self)))
    (when job
      (div (:class (list "lt-job" (format nil "lt-job-~(~A~)" (job-status job))))
        (div (:class "lt-job-track" :role "progressbar" :aria-valuemin "0" :aria-valuemax "100"
              :aria-valuenow (princ-to-string (round (* 100 (job-progress-fraction job))))
              :aria-label (job-name job))
          (div (:class "lt-job-fill" :style (format nil "width: ~D%" (round (* 100 (job-progress-fraction job)))))))
        (p (:class "lt-job-status") (text (job-status-text job)))
        (unless (finished-p job)
          (button (:on-click (ajax :callback (lambda () (cancel-job job)) :update self))
            (translate "Cancel")))))))
