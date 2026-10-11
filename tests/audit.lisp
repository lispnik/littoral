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
