;;;; The examples for the request context: the current request, session and application.

;;;; Example: littoral:request-parameter littoral:request-parameter-p littoral:request-path
;;; Read the request that started a session in initial-request.  request-parameter-p is true for a parameter given with no value.
(defclass welcome (component)
  ((seen :initform nil :accessor seen)))
(defmethod initial-request ((self welcome) request)
  (setf (seen self) (list (request-path request)
                          (request-parameter "name" request)
                          (request-parameter-p "loud" request)
                          (request-parameter "missing" request))))
(defmethod render ((self welcome))
  (p () (text (prin1-to-string (seen self)))))
(with-fresh-applications (("/welcome" 'welcome :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/welcome/back?name=Ada&loud")
    (body-text b)))
;; ⇒ "(\"/welcome/back\" \"Ada\" T NIL)"

;;;; Example: littoral:*request*
;;; The request being handled, a lack/request:request, for what the helpers don't cover, such as its headers.  The helpers read it by default.
(defclass greeter (component)
  ((language :initform nil :accessor language)))
(defmethod initial-request ((self greeter) request)
  (declare (ignore request))
  (setf (language self)
        (gethash "accept-language" (lack/request:request-headers *request*))))
(defmethod render ((self greeter))
  (p () "Your browser prefers " (text (language self)) "."))
(with-fresh-applications (("/greeter" 'greeter :mode :deployment))
  (let ((b (make-instance 'browser :headers '(("accept-language" . "fr")))))
    (visit b "/greeter")
    (body-text b)))
;; ⇒ "Your browser prefers fr."

;;;; Example: littoral:*session* littoral:*application*
;;; While a request is handled, *session* is its session and *application* its application.  session-property keeps a value in *session* by default.
(defclass visits (component) ())
(defmethod render ((self visits))
  (p () (text (application-title *application*)) ": "
    (text (princ-to-string (or (session-property :clicks) 0))) " clicks")
  (anchor (:callback (lambda ()
                       (setf (session-property :clicks *session*)
                             (1+ (or (session-property :clicks *session*) 0)))))
    "Click"))
(with-fresh-applications (("/visits" 'visits :mode :deployment :title "Visits"))
  (let ((b (make-instance 'browser)))
    (visit b "/visits")
    (click b "Click")
    (click b "Click")
    (body-text b)))
;; ⇒ "Visits: 2 clicks Click"

;;;; Example: littoral:redirect-to
;;; A callback can send the browser elsewhere instead of to the next page.
(defclass exit-page (component) ())
(defmethod render ((self exit-page))
  (anchor (:callback (lambda () (redirect-to "https://example.com/bye"))) "Leave"))
(with-fresh-applications (("/exit" 'exit-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/exit")
    (multiple-value-bind (status headers) (raw-request b :get (find-link b "Leave"))
      (list status (getf headers :location)))))
;; ⇒ (302 "https://example.com/bye")

;;;; Example: littoral:forbidden littoral:forbidden-message
;;; Signal forbidden from a callback (or while rendering) to refuse: the user gets a 403 page with the message.
(defclass vault (component) ())
(defmethod render ((self vault))
  (anchor (:callback (lambda () (error 'forbidden :message "Only the harbour master may open the vault.")))
    "Open"))
(with-fresh-applications (("/vault" 'vault :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/vault")
    (click b "Open")
    (list (browser-status b) (body-text b))))
;; ⇒ (403 "Forbidden Only the harbour master may open the vault.")
(forbidden-message (make-condition 'forbidden))
;; ⇒ "You are not allowed to do that."

;;;; Example: littoral:render-phase-error
;;; Rendering must not change state, so call, show, answer and home signal render-phase-error while a page renders.  Here an error handler shows the condition.
(defclass hasty (component) ())
(defmethod render ((self hasty))
  (answer self 42))                     ; wrong: answer from a callback
(with-fresh-applications (("/hasty" 'hasty :mode :deployment
                                           :error-handler (lambda (condition) (princ-to-string condition))))
  (let ((b (make-instance 'browser)))
    (visit b "/hasty")
    (list (browser-status b) (body-text b))))
;; ⇒ (500 "answer was used while rendering. Rendering must not change state: do it in a callback instead.")
