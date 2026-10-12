;;;; migrations.lisp — numbered SQL files that bring a database's schema up to date
;;;;
;;;;   migrations/001-notes.sql
;;;;   migrations/002-notes-get-a-due-date.sql
;;;;   migrations/003-search.sqlite.sql      ; this driver's version of 003
;;;;   migrations/003-search.postgres.sql
;;;;
;;;;   (define-migrations :my-app (asdf:system-relative-pathname :my-app "migrations/"))
;;;;   (migrate :my-app)
;;;;
;;;; A migration is a file NNN-description.sql; NNN.sqlite.sql or
;;;; NNN.postgres.sql replaces it on that driver.  Its statements are
;;;; separated by semicolons (outside quotes, comments and PostgreSQL's
;;;; $tag$ quoting).  A first-lines comment "-- littoral: one statement"
;;;; runs the file as it is (a SQLite trigger, say), and "-- littoral: no
;;;; transaction" runs it outside a transaction (CREATE INDEX CONCURRENTLY).
;;;;
;;;; MIGRATE applies a set's new migrations in order, each in a transaction
;;;; that also records it in schema_migrations, under a lock (PostgreSQL's
;;;; advisory lock; SQLite's write lock), so processes starting together
;;;; apply each once and a failure leaves nothing half done.  Migrations
;;;; only go forward: fix a mistake with a newer one.  The files are read
;;;; when the set is defined, so a saved executable carries them.

(in-package #:littoral.db)

(define-condition migration-error (error)
  ((set :initarg :set :reader migration-error-set)
   (file :initarg :file :reader migration-error-file)
   (statement :initarg :statement :initform nil :reader migration-error-statement)
   (cause :initarg :cause :reader migration-error-cause))
  (:report (lambda (c s)
             (format s "Migration ~A of ~(~A~) failed: ~A~@[~%In: ~A~]"
                     (migration-error-file c) (migration-error-set c) (migration-error-cause c)
                     (let ((statement (migration-error-statement c)))
                       (and statement (subseq statement 0 (min 300 (length statement))))))))
  (:documentation "A migration's statement failed; it was rolled back, and later ones weren't tried."))

(define-condition migration-changed (warning)
  ((set :initarg :set :reader migration-changed-set)
   (file :initarg :file :reader migration-changed-file))
  (:report (lambda (c s)
             (format s "Migration ~A of ~(~A~) was changed after it was applied; the change won't be applied. ~
Put it in a new migration instead." (migration-changed-file c) (migration-changed-set c))))
  (:documentation "An applied migration's file is no longer what was applied."))

;;; Sets of migrations

(defstruct (migration-set (:constructor make-migration-set (name directory files)))
  name directory files)

(defvar *migration-sets* '() "Defined migration sets, in the order defined.")

(defun read-migration-files (directory)
  "The .sql files in DIRECTORY, as (NAME . TEXT), by name."
  (sort (mapcar (lambda (path)
                  (cons (file-namestring path) (uiop:read-file-string path :external-format :utf-8)))
                (directory (merge-pathnames "*.sql" (uiop:ensure-directory-pathname directory))))
        #'string< :key #'car))

(defun define-migrations (name directory)
  "Define the migrations NAME (a keyword) as the .sql files in DIRECTORY,
read now so that an executable saved later carries them."
  (let ((directory (uiop:ensure-directory-pathname directory)))
    (unless (uiop:directory-exists-p directory)
      (error "No migrations directory ~A for ~S." directory name))
    (setf *migration-sets*
          (append (remove name *migration-sets* :key #'migration-set-name)
                  (list (make-migration-set name directory (read-migration-files directory)))))
    name))

(defun find-migration-set (name)
  (or (find name *migration-sets* :key #'migration-set-name)
      (error "No migrations named ~S: see DEFINE-MIGRATIONS." name)))

(defun component-name (name) (string-downcase (string name)))

(defstruct (migration (:constructor make-migration (version name file text)))
  version name file text)

(defun driver-suffix ()
  (ecase (driver) (:sqlite3 "sqlite") (:postgres "postgres")))

(defun set-migrations (set)
  "SET's migrations for the current database's driver, by version.  The
files are read again where the directory still exists."
  (let ((files (if (uiop:directory-exists-p (migration-set-directory set))
                   (read-migration-files (migration-set-directory set))
                   (migration-set-files set)))
        (versions (make-hash-table)))
    (dolist (file files)
      (multiple-value-bind (match groups)
          (cl-ppcre:scan-to-strings "^(\\d+)-(.+?)(?:\\.(sqlite|postgres))?\\.sql$" (car file))
        (unless match
          (error "Migration file ~A of ~(~A~) isn't named NNN-description.sql."
                 (car file) (migration-set-name set)))
        (let ((version (parse-integer (aref groups 0)))
              (key (if (aref groups 2) (intern (string-upcase (aref groups 2)) :keyword) :any)))
          (when (getf (gethash version versions) key)
            (error "Two migrations numbered ~D in ~(~A~)." version (migration-set-name set)))
          (setf (getf (gethash version versions) key)
                (make-migration version (aref groups 1) (car file) (cdr file))))))
    (sort (loop for version being the hash-keys of versions using (hash-value variants)
                collect (or (getf variants (intern (string-upcase (driver-suffix)) :keyword))
                            (getf variants :any)
                            (error "Migration ~D of ~(~A~) has no version for ~A."
                                   version (migration-set-name set) (driver-suffix))))
          #'< :key #'migration-version)))

;;; Statements

(defun split-sql-statements (text)
  "TEXT's statements, split at semicolons outside quotes, comments and
$tag$…$tag$ quoting; comments are kept, and empty statements dropped."
  (let ((statements '()) (start 0) (i 0) (n (length text)))
    (flet ((emit (end)
             (let ((statement (string-trim '(#\Space #\Tab #\Newline #\Return) (subseq text start end))))
               (when (cl-ppcre:scan "(?m)^\\s*(?!--)\\S" (cl-ppcre:regex-replace-all "(?s)/\\*.*?\\*/" statement ""))
                 (push statement statements)))))
      (loop while (< i n)
            do (let ((c (char text i)))
                 (cond ((and (char= c #\-) (< (1+ i) n) (char= (char text (1+ i)) #\-))
                        (setf i (or (position #\Newline text :start i) n)))
                       ((and (char= c #\/) (< (1+ i) n) (char= (char text (1+ i)) #\*))
                        (setf i (let ((end (search "*/" text :start2 (+ i 2)))) (if end (+ end 2) n))))
                       ((member c '(#\' #\"))
                        ;; A doubled quote stays inside: the loop just goes on.
                        (setf i (let ((end (position c text :start (1+ i)))) (if end (1+ end) n))))
                       ((and (char= c #\$) (cl-ppcre:scan "^\\$[A-Za-z_]*\\$" text :start i))
                        (let* ((tag (subseq text i (1+ (position #\$ text :start (1+ i)))))
                               (end (search tag text :start2 (+ i (length tag)))))
                          (setf i (if end (+ end (length tag)) n))))
                       ((char= c #\;)
                        (emit i)
                        (setf start (1+ i) i (1+ i)))
                       (t (incf i)))))
      (emit n))
    (nreverse statements)))

(defun migration-header-p (text option)
  "True when TEXT's leading comment lines say \"-- littoral: OPTION\"."
  (loop for line in (cl-ppcre:split "\\n" text)
        for trimmed = (string-trim '(#\Space #\Tab #\Return) line)
        while (or (string= trimmed "") (alexandria:starts-with-subseq "--" trimmed))
        thereis (cl-ppcre:scan (format nil "^--\\s*littoral:\\s*~A\\s*$" option) (string-downcase trimmed))))

(defun migration-statements (migration)
  (let ((text (migration-text migration)))
    (if (migration-header-p text "one statement")
        (list text)
        (split-sql-statements text))))

(defun checksum (text)
  (ironclad:byte-array-to-hex-string
   (ironclad:digest-sequence :sha256 (sb-ext:string-to-octets text :external-format :utf-8))))

;;; Applying

(defun ensure-migrations-table ()
  (execute-count "CREATE TABLE IF NOT EXISTS schema_migrations (component TEXT NOT NULL, version BIGINT NOT NULL,
name TEXT, checksum TEXT, applied BIGINT, PRIMARY KEY (component, version))"))

(defun applied-migrations (name)
  "NAME's applied versions → their checksums."
  (let ((table (make-hash-table)))
    (dolist (row (execute "SELECT version, checksum FROM schema_migrations WHERE component = ?"
                          (list (component-name name)))
                 table)
      (setf (gethash (row-value row "version") table) (row-value row "checksum")))))

(defun record-migration (name migration)
  (execute-count "INSERT INTO schema_migrations (component, version, name, checksum, applied) VALUES (?, ?, ?, ?, ?)"
                 (list (component-name name) (migration-version migration) (migration-name migration)
                       (checksum (migration-text migration)) (get-universal-time))))

(defparameter +migration-lock+ 7316730 "The PostgreSQL advisory lock key migrations hold.")

(defun apply-migration (name migration)
  "Apply MIGRATION of NAME unless another process just did; true if this one did."
  (let ((statements (migration-statements migration)))
    (flet ((run ()
             (when (zerop (row-value (first (execute "SELECT COUNT(*) AS n FROM schema_migrations WHERE component = ? AND version = ?"
                                                     (list (component-name name) (migration-version migration))))
                                     "n"))
               (dolist (statement statements)
                 (handler-case (execute-count statement)
                   (error (e)
                     (error 'migration-error :set name :file (migration-file migration)
                                             :statement statement :cause e))))
               (record-migration name migration)
               t)))
      (cond ((migration-header-p (migration-text migration) "no transaction")
             (if (eq (driver) :postgres)
                 (progn (execute (format nil "SELECT pg_advisory_lock(~D)" +migration-lock+))
                        (unwind-protect (run)
                          (execute (format nil "SELECT pg_advisory_unlock(~D)" +migration-lock+))))
                 (run)))
            (t
             (with-transaction ()
               (when (eq (driver) :postgres)
                 (execute (format nil "SELECT pg_advisory_xact_lock(~D)" +migration-lock+)))
               (run)))))))

(defun migrate (&rest names)
  "Apply the new migrations of each set NAMES (keywords given to
DEFINE-MIGRATIONS) to the current database, in order; the (NAME VERSION
FILE) of each applied.  Signals MIGRATION-ERROR when one fails, having
rolled it back, and MIGRATION-CHANGED (a warning) for an applied file that
has since changed."
  (ensure-migrations-table)
  (loop for name in names
        for set = (find-migration-set name)
        for applied = (applied-migrations name)
        nconc (loop for migration in (set-migrations set)
                    for done = (gethash (migration-version migration) applied)
                    if done
                      do (unless (equal done (checksum (migration-text migration)))
                           (warn 'migration-changed :set name :file (migration-file migration)))
                    else
                      when (apply-migration name migration)
                        collect (list name (migration-version migration) (migration-file migration)))))

(defun migration-status (&rest names)
  "Each migration of the sets NAMES, as plists of :SET :VERSION :NAME :FILE
and :APPLIED (a universal time, or NIL while it waits)."
  (ensure-migrations-table)
  (loop for name in names
        for times = (let ((table (make-hash-table)))
                      (dolist (row (execute "SELECT version, applied FROM schema_migrations WHERE component = ?"
                                            (list (component-name name)))
                                   table)
                        (setf (gethash (row-value row "version") table) (row-value row "applied"))))
        nconc (mapcar (lambda (migration)
                        (list :set name :version (migration-version migration) :name (migration-name migration)
                              :file (migration-file migration) :applied (gethash (migration-version migration) times)))
                      (set-migrations (find-migration-set name)))))

(defun baseline-migrations (name &key through)
  "Record NAME's migrations up to version THROUGH (all, by default) as
applied without running them, for a database that already has their tables."
  (ensure-migrations-table)
  (let ((applied (applied-migrations name)))
    (dolist (migration (set-migrations (find-migration-set name)))
      (when (and (or (null through) (<= (migration-version migration) through))
                 (not (gethash (migration-version migration) applied)))
        (record-migration name migration)))))

(defun forget-migrations (name)
  "Forget which of NAME's migrations were applied, as when its tables are dropped."
  (ensure-migrations-table)
  (execute-count "DELETE FROM schema_migrations WHERE component = ?" (list (component-name name))))
