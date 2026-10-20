;;;; db.lisp — objects described once, kept in a SQL database
;;;;
;;;; A table is a description plus a name.  Each field becomes a column; each
;;;; object also has an ID and a VERSION, from the PERSISTENT mixin.
;;;;
;;;;   (defclass contact (persistent) ((name …) (email …)))
;;;;   (define-description contact ((name :required t) (email :type :email)))
;;;;   (define-table contact)                 ; table "contact"
;;;;
;;;;   (connect-database :sqlite3 :database-name "app.db")
;;;;   (create-table 'contact)
;;;;   (db-save (make-instance 'contact :name "Ada" :email "ada@example.org"))
;;;;   (db-select 'contact :where "name LIKE ?" :params '("A%") :order-by "name")
;;;;
;;;; The data lives in the database; components hold only what the user is
;;;; looking at.  Updates check VERSION, so saving an object someone else
;;;; changed since it was read signals STALE-OBJECT instead of overwriting
;;;; their change.  (register-application … :around-actions (transactional))
;;;; runs each request's callbacks in one transaction, rolled back if one
;;;; of them signals.
;;;;
;;;; Built on cl-dbi; tested with SQLite and PostgreSQL.  Integers are BIGINT
;;;; (SQLite's integers are 64-bit anyway).  Names are unquoted: avoid
;;;; reserved words such as USER and ORDER for tables and columns.

(defpackage #:littoral.db
  (:use #:cl #:littoral #:littoral.html)
  (:documentation "Load with `(asdf:load-system :littoral/db)` and a cl-dbi driver, such as
`:dbd-sqlite3` or `:dbd-postgres`.  Keeps described objects in a SQL database
(SQLite or PostgreSQL): tables, queries, full-text search, transactions,
optimistic locking and migrations.")
  (:export #:connect-database #:disconnect-database #:database-connection #:*database*
           #:*sqlite-busy-timeout* #:*sqlite-journal-mode* #:*sqlite-synchronous* #:database-label
           #:persistent #:object-id #:object-version
           #:define-table #:find-table #:table-name #:table-class #:create-table #:drop-table
           #:db-find #:db-select #:db-count #:db-insert #:db-update #:db-save #:db-delete
           #:db-reload #:db-query #:db-execute #:db-search #:search-condition #:highlight-matches #:with-transaction #:transactional #:after-commit #:using-database
           #:stale-object #:stale-object-object
           #:reference-field #:reference-class #:object-label #:sql-type #:to-sql #:from-sql
           ;; Migrations
           #:define-migrations #:migrate #:migration-status #:baseline-migrations #:forget-migrations
           #:migration-error #:migration-changed))

(in-package #:littoral.db)

;;; Connections

(defvar *database* nil
  "The arguments of the last CONNECT-DATABASE: a driver keyword and its
connection parameters, as cl-dbi's CONNECT takes them; NIL for none.  Binding it
uses another database for a while (see also USING-DATABASE).")

(defun connect-database (driver &rest parameters)
  "Use the database DRIVER (:sqlite3, :postgres) reaches with PARAMETERS,
as cl-dbi's CONNECT takes them (:DATABASE-NAME, and :HOST, :PORT, :USERNAME and
:PASSWORD for PostgreSQL).  For SQLite, PARAMETERS may also give
:BUSY-TIMEOUT, :JOURNAL-MODE and :SYNCHRONOUS (see *SQLITE-BUSY-TIMEOUT*,
*SQLITE-JOURNAL-MODE* and *SQLITE-SYNCHRONOUS*).
Sets *DATABASE*, for every thread that doesn't bind it, and returns this
thread's connection.  Each thread gets its own connection, made when first
needed."
  (setf *database* (cons driver parameters))
  (database-connection))

(defvar *sqlite-busy-timeout* 5000
  "Milliseconds a SQLite connection waits for another's lock before giving up,
unless the database spec gives :BUSY-TIMEOUT.  Threads (requests, mail
delivery) each have a connection, and SQLite allows one writer at a time.")

(defvar *sqlite-journal-mode* :wal
  "The journal mode Littoral sets on a SQLite database file when it first
connects, unless the database spec gives :JOURNAL-MODE: :WAL (write-ahead
logging, so readers and the writer don't wait for each other), another of
SQLite's modes such as :DELETE, or NIL to leave the file as it is.  The
mode is kept in the file.")

(defvar *sqlite-synchronous* :normal
  "How hard SQLite connections make sure commits reach the disk, unless the
database spec gives :SYNCHRONOUS: :NORMAL (with WAL, a power cut may lose
the last commits but never corrupts the file), :FULL, or NIL for SQLite's
default.")

(defun sqlite-option (spec key default)
  "SPEC's KEY, or DEFAULT when SPEC doesn't give it."
  (let ((value (getf (rest spec) key '%none)))
    (if (eq value '%none) default value)))

(defun connection-arguments (spec)
  "SPEC as DBI:CONNECT takes it: for SQLite, without Littoral's own options
and with the busy timeout."
  (if (eq (first spec) :sqlite3)
      (let ((parameters (alexandria:remove-from-plist (rest spec) :journal-mode :synchronous)))
        (cons :sqlite3 (if (and (not (getf parameters :busy-timeout)) *sqlite-busy-timeout*)
                           (append parameters (list :busy-timeout *sqlite-busy-timeout*))
                           parameters)))
      spec))

(defun pragma-value (value allowed)
  "VALUE, one of ALLOWED, as a pragma's argument."
  (unless (member value allowed)
    (error "~S is not one of ~{~S~^, ~}." value allowed))
  (string-upcase (symbol-name value)))

(defvar *journal-mode-lock* (sb-thread:make-mutex :name "littoral sqlite journal mode"))

(defun prepare-sqlite-connection (connection spec)
  "Set SPEC's journal mode and synchronous level on a new CONNECTION."
  (flet ((pragma (sql)
           (let ((query (dbi:prepare connection sql)))
             (unwind-protect (second (first (dbi:fetch-all (dbi:execute query))))
               (dbi:free-query-resources query)))))
    (let ((mode (sqlite-option spec :journal-mode *sqlite-journal-mode*))
          (synchronous (sqlite-option spec :synchronous *sqlite-synchronous*)))
      (when mode
        (let ((wanted (pragma-value mode '(:wal :delete :truncate :persist :memory :off))))
          ;; Changing the mode needs the file to itself, and the mode is kept
          ;; in the file, so only the first connection changes it; one that
          ;; loses the race to another process finds it changed.
          (sb-thread:with-mutex (*journal-mode-lock*)
            (flet ((current () (princ-to-string (pragma "PRAGMA journal_mode"))))
              (unless (or (string-equal (current) wanted)
                          (string-equal "memory" (current)))
                (handler-case (pragma (format nil "PRAGMA journal_mode = ~A" wanted))
                  (error (e)
                    (unless (string-equal (current) wanted)
                      (warn "Couldn't set the SQLite journal mode to ~A: ~A" wanted e)))))))))
      (when synchronous
        (pragma (format nil "PRAGMA synchronous = ~A"
                        (pragma-value synchronous '(:off :normal :full :extra))))))))

(defvar *prepared-connections* (make-hash-table :test 'eq :weakness :key :synchronized t)
  "SQLite connections whose pragmas are set.")

(defun database-connection ()
  "This thread's connection to *DATABASE*, made the first time it is
needed.  Signals an error when *DATABASE* is NIL."
  (unless *database*
    (error "No database: call CONNECT-DATABASE first."))
  (let ((connection (apply #'dbi:connect-cached (connection-arguments *database*))))
    (when (and (eq (first *database*) :sqlite3)
               (not (gethash connection *prepared-connections*)))
      (prepare-sqlite-connection connection *database*)
      (note-sqlite-file *database*)
      (setf (gethash connection *prepared-connections*) t))
    connection))

;;; SQLite files' sizes, for /metrics

(defvar *sqlite-files* '() "The SQLite database files this process has connected to.")
(defvar *sqlite-files-lock* (sb-thread:make-mutex :name "littoral sqlite files"))

(defun note-sqlite-file (spec)
  "Remember SPEC's file for /metrics, unless it's in memory."
  (let ((name (getf (rest spec) :database-name)))
    (when (and name (not (member (princ-to-string name) '(":memory:" "") :test #'string=)))
      (sb-thread:with-mutex (*sqlite-files-lock*)
        (pushnew (princ-to-string name) *sqlite-files* :test #'string=)))))

(defun file-bytes (file)
  "FILE's size in bytes, or NIL when it doesn't exist."
  (ignore-errors (with-open-file (in file :element-type '(unsigned-byte 8) :if-does-not-exist nil)
                   (and in (file-length in)))))

(defun write-sqlite-metrics (out)
  "Write the size of each SQLite database file, and of its write-ahead log, to OUT."
  (format out "# HELP littoral_sqlite_bytes Size of each SQLite database's files: the database and its ~
write-ahead log.~%~
# TYPE littoral_sqlite_bytes gauge~%")
  (dolist (name (sort (sb-thread:with-mutex (*sqlite-files-lock*) (copy-list *sqlite-files*)) #'string<))
    (let ((database (file-bytes name)))
      (when database
        (format out "littoral_sqlite_bytes{database=\"~A\",file=\"database\"} ~D~%" (metric-label name) database)
        (format out "littoral_sqlite_bytes{database=\"~A\",file=\"wal\"} ~D~%" (metric-label name)
                (or (file-bytes (concatenate 'string name "-wal")) 0))))))

(add-metrics-source "sqlite" 'write-sqlite-metrics)

(defun database-label (&optional (spec *database*))
  "SPEC named for logs and metrics, without credentials: a SQLite file's
name, or a PostgreSQL server's host, port and database."
  (let ((parameters (rest spec)))
    (if (eq (first spec) :sqlite3)
        (princ-to-string (getf parameters :database-name))
        (format nil "~(~A~)://~A~@[:~A~]/~A" (first spec) (or (getf parameters :host) "localhost")
                (getf parameters :port) (getf parameters :database-name)))))

(defun disconnect-database ()
  "Forget the database: *DATABASE* becomes NIL.  Connections already made
stay open until their threads end (DBI closes them when it next connects)."
  (setf *database* nil))

(defun driver ()
  "The database's driver keyword."
  (first *database*))

;;; Persistent objects

(defclass persistent ()
  ((id :initarg :id :initform nil :accessor object-id
       :documentation "The row's key, or NIL until the object is first saved.")
   (version :initarg :version :initform 0 :accessor object-version
            :documentation "Incremented by every update; how conflicting saves are noticed."))
  (:documentation "Mixin for objects kept in a table."))

(define-condition stale-object (littoral:edit-conflict)
  ((object :initarg :object :reader stale-object-object
           :documentation "The object whose save or delete was refused."))
  (:report (lambda (condition stream)
             (format stream "~A was changed or deleted by someone else since it was read."
                     (stale-object-object condition))))
  (:documentation "Signalled when saving or deleting an object whose row has
changed (or gone) since the object was read.  It is an EDIT-CONFLICT, so
in-place editors and data grids report it rather than failing."))

(setf (documentation 'stale-object-object 'function)
      "The object whose save or delete STALE-OBJECT refused.")

;;; Tables

(defclass table ()
  ((class :initarg :class :reader table-class)
   (name :initarg :name :reader table-name)
   (description :initarg :description :reader table-description)
   (search :initarg :search :initform '() :reader table-search-fields
           :documentation "Names of the fields kept in the full-text index, or NIL."))
  (:documentation "How a class's objects are stored."))

(defvar *tables* (make-hash-table) "Class name → TABLE.")

(defun sql-name (symbol)
  "SYMBOL as a SQL identifier: lower case, underscores for dashes."
  (substitute #\_ #\- (string-downcase (symbol-name symbol))))

(defmacro define-table (class &key name description search)
  "Keep objects of CLASS (a PERSISTENT class) in the table NAME (a string;
by default the class name, lower case, with underscores for dashes), with a
column for each field of the description DESCRIPTION names (by default
CLASS), which must be defined first.  SEARCH names text fields to keep in a
full-text index, for DB-SEARCH.  CREATE-TABLE makes the table."
  `(setf (gethash ',class *tables*)
         (make-instance 'table :class ',class
                               :name ,(or name (sql-name class))
                               :description (find-description ',(or description class))
                               :search ',search)))

(defun find-table (designator)
  "The table of DESIGNATOR, a class name or an object.  Signals an error
when DEFINE-TABLE hasn't defined one."
  (or (gethash (if (symbolp designator) designator (class-name (class-of designator))) *tables*)
      (error "No table for ~S: use DEFINE-TABLE." designator)))

(defun table-fields (table)
  "The fields of TABLE's description: its columns, besides id and version."
  (description-fields (table-description table)))

(defun column-name (field)
  "FIELD's column name."
  (sql-name (field-name field)))

;;; Values

(defgeneric sql-type (field)
  (:documentation "The column type that holds FIELD's values.")
  (:method ((field field)) "TEXT")
  (:method ((field integer-field)) "BIGINT")
  (:method ((field boolean-field)) "INTEGER")
  (:method ((field rating-field)) "INTEGER"))

(defun choice-sql-text (choice)
  "How a choice is written to its column: a symbol by its name."
  (if (symbolp choice) (symbol-name choice) (princ-to-string choice)))

(defgeneric to-sql (field value)
  (:documentation "VALUE as it is written to FIELD's column.")
  (:method ((field field) value) value)
  (:method ((field boolean-field) value) (if value 1 0))
  (:method ((field date-field) value) (and value (format-field field value)))
  ;; Times, date ranges and tags are kept as they are written.
  (:method ((field littoral::time-field) value) (and value (format-field field value)))
  (:method ((field littoral::date-range-field) value) (and value (format-field field value)))
  (:method ((field littoral::tags-field) value) (format-field field value))
  (:method ((field choice-field) value)
    (and value (choice-sql-text value)))
  ;; Several choices, each written as a single one is, one to a line.
  (:method ((field multiple-choice-field) value)
    (and value (format nil "~{~A~^~%~}" (mapcar #'choice-sql-text value)))))

(defgeneric from-sql (field value)
  (:documentation "The value FIELD holds, from what its column held.")
  (:method ((field field) value) (if (eq value :null) nil value))
  (:method ((field boolean-field) value) (and value (not (eq value :null)) (/= value 0)))
  (:method ((field date-field) value)
    (and value (not (eq value :null)) (parse-field field value)))
  (:method ((field littoral::time-field) value)
    (and value (not (eq value :null)) (parse-field field value)))
  (:method ((field littoral::date-range-field) value)
    (and value (not (eq value :null)) (parse-field field value)))
  (:method ((field littoral::tags-field) value)
    (and value (not (eq value :null)) (parse-field field value)))
  (:method ((field choice-field) value)
    (and value (not (eq value :null))
         (find value (field-choices field) :key #'choice-sql-text :test #'string=)))
  (:method ((field multiple-choice-field) value)
    (and value (not (eq value :null))
         (let ((names (cl-ppcre:split "\\r?\\n" value)))
           (remove-if-not (lambda (choice) (member (choice-sql-text choice) names :test #'string=))
                          (field-choices field))))))

;;; References between tables

(defclass reference-field (choice-field)
  ((to :initarg :to :reader reference-class
       :documentation "The class of the objects referred to."))
  (:documentation "Another stored object, chosen from its table; kept as its id."))

(defmethod initialize-instance :after ((field reference-field) &key to)
  (setf (slot-value field 'littoral::choices) (lambda () (db-select to))))

(defmethod format-field ((field reference-field) value)
  (if (null value) "" (object-label value)))

(defmethod to-sql ((field reference-field) value)
  (and value (object-id value)))

(defmethod from-sql ((field reference-field) value)
  (and value (not (eq value :null)) (db-find (reference-class field) value)))

(defmethod sql-type ((field reference-field)) "BIGINT")

(defun object-label (object)
  "How OBJECT is named in choices and links: the value of its first string
field, or \"#ID\" when it has none or that value is NIL."
  (let* ((table (find-table object))
         (field (find-if (lambda (f) (typep f 'string-field)) (description-fields (table-description table)))))
    (if field
        (or (field-value field object) (format nil "#~D" (object-id object)))
        (format nil "#~D" (object-id object)))))

(push '(:reference . reference-field) *field-kinds*)

;;; Statements

(defun sql-parameters (parameters)
  "PARAMETERS as the driver takes them: cl-postgres sends NIL as false, so
NIL becomes :NULL there; SQLite's driver binds NIL as NULL already."
  (if (eq (driver) :postgres)
      (substitute :null nil parameters)
      parameters))

;;; Each statement is freed as soon as it has run.  A SQLite statement left
;;; unfinished (as DBI:ROW-COUNT leaves its "SELECT changes()") keeps its
;;; connection's read lock until the garbage collector finalizes it, and
;;; no other connection can commit meanwhile.

(define-metric "littoral_db_lock_timeouts_total" :counter
  "Statements that gave up waiting for another connection's lock (SQLite's \"database is locked\"), by database."
  :labels '("database"))
(define-metric "littoral_db_stale_objects_total" :counter
  "Saves and deletes refused because someone else changed the row meanwhile (STALE-OBJECT), by table."
  :labels '("table"))
(define-metric "littoral_db_transaction_seconds" :histogram "How long transactions took, by database."
  :labels '("database"))

(defun lock-error-p (condition)
  "True when CONDITION says a lock wasn't had in time."
  (cl-ppcre:scan "(?i)database (table )?is locked|database is busy|deadlock detected" (princ-to-string condition)))

(defmacro counting-lock-timeouts (&body body)
  "Evaluate BODY, counting an error that says a lock wasn't had in time."
  `(handler-bind ((error (lambda (e)
                           (when (ignore-errors (lock-error-p e))
                             (count-metric "littoral_db_lock_timeouts_total" (list (database-label)))))))
     ,@body))

(defun execute (sql &optional parameters)
  "Run SQL with PARAMETERS; the rows it returns, as plists."
  (let ((query (dbi:prepare (database-connection) sql)))
    (unwind-protect (counting-lock-timeouts (dbi:fetch-all (dbi:execute query (sql-parameters parameters))))
      (dbi:free-query-resources query))))

(defun execute-count (sql &optional parameters)
  "Run SQL with PARAMETERS; how many rows it changed."
  (let* ((connection (database-connection))
         (query (dbi:prepare connection sql)))
    (unwind-protect (counting-lock-timeouts (dbi:execute query (sql-parameters parameters)))
      (dbi:free-query-resources query))
    (if (eq (driver) :sqlite3)
        (row-value (first (execute "SELECT changes() AS n")) "n")
        (dbi:row-count connection))))

(defun db-query (sql &rest parameters)
  "Run SQL, with ? for each of PARAMETERS; the rows, as plists keyed by
column name (\"login\" → :|login|), NULL as NIL."
  (mapcar (lambda (row) (substitute nil :null row)) (execute sql parameters)))

(defun db-execute (sql &rest parameters)
  "Run SQL, with ? for each of PARAMETERS; how many rows it changed."
  (execute-count sql parameters))

(defun create-table (class)
  "Create CLASS's table unless it exists, with the columns id, version and
one for each field, and its full-text index if it has search fields.  An
existing table is left as it is, columns and all: change it with a
migration (see DEFINE-MIGRATIONS).  Returns CLASS."
  (let ((table (find-table class)))
    (execute-count
     (format nil "CREATE TABLE IF NOT EXISTS ~A (id ~A, version INTEGER NOT NULL DEFAULT 0~{, ~A~})"
             (table-name table)
             (if (eq (driver) :postgres) "BIGSERIAL PRIMARY KEY" "INTEGER PRIMARY KEY AUTOINCREMENT")
             (mapcar (lambda (f) (format nil "~A ~A" (column-name f) (sql-type f))) (table-fields table))))
    (when (table-search-fields table)
      (ensure-search-index table))
    class))

(defun drop-table (class)
  "Drop CLASS's table if it exists, with its full-text index."
  (let ((table (find-table class)))
    (when (and (table-search-fields table) (not (eq (driver) :postgres)))
      (execute-count (format nil "DROP TABLE IF EXISTS ~A_search" (table-name table))))
    (execute-count (format nil "DROP TABLE IF EXISTS ~A" (table-name table)))))

;;; Full-text search
;;;
;;; On SQLite an FTS5 table, kept in step by triggers; on PostgreSQL a GIN
;;; index over to_tsvector('simple', …).  Queries are words, each matching
;;; words that start with it, all of them required.

(defun search-columns (table)
  (mapcar #'sql-name (table-search-fields table)))

(defun search-document (table)
  "The SQL text PostgreSQL indexes for TABLE: its search columns, joined."
  (format nil "to_tsvector('simple', ~{coalesce(~A, '')~^ || ' ' || ~})" (search-columns table)))

(defun ensure-search-index (table)
  "Create TABLE's full-text index unless it exists, filling it from the rows already there."
  (let ((name (table-name table)) (columns (search-columns table)))
    (if (eq (driver) :postgres)
        (execute-count (format nil "CREATE INDEX IF NOT EXISTS ~A_search ON ~A USING GIN (~A)"
                               name name (search-document table)))
        (let ((exists (execute "SELECT name FROM sqlite_master WHERE name = ?" (list (format nil "~A_search" name)))))
          (execute-count (format nil "CREATE VIRTUAL TABLE IF NOT EXISTS ~A_search USING fts5(~{~A~^, ~}, content='~A', content_rowid='id')"
                                 name columns name))
          (flet ((values-of (row) (format nil "~{~A.~A~^, ~}" (loop for c in columns append (list row c)))))
            (execute-count (format nil "CREATE TRIGGER IF NOT EXISTS ~A_search_insert AFTER INSERT ON ~A BEGIN ~
INSERT INTO ~A_search(rowid, ~{~A~^, ~}) VALUES (new.id, ~A); END" name name name columns (values-of "new")))
            (execute-count (format nil "CREATE TRIGGER IF NOT EXISTS ~A_search_delete AFTER DELETE ON ~A BEGIN ~
INSERT INTO ~A_search(~A_search, rowid, ~{~A~^, ~}) VALUES ('delete', old.id, ~A); END" name name name name columns (values-of "old")))
            (execute-count (format nil "CREATE TRIGGER IF NOT EXISTS ~A_search_update AFTER UPDATE ON ~A BEGIN ~
INSERT INTO ~A_search(~A_search, rowid, ~{~A~^, ~}) VALUES ('delete', old.id, ~A); ~
INSERT INTO ~A_search(rowid, ~{~A~^, ~}) VALUES (new.id, ~A); END"
                                   name name name name columns (values-of "old") name columns (values-of "new"))))
          (unless exists
            (execute-count (format nil "INSERT INTO ~A_search(~A_search) VALUES ('rebuild')" name name)))))))

(defun search-words (query)
  "QUERY's words, letters and digits only, at most ten."
  (let ((words '()) (word (make-string-output-stream)))
    (flet ((end-word ()
             (let ((w (get-output-stream-string word)))
               (when (plusp (length w)) (push w words)))))
      (loop for char across (or query "")
            do (if (alphanumericp char) (write-char char word) (end-word)))
      (end-word))
    (let ((words (nreverse words)))
      (subseq words 0 (min 10 (length words))))))

(defun search-query (words)
  "WORDS as the database's query language: each a prefix, all required."
  (if (eq (driver) :postgres)
      (format nil "~{~A:*~^ & ~}" (mapcar #'string-downcase words))
      (format nil "~{\"~A\"*~^ ~}" words)))

(defun search-condition (class query)
  "A WHERE clause matching CLASS's objects that QUERY finds, and its
parameters, for DB-SELECT; NIL when QUERY has no words."
  (let ((table (find-table class))
        (words (search-words query)))
    (when (and words (table-search-fields table))
      (values (if (eq (driver) :postgres)
                  (format nil "~A @@ to_tsquery('simple', ?)" (search-document table))
                  (format nil "id IN (SELECT rowid FROM ~A_search WHERE ~A_search MATCH ?)"
                          (table-name table) (table-name table)))
              (list (search-query words))))))

(defun limit-clause (limit offset)
  "SQL ending a SELECT so it skips OFFSET rows and returns at most LIMIT,
either of them NIL.  SQLite takes an OFFSET only after a LIMIT, of -1 for
none."
  (format nil "~:[~; LIMIT ~:*~D~]~@[ OFFSET ~D~]"
          (or limit (and offset (not (eq (driver) :postgres)) -1))
          offset))

(defun db-search (class query &key limit offset)
  "CLASS's objects that QUERY finds in its search fields (DEFINE-TABLE's
:SEARCH), the best first, at most LIMIT of them after skipping OFFSET.  Each of QUERY's words (letters and digits,
the first ten) matches words starting with it, and all are required; NIL
when QUERY has no words.  Signals an error when CLASS has no search fields."
  (let* ((table (find-table class))
         (words (search-words query))
         (name (table-name table)))
    (unless (table-search-fields table)
      (error "~S has no full-text index: give DEFINE-TABLE :SEARCH fields." class))
    (when words
      (mapcar (lambda (row) (object-from-row table row))
              (execute (if (eq (driver) :postgres)
                           (format nil "SELECT * FROM ~A WHERE ~A @@ to_tsquery('simple', ?) ~
ORDER BY ts_rank(~A, to_tsquery('simple', ?)) DESC, id~A"
                                   name (search-document table) (search-document table) (limit-clause limit offset))
                           (format nil "SELECT ~A.* FROM ~A JOIN ~A_search ON ~A_search.rowid = ~A.id ~
WHERE ~A_search MATCH ? ORDER BY bm25(~A_search), ~A.id~A"
                                   name name name name name name name name (limit-clause limit offset)))
                       (if (eq (driver) :postgres)
                           (list (search-query words) (search-query words))
                           (list (search-query words))))))))

(defun highlight-matches (text query)
  "TEXT as HTML, escaped, with the words QUERY finds marked <mark>: words of
TEXT that start with one of QUERY's words."
  (let ((words (mapcar #'string-downcase (search-words query)))
        (text (or text ""))
        (start 0))
    (with-output-to-string (out)
      (loop with i = 0
            while (< i (length text))
            do (if (and (alphanumericp (char text i))
                        (or (zerop i) (not (alphanumericp (char text (1- i))))))
                   ;; At the start of a word: does it begin with one of WORDS?
                   (let ((end (or (position-if-not #'alphanumericp text :start i) (length text))))
                     (when (some (lambda (w) (and (<= (length w) (- end i))
                                                  (string-equal w text :start2 i :end2 (+ i (length w)))))
                                 words)
                       (write-string (html-escape (subseq text start i)) out)
                       (format out "<mark>~A</mark>" (html-escape (subseq text i end)))
                       (setf start end))
                     (setf i end))
                   (incf i)))
      (write-string (html-escape (subseq text start)) out))))

(defun row-value (row column)
  "COLUMN's value in ROW, a plist from cl-dbi."
  (getf row (intern column :keyword)))

(defun object-from-row (table row)
  "An object of TABLE's class holding ROW's values."
  (let ((object (make-instance (table-class table))))
    (setf (object-id object) (row-value row "id")
          (object-version object) (row-value row "version"))
    (dolist (field (table-fields table) object)
      (setf (field-value field object) (from-sql field (row-value row (column-name field)))))))

(defun db-find (class id)
  "The object of CLASS whose id is ID, or NIL."
  (let* ((table (find-table class))
         (row (first (execute (format nil "SELECT * FROM ~A WHERE id = ?" (table-name table)) (list id)))))
    (and row (object-from-row table row))))

(defun db-select (class &key where params order-by limit offset)
  "Objects of CLASS: those WHERE (SQL with ? for PARAMS) holds, in ORDER-BY
order (SQL, default by id), at most LIMIT of them after skipping OFFSET."
  (let ((table (find-table class)))
    (mapcar (lambda (row) (object-from-row table row))
            (execute (format nil "SELECT * FROM ~A~@[ WHERE ~A~] ORDER BY ~A~A"
                             (table-name table) where (or order-by "id") (limit-clause limit offset))
                     params))))

(defun db-count (class &key where params)
  "How many objects of CLASS WHERE (SQL with ? for PARAMS) holds; all of
them without WHERE."
  (let ((row (first (execute (format nil "SELECT COUNT(*) AS n FROM ~A~@[ WHERE ~A~]"
                                     (table-name (find-table class)) where)
                             params))))
    (row-value row "n")))

(defun field-parameters (table object)
  "OBJECT's field values, as TABLE's columns take them."
  (mapcar (lambda (f) (to-sql f (field-value f object))) (table-fields table)))

(defun db-insert (object)
  "Store OBJECT as a new row; it gets its id, and version 0.  Returns OBJECT."
  (let* ((table (find-table object))
         (fields (table-fields table))
         (row (first (execute (format nil "INSERT INTO ~A (version~{, ~A~}) VALUES (0~{, ~A~}) RETURNING id"
                                      (table-name table) (mapcar #'column-name fields)
                                      (mapcar (constantly "?") fields))
                              (field-parameters table object)))))
    (setf (object-id object) (row-value row "id")
          (object-version object) 0)
    object))

(defun db-update (object)
  "Write OBJECT's fields to its row and add one to its version.  Signals
STALE-OBJECT when the row changed (or went) since OBJECT was read.  Returns
OBJECT."
  (let* ((table (find-table object))
         (fields (table-fields table))
         (changed (execute-count
                   (format nil "UPDATE ~A SET ~{~A = ?, ~}version = version + 1 WHERE id = ? AND version = ?"
                           (table-name table) (mapcar #'column-name fields))
                   (append (field-parameters table object)
                           (list (object-id object) (object-version object))))))
    (when (zerop changed)
      (count-metric "littoral_db_stale_objects_total" (list (table-name table)))
      (error 'stale-object :object object))
    (incf (object-version object))
    object))

(defun db-save (object)
  "Insert OBJECT if it has no id yet (DB-INSERT), else update its row
(DB-UPDATE, which signals STALE-OBJECT when someone else changed it).
Returns OBJECT."
  (if (object-id object) (db-update object) (db-insert object)))

(defun db-delete (object)
  "Delete OBJECT's row; OBJECT's id becomes NIL.  Signals STALE-OBJECT
when the row changed (or went) since OBJECT was read.  Returns OBJECT."
  (let ((changed (execute-count (format nil "DELETE FROM ~A WHERE id = ? AND version = ?"
                                        (table-name (find-table object)))
                                (list (object-id object) (object-version object)))))
    (when (zerop changed)
      (count-metric "littoral_db_stale_objects_total" (list (table-name (find-table object))))
      (error 'stale-object :object object))
    (setf (object-id object) nil)
    object))

(defun db-reload (object)
  "OBJECT as its row now holds it, or NIL when the row has gone."
  (db-find (class-name (class-of object)) (object-id object)))

;;; Transactions

(defvar *in-transaction* nil
  "The database spec whose transaction is open in this thread, or NIL.")

(defmacro with-transaction (() &body body)
  "Run BODY in a transaction on *DATABASE*: committed if it returns, rolled
back if it signals.  Inside another on the same database, just BODY.
Returns BODY's value."
  `(call-with-transaction (lambda () ,@body)))

(defvar *after-commit* nil
  "A list (one cons, shared by the transaction) of functions to call once
the open transaction commits, newest first; NIL outside a transaction.")

(defun after-commit (function)
  "Call FUNCTION, of no arguments, once the transaction open on *DATABASE*
in this thread commits, or at once when none is open; if the transaction is
rolled back it is never called.  For telling others of a change, such as
publishing a channel whose subscribers read the database, which must not
happen before they can see it."
  (if (and *after-commit* (equal *in-transaction* *database*))
      (push function (car *after-commit*))
      (funcall function))
  (values))

(defun call-with-transaction (thunk)
  "Call THUNK in a transaction unless one is already open on this database,
then what it asked AFTER-COMMIT to call."
  (if (equal *in-transaction* *database*)
      (funcall thunk)
      (let ((*after-commit* (list '())))
        (multiple-value-prog1
            (let ((*in-transaction* *database*))
              (timing-metric ("littoral_db_transaction_seconds" (list (database-label)))
                (if (eq (driver) :sqlite3)
                    (call-with-sqlite-transaction thunk)
                    (dbi:with-transaction (database-connection)
                      (funcall thunk)))))
          (dolist (function (reverse (car *after-commit*)))
            (funcall function))))))

(defun call-with-sqlite-transaction (thunk)
  "Call THUNK in a SQLite transaction that takes the write lock at once.  A
transaction that reads and then writes can't take the lock while another
connection writes, and SQLite fails it at once rather than wait (it would
deadlock); one begun IMMEDIATE waits its turn, up to *SQLITE-BUSY-TIMEOUT*."
  (let ((connection (database-connection))
        (committed nil))
    (counting-lock-timeouts (dbi:do-sql connection "BEGIN IMMEDIATE"))
    (unwind-protect
         (multiple-value-prog1 (funcall thunk)
           (counting-lock-timeouts (dbi:do-sql connection "COMMIT"))
           (setf committed t))
      (unless committed
        (ignore-errors (dbi:do-sql connection "ROLLBACK"))))))

(defun using-database (driver &rest parameters)
  "An :AROUND-REQUEST function giving an application its own database,
whatever else the process connects to: DRIVER and PARAMETERS as for
CONNECT-DATABASE."
  (let ((spec (cons driver parameters)))
    (lambda (thunk)
      (let ((*database* spec))
        (funcall thunk)))))

(defun transactional ()
  "An :AROUND-ACTIONS function running each request's callbacks in one
transaction, for REGISTER-APPLICATION."
  (lambda (thunk) (call-with-transaction thunk)))
