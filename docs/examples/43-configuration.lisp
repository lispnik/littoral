;;;; The examples for application settings saved to a file and read back.  See tools/doc-examples.lisp for the format.

;;;; Example: littoral:application-settings
;;; An application's settings as a plist, the way SAVE-CONFIGURATION writes them.  The root class is a string, so a file naming a system that isn't loaded still reads.
(defclass storefront (component) ())
(with-fresh-applications (("/shop" 'storefront :title "Fish Shop" :mode :deployment :max-sessions 500))
  (let ((settings (application-settings (find-application "/shop"))))
    (list (getf settings :path)
          (string= (getf settings :root-class) (format nil "~A::STOREFRONT" (package-name *package*)))
          (getf settings :title) (getf settings :mode) (getf settings :max-sessions))))
;; ⇒ ("/shop" T "Fish Shop" :DEPLOYMENT 500)

;;;; Example: littoral:configure-application
;;; CONFIGURE-APPLICATION changes only the settings it is given, and keeps the application's sessions.  For a path with no application it registers one, so it needs :ROOT-CLASS then.
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h:h1 () "Welcome"))
(with-fresh-applications (("/shop" 'storefront :title "Fish Shop" :mode :deployment))
  (visit (make-instance 'browser) "/shop")
  (configure-application "/shop" :title "Fish & Chip Shop")
  (configure-application "/shop-test" :root-class 'storefront :mode :deployment)
  (let ((app (find-application "/shop")))
    (list (application-title app) (application-mode app) (length (list-sessions app))
          (mapcar #'application-path (list-applications)))))
;; ⇒ ("Fish & Chip Shop" :DEPLOYMENT 1 ("/shop" "/shop-test"))

;;;; Example: littoral:save-configuration littoral:load-configuration littoral:*configuration-file*
;;; SAVE-CONFIGURATION writes every registered application's settings to a file (by default *CONFIGURATION-FILE*, which START's :CONFIGURATION-FILE sets); LOAD-CONFIGURATION reads them back, registering or changing applications.  Error handlers and other functions are not saved.
(defclass storefront (component) ())
(let ((*configuration-file* (merge-pathnames (format nil "littoral-config-~D.lisp" (random 1000000))
                                             (uiop:temporary-directory))))
  (unwind-protect
       (progn
         (with-fresh-applications (("/shop" 'storefront :title "Fish Shop" :session-timeout 600))
           (save-configuration))
         (with-fresh-applications ()
           (let ((app (first (load-configuration))))
             (list (application-path app) (application-root-class app)
                   (application-title app) (application-session-timeout app)))))
    (delete-file *configuration-file*)))
;; ⇒ ("/shop" STOREFRONT "Fish Shop" 600)

;;;; Example: littoral:configure-admin
;;; The configuration application edits the registered applications' settings in the browser.  Littoral serves it at /config for requests from this machine only; with :USER and :PASSWORD it is behind HTTP basic authentication instead, and answers anyone who has them.
(with-fresh-applications ()
  (let ((open (configure-admin))
        (guarded (configure-admin :path "/settings" :user "admin" :password "correct horse")))
    (list (application-path open) (application-local-only-p open) (application-credentials open)
          (application-path guarded) (application-local-only-p guarded) (application-credentials guarded))))
;; ⇒ ("/config" T NIL "/settings" NIL ("admin" . "correct horse"))
