;;;; progress.lisp — background jobs reporting to the page
;;;;
;;;; SUBMIT-JOB runs work on a pool of threads; JOB-PROGRESS reports how far
;;;; it has got, and the JOB-VIEW watching it is redrawn on this page by
;;;; server push.  The second job fails on its first try and is retried.

(in-package #:littoral-examples)

(defparameter *job-steps* 20)
(defparameter *job-step-seconds* 0.15)

(defun steady-work ()
  (dotimes (i *job-steps*)
    (sleep *job-step-seconds*)
    (job-progress (/ (1+ i) *job-steps*) "Crunching numbers…")))

(defun flaky-work ()
  ;; The first attempt fails half-way; the retry succeeds.
  (dotimes (i *job-steps*)
    (sleep *job-step-seconds*)
    (when (and (= i 8) (= (job-attempt *current-job*) 1))
      (error "the network dropped"))
    (job-progress (/ (1+ i) *job-steps*) "Fetching…")))

(defclass progress-demo (component)
  ((view :initform (make-instance 'job-view) :reader demo-view))
  (:documentation "The progress example page."))

(defmethod children ((self progress-demo))
  (list (demo-view self)))

(defun start-demo-job (self work name attempts)
  (let ((job (submit-job work :name name :attempts attempts :backoff 1)))
    (setf (job-view-job (demo-view self)) job)
    (watch-job job (demo-view self))))

(defmethod render ((self progress-demo))
  (h1 () "Progress")
  (p () "Each button starts a background job with " (code () "submit-job")
    ". The job reports with " (code () "job-progress")
    ", and the bar below is redrawn on this page by server push.")
  (p ()
    (button (:on-click (ajax :callback (lambda () (start-demo-job self #'steady-work "Steady job" 1))
                             :update self))
      "Start the job")
    " "
    (button (:on-click (ajax :callback (lambda () (start-demo-job self #'flaky-work "Flaky job" 3))
                             :update self))
      "Start a job that fails once"))
  (render-component (demo-view self)))
