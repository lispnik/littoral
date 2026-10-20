;;;; The examples for background jobs, which run in memory on a pool of threads.

;;;; Example: littoral:submit-job littoral:wait-for-job littoral:job-result littoral:job-name littoral:job-status
;;; The function runs on a worker thread; its value becomes the job's result.
(let ((job (submit-job (lambda () (reduce #'+ '(1 2 3 4))) :name "Add up")))
  (list (wait-for-job job 5) (job-name job) (job-result job) (job-status job)))
;; ⇒ (:DONE "Add up" 10 :DONE)

;;;; Example: littoral:job-progress littoral:job-message littoral:job-progress-fraction littoral:*current-job*
;;; Inside the job, JOB-PROGRESS reports how far it has got (and redraws the pages watching it); *CURRENT-JOB* is the job itself.  A job that finishes is wholly done.
(let ((job (submit-job (lambda ()
                         (job-progress 1/2 "Halfway")
                         (list (job-name *current-job*) (job-progress-fraction *current-job*)))
                       :name "Import")))
  (wait-for-job job 5)
  (list (job-result job) (job-message job) (job-progress-fraction job)))
;; ⇒ (("Import" 1/2) "Halfway" 1)

;;;; Example: littoral:job-error littoral:job-attempt littoral:job-attempts
;;; A job that signals is tried again, up to :ATTEMPTS times; with one attempt it fails at once.  JOB-ERROR is the failure as text.
(let ((job (submit-job (lambda () (error "The disk is full.")))))
  (list (wait-for-job job 5) (job-error job) (job-attempt job) (job-attempts job)))
;; ⇒ (:FAILED "The disk is full." 1 1)

;;;; Example: littoral:cancel-job
;;; A job waiting to retry (here :BACKOFF seconds after its first failure) is cancelled at once; a running one at its next JOB-PROGRESS.
(let ((job (submit-job (lambda () (error "Not yet.")) :attempts 3 :backoff 60)))
  (wait-for (lambda () (eq (job-status job) :waiting)))
  (list (job-attempt job) (job-error job) (job-status (cancel-job job))))
;; ⇒ (1 "Not yet." :CANCELLED)

;;;; Example: littoral:job-cancelled littoral:cancel-job
;;; JOB-PROGRESS signals JOB-CANCELLED in a job that was cancelled while running, ending it; the job can clean up with UNWIND-PROTECT.
(let* ((cleaned-up nil)
       (job (submit-job (lambda ()
                          (unwind-protect
                               (loop for step from 1
                                     do (job-progress (min 1 (/ step 1000)))
                                        (sleep 0.01))
                            (setf cleaned-up t))))))
  (wait-for (lambda () (eq (job-status job) :running)))
  (cancel-job job)
  (list (wait-for-job job 5) cleaned-up))
;; ⇒ (:CANCELLED T)

;;;; Example: littoral:list-jobs littoral:job-id
;;; Recent jobs, newest first, each with an id to find it by.
(let* ((job (submit-job (lambda () :ok) :name "Find me"))
       (id (job-id job)))
  (wait-for-job job 5)
  (job-name (find id (list-jobs) :key #'job-id :test #'string=)))
;; ⇒ "Find me"

;;;; Example: littoral:job-view littoral:watch-job littoral:job-view-job littoral:*jobs-channel*
;;; A JOB-VIEW shows a job's progress bar, status and Cancel button; WATCH-JOB, called from the callback that starts the job, redraws it on the session's pages as the job goes.  The view subscribes to *JOBS-CHANNEL*, so its page listens for pushes.  The job here waits for the stream to open first.
(defvar *go* (sb-thread:make-semaphore))
(defclass exporter (component)
  ((view :initform (make-instance 'job-view) :reader view)))
(defmethod children ((self exporter)) (list (view self)))
(defmethod render ((self exporter))
  (h:anchor (:callback (lambda ()
                       (let ((job (submit-job (lambda ()
                                                (sb-thread:wait-on-semaphore *go* :timeout 5)
                                                (job-progress 1/2 "Exporting")
                                                :exported)
                                              :name "Export")))
                         (setf (job-view-job (view self)) job)
                         (watch-job job (view self)))))
    "Export")
  (render-component (view self)))
(with-fresh-applications (("/export" 'exporter :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/export") (click b "Export") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (sb-thread:signal-semaphore *go*)
    (prog1 (list (not (null (has-text-p b "Cancel")))
                 (wait-for (lambda () (search "Done." (sink-text sink)))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ (T T)
