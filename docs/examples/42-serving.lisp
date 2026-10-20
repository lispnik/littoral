;;;; The examples for serving applications: the Lack app, prefixes, cookies, mounted handlers and limits.  See tools/doc-examples.lisp for the format.

;;;; Example: littoral:set-cookie littoral:request-cookie
;;; A callback queues a cookie with SET-COOKIE; it goes out with the response, scoped to the application's path unless :PATH says otherwise.  REQUEST-COOKIE reads one the browser sent back.  A :MAX-AGE of 0 deletes it.
(defclass biscuit-tin (component) ())
(defmethod render ((self biscuit-tin))
  (h:p () (h:text (format nil "Flavour: ~A" (or (request-cookie "flavour") "none"))))
  (h:p ()
    (h:anchor (:callback (lambda () (set-cookie "flavour" "oat" :max-age 3600))) "Bake")
    " or "
    (h:anchor (:callback (lambda () (set-cookie "flavour" "" :max-age 0))) "Eat")))
(with-fresh-applications (("/tin" 'biscuit-tin :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/tin")))
    (multiple-value-bind (status headers) (raw-request b :get (find-link b "Bake"))
      (list status
            (getf headers :set-cookie)
            (body-text (visit b (getf headers :location)))
            (body-text (click b "Eat"))))))
;; ⇒ (302 "flavour=oat; Path=/tin; Max-Age=3600; HttpOnly; SameSite=Lax" "Flavour: oat Bake or Eat" "Flavour: none Bake or Eat")

;;;; Example: littoral:make-lack-app littoral:url-for littoral:*base-path*
;;; MAKE-LACK-APP returns the Lack application that serves every registered application; mount it under a prefix with Lack's builder, passing the same :PREFIX so the URLs littoral writes include it.  URL-FOR puts *BASE-PATH* in front of a path, as every URL littoral writes does.
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (h:p () (h:text (format nil "Count: ~D" (tally-count self))))
  (h:anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let* ((site (lack:builder
                (:mount "/apps" (make-lack-app :prefix "/apps"))
                (lambda (env) (declare (ignore env)) '(200 (:content-type "text/plain") ("The rest of the site")))))
         (b (make-instance 'browser :app site)))
    (visit b "/apps/tally")
    (click b "Add one")
    (list (body-text b)
          (subseq (browser-url b) 0 (position #\? (browser-url b)))
          (subseq (find-link b "Add one") 0 12))))
;; ⇒ ("Count: 1 Add one" "/apps/tally" "/apps/tally?")
(let ((*base-path* "/apps"))
  (url-for "/tally"))
;; ⇒ "/apps/tally"

;;;; Example: littoral:make-lack-app
;;; The Lack application is a function of a request's environment.  A request for a new session is answered with a redirect to its first page.
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (h:p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (destructuring-bind (status headers body) (funcall (make-lack-app) (make-env :get "/hello"))
    (declare (ignore body))
    (list status (subseq (getf headers :location) 0 10))))
;; ⇒ (302 "/hello?_s=")

;;;; Example: littoral:mount-handler littoral:unmount-handler
;;; A handler mounted at a prefix answers paths under it outside any application: it gets the rest of the path and returns a Lack response.
(unwind-protect
     (progn
       (mount-handler "/hello/" (lambda (rest)
                                  (list 200 '(:content-type "text/plain; charset=utf-8")
                                        (list (format nil "Hello, ~A!" rest)))))
       (body-text (visit (make-instance 'browser) "/hello/world")))
  (unmount-handler "/hello/"))
;; ⇒ "Hello, world!"

;;;; Example: littoral:*debug-errors*
;;; An error in a request normally becomes an error page.  With *DEBUG-ERRORS* true it is not handled, so it reaches the debugger (or, here, the caller).
(defclass fragile (component) ())
(defmethod render ((self fragile))
  (h:anchor (:callback (lambda () (error "The till is stuck."))) "Pay"))
(with-fresh-applications (("/till" 'fragile :mode :deployment))
  (list (browser-status (click (visit (make-instance 'browser) "/till") "Pay"))
        (let ((*debug-errors* t))
          (handler-case (click (visit (make-instance 'browser) "/till") "Pay")
            (error (condition) (princ-to-string condition))))))
;; ⇒ (500 "The till is stuck.")

;;;; Example: littoral:*new-sessions-per-minute* littoral:*trust-forwarded-for*
;;; Each client address may start only so many sessions a minute.  Behind a proxy every request comes from the proxy, so set *TRUST-FORWARDED-FOR* to count the address it reports instead.  (The address here is made up afresh, as the counts last a minute.)
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (h:p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (let* ((*new-sessions-per-minute* 1)
         (*trust-forwarded-for* t)
         (address (format nil "198.18.~D.~D" (random 256) (random 256)))
         (headers (list (cons "x-forwarded-for" address))))
    (list (browser-status (visit (make-instance 'browser :headers headers) "/hello"))
          (browser-status (visit (make-instance 'browser :headers headers) "/hello")))))
;; ⇒ (200 429)

;;;; Example: littoral:*max-event-streams* littoral:*max-event-streams-per-session*
;;; A page with subscribers opens an event stream for server push.  Past either limit, the stream is refused with 503 and the browser tries again later.
(defvar *headlines* (make-channel "headlines"))
(defclass headlines (component) ())
(defmethod subscriptions ((self headlines))
  (list *headlines*))
(defmethod render ((self headlines))
  (h:p () "No news yet"))
(with-fresh-applications (("/news" 'headlines :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/news"))
         (events (cl-ppcre:register-groups-bind (url) ("data-lt-events=\"([^\"]*)\"" (browser-html b))
                   (cl-ppcre:regex-replace-all "&amp;" url "&"))))
    (list (let ((*max-event-streams* 0))
            (raw-request b :get events))
          (let ((*max-event-streams-per-session* 0))
            (raw-request b :get events)))))
;; ⇒ (503 503)

;;;; Example: littoral:start littoral:stop
;;; START serves the registered applications over HTTP until STOP.  It prints the address it listens on.
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (h:p () "Hello"))
(register-application "/hello" 'greeting :mode :deployment)
(unwind-protect
     (progn (start :port 48173)
            (not (null (find-application "/hello"))))
  (stop))
;; ⇒ T
