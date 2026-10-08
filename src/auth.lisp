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
;;;; REQUIRE-ROLE, which refuses with a 403.  Passwords are kept as PBKDF2
;;;; hashes; signing in locks a name for a while after repeated failures.
;;;; Password reset sends a single-use, expiring link through *SEND-MAIL*.

(defpackage #:littoral.auth
  (:use #:cl #:littoral #:littoral.html #:littoral.db)
  (:documentation "Users, signing in, roles and password reset for Littoral.")
  (:export #:user #:user-name #:user-email #:user-roles #:user-active-p
           #:create-auth-tables #:add-user #:find-user #:find-user-by-email #:set-password
           #:check-password #:authenticate
           #:current-user #:log-in #:log-out #:signed-in-p #:has-role-p #:require-role
           #:restricted #:required-role #:permitted-p
           #:sign-in #:sign-out-link #:password-reset-request #:password-reset
           #:auth-root #:define-auth-path #:request-base-url
           #:*send-mail* #:*last-mail* #:*lockout-failures* #:*lockout-seconds*
           #:*reset-link-seconds* #:*sign-in-extras*))

(in-package #:littoral.auth)

;;; Users

(defclass user (persistent)
  ((name :initarg :name :initform nil :accessor user-name)
   (email :initarg :email :initform nil :accessor user-email)
   (roles :initarg :roles :initform "" :accessor user-roles-text
          :documentation "Roles as stored: comma-separated names.")
   (active :initarg :active :initform t :accessor user-active-p)
   (password-hash :initarg :password-hash :initform nil :accessor user-password-hash)
   (reset-hash :initform nil :accessor user-reset-hash)
   (reset-expires :initform nil :accessor user-reset-expires))
  (:documentation "Someone who can sign in."))

(define-description user
  ((name :required t :max-length 40 :pattern "[A-Za-z0-9_.-]+"
         :pattern-message "Names are letters, digits, dots, dashes and underscores.")
   (email :type :email :required t)
   (roles :help "Comma-separated, such as admin,editor.")
   (active :type :boolean)
   (password-hash :type :password :read-only t :label "Password")
   (reset-hash :hidden t)
   (reset-expires :type :integer :hidden t)))

(define-table user :name "users")

(defun user-roles (user)
  "USER's roles, as keywords."
  (mapcar (lambda (name) (intern (string-upcase (string-trim " " name)) :keyword))
          (remove "" (cl-ppcre:split "," (or (user-roles-text user) ""))
                  :test (lambda (a b) (string= a (string-trim " " b))))))

(defun create-auth-tables ()
  "Create the users table unless it exists."
  (create-table 'user))

(defun octets (string)
  (sb-ext:string-to-octets string :external-format :utf-8))

(defun hash-password (password)
  "A PBKDF2 hash of PASSWORD, salted, as one string."
  (ironclad:pbkdf2-hash-password-to-combined-string (octets password)))

(defun check-password (user password)
  "True when PASSWORD is USER's."
  (and user password (user-password-hash user)
       (ignore-errors (ironclad:pbkdf2-check-password (octets password) (user-password-hash user)))))

(defun set-password (user password)
  "Give USER the new PASSWORD (and forget any reset link)."
  (setf (user-password-hash user) (hash-password password)
        (user-reset-hash user) nil
        (user-reset-expires user) nil)
  (db-save user))

(defun find-user (name)
  "The user called NAME, ignoring case, or NIL."
  (first (db-select 'user :where "LOWER(name) = LOWER(?)" :params (list name))))

(defun find-user-by-email (email)
  "The user whose email is EMAIL, ignoring case, or NIL."
  (first (db-select 'user :where "LOWER(email) = LOWER(?)" :params (list email))))

(defun add-user (name email password &key roles)
  "Store a new user; ROLES are keywords.  Signals when NAME is taken."
  (when (find-user name)
    (error "The name ~A is taken." name))
  (db-insert (make-instance 'user :name name :email email
                                  :roles (format nil "~{~(~A~)~^,~}" roles)
                                  :password-hash (and password (hash-password password)))))

;;; Signing in, with lockout

(defvar *lockout-failures* 5 "Failed attempts on one name before it is locked.")
(defvar *lockout-seconds* 60 "How long a name stays locked.")

(defvar *failures* (make-hash-table :test 'equalp) "Name → (FAILURES . LOCKED-UNTIL).")
(defvar *failures-lock* (sb-thread:make-mutex :name "littoral sign-in failures"))

(defun locked-p (name)
  (sb-thread:with-mutex (*failures-lock*)
    (let ((entry (gethash name *failures*)))
      (and entry (cdr entry) (< (get-universal-time) (cdr entry))))))

(defun note-attempt (name succeeded)
  (sb-thread:with-mutex (*failures-lock*)
    (if succeeded
        (remhash name *failures*)
        (let ((entry (or (gethash name *failures*) (setf (gethash name *failures*) (cons 0 nil)))))
          (when (>= (incf (car entry)) *lockout-failures*)
            (setf (car entry) 0
                  (cdr entry) (+ (get-universal-time) *lockout-seconds*)))))))

(defun authenticate (name password)
  "The active user NAME if PASSWORD is theirs and the name is not locked;
otherwise NIL and, as a second value, why."
  (cond ((locked-p name)
         (values nil (translate "Too many failed attempts; try again in a minute.")))
        (t (let ((user (find-user name)))
             (if (and user (user-active-p user) (check-password user password))
                 (progn (note-attempt name t) user)
                 (progn (note-attempt name nil)
                        (values nil (translate "Unknown user or wrong password."))))))))

;;; The session's user

(defun current-user ()
  "The user signed in to this session, or NIL."
  (let ((id (session-property :user-id)))
    (and id (let ((user (db-find 'user id)))
              (and user (user-active-p user) user)))))

(defun signed-in-p ()
  (and (current-user) t))

(defun log-in (user)
  "Sign USER in to this session."
  (setf (session-property :user-id) (object-id user))
  user)

(defun log-out ()
  "Sign the session's user out."
  (setf (session-property :user-id) nil))

(defun has-role-p (role &optional (user (current-user)))
  "True when USER has ROLE (a keyword); with ROLE NIL, when there is a user."
  (and user (or (null role) (member role (user-roles user)))))

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

(defun permitted-p (component)
  "True when the current user may see COMPONENT."
  (has-role-p (required-role component)))

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

(defun request-base-url (&optional (request *request*))
  "This server's address as the browser sees it, such as https://example.org."
  (let ((headers (lack/request:request-headers request)))
    (format nil "~A://~A"
            (if (littoral::secure-request-p request) "https" "http")
            (or (gethash "x-forwarded-host" headers) (gethash "host" headers) "localhost"))))

(defun send-reset-link (user)
  "Email USER a link that lets them choose a new password."
  (let ((token (littoral::random-key 32)))
    (setf (user-reset-hash user) (token-hash token)
          (user-reset-expires user) (+ (get-universal-time) *reset-link-seconds*))
    (db-save user)
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
       (let ((user (first (db-select 'user :where "reset_hash = ?" :params (list (token-hash token))))))
         (and user (user-reset-expires user) (< (get-universal-time) (user-reset-expires user))
              user))))

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
                                          (when (and user (user-active-p user))
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
                                (t (let ((user (db-find 'user (reset-user-id self))))
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
        (show root (make-instance 'password-reset :user-id (object-id user)))
        (show root (make-instance 'message-dialog
                                  :message (translate "That link has expired or been used. Ask for a new one."))))))
