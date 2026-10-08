;;;; auth-store.lisp — signing in against an application's own users table

(in-package #:littoral/tests)

(def-suite auth-store :in littoral)
(in-suite auth-store)

(defun make-accounts ()
  "An application's own tables: accounts with bcrypt and Werkzeug hashes,
and roles in a table of their own."
  (dolist (table '("account_roles" "accounts"))
    (littoral.db:db-execute (format nil "DROP TABLE IF EXISTS ~A" table)))
  (littoral.db:db-execute "CREATE TABLE accounts (account_id INTEGER PRIMARY KEY, login TEXT,
                           email_address TEXT, pw_hash TEXT, enabled INTEGER)")
  (littoral.db:db-execute "CREATE TABLE account_roles (account_id INTEGER, role TEXT)")
  (loop for (id login email hash enabled) in
        `((1 "ada" "ada@example.org" ,(littoral.auth:bcrypt-hash "ada's long secret" :cost 4) 1)
          (2 "bob" "bob@example.org"
             "pbkdf2:sha256:1000$seasalt1234$7550ac791a251d65e7ddd282ac996a427107369b72fe00b683aa5462d0864ffe" 1)
          (3 "carol" "carol@example.org" ,(littoral.auth:bcrypt-hash "carol's secret" :cost 4) 0))
        do (littoral.db:db-execute "INSERT INTO accounts (account_id, login, email_address, pw_hash, enabled)
                                    VALUES (?, ?, ?, ?, ?)" id login email hash enabled))
  (littoral.db:db-execute "INSERT INTO account_roles (account_id, role) VALUES (1, 'admin')"))

(defun account-store (&rest options)
  (apply #'littoral.auth:make-sql-user-store
         :table "accounts" :id "account_id" :name "login" :email "email_address"
         :password "pw_hash" :active "enabled"
         :roles-query "SELECT role FROM account_roles WHERE account_id = ?"
         options))

(defun account-hash (login)
  (getf (first (littoral.db:db-query "SELECT pw_hash FROM accounts WHERE login = ?" login)) :|pw_hash|))

(defmacro with-accounts ((b store) &body body)
  "The members app signing in against the accounts table through STORE."
  `(progn
     (connect-test-database)
     (make-accounts)
     (littoral.auth:drop-auth-tables :users nil)
     (littoral.auth:create-auth-tables :users nil)
     (clrhash littoral.auth::*failures*)
     (with-fresh-applications (("/m" 'members-app :mode :deployment
                                     :around-request (littoral.auth:using-user-store ,store)))
       (let ((littoral.auth:*public-url* "http://localhost")
             (littoral.auth:*user-store* ,store)
             (,b (make-instance 'browser)))
         (visit ,b "/m")
         ,@body))))

(test sign-in-against-your-own-table
  (let ((store (account-store :writable t)))
    (with-accounts (b store)
      (sign-in-as b "ADA" "ada's long secret")
      (is (has-text-p b "Signed in as ada"))
      ;; Roles from the roles table: ada is an admin.
      (is (has-text-p b "Admin console"))
      (click b "Sign out")
      ;; Werkzeug's hash, and a member without roles.
      (sign-in-as b "bob" "correct horse battery")
      (is (has-text-p b "Signed in as bob"))
      (is (has-text-p b "You don't have permission to see this."))
      (click b "Sign out")
      ;; Disabled accounts can't.
      (sign-in-as b "carol" "carol's secret")
      (is (has-text-p b "Unknown user or wrong password.")))))

(test signing-in-upgrades-old-hashes-when-writable
  (let ((store (account-store :writable t)))
    (with-accounts (b store)
      (is (alexandria:starts-with-subseq "$2b$" (account-hash "ada")))
      (sign-in-as b "ada" "ada's long secret")
      (is (alexandria:starts-with-subseq "PBKDF2$" (account-hash "ada")))
      (is (littoral.auth:verify-password "ada's long secret" (account-hash "ada")))))
  (let ((store (account-store)))           ; read-only
    (with-accounts (b store)
      (let ((before (account-hash "ada")))
        (sign-in-as b "ada" "ada's long secret")
        (is (has-text-p b "Signed in as ada"))
        (is (string= before (account-hash "ada")))))))

(test resetting-a-password-in-your-own-table
  (let ((littoral.auth:*send-mail* (lambda (to subject body) (declare (ignore to subject body))))
        (store (account-store :writable t)))
    (with-accounts (b store)
      (setf littoral.auth:*last-mail* nil)
      (click b "Sign in")
      (click b "Forgot your password?")
      (fill-in b "reset-email" "Bob@Example.org")
      (press b "Send me a link")
      (let* ((body (third littoral.auth:*last-mail*))
             (link (cl-ppcre:scan-to-strings "/m/reset\\?token=[A-Za-z0-9]+" body))
             (other (make-instance 'browser)))
        (is (not (null link)))
        (visit other link)
        (fill-in other "new-password" "a whole new phrase")
        (fill-in other "new-password-again" "a whole new phrase")
        (press other "Save and sign in")
        (is (has-text-p other "Signed in as bob"))
        (is (littoral.auth:verify-password "a whole new phrase" (account-hash "bob")))
        ;; The link is spent.
        (let ((again (make-instance 'browser)))
          (visit again link)
          (is (has-text-p again "That link has expired or been used")))))))

(test a-custom-verify-function
  (let ((store (account-store :verify (lambda (password hash)
                                        (declare (ignore hash))
                                        (string= password "open sesame")))))
    (with-accounts (b store)
      (sign-in-as b "bob" "correct horse battery")
      (is (has-text-p b "Unknown user or wrong password."))
      (sign-in-as b "bob" "open sesame")
      (is (has-text-p b "Signed in as bob")))))

(test stores-create-users-only-when-allowed
  (let ((closed (account-store)) (open (account-store :create t)))
    (with-accounts (b closed)
      (is (search "Not signed in" (browser-html b)))
      (is (null (littoral.auth:store-create-user closed :name "dave" :email "dave@example.org")))
      (let ((dave (littoral.auth:store-create-user open :name "dave" :email "dave@example.org")))
        (is (string= "dave" (littoral.auth:user-name dave)))
        (is (string= "dave@example.org" (littoral.auth:user-email dave)))))))

(test store-names-are-checked
  (signals error (littoral.auth:make-sql-user-store :table "accounts; DROP TABLE x"))
  (signals error (littoral.auth:make-sql-user-store :table "accounts" :name "login--"))
  (signals error (littoral.auth:store-set-password-hash (account-store) nil "hash")))

(test granted-roles-add-to-a-stores-own
  (let ((store (account-store)))
    (with-accounts (b store)
      (let ((bob (littoral.auth:find-user "bob")))
        (is (null (littoral.auth:user-roles bob)))
        (littoral.auth:grant-role bob :editor)
        (is (equal '(:editor) (littoral.auth:user-roles bob)))
        (is (equal '(:admin) (littoral.auth:user-roles (littoral.auth:find-user "ada"))))))))
