;;;; The examples for sessions: their keys, roots, properties and ends.  See tools/doc-examples.lisp for the format.

;;;; Example: littoral:session littoral:list-sessions littoral:session-root littoral:application-sessions
;;; Every browser that visits an application gets a SESSION holding its own root component.  LIST-SESSIONS returns them, most recently used first; APPLICATION-SESSIONS is the table behind it, by key.
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let ((ann (visit (make-instance 'browser) "/tally"))
        (bob (visit (make-instance 'browser) "/tally")))
    (click ann "Add one")
    (click ann "Add one")
    (click bob "Add one")
    (let ((app (find-application "/tally")))
      (list (hash-table-count (application-sessions app))
            (every (lambda (s) (typep s 'session)) (list-sessions app))
            (sort (mapcar (lambda (s) (tally-count (session-root s))) (list-sessions app)) #'<)))))
;; ⇒ (2 T (1 2))

;;;; Example: littoral:session-property littoral:session-properties
;;; A session keeps whatever the application stores in it with (SETF SESSION-PROPERTY), by key.  The session defaults to *SESSION*, the current request's.
(defclass visit-counter (component) ())
(defmethod render ((self visit-counter))
  (p () (text (format nil "Pages seen: ~D" (or (session-property :pages) 0))))
  (anchor (:callback (lambda ()
                       (setf (session-property :pages) (1+ (or (session-property :pages) 0)))))
    "Next"))
(with-fresh-applications (("/visits" 'visit-counter :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/visits")))
    (click b "Next")
    (click b "Next")
    (let ((session (first (list-sessions (find-application "/visits")))))
      (list (body-text b)
            (session-property :pages session)
            (hash-table-p (session-properties session))))))
;; ⇒ ("Pages seen: 2 Next" 2 T)

;;;; Example: littoral:session-key littoral:*instance-id*
;;; A session's key is in its pages' URLs (as _s), unless the application keeps it in a cookie.  With *INSTANCE-ID* set, keys start with it, so a load balancer can send each session back to its process.
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (let* ((*instance-id* "a1")
         (b (visit (make-instance 'browser) "/hello"))
         (key (session-key (first (list-sessions (find-application "/hello"))))))
    (list (subseq key 0 3)
          (not (null (search (concatenate 'string "_s=" key) (browser-url b)))))))
;; ⇒ ("a1." T)

;;;; Example: littoral:application-cookie-sessions-p
;;; With :COOKIE-SESSIONS the session key travels in a cookie instead of the URL.
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment :cookie-sessions t))
  (let* ((b (visit (make-instance 'browser) "/hello"))
         (key (session-key (first (list-sessions (find-application "/hello"))))))
    (list (null (search "_s=" (browser-url b)))
          (equal key (cdr (assoc "_s_hello" (browser-cookies b) :test #'string=))))))
;; ⇒ (T T)

;;;; Example: littoral:rotate-session-key
;;; Give the session a new key when its user signs in, so a key someone learned before is no use.  The session and its state carry on under the new key, and the page that follows names it.
(defclass sign-in-page (component)
  ((user :initform nil :accessor signed-in-user)))
(defmethod render ((self sign-in-page))
  (p () (text (or (signed-in-user self) "Nobody")))
  (anchor (:callback (lambda ()
                       (setf (signed-in-user self) "ada")
                       (rotate-session-key)))
    "Sign in"))
(with-fresh-applications (("/members" 'sign-in-page :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/members"))
         (before (session-key (first (list-sessions (find-application "/members"))))))
    (click b "Sign in")
    (let ((after (session-key (first (list-sessions (find-application "/members"))))))
      (list (body-text b)
            (string= before after)
            (null (search before (browser-url b)))
            (length (list-sessions (find-application "/members")))))))
;; ⇒ ("ada Sign in" NIL T 1)

;;;; Example: littoral:expire-session littoral:application-expired-notice littoral:session-expired-notice
;;; EXPIRE-SESSION forgets a session at once, as the timeout does.  The browser's next request starts a new session; with an :EXPIRED-NOTICE, a component class such as SESSION-EXPIRED-NOTICE, the new session shows it first.
(defclass tally (component)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (p () (text (format nil "Count: ~D" (tally-count self))))
  (anchor (:callback (lambda () (incf (tally-count self)))) "Add one"))
(with-fresh-applications (("/tally" 'tally :mode :deployment :expired-notice 'session-expired-notice))
  (let ((b (visit (make-instance 'browser) "/tally")))
    (click b "Add one")
    (expire-session (first (list-sessions (find-application "/tally"))))
    (click b "Add one")
    (list (body-text b)
          (body-text (press b "Continue")))))
;; ⇒ ("Your session expired, so you are starting again from the beginning. Continue" "Count: 0 Add one")

;;;; Example: littoral:application-session-timeout littoral:reap-all-sessions littoral:start-reaper littoral:stop-reaper
;;; A session idle for longer than the application's :SESSION-TIMEOUT (in seconds) is forgotten when next looked up, or by REAP-ALL-SESSIONS, which START-REAPER runs in a thread (START starts one).  A timeout of -1 makes every session too old here, so the example needn't wait.
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (p () "Hello"))
(with-fresh-applications (("/hello" 'greeting :mode :deployment))
  (let ((app (find-application "/hello")))
    (visit (make-instance 'browser) "/hello")
    (let ((before (length (list-sessions app))))
      (setf (application-session-timeout app) -1)
      (reap-all-sessions)
      (list before (length (list-sessions app))))))
;; ⇒ (1 0)
(start-reaper :interval 300)
(stop-reaper)
;; ⇒ NIL
