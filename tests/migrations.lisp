;;;; migrations.lisp — numbered SQL files, applied once, in order, under a lock

(in-package #:littoral/tests)

(def-suite migrations :in littoral)
(in-suite migrations)

(defun write-migration-files (directory files)
  "Write FILES, (NAME . TEXT) pairs, into DIRECTORY, emptied first."
  (ensure-directories-exist directory)
  (dolist (old (directory (merge-pathnames "*.sql" directory)))
    (delete-file old))
  (loop for (name . text) in files
        do (with-open-file (out (merge-pathnames name directory) :direction :output :if-exists :supersede
                                                                 :external-format :utf-8)
             (write-string text out))))

(defun drop-test-tables ()
  (dolist (table '("mig_notes" "mig_tags" "mig_count" "mig_dialect"))
    (littoral.db:db-execute (format nil "DROP TABLE IF EXISTS ~A" table))))

(defmacro with-migrations ((directory files) &body body)
  "A migration set :TEST-MIGRATIONS of FILES, in DIRECTORY, over the test database."
  `(let ((,directory (uiop:ensure-directory-pathname
                      (merge-pathnames (format nil "littoral-migrations-~36R" (random (expt 36 8)))
                                       (uiop:temporary-directory)))))
     (unwind-protect
          (progn
            (connect-test-database)
            (drop-test-tables)
            (write-migration-files ,directory ,files)
            (littoral.db:define-migrations :test-migrations ,directory)
            (littoral.db:forget-migrations :test-migrations)
            ,@body)
       (ignore-errors (drop-test-tables))
       (setf littoral.db::*migration-sets*
             (remove :test-migrations littoral.db::*migration-sets* :key #'littoral.db::migration-set-name))
       (uiop:delete-directory-tree ,directory :validate t :if-does-not-exist :ignore))))

(defun table-columns (table)
  "TABLE's columns, by asking for no rows."
  (if (postgres-test-p)
      (mapcar (lambda (row) (getf row :|column_name|))
              (littoral.db:db-query "SELECT column_name FROM information_schema.columns WHERE table_name = ? ORDER BY ordinal_position" table))
      (mapcar (lambda (row) (getf row :|name|))
              (littoral.db:db-query (format nil "PRAGMA table_info(~A)" table)))))

(test splitting-sql-statements
  (is (equal '("CREATE TABLE a (x TEXT DEFAULT 'semi;colon')"
               "-- a comment; with a semicolon
INSERT INTO a VALUES ('it''s; fine')"
               "CREATE FUNCTION f() RETURNS int AS $body$ BEGIN RETURN 1; END; $body$ LANGUAGE plpgsql"
               "SELECT \"odd;name\" FROM a /* block; comment */")
             (littoral.db::split-sql-statements
              "CREATE TABLE a (x TEXT DEFAULT 'semi;colon');
-- a comment; with a semicolon
INSERT INTO a VALUES ('it''s; fine');
CREATE FUNCTION f() RETURNS int AS $body$ BEGIN RETURN 1; END; $body$ LANGUAGE plpgsql;
SELECT \"odd;name\" FROM a /* block; comment */;
-- only a comment at the end;
")))
  (is (littoral.db::migration-header-p (format nil "-- What this does~%-- littoral: one statement~%CREATE…") "one statement"))
  (is (not (littoral.db::migration-header-p (format nil "CREATE…~%-- littoral: one statement") "one statement"))
      "Only in the leading comments"))

(test migrations-apply-in-order-once
  (with-migrations (directory '(("001-notes.sql" . "CREATE TABLE mig_notes (id INTEGER, title TEXT);
INSERT INTO mig_notes VALUES (1, 'first');")
                                ("005-tags.sql" . "CREATE TABLE mig_tags (note INTEGER, tag TEXT);")
                                ("002-due-dates.sql" . "ALTER TABLE mig_notes ADD COLUMN due BIGINT;")))
    (is (equal '(nil nil nil) (mapcar (lambda (m) (getf m :applied)) (littoral.db:migration-status :test-migrations))))
    (is (equal '((:test-migrations 1 "001-notes.sql") (:test-migrations 2 "002-due-dates.sql")
                 (:test-migrations 5 "005-tags.sql"))
               (littoral.db:migrate :test-migrations)))
    (is (equal '("id" "title" "due") (table-columns "mig_notes")))
    (is (null (littoral.db:migrate :test-migrations)) "Nothing left to do")
    (is (every (lambda (m) (integerp (getf m :applied))) (littoral.db:migration-status :test-migrations)))
    (is (equal '("notes" "due-dates" "tags") (mapcar (lambda (m) (getf m :name)) (littoral.db:migration-status :test-migrations))))
    ;; A new file is applied next time, and only it.
    (write-migration-files directory '(("001-notes.sql" . "CREATE TABLE mig_notes (id INTEGER, title TEXT);
INSERT INTO mig_notes VALUES (1, 'first');")
                                       ("005-tags.sql" . "CREATE TABLE mig_tags (note INTEGER, tag TEXT);")
                                       ("002-due-dates.sql" . "ALTER TABLE mig_notes ADD COLUMN due BIGINT;")
                                       ("006-more.sql" . "INSERT INTO mig_notes VALUES (2, 'second', NULL);")))
    (is (equal '((:test-migrations 6 "006-more.sql")) (littoral.db:migrate :test-migrations)))
    (is (= 2 (getf (first (littoral.db:db-query "SELECT COUNT(*) AS n FROM mig_notes")) :|n|)))))

(test migration-files-are-checked
  (with-migrations (directory '(("001-a.sql" . "SELECT 1;") ("001-b.sql" . "SELECT 2;")))
    (signals error (littoral.db:migrate :test-migrations) "Two migrations numbered 1"))
  (with-migrations (directory '(("one.sql" . "SELECT 1;")))
    (signals error (littoral.db:migrate :test-migrations) "Badly named"))
  (signals error (littoral.db:define-migrations :nowhere #p"/no/such/directory/"))
  (signals error (littoral.db:migrate :never-defined)))

(test migrations-pick-their-driver
  (with-migrations (directory '(("001-dialect.sql" . "CREATE TABLE mig_dialect (generic TEXT);")
                                ("001-dialect.sqlite.sql" . "CREATE TABLE mig_dialect (sqlite TEXT);")
                                ("001-dialect.postgres.sql" . "CREATE TABLE mig_dialect (postgres TEXT);")))
    (littoral.db:migrate :test-migrations)
    (is (equal (if (postgres-test-p) '("postgres") '("sqlite")) (table-columns "mig_dialect"))))
  (with-migrations (directory (list (cons (if (postgres-test-p) "001-x.sqlite.sql" "001-x.postgres.sql") "SELECT 1;")))
    (signals error (littoral.db:migrate :test-migrations) "Only the other driver's version")))

(test failed-migrations-leave-nothing-behind
  (with-migrations (directory '(("001-notes.sql" . "CREATE TABLE mig_notes (id INTEGER);")
                                ("002-broken.sql" . "CREATE TABLE mig_tags (tag TEXT);
INSERT INTO no_such_table VALUES (1);")
                                ("003-later.sql" . "CREATE TABLE mig_count (n INTEGER);")))
    (let ((condition (handler-case (progn (littoral.db:migrate :test-migrations) nil)
                       (littoral.db:migration-error (e) e))))
      (is (not (null condition)))
      (when condition
        (is (string= "002-broken.sql" (littoral.db::migration-error-file condition)))
        (is (search "no_such_table" (princ-to-string condition)))))
    (is (equal '("id") (table-columns "mig_notes")) "The first stays applied")
    (is (null (table-columns "mig_tags")) "The failing one is rolled back whole")
    (is (null (table-columns "mig_count")) "Later ones aren't tried")
    (is (equal '(1) (mapcar (lambda (m) (getf m :version))
                            (remove nil (littoral.db:migration-status :test-migrations) :key (lambda (m) (getf m :applied))))))))

(test changed-migrations-warn
  (with-migrations (directory '(("001-notes.sql" . "CREATE TABLE mig_notes (id INTEGER);")))
    (littoral.db:migrate :test-migrations)
    (write-migration-files directory '(("001-notes.sql" . "CREATE TABLE mig_notes (id INTEGER, extra TEXT);")))
    (signals littoral.db:migration-changed (littoral.db:migrate :test-migrations))
    (is (equal '("id") (table-columns "mig_notes")) "Not applied again")))

(test baselining-migrations
  (with-migrations (directory '(("001-notes.sql" . "CREATE TABLE mig_notes (id INTEGER);")
                                ("002-tags.sql" . "CREATE TABLE mig_tags (tag TEXT);")))
    ;; The table exists already, made before migrations.
    (littoral.db:db-execute "CREATE TABLE mig_notes (id INTEGER)")
    (littoral.db:baseline-migrations :test-migrations :through 1)
    (is (equal '((:test-migrations 2 "002-tags.sql")) (littoral.db:migrate :test-migrations)))))

(test migrations-without-a-transaction-or-splitting
  (with-migrations (directory `(("001-notes.sql" . ,(format nil "-- littoral: no transaction~%CREATE TABLE mig_notes (id INTEGER);"))
                                ("002-trigger.sqlite.sql" . ,(format nil "-- littoral: one statement
CREATE TRIGGER mig_trigger AFTER INSERT ON mig_notes BEGIN UPDATE mig_notes SET id = id + 100; END;"))
                                ("002-trigger.postgres.sql" . "CREATE TABLE mig_tags (tag TEXT);")))
    (is (= 2 (length (littoral.db:migrate :test-migrations))))))

(test migrating-from-two-threads
  ;; Each thread has its own connection, so this uses a SQLite file.
  (let* ((file (merge-pathnames (format nil "littoral-migrate-~36R.sqlite3" (random (expt 36 8)))
                                (uiop:temporary-directory)))
         (spec (list :sqlite3 :database-name (namestring file)))
         (directory (uiop:ensure-directory-pathname
                     (merge-pathnames (format nil "littoral-migrations-~36R" (random (expt 36 8)))
                                      (uiop:temporary-directory)))))
    (unwind-protect
         (progn
           (write-migration-files directory (loop for i from 1 to 8
                                                  collect (cons (format nil "~3,'0D-step.sql" i)
                                                                (if (= i 1)
                                                                    "CREATE TABLE mig_count (step INTEGER);"
                                                                    (format nil "INSERT INTO mig_count VALUES (~D);" i)))))
           (littoral.db:define-migrations :test-migrations directory)
           (let* ((errors '())
                  (threads (loop repeat 3
                                 collect (sb-thread:make-thread
                                          (lambda ()
                                            (let ((littoral.db:*database* spec))
                                              (handler-case (littoral.db:migrate :test-migrations)
                                                (error (e) (push e errors)))))))))
             (mapc #'sb-thread:join-thread threads)
             (is (null errors))
             (let ((littoral.db:*database* spec))
               (is (equal '(2 3 4 5 6 7 8)
                          (mapcar (lambda (row) (getf row :|step|))
                                  (littoral.db:db-query "SELECT step FROM mig_count ORDER BY step")))
                   "Each applied once"))))
      (setf littoral.db::*migration-sets*
            (remove :test-migrations littoral.db::*migration-sets* :key #'littoral.db::migration-set-name))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore)
      (ignore-errors (delete-file file)))))

(test littorals-tables-adopt-migrations
  (connect-test-database)
  (littoral.auth:drop-auth-tables)
  (littoral.mail:drop-mail-tables)
  (littoral.jobs:drop-job-tables)
  (littoral.db:db-execute "DELETE FROM schema_migrations")
  ;; Tables made the way earlier versions made them, without migrations.
  (littoral.db:create-table 'littoral.auth:user)
  (littoral.db:create-table 'littoral.mail::outbox-mail)
  (littoral.auth:add-user "ada" "ada@example.org" "a long passphrase")
  (littoral.auth:create-auth-tables)
  (littoral.mail:create-mail-tables)
  (littoral.jobs:create-job-tables)
  (is (littoral.auth:find-user "ada") "Nothing lost")
  (is (equal '("littoral-audit 1" "littoral-auth 1" "littoral-auth 2" "littoral-jobs 1" "littoral-jobs 2" "littoral-mail 1" "littoral-users 1")
             (sort (mapcar (lambda (row) (format nil "~A ~D" (getf row :|component|) (getf row :|version|)))
                           (littoral.db:db-query "SELECT component, version FROM schema_migrations"))
                   #'string<))
      "Each set's migrations, the later ones too, applied to the old tables"))

(test pending-migrations-are-reported
  (with-migrations (directory '(("001-notes.sql" . "CREATE TABLE mig_notes (id INTEGER);")))
    (littoral.db:migrate :test-migrations)
    (flet ((pending ()
             (metric-value (format nil "littoral_migrations_pending{database=\"~A\",set=\"test-migrations\"}"
                                   (littoral.db:database-label)))))
      (is (eql 0 (pending)))
      (write-migration-files directory '(("001-notes.sql" . "CREATE TABLE mig_notes (id INTEGER);")
                                         ("002-tags.sql" . "CREATE TABLE mig_tags (id INTEGER);")))
      (is (= 1 (pending)))
      (littoral.db:migrate :test-migrations)
      (is (eql 0 (pending))))))
