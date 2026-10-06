;;;; progress.lisp — a background job reporting to the page with NOTIFY

(in-package #:littoral-examples)

(defvar *progress-channel* (make-channel "progress demo")
  "Never published: subscribing just opens the page's event stream, which
NOTIFY then uses.")

(defparameter *job-steps* 20)
(defparameter *job-step-seconds* 0.15)

(defclass progress-bar (component updatable)
  ((done :initform 0 :accessor done-steps)
   (running :initform nil :accessor job-running-p)
   (finished :initform nil :accessor job-finished-p))
  (:documentation "A bar showing a background job's progress, updated by NOTIFY."))

(defun run-job (bar session)
  "Work in another thread, telling the page after every step."
  (sb-thread:make-thread
   (lambda ()
     (dotimes (i *job-steps*)
       (sleep *job-step-seconds*)
       (with-session (session) (setf (done-steps bar) (1+ i)))
       (notify bar session))
     (with-session (session)
       (setf (job-running-p bar) nil
             (job-finished-p bar) t))
     (notify bar session))
   :name "progress example job"))

(defun start-job (bar)
  "Start BAR's job in another thread unless it is already running."
  (unless (job-running-p bar)
    (setf (done-steps bar) 0
          (job-running-p bar) t
          (job-finished-p bar) nil)
    (run-job bar *session*)))

(defmethod render ((self progress-bar))
  (let ((percent (round (* 100 (done-steps self)) *job-steps*)))
    (div (:class "progress")
      (div (:class "progress-track")
        (div (:class "progress-fill" :style (format nil "width: ~D%" percent))))
      (p () (text (cond ((job-running-p self) (format nil "Working… ~D%" percent))
                        ((job-finished-p self) "Done.")
                        (t "Not started."))))
      (button (:on-click (ajax :callback (lambda () (start-job self)) :update self)
               :disabled (job-running-p self))
        (text (if (job-finished-p self) "Run again" "Start the job"))))))

(defclass progress-demo (component)
  ((bar :initform (make-instance 'progress-bar) :reader demo-bar))
  (:documentation "The progress example page."))

(defmethod children ((self progress-demo))
  (list (demo-bar self)))

;; The page must listen for pushes while a job might report.
(defmethod subscriptions ((self progress-bar))
  (list *progress-channel*))

(defmethod render ((self progress-demo))
  (h1 () "Progress")
  (p () "The job runs in a background thread and calls " (code () "notify")
    " after each step; the bar is re-rendered on this page by server push.")
  (render-component (demo-bar self)))

(defmethod style ((self progress-demo))
  ".progress-track { height: 1rem; border: 1px solid var(--lt-border); border-radius: 999px;
                   overflow: hidden; max-width: 30rem; }
.progress-fill { height: 100%; background: var(--lt-accent); transition: width .1s; }")
