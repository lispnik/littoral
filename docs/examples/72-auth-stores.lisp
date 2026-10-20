;;;; Examples for littoral.auth: where users come from — the users table, an application's own table, or any store.

;;;; Example: littoral.auth:make-sql-user-store littoral.auth:sql-user-store littoral.auth:sql-user
;;; Sign in against an application's own accounts table, naming its columns.  Its bcrypt hashes verify as they are, and its roles come from a query.  Littoral's own tables are made without a users table.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.db:db-execute "CREATE TABLE accounts (account_id INTEGER PRIMARY KEY, login TEXT,
                           email TEXT, pw_hash TEXT, enabled INTEGER)")
  (littoral.db:db-execute "CREATE TABLE account_roles (account_id INTEGER, role TEXT)")
  (littoral.db:db-execute "INSERT INTO accounts (login, email, pw_hash, enabled) VALUES (?, ?, ?, 1)"
                          "ada" "ada@example.org" (littoral.auth:bcrypt-hash "ada's long secret" :cost 4))
  (littoral.db:db-execute "INSERT INTO account_roles VALUES (1, 'admin')")
  (littoral.auth:create-auth-tables :users nil)
  (let ((littoral.auth:*user-store*
          (littoral.auth:make-sql-user-store
           :table "accounts" :id "account_id" :name "login" :email "email"
           :password "pw_hash" :active "enabled"
           :roles-query "SELECT role FROM account_roles WHERE account_id = ?")))
    (let ((ada (littoral.auth:authenticate "ADA" "ada's long secret")))
      (list (type-of ada)
            (littoral.auth:user-id ada)
            (littoral.auth:user-name ada)
            (littoral.auth:user-roles ada)))))
;; ⇒ (LITTORAL.AUTH:SQL-USER 1 "ada" (:ADMIN))

;;;; Example: littoral.auth:make-sql-user-store
;;; Table and column names must be plain SQL names: they are written into queries.
(handler-case (littoral.auth:make-sql-user-store :table "accounts; DROP TABLE accounts")
  (error (e) (princ-to-string e)))
;; ⇒ "The table must be a plain SQL name, not \"accounts; DROP TABLE accounts\"."

;;;; Example: littoral.auth:user-store littoral.auth:store-find-user littoral.auth:store-find-user-by-id littoral.auth:store-find-user-by-email
;;; Any class can be a store: specialise the STORE- generic functions.  Its users are any objects with methods for the user generic functions; here, users kept in a list.
(defclass staff-member ()
  ((id :initarg :id :reader staff-id)
   (name :initarg :name :reader staff-name)
   (hash :initarg :hash :reader staff-hash)))
(defmethod littoral.auth:user-id ((user staff-member)) (staff-id user))
(defmethod littoral.auth:user-name ((user staff-member)) (staff-name user))
(defmethod littoral.auth:user-password-hash ((user staff-member)) (staff-hash user))
(defclass staff-list (littoral.auth:user-store)
  ((members :initarg :members :reader staff-members)))
(defmethod littoral.auth:store-find-user ((store staff-list) name)
  (find name (staff-members store) :key #'staff-name :test #'string-equal))
(defmethod littoral.auth:store-find-user-by-id ((store staff-list) id)
  (find (princ-to-string id) (staff-members store)
        :key (lambda (user) (princ-to-string (staff-id user))) :test #'string=))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables :users nil)
  (let ((littoral.auth:*user-store*
          (make-instance 'staff-list
                         :members (list (make-instance 'staff-member :id 7 :name "carol"
                                                                     :hash (littoral.auth:hash-password "carol's secret"))))))
    (list (littoral.auth:user-name (littoral.auth:authenticate "Carol" "carol's secret"))
          (littoral.auth:user-name (littoral.auth:find-user-by-id "7"))
          ;; Without a method for it, the store finds no one by email.
          (littoral.auth:find-user-by-email "carol@example.org")
          (littoral.auth:user-roles (littoral.auth:find-user "carol")))))
;; ⇒ ("carol" "carol" NIL NIL)

;;;; Example: littoral.auth:store-writable-p littoral.auth:store-set-password-hash
;;; Only a writable store can change passwords; a SQL store is read-only unless made with :WRITABLE T.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.db:db-execute "CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, password_hash TEXT)")
  (littoral.db:db-execute "INSERT INTO people (name, password_hash) VALUES ('ada', NULL)")
  (littoral.auth:create-auth-tables :users nil)
  (let* ((read-only (littoral.auth:make-sql-user-store :table "people"))
         (writable (littoral.auth:make-sql-user-store :table "people" :writable t))
         (ada (littoral.auth:store-find-user writable "ada")))
    (littoral.auth:store-set-password-hash writable ada (littoral.auth:hash-password "a passphrase"))
    (list (littoral.auth:store-writable-p read-only)
          (littoral.auth:store-writable-p writable)
          (littoral.auth:verify-password "a passphrase" (littoral.auth:user-password-hash ada))
          (handler-case (littoral.auth:store-set-password-hash read-only ada "x")
            (error (e) (princ-to-string e))))))
;; ⇒ (NIL T T "This user store is read-only: it can't change passwords.")

;;;; Example: littoral.auth:store-create-user
;;; OAuth sign-in creates users through the store; a SQL store does only when made with :CREATE T, and returns NIL otherwise.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:db-execute "CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, email TEXT, password_hash TEXT)")
  (let ((closed (littoral.auth:make-sql-user-store :table "people" :email "email"))
        (open (littoral.auth:make-sql-user-store :table "people" :email "email" :create t)))
    (list (littoral.auth:store-create-user closed :name "dave" :email "dave@example.org")
          (littoral.auth:user-email (littoral.auth:store-create-user open :name "dave" :email "dave@example.org")))))
;; ⇒ (NIL "dave@example.org")

;;;; Example: littoral.auth:store-verify-password
;;; :VERIFY replaces the built-in hash formats, for a table whose hashes Littoral can't read.
(let ((store (littoral.auth:make-sql-user-store
              :table "people"
              :verify (lambda (password hash) (string= hash (reverse password))))))
  (list (littoral.auth:store-verify-password store "secret" "terces")
        (littoral.auth:store-verify-password store "secret" "secret")))
;; ⇒ (T NIL)

;;;; Example: littoral.auth:users-table-store littoral.auth:*user-store*
;;; By default users come from the built-in users table.
(type-of littoral.auth:*user-store*)
;; ⇒ LITTORAL.AUTH:USERS-TABLE-STORE

;;;; Example: littoral.auth:using-user-store
;;; Give one application its own store, by binding *USER-STORE* around its requests.
(defclass who-is-ada (component) ())
(defmethod render ((self who-is-ada))
  (h:p () (h:text (littoral.auth:user-email (littoral.auth:find-user "ada")))))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:db-execute "CREATE TABLE members (id INTEGER PRIMARY KEY, name TEXT, email TEXT, password_hash TEXT)")
  (littoral.db:db-execute "INSERT INTO members (name, email) VALUES ('ada', 'ada@members.example')")
  (with-fresh-applications
      (("/members" 'who-is-ada :mode :deployment
                               :around-request (littoral.auth:using-user-store
                                                (littoral.auth:make-sql-user-store :table "members" :email "email"))))
    (let ((b (make-instance 'browser)))
      (visit b "/members")
      (body-text b))))
;; ⇒ "ada@members.example"
