;;;; comments.lisp — comment threads kept in the database
;;;;
;;;;   (create-comment-tables)
;;;;   (setf *comment-store* (make-instance 'database-comment-store))
;;;;   (make-instance 'live-comment-thread :thread "invoice:42")
;;;;
;;;; Each comment is a row in the comments table: its thread, author, body,
;;;; when it was posted and the session that posted it.  Pages showing a
;;;; thread hear of a change once the transaction making it commits.

(defpackage #:littoral.comments
  (:use #:cl #:littoral)
  (:documentation "Load it with `(asdf:load-system :littoral/comments)`.  Comment threads kept in the
database, for LIVE-COMMENT-THREAD.")
  (:export #:create-comment-tables #:drop-comment-tables #:database-comment-store))

(in-package #:littoral.comments)

(littoral.db:define-migrations :littoral-comments
  (asdf:system-relative-pathname :littoral "migrations/comments/"))

(defun create-comment-tables ()
  "Create or bring up to date the comments table (migrations
:LITTORAL-COMMENTS) in the current database."
  (littoral.db:migrate :littoral-comments)
  t)

(defun drop-comment-tables ()
  "Drop the comments table."
  (littoral.db:db-execute "DROP TABLE IF EXISTS comments")
  (littoral.db:forget-migrations :littoral-comments))

(defclass database-comment-store () ()
  (:documentation "Comments kept in the comments table of the current
database (LITTORAL.DB:*DATABASE*), which CREATE-COMMENT-TABLES makes."))

(defun row-comment (row)
  "The THREAD-COMMENT a comments ROW, a plist from DB-QUERY, holds."
  (flet ((value (key) (let ((v (getf row key))) (if (eq v :null) nil v))))
    (make-instance 'thread-comment :id (value :|id|) :thread (value :|thread|) :author (value :|author|)
                                   :body (value :|body|) :time (value :|created|) :origin (value :|origin|))))

(defmethod store-thread-comments ((store database-comment-store) thread)
  (mapcar #'row-comment (littoral.db:db-query "SELECT * FROM comments WHERE thread = ? ORDER BY id" thread)))

(defmethod store-add-comment ((store database-comment-store) thread author body time origin)
  (let ((id (getf (first (littoral.db:db-query
                          "INSERT INTO comments (thread, author, body, created, origin) VALUES (?, ?, ?, ?, ?) RETURNING id"
                          thread author body time origin))
                  :|id|)))
    (make-instance 'thread-comment :id id :thread thread :author author :body body :time time :origin origin)))

(defmethod store-delete-comment ((store database-comment-store) thread id)
  (littoral.db:db-execute "DELETE FROM comments WHERE thread = ? AND id = ?" thread id))

(defmethod call-after-store-change ((store database-comment-store) function)
  (littoral.db:after-commit function))
