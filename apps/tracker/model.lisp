;;;; model.lisp — users, issues and comments, kept in one store
;;;;
;;;; Every session sees the same store.  Reads take a snapshot of what they
;;;; need; changes go through the functions here, which hold the store's
;;;; lock, save it to *TRACKER-FILE* and publish *TRACKER-CHANNEL* so open
;;;; pages update.

(in-package #:littoral-tracker)

(defclass user ()
  ((name :initarg :name :reader user-name)
   (email :initarg :email :accessor user-email)
   (password-hash :initarg :password-hash :accessor user-password-hash))
  (:documentation "Someone who can log in."))

(defclass issue ()
  ((id :initarg :id :reader issue-id)
   (title :initarg :title :initform nil :accessor issue-title)
   (body :initarg :body :initform nil :accessor issue-body)
   (status :initarg :status :initform :open :accessor issue-status)
   (priority :initarg :priority :initform :normal :accessor issue-priority)
   (assignee :initarg :assignee :initform nil :accessor issue-assignee)
   (reporter :initarg :reporter :initform nil :accessor issue-reporter)
   (due :initarg :due :initform nil :accessor issue-due)
   (created :initarg :created :initform (get-universal-time) :accessor issue-created)
   (updated :initarg :updated :initform (get-universal-time) :accessor issue-updated)
   (comments :initarg :comments :initform '() :accessor issue-comments
             :documentation "Oldest first."))
  (:documentation "A thing to be done, discussed in comments."))

(defclass comment ()
  ((author :initarg :author :reader comment-author)
   (text :initarg :text :reader comment-text)
   (time :initarg :time :initform (get-universal-time) :reader comment-time))
  (:documentation "A remark on an issue."))

(defparameter *statuses* '(:open :in-progress :closed))
(defparameter *priorities* '(:low :normal :high :urgent))

(defun status-label (status)
  "STATUS as words, such as In Progress."
  (substitute #\Space #\- (string-capitalize status)))

(defvar *store-lock* (sb-thread:make-mutex :name "tracker store"))
(defvar *users* (make-hash-table :test 'equalp) "Name → USER; names ignore case.")
(defvar *issues* '() "Newest first.")
(defvar *next-issue-id* 1)
(defvar *tracker-file* nil "Where the store is saved; NIL keeps it in memory.")
(defvar *tracker-channel* (make-channel "tracker") "Published after every change.")

(defmacro with-store (() &body body)
  "Run BODY holding the store's lock."
  `(sb-thread:with-recursive-lock (*store-lock*) ,@body))

(defmacro changing-store (() &body body)
  "Run BODY holding the store's lock, then save and tell open pages."
  `(multiple-value-prog1
       (with-store ()
         (multiple-value-prog1 (progn ,@body)
           (save-store)))
     (publish *tracker-channel*)))

(defun find-user (name)
  "The user called NAME, ignoring case, or NIL."
  (with-store () (gethash name *users*)))

(defun user-names ()
  "Every user's name, alphabetically."
  (with-store ()
    (sort (loop for user being the hash-values of *users* collect (user-name user)) #'string-lessp)))

(defun add-user (name email password)
  "Register a user; signals an error when NAME is taken."
  (changing-store ()
    (when (gethash name *users*)
      (error "The name ~A is taken." name))
    (setf (gethash name *users*)
          (make-instance 'user :name name :email email
                               :password-hash (ironclad:pbkdf2-hash-password-to-combined-string
                                               (sb-ext:string-to-octets password :external-format :utf-8))))))

(defun authenticate (name password)
  "The user NAME if PASSWORD is theirs, else NIL."
  (let ((user (find-user name)))
    (and user password
         (ignore-errors
          (ironclad:pbkdf2-check-password (sb-ext:string-to-octets password :external-format :utf-8)
                                          (user-password-hash user)))
         user)))

(defun all-issues ()
  "Every issue, newest first."
  (with-store () (copy-list *issues*)))

(defun find-issue (id)
  "The issue numbered ID, or NIL."
  (with-store () (find id *issues* :key #'issue-id)))

(defun create-issue (reporter &rest values &key title body priority assignee due status)
  "File a new issue from REPORTER with VALUES; return it."
  (declare (ignore title body priority assignee due status))
  (changing-store ()
    (let ((issue (apply #'make-instance 'issue :id *next-issue-id* :reporter reporter
                        (loop for (key value) on values by #'cddr
                              when value append (list key value)))))
      (incf *next-issue-id*)
      (push issue *issues*)
      issue)))

(defun update-issue (issue values)
  "Change ISSUE's fields from the plist VALUES."
  (changing-store ()
    (loop for (key value) on values by #'cddr
          do (ecase key
               (:title (setf (issue-title issue) value))
               (:body (setf (issue-body issue) value))
               (:status (setf (issue-status issue) value))
               (:priority (setf (issue-priority issue) value))
               (:assignee (setf (issue-assignee issue) value))
               (:due (setf (issue-due issue) value))))
    (setf (issue-updated issue) (get-universal-time))
    issue))

(defun add-comment (issue author text)
  "Add AUTHOR's TEXT to ISSUE's comments."
  (changing-store ()
    (setf (issue-comments issue)
          (append (issue-comments issue) (list (make-instance 'comment :author author :text text)))
          (issue-updated issue) (get-universal-time))))

(defun issue-values (issue)
  "ISSUE's editable fields as a plist, for an editor's draft."
  (list :title (issue-title issue) :body (issue-body issue) :status (issue-status issue)
        :priority (issue-priority issue) :assignee (issue-assignee issue) :due (issue-due issue)))

;;; Saving

(defun store-forms ()
  "The store as plain data."
  (with-store ()
    (list :next-issue-id *next-issue-id*
          :users (loop for user being the hash-values of *users*
                       collect (list :name (user-name user) :email (user-email user)
                                     :password-hash (user-password-hash user)))
          :issues (loop for issue in *issues*
                        collect (list :id (issue-id issue) :title (issue-title issue)
                                      :body (issue-body issue) :status (issue-status issue)
                                      :priority (issue-priority issue) :assignee (issue-assignee issue)
                                      :reporter (issue-reporter issue) :due (issue-due issue)
                                      :created (issue-created issue) :updated (issue-updated issue)
                                      :comments (loop for c in (issue-comments issue)
                                                      collect (list :author (comment-author c)
                                                                    :text (comment-text c)
                                                                    :time (comment-time c))))))))

(defun save-store ()
  "Write the store to *TRACKER-FILE*, atomically, readable only by its owner."
  (when *tracker-file*
    (let ((temporary (format nil "~A.tmp" (namestring *tracker-file*))))
      (with-open-file (out temporary :direction :output :if-exists :supersede :external-format :utf-8)
        (sb-posix:chmod temporary #o600)
        (with-standard-io-syntax
          (let ((*package* (find-package :keyword)) (*print-readably* nil))
            (format out ";;;; Tracker data, written by littoral-tracker.~%")
            (prin1 (store-forms) out)
            (terpri out))))
      (rename-file temporary (merge-pathnames *tracker-file*)))))

(defun load-store (file)
  "Replace the store with what FILE holds."
  (let ((data (with-open-file (in file :external-format :utf-8)
                (with-standard-io-syntax
                  (let ((*package* (find-package :keyword)) (*read-eval* nil))
                    (read in))))))
    (with-store ()
      (clrhash *users*)
      (dolist (u (getf data :users))
        (setf (gethash (getf u :name) *users*)
              (make-instance 'user :name (getf u :name) :email (getf u :email)
                                   :password-hash (getf u :password-hash))))
      (setf *next-issue-id* (getf data :next-issue-id 1)
            *issues* (loop for i in (getf data :issues)
                           collect (make-instance
                                    'issue :id (getf i :id) :title (getf i :title) :body (getf i :body)
                                           :status (getf i :status) :priority (getf i :priority)
                                           :assignee (getf i :assignee) :reporter (getf i :reporter)
                                           :due (getf i :due) :created (getf i :created)
                                           :updated (getf i :updated)
                                           :comments (loop for c in (getf i :comments)
                                                           collect (make-instance 'comment
                                                                                  :author (getf c :author)
                                                                                  :text (getf c :text)
                                                                                  :time (getf c :time)))))))))

(defun reset-tracker ()
  "Empty the store (but not the file)."
  (with-store ()
    (clrhash *users*)
    (setf *issues* '() *next-issue-id* 1)))
