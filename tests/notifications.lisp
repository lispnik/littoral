;;;; notifications.lisp — notifications kept until read, and the bell

(in-package #:littoral/tests)

(def-suite notifications :in littoral)
(in-suite notifications)

(defmacro with-notification-users ((ada bob) &body body)
  "Fresh users and notifications tables in the test database, with ADA and BOB."
  `(progn
     (connect-test-database)
     (littoral.auth:drop-auth-tables)
     (littoral.notifications:drop-notification-tables)
     (littoral.auth:create-auth-tables)
     (littoral.notifications:create-notification-tables)
     (let ((,ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:admin)))
           (,bob (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")))
       (declare (ignorable ,ada ,bob))
       ,@body)))

(test notifications-wait-until-read
  (with-notification-users (ada bob)
    (let ((first (littoral.notifications:notify-user ada "First"))
          (second (littoral.notifications:notify-user ada "Second" :url "/somewhere" :kind :warning)))
      (littoral.notifications:notify-user (littoral.auth:user-id bob) "For bob")
      (is (= 2 (littoral.notifications:unread-notification-count ada)))
      (is (= 1 (littoral.notifications:unread-notification-count bob)))
      (let ((list (littoral.notifications:user-notifications ada)))
        (is (equal '("Second" "First") (mapcar #'littoral.notifications:notification-message list)) "Newest first")
        (is (equal "/somewhere" (littoral.notifications:notification-url (first list))))
        (is (eq :warning (littoral.notifications:notification-kind (first list))))
        (is (eq :info (littoral.notifications:notification-kind (second list))))
        (is (null (littoral.notifications:notification-url (second list))))
        (is (notany #'littoral.notifications:notification-read-p list)))
      ;; Bob can't mark ada's read.
      (is (not (littoral.notifications:mark-notification-read bob first)))
      (is (littoral.notifications:mark-notification-read ada first))
      (is (not (littoral.notifications:mark-notification-read ada first)) "Already read")
      (is (= 1 (littoral.notifications:unread-notification-count ada)))
      (is (equal '("Second")
                 (mapcar #'littoral.notifications:notification-message
                         (littoral.notifications:user-notifications ada :unread-only t))))
      (is (= 1 (length (littoral.notifications:user-notifications ada :limit 1))))
      (littoral.notifications:mark-all-notifications-read ada)
      (is (zerop (littoral.notifications:unread-notification-count ada)))
      (is (= 1 (littoral.notifications:unread-notification-count bob)))
      (is (littoral.notifications:notification-read-at
           (first (littoral.notifications:user-notifications ada))))
      (is (integerp second)))))

(test old-notifications-are-purged
  (with-notification-users (ada bob)
    (let ((old (littoral.notifications:notify-user ada "Old, read")))
      (littoral.notifications:notify-user ada "Old, unread")
      (littoral.notifications:notify-user ada "New, read")
      (littoral.notifications:mark-notification-read ada old)
      (littoral.db:db-execute "UPDATE notifications SET created = created - 1000, read_at = read_at - 1000 WHERE message LIKE 'Old%'")
      (littoral.notifications:mark-all-notifications-read bob)
      (littoral.db:db-execute "UPDATE notifications SET read_at = ? WHERE message = 'New, read'" (get-universal-time))
      (littoral.notifications:purge-notifications :older-than 500)
      (is (equal '("New, read" "Old, unread")
                 (mapcar #'littoral.notifications:notification-message (littoral.notifications:user-notifications ada))))
      (littoral.notifications:purge-notifications :older-than 500 :unread t)
      (is (equal '("New, read")
                 (mapcar #'littoral.notifications:notification-message (littoral.notifications:user-notifications ada)))))))

(test notifications-are-published-after-commit
  (with-notification-users (ada bob)
    (let ((published '()))
      (flet ((note (what) (lambda () (push what published))))
        ;; Outside a transaction, at once.
        (littoral.db:after-commit (note :now))
        (is (equal '(:now) published))
        ;; Inside, once it commits, in order.
        (littoral.db:with-transaction ()
          (littoral.db:after-commit (note :first))
          (littoral.db:with-transaction ()   ; nested: the same transaction
            (littoral.db:after-commit (note :second)))
          (is (equal '(:now) published)))
        (is (equal '(:second :first :now) published))
        ;; Never, when it rolls back.
        (ignore-errors
         (littoral.db:with-transaction ()
           (littoral.db:after-commit (note :rolled-back))
           (error "No")))
        (is (not (member :rolled-back published))))
      ;; A notification made in a rolled-back transaction doesn't exist.
      (ignore-errors
       (littoral.db:with-transaction ()
         (littoral.notifications:notify-user ada "Never")
         (error "No")))
      (is (zerop (littoral.notifications:unread-notification-count ada))))))

(defclass bell-app (littoral.auth:auth-root component)
  ((members :initform (make-instance 'members-area) :reader app-members)
   (bell :initform (make-instance 'littoral.notifications:notification-bell) :reader app-bell))
  (:documentation "A page with a notification bell, and a way to sign in."))

(defmethod children ((self bell-app)) (list (app-members self) (app-bell self)))

(defmethod render ((self bell-app))
  (p () "Bell page")
  (render-component (app-bell self))
  (render-component (app-members self)))

(defun bell-count-text (b)
  "The bell's unread count as the page shows it, or NIL when there's none."
  (cl-ppcre:register-groups-bind (n) ("<span class=\"lt-bell-count\" aria-hidden=\"true\">([^<]*)</span>" (browser-html b))
    n))

(test the-notification-bell
  (with-notification-users (ada bob)
    (with-fresh-applications (("/n" 'bell-app :mode :deployment))
      (let ((b (make-instance 'browser)))
        (visit b "/n")
        (is (not (search "lt-bell" (browser-html b))) "Nobody signed in: no bell")
        (sign-in-as b "ada" "correct horse battery")
        (is (search "<details class=\"lt-dropdown lt-bell\">" (browser-html b)))
        (is (null (bell-count-text b)))
        (is (has-text-p b "No notifications."))
        (is (has-text-p b "0 unread"))
        (littoral.notifications:notify-user ada "Plain news")
        (littoral.notifications:notify-user ada "Linked news" :url "/n")
        (littoral.notifications:notify-user bob "Bob's news")
        (visit b (browser-url b))
        (is (equal "2" (bell-count-text b)))
        (is (has-text-p b "2 unread"))
        (is (has-text-p b "Linked news"))
        (is (not (has-text-p b "Bob's news")))
        (is (has-text-p b "just now"))
        (is (= 2 (cl-ppcre:count-matches "class=\"lt-notification lt-notification-info lt-unread\"" (browser-html b))))
        ;; Following a linked one marks it read and goes there.
        (click b "Linked news")
        (is (equal "1" (bell-count-text b)))
        ;; A plain one is marked read over AJAX.
        (let* ((specs (ajax-specs b "on-click"))
               (json (ajax-request b (car (second specs)) (cdr (second specs)))))
          (is (search "0 unread" json))
          (is (not (search "lt-bell-count" json))))
        (is (zerop (littoral.notifications:unread-notification-count ada)))
        ;; Mark all as read.
        (littoral.notifications:notify-user ada "More")
        (littoral.notifications:notify-user ada "And more")
        (visit b (browser-url b))
        (is (equal "2" (bell-count-text b)))
        (let ((spec (first (ajax-specs b "on-click"))))
          (is (search "Mark all as read" (browser-html b)))
          (is (search "0 unread" (ajax-request b (car spec) (cdr spec)))))
        (visit b (browser-url b))
        (is (null (bell-count-text b)))
        (is (not (search "Mark all as read" (browser-html b))))))))

(test notifications-ring-the-bell-by-push
  ;; The stream renders in a thread of its own, with its own connection: a file
  ;; for SQLite.
  (let ((file (unless (postgres-test-p)
                (namestring (merge-pathnames (format nil "littoral-bell-~36R.sqlite3" (random (expt 36 8)))
                                             (uiop:temporary-directory))))))
    (unwind-protect
         (progn
           (if file
               (littoral.db:connect-database :sqlite3 :database-name file)
               (connect-test-database))
           (littoral.auth:drop-auth-tables)
           (littoral.notifications:drop-notification-tables)
           (littoral.auth:create-auth-tables)
           (littoral.notifications:create-notification-tables)
           (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")))
             (with-fresh-applications (("/n" 'bell-app :mode :deployment))
               (let ((b (make-instance 'browser))
                     (sink (make-instance 'sink)))
                 (visit b "/n")
                 (sign-in-as b "ada" "correct horse battery")
                 (is (search "data-lt-events" (browser-html b)) "The bell opens an event stream")
                 (let ((thread (open-stream b sink)))
                   ;; From another thread, as a job runner would.
                   (sb-thread:join-thread
                    (sb-thread:make-thread (lambda () (littoral.notifications:notify-user ada "Pushed news"))))
                   (is (wait-for (lambda () (search "Pushed news" (sink-text sink)))))
                   (is (search "lt-bell-count" (sink-text sink)))
                   (close-event-streams)
                   (is (wait-for (lambda () (not (sb-thread:thread-alive-p thread))))))))))
      (littoral.notifications:drop-notification-tables)
      (littoral.auth:drop-auth-tables)
      (connect-test-database)
      (when file
        (dolist (suffix '("" "-wal" "-shm"))
          (uiop:delete-file-if-exists (concatenate 'string file suffix)))))))

(test members-hear-of-their-new-role
  (with-members (b)
    ;; The test runs the queue itself.
    (littoral.jobs:stop-job-runner)
    (members-sign-in b "ada" "correct horse battery")
    (click b "Make editor")
    (click b "Sign out")
    (members-sign-in b "bob" "another passphrase")
    (is (equal "1" (bell-count-text b)))
    (is (has-text-p b "ada made you an editor: you may edit posts now."))
    ;; One in three seconds, through the job queue.
    (click b "Send me a notification in three seconds")
    (is (has-text-p b "the bell will ring"))
    (let ((littoral.db:*database* littoral-jobs-demo::*demo-database*))
      (littoral.db:db-execute "UPDATE job_queue SET run_at = 0 WHERE name LIKE '%DELAYED-NOTIFICATION%'"))
    (littoral-jobs-demo:run-now)
    (visit b (browser-url b))
    (is (equal "2" (bell-count-text b)))
    (is (has-text-p b "Here is the notification you asked for."))))
