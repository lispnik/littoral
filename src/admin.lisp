;;;; admin.lisp — an administration interface generated from descriptions
;;;;
;;;;   (register-admin "/admin" '(project job)
;;;;                   :database '(:sqlite3 :database-name "app.db")
;;;;                   :role :admin)                ; users with the admin role sign in
;;;;
;;;; For each stored class (see littoral/db): a searchable, filterable,
;;;; sortable list; a page per object with its fields, links to the objects
;;;; it refers to and lists of those referring to it; editing that notices
;;;; someone else's concurrent change; creation; deletion after asking.
;;;; With :ROLE, users of littoral/auth with that role sign in to it; with
;;;; :CREDENTIALS, it asks for HTTP basic auth; with neither, it answers only
;;;; requests from this machine.

(defpackage #:littoral.admin
  (:use #:cl #:littoral #:littoral.html #:littoral.db)
  (:documentation "An administration interface generated from descriptions.  Load it with
`(asdf:load-system :littoral/admin)`.")
  (:export #:register-admin #:admin #:job-queue-view))

(in-package #:littoral.admin)

(defvar *admins* (make-hash-table :test 'equal)
  "Application path → the classes its admin manages.")

(defun admin-classes ()
  "The classes the current admin application manages."
  (gethash (application-path *application*) *admins*))

(defun class-label (class &optional plural)
  "CLASS's name for people, from its description: \"Shelf\", or with
PLURAL \"Shelves\"."
  (let ((description (find-description class)))
    (if plural (description-plural description) (description-label description))))

(defun class-fields (class)
  "CLASS's described fields."
  (description-fields (find-description class)))

(defun text-fields (class)
  "CLASS's fields searched by the search box."
  (remove-if-not (lambda (f) (and (typep f 'string-field) (not (typep f 'password-field))))
                 (class-fields class)))

(defun filter-fields (class)
  "CLASS's fields offered as filters: choices and yes/no."
  (remove-if-not (lambda (f) (and (typep f '(or choice-field boolean-field))
                                  (not (typep f 'reference-field))))
                 (class-fields class)))

(defun referring-fields (class)
  "Pairs (OTHER-CLASS . FIELD) for the reference fields, among the admin's
classes, that point at CLASS."
  (loop for other in (admin-classes)
        append (loop for field in (class-fields other)
                     when (and (typep field 'reference-field) (eq (reference-class field) class))
                       collect (cons other field))))

;;; One object

(defclass object-page (component)
  ((class :initarg :class :reader page-class)
   (id :initarg :object-id :reader page-object-id)
   (admin :initarg :admin :reader page-admin))
  (:documentation "One stored object: its fields, references, and actions."))

(defun render-value (field value admin)
  "VALUE of FIELD; references link to the object they refer to."
  (if (and (typep field 'reference-field) value)
      (anchor (:callback (lambda () (open-object admin (reference-class field) (object-id value))))
        (text (format-field field value)))
      (render-field-value field value)))

(defmethod render ((self object-page))
  (let* ((class (page-class self))
         (admin (page-admin self))
         (object (db-find class (page-object-id self))))
    (if (null object)
        (progn (p () (translate "This record no longer exists."))
               (p () (anchor (:callback (lambda () (answer self))) (translate "Back"))))
        (progn
          (h2 () (text (format nil "~A #~D" (class-label class) (object-id object))))
          (table (:class "lt-table lt-viewer")
            (dolist (field (class-fields class))
              (unless (or (typep field 'password-field) (field-hidden-p field))
                (tr () (th () (text (field-label field)))
                  (td () (render-value field (field-value field object) admin))))))
          (div (:class "lt-buttons")
            ;; Spaces between, so the links read apart without the
            ;; stylesheet too (in text browsers, reader views, copied text).
            (anchor (:class "action" :callback (lambda () (edit-object admin class (object-id object))))
              (translate "Edit"))
            " "
            (anchor (:class "action" :callback (lambda () (delete-object admin self object)))
              (translate "Delete"))
            " "
            (anchor (:callback (lambda () (answer self))) (translate "Back to the list")))
          ;; Those that refer to this one.
          (loop for (other . field) in (referring-fields class)
                for related = (db-select other :where (format nil "~A = ?"
                                                              (substitute #\_ #\- (string-downcase (symbol-name (field-name field)))))
                                               :params (list (object-id object)))
                when related
                  do (h3 () (text (format nil "~A with this ~A" (class-label other t)
                                          (string-downcase (class-label class)))))
                     (ul ()
                       (dolist (r related)
                         (let ((r r) (other other))
                           (li () (anchor (:callback (lambda () (open-object admin other (object-id r))))
                                    (text (object-title r))))))))))))

(defun object-title (object)
  "A line naming OBJECT: its first text field, or its number."
  (let ((field (first (text-fields (class-name (class-of object))))))
    (or (and field (field-value field object))
        (format nil "#~D" (object-id object)))))

;;; The list of one class

(defclass class-list (component updatable)
  ((class :initarg :class :reader list-class)
   (admin :initarg :admin :reader list-admin)
   (query :initform "" :accessor list-query)
   (filters :initform '() :accessor list-filters
            :documentation "Alist of field name → the value it must have.")
   (report :reader list-report))
  (:documentation "The stored objects of one class, searchable and filterable."))

(defmethod states ((self class-list))
  (list self))

(defmethod children ((self class-list))
  (list (list-report self)))

(defun matching-objects (list)
  "LIST's objects that match its search and filters, as SQL decides."
  (let ((clauses '()) (params '())
        (query (string-trim " " (list-query list)))
        (class (list-class list)))
    (when (string/= query "")
      ;; The full-text index when the table has one, else LIKE over text fields.
      (multiple-value-bind (search-where search-params) (search-condition class query)
        (cond (search-where
               (push search-where clauses)
               (dolist (p search-params) (push p params)))
              ((text-fields class)
               ;; LOWER on both sides: PostgreSQL's LIKE minds case, SQLite's doesn't.
               (push (format nil "(~{LOWER(~A) LIKE LOWER(?)~^ OR ~})"
                             (mapcar (lambda (f) (substitute #\_ #\- (string-downcase (symbol-name (field-name f)))))
                                     (text-fields class)))
                     clauses)
               (dolist (f (text-fields class))
                 (declare (ignore f))
                 (push (format nil "%~A%" query) params))))))
    (loop for (name . value) in (list-filters list)
          for field = (find-field class name)
          do (push (format nil "~A = ?" (substitute #\_ #\- (string-downcase (symbol-name name)))) clauses)
             (push (to-sql field value) params))
    (db-select class :where (and clauses (format nil "~{~A~^ AND ~}" (reverse clauses)))
                     :params (reverse params))))

(defmethod initialize-instance :after ((self class-list) &key)
  (let ((class (list-class self)) (admin (list-admin self)))
    (setf (slot-value self 'report)
          (make-instance
           'report
           :rows (lambda () (matching-objects self))
           :batch-size 20
           :columns (append
                     (list (column "#" #'object-id :class "number"
                                   :render (lambda (object id)
                                             (declare (ignore object))
                                             (anchor (:callback (lambda () (open-object admin class id)))
                                               (text id)))))
                     (loop for field in (class-fields class)
                           unless (or (typep field 'password-field) (typep field 'text-field)
                                      (field-hidden-p field)
                                      (not (littoral::field-in-report-p field)))
                             collect (let ((field field))
                                       (column (field-label field) (littoral::field-reader field)
                                               :sort-key (lambda (o)
                                                           (let ((v (field-value field o)))
                                                             (if (typep field 'reference-field)
                                                                 (and v (format-field field v))
                                                                 (if (listp v) (format-field field v) v))))
                                               :render (lambda (object value)
                                                         (declare (ignore object))
                                                         (render-value field value admin))))))))))

(defun set-filter (list name value)
  "Filter LIST on field NAME having VALUE, or not at all for :ANY."
  (setf (list-filters list)
        (if (eq value :any)
            (remove name (list-filters list) :key #'car)
            (acons name value (remove name (list-filters list) :key #'car)))))

(defmethod render ((self class-list))
  (let ((class (list-class self)))
    (div (:class "admin-list")
      (div (:class "admin-controls")
        (text-input (:id "search" :label "Search" :placeholder "Search" :value (list-query self)
                     :callback (lambda (v) (setf (list-query self) v))
                     :on-input (ajax-update self)))
        (dolist (field (filter-fields class))
          (let* ((field field)
                 (name (field-name field))
                 (current (or (cdr (assoc name (list-filters self))) :any)))
            (label () (text (field-label field)) " "
              (select-list (:items (cons :any (if (typep field 'boolean-field) '(t nil) (field-choices field)))
                            :selected current
                            :labels (lambda (v)
                                      (cond ((eq v :any) (translate "Any"))
                                            ((typep field 'boolean-field) (if v (translate "Yes") (translate "No")))
                                            (t (format-field field v))))
                            :callback (lambda (v) (set-filter self name v))
                            :on-change (ajax-update self)))))))
      (let ((count (length (matching-objects self))))
        (p (:class "admin-count") (text (format nil "~D ~A" count (string-downcase (class-label class (/= count 1)))))))
      (render-component (list-report self)))))

;;; The job queue

(defparameter *job-page-size* 25)

(defclass job-queue-view (component)
  ((status :initform nil :accessor view-status :documentation "The status shown, or NIL for all.")
   (offset :initform 0 :accessor view-offset)
   (on-change :initarg :on-change :initform nil :reader view-on-change
              :documentation "Called with a message after a job is retried or cancelled."))
  (:documentation "The durable jobs of the current database, newest first, by
status, with Retry for failed and cancelled jobs and Cancel for waiting ones.
Shows everything: put it where only those who may see it can."))

(defmethod states ((self job-queue-view)) (list self))

(defun status-label (status)
  (cond ((null status) (translate "All"))
        ((string= status "queued") (translate "Queued"))
        ((string= status "running") (translate "Running"))
        ((string= status "done") (translate "Done"))
        ((string= status "failed") (translate "Failed"))
        ((string= status "cancelled") (translate "Cancelled"))
        (t status)))

(defun time-text (time)
  (if time
      (multiple-value-bind (s m h date month year) (decode-universal-time time)
        (format nil "~D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D" year month date h m s))
      ""))

(defun first-line (text)
  (subseq text 0 (or (position #\Newline text) (length text))))

(defun job-call-text (job)
  "JOB's name and arguments, as a call: (send-digest 42)."
  (let ((name (littoral.jobs:durable-job-name job))
        (arguments (littoral.jobs:durable-job-arguments job)))
    (with-standard-io-syntax
      (let ((*print-readably* nil))
        (format nil "(~(~A~)~{ ~S~})" (if (symbolp name) (symbol-name name) name)
                (if (listp arguments) arguments (list arguments)))))))

(defun job-action (view action job)
  "Retry or cancel JOB (ACTION :RETRY or :CANCEL), record it, and tell VIEW's owner."
  (littoral.auth:check-application-role)
  (let* ((id (littoral.jobs:durable-job-id job))
         (done (if (eq action :retry)
                   (littoral.jobs:retry-durable-job id)
                   (littoral.jobs:cancel-durable-job id))))
    (when done
      (multiple-value-bind (actor-id actor-name) (admin-actor)
        (littoral.audit:audit (if (eq action :retry) "job.retried" "job.cancelled")
                              :actor-id actor-id :actor-name actor-name
                              :subject (format nil "job:~D" id)
                              :subject-label (format nil "Job #~D ~A" id (job-call-text job)))))
    (when (view-on-change view)
      (funcall (view-on-change view)
               (cond ((not done) (translate "Job #~D has changed meanwhile; nothing was done." id))
                     ((eq action :retry) (translate "Job #~D will run again." id))
                     (t (translate "Cancelled job #~D." id)))))))

(defmethod render ((self job-queue-view))
  (let* ((counts (littoral.jobs:durable-job-counts))
         (jobs (littoral.jobs:durable-jobs :status (view-status self) :limit (1+ *job-page-size*)
                                           :offset (view-offset self)))
         (more (> (length jobs) *job-page-size*)))
    (div (:class "lt-job-queue")
      (nav (:class "lt-job-statuses" :aria-label (translate "Status"))
        (dolist (status '(nil "queued" "running" "failed" "done" "cancelled"))
          (let ((status status)
                (count (if status
                           (or (cdr (assoc status counts :test #'string=)) 0)
                           (reduce #'+ counts :key #'cdr))))
            (anchor (:aria-current (when (equal status (view-status self)) "page")
                     :callback (lambda () (setf (view-status self) status (view-offset self) 0)))
              (text (format nil "~A (~D)" (status-label status) count)))
            (text " ")))
        (anchor (:class "lt-job-refresh" :callback (lambda ())) (translate "Refresh")))
      (if (null jobs)
          (p () (translate "No jobs."))
          (table (:class "lt-table lt-job-table")
            (caption (:class "lt-visually-hidden") (translate "Jobs, newest first"))
            (tr () (th () "#") (th () (translate "Job")) (th () (translate "Queue")) (th () (translate "Status"))
                (th () (translate "Tries")) (th () (translate "When")) (th () (translate "Details")) (th () ""))
            (dolist (job (subseq jobs 0 (min (length jobs) *job-page-size*)))
              (let ((job job)
                    (status (littoral.jobs:durable-job-status job))
                    (error-text (littoral.jobs:durable-job-last-error job)))
                (tr ()
                  (td () (text (princ-to-string (littoral.jobs:durable-job-id job))))
                  (td () (code () (text (job-call-text job))))
                  (td () (text (littoral.jobs:durable-job-queue job)))
                  (td (:class (format nil "lt-job-~A" status)) (text (status-label status)))
                  (td () (text (princ-to-string (littoral.jobs:durable-job-attempts job))))
                  (td (:class "lt-job-time")
                    (text (time-text (if (member status '("queued" "running") :test #'string=)
                                         (littoral.jobs:durable-job-run-at job)
                                         (littoral.jobs:durable-job-finished job)))))
                  (td ()
                    (when (littoral.jobs:durable-job-progress job)
                      (p () (text (littoral.jobs:durable-job-progress job))))
                    (when (and error-text (plusp (length error-text)))
                      (details ()
                        (summary () (text (first-line error-text)))
                        (pre () (text error-text)))))
                  (td ()
                    (cond ((member status '("failed" "cancelled") :test #'string=)
                           (anchor (:callback (lambda () (job-action self :retry job))) (translate "Retry")))
                          ((string= status "queued")
                           (anchor (:callback (lambda () (job-action self :cancel job))) (translate "Cancel"))))))))))
      (p (:class "lt-job-pages")
        (when (plusp (view-offset self))
          (anchor (:callback (lambda () (setf (view-offset self) (max 0 (- (view-offset self) *job-page-size*)))))
            (translate "« Newer")))
        " "
        (when more
          (anchor (:callback (lambda () (incf (view-offset self) *job-page-size*)))
            (translate "Older »")))))))

(defmethod style ((self job-queue-view))
  ".lt-job-statuses { display: flex; flex-wrap: wrap; gap: .4rem 1rem; margin-bottom: .6rem; }
.lt-job-statuses a[aria-current] { font-weight: 600; }
.lt-job-refresh { margin-left: auto; }
.lt-job-queue { overflow-x: auto; }
.lt-job-table td { vertical-align: top; }
.lt-job-table pre { white-space: pre-wrap; font-size: .8rem; max-width: 40rem; }
.lt-job-time { white-space: nowrap; }
.lt-job-failed { color: var(--lt-error, #b00020); font-weight: 600; }")

;;; The application

(defclass admin (component)
  ((lists :initform (make-hash-table) :reader admin-lists)
   (selected :accessor admin-selected)
   (message :initform nil :accessor admin-message)
   (audit :initform (make-instance 'littoral.audit:audit-log-view) :reader admin-audit-view)
   (jobs :reader admin-jobs-view)
   (main :reader admin-main))
  (:documentation "The root of an admin application: header, messages and
menu stay; pages replace the main area."))

(defclass main-area (component)
  ((admin :initarg :admin :reader area-admin))
  (:documentation "Where an admin shows the selected class's list, or the
page shown in its place."))

(defmethod initialize-instance :after ((self admin) &key)
  (setf (admin-selected self) (first (admin-classes))
        (slot-value self 'main) (make-instance 'main-area :admin self)
        (slot-value self 'jobs) (make-instance 'job-queue-view
                                               :on-change (lambda (message) (setf (admin-message self) message)))))

(defmethod states ((self admin))
  (list self))

(defun class-list-for (admin class)
  "ADMIN's list for CLASS, made once."
  (or (gethash class (admin-lists admin))
      (setf (gethash class (admin-lists admin)) (make-instance 'class-list :class class :admin admin))))

(defmethod children ((self admin))
  (list (admin-main self)))

(defmethod children ((self main-area))
  (let ((admin (area-admin self)))
    (case (admin-selected admin)
      (:audit-log (list (admin-audit-view admin)))
      (:job-queue (list (admin-jobs-view admin)))
      (t (list (class-list-for admin (admin-selected admin)))))))

(defmethod render ((self main-area))
  (let* ((admin (area-admin self))
         (class (admin-selected admin)))
    (cond ((eq class :audit-log)
           (h1 () (translate "Audit log"))
           (render-component (admin-audit-view admin)))
          ((eq class :job-queue)
           (h1 () (translate "Job queue"))
           (render-component (admin-jobs-view admin)))
          (t
           (h1 () (text (class-label class t)))
           (p () (anchor (:callback (lambda () (create-object admin class)))
                   (text (translate "New ~A" (string-downcase (class-label class))))))
           (render-component (class-list-for admin class))))))

(defun show-page (admin page &rest show-arguments)
  "Show PAGE in ADMIN's main area, replacing whatever page was there."
  (home (admin-main admin))
  (apply #'show (admin-main admin) page show-arguments))

(defun open-object (admin class id)
  "Show the object of CLASS numbered ID in ADMIN's main area."
  (show-page admin (make-instance 'object-page :class class :object-id id :admin admin)))

(defun admin-actor ()
  "Who is using the admin, for the audit log, as an id and a name: the
signed-in user, the name in its credentials, or else someone on this machine."
  (let ((user (littoral.auth:current-user))
        (credentials (application-credentials *application*)))
    (cond (user (values (princ-to-string (littoral.auth:user-id user)) (littoral.auth:user-name user)))
          (credentials (values nil (first credentials)))
          (t (values nil "local admin")))))

(defun audit-record (action class id title &rest details)
  "Record ACTION, done through the admin to the object of CLASS numbered ID,
called TITLE."
  (multiple-value-bind (actor-id actor-name) (admin-actor)
    (littoral.audit:audit action :actor-id actor-id :actor-name actor-name
                                 :subject (format nil "~(~A~):~A" (table-name (find-table class)) id)
                                 :subject-label (format nil "~A #~A ~A" (class-label class) id title)
                                 :details details)))

(defun changed-fields (class old new)
  "The fields whose values differ between OLD and NEW: a plist of field
name → \"old → new\", passwords shown only as changed."
  (loop for field in (class-fields class)
        for before = (and old (format-field field (field-value field old)))
        for after = (format-field field (field-value field new))
        unless (equal before after)
          append (list (field-name field)
                       (if (typep field 'password-field) "changed" (format nil "~A → ~A" (or before "") after)))))

(defun save-edited (admin class edited)
  "Save EDITED; on someone else's change, say so and show theirs."
  (littoral.auth:check-application-role)
  (handler-case (let ((old (db-find class (object-id edited))))
                  (db-save edited)
                  (apply #'audit-record "record.updated" class (object-id edited) (object-title edited)
                         (changed-fields class old edited))
                  (setf (admin-message admin) (translate "Saved ~A #~D." (class-label class) (object-id edited)))
                  (open-object admin class (object-id edited)))
    (stale-object ()
      (setf (admin-message admin) (translate "Someone else changed this record meanwhile; here it is as they left it."))
      (open-object admin class (object-id edited)))))

(defun edit-object (admin class id)
  "Edit the object of CLASS numbered ID, then save it."
  (let ((object (db-find class id)))
    (when object
      (show-page admin (make-editor object :title (translate "Edit ~A #~D" (class-label class) id))
            :on-answer (lambda (edited)
                         (if edited
                             (save-edited admin class edited)
                             (open-object admin class id)))))))

(defun create-object (admin class)
  "Ask for a new object of CLASS, then store it."
  (show-page admin (make-editor (make-instance class) :title (translate "New ~A" (string-downcase (class-label class)))
                                                  :save-label "Create")
        :on-answer (lambda (object)
                     (when object
                       (littoral.auth:check-application-role)
                       (db-insert object)
                       (apply #'audit-record "record.created" class (object-id object) (object-title object)
                              (changed-fields class nil object))
                       (setf (admin-message admin)
                             (translate "Created ~A #~D." (class-label class) (object-id object)))
                       (open-object admin class (object-id object))))))

(defun delete-object (admin page object)
  "Ask, then delete OBJECT."
  (show page (make-instance 'confirm-dialog
                            :message (translate "Delete ~A #~D, ~A?" (class-label (page-class page))
                                             (object-id object) (object-title object)))
        :on-answer (lambda (yes)
                     (when yes
                       (littoral.auth:check-application-role)
                       (handler-case
                           (let ((id (object-id object)) (title (object-title object)))
                             (db-delete object)
                             (audit-record "record.deleted" (page-class page) id title)
                             (setf (admin-message admin)
                                   (translate "Deleted ~A #~D." (class-label (page-class page))
                                              (page-object-id page))))
                         (stale-object ()
                           (setf (admin-message admin)
                                 "Someone else changed or deleted this record meanwhile; nothing was deleted.")))
                       (home (admin-main admin))))))

(defun menu-entry (admin page label)
  "A menu entry for one of ADMIN's own pages, such as the audit log."
  (let ((current (eq (admin-selected admin) page)))
    (li (:class (when current "lt-active"))
      (anchor (:aria-current (when current "page")
               :callback (lambda ()
                           (home (admin-main admin))
                           (setf (admin-selected admin) page
                                 (admin-message admin) nil)))
        (text label)))))

(defmethod render ((self admin))
  (header (:class "admin-header")
    (strong () (text (or (application-title *application*) "Admin")))
    (let ((user (littoral.auth:current-user)))
      (when user
        (span (:class "admin-user") (text (littoral.auth:user-name user)) " · " (littoral.auth:sign-out-link)))))
  (when (admin-message self)
    (p (:class "lt-message notice" :role "status") (text (admin-message self))))
  (div (:class "admin-body")
    (nav (:class "admin-menu" :aria-label (translate "Tables"))
      (ul ()
        (dolist (class (admin-classes))
          (let ((class class))
            (li (:class (when (eq class (admin-selected self)) "lt-active"))
              (anchor (:aria-current (when (eq class (admin-selected self)) "page")
                       :callback (lambda ()
                                   (home (admin-main self))
                                   (setf (admin-selected self) class
                                         (admin-message self) nil)))
                (text (class-label class t))))))
        (when (littoral.audit:audit-enabled-p)
          (menu-entry self :audit-log (translate "Audit log")))
        (when (littoral.jobs:job-tables-p)
          (menu-entry self :job-queue (translate "Job queue")))))
    (section (:class "admin-main")
      (render-component (admin-main self)))))

(defmethod style ((self admin))
  ".admin-header { display: flex; justify-content: space-between; align-items: baseline; gap: 1rem; flex-wrap: wrap; border-bottom: 1px solid var(--lt-border); padding-bottom: .4rem; margin-bottom: .8rem; }
.admin-body { display: grid; grid-template-columns: 11rem minmax(0, 1fr); gap: 1.5rem; }
@media (max-width: 40rem) { .admin-body { grid-template-columns: minmax(0, 1fr); } }
.admin-menu ul { list-style: none; padding: 0; margin: 0; }
.admin-menu a { display: block; padding: .3rem .6rem; border-radius: 4px; text-decoration: none; }
.admin-menu li.lt-active a { background: var(--lt-panel); font-weight: 600; }
.admin-controls { display: flex; flex-wrap: wrap; gap: .8rem; align-items: center; margin-bottom: .4rem; }
.admin-count { color: var(--lt-muted); font-size: .9rem; }
.admin-main { overflow-x: auto; }
a.action { margin-right: .8rem; }")

(defclass signed-in-admin (littoral.auth:signed-in-root admin) ()
  (:documentation "An admin that users with its role sign in to."))

(defun register-admin (path classes &key (title "Admin") database role credentials (mode :deployment) (audit t))
  "Serve an admin for CLASSES (stored classes, see DEFINE-TABLE) at PATH.
DATABASE (a driver and parameters, as CONNECT-DATABASE takes them) gives
it its own database; otherwise it uses the current one.  With ROLE, users
with that role (any signed-in user, for T) sign in to it, from anywhere: the
database must hold littoral/auth's tables.  With CREDENTIALS instead, it asks
for HTTP basic auth.  With neither, it answers only requests from this machine.  With AUDIT (the
default), it records what it creates, changes and deletes in the audit log
(creating its table) and shows the log."
  (when (and role credentials)
    (error "REGISTER-ADMIN takes :ROLE or :CREDENTIALS, not both."))
  (setf (gethash (littoral::normalize-path path) *admins*) classes)
  (littoral.auth:restrict-application path role)
  (let ((*database* (or database *database*)))
    (when (and audit *database*)
      (littoral.audit:create-audit-tables)))
  (register-application path (if role 'signed-in-admin 'admin)
                        :title title :mode mode
                        :credentials credentials
                        :local-only (not (or role credentials))
                        :around-request (and database (apply #'using-database database))
                        :around-actions (transactional)))
