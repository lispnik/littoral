;;;; Examples for littoral.auth: the users table, adding and finding users, checking passwords.

;;;; Example: littoral.auth:create-auth-tables littoral.auth:add-user littoral.auth:find-user
;;; Make the tables in a database, add users, and find them by name, whatever its case.  A low *PBKDF2-ITERATIONS* keeps hashing quick while trying things out.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin))
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (let ((ada (littoral.auth:find-user "ADA")))
    (list (littoral.auth:user-name ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:find-user "nobody"))))
;; ⇒ ("ada" (:ADMIN) NIL)

;;;; Example: littoral.auth:add-user
;;; Names are unique, case aside.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (handler-case (littoral.auth:add-user "Ada" "other@example.org" "a passphrase")
    (error (e) (princ-to-string e))))
;; ⇒ "The name Ada is taken."

;;;; Example: littoral.auth:user littoral.auth:user-id littoral.auth:user-name littoral.auth:user-email littoral.auth:user-roles littoral.auth:user-active-p littoral.auth:user-password-hash
;;; A user in the built-in users table.  Only the password's hash is kept.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin :editor))))
    (list (type-of ada)
          (littoral.auth:user-id ada)
          (littoral.auth:user-name ada)
          (littoral.auth:user-email ada)
          (littoral.auth:user-roles ada)
          (littoral.auth:user-active-p ada)
          (subseq (littoral.auth:user-password-hash ada) 0 19))))
;; ⇒ (LITTORAL.AUTH:USER 1 "ada" "ada@example.org" (:ADMIN :EDITOR) T "PBKDF2$SHA256:1000$")

;;;; Example: littoral.auth:find-user-by-email littoral.auth:find-user-by-id
;;; Emails match whatever their case.  An id may be given as its printed form, as cookies and tables keep it.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (list (littoral.auth:user-name (littoral.auth:find-user-by-email "ADA@example.org"))
        (littoral.auth:user-name (littoral.auth:find-user-by-id 1))
        (littoral.auth:user-name (littoral.auth:find-user-by-id "1"))
        (littoral.auth:find-user-by-id 2)))
;; ⇒ ("ada" "ada" "ada" NIL)

;;;; Example: littoral.auth:check-password littoral.auth:set-password
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")))
    (littoral.auth:set-password ada "a new passphrase")
    (list (littoral.auth:check-password ada "correct horse battery")
          (littoral.auth:check-password ada "a new passphrase"))))
;; ⇒ (NIL T)

;;;; Example: littoral.auth:authenticate
;;; The user, when the password is right; otherwise NIL and why, in words for the sign-in form.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (list (littoral.auth:user-name (littoral.auth:authenticate "ada" "correct horse battery"))
        (multiple-value-list (littoral.auth:authenticate "ada" "wrong"))
        (multiple-value-list (littoral.auth:authenticate "nobody" "wrong"))))
;; ⇒ ("ada" (NIL "Unknown user or wrong password.") (NIL "Unknown user or wrong password."))

;;;; Example: littoral.auth:*lockout-failures* littoral.auth:*lockout-seconds* littoral.auth:authenticate
;;; After *LOCKOUT-FAILURES* wrong passwords for a name, even the right one is refused until *LOCKOUT-SECONDS* pass.  Failures are kept in the database, so every process sees them.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*lockout-failures* 3)
      (littoral.auth:*lockout-seconds* 60))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (dotimes (i 3) (littoral.auth:authenticate "bob" "guess"))
  (nth-value 1 (littoral.auth:authenticate "bob" "another passphrase")))
;; ⇒ "Too many failed attempts; try again in a minute."

;;;; Example: littoral.auth:purge-expired-auth-rows
;;; Run nightly, it deletes what no longer counts, and says how many rows went.  Here, a sign-in failure from two hours ago.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:authenticate "nobody" "guess")
  (littoral.db:db-execute "UPDATE auth_events SET happened = happened - 7200")
  (list (littoral.auth:purge-expired-auth-rows)
        (littoral.auth:purge-expired-auth-rows)))
;; ⇒ (1 0)

;;;; Example: littoral.auth:drop-auth-tables
;;; For tests: drop every table CREATE-AUTH-TABLES made, users and all, then make them afresh.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")
  (littoral.auth:drop-auth-tables)
  (littoral.auth:create-auth-tables)
  (littoral.auth:find-user "ada"))
;; ⇒ NIL
