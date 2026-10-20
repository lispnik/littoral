;;;; The audit log: recording who did what, and reading it back.

;;;; Example: littoral.audit:audit littoral.audit:create-audit-tables littoral.audit:drop-audit-tables littoral.audit:audit-events littoral.audit:audit-event littoral.audit:audit-event-action littoral.audit:audit-event-actor-id littoral.audit:audit-event-actor-name littoral.audit:audit-event-subject littoral.audit:audit-event-subject-label littoral.audit:audit-event-details
;;; An event names an action, what it was done to, and details kept as JSON; it reads back with its details as an alist, sorted by key.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                              :details '(:to "ada@example.org" :copies 2)
                                              :actor-id "7" :actor-name "Zoë")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-action event)
                 (littoral.audit:audit-event-actor-id event)
                 (littoral.audit:audit-event-actor-name event)
                 (littoral.audit:audit-event-subject event)
                 (littoral.audit:audit-event-subject-label event)
                 (littoral.audit:audit-event-details event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("invoice.sent" "7" "Zoë" "invoice:42" "Invoice 42" (("copies" . 2) ("to" . "ada@example.org")))

;;;; Example: littoral.audit:audit-event-id littoral.audit:audit-event-time littoral.audit:audit-event-address
;;; Each event has an id and a time; its address is the client's, so NIL outside a request.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "report.exported" :actor-id nil)
         (let ((event (first (littoral.audit:audit-events))))
           (list (integerp (littoral.audit:audit-event-id event))
                 (<= (- (get-universal-time) 2) (littoral.audit:audit-event-time event) (get-universal-time))
                 (littoral.audit:audit-event-address event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ (T T NIL)

;;;; Example: littoral.audit:audit-events littoral.audit:audit-actions
;;; Finding events: an action matches itself and the actions under it, newest first; SEARCH looks in the names of who and what.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :subject "invoice:42" :actor-id "7" :actor-name "Zoë")
         (littoral.audit:audit "invoice.paid" :subject "invoice:42" :actor-id "8" :actor-name "Bob")
         (littoral.audit:audit "invoices" :subject "invoice:43" :actor-id "7" :actor-name "Zoë")
         (flet ((actions (&rest filters)
                  (mapcar #'littoral.audit:audit-event-action (apply #'littoral.audit:audit-events filters))))
           (list (actions :action "invoice")
                 (actions :subject "invoice:42")
                 (actions :actor "7")
                 (actions :search "bob")
                 (actions :limit 1)
                 (actions :since (+ (get-universal-time) 60))
                 (littoral.audit:audit-actions))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ (("invoice.paid" "invoice.sent") ("invoice.paid" "invoice.sent") ("invoices" "invoice.sent") ("invoice.paid") ("invoices") NIL ("invoice.paid" "invoice.sent" "invoices"))

;;;; Example: littoral.audit:*audit-actor*
;;; Who is acting, when an event doesn't say.  littoral/auth makes it the signed-in user; here it is fixed.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.audit:*audit-actor* (lambda () (values "7" "Zoë"))))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "report.exported")
         (let ((event (first (littoral.audit:audit-events))))
           (list (littoral.audit:audit-event-actor-id event) (littoral.audit:audit-event-actor-name event))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("7" "Zoë")

;;;; Example: littoral.audit:*audit-hook* littoral.audit:audit-enabled-p
;;; The hook sees every event as a plist, even where no audit table records it.
(let* ((littoral.db:*database* nil)
       (seen '())
       (littoral.audit:*audit-hook* (lambda (event) (push event seen))))
  (list (littoral.audit:audit-enabled-p)
        (littoral.audit:audit "cache.cleared" :details '(:entries 120) :actor-id nil)
        (getf (first seen) :action)
        (getf (first seen) :details)))
;; ⇒ (NIL "cache.cleared" "cache.cleared" (:ENTRIES 120))

;;;; Example: littoral.audit:audit-enabled-p
;;; Events are recorded only in a database whose audit tables were made in this process.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (list (littoral.audit:audit-enabled-p)
        (progn (littoral.audit:drop-audit-tables)
               (littoral.audit:audit-enabled-p))))
;; ⇒ (T NIL)

;;;; Example: littoral.audit:audit
;;; An event is written in the current transaction, so it goes when its action rolls back.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (ignore-errors
          (littoral.db:with-transaction ()
            (littoral.audit:audit "invoice.sent" :subject "invoice:42" :actor-id nil)
            (error "The mail couldn't be queued.")))
         (littoral.audit:audit-events))
    (littoral.audit:drop-audit-tables)))
;; ⇒ NIL

;;;; Example: littoral.audit:purge-audit-log
;;; Deletes events more than a year old, unless told otherwise.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "invoice.sent" :actor-id nil)
         (list (littoral.audit:purge-audit-log)
               (littoral.audit:purge-audit-log :older-than -60)
               (littoral.audit:audit-events)))
    (littoral.audit:drop-audit-tables)))
;; ⇒ (0 1 NIL)

;;;; Example: littoral.audit:audit-log-view
;;; A page to look through the log, newest first, filtered by action and by who or what.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (with-fresh-applications (("/audit" 'littoral.audit:audit-log-view :mode :deployment))
         (let ((b (make-instance 'browser)))
           (visit b "/audit")
           (let ((empty (not (null (has-text-p b "Nothing has been recorded.")))))
             (littoral.audit:audit "invoice.sent" :subject-label "Invoice 42" :actor-id "7" :actor-name "Zoë")
             (visit b "/audit")
             (list empty
                   (not (null (search "Zoë invoice.sent Invoice 42" (body-text b))))))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ (T T)

;;;; Example: littoral.audit:activity-feed littoral.audit:*audit-channel*
;;; What's happened lately, newest first, a batch at a time with a button for older events: who did what to what, and how long ago.  Events recorded in this process reach open pages as they happen, through `*audit-channel*`.  `:action`, `:actor` and `:subject` narrow it, and `:describe` says what was done in your own words.
(defclass recent-page (component)
  ((feed :reader feed :initform (make-instance 'littoral.audit:activity-feed :batch-size 2))))
(defmethod children ((self recent-page)) (list (feed self)))
(defmethod render ((self recent-page)) (render-component (feed self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.audit:create-audit-tables)
  (unwind-protect
       (progn
         (littoral.audit:audit "record.created" :subject-label "Invoice 42" :actor-id "1" :actor-name "Ada")
         (littoral.audit:audit "record.updated" :subject-label "Invoice 42" :actor-id "2" :actor-name "Grace")
         (littoral.audit:audit "invoice.sent" :subject-label "Invoice 42" :actor-id "1" :actor-name "Ada")
         (with-fresh-applications (("/recent" 'recent-page :mode :deployment))
           (let ((b (make-instance 'browser)))
             (visit b "/recent")
             (list (body-text b)
                   (typep littoral.audit:*audit-channel* 'channel)))))
    (littoral.audit:drop-audit-tables)))
;; ⇒ ("Ada invoice.sent Invoice 42 just now Grace changed Invoice 42 just now Older activity Showing 2." T)

;;;; Example: littoral.audit:activity-phrase littoral.audit:*activity-phrases*
;;; The words an activity feed uses for an action, translated; `*activity-phrases*` holds them for the actions Littoral records, and an application can add its own.
(let ((littoral.audit:*activity-phrases* (acons "invoice.sent" "sent" littoral.audit:*activity-phrases*)))
  (list (littoral.audit:activity-phrase "invoice.sent")
        (littoral.audit:activity-phrase "sign-in")
        (let ((littoral::*language* "es")) (littoral.audit:activity-phrase "sign-in"))
        (littoral.audit:activity-phrase "something.else")))
;; ⇒ ("sent" "signed in" "ha iniciado sesión" NIL)
