;;;; observe.lisp — /healthz, metrics and request logs

(in-package #:littoral/tests)

(def-suite observe :in littoral)
(in-suite observe)

(defun fetch (b path)
  "Status, headers and body of PATH, as the fake browser B gets them."
  (multiple-value-bind (status headers body) (raw-request b :get path)
    (values status headers body)))

(test health-checks
  (let ((b (make-instance 'browser)))
    (multiple-value-bind (status headers body) (fetch b "/healthz")
      (is (= 200 status))
      (is (search "application/json" (getf headers :content-type)))
      (is (search "\"status\":\"ok\"" body)))
    (add-health-check "flaky" (lambda () (error "the disk is full")))
    (unwind-protect
         (multiple-value-bind (status headers body) (fetch b "/healthz")
           (declare (ignore headers))
           (is (= 503 status))
           (is (search "the disk is full" body)))
      (remove-health-check "flaky"))))

(test uptime-counts-from-when-an-image-starts
  ;; An executable saved an hour after loading must not report that hour.
  (is (member 'littoral::reset-start-time sb-ext:*init-hooks*))
  (let ((littoral::*started* (- (get-universal-time) 3600)))
    (mapc #'funcall (remove 'littoral::reset-start-time sb-ext:*init-hooks* :test-not #'eq))
    (multiple-value-bind (status headers body) (fetch (make-instance 'browser) "/healthz")
      (declare (ignore status headers))
      (is (cl-ppcre:scan "\"uptime\":[0-5]," body)))))

(test metrics-count-and-time-requests
  (reset-metrics)
  (with-fresh-applications (("/counted" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counted")
      (click b "++")
      (serve-metrics)
      (unwind-protect
           (multiple-value-bind (status headers body) (fetch b "/metrics")
             (is (= 200 status))
             (is (search "text/plain" (getf headers :content-type)))
             (is (search "littoral_requests_total{app=\"/counted\",kind=\"page\",status=\"200\"}" body))
             (is (search "littoral_requests_total{app=\"/counted\",kind=\"action\",status=\"302\"} 1" body))
             (is (search "littoral_request_duration_seconds_bucket{app=\"/counted\",kind=\"page\",le=\"+Inf\"}" body))
             (is (search "littoral_sessions{app=\"/counted\"} 1" body))
             (is (search "littoral_heap_bytes" body)))
        (unmount-handler "/metrics"))
      (let ((summary (metrics-summary)))
        (is (>= (getf summary :requests) 3))
        (is (= 1 (getf summary :sessions)))))))

(test metrics-only-from-this-machine
  (serve-metrics)
  (unwind-protect
       (destructuring-bind (status headers body)
           (funcall (make-lack-app)
                    (let ((env (make-env :get "/metrics"))) (setf (getf env :remote-addr) "203.0.113.9") env))
         (declare (ignore headers body))
         (is (= 403 status)))
    (unmount-handler "/metrics")))

(test request-logs-leave-out-the-query
  (let ((lines (make-string-output-stream)))
    (log-requests-to lines)
    (unwind-protect
         (with-fresh-applications (("/logged" 'littoral-examples:counter :mode :deployment))
           (let ((b (make-instance 'browser)))
             (visit b "/logged")
             (click b "++")))
      (log-requests-to nil))
    (let ((text (get-output-stream-string lines)))
      (is (search "\"path\":\"/logged\"" text))
      (is (search "\"kind\":\"action\"" text))
      (is (search "\"status\":302" text))
      ;; Session keys ride in the query string: never logged.
      (is (not (search "_s=" text)))
      (is (not (search "_k=" text))))))

(test metrics-report-job-queues-and-outboxes
  (let* ((file (merge-pathnames (format nil "littoral-metrics-~36R.sqlite3" (random (expt 36 8)))
                                (uiop:temporary-directory)))
         (spec (list :sqlite3 :database-name (namestring file)))
         (label (format nil "database=\"~A\"" (namestring file))))
    (unwind-protect
         (let ((littoral.db:*database* spec))
           (littoral.mail:create-mail-tables)
           (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :subject "Hi" :text "x"))
           (let ((late (littoral.jobs:enqueue-job (list 'record-job 1 2))))
             (littoral.db:db-execute "UPDATE job_queue SET run_at = ? WHERE id = ?" (- (get-universal-time) 120) late))
           (littoral.db:db-execute "UPDATE mail_outbox SET created = ?" (- (get-universal-time) 300))
           (let ((text (metrics-text))
                 (queued (cdr (assoc "queued" (littoral.jobs:durable-job-counts) :test #'string=))))
             (is (search (format nil "littoral_durable_jobs{~A,queue=\"default\",status=\"queued\"} ~D" label queued)
                         text))
             (is (search (format nil "littoral_durable_jobs_database_up{~A} 1" label) text))
             (let ((waited (cl-ppcre:register-groups-bind ((#'parse-integer seconds))
                               ((format nil "littoral_durable_jobs_oldest_due_seconds\\{~A,queue=\"default\"\\} (\\d+)"
                                        (cl-ppcre:quote-meta-chars label))
                                text)
                             seconds)))
               (is (and waited (<= 120 waited 130))))
             (is (search (format nil "littoral_mail_outbox{~A,status=\"queued\"} 1" label) text))
             (is (cl-ppcre:scan (format nil "littoral_mail_oldest_unsent_seconds\\{~A\\} 3\\d\\d"
                                        (cl-ppcre:quote-meta-chars label))
                                text))
             (is (search "littoral_metrics_source_up{source=\"durable-jobs\"} 1" text))
             (is (search "littoral_job_runner_threads " text)))
           ;; A source that fails reports 0, and none of its partial output.
           (add-metrics-source "broken" (lambda (out) (write-string "half_written_metric" out) (error "no")))
           (unwind-protect
                (let ((text (metrics-text)))
                  (is (search "littoral_metrics_source_up{source=\"broken\"} 0" text))
                  (is (not (search "half_written_metric" text))))
             (remove-metrics-source "broken"))
           ;; A database that can't be read is reported down; one whose
           ;; tables were dropped isn't reported at all.
           (littoral.db:db-execute "DROP TABLE job_queue")
           (is (search (format nil "littoral_durable_jobs_database_up{~A} 0" label) (metrics-text)))
           (littoral.mail:drop-mail-tables)
           (littoral.jobs:drop-job-tables)
           (is (not (search label (metrics-text)))))
      (dolist (suffix '("" "-wal" "-shm"))
        (uiop:delete-file-if-exists (concatenate 'string (namestring file) suffix))))))
