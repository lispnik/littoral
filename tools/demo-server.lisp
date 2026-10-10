;;;; demo-server.lisp — every example and demo in one executable
;;;;
;;;;   make build     writes bin/littoral-demo
;;;;   make docker    builds the image littoral-demo from it
;;;;
;;;; The executable serves on $PORT (default 8080) and $ADDRESS (default
;;;; 127.0.0.1), keeping the demos' files under $DATA_DIR (default the
;;;; temporary directory).  The examples run in development mode, halos and
;;;; all, so publish its port only to this machine.

(dolist (system '(:littoral/examples :littoral/tracker :littoral/tutorial :littoral/admin-demo
                  :littoral/members-demo :littoral/storage-demo :littoral/search-demo
                  :littoral/parenscript-demo :littoral/websocket))
  (asdf:load-system system))

(defpackage #:littoral-demo
  (:use #:cl)
  (:export #:toplevel #:build))

(in-package #:littoral-demo)

(defun data-directory ()
  (uiop:ensure-directory-pathname (or (uiop:getenv "DATA_DIR") (uiop:temporary-directory))))

(defun register-demos ()
  "The demos that keep data register at startup, so their files are opened where they run."
  (let ((data (data-directory)))
    (littoral-tracker:register-tracker)
    (reading-list:register)
    (littoral-admin-demo:register :file (merge-pathnames "littoral-admin-demo.sqlite3" data))
    (littoral-members-demo:register :file (merge-pathnames "littoral-members-demo.sqlite3" data))
    (littoral-gallery:register :directory (merge-pathnames "littoral-gallery/" data))
    (littoral-search-demo:register :file (merge-pathnames "littoral-search-demo.sqlite3" data))
    (littoral-parenscript-demo:register)))

(defun toplevel ()
  "Register the demos and serve them until killed."
  (sb-ext:disable-debugger)
  (register-demos)
  (setf littoral:*trust-forwarded-for* (and (uiop:getenv "TRUST_PROXY") t))
  (littoral:start :port (parse-integer (or (uiop:getenv "PORT") "8080"))
                  :address (or (uiop:getenv "ADDRESS") "127.0.0.1"))
  (loop (sleep 3600)))

(defun build (&optional (output "bin/littoral-demo"))
  "Save the executable at OUTPUT."
  (ensure-directories-exist output)
  (sb-ext:save-lisp-and-die output :executable t :toplevel #'toplevel))
