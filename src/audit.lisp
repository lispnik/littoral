;;;; audit.lisp — who did what, and when
;;;;
;;;;   (create-audit-tables)                    ; CREATE-AUTH-TABLES does this too
;;;;   (audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
;;;;                         :details '(:to "ada@example.org"))
;;;;   (audit-events :action "sign-in" :limit 20)
;;;;   (make-instance 'audit-log-view)          ; a page to look through them
;;;;   (make-instance 'activity-feed)           ; what's happened lately, as it happens
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
  (:documentation "Load it with `(asdf:load-system :littoral/audit)`.  An audit log: who did what,
and when, kept in the database.")
  (:export #:audit #:create-audit-tables #:drop-audit-tables #:audit-enabled-p
           #:*audit-actor* #:*audit-hook* #:audit-events #:audit-actions #:purge-audit-log
           #:audit-event #:audit-event-id #:audit-event-time #:audit-event-actor-id #:audit-event-actor-name
           #:audit-event-action #:audit-event-subject #:audit-event-subject-label #:audit-event-details
           #:audit-event-address
           #:audit-log-view
           #:*audit-channel* #:activity-feed #:*activity-phrases* #:activity-phrase))

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

(defvar *audit-channel* (make-channel "audit log")
  "The channel published when an event is recorded in this process, once
its transaction commits.  An ACTIVITY-FEED subscribes to it.")

(defvar *audit-actor* (constantly nil)
  "A function of no arguments: the id and name (two values, strings or NIL)
of whoever is acting now.  littoral/auth makes it the signed-in user.")

(defvar *audit-hook* nil
  "A function of each event as a plist (:TIME :ACTOR-ID :ACTOR-NAME :ACTION
:SUBJECT :SUBJECT-LABEL :DETAILS :ADDRESS), or NIL.  Called even where
there's no audit table; errors it signals are ignored.")

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
DETAILS, a plist of short values (strings, numbers, T and NIL, symbols, lists
of them).  The actor is ACTOR-ID and ACTOR-NAME when ACTOR-ID is given, even
as NIL for none, or else whoever *AUDIT-ACTOR* finds.  Returns ACTION.  The
event is written only where AUDIT-ENABLED-P, and passed to *AUDIT-HOOK*."
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
                                (getf event :address))
        ;; Once the row is there for others to read: after the insert, and
        ;; after its transaction commits.
        (littoral.db:after-commit (lambda () (publish *audit-channel*))))
      (when *audit-hook*
        (ignore-errors (funcall *audit-hook* event)))
      action)))

;;; Reading

(defclass audit-event ()
  ((id :initarg :id :reader audit-event-id :documentation "Its row's id, larger for later events.")
   (time :initarg :time :reader audit-event-time :documentation "A universal time.")
   (actor-id :initarg :actor-id :reader audit-event-actor-id :documentation "Who acted, a string, or NIL.")
   (actor-name :initarg :actor-name :reader audit-event-actor-name
               :documentation "Who acted, named for people, or NIL.")
   (action :initarg :action :reader audit-event-action :documentation "What was done, such as \"invoice.sent\".")
   (subject :initarg :subject :reader audit-event-subject
            :documentation "What it was done to, such as \"invoice:42\", or NIL.")
   (subject-label :initarg :subject-label :reader audit-event-subject-label
                  :documentation "What it was done to, named for people, or NIL.")
   (details :initarg :details :reader audit-event-details
            :documentation "An alist of (\"key\" . value), sorted by key; a list value
is a list of strings, and NIL reads back as the symbol NULL.")
   (address :initarg :address :reader audit-event-address
            :documentation "The client's IP address, or NIL outside a request."))
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
a subject; SEARCH looks in the actor's and subject's names, ignoring case
(on SQLite, the case of ASCII letters only);
SINCE and UNTIL are universal times.  At most LIMIT, skipping the first
OFFSET."
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

;;; What's happened lately

(defparameter *activity-phrases*
  '(("sign-in" . "signed in") ("sign-in.failed" . "failed to sign in as") ("sign-out" . "signed out")
    ("sign-out.everywhere" . "signed out everywhere") ("session.revoked" . "ended a session of")
    ("password.changed" . "changed the password of")
    ("password.reset-requested" . "asked to reset the password of")
    ("role.granted" . "gave a role to") ("role.revoked" . "took a role from")
    ("permission.granted" . "gave a permission to") ("permission.revoked" . "took a permission from")
    ("api-token.created" . "made an API token for") ("api-tokens.revoked" . "revoked the API tokens of")
    ("recovery-codes.created" . "made recovery codes for")
    ("second-factor.added" . "added a second factor for") ("second-factor.removed" . "removed a second factor of")
    ("record.created" . "created") ("record.updated" . "changed") ("record.deleted" . "deleted")
    ("job.retried" . "retried") ("job.cancelled" . "cancelled") ("job.cancel-requested" . "asked to cancel"))
  "(ACTION . PHRASE) for the actions Littoral records: what an ACTIVITY-FEED
says someone did, before what they did it to.  Add an application's own
actions, or give the feed :DESCRIBE.")

(defun activity-phrase (action)
  "The phrase *ACTIVITY-PHRASES* has for ACTION, translated, or NIL."
  (let ((phrase (cdr (assoc action *activity-phrases* :test #'string=))))
    (and phrase (translate-label phrase))))

(defclass activity-feed (component)
  ((action :initarg :action :initform nil :reader feed-action
           :documentation "Only events of this action and those under it, or NIL for all.")
   (actor :initarg :actor :initform nil :reader feed-actor :documentation "Only this actor's events, by id.")
   (subject :initarg :subject :initform nil :reader feed-subject :documentation "Only events on this subject.")
   (describe :initarg :describe :initform nil :reader feed-describe
             :documentation "A function of an event giving what was done, or NIL to use ACTIVITY-PHRASE.")
   (list :reader feed-list))
  (:documentation "What has happened lately, from the audit log: newest
first, who did what to what and how long ago, a batch at a time with a
button for older events.  Events recorded in this process appear on open
pages as they happen.  :ACTION, :ACTOR and :SUBJECT narrow it as for
AUDIT-EVENTS, and :BATCH-SIZE is how many it shows at once (20).  Each
event is described by :DESCRIBE, a function of an event, or else by
ACTIVITY-PHRASE, or failing both by its action.  Shows whatever it's
given: put it where those who see it may know these things."))

(defmethod initialize-instance :after ((self activity-feed) &key (batch-size 20))
  (setf (slot-value self 'list)
        (make-instance 'load-more-list
                       :batch-size batch-size :subscriptions (list *audit-channel*)
                       :label "Older activity" :list-label "Recent activity"
                       :fetch (lambda (start count)
                                (audit-events :action (feed-action self) :actor (feed-actor self)
                                              :subject (feed-subject self) :limit count :offset start))
                       :render-item (lambda (event) (render-activity self event)))))

(defmethod children ((self activity-feed)) (list (feed-list self)))

(defun render-activity (feed event)
  "Write what FEED says of EVENT: who, what they did, to what, and when."
  (let ((what (or (and (feed-describe feed) (funcall (feed-describe feed) event))
                  (activity-phrase (audit-event-action event))))
        (who (or (audit-event-actor-name event) (audit-event-actor-id event)))
        (subject (or (audit-event-subject-label event) (audit-event-subject event))))
    (div (:class "lt-activity-item")
      (strong (:class "lt-activity-actor") (text (or who (translate "Someone"))))
      (text " ")
      (if what
          (text what)
          (code () (text (audit-event-action event))))
      ;; Signing in names the user, who is the actor already.
      (when (and subject (not (equal subject who)))
        (text " ")
        (span (:class "lt-activity-subject") (text subject)))
      (text " ")
      (time-ago (audit-event-time event) :class "lt-activity-time"))))

(defmethod render ((self activity-feed))
  (div (:class "lt-activity")
    (render-component (feed-list self))))
