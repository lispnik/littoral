;;;; auth-store.lisp — signing in against an application's own users table
;;;;
;;;;   (setf *user-store*
;;;;         (make-sql-user-store :table "accounts" :id "account_id" :name "login"
;;;;                              :email "email" :password "pw_hash" :active "enabled"
;;;;                              :roles-query "SELECT r.name FROM roles r
;;;;                                            JOIN account_roles ar ON ar.role_id = r.id
;;;;                                            WHERE ar.account_id = ?"))
;;;;   (create-auth-tables :users nil)          ; only Littoral's own tables
;;;;
;;;; Columns are named, not written as code.  Hashes may be bcrypt, Django's
;;;; or Werkzeug's PBKDF2, or Littoral's (see passwords.lisp); :VERIFY takes
;;;; a function of (PASSWORD HASH) for anything else.  With :WRITABLE T,
;;;; password changes and resets write the password column, and signing in
;;;; upgrades old hashes to Littoral's; otherwise the table is only read.
;;;; With :CREATE T, OAuth sign-in may insert users (name and email).

(in-package #:littoral.auth)

(defclass sql-user-store (user-store)
  ((table :initarg :table :reader store-table)
   (id :initarg :id :reader store-id-column)
   (name :initarg :name :reader store-name-column)
   (email :initarg :email :reader store-email-column)
   (password :initarg :password :reader store-password-column)
   (active :initarg :active :reader store-active-column)
   (roles-column :initarg :roles-column :reader store-roles-column)
   (roles-query :initarg :roles-query :reader store-roles-query)
   (writable :initarg :writable :reader store-writable)
   (create :initarg :create :reader store-create)
   (case-insensitive :initarg :case-insensitive :reader store-case-insensitive-p)
   (verify :initarg :verify :reader store-verify))
  (:documentation "Users kept in an application's own table, described by its column names."))

(defun check-identifier (name what)
  (unless (and (stringp name) (cl-ppcre:scan "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)?$" name))
    (error "~A must be a plain SQL name, not ~S." what name))
  name)

(defun make-sql-user-store (&key table (id "id") (name "name") email (password "password_hash")
                              active roles-column roles-query writable create
                              (case-insensitive t) verify)
  "A user store over TABLE, whose columns are ID, NAME, EMAIL (optional),
PASSWORD (the hash) and ACTIVE (optional: a boolean or 0/1 column).  Roles
come from ROLES-COLUMN (comma-separated names) or ROLES-QUERY (SQL with one
?, the user's id, returning role names in its first column).  NAME and
EMAIL match regardless of case unless CASE-INSENSITIVE is NIL.  VERIFY, a
function of (PASSWORD HASH), replaces the built-in hash formats."
  (check-identifier table "The table")
  (dolist (column (list id name password)) (check-identifier column "A column"))
  (dolist (column (list email active roles-column)) (when column (check-identifier column "A column")))
  (make-instance 'sql-user-store :table table :id id :name name :email email :password password
                                 :active active :roles-column roles-column :roles-query roles-query
                                 :writable writable :create create
                                 :case-insensitive case-insensitive :verify verify))

(defclass sql-user ()
  ((store :initarg :store :reader sql-user-store)
   (row :initarg :row :reader sql-user-row
        :documentation "The row read, keyed :|lt_id|, :|lt_name|, …"))
  (:documentation "A user read from a SQL-USER-STORE's table."))

(defmethod print-object ((user sql-user) stream)
  (print-unreadable-object (user stream :type t)
    (format stream "~A" (user-name user))))

(defun select-users (store where &rest parameters)
  "STORE's users matching WHERE (SQL over its columns, with ? for PARAMETERS)."
  (let ((sql (format nil "SELECT ~A AS lt_id, ~A AS lt_name, ~:[NULL~;~:*~A~] AS lt_email, ~
~A AS lt_password, ~:[1~;~:*~A~] AS lt_active, ~:[NULL~;~:*~A~] AS lt_roles FROM ~A WHERE ~A"
                     (store-id-column store) (store-name-column store) (store-email-column store)
                     (store-password-column store) (store-active-column store)
                     (store-roles-column store) (store-table store) where)))
    (mapcar (lambda (row) (make-instance 'sql-user :store store :row row))
            (apply #'db-query sql parameters))))

(defun matching (store column)
  (if (store-case-insensitive-p store)
      (format nil "LOWER(~A) = LOWER(?)" column)
      (format nil "~A = ?" column)))

(defmethod store-find-user ((store sql-user-store) name)
  (first (select-users store (matching store (store-name-column store)) name)))

(defmethod store-find-user-by-email ((store sql-user-store) email)
  (and (store-email-column store)
       (first (select-users store (matching store (store-email-column store)) email))))

(defmethod store-find-user-by-id ((store sql-user-store) id)
  (first (select-users store (format nil "~A = ?" (store-id-column store)) id)))

(defmethod store-writable-p ((store sql-user-store))
  (store-writable store))

(defmethod store-set-password-hash ((store sql-user-store) user hash)
  (unless (store-writable store)
    (error "This user store is read-only: it can't change passwords."))
  (db-execute (format nil "UPDATE ~A SET ~A = ? WHERE ~A = ?"
                      (store-table store) (store-password-column store) (store-id-column store))
              hash (user-id user))
  (setf (getf (slot-value user 'row) :|lt_password|) hash)
  user)

(defmethod store-create-user ((store sql-user-store) &key name email password-hash roles)
  (declare (ignore roles))
  (when (store-create store)
    (let ((columns (list (store-name-column store)))
          (values (list name)))
      (when (store-email-column store)
        (push (store-email-column store) columns) (push email values))
      (when password-hash
        (push (store-password-column store) columns) (push password-hash values))
      (apply #'db-execute (format nil "INSERT INTO ~A (~{~A~^, ~}) VALUES (~{~*?~^, ~})"
                                  (store-table store) columns columns)
             values)
      (store-find-user store name))))

(defmethod store-verify-password ((store sql-user-store) password hash)
  (if (store-verify store)
      (and (funcall (store-verify store) password hash) t)
      (verify-password password hash)))

;;; The user protocol, for rows of such a table

(defun row-value (user key)
  (getf (sql-user-row user) key))

(defmethod user-id ((user sql-user)) (row-value user :|lt_id|))
(defmethod user-name ((user sql-user)) (row-value user :|lt_name|))
(defmethod user-email ((user sql-user)) (row-value user :|lt_email|))
(defmethod user-password-hash ((user sql-user)) (row-value user :|lt_password|))

(defmethod user-active-p ((user sql-user))
  ;; PostgreSQL booleans arrive as T/NIL, SQLite's as 1/0, some as text.
  (let ((value (row-value user :|lt_active|)))
    (not (member value '(nil 0 "0" "f" "false" "F" "FALSE") :test #'equal))))

(defun role-keyword (name)
  (intern (string-upcase (string-trim " " (princ-to-string name))) :keyword))

(defmethod user-roles ((user sql-user))
  (let ((store (sql-user-store user)))
    (cond ((store-roles-query store)
           (loop for row in (db-query (store-roles-query store) (user-id user))
                 for value = (second row)
                 when value collect (role-keyword value)))
          ((row-value user :|lt_roles|)
           (mapcar #'role-keyword
                   (remove "" (mapcar (lambda (s) (string-trim " " s))
                                      (cl-ppcre:split "," (row-value user :|lt_roles|)))
                           :test #'string=)))
          (t '()))))
