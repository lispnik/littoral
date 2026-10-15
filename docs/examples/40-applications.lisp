;;;; The examples for registering applications and their settings.  See tools/doc-examples.lisp for the format.

;;;; Example: littoral:register-application littoral:application littoral:find-application littoral:application-path littoral:application-root-class
;;; An application serves a root component class at a path.  The path is normalised to one leading slash and no trailing one, and FIND-APPLICATION takes either spelling.
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome to the shop"))
(with-fresh-applications ()
  (register-application "shop/" 'storefront :mode :deployment)
  (let ((app (find-application "/shop")))
    (list (application-path app) (application-root-class app) (typep app 'application))))
;; ⇒ ("/shop" STOREFRONT T)

;;;; Example: littoral:list-applications littoral:unregister-application
;;; LIST-APPLICATIONS returns them sorted by path; UNREGISTER-APPLICATION stops serving one.
(defclass blank-page (component) ())
(defmethod render ((self blank-page))
  (p () "Nothing here yet."))
(with-fresh-applications (("/wiki" 'blank-page) ("/blog" 'blank-page) ("/admin" 'blank-page))
  (unregister-application "/admin")
  (mapcar #'application-path (list-applications)))
;; ⇒ ("/blog" "/wiki")

;;;; Example: littoral:application-title littoral:application-mode littoral:application-session-timeout littoral:application-max-continuations littoral:application-max-sessions littoral:application-cookie-sessions-p littoral:application-websockets-p littoral:application-local-only-p littoral:application-content-security-policy littoral:application-max-request-size
;;; Each initarg of REGISTER-APPLICATION has a reader, which SETF changes for the running application.  The defaults:
(defclass blank-page (component) ())
(with-fresh-applications (("/notes" 'blank-page))
  (let ((app (find-application "/notes")))
    (list (application-title app) (application-mode app) (application-session-timeout app)
          (application-max-continuations app) (application-max-sessions app)
          (application-cookie-sessions-p app) (application-websockets-p app)
          (application-local-only-p app) (application-content-security-policy app)
          (application-max-request-size app))))
;; ⇒ (NIL :DEVELOPMENT 1800 50 NIL NIL NIL NIL :STRICT NIL)

;;;; Example: littoral:application-title littoral:application-language littoral:application-stylesheets littoral:application-scripts
;;; The title, language, style sheets and scripts go into every page's head.
(defclass storefront (component) ())
(defmethod render ((self storefront))
  (h1 () "Welcome"))
(with-fresh-applications (("/shop" 'storefront :mode :deployment :title "Fish Shop" :language "fr"
                                   :stylesheets '("/css/shop.css") :scripts '("/js/basket.js")))
  (let* ((b (visit (make-instance 'browser) "/shop"))
         (html (browser-html b)))
    (list (not (null (search "<title>Fish Shop</title>" html)))
          (not (null (search "<html lang=\"fr\">" html)))
          (not (null (search "<link rel=\"stylesheet\" href=\"/css/shop.css\">" html)))
          (not (null (search "<script src=\"/js/basket.js\" defer" html))))))
;; ⇒ (T T T T)

;;;; Example: littoral:application-mode
;;; In :DEVELOPMENT mode, the default, every page ends with the development toolbar (New Session, Halos, …); :DEPLOYMENT leaves it out.
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/dev" 'greeting) ("/live" 'greeting :mode :deployment))
  (list (not (null (find-link (visit (make-instance 'browser) "/dev") "New Session")))
        (body-text (visit (make-instance 'browser) "/live"))))
;; ⇒ (T "Hello")

;;;; Example: littoral:application-credentials
;;; With :CREDENTIALS, a (USER . PASSWORD) pair, the application asks for HTTP basic authentication.
(defclass vault (component) ())
(defmethod render ((self vault))
  (p () "The secret is 42."))
(with-fresh-applications (("/vault" 'vault :mode :deployment :credentials '("ada" . "lovelace")))
  (let ((stranger (make-instance 'browser))
        (ada (make-instance 'browser
                            :headers (list (cons "authorization"
                                                 (concatenate 'string "Basic "
                                                              (cl-base64:string-to-base64-string "ada:lovelace")))))))
    (list (browser-status (visit stranger "/vault"))
          (body-text (visit ada "/vault")))))
;; ⇒ (401 "The secret is 42.")

;;;; Example: littoral:application-local-only-p
;;; A :LOCAL-ONLY application answers only requests from this machine.  A request that came through a proxy (it has an X-Forwarded-For header) is not one, unless *TRUST-FORWARDED-FOR* says to believe the header.
(defclass console (component) ())
(defmethod render ((self console))
  (p () "Console"))
(with-fresh-applications (("/console" 'console :mode :deployment :local-only t))
  (list (browser-status (visit (make-instance 'browser) "/console"))
        (browser-status (visit (make-instance 'browser :headers '(("x-forwarded-for" . "203.0.113.7")))
                               "/console"))))
;; ⇒ (200 403)

;;;; Example: littoral:application-error-handler
;;; An error in a request shows an error page.  :ERROR-HANDLER, a function of the condition, makes the page: it returns a component (rendered on its own, so use plain links) or a string of HTML.
(defclass fragile (component) ())
(defmethod render ((self fragile))
  (anchor (:callback (lambda () (error "The till is stuck."))) "Pay"))
(defclass apology (component)
  ((problem :initarg :problem :reader apology-problem)))
(defmethod render ((self apology))
  (h1 () "Sorry")
  (p () (text (princ-to-string (apology-problem self))))
  (anchor (:href "/till") "Start again"))
(with-fresh-applications (("/till" 'fragile :mode :deployment
                                   :error-handler (lambda (condition)
                                                    (make-instance 'apology :problem condition))))
  (let ((b (visit (make-instance 'browser) "/till")))
    (click b "Pay")
    (list (browser-status b) (body-text b))))
;; ⇒ (500 "Sorry The till is stuck. Start again")

;;;; Example: littoral:application-max-continuations
;;; A session keeps its last MAX-CONTINUATIONS pages for the back button.  Going back to a page it has forgotten shows the session as it is now.
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod states ((self tally))
  (list self))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/kept" 'tally :mode :deployment)
                          ("/forgetful" 'tally :mode :deployment :max-continuations 2))
  (flet ((go-back (path)
           (let* ((b (visit (make-instance 'browser) path))
                  (first-page (browser-url b)))
             (dotimes (i 3) (click b "Add one"))
             (body-text (back-to b first-page)))))
    (list (go-back "/kept") (go-back "/forgetful"))))
;; ⇒ ("Count: 0 Add one" "Count: 3 Add one")

;;;; Example: littoral:application-around-request littoral:application-around-actions
;;; :AROUND-REQUEST wraps the whole request, rendering included; :AROUND-ACTIONS wraps only the callbacks.  Each is a function of a thunk; it must call the thunk and return what the thunk returns.  AROUND-ACTIONS runs for every request for a page, with callbacks or not: here the click runs the callback, and the page it redirects to runs none.
(defvar *shop-currency* nil)
(defvar *action-log* '())
(defclass price-list (component) ())
(defmethod render ((self price-list))
  (p () (text (format nil "Cod: 4 ~A" *shop-currency*)))
  (anchor (:callback (lambda () (push :bought *action-log*))) "Buy"))
(with-fresh-applications (("/prices" 'price-list :mode :deployment
                                     :around-request (lambda (thunk)
                                                       (let ((*shop-currency* "EUR")) (funcall thunk)))
                                     :around-actions (lambda (thunk)
                                                       (push :begin *action-log*)
                                                       (prog1 (funcall thunk)
                                                         (push :commit *action-log*)))))
  (let* ((*action-log* '())
         (b (visit (make-instance 'browser) "/prices")))
    (setf *action-log* '())
    (click b "Buy")
    (list (body-text b) (reverse *action-log*))))
;; ⇒ ("Cod: 4 EUR Buy" (:BEGIN :BOUGHT :COMMIT :BEGIN :COMMIT))

;;;; Example: littoral:application-content-security-policy
;;; Pages get a strict Content-Security-Policy header by default.  A string replaces it ({nonce} stands for the nonce the page gives its scripts); NIL sends none.
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/strict" 'greeting :mode :deployment)
                          ("/own" 'greeting :mode :deployment :content-security-policy "default-src 'self'")
                          ("/none" 'greeting :mode :deployment :content-security-policy nil))
  (flet ((policy (path)
           (let ((b (visit (make-instance 'browser) path)))
             (multiple-value-bind (status headers) (raw-request b :get (browser-url b))
               (declare (ignore status))
               (getf headers :content-security-policy)))))
    (list (subseq (policy "/strict") 0 18) (policy "/own") (policy "/none"))))
;; ⇒ ("default-src 'self'" "default-src 'self'" NIL)

;;;; Example: littoral:application-max-request-size littoral:*max-request-size*
;;; A request whose body is larger than the application's :MAX-REQUEST-SIZE (or, when that is NIL, *MAX-REQUEST-SIZE*) gets 413 before its body is read.
(defclass guestbook (component) ())
(defmethod render ((self guestbook))
  (p () "Sign here"))
(with-fresh-applications (("/guestbook" 'guestbook :mode :deployment :max-request-size 1000))
  (let ((b (make-instance 'browser)))
    (list (raw-request b :post "/guestbook" :body (make-string 2000 :initial-element #\x))
          (let ((*max-request-size* 100))
            (raw-request b :post "/elsewhere" :body (make-string 200 :initial-element #\x))))))
;; ⇒ (413 413)
