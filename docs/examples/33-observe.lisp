;;;; The examples for health checks, metrics and request logs.

;;;; Example: littoral:add-health-check littoral:remove-health-check
;;; /healthz answers 200 while every check passes and 503 when one signals or returns NIL, naming it.
(add-health-check "mail queue" (lambda () (error "The queue is stuck.")))
;; ⇒ "mail queue"
(unwind-protect
     (multiple-value-bind (status headers body) (raw-request (make-instance 'browser) :get "/healthz")
       (declare (ignore headers))
       (list status (gethash "mail queue" (gethash "checks" (com.inuoe.jzon:parse body)))))
  (remove-health-check "mail queue"))
;; ⇒ (503 "failing: The queue is stuck.")

;;;; Example: littoral:serve-metrics littoral:metrics-text
;;; Mount the metrics text at a path for Prometheus to scrape; by default only requests from this machine get it.  Every request is counted by application, kind and status.
(defclass hello (component) ())
(defmethod render ((self hello)) (h:p () "Hello"))
(serve-metrics :path "/hello-metrics")
(unwind-protect
     (with-fresh-applications (("/hello" 'hello :mode :deployment))
       (let ((b (make-instance 'browser)))
         (visit b "/hello")
         (multiple-value-bind (status headers body) (raw-request b :get "/hello-metrics")
           (list status
                 (getf headers :content-type)
                 (not (null (search "littoral_requests_total{app=\"/hello\",kind=\"page\",status=\"200\"}" body)))
                 (not (null (search "littoral_sessions{app=\"/hello\"} 1" (metrics-text))))))))
  (unmount-handler "/hello-metrics"))
;; ⇒ (200 "text/plain; version=0.0.4; charset=utf-8" T T)

;;;; Example: littoral:define-metric littoral:count-metric
;;; A counter of your own, with a label; /metrics reports it.  SERIES-VALUE reads one series back from the metrics text.
(define-metric "doc_example_orders_total" :counter "Orders placed, by kind." :labels '("kind"))
;; ⇒ "doc_example_orders_total"
(defun series-value (series)
  (let* ((text (metrics-text))
         (start (search (format nil "~A " series) text)))
    (if start (read-from-string text t nil :start (+ start (length series) 1)) 0)))
(let ((before (series-value "doc_example_orders_total{kind=\"book\"}")))
  (count-metric "doc_example_orders_total" '("book"))
  (count-metric "doc_example_orders_total" '("book") 2)
  (- (series-value "doc_example_orders_total{kind=\"book\"}") before))
;; ⇒ 3

;;;; Example: littoral:timing-metric littoral:observe-metric
;;; A histogram counts values into its buckets: TIMING-METRIC observes how long its body took, even when it fails; OBSERVE-METRIC observes any value.
(define-metric "doc_example_report_seconds" :histogram "Time to build a report." :buckets '(0.1 1 10))
(defun series-value (series)
  (let* ((text (metrics-text))
         (start (search (format nil "~A " series) text)))
    (if start (read-from-string text t nil :start (+ start (length series) 1)) 0)))
(let ((before (series-value "doc_example_report_seconds_count"))
      (slow-before (series-value "doc_example_report_seconds_bucket{le=\"1\"}")))
  (timing-metric ("doc_example_report_seconds") (sleep 0.01))
  (observe-metric "doc_example_report_seconds" 5)
  (list (- (series-value "doc_example_report_seconds_count") before)
        (- (series-value "doc_example_report_seconds_bucket{le=\"1\"}") slow-before)))
;; ⇒ (2 1)

;;;; Example: littoral:add-metrics-source littoral:remove-metrics-source littoral:metric-label
;;; A function that writes metrics computed when /metrics is read, such as a queue's length.  METRIC-LABEL escapes a label value.
(metric-label "say \"hi\"")
;; ⇒ "say \\\"hi\\\""
(add-metrics-source "doc-example-queue"
                    (lambda (out)
                      (format out "# TYPE doc_example_queue_length gauge~%~
                                   doc_example_queue_length{queue=\"~A\"} ~D~%"
                              (metric-label "mail") 4)))
;; ⇒ "doc-example-queue"
(unwind-protect
     (let ((text (metrics-text)))
       (list (not (null (search "doc_example_queue_length{queue=\"mail\"} 4" text)))
             (not (null (search "littoral_metrics_source_up{source=\"doc-example-queue\"} 1" text)))))
  (remove-metrics-source "doc-example-queue"))
;; ⇒ (T T)

;;;; Example: littoral:metrics-summary
;;; Headline numbers for a status page.
(defclass hello (component) ())
(defmethod render ((self hello)) (h:p () "Hello"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (visit (make-instance 'browser) "/hello")
  (let ((summary (metrics-summary)))
    (list (getf summary :sessions) (integerp (getf summary :heap)))))
;; ⇒ (1 T)

;;;; Example: littoral:log-requests-to
;;; One line per request, here as JSON into a string.  Binding *REQUEST-LOG* keeps the logging to this example.  Visiting the page is two requests: the first starts the session and redirects.
(defclass hello (component) ())
(defmethod render ((self hello)) (h:p () "Hello"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let ((*request-log* nil)
        (log (make-string-output-stream)))
    (log-requests-to log :format :json)
    (visit (make-instance 'browser) "/hello")
    (with-input-from-string (in (get-output-stream-string log))
      (loop for line = (read-line in nil)
            while line
            collect (let ((entry (com.inuoe.jzon:parse line)))
                      (list (gethash "method" entry) (gethash "path" entry) (gethash "status" entry)))))))
;; ⇒ (("GET" "/hello" 302) ("GET" "/hello" 200))

;;;; Example: littoral:*request-log*
;;; Any function of a plist can take the log: here one that keeps each request's kind and status.
(defclass hello (component) ())
(defmethod render ((self hello)) (h:anchor (:callback (lambda () nil)) "Again"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let* ((seen '())
         (*request-log* (lambda (entry) (push (list (getf entry :kind) (getf entry :status)) seen)))
         (b (make-instance 'browser)))
    (visit b "/hello")
    (click b "Again")
    (reverse seen)))
;; ⇒ (("page" 302) ("page" 200) ("action" 302) ("page" 200))
