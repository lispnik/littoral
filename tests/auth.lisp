;;;; auth.lisp — users, signing in, roles, password reset, OAuth

(in-package #:littoral/tests)

(def-suite auth :in littoral)
(in-suite auth)

(defclass members-area (littoral.auth:restricted component) ()
  (:documentation "Signed-in users only."))

(defmethod render ((self members-area))
  (p () "Members' news")
  (anchor (:callback (lambda () (littoral.auth:require-role :admin))) "admin action"))

(defclass admin-area (littoral.auth:restricted component) ()
  (:documentation "Admins only."))

(defmethod littoral.auth:required-role ((self admin-area)) :admin)

(defmethod render ((self admin-area))
  (p () "Admin console"))

(defclass members-app (littoral.auth:auth-root component)
  ((members :initform (make-instance 'members-area) :reader app-members)
   (admin :initform (make-instance 'admin-area) :reader app-admin))
  (:documentation "A root with a members' area and an admins' area."))

(defmethod children ((self members-app))
  (list (app-members self) (app-admin self)))

(defmethod render ((self members-app))
  (let ((user (littoral.auth:current-user)))
    (p (:class "who") (text (if user (format nil "Signed in as ~A" (littoral.auth:user-name user)) "Not signed in")))
    (when user (littoral.auth:sign-out-link)))
  (render-component (app-members self))
  (render-component (app-admin self)))

(defmacro with-auth ((b) &body body)
  "A members app over a fresh users table, with ada (admin) and bob."
  `(with-fresh-applications (("/m" 'members-app :mode :deployment))
     (littoral.db:connect-database :sqlite3 :database-name ":memory:")
     (littoral.db:drop-table 'littoral.auth:user)
     (littoral.auth:create-auth-tables)
     (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin))
     (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
     (clrhash littoral.auth::*failures*)
     (let ((littoral.auth:*public-url* "http://localhost")
           (,b (make-instance 'browser)))
       (visit ,b "/m")
       ,@body)))

(defun sign-in-as (b name password)
  (click b "Sign in")
  (fill-in b "sign-in-name" name)
  (fill-in b "sign-in-password" password)
  (press b "Sign in"))

(test users-and-passwords
  (with-auth (b)
    (let ((ada (littoral.auth:find-user "ADA")))
      (is (string= "ada" (littoral.auth:user-name ada)))
      (is (littoral.auth:check-password ada "correct horse battery"))
      (is (not (littoral.auth:check-password ada "wrong")))
      (is (equal '(:admin) (littoral.auth:user-roles ada)))
      (is (search "PBKDF2" (string-upcase (littoral.auth::user-password-hash ada))))
      (signals error (littoral.auth:add-user "Ada" "x@example.org" "whatever pass")))))

(test restricted-components
  (with-auth (b)
    (is (has-text-p b "Not signed in"))
    (is (has-text-p b "Please sign in to see this."))
    (is (not (has-text-p b "Members' news")))
    (sign-in-as b "bob" "wrong")
    (is (has-text-p b "Unknown user or wrong password."))
    (fill-in b "sign-in-name" "bob")
    (fill-in b "sign-in-password" "another passphrase")
    (press b "Sign in")
    (is (has-text-p b "Signed in as bob"))
    (is (has-text-p b "Members' news"))
    ;; Bob is not an admin.
    (is (has-text-p b "You don't have permission to see this."))
    (is (not (has-text-p b "Admin console")))
    (click b "admin action")
    (is (= 403 (browser-status b)))
    (visit b "/m")
    (sign-in-as b "ada" "correct horse battery")
    (is (has-text-p b "Admin console"))
    (click b "Sign out")
    (is (has-text-p b "Not signed in"))))

(test lockout-after-failures
  (let ((littoral.auth:*lockout-failures* 3) (littoral.auth:*lockout-seconds* 2))
    (with-auth (b)
      (click b "Sign in")
      (dotimes (i 3)
        (fill-in b "sign-in-name" "bob")
        (fill-in b "sign-in-password" "wrong")
        (press b "Sign in"))
      ;; Now even the right password is refused for a while.
      (fill-in b "sign-in-name" "bob")
      (fill-in b "sign-in-password" "another passphrase")
      (press b "Sign in")
      (is (has-text-p b "Too many failed attempts"))
      (sleep 2.1)
      (fill-in b "sign-in-name" "bob")
      (fill-in b "sign-in-password" "another passphrase")
      (press b "Sign in")
      (is (has-text-p b "Signed in as bob")))))

(test password-reset
  (let ((littoral.auth:*send-mail* (lambda (to subject body) (declare (ignore to subject body)))))
    (with-auth (b)
      (setf littoral.auth:*last-mail* nil)
      (click b "Sign in")
      (click b "Forgot your password?")
      ;; Unknown addresses get the same answer, and no mail.
      (fill-in b "reset-email" "nobody@example.org")
      (press b "Send me a link")
      (is (has-text-p b "a link to choose a new password is on its way"))
      (is (null littoral.auth:*last-mail*))
      (press b "Back")
      (click b "Forgot your password?")
      (fill-in b "reset-email" "BOB@example.org")
      (press b "Send me a link")
      (destructuring-bind (to subject body) littoral.auth:*last-mail*
        (is (string= "bob@example.org" to))
        (is (search "new password" subject))
        (let ((link (cl-ppcre:scan-to-strings "/m/reset\\?token=[A-Za-z0-9]+" body)))
          (is (not (null link)))
          ;; Following the link, in another browser.
          (let ((other (make-instance 'browser)))
            (visit other link)
            (is (has-text-p other "Choose a new password"))
            (fill-in other "new-password" "short")
            (fill-in other "new-password-again" "short")
            (press other "Save and sign in")
            (is (has-text-p other "at least 8 characters"))
            (fill-in other "new-password" "a brand new passphrase")
            (fill-in other "new-password-again" "a brand new passphrase")
            (press other "Save and sign in")
            (is (has-text-p other "Signed in as bob")))
          ;; The link works once.
          (let ((again (make-instance 'browser)))
            (visit again link)
            (is (has-text-p again "That link has expired or been used")))
          (is (littoral.auth:check-password (littoral.auth:find-user "bob") "a brand new passphrase"))
          (is (not (littoral.auth:check-password (littoral.auth:find-user "bob") "another passphrase"))))))))

(defun start-oauth (b)
  "Press the FakeID button; the state in the provider URL it redirects to,
and that URL."
  (click b "Sign in")
  (let ((name (cl-ppcre:register-groups-bind (n)
                  ("<button type=\"submit\" name=\"(\\d+)\" value=\"1\">Sign in with FakeID" (browser-html b))
                n)))
    (multiple-value-bind (status headers)
        (raw-request b :post (form-action b) :body (encode-fields (list (cons name "1"))))
      (declare (ignore status))
      (let ((location (getf headers :location)))
        (values (cl-ppcre:register-groups-bind (s) ("[?&]state=([^&]+)" location) s)
                location)))))

(defun fake-provider-post (url parameters)
  (assert (string= url "https://idp.example/token"))
  (assert (string= "the-code" (cdr (assoc "code" parameters :test #'string=))))
  (assert (cdr (assoc "code_verifier" parameters :test #'string=)))
  "{\"access_token\": \"tok\", \"token_type\": \"bearer\"}")

(defun fake-provider-get (url token)
  (assert (string= url "https://idp.example/userinfo"))
  (assert (string= token "tok"))
  "{\"email\": \"carol@example.org\", \"preferred_username\": \"carol\"}")

(test oauth-sign-in
  (let ((littoral.oauth:*http-post* #'fake-provider-post)
        (littoral.oauth:*http-get* #'fake-provider-get))
    (littoral.oauth:define-oauth-provider :fakeid :label "FakeID"
      :authorize-url "https://idp.example/authorize" :token-url "https://idp.example/token"
      :userinfo-url "https://idp.example/userinfo" :client-id "client" :client-secret "secret")
    (unwind-protect
         (with-auth (b)
           (multiple-value-bind (state location) (start-oauth b)
             (is (alexandria:starts-with-subseq "https://idp.example/authorize?" location))
             (is (search "code_challenge_method=S256" location))
             (is (search "redirect_uri=http%3A%2F%2Flocalhost%2Fm%2Foauth%2Ffakeid" location))
             ;; Another browser cannot complete it (and the state is used up).
             (let ((thief (make-instance 'browser)))
               (visit thief (format nil "/m/oauth/fakeid?code=the-code&state=~A" state))
               (is (has-text-p thief "didn't work"))))
           (visit b "/m")
           (let ((state (start-oauth b)))
             ;; The provider sends this browser back.
             (visit b (format nil "/m/oauth/fakeid?code=the-code&state=~A" state))
             (is (has-text-p b "Signed in as carol"))
             (is (littoral.auth:find-user-by-email "carol@example.org"))))
      (setf littoral.oauth::*providers* '()))))

;;; Security review: fixation, reset poisoning, limits, OAuth email

(test signing-in-gives-the-session-a-new-key
  (with-auth (b)
    (let* ((before (browser-url b))
           (old-key (cl-ppcre:register-groups-bind (k) ("_s=([^&]+)" before) k)))
      (sign-in-as b "bob" "another passphrase")
      (is (has-text-p b "Signed in as bob"))
      (is (not (search old-key (browser-url b))))
      ;; Whoever had the old URL (say, from a link they sent) reaches a fresh
      ;; session, not bob's.
      (let ((attacker (make-instance 'browser)))
        (visit attacker before)
        (is (has-text-p attacker "Not signed in")))
      ;; Signing out changes it again.
      (let ((signed-in (browser-url b)))
        (click b "Sign out")
        (is (not (search (cl-ppcre:register-groups-bind (k) ("_s=([^&]+)" signed-in) k)
                         (browser-url b))))))))

(test signing-in-over-ajax-moves-the-page
  (with-auth (b)
    (let ((session (first (list-sessions (find-application "/m")))))
      (let ((*session* session) (littoral::*application* (find-application "/m")))
        (let ((old (session-key session)))
          (littoral.auth:log-in (littoral.auth:find-user "bob"))
          (is (string/= old (session-key session)))
          (is (eq session (littoral::find-session (find-application "/m") (session-key session))))
          (is (null (littoral::find-session (find-application "/m") old))))))))

(test reset-links-use-the-public-url
  (let ((littoral.auth:*send-mail* (lambda (to subject body) (declare (ignore to subject body)))))
    (with-auth (b)
      (setf littoral.auth:*last-mail* nil)
      ;; A forged Host header doesn't reach the link.
      (setf (browser-headers b) '(("host" . "evil.example") ("x-forwarded-host" . "evil.example")))
      (let ((littoral.auth:*public-url* "https://app.example.org/"))
        (click b "Sign in")
        (click b "Forgot your password?")
        (fill-in b "reset-email" "bob@example.org")
        (press b "Send me a link")
        (let ((body (third littoral.auth:*last-mail*)))
          (is (search "https://app.example.org/m/reset?token=" body))
          (is (not (search "evil" body)))))
      ;; Without a public URL, deployment refuses rather than trust the header.
      (let ((littoral.auth:*public-url* nil))
        (signals error (let ((littoral::*application* (find-application "/m")))
                         (littoral.auth:request-base-url (lack/request:make-request (make-env :get "/m")))))))))

(test reset-mails-are-rate-limited
  (let ((sent 0)
        (littoral.auth:*send-mail* (lambda (to subject body) (declare (ignore to subject body)))))
    (with-auth (b)
      (dotimes (i 3)
        (setf littoral.auth:*last-mail* nil)
        (visit b "/m")
        (click b "Sign in")
        (click b "Forgot your password?")
        (fill-in b "reset-email" "bob@example.org")
        (press b "Send me a link")
        ;; The same answer every time.
        (is (has-text-p b "a link to choose a new password is on its way"))
        (when littoral.auth:*last-mail* (incf sent)))
      (is (= 1 sent)))))

(test failures-decay-and-addresses-are-limited
  (let ((littoral.auth:*lockout-failures* 3) (littoral.auth:*failures-per-address* 4)
        (littoral.auth:*lockout-seconds* 60))
    (with-auth (b)
      (let ((*request* (lack/request:make-request (make-env :get "/m"))))
        ;; Old failures don't count.
        (let ((littoral.auth:*failure-window-seconds* 900))
          (dotimes (i 2) (littoral.auth:authenticate "ada" "wrong")))
        (setf (gethash (cons :name "ada") littoral.auth::*events*)
              (mapcar (lambda (time) (- time 1000)) (gethash (cons :name "ada") littoral.auth::*events*)))
        (littoral.auth:authenticate "ada" "wrong")
        (is (littoral.auth:authenticate "ada" "correct horse battery"))
        ;; One address trying many names is stopped, even for names it hasn't tried.
        (dolist (name '("carol" "dave" "erin" "frank"))
          (littoral.auth:authenticate name "password1"))
        (multiple-value-bind (user why) (littoral.auth:authenticate "bob" "another passphrase")
          (is (null user))
          (is (search "Too many" why)))))))

(test unknown-names-take-as-long-as-wrong-passwords
  (with-auth (b)
    (flet ((time-of (name)
             (let ((start (get-internal-real-time)))
               (dotimes (i 3) (littoral.auth:authenticate name "wrong password"))
               (- (get-internal-real-time) start))))
      (clrhash littoral.auth::*failures*)
      (let ((known (time-of "bob")) (unknown (time-of "nobody-at-all")))
        (clrhash littoral.auth::*failures*)
        (is (> unknown (* known 1/3)))))))

(test oauth-refuses-unverified-email
  (let ((littoral.oauth:*http-post* #'fake-provider-post)
        (littoral.oauth:*http-get* (lambda (url token)
                                     (declare (ignore url token))
                                     "{\"email\": \"bob@example.org\", \"email_verified\": false}")))
    (littoral.oauth:define-oauth-provider :fakeid :label "FakeID"
      :authorize-url "https://idp.example/authorize" :token-url "https://idp.example/token"
      :userinfo-url "https://idp.example/userinfo" :client-id "client" :client-secret "secret")
    (unwind-protect
         (with-auth (b)
           (let ((state (start-oauth b)))
             (visit b (format nil "/m/oauth/fakeid?code=the-code&state=~A" state))
             (is (has-text-p b "didn't work"))
             (is (not (has-text-p b "Signed in as bob")))))
      (setf littoral.oauth::*providers* '()))))
