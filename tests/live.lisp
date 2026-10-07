;;;; live.lisp — redefining rendering methods reloads open pages

(in-package #:littoral/tests)

(def-suite live :in littoral)
(in-suite live)

(defclass live-thing (component) ()
  (:documentation "A component whose render method the test redefines."))

(defmethod render ((self live-thing))
  (p () "version one"))

(defclass bystander (component) ()
  (:documentation "A component on another page, which must not reload."))

(defmethod render ((self bystander))
  (p () "unchanged"))

(test redefinition-reloads-pages-showing-the-class
  (start-live-watcher :interval 0.1)
  (unwind-protect
       (with-fresh-applications (("/live" 'live-thing :mode :development)
                                 ("/other" 'bystander :mode :development))
         (let ((b (make-instance 'browser)) (o (make-instance 'browser))
               (sink (make-instance 'sink)) (other-sink (make-instance 'sink)))
           (visit b "/live")
           (visit o "/other")
           ;; Development pages listen even with nothing subscribed.
           (is (search "data-lt-events" (browser-html b)))
           (let ((stream (open-stream b sink))
                 (other (open-stream o other-sink)))
             (is (wait-for (lambda () (and (search "retry:" (sink-text sink))
                                           (search "retry:" (sink-text other-sink))))))
             ;; As recompiling it in Emacs would.
             (eval '(defmethod render ((self live-thing)) (p () "version two")))
             (is (wait-for (lambda () (search "event: reload" (sink-text sink)))))
             (sleep 0.5)
             (is (not (search "event: reload" (sink-text other-sink))))
             ;; The reloaded page draws its state with the new method.
             (visit b (browser-url b))
             (is (has-text-p b "version two"))
             ;; RELOAD-PAGES covers everything else.
             (is (= 2 (reload-pages)))
             (is (wait-for (lambda () (search "event: reload" (sink-text other-sink)))))
             (close-event-streams)
             (is (wait-for (lambda () (not (or (sb-thread:thread-alive-p stream)
                                              (sb-thread:thread-alive-p other)))))))))
    (stop-live-watcher)
    (eval '(defmethod render ((self live-thing)) (p () "version one")))))

(test deployment-pages-do-not-listen
  (with-fresh-applications (("/live" 'live-thing :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/live")
      (is (not (search "data-lt-events" (browser-html b)))))))

(test method-classes
  (let ((methods (closer-mop:generic-function-methods #'render)))
    (is (member (find-class 'live-thing)
                (littoral::method-classes
                 (remove-if-not (lambda (m) (eq (first (closer-mop:method-specializers m))
                                                (find-class 'live-thing)))
                                methods))))))
