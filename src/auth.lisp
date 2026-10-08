;;;; auth.lisp — users, signing in, roles, password reset
;;;;
;;;;   (littoral.db:connect-database :sqlite3 :database-name "app.db")
;;;;   (create-auth-tables)
;;;;   (add-user "ada" "ada@example.org" "a long passphrase" :roles '(:admin))
;;;;
;;;;   (defclass app (auth-root component) ())        ; handles /reset links
;;;;   (defclass reports (restricted component) ())   ; signed-in users only
;;;;   (defmethod required-role ((self reports)) :admin)
;;;;
;;;; A RESTRICTED component shows a sign-in prompt, or a refusal, in its
;;;; place until the current user may see it.  Callbacks check with
;;;; REQUIRE-ROLE, which refuses with a 403.  Signing in locks a name for a
;;;; while after repeated failures.  Password reset sends a single-use,
;;;; expiring link through *SEND-MAIL*.
;;;;
;;;; Users come from *USER-STORE*: by default the users table here, or an
;;;; application's own table through SQL-USER-STORE (auth-store.lisp), or any
;;;; class with methods for the STORE- generic functions.  A user is any
;;;; object with methods for USER-ID, USER-NAME, USER-EMAIL, USER-ACTIVE-P,
;;;; USER-PASSWORD-HASH and USER-ROLES.  Passwords: passwords.lisp.

(defpackage #:littoral.auth
  (:use #:cl #:littoral #:littoral.html #:littoral.db)
  (:documentation "Users, signing in, roles and password reset for Littoral.")
  (:export #:user #:user-id #:user-name #:user-email #:user-roles #:user-active-p #:user-password-hash
           #:user-store #:users-table-store #:*user-store* #:using-user-store
           #:store-find-user #:store-find-user-by-email #:store-find-user-by-id
           #:store-set-password-hash #:store-create-user #:store-writable-p #:store-verify-password
           #:sql-user-store #:make-sql-user-store #:sql-user
           #:hash-password #:verify-password #:password-needs-rehash-p #:bcrypt-hash
           #:*pbkdf2-iterations* #:*rehash-on-sign-in*
           #:create-auth-tables #:drop-auth-tables #:add-user #:find-user #:find-user-by-email #:find-user-by-id
           #:set-password #:check-password #:authenticate
           #:current-user #:log-in #:log-out #:signed-in-p #:has-role-p #:require-role
           #:grant-role #:revoke-role #:grant-permission #:revoke-permission
           #:role-permissions #:user-permissions #:has-permission-p #:require-permission
           #:restricted #:required-role #:required-permission #:permitted-p
           #:sign-in #:sign-out-link #:password-reset-request #:password-reset
           #:auth-root #:define-auth-path #:request-base-url
           #:*send-mail* #:*last-mail* #:*lockout-failures* #:*lockout-seconds*
           #:*failure-window-seconds* #:*failures-per-address* #:*reset-mails-per-address*
           #:*public-url* #:*reset-link-seconds* #:*sign-in-extras*))

(in-package #:littoral.auth)

;;; What a user is: generic functions, so an application's own class can be one

(defgeneric user-id (user)
  (:documentation "USER's key in its store, kept in the session while they are signed in.")
  (:method ((user persistent)) (object-id user)))

(defgeneric user-name (user)
  (:documentation "The name USER signs in with."))

(defgeneric user-email (user)
  (:documentation "USER's email address, or NIL.")
  (:method (user) (declare (ignore user)) nil))

(defgeneric user-active-p (user)
  (:documentation "True when USER may sign in.")
  (:method (user) (declare (ignore user)) t))

(defgeneric user-password-hash (user)
  (:documentation "USER's stored password hash, or NIL when they have none.")
  (:method (user) (declare (ignore user)) nil))

(defgeneric user-roles (user)
  (:documentation "USER's roles, as keywords.")
  (:method (user) (declare (ignore user)) '()))

;;; Where users come from

(defclass user-store () ()
  (:documentation "Where users are found.  Specialise the STORE- generic functions."))

(defgeneric store-find-user (store name)
  (:documentation "The user STORE knows by NAME, or NIL."))

(defgeneric store-find-user-by-email (store email)
  (:documentation "The user STORE knows by EMAIL, or NIL.")
  (:method ((store user-store) email) (declare (ignore email)) nil))

(defgeneric store-find-user-by-id (store id)
  (:documentation "The user whose USER-ID is ID, or its printed form; NIL if none."))

(defgeneric store-writable-p (store)
  (:documentation "True when STORE-SET-PASSWORD-HASH works.")
  (:method ((store user-store)) nil))

(defgeneric store-set-password-hash (store user hash)
  (:documentation "Keep HASH as USER's password hash.")
  (:method ((store user-store) user hash)
    (declare (ignore user hash))
    (error "This user store can't change passwords.")))

(defgeneric store-create-user (store &key name email password-hash roles)
  (:documentation "A new user in STORE, or NIL when STORE doesn't create users
(OAuth then signs in only users it already has).")
  (:method ((store user-store) &key name email password-hash roles)
    (declare (ignore name email password-hash roles))
    nil))

(defgeneric store-verify-password (store password hash)
  (:documentation "True when PASSWORD matches HASH as STORE keeps them.")
  (:method ((store user-store) password hash) (verify-password password hash)))

;;; The built-in users table

(defclass user (persistent)
  ((name :initarg :name :initform nil :accessor user-name)
   (email :initarg :email :initform nil :accessor user-email)
   (roles :initarg :roles :initform "" :accessor user-roles-text
          :documentation "Roles as earlier versions kept them, comma-separated;
CREATE-AUTH-TABLES moves them to the user_roles table.")
   (active :initarg :active :initform t :accessor user-active-p)
   (password-hash :initarg :password-hash :initform nil :accessor user-password-hash))
  (:documentation "Someone who can sign in, in the built-in users table."))

(define-description user
  ((name :required t :max-length 40 :pattern "[A-Za-z0-9_.-]+"
         :pattern-message "Names are letters, digits, dots, dashes and underscores.")
   (email :type :email :required t)
   (roles :hidden t)
   (active :type :boolean)
   (password-hash :type :password :read-only t :label "Password")))

(define-table user :name "users")

(defmethod user-roles ((user user))
  (granted-roles user))

(defclass users-table-store (user-store) ()
  (:documentation "The built-in users table, through littoral/db."))

(defmethod store-find-user ((store users-table-store) name)
  (first (db-select 'user :where "LOWER(name) = LOWER(?)" :params (list name))))

(defmethod store-find-user-by-email ((store users-table-store) email)
  (first (db-select 'user :where "LOWER(email) = LOWER(?)" :params (list email))))

(defmethod store-find-user-by-id ((store users-table-store) id)
  (let ((id (if (stringp id) (parse-integer id :junk-allowed t) id)))
    (and (integerp id) (db-find 'user id))))

(defmethod store-writable-p ((store users-table-store)) t)

(defmethod store-set-password-hash ((store users-table-store) (user user) hash)
  (setf (user-password-hash user) hash)
  (db-save user))

(defmethod store-create-user ((store users-table-store) &key name email password-hash roles)
  (let ((user (db-insert (make-instance 'user :name name :email email :password-hash password-hash))))
    (dolist (role roles) (grant-role user role))
    user))

(defvar *user-store* (make-instance 'users-table-store)
  "Where users come from.  Bind it per application with USING-USER-STORE.")

(defun using-user-store (store &optional around)
  "An :AROUND-REQUEST function binding *USER-STORE* to STORE, then calling
AROUND (another such function, such as USING-DATABASE's) if given."
  (lambda (thunk)
    (let ((*user-store* store))
      (if around (funcall around thunk) (funcall thunk)))))

;;; Roles and permissions, by name, whatever the store
;;;
;;;   user_roles (user_id, role)              roles granted here, to any store's users
;;;   role_permissions (role, permission)     what each role may do
;;;
;;; A user's roles are their store's (a SQL-USER-STORE's column or query)
;;; and those granted here; the built-in users table keeps all of its own
;;; here.  Lookups are cached for *ROLES-CACHE-SECONDS*, as restricted
;;; components ask several times a page; granting clears the cache.

(defvar *roles-cache-seconds* 2)
(defvar *roles-cache* (make-hash-table :test 'equal) "KEY → (EXPIRES . VALUE).")
(defvar *roles-cache-lock* (sb-thread:make-mutex :name "littoral roles cache"))

(defun cached (key thunk)
  (let ((now (get-universal-time)))
    (let ((entry (sb-thread:with-mutex (*roles-cache-lock*) (gethash key *roles-cache*))))
      (if (and entry (> (car entry) now))
          (cdr entry)
          (let ((value (funcall thunk)))
            (sb-thread:with-mutex (*roles-cache-lock*)
              (when (> (hash-table-count *roles-cache*) 10000) (clrhash *roles-cache*))
              (setf (gethash key *roles-cache*) (cons (+ now *roles-cache-seconds*) value)))
            value)))))

(defun forget-cached-roles ()
  (sb-thread:with-mutex (*roles-cache-lock*) (clrhash *roles-cache*)))

(defun role-name (role)
  "ROLE (a keyword or string) as stored: lower case."
  (string-downcase (string role)))

(defun name-keyword (name)
  (intern (string-upcase (string-trim " " name)) :keyword))

(defun granted-roles (user)
  "The roles granted to USER in the user_roles table."
  (let ((id (princ-to-string (user-id user))))
    (cached (list :roles id)
            (lambda ()
              (mapcar (lambda (row) (name-keyword (getf row :|role|)))
                      (db-query "SELECT role FROM user_roles WHERE user_id = ? ORDER BY role" id))))))

(defun grant-role (user role)
  "Give USER the ROLE (a keyword), whatever their store."
  (let ((id (princ-to-string (user-id user))))
    (unless (member (name-keyword (role-name role)) (granted-roles user))
      (db-execute "INSERT INTO user_roles (user_id, role) VALUES (?, ?)" id (role-name role)))
    (forget-cached-roles)
    user))

(defun revoke-role (user role)
  "Take ROLE from USER (only a role granted here: a store's own roles stay)."
  (db-execute "DELETE FROM user_roles WHERE user_id = ? AND role = ?"
              (princ-to-string (user-id user)) (role-name role))
  (forget-cached-roles)
  user)

(defun grant-permission (role permission)
  "Let users with ROLE do PERMISSION (both keywords)."
  (unless (member (name-keyword (role-name permission)) (role-permissions role))
    (db-execute "INSERT INTO role_permissions (role, permission) VALUES (?, ?)"
                (role-name role) (role-name permission)))
  (forget-cached-roles)
  permission)

(defun revoke-permission (role permission)
  (db-execute "DELETE FROM role_permissions WHERE role = ? AND permission = ?"
              (role-name role) (role-name permission))
  (forget-cached-roles)
  permission)

(defun role-permissions (role)
  "What users with ROLE may do, as keywords."
  (cached (list :role-permissions (role-name role))
          (lambda ()
            (mapcar (lambda (row) (name-keyword (getf row :|permission|)))
                    (db-query "SELECT permission FROM role_permissions WHERE role = ? ORDER BY permission"
                              (role-name role))))))

(defun user-permissions (user)
  "What USER may do through all their roles, as keywords."
  (remove-duplicates (mapcan (lambda (role) (copy-list (role-permissions role))) (user-roles user))))

(defun migrate-role-column ()
  "Move roles kept the old way, comma-separated in users.roles, to user_roles."
  (dolist (row (db-query "SELECT id, roles FROM users WHERE roles IS NOT NULL AND roles <> ''"))
    (let ((id (princ-to-string (getf row :|id|))))
      (dolist (name (cl-ppcre:split "\\s*,\\s*" (string-trim " " (getf row :|roles|))))
        (when (plusp (length name))
          (unless (db-query "SELECT 1 AS present FROM user_roles WHERE user_id = ? AND role = ?"
                            id (role-name name))
            (db-execute "INSERT INTO user_roles (user_id, role) VALUES (?, ?)" id (role-name name)))))
      (db-execute "UPDATE users SET roles = '' WHERE id = ?" (getf row :|id|))))
  (forget-cached-roles))

;;; Tables Littoral keeps whatever the store: reset tokens

(defclass auth-token (persistent)
  ((token-hash :initarg :token-hash :initform nil)
   (user-id :initarg :user-id :initform nil)
   (purpose :initarg :purpose :initform nil)
   (expires :initarg :expires :initform nil))
  (:documentation "A single-use token, such as a password reset link's, kept as its hash."))

(define-description auth-token
  ((token-hash) (user-id) (purpose) (expires :type :integer)))

(define-table auth-token :name "auth_tokens")

(defun drop-auth-tables (&key (users t))
  "Drop the tables CREATE-AUTH-TABLES makes, for tests: everything is lost."
  (dolist (table (append (when users '("users")) '("auth_tokens" "user_roles" "role_permissions")))
    (db-execute (format nil "DROP TABLE IF EXISTS ~A" table)))
  (forget-cached-roles))

(defun create-auth-tables (&key (users t))
  "Create the tables signing in needs unless they exist: the users table
(names and emails unique whatever their case) unless USERS is NIL, as when
users come from an application's own table, and the tokens table."
  (when users
    (create-table 'user)
    (db-execute "CREATE UNIQUE INDEX IF NOT EXISTS users_name ON users (LOWER(name))")
    (db-execute "CREATE UNIQUE INDEX IF NOT EXISTS users_email ON users (LOWER(email))"))
  (create-table 'auth-token)
  (db-execute "CREATE UNIQUE INDEX IF NOT EXISTS auth_tokens_hash ON auth_tokens (token_hash)")
  (db-execute "CREATE TABLE IF NOT EXISTS user_roles (user_id TEXT NOT NULL, role TEXT NOT NULL)")
  (db-execute "CREATE UNIQUE INDEX IF NOT EXISTS user_roles_key ON user_roles (user_id, role)")
  (db-execute "CREATE TABLE IF NOT EXISTS role_permissions (role TEXT NOT NULL, permission TEXT NOT NULL)")
  (db-execute "CREATE UNIQUE INDEX IF NOT EXISTS role_permissions_key ON role_permissions (role, permission)")
  (when users (migrate-role-column)))

;;; Users, whatever the store

(defun find-user (name)
  "The user called NAME (case aside, in the built-in store), or NIL."
  (and name (store-find-user *user-store* name)))

(defun find-user-by-email (email)
  "The user whose email is EMAIL, or NIL."
  (and email (store-find-user-by-email *user-store* email)))

(defun find-user-by-id (id)
  "The user whose USER-ID is ID, or NIL."
  (and id (store-find-user-by-id *user-store* id)))

(defun check-password (user password)
  "True when PASSWORD is USER's."
  (let ((hash (and user (user-password-hash user))))
    (and hash password (store-verify-password *user-store* password hash) t)))

(defun set-password (user password)
  "Give USER the new PASSWORD, and void their outstanding reset links."
  (store-set-password-hash *user-store* user (hash-password password))
  (db-execute "DELETE FROM auth_tokens WHERE user_id = ? AND purpose = ?"
              (princ-to-string (user-id user)) "reset")
  user)

(defun add-user (name email password &key roles)
  "Store a new user; ROLES are keywords.  Signals when NAME is taken or the
store doesn't create users."
  (when (find-user name)
    (error "The name ~A is taken." name))
  (or (store-create-user *user-store* :name name :email email :roles roles
                                      :password-hash (and password (hash-password password)))
      (error "This user store doesn't create users.")))

;;; Signing in, with lockout

(defvar *lockout-failures* 5
  "Failed attempts on one name, within *FAILURE-WINDOW-SECONDS*, before it is locked.")
(defvar *lockout-seconds* 60
  "How long a name stays locked after its latest failure.")
(defvar *failure-window-seconds* 900
  "How long a failed attempt counts against a name or an address.")
(defvar *failures-per-address* 30
  "Failed sign-ins from one public client address, within
*FAILURE-WINDOW-SECONDS*, before it may try no more names for
*LOCKOUT-SECONDS*.  Stops one address guessing a common password across
many names.  Loopback and private addresses, usually a proxy's, are not
limited: behind a proxy, set *TRUST-FORWARDED-FOR* so the limit sees clients.")

;;; Recent events by key, such as failed sign-ins by name

(defvar *events* (make-hash-table :test 'equal)
  "(KIND . KEY) → times of recent events, newest first.")
(defvar *failures* *events* "The table of recent failures and mails (for tests to clear).")
(defvar *events-lock* (sb-thread:make-mutex :name "littoral auth events"))

(defun recent-events (kind key &optional (seconds *failure-window-seconds*))
  "Times of KIND events for KEY in the last SECONDS, newest first."
  (let ((since (- (get-universal-time) seconds)))
    (sb-thread:with-mutex (*events-lock*)
      (remove-if (lambda (time) (< time since)) (gethash (cons kind key) *events*)))))

(defun note-event (kind key)
  "Record a KIND event for KEY now, forgetting events too old to matter."
  (let* ((now (get-universal-time))
         (since (- now (max *failure-window-seconds* 3600))))
    (sb-thread:with-mutex (*events-lock*)
      (let ((k (cons kind key)))
        (setf (gethash k *events*)
              (cons now (remove-if (lambda (time) (< time since)) (gethash k *events*)))))
      ;; Now and then, drop keys with nothing recent, so names tried once
      ;; don't pile up.
      (when (zerop (random 64))
        (loop for k being the hash-keys of *events* using (hash-value times)
              unless (and times (>= (first times) since))
                do (remhash k *events*))))))

(defun forget-events (kind key)
  (sb-thread:with-mutex (*events-lock*)
    (remhash (cons kind key) *events*)))

(defun locked-out-p (kind key limit)
  "True when KEY has LIMIT or more KIND failures in the window, the latest
within *LOCKOUT-SECONDS*."
  (let ((times (recent-events kind key)))
    (and (>= (length times) limit)
         (> (first times) (- (get-universal-time) *lockout-seconds*)))))

(defun limited-address ()
  "The request's client address when limits per address should apply to it:
a public one.  A loopback or private address is almost always a proxy that
every visitor shares (set *TRUST-FORWARDED-FOR* to see past it), and
limiting it would let one person lock everyone out."
  (let ((address (and *request* (littoral::client-address))))
    (and address
         (not (cl-ppcre:scan "^(?:127\\.|10\\.|192\\.168\\.|172\\.(?:1[6-9]|2[0-9]|3[01])\\.|169\\.254\\.|::1$|::ffff:127\\.|f[cd][0-9a-f]{2}:|fe80:|localhost$)"
                             (string-downcase address)))
         address)))

(defun locked-p (name)
  (or (locked-out-p :name (string-downcase name) *lockout-failures*)
      (let ((address (limited-address)))
        (and address (locked-out-p :address address *failures-per-address*)))))

(defun note-attempt (name succeeded)
  (let ((name (string-downcase name)))
    (cond (succeeded (forget-events :name name))
          (t (note-event :name name)
             (let ((address (limited-address)))
               (when address (note-event :address address)))))))

(defvar *dummy-hash* nil
  "A hash checked against when the name is unknown, so that answering takes
as long as for a wrong password and doesn't tell which names exist.")

(defvar *rehash-on-sign-in* t
  "When true, signing in re-hashes a password kept in another format (bcrypt,
Django's) or with fewer than *PBKDF2-ITERATIONS*, where the store can write.")

(defun dummy-check (password)
  (let ((dummy *dummy-hash*))
    (unless (and dummy (not (password-needs-rehash-p dummy)))
      (setf dummy (setf *dummy-hash* (hash-password "dummy password"))))
    (verify-password (or password "") dummy)
    nil))

(defun authenticate (name password)
  "The active user NAME if PASSWORD is theirs and neither the name nor the
client's address is locked out; otherwise NIL and, as a second value, why."
  (cond ((locked-p name)
         (values nil (translate "Too many failed attempts; try again in a minute.")))
        (t (let* ((user (find-user name))
                  (good (if user (check-password user password) (dummy-check password))))
             (cond ((and good (user-active-p user))
                    (note-attempt name t)
                    (when (and *rehash-on-sign-in* (store-writable-p *user-store*)
                               (password-needs-rehash-p (user-password-hash user)))
                      (store-set-password-hash *user-store* user (hash-password password)))
                    user)
                   (t (note-attempt name nil)
                      (values nil (translate "Unknown user or wrong password."))))))))

;;; The session's user

(defun current-user ()
  "The user signed in to this session, or NIL."
  (let ((id (session-property :user-id)))
    (and id (let ((user (find-user-by-id id)))
              (and user (user-active-p user) user)))))

(defun signed-in-p ()
  (and (current-user) t))

(defun log-in (user)
  "Sign USER in to this session.  The session gets a new key, so a link to
it that someone else had beforehand no longer reaches it."
  (setf (session-property :user-id) (user-id user))
  (when *session* (rotate-session-key *session*))
  user)

(defun log-out ()
  "Sign the session's user out, and give the session a new key."
  (setf (session-property :user-id) nil)
  (when *session* (rotate-session-key *session*)))

(defun has-role-p (role &optional (user (current-user)))
  "True when USER has ROLE (a keyword); with ROLE NIL, when there is a user."
  (and user (or (null role) (member role (user-roles user)))))

(defun has-permission-p (permission &optional (user (current-user)))
  "True when USER may do PERMISSION (a keyword) through one of their roles."
  (and user (member permission (user-permissions user)) t))

(defun require-permission (permission)
  "Refuse the request (403) unless the current user may do PERMISSION."
  (unless (has-permission-p permission)
    (error 'forbidden :message (if (signed-in-p)
                                   "You don't have permission to do that."
                                   "Please sign in first."))))

(defun require-role (role)
  "Refuse the request (403) unless the current user has ROLE; with ROLE
NIL, unless someone is signed in."
  (unless (has-role-p role)
    (error 'forbidden :message (if (signed-in-p)
                                   "You don't have permission to do that."
                                   "Please sign in first."))))

;;; Restricted components

(defclass restricted () ()
  (:documentation "Mixin for components only some users may see.  Specialise
REQUIRED-ROLE; the default lets anyone signed in see it."))

(defgeneric required-role (component)
  (:documentation "The role needed to see COMPONENT, or NIL for any signed-in user.")
  (:method ((component restricted)) nil))

(defgeneric required-permission (component)
  (:documentation "The permission needed to see COMPONENT, or NIL for none beyond its role.")
  (:method ((component restricted)) nil))

(defun permitted-p (component)
  "True when the current user may see COMPONENT: has its role, and its permission."
  (and (has-role-p (required-role component))
       (let ((permission (required-permission component)))
         (or (null permission) (has-permission-p permission)))))

(defmethod render-component :around ((component restricted))
  ;; Showing what it called (the sign-in form, say) is always allowed.
  (if (or (permitted-p component) (littoral::find-decoration component 'delegation))
      (call-next-method)
      (div (:class "lt-restricted")
        (if (signed-in-p)
            (p () (translate "You don't have permission to see this."))
            (p () (translate "Please sign in to see this.") " "
              (anchor (:callback (lambda () (show component (make-instance 'sign-in))))
                (translate "Sign in")))))))

(defmethod children :around ((component restricted))
  ;; What is not shown is not visited (snapshots, AJAX, push).
  (if (permitted-p component) (call-next-method) '()))

;;; The sign-in form

(defvar *sign-in-extras* '()
  "Functions of the SIGN-IN component writing more ways to sign in (OAuth
buttons, from littoral/oauth).")

(defclass sign-in (component)
  ((name :initform "" :accessor sign-in-name)
   (password :initform "" :accessor sign-in-password)
   (message :initform nil :accessor sign-in-message))
  (:documentation "Asks for a name and password; signs the user in and answers them."))

(defun try-sign-in (self)
  (multiple-value-bind (user problem) (authenticate (string-trim " " (sign-in-name self)) (sign-in-password self))
    (setf (sign-in-password self) "")
    (if user
        (progn (log-in user) (answer self user))
        (setf (sign-in-message self) problem))))

(defmethod render ((self sign-in))
  (div (:class "lt-dialog lt-sign-in")
    (h2 () (translate "Sign in"))
    (when (sign-in-message self)
      (p (:class "lt-validation-error" :role "alert") (text (sign-in-message self))))
    (form ()
      (div (:class "lt-field")
        (label (:for "sign-in-name") (translate "Name"))
        (text-input (:id "sign-in-name" :value (sign-in-name self) :autocomplete "username" :required t
                     :callback (lambda (v) (setf (sign-in-name self) v)))))
      (div (:class "lt-field")
        (label (:for "sign-in-password") (translate "Password"))
        (password-input (:id "sign-in-password" :autocomplete "current-password" :required t
                         :callback (lambda (v) (setf (sign-in-password self) v)))))
      (div (:class "lt-buttons")
        (submit-button (:callback (lambda () (try-sign-in self))) (translate "Sign in"))
        (cancel-button (:callback (lambda () (answer self nil))) (translate "Cancel"))))
    (p () (anchor (:callback (lambda () (show self (make-instance 'password-reset-request))))
            (translate "Forgot your password?")))
    (dolist (extra *sign-in-extras*)
      (funcall extra self))))

(defun sign-out-link (&key (label "Sign out") then)
  "Write a link that signs the user out, then calls THEN, a thunk."
  (anchor (:callback (lambda () (log-out) (when then (funcall then)))) (text (translate-label label))))

;;; Password reset

(defvar *send-mail*
  (lambda (to subject body)
    (format *error-output* "~&--- mail to ~A: ~A~%~A~%---~%" to subject body))
  "A function of (TO SUBJECT BODY) that sends mail.  The default prints it;
plug in your mailer.")

(defvar *last-mail* nil
  "The last mail sent, as (TO SUBJECT BODY), for development and tests.")

(defvar *reset-link-seconds* 3600 "How long a password reset link works.")

(defun token-hash (token)
  (ironclad:byte-array-to-hex-string (ironclad:digest-sequence :sha256 (octets token))))

(defvar *public-url* nil
  "This site's address as its users reach it, such as \"https://example.org\",
for links in mail and OAuth redirects.  Required in deployment mode: the
request's Host header is the client's to choose, and a reset link built
from a forged one would send its token to someone else's site.")

(defun request-base-url (&optional (request *request*))
  "This site's address, such as https://example.org: *PUBLIC-URL*, or in
development mode the request's own host."
  (cond (*public-url* (string-right-trim "/" *public-url*))
        ((and *application* (not (littoral::development-p)))
         (error "Set LITTORAL.AUTH:*PUBLIC-URL* to this site's address: links in mail ~
and OAuth redirects can't trust the request's Host header."))
        (t (let ((headers (lack/request:request-headers request)))
             (format nil "~A://~A"
                     (if (littoral::secure-request-p request) "https" "http")
                     (or (and *trust-forwarded-for* (gethash "x-forwarded-host" headers))
                         (gethash "host" headers) "localhost"))))))

(defvar *reset-mails-per-address* 5
  "Reset mails one client address may have sent, within *FAILURE-WINDOW-SECONDS*.")

(defun may-send-reset-p (user)
  "True unless USER was sent a link in the last minute or this client has
asked for too many: the form must not become a way to flood an inbox."
  (and (null (recent-events :reset-mail (user-id user) 60))
       (let ((address (limited-address)))
         (or (null address)
             (< (length (recent-events :reset-address address)) *reset-mails-per-address*)))))

(defun send-reset-link (user)
  "Email USER a link that lets them choose a new password."
  (note-event :reset-mail (user-id user))
  (let ((address (limited-address)))
    (when address (note-event :reset-address address)))
  (let ((token (littoral::random-key 32))
        (id (princ-to-string (user-id user))))
    ;; One live link per user: a new one voids the last.
    (db-execute "DELETE FROM auth_tokens WHERE user_id = ? AND purpose = ?" id "reset")
    (db-insert (make-instance 'auth-token :token-hash (token-hash token) :user-id id :purpose "reset"
                                          :expires (+ (get-universal-time) *reset-link-seconds*)))
    (let ((mail (list (user-email user) (translate "Choose a new password")
                      (translate "Someone asked to reset the password for ~A.~%~%~
To choose a new one, open:~%~A~A/reset?token=~A~%~%~
The link works once, for an hour.  If it wasn't you, ignore this mail."
                              (user-name user) (request-base-url)
                              (url-for (application-path *application*)) token))))
      (setf *last-mail* mail)
      (apply *send-mail* mail))))

(defun user-for-reset-token (token)
  "The user whose unexpired reset link carries TOKEN, or NIL."
  (and token
       (let ((row (first (db-select 'auth-token :where "token_hash = ? AND purpose = ?"
                                                :params (list (token-hash token) "reset")))))
         (and row (> (slot-value row 'expires) (get-universal-time))
              (find-user-by-id (slot-value row 'user-id))))))

(defclass password-reset-request (component)
  ((email :initform "" :accessor reset-email)
   (sent :initform nil :accessor reset-sent-p))
  (:documentation "Asks for an email address and sends a reset link to it."))

(defmethod render ((self password-reset-request))
  (div (:class "lt-dialog")
    (h2 () (translate "Reset your password"))
    (if (reset-sent-p self)
        (progn
          ;; The same answer whether or not the address has an account.
          (p (:role "status") (translate "If that address belongs to an account, a link to choose a new password is on its way."))
          (form () (submit-button (:callback (lambda () (answer self nil))) (translate "Back"))))
        (form ()
          (div (:class "lt-field")
            (label (:for "reset-email") (translate "Email"))
            (littoral::emit-tag "input" (list :type "email" :id "reset-email" :required t :value (reset-email self)
                                    :name (littoral::register :value (lambda (v) (setf (reset-email self) v))))
                      nil))
          (div (:class "lt-buttons")
            (submit-button (:callback (lambda ()
                                        (let ((user (find-user-by-email (string-trim " " (reset-email self)))))
                                          (when (and user (user-active-p user) (may-send-reset-p user))
                                            (send-reset-link user)))
                                        (setf (reset-sent-p self) t)))
              (translate "Send me a link"))
            (cancel-button (:callback (lambda () (answer self nil))) (translate "Cancel")))))))

(defclass password-reset (component)
  ((user-id :initarg :user-id :reader reset-user-id)
   (password :initform "" :accessor reset-password)
   (again :initform "" :accessor reset-again)
   (message :initform nil :accessor reset-message))
  (:documentation "Lets the holder of a reset link choose a new password; answers the user."))

(defmethod render ((self password-reset))
  (div (:class "lt-dialog")
    (h2 () (translate "Choose a new password"))
    (when (reset-message self)
      (p (:class "lt-validation-error" :role "alert") (text (reset-message self))))
    (form ()
      (div (:class "lt-field")
        (label (:for "new-password") (translate "New password"))
        (password-input (:id "new-password" :autocomplete "new-password" :required t
                         :callback (lambda (v) (setf (reset-password self) v)))))
      (div (:class "lt-field")
        (label (:for "new-password-again") (translate "Again"))
        (password-input (:id "new-password-again" :autocomplete "new-password" :required t
                         :callback (lambda (v) (setf (reset-again self) v)))))
      (div (:class "lt-buttons")
        (submit-button (:callback
                        (lambda ()
                          (cond ((< (length (reset-password self)) 8)
                                 (setf (reset-message self) (translate "Passwords need at least 8 characters.")))
                                ((string/= (reset-password self) (reset-again self))
                                 (setf (reset-message self) (translate "The passwords differ.")))
                                (t (let ((user (find-user-by-id (reset-user-id self))))
                                     (set-password user (reset-password self))
                                     (log-in user)
                                     (answer self user))))))
          (translate "Save and sign in"))))))

;;; Paths an application's root answers: /reset (and /oauth/… from littoral/oauth)

(defvar *auth-paths* (make-hash-table :test 'equal)
  "First path segment → a function of (ROOT REST-OF-PATH REQUEST) run when a
session starts at that path.")

(defmacro define-auth-path (segment (root rest request) &body body)
  "Run BODY when a session of an AUTH-ROOT application starts at
/SEGMENT/…, with REST the remaining segments."
  `(setf (gethash ,segment *auth-paths*)
         (lambda (,root ,rest ,request)
           (declare (ignorable ,root ,rest ,request))
           ,@body)))

(defclass auth-root () ()
  (:documentation "Mixin for an application's root component: it answers
password reset links and, with littoral/oauth, sign-in callbacks."))

(defmethod initial-request :around ((root auth-root) request)
  (let* ((path (request-extra-path))
         (handler (gethash (first path) *auth-paths*)))
    (if handler
        (funcall handler root (rest path) request)
        (call-next-method))))

(define-auth-path "reset" (root rest request)
  (let ((user (user-for-reset-token (request-parameter "token" request))))
    (if user
        (show root (make-instance 'password-reset :user-id (user-id user)))
        (show root (make-instance 'message-dialog
                                  :message (translate "That link has expired or been used. Ask for a new one."))))))
