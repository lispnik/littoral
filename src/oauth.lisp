;;;; oauth.lisp — sign in with an OAuth 2 / OpenID Connect provider
;;;;
;;;;   (define-oauth-provider :github
;;;;     :label "GitHub"
;;;;     :authorize-url "https://github.com/login/oauth/authorize"
;;;;     :token-url "https://github.com/login/oauth/access_token"
;;;;     :userinfo-url "https://api.github.com/user"
;;;;     :client-id "…" :client-secret "…" :scopes '("read:user" "user:email"))
;;;;
;;;; The sign-in form then offers "Sign in with GitHub".  The flow is the
;;;; authorization code flow with PKCE: the server remembers a random state,
;;;; tied to the browser's cookie, and a code verifier; the provider sends
;;;; the browser back to /oauth/github on the application (register that
;;;; address with the provider), where the code is exchanged for a token,
;;;; the user's details fetched, and the user found by email, or created,
;;;; and signed in.  The application's root must be an AUTH-ROOT.

(defpackage #:littoral.oauth
  (:use #:cl #:littoral #:littoral.html #:littoral.db #:littoral.auth)
  (:documentation "Sign in with OAuth 2 / OpenID Connect providers.")
  (:export #:define-oauth-provider #:find-oauth-provider #:oauth-providers
           #:*http-post* #:*http-get*))

(in-package #:littoral.oauth)

(defstruct (provider (:constructor make-provider))
  "An identity provider and this application's registration with it."
  name label authorize-url token-url userinfo-url client-id client-secret
  (scopes '("openid" "email" "profile")))

(defvar *providers* '() "Defined providers, in order.")

(defun define-oauth-provider (name &key (label (string-capitalize name)) authorize-url token-url
                                     userinfo-url client-id client-secret
                                     (scopes '("openid" "email" "profile")))
  "Offer signing in with the provider NAME (a keyword).  Redefining replaces it."
  (setf *providers* (append (remove name *providers* :key #'provider-name)
                            (list (make-provider :name name :label label :authorize-url authorize-url
                                                 :token-url token-url :userinfo-url userinfo-url
                                                 :client-id client-id :client-secret client-secret
                                                 :scopes scopes))))
  name)

(defun oauth-providers () *providers*)

(defun find-oauth-provider (name)
  (find name *providers* :key #'provider-name :test #'string-equal))

;;; HTTP, replaceable for tests

(defvar *http-post*
  (lambda (url parameters)
    (dex:post url :content parameters :headers '(("Accept" . "application/json"))))
  "A function of (URL PARAMETERS) posting a form and returning the body.")

(defvar *http-get*
  (lambda (url token)
    (dex:get url :headers `(("Authorization" . ,(format nil "Bearer ~A" token))
                            ("Accept" . "application/json"))))
  "A function of (URL ACCESS-TOKEN) returning the body.")

;;; Pending sign-ins

(defvar *pending* (make-hash-table :test 'equal)
  "State → (PROVIDER-NAME VERIFIER BROWSER-KEY EXPIRES).")

(defvar *pending-lock* (sb-thread:make-mutex :name "littoral oauth"))

(defun base64url (octets)
  (string-right-trim "=" (substitute #\_ #\/ (substitute #\- #\+ (cl-base64:usb8-array-to-base64-string octets)))))

(defun code-challenge (verifier)
  "The PKCE S256 challenge for VERIFIER."
  (base64url (ironclad:digest-sequence :sha256 (sb-ext:string-to-octets verifier :external-format :ascii))))

(defun redirect-uri (provider)
  "Where the provider sends the browser back to."
  (format nil "~A~A/oauth/~(~A~)" (request-base-url) (url-for (application-path *application*))
          (provider-name provider)))

(defun browser-key ()
  (littoral::request-cookie (littoral::browser-cookie-name *application*)))

(defun start-sign-in (provider)
  "From a callback: send the browser to PROVIDER to sign in."
  (let ((state (littoral::random-key 32))
        (verifier (littoral::random-key 64)))
    (sb-thread:with-mutex (*pending-lock*)
      ;; Forget the stale ones while here.
      (let ((now (get-universal-time)))
        (loop for key being the hash-keys of *pending* using (hash-value entry)
              when (< (fourth entry) now) do (remhash key *pending*)))
      (setf (gethash state *pending*)
            (list (provider-name provider) verifier (browser-key) (+ (get-universal-time) 600))))
    (redirect-to
     (littoral::url-with-params (provider-authorize-url provider)
                                (list (cons "response_type" "code")
                                      (cons "client_id" (provider-client-id provider))
                                      (cons "redirect_uri" (redirect-uri provider))
                                      (cons "scope" (format nil "~{~A~^ ~}" (provider-scopes provider)))
                                      (cons "state" state)
                                      (cons "code_challenge" (code-challenge verifier))
                                      (cons "code_challenge_method" "S256"))))))

(defun take-pending (state provider)
  "The verifier for STATE if it was issued for PROVIDER to this browser and
has not expired; it can be used once."
  (sb-thread:with-mutex (*pending-lock*)
    (let ((entry (gethash state *pending*)))
      (remhash state *pending*)
      (and entry
           (string-equal (first entry) (provider-name provider))
           (third entry) (equal (third entry) (browser-key))
           (> (fourth entry) (get-universal-time))
           (second entry)))))

(defun json-field (json &rest keys)
  "The first of KEYS present in the JSON object JSON (a string)."
  (let ((object (com.inuoe.jzon:parse json)))
    (loop for key in keys
          for value = (and (hash-table-p object) (gethash key object))
          when (and value (not (eq value 'null))) return value)))

(defun finish-sign-in (provider code verifier)
  "Exchange CODE for a token, fetch the user's details, and sign them in."
  (let* ((token (json-field (funcall *http-post* (provider-token-url provider)
                                     (list (cons "grant_type" "authorization_code")
                                           (cons "code" code)
                                           (cons "redirect_uri" (redirect-uri provider))
                                           (cons "client_id" (provider-client-id provider))
                                           (cons "client_secret" (provider-client-secret provider))
                                           (cons "code_verifier" verifier)))
                            "access_token"))
         (info (and token (funcall *http-get* (provider-userinfo-url provider) token)))
         (email (and info (json-field info "email")))
         (name (and info (json-field info "preferred_username" "login" "name"))))
    (when email
      (let ((user (or (find-user-by-email email)
                      (add-user (available-name (or name (subseq email 0 (position #\@ email))))
                                email nil))))
        (when (user-active-p user)
          (log-in user))))))

(defun available-name (wanted)
  "WANTED, made a valid user name not yet taken."
  (let ((base (or (cl-ppcre:regex-replace-all "[^A-Za-z0-9_.-]" wanted "") "")))
    (when (string= base "") (setf base "user"))
    (loop for n from 1
          for candidate = base then (format nil "~A~D" base n)
          unless (find-user candidate) return candidate)))

(define-auth-path "oauth" (root rest request)
  (let* ((provider (find-oauth-provider (first rest)))
         (code (request-parameter "code" request))
         (verifier (and provider (take-pending (request-parameter "state" request) provider))))
    (unless (and provider code verifier
                 (ignore-errors (finish-sign-in provider code verifier)))
      (show root (make-instance 'message-dialog
                                :message (translate "Signing in with that provider didn't work. Please try again."))))))

;;; Buttons on the sign-in form

(push (lambda (sign-in)
        (declare (ignore sign-in))
        (when *providers*
          (div (:class "lt-oauth")
            (dolist (provider *providers*)
              (let ((provider provider))
                (form ()
                  (submit-button (:callback (lambda () (start-sign-in provider)))
                    (text (translate "Sign in with ~A" (provider-label provider))))))))))
      *sign-in-extras*)
