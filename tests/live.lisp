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

(defun live-poll (browser)
  "What the page's live-reload poll answers."
  (let ((url (cl-ppcre:register-groups-bind (u) ("data-lt-live=\"([^\"]*)\"" (browser-html browser))
               (unescape u))))
    (multiple-value-bind (status headers body) (raw-request browser :get url)
      (declare (ignore headers))
      (values (search "\"reload\":true" body) status))))

(test redefinition-reloads-pages-showing-the-class
  (start-live-watcher :interval 0.1)
  (unwind-protect
       (with-fresh-applications (("/live" 'live-thing :mode :development)
                                 ("/other" 'bystander :mode :development))
         (let ((b (make-instance 'browser)) (o (make-instance 'browser)))
           (visit b "/live")
           (visit o "/other")
           ;; Development pages poll; they hold no connection open.
           (is (search "data-lt-live" (browser-html b)))
           (is (not (search "data-lt-events" (browser-html b))))
           (is (not (live-poll b)))
           ;; As recompiling it in Emacs would.
           (eval '(defmethod render ((self live-thing)) (p () "version two")))
           (is (wait-for (lambda () (live-poll b)) 3))
           (is (not (live-poll o)))
           ;; The reloaded page draws its state with the new method.
           (visit b (browser-url b))
           (is (has-text-p b "version two"))
           (is (not (live-poll b)))
           ;; RELOAD-PAGES covers everything else.
           (reload-pages)
           (is (live-poll o))))
    (stop-live-watcher)
    (eval '(defmethod render ((self live-thing)) (p () "version one")))))

(test pages-with-streams-reload-through-them
  (with-fresh-applications (("/progress" 'littoral-examples:progress-demo :mode :development))
    (let ((b (make-instance 'browser)) (sink (make-instance 'sink)))
      (visit b "/progress")
      (is (search "data-lt-events" (browser-html b)))
      (is (not (search "data-lt-live" (browser-html b))))
      (let ((stream (open-stream b sink)))
        (is (wait-for (lambda () (search "retry:" (sink-text sink)))))
        (is (= 1 (reload-pages)))
        (is (wait-for (lambda () (search "event: reload" (sink-text sink)))))
        (close-event-streams)
        (is (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))))

(test deployment-pages-do-not-listen
  (with-fresh-applications (("/live" 'live-thing :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/live")
      (is (not (search "data-lt-events" (browser-html b))))
      (is (not (search "data-lt-live" (browser-html b)))))))

(test method-classes
  (let ((methods (closer-mop:generic-function-methods #'render)))
    (is (member (find-class 'live-thing)
                (littoral::method-classes
                 (remove-if-not (lambda (m) (eq (first (closer-mop:method-specializers m))
                                                (find-class 'live-thing)))
                                methods))))))
