;;;; load-server.lisp — the server bench/load.mjs measures
;;;;
;;;;   sbcl --load bench/load-server.lisp --eval '(start-load-server :port 8095)'
;;;;   … (start-load-server :server :woo :workers 4)   ; needs littoral/woo
;;;;
;;;; Serves the counter, the store and a push page in deployment mode, plus
;;;; /_stats (heap in use after a full GC, and counts of sessions, event
;;;; streams and threads) and /_publish (push to every open push page).

(asdf:load-system :littoral/examples)
(asdf:load-system :littoral/woo)

(defpackage #:littoral-load (:use #:cl) (:export #:start-load-server))
(in-package #:littoral-load)

(defvar *channel* (littoral:make-channel "load")
  "What /_publish publishes: every open push page re-renders.")

(defclass push-page (littoral:component littoral:updatable)
  ()
  (:documentation "A page subscribed to *CHANNEL*, so it opens an event stream."))

(defmethod littoral:subscriptions ((self push-page))
  (list *channel*))

(defmethod littoral:render ((self push-page))
  (littoral.html:p () "Pushed " (littoral.html:text (get-universal-time))))

(defun stats-json ()
  (sb-ext:gc :full t)
  (format nil "{\"heap\":~D,\"sessions\":~D,\"streams\":~D,\"threads\":~D}"
          (sb-kernel:dynamic-usage)
          (reduce #'+ (littoral:list-applications)
                  :key (lambda (app) (hash-table-count (littoral:application-sessions app))))
          (length (littoral::open-event-streams))
          (length (sb-thread:list-all-threads))))

(defun start-load-server (&key (port 8095) (max-threads 100) (server :hunchentoot) (workers 4))
  (setf littoral:*new-sessions-per-minute* nil
        littoral:*max-event-streams* 100000)
  (dolist (pair '(("/counter" . littoral-examples:counter)
                  ("/store" . littoral-examples:store)
                  ("/progress" . push-page)))
    (littoral:register-application (car pair) (cdr pair) :mode :deployment :max-continuations 20))
  (let ((app (littoral:make-lack-app)))
    (apply #'clack:clackup
           (lambda (env)
             (cond ((string= (getf env :path-info) "/_stats")
                    (list 200 '(:content-type "application/json") (list (stats-json))))
                   ;; Re-render every open progress page, to test delivery.
                   ((string= (getf env :path-info) "/_publish")
                    (list 200 '(:content-type "text/plain")
                          (list (princ-to-string (littoral:publish *channel*)))))
                   (t (funcall app env))))
           :server server :port port :address "127.0.0.1"
           :use-default-middlewares nil :silent t :debug nil
           (ecase server
             (:hunchentoot (list :max-thread-count max-threads :max-accept-count (+ max-threads 20)))
             (:woo (list :worker-num workers)))))
  (format t "~&Load server on ~D (~(~A~))~%" port server))
