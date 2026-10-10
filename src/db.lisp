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
  (:documentation "Keep described objects in a SQL database.")
  (:export #:connect-database #:disconnect-database #:database-connection #:*database*
           #:persistent #:object-id #:object-version
           #:define-table #:find-table #:table-name #:table-class #:create-table #:drop-table
           #:db-find #:db-select #:db-count #:db-insert #:db-update #:db-save #:db-delete
           #:db-reload #:db-query #:db-execute #:db-search #:search-condition #:highlight-matches #:with-transaction #:transactional #:using-database
           #:stale-object #:stale-object-object
           #:reference-field #:reference-class #:object-label #:sql-type #:to-sql #:from-sql))

(in-package #:littoral.db)

;;; Connections

(defvar *database* nil
  "The arguments of the last CONNECT-DATABASE: a driver keyword and its
connection parameters, as DBI:CONNECT takes them.")

(defun connect-database (driver &rest parameters)
  "Use the database DRIVER (:sqlite3, :postgres) reaches with PARAMETERS.
Each thread gets its own connection, made when first needed."
  (setf *database* (cons driver parameters))
  (database-connection))

(defun database-connection ()
  "This thread's connection to *DATABASE*."
  (unless *database*
    (error "No database: call CONNECT-DATABASE first."))
  (apply #'dbi:connect-cached *database*))

(defun disconnect-database ()
  "Forget the database (connections close as their threads end)."
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

(define-condition stale-object (error)
  ((object :initarg :object :reader stale-object-object))
  (:report (lambda (condition stream)
             (format stream "~A was changed or deleted by someone else since it was read."
                     (stale-object-object condition))))
  (:documentation "Signalled when saving or deleting an object whose row has
changed (or gone) since the object was read."))

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
  "Keep objects of CLASS (a PERSISTENT class with a description) in the
table NAME (default: the class name), with DESCRIPTION's fields as columns.
SEARCH names text fields to keep in a full-text index, for DB-SEARCH."
  `(setf (gethash ',class *tables*)
         (make-instance 'table :class ',class
                               :name ,(or name (sql-name class))
                               :description (find-description ',(or description class))
                               :search ',search)))

(defun find-table (designator)
  "The table of DESIGNATOR, a class name or an object."
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
  (:method ((field boolean-field)) "INTEGER"))

(defgeneric to-sql (field value)
  (:documentation "VALUE as it is written to FIELD's column.")
  (:method ((field field) value) value)
  (:method ((field boolean-field) value) (if value 1 0))
  (:method ((field date-field) value) (and value (format-field field value)))
  (:method ((field choice-field) value)
    (cond ((null value) nil)
          ((symbolp value) (symbol-name value))
          (t (princ-to-string value)))))

(defgeneric from-sql (field value)
  (:documentation "The value FIELD holds, from what its column held.")
  (:method ((field field) value) (if (eq value :null) nil value))
  (:method ((field boolean-field) value) (and value (not (eq value :null)) (/= value 0)))
  (:method ((field date-field) value)
    (and value (not (eq value :null)) (parse-field field value)))
  (:method ((field choice-field) value)
    (and value (not (eq value :null))
         (find value (field-choices field)
               :key (lambda (choice) (if (symbolp choice) (symbol-name choice) (princ-to-string choice)))
               :test #'string=))))

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
  "How OBJECT is named in choices and links: its first string field."
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

(defun execute (sql &optional parameters)
  "Run SQL with PARAMETERS; the rows it returns, as plists."
  (dbi:fetch-all (dbi:execute (dbi:prepare (database-connection) sql) (sql-parameters parameters))))

(defun execute-count (sql &optional parameters)
  "Run SQL with PARAMETERS; how many rows it changed."
  (let ((connection (database-connection)))
    (dbi:execute (dbi:prepare connection sql) (sql-parameters parameters))
    (dbi:row-count connection)))

(defun db-query (sql &rest parameters)
  "Run SQL, with ? for each of PARAMETERS; the rows, as plists keyed by
column name (\"login\" → :|login|), NULL as NIL."
  (mapcar (lambda (row) (substitute nil :null row)) (execute sql parameters)))

(defun db-execute (sql &rest parameters)
  "Run SQL, with ? for each of PARAMETERS; how many rows it changed."
  (execute-count sql parameters))

(defun create-table (class)
  "Create CLASS's table unless it exists."
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

(defun db-search (class query &key limit offset)
  "CLASS's objects that QUERY finds in its search fields, the best first."
  (let* ((table (find-table class))
         (words (search-words query))
         (name (table-name table)))
    (unless (table-search-fields table)
      (error "~S has no full-text index: give DEFINE-TABLE :SEARCH fields." class))
    (when words
      (mapcar (lambda (row) (object-from-row table row))
              (execute (if (eq (driver) :postgres)
                           (format nil "SELECT * FROM ~A WHERE ~A @@ to_tsquery('simple', ?) ~
ORDER BY ts_rank(~A, to_tsquery('simple', ?)) DESC, id~@[ LIMIT ~D~]~@[ OFFSET ~D~]"
                                   name (search-document table) (search-document table) limit (and limit offset))
                           (format nil "SELECT ~A.* FROM ~A JOIN ~A_search ON ~A_search.rowid = ~A.id ~
WHERE ~A_search MATCH ? ORDER BY bm25(~A_search), ~A.id~@[ LIMIT ~D~]~@[ OFFSET ~D~]"
                                   name name name name name name name name limit (and limit offset)))
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
            (execute (format nil "SELECT * FROM ~A~@[ WHERE ~A~] ORDER BY ~A~@[ LIMIT ~D~]~@[ OFFSET ~D~]"
                             (table-name table) where (or order-by "id") limit
                             (and limit offset))
                     params))))

(defun db-count (class &key where params)
  "How many objects of CLASS WHERE holds."
  (let ((row (first (execute (format nil "SELECT COUNT(*) AS n FROM ~A~@[ WHERE ~A~]"
                                     (table-name (find-table class)) where)
                             params))))
    (row-value row "n")))

(defun field-parameters (table object)
  "OBJECT's field values, as TABLE's columns take them."
  (mapcar (lambda (f) (to-sql f (field-value f object))) (table-fields table)))

(defun db-insert (object)
  "Store OBJECT as a new row; it gets its id.  Returns OBJECT."
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
  "Write OBJECT's fields to its row.  Signals STALE-OBJECT when the row
changed since OBJECT was read.  Returns OBJECT."
  (let* ((table (find-table object))
         (fields (table-fields table))
         (changed (execute-count
                   (format nil "UPDATE ~A SET ~{~A = ?, ~}version = version + 1 WHERE id = ? AND version = ?"
                           (table-name table) (mapcar #'column-name fields))
                   (append (field-parameters table object)
                           (list (object-id object) (object-version object))))))
    (when (zerop changed)
      (error 'stale-object :object object))
    (incf (object-version object))
    object))

(defun db-save (object)
  "Insert OBJECT if it is new, else update it."
  (if (object-id object) (db-update object) (db-insert object)))

(defun db-delete (object)
  "Delete OBJECT's row.  Signals STALE-OBJECT when the row changed since
OBJECT was read."
  (let ((changed (execute-count (format nil "DELETE FROM ~A WHERE id = ? AND version = ?"
                                        (table-name (find-table object)))
                                (list (object-id object) (object-version object)))))
    (when (zerop changed)
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
  "Run BODY in a transaction: committed if it returns, rolled back if it
signals.  Inside another, just BODY."
  `(call-with-transaction (lambda () ,@body)))

(defun call-with-transaction (thunk)
  "Call THUNK in a transaction unless one is already open on this database."
  (if (equal *in-transaction* *database*)
      (funcall thunk)
      (let ((*in-transaction* *database*))
        (dbi:with-transaction (database-connection)
          (funcall thunk)))))

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
