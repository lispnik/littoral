;;;; monitoring.lisp — the server's own metrics, charted live

(in-package #:littoral-examples)

(defclass monitoring-demo (component updatable)
  ((samples :initform '() :accessor demo-samples :documentation "Newest first: plists from METRICS-SUMMARY.")
   (last :initform nil :accessor demo-last))
  (:documentation "Charts this server's requests, latency and memory, sampled every two seconds."))

(defmethod states ((self monitoring-demo)) (list self))

(defun take-sample (self)
  "Note the metrics now; requests are counted per interval."
  (let* ((now (metrics-summary))
         (last (demo-last self))
         (sample (list :requests (if last (max 0 (- (getf now :requests) (getf last :requests))) 0)
                       :mean-ms (getf now :mean-ms) :heap-mb (round (getf now :heap) (* 1024 1024))
                       :sessions (getf now :sessions) :streams (getf now :streams) :threads (getf now :threads))))
    (setf (demo-last self) now
          (demo-samples self) (subseq (cons sample (demo-samples self)) 0 (min 30 (1+ (length (demo-samples self))))))))

(defmethod render ((self monitoring-demo))
  (h1 () "Monitoring")
  (p () "This server counts and times every request (" (code () "metrics-summary") "), serves "
    (anchor (:href (url-for "/healthz")) (code () "/healthz")) " for load balancers and "
    (anchor (:href (url-for "/metrics")) (code () "/metrics")) " for Prometheus. "
    "This page samples the numbers every two seconds; click around other examples in another tab to move them.")
  (span (:periodical (periodical 2 :callback (lambda () (take-sample self)) :update self)))
  (let* ((samples (reverse (demo-samples self)))
         (latest (or (first (demo-samples self)) (list :requests 0 :mean-ms 0 :heap-mb 0 :sessions 0 :streams 0 :threads 0))))
    (dl (:class "monitoring-figures")
      (loop for (label key unit) in '(("Requests (last 2 s)" :requests "") ("Mean response" :mean-ms " ms")
                                      ("Heap" :heap-mb " MB") ("Sessions" :sessions "") ("Push streams" :streams "")
                                      ("Threads" :threads ""))
            do (div ()
                 (dt () (text label))
                 (dd () (text (format nil "~:[~D~;~,1F~]~A" (eq key :mean-ms) (getf latest key) unit))
                   (sparkline (mapcar (lambda (s) (getf s key)) samples) :label (format nil "~A, recent" label))))))
    (if (< (length samples) 2)
        (p (:class "lt-help") "Collecting samples…")
        (progn
          (line-chart (list (cons "Requests per 2 s" (mapcar (lambda (s) (getf s :requests)) samples)))
                      :title "Requests" :x-labels (loop for i downfrom (* 2 (1- (length samples))) to 0 by 2 collect (format nil "-~Ds" i)))
          (line-chart (list (cons "Heap, MB" (mapcar (lambda (s) (getf s :heap-mb)) samples)))
                      :title "Memory")))))

(defmethod style ((self monitoring-demo))
  ".monitoring-figures { display: grid; grid-template-columns: repeat(auto-fill, minmax(10rem, 1fr)); gap: .8rem; }
.monitoring-figures div { border: 1px solid var(--lt-border); border-radius: 8px; padding: .5rem .7rem; }
.monitoring-figures dt { font-size: .8rem; color: var(--lt-muted); }
.monitoring-figures dd { margin: 0; font-size: 1.3rem; font-weight: 600; display: flex; justify-content: space-between; align-items: center; gap: .5rem; }")
