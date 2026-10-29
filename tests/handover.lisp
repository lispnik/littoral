;;;; handover.lisp — draining a process so a new one can take over

(in-package #:littoral/tests)

(def-suite handover :in littoral)
(in-suite handover)

(defmacro while-draining ((&rest drain-arguments) &body body)
  "Run BODY after (DRAIN :EXIT NIL …), with no drain hooks, and stop draining after."
  `(let ((littoral::*drain-hooks* '()))
     (unwind-protect
          (progn (let ((*error-output* (make-broadcast-stream)))
                   (drain :exit nil ,@drain-arguments))
                 ,@body)
       (cancel-drain))))

(test draining-keeps-sessions-and-starts-none
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (click b "++")
      (while-draining ()
        (is (draining-p))
        ;; The session this process has goes on working.
        (click b "++")
        (is (= 2 (count-shown b)))
        ;; A new visitor is refused, for the proxy to retry elsewhere.
        (multiple-value-bind (status headers body) (raw-request (make-instance 'browser) :get "/counter")
          (is (= 503 status))
          (is (equal "1" (getf headers :retry-after)))
          (is (search "being replaced" body)))
        ;; A session this process doesn't have goes to the same URL without it.
        (multiple-value-bind (status headers)
            (raw-request (make-instance 'browser) :get "/counter?_s=a.gone&_k=x&_lt_value=1&q=1")
          (is (= 303 status))
          (is (equal "/counter?q=1" (getf headers :location))))
        ;; A page whose session is gone still reloads.
        (multiple-value-bind (status headers body)
            (raw-request (make-instance 'browser) :get "/counter?_s=a.gone&_k=x&_lt_ajax=1")
          (declare (ignore headers))
          (is (= 200 status))
          (is (search "\"reload\":true" body))))
      (is (not (draining-p)))
      (is (= 302 (raw-request (make-instance 'browser) :get "/counter"))))))

(test draining-clears-gone-cookie-sessions
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment :cookie-sessions t))
    (while-draining ()
      (let ((b (make-instance 'browser)))
        (setf (browser-cookies b) (list (cons "_s_counter" "a.gone")))
        (multiple-value-bind (status headers) (raw-request b :get "/counter")
          (is (= 303 status))
          (is (equal "/counter" (getf headers :location)))
          (is (search "_s_counter=; " (getf headers :set-cookie)))
          (is (search "Max-Age=0" (getf headers :set-cookie)))
          (is (not (eq :set-cookie (first headers)))))))))

(test draining-fails-health-checks
  (let ((b (make-instance 'browser)))
    (is (= 200 (fetch b "/healthz")))
    (is (search "littoral_draining 0" (metrics-text)))
    (while-draining ()
      (multiple-value-bind (status headers body) (fetch b "/healthz")
        (declare (ignore headers))
        (is (= 503 status))
        (is (search "\"status\":\"draining\"" body)))
      (is (search "littoral_draining 1" (metrics-text))))
    (is (= 200 (fetch b "/healthz")))))

(test drain-hooks-run-once
  (let ((ran '()))
    (let ((littoral::*drain-hooks* '()))
      (add-drain-hook "broken" (lambda () (push :broken ran) (error "Hook trouble")))
      (add-drain-hook "counting" (lambda () (push :counting ran)))
      (unwind-protect
           (let ((*error-output* (make-broadcast-stream)))
             (with-fresh-applications ()
               (drain :exit nil)
               (drain :exit nil)))
        (cancel-drain))
      (remove-drain-hook "broken")
      (is (equal '("counting") (mapcar #'car littoral::*drain-hooks*))))
    ;; A failing hook doesn't stop the others, and a second DRAIN runs none.
    (is (equal '(:counting :broken) ran))))

(test draining-ends-when-sessions-do
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (while-draining ()
        (let ((*error-output* (make-broadcast-stream)))
          (is (not (littoral::drain-step)))
          (mapc #'expire-session (list-sessions (find-application "/counter")))
          (is (littoral::drain-step))))))
  ;; Or at the deadline, sessions or not.
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (visit (make-instance 'browser) "/counter")
    (while-draining (:seconds 0)
      (let ((*error-output* (make-broadcast-stream)))
        (is (littoral::drain-step))))))

(test the-drain-signal-ends-an-idle-process
  ;; A real process: started with DRAIN-ON-SIGNAL and no sessions, SIGUSR1
  ;; drains it, and it exits with code 0.
  (let* ((port (+ 20000 (random 20000)))
         (process (uiop:launch-program
                   (list (or (uiop:getenv "SBCL") "sbcl") "--non-interactive"
                         "--eval" "(asdf:load-system :littoral)"
                         "--eval" "(littoral:drain-on-signal)"
                         "--eval" (format nil "(littoral:start :port ~D)" port)
                         "--eval" "(loop (sleep 1))")
                   :output nil :error-output nil)))
    (unwind-protect
         (progn
           (is (wait-for (lambda () (ignore-errors (dex:get (format nil "http://127.0.0.1:~D/healthz" port))))
                         120))
           (uiop:run-program (list "kill" "-USR1" (princ-to-string (uiop:process-info-pid process))))
           (is (wait-for (lambda () (not (uiop:process-alive-p process))) 30))
           (is (eql 0 (uiop:wait-process process))))
      (when (uiop:process-alive-p process)
        (uiop:terminate-process process :urgent t)))))
