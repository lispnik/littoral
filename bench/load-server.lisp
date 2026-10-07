;;;; load-server.lisp — the server bench/load.mjs measures
;;;;
;;;;   sbcl --load bench/load-server.lisp --eval '(start-load-server :port 8095)'
;;;;
;;;; Serves the counter, the store and the progress page in deployment mode,
;;;; plus /_stats: heap in use after a full GC, and counts of sessions,
;;;; event streams and threads.

(asdf:load-system :littoral/examples)

(defpackage #:littoral-load (:use #:cl) (:export #:start-load-server))
(in-package #:littoral-load)

(defun stats-json ()
  (sb-ext:gc :full t)
  (format nil "{\"heap\":~D,\"sessions\":~D,\"streams\":~D,\"threads\":~D}"
          (sb-kernel:dynamic-usage)
          (reduce #'+ (littoral:list-applications)
                  :key (lambda (app) (hash-table-count (littoral:application-sessions app))))
          (length (littoral::open-event-streams))
          (length (sb-thread:list-all-threads))))

(defun start-load-server (&key (port 8095) (max-threads 100))
  (setf littoral:*new-sessions-per-minute* nil)
  (dolist (pair '(("/counter" . littoral-examples:counter)
                  ("/store" . littoral-examples:store)
                  ("/progress" . littoral-examples:progress-demo)))
    (littoral:register-application (car pair) (cdr pair) :mode :deployment :max-continuations 20))
  (let ((app (littoral:make-lack-app)))
    (clack:clackup (lambda (env)
                     (if (string= (getf env :path-info) "/_stats")
                         (list 200 '(:content-type "application/json") (list (stats-json)))
                         (funcall app env)))
                   :server :hunchentoot :port port :address "127.0.0.1"
                   :max-thread-count max-threads :max-accept-count (+ max-threads 20)
                   :use-default-middlewares nil :silent t :debug nil))
  (format t "~&Load server on ~D, ~D threads~%" port max-threads))
