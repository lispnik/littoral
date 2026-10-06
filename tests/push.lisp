;;;; push.lisp — server-sent events

(in-package #:littoral/tests)

(def-suite push :in littoral)
(in-suite push)

(defclass sink ()
  ((chunks :initform '() :accessor sink-chunks)
   (lock :initform (sb-thread:make-mutex) :reader sink-lock))
  (:documentation "Collects what an event stream writes."))

(defun sink-text (sink)
  "Everything written to SINK so far."
  (sb-thread:with-mutex ((sink-lock sink))
    (format nil "~{~A~}" (reverse (sink-chunks sink)))))

(defun open-stream (browser sink)
  "Open the current page's event stream in a thread, writing into SINK."
  (let* ((url (cl-ppcre:register-groups-bind (u) ("data-lt-events=\"([^\"]*)\"" (browser-html browser))
                (unescape u)))
         (response (funcall (browser-app browser)
                            (make-env :get url :cookies (browser-cookies browser)))))
    (is (functionp response))
    (sb-thread:make-thread
     (lambda ()
       (funcall response
                (lambda (head)
                  (declare (ignore head))
                  (lambda (chunk &key close)
                    (declare (ignore close))
                    (when chunk
                      (sb-thread:with-mutex ((sink-lock sink)) (push chunk (sink-chunks sink)))))))))))

(defun wait-for (predicate &optional (seconds 10))
  "Poll PREDICATE for up to SECONDS; true when it came true."
  (loop repeat (* seconds 20)
        when (funcall predicate) return t
        do (sleep 0.05)))

(test chat-push
  (littoral-examples:clear-room)
  (with-fresh-applications (("/chat" 'littoral-examples:chat :mode :deployment))
    (let ((alice (make-instance 'browser)) (bob (make-instance 'browser)) (sink (make-instance 'sink)))
      (join-chat alice "alice")
      (join-chat bob "bob")
      (is (search "data-lt-events=" (browser-html bob)))
      (let ((thread (open-stream bob sink)))
        (is (wait-for (lambda () (search "retry:" (sink-text sink)))))
        (let ((spec (first (ajax-specs alice "on-submit"))))
          (ajax-request alice (first spec) (rest spec)
                        :fields (list (cons (element-name alice "draft") "pushed hello"))))
        (is (wait-for (lambda () (search "pushed hello" (sink-text sink)))))
        (is (search "event: update" (sink-text sink)))
        (close-event-streams)
        (is (wait-for (lambda () (not (sb-thread:thread-alive-p thread)))))))))

(test pages-without-subscribers-do-not-listen
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (is (not (search "data-lt-events" (browser-html b)))))))

(test stale-page-stream-is-refused
  (with-fresh-applications (("/chat" 'littoral-examples:chat :mode :deployment))
    (let ((b (make-instance 'browser)))
      (join-chat b "carol")
      (let ((url (cl-ppcre:register-groups-bind (u) ("data-lt-events=\"([^\"]*)\"" (browser-html b)) (unescape u))))
        (is (= 204 (first (funcall (browser-app b)
                                   (make-env :get (cl-ppcre:regex-replace "_k=[^&]*" url "_k=gone")
                                             :cookies (browser-cookies b))))))))))

(test notify-from-a-background-thread
  ;; The job runs in its own thread, which does not see LET bindings, so
  ;; the step time is set globally for the test's duration.
  (let ((saved littoral-examples::*job-step-seconds*))
    (setf littoral-examples::*job-step-seconds* 0.01)
    (unwind-protect
         (with-fresh-applications (("/progress" 'littoral-examples:progress-demo :mode :deployment))
           (let* ((b (make-instance 'browser))
                  (sink (make-instance 'sink))
                  (thread (progn (visit b "/progress") (open-stream b sink)))
                  (spec (first (ajax-specs b "on-click"))))
             (is (wait-for (lambda () (search "retry:" (sink-text sink)))))
             (ajax-request b (first spec) (rest spec))
             (is (wait-for (lambda () (search "Done." (sink-text sink)))))
             (is (search "width: 50%" (sink-text sink)))
             (close-event-streams)
             (is (wait-for (lambda () (not (sb-thread:thread-alive-p thread)))))))
      (setf littoral-examples::*job-step-seconds* saved))))
