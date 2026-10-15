;;;; The examples for littoral.db's migrations: numbered SQL files, applied once, in order.

;;;; Example: littoral.db:define-migrations littoral.db:migrate
;;; An application keeps its schema as numbered files, usually in its source tree; here they are written to a temporary directory first.  MIGRATE applies those the database lacks, and answers which it applied.
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (write-migration directory "001-notes.sql" "CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT);
INSERT INTO notes (title) VALUES ('Welcome');")
         (write-migration directory "002-notes-get-a-due-date.sql" "ALTER TABLE notes ADD COLUMN due BIGINT;")
         (littoral.db:define-migrations :example-notes directory)
         (list (littoral.db:migrate :example-notes)
               (littoral.db:migrate :example-notes)
               (littoral.db:db-query "SELECT * FROM notes")))
    (littoral.db:forget-migrations :example-notes)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (((:EXAMPLE-NOTES 1 "001-notes.sql") (:EXAMPLE-NOTES 2 "002-notes-get-a-due-date.sql")) NIL ((:|id| 1 :|title| "Welcome" :|due| NIL)))

;;;; Example: littoral.db:define-migrations
;;; A file named NNN-description.sqlite.sql or .postgres.sql replaces NNN-description.sql on that driver.  A file whose first comment says "-- littoral: one statement" runs whole, for a statement with semicolons inside, such as a SQLite trigger.  (On PostgreSQL this set would need a 002-touch.postgres.sql too.)
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-2/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (write-migration directory "001-pages.sql" "CREATE TABLE pages (id SERIAL PRIMARY KEY, title TEXT, changed BIGINT);")
         (write-migration directory "001-pages.sqlite.sql" "CREATE TABLE pages (id INTEGER PRIMARY KEY, title TEXT, changed BIGINT);")
         (write-migration directory "002-touch.sqlite.sql" "-- littoral: one statement
CREATE TRIGGER pages_touch AFTER UPDATE OF title ON pages BEGIN
  UPDATE pages SET changed = 1 WHERE id = new.id;
END;")
         (littoral.db:define-migrations :example-pages directory)
         (littoral.db:migrate :example-pages)
         (littoral.db:db-execute "INSERT INTO pages (title) VALUES ('Home')")
         (littoral.db:db-execute "UPDATE pages SET title = 'Start'")
         (littoral.db:db-query "SELECT title, changed FROM pages"))
    (littoral.db:forget-migrations :example-pages)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ((:|title| "Start" :|changed| 1))

;;;; Example: littoral.db:migration-status
;;; Each migration of a set, with when it was applied (a universal time) or NIL while it waits.
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-3/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (flet ((status ()
                (mapcar (lambda (m) (list (getf m :version) (getf m :name) (integerp (getf m :applied))))
                        (littoral.db:migration-status :example-shop))))
         (write-migration directory "001-products.sql" "CREATE TABLE products (name TEXT);")
         (littoral.db:define-migrations :example-shop directory)
         (let ((before (status)))
           (littoral.db:migrate :example-shop)
           (write-migration directory "002-prices.sql" "ALTER TABLE products ADD COLUMN price BIGINT;")
           (list before (status))))
    (littoral.db:forget-migrations :example-shop)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (((1 "products" NIL)) ((1 "products" T) (2 "prices" NIL)))

;;;; Example: littoral.db:baseline-migrations
;;; A database made before the application had migrations already has the tables of the first ones: record those as applied, and MIGRATE runs only the rest.
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-4/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (littoral.db:db-execute "CREATE TABLE members (name TEXT)")   ; made by hand, long ago
         (write-migration directory "001-members.sql" "CREATE TABLE members (name TEXT);")
         (write-migration directory "002-emails.sql" "ALTER TABLE members ADD COLUMN email TEXT;")
         (littoral.db:define-migrations :example-club directory)
         (littoral.db:baseline-migrations :example-club :through 1)
         (littoral.db:migrate :example-club))
    (littoral.db:forget-migrations :example-club)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ((:EXAMPLE-CLUB 2 "002-emails.sql"))

;;;; Example: littoral.db:forget-migrations
;;; After dropping a set's tables, forgetting its migrations lets MIGRATE make them again.
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-5/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (write-migration directory "001-scores.sql" "CREATE TABLE scores (n INTEGER);")
         (littoral.db:define-migrations :example-game directory)
         (littoral.db:migrate :example-game)
         (littoral.db:db-execute "DROP TABLE scores")
         (littoral.db:forget-migrations :example-game)
         (littoral.db:migrate :example-game))
    (littoral.db:forget-migrations :example-game)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ((:EXAMPLE-GAME 1 "001-scores.sql"))

;;;; Example: littoral.db:migration-error
;;; A migration that fails is rolled back whole, and later ones aren't tried; those before it stay applied.
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-6/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (write-migration directory "001-tags.sql" "CREATE TABLE tags (tag TEXT);")
         (write-migration directory "002-broken.sql" "CREATE TABLE tag_counts (tag TEXT, n INTEGER);
INSERT INTO no_such_table VALUES (1);")
         (write-migration directory "003-later.sql" "CREATE TABLE later (x TEXT);")
         (littoral.db:define-migrations :example-tags directory)
         (list (handler-case (littoral.db:migrate :example-tags)
                 (littoral.db:migration-error () :failed))
               (mapcar (lambda (row) (getf row :|name|))
                       (littoral.db:db-query "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('tags', 'tag_counts', 'later')"))
               (mapcar (lambda (m) (getf m :version))
                       (remove nil (littoral.db:migration-status :example-tags) :key (lambda (m) (getf m :applied))))))
    (littoral.db:forget-migrations :example-tags)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (:FAILED ("tags") (1))

;;;; Example: littoral.db:migration-changed
;;; Editing a migration after it was applied changes nothing in the database; MIGRATE warns instead.  Put the change in a new file.
(defun write-migration (directory name text)
  (alexandria:write-string-into-file text (merge-pathnames name directory) :if-exists :supersede))
(let ((directory (merge-pathnames "littoral-example-migrations-7/" (uiop:temporary-directory)))
      (littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (warnings '()))
  (ensure-directories-exist directory)
  (unwind-protect
       (progn
         (write-migration directory "001-events.sql" "CREATE TABLE events (what TEXT);")
         (littoral.db:define-migrations :example-events directory)
         (littoral.db:migrate :example-events)
         (write-migration directory "001-events.sql" "CREATE TABLE events (what TEXT, happened BIGINT);")
         (handler-bind ((littoral.db:migration-changed
                          (lambda (w) (push (princ-to-string w) warnings) (muffle-warning w))))
           (littoral.db:migrate :example-events))
         warnings)
    (littoral.db:forget-migrations :example-events)
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ("Migration 001-events.sql of example-events was changed after it was applied; the change won't be applied. Put it in a new migration instead.")
