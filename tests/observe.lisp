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

(test request-logs-carry-an-id-agent-and-referrer
  (let* ((entries '())
         (*request-log* (lambda (entry) (push entry entries))))
    (with-fresh-applications (("/logged" 'littoral-examples:counter :mode :deployment))
      (destructuring-bind (status headers body)
          (funcall (make-lack-app)
                   (make-env :get "/logged" :extra-headers '(("User-Agent" . "TestAgent/1")
                                                              ("Referer" . "https://elsewhere.example/p?_s=secret#x"))))
        (declare (ignore body))
        (is (= 302 status))
        (let ((entry (first entries)))
          (is (equal (getf headers :x-request-id) (getf entry :request-id)) "The response says which line")
          (is (cl-ppcre:scan "^[0-9a-f]{16}$" (getf entry :request-id)))
          (is (equal "TestAgent/1" (getf entry :user-agent)))
          (is (equal "https://elsewhere.example/p" (getf entry :referrer)) "No query, where keys ride")
          (is (null (getf entry :user)) "Nobody signed in")
          (is (integerp (getf entry :bytes)))))
      ;; Each request gets its own id; a proxy's is taken only when trusted.
      (let ((env (make-env :get "/logged" :extra-headers '(("X-Request-Id" . "proxy-42")))))
        (funcall (make-lack-app) env)
        (is (not (equal "proxy-42" (getf (first entries) :request-id))))
        (is (not (equal (getf (first entries) :request-id) (getf (second entries) :request-id))))
        (let ((*trust-forwarded-for* t))
          (funcall (make-lack-app) (make-env :get "/logged" :extra-headers '(("X-Request-Id" . "proxy-42"))))
          (is (equal "proxy-42" (getf (first entries) :request-id)))
          (funcall (make-lack-app) (make-env :get "/logged" :extra-headers '(("X-Request-Id" . "bad id\"}"))))
          (is (cl-ppcre:scan "^[0-9a-f]{16}$" (getf (first entries) :request-id)) "Odd ids are replaced"))))))

(test request-log-lines-have-the-new-fields
  (let ((json (make-string-output-stream))
        (text (make-string-output-stream))
        (entry (list :time 0 :method "GET" :path "/p" :app "/p" :kind "page" :status 200 :milliseconds 1.5
                     :address "127.0.0.1" :request-id "abc" :user "7" :user-agent "Agent \"X\"" :referrer nil
                     :bytes 120)))
    (let ((*request-log* nil))
      (log-requests-to json)
      (funcall *request-log* entry)
      (log-requests-to text :format :text)
      (funcall *request-log* entry))
    (let ((parsed (com.inuoe.jzon:parse (get-output-stream-string json))))
      (is (equal "abc" (gethash "id" parsed)))
      (is (equal "7" (gethash "user" parsed)))
      (is (equal 120 (gethash "bytes" parsed)))
      (is (equal "Agent \"X\"" (gethash "agent" parsed)))
      (is (null (nth-value 1 (gethash "referrer" parsed))) "Unknown fields are left out"))
    (is (search " abc 7 120" (get-output-stream-string text)))))

(test request-log-from-the-environment
  (let ((file (merge-pathnames (format nil "littoral-requests-~36R.log" (random (expt 36 8)))
                               (uiop:temporary-directory))))
    (unwind-protect
         (let ((*request-log* nil))
           (setf (uiop:getenv "LITTORAL_REQUEST_LOG") "off")
           (is (null (log-requests-from-environment)))
           (setf (uiop:getenv "LITTORAL_REQUEST_LOG") (namestring file))
           (is (functionp (log-requests-from-environment)))
           (let ((set *request-log*))
             (is (eq set (log-requests-from-environment)) "A log already set is kept"))
           (with-fresh-applications (("/logged" 'littoral-examples:counter :mode :deployment))
             (visit (make-instance 'browser) "/logged"))
           (is (search "\"path\":\"/logged\"" (alexandria:read-file-into-string file))))
      (setf (uiop:getenv "LITTORAL_REQUEST_LOG") "")
      (ignore-errors (delete-file file)))))

(test error-pages-give-the-request-id
  (with-fresh-applications (("/k" 'kaboom :mode :deployment))
    (let ((b (make-instance 'browser))
          (*request-log* nil)
          (ids '()))
      (visit b "/k")
      (let ((*request-log* (lambda (entry) (push (getf entry :request-id) ids))))
        (click b "explode"))
      (is (= 500 (browser-status b)))
      (is (has-text-p b (format nil "Reference: ~A" (car (last ids))))))))

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
           (let ((text (metrics-text)))
             (is (not (search (format nil "littoral_durable_jobs_database_up{~A}" label) text)))
             (is (not (search (format nil "littoral_mail_outbox_database_up{~A}" label) text)))))
      (dolist (suffix '("" "-wal" "-shm"))
        (uiop:delete-file-if-exists (concatenate 'string (namestring file) suffix))))))

(defun metric-value (series &optional (text (metrics-text)))
  "The value of SERIES, such as \"littoral_x_total{a=\\\"b\\\"}\", in TEXT, or NIL."
  (let ((start (search (format nil "~A " series) text)))
    (and start
         (let ((*read-default-float-format* 'double-float))
           (read-from-string text t nil :start (+ start (length series) 1))))))

(test defined-metrics-count-and-time
  (define-metric "littoral_test_events_total" :counter "Test events." :labels '("kind"))
  (define-metric "littoral_test_seconds" :histogram "Test durations." :buckets '(0.1 1))
  (reset-metrics)
  (count-metric "littoral_test_events_total" '("a"))
  (count-metric "littoral_test_events_total" '("a") 2)
  (count-metric "littoral_test_events_total" '("b \"quoted\""))
  (observe-metric "littoral_test_seconds" 0.5)
  (ignore-errors (timing-metric ("littoral_test_seconds") (error "timed anyway")))
  (let ((text (metrics-text)))
    (is (search "# TYPE littoral_test_events_total counter" text))
    (is (= 3 (metric-value "littoral_test_events_total{kind=\"a\"}" text)))
    (is (= 1 (metric-value "littoral_test_events_total{kind=\"b \\\"quoted\\\"\"}" text)))
    (is (= 2 (metric-value "littoral_test_seconds_count" text)))
    (is (= 1 (metric-value "littoral_test_seconds_bucket{le=\"0.1\"}" text)) "The failing body took no time")
    (is (= 2 (metric-value "littoral_test_seconds_bucket{le=\"1\"}" text)))
    (is (= 2 (metric-value "littoral_test_seconds_bucket{le=\"+Inf\"}" text)))
    (is (search "littoral_build_info{littoral=" text))
    (is (metric-value "littoral_gc_seconds_total" text))
    (is (metric-value "littoral_allocated_bytes_total" text)))
  (signals error (count-metric "littoral_no_such_total"))
  (reset-metrics)
  (is (null (metric-value "littoral_test_events_total{kind=\"a\"}"))))

(test sessions-are-counted
  (reset-metrics)
  (with-fresh-applications (("/counted-sessions" 'littoral-examples:counter :mode :deployment :max-sessions 1))
    (visit (make-instance 'browser) "/counted-sessions")
    (visit (make-instance 'browser) "/counted-sessions")
    (let ((text (metrics-text)))
      (is (= 2 (metric-value "littoral_sessions_created_total{app=\"/counted-sessions\"}" text)))
      (is (= 1 (metric-value "littoral_sessions_ended_total{app=\"/counted-sessions\",reason=\"evicted\"}" text))))))

(test query-parameters-are-found-by-name
  (dolist (query '("_k=1" "a=b&_k=2" "_k" "a&_k&b" "_k=" "x=1&_k=&y"))
    (is (littoral::query-has-p query "_k") "~S has _k" query))
  (dolist (query '(nil "" "_kx=1" "a=_k" "x_k=1" "a=b&_kk" "_" "&"))
    (is (not (littoral::query-has-p query "_k")) "~S has no _k" query)))

(test latency-buckets-can-change
  ;; Timings kept with the old buckets would overflow; the histogram starts again.
  (with-fresh-applications (("/rebucketed" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/rebucketed")
      (let ((*latency-buckets* (append *latency-buckets* '(30 60))))
        (visit b "/rebucketed")
        (is (search "le=\"60\"" (metrics-text))))
      (visit b "/rebucketed")
      (is (not (search "le=\"60\"" (metrics-text)))))))

(test closed-event-streams-are-logged
  (reset-metrics)
  (littoral-examples:clear-room)
  (let ((lines (make-string-output-stream)))
    (log-requests-to lines)
    (unwind-protect
         (with-fresh-applications (("/chat" 'littoral-examples:chat :mode :deployment))
           (let ((bob (make-instance 'browser)) (sink (make-instance 'sink)))
             (join-chat bob "bob")
             (let ((thread (open-stream bob sink)))
               (close-event-streams)
               (is (wait-for (lambda () (not (sb-thread:thread-alive-p thread))))))))
      (log-requests-to nil))
    (let ((closed (find-if (lambda (line) (search "events-closed" line))
                           (uiop:split-string (get-output-stream-string lines) :separator '(#\Newline)))))
      (is (not (null closed)))
      (when closed
        (let ((entry (com.inuoe.jzon:parse closed)))
          (is (equal "/chat" (gethash "app" entry)))
          (is (integerp (gethash "updates" entry)))
          (is (plusp (length (gethash "id" entry))))))))
  (is (eql 1 (metric-value "littoral_event_stream_seconds_count{app=\"/chat\"}"))))
