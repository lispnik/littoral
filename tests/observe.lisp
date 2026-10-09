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
