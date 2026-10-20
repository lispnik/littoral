;;;; audit.lisp — the audit log, and what auth and the admin record in it

(in-package #:littoral/tests)

(def-suite audit :in littoral)
(in-suite audit)

(defmacro with-audit-log (() &body body)
  `(progn
     (connect-test-database)
     (littoral.audit:drop-audit-tables)
     (littoral.audit:create-audit-tables)
     ,@body))

(defun audit-actions-recorded (&rest arguments)
  "The actions of the events ARGUMENTS select, oldest first."
  (reverse (mapcar #'littoral.audit:audit-event-action (apply #'littoral.audit:audit-events arguments))))

(test audit-records-and-finds-events
  (with-audit-log ()
    (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42"
                                         :actor-id "7" :actor-name "Zoë"
                                         :details '(:to "ada@example.org" :copies 2 :urgent t :tags ("a" "b") :note nil))
    (littoral.audit:audit "invoice.paid" :subject "invoice:42" :actor-id nil)
    (littoral.audit:audit "invoices" :subject "invoice:43" :actor-id nil)
    (let ((event (first (littoral.audit:audit-events :action "invoice.sent"))))
      (is (string= "Zoë" (littoral.audit:audit-event-actor-name event)))
      (is (string= "7" (littoral.audit:audit-event-actor-id event)))
      (is (string= "Invoice 42" (littoral.audit:audit-event-subject-label event)))
      (is (<= (abs (- (get-universal-time) (littoral.audit:audit-event-time event))) 2))
      (is (equal '(("copies" . 2) ("note" . null) ("tags" "a" "b") ("to" . "ada@example.org") ("urgent" . t))
                 (littoral.audit:audit-event-details event))))
    (is (equal '("invoice.sent" "invoice.paid") (audit-actions-recorded :action "invoice"))
        "An action matches those under it, not others that start alike")
    (is (equal '("invoice.sent" "invoice.paid") (audit-actions-recorded :subject "invoice:42")))
    (is (equal '("invoice.sent") (audit-actions-recorded :actor "7")))
    (is (equal '("invoice.sent") (audit-actions-recorded :search "zoë")))
    (is (equal '("invoice.paid" "invoices") (audit-actions-recorded :limit 2)) "Newest first")
    (is (equal '("invoice.paid" "invoice.sent" "invoices") (littoral.audit:audit-actions)))
    (is (= 0 (littoral.audit:purge-audit-log)))
    (littoral.db:db-execute "UPDATE audit_log SET at = 0 WHERE action = 'invoices'")
    (is (= 1 (littoral.audit:purge-audit-log)))))

(test audit-without-tables-does-nothing
  (connect-test-database)
  (littoral.audit:drop-audit-tables)
  (let* ((seen '())
         (littoral.audit:*audit-hook* (lambda (event) (push event seen))))
    (is (not (littoral.audit:audit-enabled-p)))
    (finishes (littoral.audit:audit "thing.done" :details '(:x 1)))
    (is (equal "thing.done" (getf (first seen) :action)) "The hook sees it all the same")))

(test audit-events-roll-back-with-their-action
  (with-audit-log ()
    (ignore-errors
     (littoral.db:with-transaction ()
       (littoral.audit:audit "thing.done")
       (error "the action failed")))
    (is (null (littoral.audit:audit-events)))))

(test auth-records-sign-ins-and-changes
  (with-auth (b)
    (click b "Sign in")
    (loop for (name password) in '(("ada" "wrong") ("nobody" "whatever") ("ada" "correct horse battery"))
          do (fill-in b "sign-in-name" name)
             (fill-in b "sign-in-password" password)
             (press b "Sign in"))
    (let ((events (littoral.audit:audit-events :action "sign-in")))
      (is (equal '("sign-in" "sign-in.failed" "sign-in.failed") (mapcar #'littoral.audit:audit-event-action events)))
      (destructuring-bind (success unknown wrong) events
        (is (equal "ada" (littoral.audit:audit-event-actor-name success)))
        (is (equal "password" (cdr (assoc "method" (littoral.audit:audit-event-details success) :test #'string=))))
        (is (equal "unknown-user" (cdr (assoc "reason" (littoral.audit:audit-event-details unknown) :test #'string=))))
        (is (equal "nobody" (littoral.audit:audit-event-subject-label unknown)))
        (is (null (littoral.audit:audit-event-actor-id unknown)))
        (is (equal "wrong-password" (cdr (assoc "reason" (littoral.audit:audit-event-details wrong) :test #'string=))))
        (is (equal (format nil "user:~A" (littoral.auth:user-id (littoral.auth:find-user "ada")))
                   (littoral.audit:audit-event-subject wrong)))))
    ;; Outside a request there's no signed-in actor; still recorded.
    (let* ((bob (littoral.auth:find-user "bob"))
           (subject (format nil "user:~A" (littoral.auth:user-id bob))))
      (littoral.auth:grant-role bob :editor)
      (littoral.auth:grant-role bob :editor)
      (littoral.auth:revoke-role bob :editor)
      (is (equal '("user.created" "role.granted" "role.revoked") (audit-actions-recorded :subject subject))
          "Only real changes"))
    (click b "Sign out")
    (let ((event (first (littoral.audit:audit-events))))
      (is (equal "sign-out" (littoral.audit:audit-event-action event)))
      (is (equal "ada" (littoral.audit:audit-event-actor-name event)) "The signed-in user is the actor")
      (is (equal "ada" (littoral.audit:audit-event-subject-label event))))
    (is (equal '("user.created" "user.created") (audit-actions-recorded :action "user")) "From WITH-AUTH")))

(test admin-records-what-it-changes
  (with-admin (b)
    (littoral.db:db-execute "DELETE FROM audit_log")
    (click-nth b "1" 0)
    (click b "Edit")
    (fill-in b "budget" "250")
    (press b "Save")
    (let ((event (first (littoral.audit:audit-events :action "record.updated"))))
      (is (string= "project:1" (littoral.audit:audit-event-subject event)))
      (is (string= "local admin" (littoral.audit:audit-event-actor-name event)))
      (is (equal '(("budget" . "100 → 250")) (littoral.audit:audit-event-details event)) "Only what changed"))
    (click b "Audit log")
    (is (has-text-p b "record.updated"))
    (is (has-text-p b "budget: 100 → 250"))))

;;; The activity feed

(defclass feed-page (component)
  ((feed :initarg :feed :reader page-feed))
  (:documentation "A page showing an activity feed."))

(defmethod children ((self feed-page)) (list (page-feed self)))
(defmethod render ((self feed-page)) (render-component (page-feed self)))

(defvar *feed-under-test* nil "The feed FEED-PAGE shows, made by the test.")

(defclass test-feed-page (feed-page) ()
  (:default-initargs :feed *feed-under-test*)
  (:documentation "A FEED-PAGE showing *FEED-UNDER-TEST*."))

(defun record-sample-activity ()
  "Six events, oldest first."
  (littoral.audit:audit "sign-in" :subject "user:1" :subject-label "Ada" :actor-id "1" :actor-name "Ada")
  (littoral.audit:audit "record.created" :subject "invoice:42" :subject-label "Invoice 42" :actor-id "1" :actor-name "Ada")
  (littoral.audit:audit "sign-in.failed" :subject-label "bob" :actor-id nil)
  (littoral.audit:audit "invoice.sent" :subject "invoice:42" :subject-label "Invoice 42" :actor-id "1" :actor-name "Ada")
  (littoral.audit:audit "record.updated" :subject "invoice:42" :subject-label "Invoice 42" :actor-id "2" :actor-name "Grace")
  (littoral.audit:audit "sign-out" :subject "user:2" :subject-label "Grace" :actor-id "2" :actor-name "Grace"))

(test activity-feeds-say-what-happened
  (with-audit-log ()
    (record-sample-activity)
    (let ((*feed-under-test* (make-instance 'littoral.audit:activity-feed :batch-size 4)))
      (with-fresh-applications (("/feed" 'test-feed-page :mode :deployment))
        (let ((b (make-instance 'browser)))
          (visit b "/feed")
          (let ((text (body-text b)))
            (is (search "Grace signed out just now Grace changed Invoice 42 just now Ada invoice.sent Invoice 42 just now Someone failed to sign in as bob just now"
                        text)
                text)
            (is (not (search "Ada created" text)) "A batch at a time")
            (is (search "Older activity Showing 4." text)))
          (is (search "<code>invoice.sent</code>" (browser-html b)) "An action without a phrase is shown as it is")
          (is (search "<time datetime=" (browser-html b)))
          (click b "Older activity")
          (is (search "Ada created Invoice 42 just now Ada signed in just now" (body-text b))
              "Signing in doesn't name the user twice")
          (is (not (search "Older activity" (body-text b)))))))
    ;; Narrowed, and described by the application.
    (let ((*feed-under-test* (make-instance 'littoral.audit:activity-feed
                                            :action "record" :subject "invoice:42"
                                            :describe (lambda (e) (when (equal (littoral.audit:audit-event-action e) "record.updated")
                                                                    "tidied up")))))
      (with-fresh-applications (("/feed" 'test-feed-page :mode :deployment))
        (let ((b (make-instance 'browser)))
          (visit b "/feed")
          (is (search "Grace tidied up Invoice 42 just now Ada created Invoice 42 just now Showing 2." (body-text b))
              (body-text b)))))
    (is (equal "changed" (littoral.audit:activity-phrase "record.updated")))
    (is (null (littoral.audit:activity-phrase "invoice.sent")))
    (let ((littoral::*language* "fr"))
      (is (equal "a modifié" (littoral.audit:activity-phrase "record.updated"))))))

(test activity-feeds-hear-of-events-by-push
  ;; The stream renders in a thread of its own, with its own connection: a file for SQLite.
  (let ((file (unless (postgres-test-p)
                (namestring (merge-pathnames (format nil "littoral-feed-~36R.sqlite3" (random (expt 36 8)))
                                             (uiop:temporary-directory))))))
    (unwind-protect
         (progn
           (if file
               (littoral.db:connect-database :sqlite3 :database-name file)
               (connect-test-database))
           (littoral.audit:drop-audit-tables)
           (littoral.audit:create-audit-tables)
           (let ((*feed-under-test* (make-instance 'littoral.audit:activity-feed)))
             (with-fresh-applications (("/feed" 'test-feed-page :mode :deployment))
               (let ((b (make-instance 'browser)) (sink (make-instance 'sink)))
                 (visit b "/feed")
                 (is (search "data-lt-events" (browser-html b)) "The feed opens an event stream")
                 (let ((thread (open-stream b sink)))
                   ;; Rolled back: never heard of.
                   (ignore-errors
                    (littoral.db:with-transaction ()
                      (littoral.audit:audit "invoice.voided" :actor-id "1" :actor-name "Ada")
                      (error "No.")))
                   (sb-thread:join-thread
                    (sb-thread:make-thread
                     (lambda () (littoral.audit:audit "invoice.paid" :subject-label "Invoice 7" :actor-id "1" :actor-name "Ada"))))
                   (is (wait-for (lambda () (search "Invoice 7" (sink-text sink)))))
                   (is (not (search "invoice.voided" (sink-text sink))))
                   (close-event-streams)
                   (is (wait-for (lambda () (not (sb-thread:thread-alive-p thread))))))))))
      (littoral.audit:drop-audit-tables)
      (connect-test-database)
      (when file
        (dolist (suffix '("" "-wal" "-shm"))
          (uiop:delete-file-if-exists (concatenate 'string file suffix)))))))
