;;;; jobs.lisp — background jobs: results, retries, cancelling, the page

(in-package #:littoral/tests)

(def-suite jobs :in littoral)
(in-suite jobs)

(test jobs-run-and-answer
  (let ((job (submit-job (lambda ()
                           (job-progress 1/2 "Half-way")
                           (* 6 7))
                         :name "Answer")))
    (is (eq :done (wait-for-job job 10)))
    (is (= 42 (job-result job)))
    (is (= 1 (job-progress-fraction job)))
    (is (equal "Half-way" (job-message job)))
    (is (member job (list-jobs)))))

(test failing-jobs-are-retried
  (let* ((tries 0)
         (job (submit-job (lambda ()
                            (when (< (incf tries) 3) (error "flaky ~D" tries))
                            :finally)
                          :attempts 3 :backoff 0.2)))
    (is (eq :done (wait-for-job job 20)))
    (is (= 3 tries))
    (is (= 3 (job-attempt job)))
    (is (eq :finally (job-result job)))))

(test jobs-give-up-after-their-attempts
  (let ((job (submit-job (lambda () (error "always broken")) :attempts 2 :backoff 0.2)))
    (is (eq :failed (wait-for-job job 20)))
    (is (= 2 (job-attempt job)))
    (is (search "always broken" (job-error job)))))

(test cancelling-a-running-job
  (let ((job (submit-job (lambda ()
                           (loop for i from 0
                                 do (sleep 0.02) (job-progress (min 99/100 (/ i 1000)))))
                         :name "Endless")))
    (is (wait-for (lambda () (eq :running (job-status job)))))
    (cancel-job job)
    (is (eq :cancelled (wait-for-job job 10)))))

(test cancelling-a-waiting-job
  (let ((job (submit-job (lambda () (error "fails")) :attempts 3 :backoff 60)))
    (is (wait-for (lambda () (eq :waiting (job-status job)))))
    (cancel-job job)
    (is (eq :cancelled (job-status job)))))

(test jobs-run-side-by-side
  (let* ((start (get-internal-real-time))
         (jobs (loop repeat 4 collect (submit-job (lambda () (sleep 0.4) t)))))
    (dolist (job jobs) (is (eq :done (wait-for-job job 10))))
    ;; Four workers: about one sleep's time, not four.
    (is (< (/ (- (get-internal-real-time) start) internal-time-units-per-second) 1.4))))

(test retries-show-on-the-page
  (let ((saved littoral-examples::*job-step-seconds*))
    (setf littoral-examples::*job-step-seconds* 0.01)
    (unwind-protect
         (with-fresh-applications (("/progress" 'littoral-examples:progress-demo :mode :deployment))
           (let* ((b (make-instance 'browser))
                  (sink (make-instance 'sink))
                  (thread (progn (visit b "/progress") (open-stream b sink)))
                  (flaky (second (ajax-specs b "on-click"))))
             (is (wait-for (lambda () (search "retry:" (sink-text sink)))))
             (ajax-request b (first flaky) (rest flaky))
             (is (wait-for (lambda () (search "the network dropped" (sink-text sink))) 10))
             (is (wait-for (lambda () (search "Done." (sink-text sink))) 10))
             (close-event-streams)
             (is (wait-for (lambda () (not (sb-thread:thread-alive-p thread)))))))
      (setf littoral-examples::*job-step-seconds* saved))))
