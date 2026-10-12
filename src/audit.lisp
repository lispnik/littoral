;;;; audit.lisp — who did what, and when
;;;;
;;;;   (create-audit-tables)                    ; CREATE-AUTH-TABLES does this too
;;;;   (audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
;;;;                         :details '(:to "ada@example.org"))
;;;;   (audit-events :action "sign-in" :limit 20)
;;;;   (make-instance 'audit-log-view)          ; a page to look through them
;;;;
;;;; Each event is a row in audit_log: when, who (the signed-in user, as
;;;; *AUDIT-ACTOR* finds them, unless given), the action, what it was done
;;;; to, details (kept as JSON) and the client's address.  littoral/auth
;;;; records signing in and out, failures, password and role changes, tokens
;;;; and second factors; littoral/admin records what is created, changed and
;;;; deleted.  An event is written in the current transaction, so one whose
;;;; action rolls back is gone with it.  Events are recorded only in a
;;;; database whose tables CREATE-AUDIT-TABLES made in this process, so an
;;;; application without them works as before.  *AUDIT-HOOK* sees every
;;;; event too, to send it on to a log.

(defpackage #:littoral.audit
  (:use #:cl #:littoral #:littoral.html)
  (:documentation "An audit log: who did what, and when, kept in the database.")
  (:export #:audit #:create-audit-tables #:drop-audit-tables #:audit-enabled-p
           #:*audit-actor* #:*audit-hook* #:audit-events #:audit-actions #:purge-audit-log
           #:audit-event #:audit-event-id #:audit-event-time #:audit-event-actor-id #:audit-event-actor-name
           #:audit-event-action #:audit-event-subject #:audit-event-subject-label #:audit-event-details
           #:audit-event-address
           #:audit-log-view))

(in-package #:littoral.audit)

;;; The table

(defvar *audit-databases* '() "Database specs whose audit tables were made in this process.")
(defvar *audit-databases-lock* (sb-thread:make-mutex :name "littoral audit databases"))

(defun audit-enabled-p ()
  "True when events are recorded in the current database."
  (and littoral.db:*database*
       (member littoral.db:*database* *audit-databases* :test #'equal)
       t))

(littoral.db:define-migrations :littoral-audit (asdf:system-relative-pathname :littoral "migrations/audit/"))

(defun create-audit-tables ()
  "Create or bring up to date the audit_log table (migrations
:LITTORAL-AUDIT), and record events in this database."
  (littoral.db:migrate :littoral-audit)
  (sb-thread:with-mutex (*audit-databases-lock*)
    (pushnew (copy-tree littoral.db:*database*) *audit-databases* :test #'equal))
  t)

(defun drop-audit-tables ()
  "Drop the audit_log table, and stop recording events in this database."
  (sb-thread:with-mutex (*audit-databases-lock*)
    (setf *audit-databases* (remove littoral.db:*database* *audit-databases* :test #'equal)))
  (littoral.db:db-execute "DROP TABLE IF EXISTS audit_log")
  (littoral.db:forget-migrations :littoral-audit))

;;; Recording

(defvar *audit-actor* (constantly nil)
  "A function of no arguments: the id and name (two values, strings or NIL)
of whoever is acting now.  littoral/auth makes it the signed-in user.")

(defvar *audit-hook* nil
  "A function of each event as a plist (:TIME :ACTOR-ID :ACTOR-NAME :ACTION
:SUBJECT :SUBJECT-LABEL :DETAILS :ADDRESS), or NIL.  Called even where
there's no audit table.")

(defun clip (value &optional (length 200))
  (let ((text (and value (if (stringp value) value (princ-to-string value)))))
    (and text (subseq text 0 (min length (length text))))))

(defun details-json (details)
  "DETAILS, a plist, as a JSON object; keys lower-cased."
  (and details
       (let ((table (make-hash-table :test 'equal)))
         (loop for (key value) on details by #'cddr
               do (setf (gethash (string-downcase (string key)) table)
                        (typecase value
                          ((or string real) value)
                          (null 'null)
                          ((eql t) t)
                          (symbol (string-downcase (symbol-name value)))
                          (list (map 'vector (lambda (v) (if (stringp v) v (princ-to-string v))) value))
                          (t (princ-to-string value)))))
         (com.inuoe.jzon:stringify table))))

(defun audit (action &key subject subject-label details (actor-id nil actor-given) actor-name)
  "Record that ACTION (a string such as \"invoice.sent\") happened to SUBJECT
(a string such as \"invoice:42\", named SUBJECT-LABEL for people), with
DETAILS, a plist of short values.  The actor is ACTOR-ID and ACTOR-NAME when
given, or else whoever *AUDIT-ACTOR* finds."
  (multiple-value-bind (id name) (if actor-given (values actor-id actor-name) (funcall *audit-actor*))
    (let ((event (list :time (get-universal-time) :actor-id (clip id) :actor-name (clip name)
                       :action action :subject (clip subject) :subject-label (clip subject-label)
                       :details details
                       :address (and littoral:*request* (ignore-errors (littoral::client-address))))))
      (when (audit-enabled-p)
        (littoral.db:db-execute "INSERT INTO audit_log (at, actor_id, actor_name, action, subject, subject_label, details, address)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
                                (getf event :time) (getf event :actor-id) (getf event :actor-name) action
                                (getf event :subject) (getf event :subject-label) (details-json details)
                                (getf event :address)))
      (when *audit-hook*
        (ignore-errors (funcall *audit-hook* event)))
      action)))

;;; Reading

(defclass audit-event ()
  ((id :initarg :id :reader audit-event-id)
   (time :initarg :time :reader audit-event-time :documentation "A universal time.")
   (actor-id :initarg :actor-id :reader audit-event-actor-id)
   (actor-name :initarg :actor-name :reader audit-event-actor-name)
   (action :initarg :action :reader audit-event-action)
   (subject :initarg :subject :reader audit-event-subject)
   (subject-label :initarg :subject-label :reader audit-event-subject-label)
   (details :initarg :details :reader audit-event-details
            :documentation "An alist of (\"key\" . value), in the order recorded.")
   (address :initarg :address :reader audit-event-address))
  (:documentation "An event read from the audit log."))

(defmethod print-object ((event audit-event) stream)
  (print-unreadable-object (event stream :type t)
    (format stream "~A~@[ by ~A~]~@[ on ~A~]" (audit-event-action event) (audit-event-actor-name event)
            (audit-event-subject event))))

(defun parse-details (json)
  (and json
       (let ((value (ignore-errors (com.inuoe.jzon:parse json))))
         (when (hash-table-p value)
           (sort (loop for key being the hash-keys of value using (hash-value v)
                       collect (cons key (if (and (vectorp v) (not (stringp v))) (coerce v 'list) v)))
                 #'string< :key #'car)))))

(defun event-from-row (row)
  (flet ((column (name) (getf row (intern name :keyword))))
    (make-instance 'audit-event :id (column "id") :time (column "at")
                                :actor-id (column "actor_id") :actor-name (column "actor_name")
                                :action (column "action") :subject (column "subject")
                                :subject-label (column "subject_label")
                                :details (parse-details (column "details")) :address (column "address"))))

(defun audit-events (&key action actor subject search since until (limit 50) (offset 0))
  "Events, newest first.  ACTION matches itself and the actions under it
(\"sign-in\" matches \"sign-in.failed\"); ACTOR is an actor id and SUBJECT
a subject; SEARCH looks in the actor's and subject's names; SINCE and UNTIL
are universal times."
  (let ((clauses '()) (parameters '()))
    (flet ((where (clause &rest values)
             (push clause clauses)
             (setf parameters (append parameters values))))
      (when action (where "(action = ? OR action LIKE ?)" action (format nil "~A.%" action)))
      (when actor (where "actor_id = ?" (princ-to-string actor)))
      (when subject (where "subject = ?" subject))
      (when (and search (plusp (length search)))
        (let ((pattern (format nil "%~A%" (string-downcase search))))
          (where "(LOWER(actor_name) LIKE ? OR LOWER(subject_label) LIKE ? OR LOWER(subject) LIKE ?)"
                 pattern pattern pattern)))
      (when since (where "at >= ?" since))
      (when until (where "at < ?" until)))
    (mapcar #'event-from-row
            (apply #'littoral.db:db-query
                   (format nil "SELECT * FROM audit_log~@[ WHERE ~{~A~^ AND ~}~] ORDER BY id DESC LIMIT ~D OFFSET ~D"
                           (reverse clauses) limit offset)
                   parameters))))

(defun audit-actions ()
  "The actions recorded so far, in order.  Sorted here: PostgreSQL's
collation would put \"invoices\" before \"invoice.sent\"."
  (sort (mapcar (lambda (row) (getf row :|action|))
                (littoral.db:db-query "SELECT DISTINCT action FROM audit_log"))
        #'string<))

(defun purge-audit-log (&key (older-than (* 365 24 3600)))
  "Delete events more than OLDER-THAN seconds old (a year); how many."
  (littoral.db:db-execute "DELETE FROM audit_log WHERE at < ?" (- (get-universal-time) older-than)))

;;; Looking through it

(defparameter *audit-page-size* 25)

(defclass audit-log-view (component)
  ((action :initform :any :accessor view-action)
   (search :initform "" :accessor view-search)
   (offset :initform 0 :accessor view-offset))
  (:documentation "The audit log, newest first, filtered by action and by
who or what.  Shows everything: put it where only those who may see it can."))

(defmethod states ((self audit-log-view)) (list self))

(defun event-time-text (time)
  (multiple-value-bind (s m h date month year) (decode-universal-time time)
    (format nil "~D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D" year month date h m s)))

(defun details-text (details)
  (format nil "~{~A~^; ~}"
          (mapcar (lambda (pair)
                    (let ((value (cdr pair)))
                      (format nil "~A: ~A" (car pair)
                              (cond ((listp value) (format nil "~{~A~^, ~}" value))
                                    ((eq value 'null) "—")
                                    (t value)))))
                  details)))

(defmethod render ((self audit-log-view))
  (let* ((events (audit-events :action (unless (eq (view-action self) :any) (view-action self))
                               :search (view-search self)
                               :limit (1+ *audit-page-size*) :offset (view-offset self)))
         (more (> (length events) *audit-page-size*)))
    (div (:class "lt-audit-log")
      (form (:class "lt-audit-filters")
        (label () (translate "Action") " "
          (select-list (:items (cons :any (audit-actions)) :selected (view-action self) :test #'equal
                        :labels (lambda (v) (if (eq v :any) (translate "Any") v))
                        :callback (lambda (v) (setf (view-action self) v (view-offset self) 0)))))
        (label () (translate "Who or what") " "
          (text-input (:value (view-search self)
                       :callback (lambda (v) (setf (view-search self) v (view-offset self) 0)))))
        (submit-button (:callback (lambda ())) (translate "Filter")))
      (if (null events)
          (p () (translate "Nothing has been recorded."))
          (table (:class "lt-table lt-audit-table")
            (caption (:class "lt-visually-hidden") (translate "Audit log, newest first"))
            (tr () (th () (translate "When")) (th () (translate "Who")) (th () (translate "Action"))
                (th () (translate "Subject")) (th () (translate "Details")) (th () (translate "Address")))
            (dolist (event (subseq events 0 (min (length events) *audit-page-size*)))
              (tr ()
                (td (:class "lt-audit-time") (text (event-time-text (audit-event-time event))))
                (td () (text (or (audit-event-actor-name event) (audit-event-actor-id event) "")))
                (td () (code () (text (audit-event-action event))))
                (td () (text (or (audit-event-subject-label event) (audit-event-subject event) "")))
                (td () (text (details-text (audit-event-details event))))
                (td () (text (or (audit-event-address event) "")))))))
      (p (:class "lt-audit-pages")
        (when (plusp (view-offset self))
          (anchor (:callback (lambda () (setf (view-offset self) (max 0 (- (view-offset self) *audit-page-size*)))))
            (translate "« Newer")))
        " "
        (when more
          (anchor (:callback (lambda () (incf (view-offset self) *audit-page-size*)))
            (translate "Older »")))))))

(defmethod style ((self audit-log-view))
  ".lt-audit-filters { display: flex; flex-wrap: wrap; gap: .8rem; align-items: center; margin-bottom: .6rem; }
.lt-audit-table td { vertical-align: top; }
.lt-audit-time { white-space: nowrap; }
.lt-audit-log { overflow-x: auto; }")
