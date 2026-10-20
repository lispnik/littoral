;;;; Examples for littoral.oauth: signing in with an OAuth 2 / OpenID Connect provider.

;;;; Example: littoral.oauth:define-oauth-provider littoral.oauth:find-oauth-provider littoral.oauth:oauth-providers
;;; Define a provider with the addresses it publishes and this application's registration with it.  The sign-in form then offers it.
(littoral.oauth:define-oauth-provider :github
  :label "GitHub"
  :authorize-url "https://github.com/login/oauth/authorize"
  :token-url "https://github.com/login/oauth/access_token"
  :userinfo-url "https://api.github.com/user"
  :client-id "the-client-id" :client-secret "the-client-secret"
  :scopes '("read:user" "user:email"))
;; ⇒ :GITHUB
(defclass oauth-sign-in-page (component) ())
(defmethod render ((self oauth-sign-in-page))
  (render-component (make-instance 'littoral.auth:sign-in)))
(list (length (littoral.oauth:oauth-providers))
      (not (null (littoral.oauth:find-oauth-provider "github")))
      (littoral.oauth:find-oauth-provider :gitlab)
      (let ((littoral.auth:*offer-passkeys* nil))
        (with-fresh-applications (("/sign-in" 'oauth-sign-in-page :mode :deployment))
          (let ((b (make-instance 'browser)))
            (visit b "/sign-in")
            (body-text b)))))
;; ⇒ (1 T NIL "Sign in Name Password Keep me signed in Sign in Cancel Forgot your password? Sign in with GitHub")

;;;; Example: littoral.oauth:*http-post* littoral.oauth:*http-get* littoral.oauth:define-oauth-provider
;;; The whole flow, with the provider played by two functions: the button sends the browser to the provider, which sends it back to /oauth/NAME with a code.  The code buys a token, the token the user's details, and the user is found by email, or made, and signed in.
(defclass oauth-club (littoral.auth:auth-root component) ())
(defmethod render ((self oauth-club))
  (let ((user (littoral.auth:current-user)))
    (if user
        (h:p () (h:text (format nil "Hello, ~A." (littoral.auth:user-name user))))
        (h:anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in)))) "Sign in"))))
(littoral.oauth:define-oauth-provider :fakeid
  :label "FakeID"
  :authorize-url "https://id.example/authorize"
  :token-url "https://id.example/token"
  :userinfo-url "https://id.example/userinfo"
  :client-id "club" :client-secret "secret")
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*public-url* "https://club.example")
      (littoral.oauth:*http-post*
        (lambda (url parameters)
          (assert (string= url "https://id.example/token"))
          (assert (string= "the-code" (cdr (assoc "code" parameters :test #'string=))))
          "{\"access_token\": \"a-token\", \"token_type\": \"bearer\"}"))
      (littoral.oauth:*http-get*
        (lambda (url token)
          (assert (and (string= url "https://id.example/userinfo") (string= token "a-token")))
          "{\"email\": \"carol@example.org\", \"preferred_username\": \"carol\"}")))
  (littoral.auth:create-auth-tables)
  (with-fresh-applications (("/club" 'oauth-club :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/club")
      (click b "Sign in")
      (press b "Sign in with FakeID")
      (let* ((provider-url (browser-url b))
             (state (cl-ppcre:register-groups-bind (s) ("[?&]state=([^&]+)" provider-url) s)))
        (visit b (format nil "/club/oauth/fakeid?code=the-code&state=~A" state))
        (list (subseq provider-url 0 (position #\? provider-url))
              (not (null (search "redirect_uri=https%3A%2F%2Fclub.example%2Fclub%2Foauth%2Ffakeid" provider-url)))
              (body-text b)
              (littoral.auth:user-name (littoral.auth:find-user-by-email "carol@example.org")))))))
;; ⇒ ("https://id.example/authorize" T "Hello, carol." "carol")
