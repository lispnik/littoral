;;;; members-demo.lisp — signing in, roles, password reset and OAuth
;;;;
;;;; (asdf:load-system :littoral/members-demo) (littoral-members-demo:register)
;;;; serves /examples/members, its users in SQLite in the temp directory.
;;;;
;;;; The page has a part anyone sees, a part for signed-in members (a
;;;; RESTRICTED component) and a part for admins (a RESTRICTED component
;;;; with a REQUIRED-ROLE).  Mail that password reset would send lands in
;;;; a demo mailbox on the page.  "Sign in with DemoID" runs the whole
;;;; OAuth 2 authorisation code flow, with PKCE, against a pretend identity
;;;; provider served at /examples/demo-idp, so it works with no accounts
;;;; anywhere.  Sign-ins are kept in the database: they survive a restart,
;;;; "Keep me signed in" makes them last a month, and "Your sessions" lists
;;;; and ends them.  Editors (a role an admin grants) may edit posts (a
;;;; permission).  /examples/accounts is the same page signing in against
;;;; an existing "accounts" table with bcrypt hashes, through
;;;; MAKE-SQL-USER-STORE.  Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET to offer
;;;; signing in with Google too (register .../examples/members/oauth/google
;;;; as the redirect URI with Google).

(defpackage #:littoral-members-demo
  (:use #:cl #:littoral #:littoral.html)
  (:documentation "Users, roles, password reset and OAuth sign-in.")
  (:export #:register #:members-root #:demo-idp #:*outbox*))

(in-package #:littoral-members-demo)

;;; The demo mailbox: where reset mail goes instead of out

(defvar *outbox* '() "Mail the demo would have sent, newest first: (TO SUBJECT BODY).")
(defvar *outbox-lock* (sb-thread:make-mutex :name "members demo outbox"))

(defun deliver-mail (to subject body)
  "A *SEND-MAIL* that keeps the last few mails for the page to show."
  (sb-thread:with-mutex (*outbox-lock*)
    (setf *outbox* (subseq (cons (list to subject body) *outbox*) 0 (min 5 (1+ (length *outbox*)))))))

(defun outbox ()
  (sb-thread:with-mutex (*outbox-lock*) (copy-list *outbox*)))

(defun render-mailbox ()
  (section (:class "members-mailbox")
    (h2 () "Demo mailbox")
    (if (null (outbox))
        (p () "Empty. Mail sent by password reset would arrive here.")
        (dolist (mail (outbox))
          (destructuring-bind (to subject body) mail
            (article (:class "members-mail")
              (p () (strong () "To: ") (text to) (br) (strong () "Subject: ") (text subject))
              (pre () (text body))
              (let ((link (cl-ppcre:scan-to-strings "https?://\\S+/reset\\?token=\\S+" body)))
                (when link (p () (anchor (:href link) "Open the reset link"))))))))))

;;; The page

(defclass account-box (component) ()
  (:documentation "Who is signed in, with a link to sign in or out.  The sign-in
form shows in its place, so the rest of the page stays in view."))

(defmethod render ((self account-box))
  (let ((user (littoral.auth:current-user)))
    (p (:class "members-account")
      (if user
          (progn (text "Signed in as ") (strong () (text (littoral.auth:user-name user)))
                 (when (littoral.auth:has-role-p :admin user) (text " (admin)"))
                 (text " · ")
                 (littoral.auth:sign-out-link))
          (progn (text "Not signed in. ")
                 (anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in))))
                   "Sign in"))))))

(defclass members-news (littoral.auth:restricted component) ()
  (:documentation "For anyone signed in."))

(defmethod render ((self members-news))
  (p () "Welcome back. This is a restricted component: until someone signs in, a prompt shows in its place.")
  (p () (anchor (:callback (lambda ()
                             ;; Refuses with 403 unless the user is an admin.
                             (littoral.auth:require-role :admin)
                             (toast "Only admins may do that, and you are one." :kind :success)))
          "Do something only admins may do"))
  (p () (anchor (:callback (lambda ()
                             ;; A permission, which editors and admins have.
                             (littoral.auth:require-permission :edit-posts)
                             (toast "You may edit posts." :kind :success)))
          "Edit a post (needs the edit-posts permission)")))

(defclass sessions-box (littoral.auth:restricted component)
  ((token :initform nil :accessor new-token :documentation "An API token just made, shown once."))
  (:documentation "The signed-in user's sign-ins, with ways to end them, and API tokens."))

(defun describe-agent (agent)
  (cond ((null agent) "an unknown browser")
        ((search "Firefox" agent) "Firefox")
        ((search "Edg/" agent) "Edge")
        ((search "Chrome" agent) "Chrome")
        ((search "Safari" agent) "Safari")
        (t (subseq agent 0 (min 40 (length agent))))))

(defun minutes-ago (time)
  (let ((minutes (floor (- (get-universal-time) time) 60)))
    (if (< minutes 1) "just now" (format nil "~D minute~:P ago" minutes))))

(defmethod render ((self sessions-box))
  (let ((user (littoral.auth:current-user)))
    (ul (:class "members-sessions")
      (dolist (session (littoral.auth:user-sessions user))
        (let ((id (getf session :id)))
          (li ()
            (text (format nil "~A, signed in ~A~:[~;, kept for a month~]"
                          (describe-agent (getf session :user-agent))
                          (minutes-ago (getf session :created)) (getf session :remember)))
            (if (getf session :current)
                (strong () " (this browser)")
                (progn (text " · ")
                       (anchor (:callback (lambda () (littoral.auth:revoke-session id)
                                            (toast "That sign-in has ended.")))
                         "End")))))))
    (p () (anchor (:callback (lambda () (littoral.auth:log-out-everywhere))) "Sign out everywhere"))
    (h3 () "API")
    (p () "This application also answers JSON: " (code () "GET /api/me") " tells a script who it is, "
      "with a bearer token or this browser's sign-in.")
    (if (new-token self)
        (let ((curl (format nil "curl -H 'Authorization: Bearer ~A' ~A~A/api/me"
                            (new-token self) (littoral.auth:request-base-url)
                            (url-for (application-path *application*)))))
          (p () "Your new token, shown only now:")
          (pre (:class "members-token") (text curl))
          (p () (anchor (:callback (lambda () (setf (new-token self) nil))) "Done")))
        (p () (anchor (:callback (lambda () (setf (new-token self) (littoral.auth:create-api-token user :days 30))))
                "Create an API token")))))

(defclass admin-console (littoral.auth:restricted component)
  ((users :initarg :users :initform (lambda () (littoral.db:db-select 'littoral.auth:user :order-by "name"))
          :reader console-users
          :documentation "A function returning the users to list."))
  (:documentation "For admins: the users, their roles, and switching them on and off."))

(defun toggle-editor (user)
  (if (member :editor (littoral.auth:user-roles user))
      (littoral.auth:revoke-role user :editor)
      (littoral.auth:grant-role user :editor))
  (toast (format nil "~A is ~:[no longer~;now~] an editor." (littoral.auth:user-name user)
                 (member :editor (littoral.auth:user-roles user)))))

(defmethod littoral.auth:required-role ((self admin-console)) :admin)

(defun toggle-active (user)
  (unless (eql (littoral.auth:user-id user) (littoral.auth:user-id (littoral.auth:current-user)))
    (setf (littoral.auth:user-active-p user) (not (littoral.auth:user-active-p user)))
    (littoral.db:db-save user)
    (toast (format nil "~A is now ~:[inactive~;active~]." (littoral.auth:user-name user)
                   (littoral.auth:user-active-p user)))))

(defmethod render ((self admin-console))
  (table (:class "lt-table")
    (thead () (tr () (th () "Name") (th () "Email") (th () "Roles") (th () "Active") (th () "")))
    (tbody ()
      (dolist (user (funcall (console-users self)))
        (let ((user user))
          (tr ()
            (td () (text (littoral.auth:user-name user)))
            (td () (text (littoral.auth:user-email user)))
            (td () (text (format nil "~{~(~A~)~^, ~}" (littoral.auth:user-roles user))))
            (td () (text (if (littoral.auth:user-active-p user) "yes" "no")))
            (td () (unless (eql (littoral.auth:user-id user)
                                (littoral.auth:user-id (littoral.auth:current-user)))
                     (anchor (:callback (lambda () (toggle-editor user)))
                       (text (if (member :editor (littoral.auth:user-roles user)) "Remove editor" "Make editor")))
                     ;; Only the built-in table is written here; an existing
                     ;; table's own tools switch its users on and off.
                     (when (typep user 'littoral.auth:user)
                       (text " · ")
                       (anchor (:callback (lambda () (toggle-active user)))
                         (text (if (littoral.auth:user-active-p user) "Deactivate" "Activate"))))))))))))

(defclass members-root (littoral.auth:auth-root component)
  ((account :initform (make-instance 'account-box) :reader root-account)
   (news :initform (make-instance 'members-news) :reader root-news)
   (sessions :initform (make-instance 'sessions-box) :reader root-sessions)
   (security :initform (make-instance 'littoral.auth:security-settings) :reader root-security)
   (console :initform (make-instance 'admin-console) :accessor root-console))
  (:documentation "The members demo: a public part, a members' part, an admins' part."))

(defmethod children ((self members-root))
  (list (root-account self) (root-news self) (root-sessions self) (root-security self) (root-console self)))

(defgeneric render-try-it (root)
  (:documentation "The demo accounts to try, and what to try."))

(defmethod render-try-it ((self members-root))
  (ul ()
    (li () (strong () "ada") ", password " (code () "correct horse battery") ": an admin.")
    (li () (strong () "bob") ", password " (code () "another passphrase") ": a member. Ada can make him an editor.")
    (li () "Tick \"Keep me signed in\" and the sign-in lasts a month, even across server restarts; without it, until the browser closes.")
    (li () "Sign in from two browsers and \"Your sessions\" lists both; end one from the other.")
    (li () "Under Security, add an authenticator app (signing in then asks for its code), passkeys "
      "(sign in with your fingerprint or face, no password) and recovery codes.")
    (li () "Five wrong passwords for a name lock it for a minute.")
    (li () "Forgot a password? Ask for a link for bob@example.org; it arrives in the demo mailbox below.")
    (li () "Or sign in with DemoID, a pretend OAuth provider, as carol. Her account is created on first sign-in.")))

(defgeneric page-heading (root)
  (:method ((root members-root)) "Members"))

(defmethod render ((self members-root))
  (h1 () (text (page-heading self)))
  (render-component (root-account self))
  (section (:class "members-try")
    (h2 () "Try it")
    (render-try-it self))
  (section ()
    (h2 () "Everyone")
    (p () "Anyone can see this part of the page."))
  (section ()
    (h2 () "Members")
    (render-component (root-news self)))
  (section ()
    (h2 () "Your sessions")
    (render-component (root-sessions self)))
  (section ()
    (h2 () "Security")
    (render-component (root-security self)))
  (section ()
    (h2 () "Admins")
    (render-component (root-console self)))
  (render-mailbox))

;;; The same page over an existing table

(defclass accounts-root (members-root) ()
  (:documentation "The members page, signing in against the accounts table."))

(defmethod initialize-instance :after ((self accounts-root) &key)
  (setf (root-console self)
        (make-instance 'admin-console
                       :users (lambda ()
                                (mapcar (lambda (row) (littoral.auth:find-user-by-id (getf row :|account_id|)))
                                        (littoral.db:db-query "SELECT account_id FROM accounts ORDER BY login"))))))

(defmethod page-heading ((self accounts-root)) "Accounts (an existing table)")

(defmethod render-try-it ((self accounts-root))
  (p () "Here users come from an " (code () "accounts") " table this demo pretends it already had, "
    "with its own column names and bcrypt hashes, read through "
    (code () "make-sql-user-store") ".")
  (ul ()
    (li () (strong () "dora") ", password " (code () "dora's password") ": an admin, by the table's own roles column.")
    (li () (strong () "eve") ", password " (code () "correct horse battery") ": her hash is Werkzeug's PBKDF2.")
    (li () "Signing in upgrades a bcrypt or Werkzeug hash to Littoral's own; the table is writable.")
    (li () "DemoID can't sign in here: this store doesn't create users.")))

(defun accounts-store ()
  (littoral.auth:make-sql-user-store
   :table "accounts" :id "account_id" :name "login" :email "email_address"
   :password "pw_hash" :active "enabled" :roles-column "roles" :writable t))

(defun seed-accounts ()
  (littoral.db:db-execute "CREATE TABLE IF NOT EXISTS accounts (account_id INTEGER PRIMARY KEY, login TEXT,
                           email_address TEXT, pw_hash TEXT, enabled INTEGER, roles TEXT)")
  (when (null (littoral.db:db-query "SELECT account_id FROM accounts"))
    (littoral.db:db-execute "INSERT INTO accounts (login, email_address, pw_hash, enabled, roles) VALUES (?, ?, ?, 1, 'admin')"
                            "dora" "dora@example.org" (littoral.auth:bcrypt-hash "dora's password" :cost 10))
    (littoral.db:db-execute "INSERT INTO accounts (login, email_address, pw_hash, enabled, roles) VALUES (?, ?, ?, 1, '')"
                            "eve" "eve@example.org"
                            "pbkdf2:sha256:1000$seasalt1234$7550ac791a251d65e7ddd282ac996a427107369b72fe00b683aa5462d0864ffe")))

(defmethod style ((self members-root))
  ".members-mail { border: 1px solid var(--lt-border); border-radius: 6px; padding: .2rem .8rem; margin: .5rem 0; }
.members-mail pre { white-space: pre-wrap; font-size: .85rem; }
.members-token { white-space: pre-wrap; word-break: break-all; font-size: .8rem; background: var(--lt-panel); padding: .5rem; border-radius: 6px; }
.lt-oauth form { display: inline-block; margin: .5rem .5rem 0 0; }
.lt-remember { display: flex; gap: .4rem; align-items: center; }
.lt-remember label { margin: 0; }")

;;; DemoID: a pretend OAuth 2 identity provider
;;;
;;; Its authorisation page is a Littoral application.  Its token and user
;;; details endpoints are answered in-process: littoral.oauth fetches them
;;; through *HTTP-POST* and *HTTP-GET*, which REGISTER wraps to catch the
;;; demoid: addresses and pass every other address on.

(defvar *codes* (make-hash-table :test 'equal) "Code → (CHALLENGE REDIRECT-URI EMAIL NAME EXPIRES).")
(defvar *tokens* (make-hash-table :test 'equal) "Access token → (EMAIL NAME).")
(defvar *idp-lock* (sb-thread:make-mutex :name "demo identity provider"))

(defparameter *demo-client-id* "members-demo")
(defparameter *demo-client-secret* "not-so-secret")

(defclass demo-idp (component)
  ((redirect-uri :initform nil :accessor idp-redirect-uri)
   (state :initform nil :accessor idp-state)
   (challenge :initform nil :accessor idp-challenge)
   (client-id :initform nil :accessor idp-client-id))
  (:documentation "DemoID's sign-in page: asks whether to tell the members demo who you are."))

(defmethod initial-request ((self demo-idp) request)
  (setf (idp-redirect-uri self) (request-parameter "redirect_uri" request)
        (idp-state self) (request-parameter "state" request)
        (idp-challenge self) (request-parameter "code_challenge" request)
        (idp-client-id self) (request-parameter "client_id" request)))

(defun valid-request-p (self)
  "True when the request came from the members demo, with a PKCE challenge,
and asks to go back to the members demo's own OAuth address."
  (and (equal (idp-client-id self) *demo-client-id*)
       (idp-state self) (idp-challenge self) (idp-redirect-uri self)
       (cl-ppcre:scan "^https?://[^/]+/.*/oauth/demoid$" (idp-redirect-uri self))))

(defun back-to-client (self &rest parameters)
  (redirect-to (format nil "~A?~{~A=~A~^&~}" (idp-redirect-uri self)
                       (loop for (key value) on (append parameters (list "state" (idp-state self))) by #'cddr
                             collect key collect (quri:url-encode value)))))

(defun approve (self email name)
  "Issue a code for EMAIL, good once, for a minute, and send the browser back."
  (let ((code (littoral::random-key 24)))
    (sb-thread:with-mutex (*idp-lock*)
      (setf (gethash code *codes*)
            (list (idp-challenge self) (idp-redirect-uri self) email name (+ (get-universal-time) 60))))
    (back-to-client self "code" code)))

(defmethod render ((self demo-idp))
  (div (:class "lt-dialog")
    (h1 () "DemoID")
    (if (valid-request-p self)
        (progn
          (p () "The members demo would like to know who you are. Continue as:")
          (form ()
            (submit-button (:callback (lambda () (approve self "carol@example.org" "carol")))
              "carol@example.org")
            (cancel-button (:callback (lambda () (back-to-client self "error" "access_denied")))
              "Deny")))
        (p () "This sign-in request didn't come from the members demo."))
    (p (:class "lt-help") "A pretend identity provider, for the demo. A real one would ask you to sign in first.")))

(defun demo-token (parameters)
  "The token endpoint: exchange a code, checking its PKCE verifier."
  (flet ((param (name) (cdr (assoc name parameters :test #'string=))))
    (let ((entry (sb-thread:with-mutex (*idp-lock*)
                   (prog1 (gethash (param "code") *codes*)
                     (remhash (param "code") *codes*)))))
      (if (and entry
               (equal (param "client_id") *demo-client-id*)
               (equal (param "client_secret") *demo-client-secret*)
               (equal (param "redirect_uri") (second entry))
               (> (fifth entry) (get-universal-time))
               (param "code_verifier")
               (string= (littoral.oauth::code-challenge (param "code_verifier")) (first entry)))
          (let ((token (littoral::random-key 32)))
            (sb-thread:with-mutex (*idp-lock*)
              (setf (gethash token *tokens*) (list (third entry) (fourth entry))))
            (format nil "{\"access_token\":\"~A\",\"token_type\":\"bearer\"}" token))
          "{\"error\":\"invalid_grant\"}"))))

(defun demo-userinfo (token)
  "The user details endpoint."
  (let ((entry (sb-thread:with-mutex (*idp-lock*) (gethash token *tokens*))))
    (if entry
        (format nil "{\"email\":\"~A\",\"email_verified\":true,\"preferred_username\":\"~A\"}"
                (first entry) (second entry))
        "{\"error\":\"invalid_token\"}")))

(defvar *next-http-post* nil "The *HTTP-POST* that non-DemoID requests go to.")
(defvar *next-http-get* nil "The *HTTP-GET* that non-DemoID requests go to.")

(defun install-demo-endpoints ()
  "Have littoral.oauth's HTTP hooks answer the demoid: addresses in-process."
  (unless *next-http-post*
    (setf *next-http-post* littoral.oauth:*http-post*
          *next-http-get* littoral.oauth:*http-get*
          littoral.oauth:*http-post* (lambda (url parameters)
                                       (if (string= url "demoid:token")
                                           (demo-token parameters)
                                           (funcall *next-http-post* url parameters)))
          littoral.oauth:*http-get* (lambda (url token)
                                      (if (string= url "demoid:userinfo")
                                          (demo-userinfo token)
                                          (funcall *next-http-get* url token))))))

;;; Serving

(defun seed ()
  (littoral.auth:create-auth-tables)
  (unless (littoral.auth:find-user "ada")
    (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin)))
  (unless (littoral.auth:find-user "bob")
    (littoral.auth:add-user "bob" "bob@example.org" "another passphrase"))
  (littoral.auth:grant-permission :admin :edit-posts)
  (littoral.auth:grant-permission :editor :edit-posts)
  (seed-accounts))

(defun register (&key (path "/examples/members") (idp-path "/examples/demo-idp")
                   (accounts-path "/examples/accounts")
                   (file (merge-pathnames "littoral-members-demo.sqlite3" (uiop:temporary-directory))))
  "Serve the members demo at PATH and DemoID at IDP-PATH, keeping users in FILE."
  (let ((database (littoral.db:using-database :sqlite3 :database-name (namestring file))))
    (funcall database #'seed)
    (install-demo-endpoints)
    (littoral.oauth:define-oauth-provider :demoid
      :label "DemoID"
      :authorize-url (url-for idp-path)
      :token-url "demoid:token" :userinfo-url "demoid:userinfo"
      :client-id *demo-client-id* :client-secret *demo-client-secret*)
    (let ((id (uiop:getenv "GOOGLE_CLIENT_ID")) (secret (uiop:getenv "GOOGLE_CLIENT_SECRET")))
      (when (and id secret (plusp (length id)))
        (littoral.oauth:define-oauth-provider :google
          :label "Google"
          :authorize-url "https://accounts.google.com/o/oauth2/v2/auth"
          :token-url "https://oauth2.googleapis.com/token"
          :userinfo-url "https://openidconnect.googleapis.com/v1/userinfo"
          :client-id id :client-secret secret)))
    (register-application idp-path 'demo-idp :title "DemoID")
    ;; JSON beside the pages: who is asking, by bearer token or sign-in cookie.
    (register-endpoint path :get "/api/me"
                       (lambda ()
                         (let ((user (littoral.auth:require-endpoint-user)))
                           (list :name (littoral.auth:user-name user)
                                 :email (littoral.auth:user-email user)
                                 :roles (coerce (mapcar #'string-downcase (littoral.auth:user-roles user)) 'vector)))))
    (register-application path 'members-root
                          :title "Members"
                          ;; Each request: this demo's database, and mail to the demo mailbox.
                          :around-request (lambda (thunk)
                                            (let ((littoral.auth:*send-mail* #'deliver-mail))
                                              (funcall database thunk)))
                          :around-actions (littoral.db:transactional))
    (register-application accounts-path 'accounts-root
                          :title "Accounts"
                          :around-request (littoral.auth:using-user-store
                                           (accounts-store)
                                           (lambda (thunk)
                                             (let ((littoral.auth:*send-mail* #'deliver-mail))
                                               (funcall database thunk))))
                          :around-actions (littoral.db:transactional))))
