;;;; The examples for live reload: open development pages redraw after code changes.

;;;; Example: littoral:start-live-watcher littoral:stop-live-watcher
;;; While the watcher runs, redefining a render method (as recompiling it in Emacs does) has the open development pages showing that class reload.  A page with no event stream polls the URL in its data-lt-live attribute.
(defclass banner (component) ())
(defmethod render ((self banner)) (p () "Welcome"))
(defun reload-asked-p (browser)
  (let ((url (cl-ppcre:register-groups-bind (u) ("data-lt-live=\"([^\"]*)\"" (browser-html browser))
               (unescape u))))
    (not (null (search "\"reload\":true" (nth-value 2 (raw-request browser :get url)))))))
(start-live-watcher :interval 0.1)
(unwind-protect
     (with-fresh-applications (("/banner" 'banner :mode :development))
       (let ((b (make-instance 'browser)))
         (visit b "/banner")
         (let ((before (reload-asked-p b)))
           (eval '(defmethod render ((self banner)) (p () "Welcome aboard")))
           (list before (wait-for (lambda () (reload-asked-p b)) 3)))))
  (stop-live-watcher))
;; ⇒ (NIL T)

;;;; Example: littoral:reload-pages
;;; For changes the watcher can't see, such as a helper function or a style sheet: reload the open development pages, all of them or those showing one of the classes given.  Pages with an event stream are told through it, and counted.
(defvar *ticks* (make-channel "ticks"))
(defclass dashboard (component updatable) ())
(defmethod subscriptions ((self dashboard)) (list *ticks*))
(defmethod render ((self dashboard)) (p () "Dashboard"))
(with-fresh-applications (("/dashboard" 'dashboard :mode :development))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/dashboard") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (prog1 (list (reload-pages '(dashboard))
                 (wait-for (lambda () (search "event: reload" (sink-text sink)))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ (1 T)

;;;; Example: littoral:*live-reload*
;;; Pages drawn while it is false don't poll for reloads.  Set globally to NIL, it also stops the watcher reloading pages.
(defclass banner (component) ())
(defmethod render ((self banner)) (p () "Welcome"))
(with-fresh-applications (("/banner" 'banner :mode :development))
  (let ((b (make-instance 'browser)))
    (list (progn (visit b "/banner") (not (null (search "data-lt-live" (browser-html b)))))
          (let ((*live-reload* nil))
            (visit b (browser-url b))
            (not (null (search "data-lt-live" (browser-html b))))))))
;; ⇒ (T NIL)
