;;;; observe.lisp — health checks, metrics and request logs
;;;;
;;;;   GET /healthz                 200 {"status":"ok",…}, or 503 when a check fails
;;;;   (add-health-check "database" (lambda () (littoral.db:db-query "SELECT 1")))
;;;;   (serve-metrics)              Prometheus text at /metrics, from this machine only
;;;;   (log-requests-to *standard-output*)          one JSON line per request
;;;;
;;;; Every request is counted by application, kind (page, action, ajax,
;;;; events, websocket, static, other) and status, and timed into a
;;;; histogram.  Logs carry the path, never the query string: session keys
;;;; ride in URLs and must not end up in log files.

(in-package #:littoral)

(defvar *started* (get-universal-time) "When this process started serving.")

;;; Counting requests

(defparameter *latency-buckets* '(0.005 0.01 0.025 0.05 0.1 0.25 0.5 1 2.5 5 10)
  "Upper bounds, in seconds, of the request duration histogram's buckets.")

(defvar *metrics-lock* (sb-thread:make-mutex :name "littoral metrics"))
(defvar *request-counts* (make-hash-table :test 'equal) "(APP KIND STATUS) → count.")
(defvar *request-times* (make-hash-table :test 'equal)
  "(APP KIND) → #(SUM COUNT BUCKET-COUNTS…), one count per bucket of *LATENCY-BUCKETS*.")

(defvar *request-log* nil
  "A function of a plist describing each request (:TIME :METHOD :PATH :APP :KIND
:STATUS :MILLISECONDS :ADDRESS), or NIL.  See LOG-REQUESTS-TO.")

(defun query-has-p (query name)
  "True when the query string QUERY has the parameter NAME."
  (and query (cl-ppcre:scan (format nil "(?:^|&)~A(?:=|&|$)" (cl-ppcre:quote-meta-chars name)) query)))

(defun request-kind (env status)
  (let ((path (getf env :path-info "")) (query (getf env :query-string)))
    (cond ((alexandria:starts-with-subseq "/littoral/files/" path) "static")
          ((query-has-p query "_lt_ws") "websocket")
          ((query-has-p query "_lt_events") "events")
          ((query-has-p query "_lt_ajax") "ajax")
          ((and (eql status 302) (query-has-p query "_k")) "action")
          ((application-for-path path) "page")
          (t "other"))))

(defun response-status (response)
  (if (consp response) (first response) 200))     ; a function streams: it said 200

(defun observe-request (env response start)
  "Count and time the request ENV answered with RESPONSE, begun at START
(internal real time), and log it."
  (let* ((seconds (/ (- (get-internal-real-time) start) internal-time-units-per-second))
         (status (response-status response))
         (path (getf env :path-info ""))
         (app (let ((a (application-for-path path))) (if a (application-path a) "-")))
         (kind (request-kind env status)))
    (sb-thread:with-mutex (*metrics-lock*)
      (incf (gethash (list app kind status) *request-counts* 0))
      (let ((times (or (gethash (list app kind) *request-times*)
                       (setf (gethash (list app kind) *request-times*)
                             (make-array (+ 2 (length *latency-buckets*)) :initial-element 0)))))
        (incf (aref times 0) seconds)
        (incf (aref times 1))
        (loop for bound in *latency-buckets* for i from 2
              when (<= seconds bound) do (incf (aref times i)))))
    (when *request-log*
      (ignore-errors
       (funcall *request-log*
                (list :time (get-universal-time) :method (string (getf env :request-method))
                      :path path :app app :kind kind :status status
                      :milliseconds (float (* 1000 seconds)) :address (getf env :remote-addr)))))))

(defun reset-metrics ()
  (sb-thread:with-mutex (*metrics-lock*)
    (clrhash *request-counts*) (clrhash *request-times*)))

;;; Request logs

(defun iso-time (universal-time)
  (multiple-value-bind (s m h day month year) (decode-universal-time universal-time 0)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ" year month day h m s)))

(defun log-requests-to (stream &key (format :json))
  "Write a line to STREAM for every request: JSON (FORMAT :JSON, for log
collectors) or text (:TEXT).  NIL for STREAM stops logging."
  (setf *request-log*
        (and stream
             (let ((lock (sb-thread:make-mutex :name "littoral request log")))
               (lambda (entry)
                 (let ((line (if (eq format :json)
                                 (format nil "{\"time\":~A,\"method\":~A,\"path\":~A,\"app\":~A,\"kind\":~A,\"status\":~D,\"ms\":~,1F,\"address\":~A}"
                                         (json-string (iso-time (getf entry :time))) (json-string (getf entry :method))
                                         (json-string (getf entry :path)) (json-string (getf entry :app))
                                         (json-string (getf entry :kind)) (getf entry :status)
                                         (getf entry :milliseconds) (json-string (or (getf entry :address) "")))
                                 (format nil "~A ~A ~A ~A ~D ~,1Fms ~A" (iso-time (getf entry :time))
                                         (getf entry :method) (getf entry :path) (getf entry :kind)
                                         (getf entry :status) (getf entry :milliseconds) (or (getf entry :address) "")))))
                   (sb-thread:with-mutex (lock)
                     (write-line line stream)
                     (force-output stream))))))))

;;; Health

(defvar *health-checks* '()
  "(NAME . FUNCTION) pairs; a check fails when its function signals or returns NIL.")

(defun add-health-check (name function)
  "Have /healthz call FUNCTION, of no arguments; it fails when FUNCTION
signals or returns NIL.  Replaces any check called NAME."
  (setf *health-checks* (append (remove name *health-checks* :key #'car :test #'string=)
                                (list (cons name function))))
  name)

(defun remove-health-check (name)
  (setf *health-checks* (remove name *health-checks* :key #'car :test #'string=)))

(defun health-response (rest)
  (if (string/= rest "")
      (simple-page 404 "Not Found")
      (let* ((results (loop for (name . check) in *health-checks*
                            collect (cons name (handler-case (if (funcall check) "ok" "failing")
                                                 (error (e) (format nil "failing: ~A" e))))))
             (ok (every (lambda (r) (string= (cdr r) "ok")) results)))
        (list (if ok 200 503)
              (list :content-type "application/json" :cache-control "no-store")
              (list (format nil "{\"status\":~A,\"uptime\":~D,\"checks\":{~{~A~^,~}}}"
                            (json-string (if ok "ok" "failing")) (- (get-universal-time) *started*)
                            (loop for (name . result) in results
                                  collect (format nil "~A:~A" (json-string name) (json-string result)))))))))

(mount-handler "/healthz" 'health-response)

;;; Metrics, in Prometheus's text format

(defun metric-label (value)
  "VALUE escaped for a Prometheus label."
  (cl-ppcre:regex-replace-all "[\"\\\\\\n]" (princ-to-string value)
                              (lambda (match &rest r) (declare (ignore r))
                                (case (char match 0) (#\Newline "\\n") (t (format nil "\\~A" match))))
                              :simple-calls t))

(defun metrics-text ()
  "Every metric, in Prometheus's text exposition format."
  (with-output-to-string (out)
    (flet ((head (name type help) (format out "# HELP ~A ~A~%# TYPE ~A ~A~%" name help name type)))
      (sb-thread:with-mutex (*metrics-lock*)
        (head "littoral_requests_total" "counter" "Requests answered, by application, kind and status.")
        (loop for (app kind status) being the hash-keys of *request-counts* using (hash-value count)
              do (format out "littoral_requests_total{app=\"~A\",kind=\"~A\",status=\"~A\"} ~D~%"
                         (metric-label app) (metric-label kind) status count))
        (head "littoral_request_duration_seconds" "histogram" "How long requests took to answer.")
        (loop for (app kind) being the hash-keys of *request-times* using (hash-value times)
              do (loop for bound in *latency-buckets* for i from 2
                       do (format out "littoral_request_duration_seconds_bucket{app=\"~A\",kind=\"~A\",le=\"~A\"} ~D~%"
                                  (metric-label app) (metric-label kind) bound (aref times i)))
                 (format out "littoral_request_duration_seconds_bucket{app=\"~A\",kind=\"~A\",le=\"+Inf\"} ~D~%"
                         (metric-label app) (metric-label kind) (aref times 1))
                 (format out "littoral_request_duration_seconds_sum{app=\"~A\",kind=\"~A\"} ~,6F~%"
                         (metric-label app) (metric-label kind) (aref times 0))
                 (format out "littoral_request_duration_seconds_count{app=\"~A\",kind=\"~A\"} ~D~%"
                         (metric-label app) (metric-label kind) (aref times 1))))
      (head "littoral_sessions" "gauge" "Live sessions, by application.")
      (dolist (app (list-applications))
        (format out "littoral_sessions{app=\"~A\"} ~D~%" (metric-label (application-path app))
                (hash-table-count (application-sessions app))))
      (head "littoral_event_streams" "gauge" "Open server push streams and sockets.")
      (format out "littoral_event_streams ~D~%" (length (open-event-streams)))
      (head "littoral_jobs" "gauge" "Background jobs remembered, by status.")
      (let ((jobs (list-jobs)))
        (dolist (status '(:queued :running :waiting :done :failed :cancelled))
          (format out "littoral_jobs{status=\"~(~A~)\"} ~D~%" status (count status jobs :key #'job-status))))
      (head "littoral_heap_bytes" "gauge" "Lisp heap in use.")
      (format out "littoral_heap_bytes ~D~%" (sb-kernel:dynamic-usage))
      (head "littoral_threads" "gauge" "Lisp threads.")
      (format out "littoral_threads ~D~%" (length (sb-thread:list-all-threads)))
      (head "littoral_uptime_seconds" "gauge" "Seconds since the process started serving.")
      (format out "littoral_uptime_seconds ~D~%" (- (get-universal-time) *started*)))))

(defun serve-metrics (&key (path "/metrics") (local-only t))
  "Serve metrics at PATH for Prometheus to scrape.  With LOCAL-ONLY (the
default) only requests from this machine get them: put the scraper there,
or behind the proxy with *TRUST-FORWARDED-FOR* and an allow list."
  (mount-handler path
                 (lambda (rest)
                   (cond ((string/= rest "") (simple-page 404 "Not Found"))
                         ((and local-only (not (local-request-p))) (simple-page 403 "Forbidden"))
                         (t (list 200 (list :content-type "text/plain; version=0.0.4; charset=utf-8"
                                            :cache-control "no-store")
                                  (list (metrics-text))))))))

(defun metrics-summary ()
  "A plist of headline numbers, for pages that show them: :REQUESTS :ERRORS
:SESSIONS :STREAMS :JOBS-RUNNING :HEAP :THREADS :UPTIME and :MEAN-MS."
  (let ((requests 0) (errors 0) (seconds 0) (timed 0))
    (sb-thread:with-mutex (*metrics-lock*)
      (loop for (nil kind status) being the hash-keys of *request-counts* using (hash-value count)
            unless (string= kind "events")
              do (incf requests count)
                 (when (>= status 500) (incf errors count)))
      (loop for (nil kind) being the hash-keys of *request-times* using (hash-value times)
            unless (member kind '("events" "websocket") :test #'string=)
              do (incf seconds (aref times 0)) (incf timed (aref times 1))))
    (list :requests requests :errors errors
          :sessions (reduce #'+ (list-applications) :key (lambda (a) (hash-table-count (application-sessions a))))
          :streams (length (open-event-streams))
          :jobs-running (count :running (list-jobs) :key #'job-status)
          :heap (sb-kernel:dynamic-usage) :threads (length (sb-thread:list-all-threads))
          :uptime (- (get-universal-time) *started*)
          :mean-ms (if (plusp timed) (* 1000 (/ seconds timed)) 0))))
