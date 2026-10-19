;;;; notifications.lisp — messages for users, kept until they're read
;;;;
;;;;   (create-notification-tables)
;;;;   (notify-user user "Ada made you an editor." :url "/members")
;;;;   (make-instance 'notification-bell)        ; somewhere on the page
;;;;
;;;; A notification is a row in the notifications table: a user, a message,
;;;; perhaps a link, and when it was read.  Unlike a toast, it waits until
;;;; its user reads it, on whatever page, in whatever browser, after
;;;; restarts.  Users are named as littoral/auth's own tables name them,
;;;; (princ-to-string (user-id user)).  Each user has a channel
;;;; (NOTIFICATIONS-CHANNEL), published when their notifications change in
;;;; this process, after the transaction making the change commits; a
;;;; NOTIFICATION-BELL subscribes to its user's, so its count goes up as
;;;; notifications arrive.  For notifications made by other processes, give
;;;; the bell :POLL.

(defpackage #:littoral.notifications
  (:use #:cl #:littoral #:littoral.html)
  (:documentation "Load it with `(asdf:load-system :littoral/notifications)`.  Notifications for
users, kept in the database until read, and a bell that counts them as they arrive.")
  (:export #:create-notification-tables #:drop-notification-tables
           #:notify-user #:user-notifications #:unread-notification-count
           #:mark-notification-read #:mark-all-notifications-read #:purge-notifications
           #:notifications-channel
           #:notification #:notification-id #:notification-message #:notification-url
           #:notification-kind #:notification-created #:notification-read-at #:notification-read-p
           #:notification-bell))

(in-package #:littoral.notifications)

(littoral.db:define-migrations :littoral-notifications
  (asdf:system-relative-pathname :littoral "migrations/notifications/"))

(defun create-notification-tables ()
  "Create or bring up to date the notifications table (migrations
:LITTORAL-NOTIFICATIONS) in the current database."
  (littoral.db:migrate :littoral-notifications)
  t)

(defun drop-notification-tables ()
  "Drop the notifications table."
  (littoral.db:db-execute "DROP TABLE IF EXISTS notifications")
  (littoral.db:forget-migrations :littoral-notifications))

(defun user-key (user)
  "USER, a user object or its id, as the notifications table names it."
  (princ-to-string (if (or (integerp user) (stringp user)) user (littoral.auth:user-id user))))

;;; Channels

(defvar *channels* (make-hash-table :test 'equal :weakness :value :synchronized t)
  "User key → channel, kept while something refers to it.")

(defun notifications-channel (user)
  "The channel published when USER's notifications change in this process:
one arrives, or some are read.  USER is a user or its id."
  (let ((key (user-key user)))
    (or (gethash key *channels*)
        (sb-ext:with-locked-hash-table (*channels*)
          (or (gethash key *channels*)
              (setf (gethash key *channels*) (make-channel (format nil "notifications:~A" key))))))))

(defun notifications-changed (key)
  "Publish user KEY's channel once the current transaction commits."
  (littoral.db:after-commit (lambda () (publish (notifications-channel key)))))

;;; Notifications

(defclass notification ()
  ((id :initarg :id :reader notification-id)
   (user :initarg :user :reader notification-user :documentation "The user's key.")
   (message :initarg :message :reader notification-message)
   (url :initarg :url :initform nil :reader notification-url
        :documentation "Where following it goes, or NIL.")
   (kind :initarg :kind :reader notification-kind
         :documentation "A keyword such as :INFO (the default), :SUCCESS or :WARNING.")
   (created :initarg :created :reader notification-created :documentation "A universal time.")
   (read-at :initarg :read-at :initform nil :reader notification-read-at
            :documentation "When it was read, a universal time, or NIL."))
  (:documentation "One message for one user, as USER-NOTIFICATIONS reads it."))

(defun notification-read-p (notification)
  "True once NOTIFICATION has been read."
  (and (notification-read-at notification) t))

(defun row-notification (row)
  "The NOTIFICATION a notifications ROW, a plist from DB-QUERY, holds."
  (flet ((value (key) (let ((v (getf row key))) (if (eq v :null) nil v))))
    (make-instance 'notification
                   :id (value :|id|) :user (value :|user_id|) :message (value :|message|)
                   :url (value :|url|) :kind (intern (string-upcase (value :|kind|)) :keyword)
                   :created (value :|created|) :read-at (value :|read_at|))))

(defun notify-user (user message &key url (kind :info))
  "Tell USER, a user or its id, MESSAGE: a notification kept until they
read it, which a NOTIFICATION-BELL lists.  URL, when given, is where
following it goes.  KIND is a keyword such as :INFO, :SUCCESS or :WARNING,
for styling.  Inside a transaction, the notification exists, and bells hear
of it, only if the transaction commits.  Returns its id."
  (let ((key (user-key user)))
    (prog1 (getf (first (littoral.db:db-query
                         "INSERT INTO notifications (user_id, message, url, kind, created)
VALUES (?, ?, ?, ?, ?) RETURNING id"
                         key message url (string-downcase kind) (get-universal-time)))
                 :|id|)
      (notifications-changed key))))

(defun user-notifications (user &key (limit 20) unread-only)
  "USER's notifications, newest first: at most LIMIT, and only those not
yet read when UNREAD-ONLY."
  (mapcar #'row-notification
          (littoral.db:db-query
           (format nil "SELECT * FROM notifications WHERE user_id = ?~:[~; AND read_at IS NULL~]
ORDER BY created DESC, id DESC LIMIT ?"
                   unread-only)
           (user-key user) limit)))

(defun unread-notification-count (user)
  "How many of USER's notifications haven't been read."
  (getf (first (littoral.db:db-query "SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND read_at IS NULL"
                                     (user-key user)))
        :|n|))

(defun mark-notification-read (user id)
  "Mark USER's notification ID read.  Another user's is left alone.  True
when it was unread."
  (let* ((key (user-key user))
         (changed (getf (first (littoral.db:db-query
                                "UPDATE notifications SET read_at = ?
WHERE id = ? AND user_id = ? AND read_at IS NULL RETURNING id"
                                (get-universal-time) id key))
                        :|id|)))
    (when changed (notifications-changed key))
    (and changed t)))

(defun mark-all-notifications-read (user)
  "Mark every one of USER's notifications read."
  (let ((key (user-key user)))
    (littoral.db:db-execute "UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL"
                            (get-universal-time) key)
    (notifications-changed key)
    (values)))

(defun purge-notifications (&key (older-than (* 90 24 60 60)) (unread nil))
  "Delete notifications read more than OLDER-THAN seconds ago (90 days),
and with UNREAD, unread ones made that long ago too.  For a recurring job."
  (let ((before (- (get-universal-time) older-than)))
    (if unread
        (littoral.db:db-execute "DELETE FROM notifications
WHERE (read_at IS NOT NULL AND read_at < ?) OR (read_at IS NULL AND created < ?)"
                                before before)
        (littoral.db:db-execute "DELETE FROM notifications WHERE read_at IS NOT NULL AND read_at < ?" before))
    (values)))

;;; The bell

(defclass notification-bell (component)
  ((limit :initarg :limit :initform 8 :reader bell-limit)
   (poll :initarg :poll :initform nil :reader bell-poll)
   (count :reader bell-count)
   (panel :reader bell-panel))
  (:documentation "A bell showing how many notifications the signed-in
user hasn't read, opening onto the latest :LIMIT (8): following one marks
it read and goes to its URL, and Mark all as read does that for them all.
It shows nothing to someone not signed in.  New notifications made in this
process arrive by server push; for those made by other processes, :POLL
gives the seconds between looks.  Like DROPDOWN-MENU it is a details
element, so it opens without JavaScript, and closes on Escape or a click
elsewhere."))

(defclass bell-part (component updatable)
  ((bell :initarg :bell :reader part-bell))
  (:documentation "A part of a NOTIFICATION-BELL that server push redraws."))

(defclass bell-count (bell-part) ()
  (:documentation "A NOTIFICATION-BELL's unread count."))

(defclass bell-panel (bell-part) ()
  (:documentation "A NOTIFICATION-BELL's list of notifications."))

(defmethod initialize-instance :after ((self notification-bell) &key)
  (setf (slot-value self 'count) (make-instance 'bell-count :bell self)
        (slot-value self 'panel) (make-instance 'bell-panel :bell self)))

(defmethod children ((self notification-bell)) (list (bell-count self) (bell-panel self)))

(defmethod subscriptions ((self bell-part))
  ;; Asked of every open page at each publish: the session's user id, not a query.
  (let ((id (and *session* (session-property :user-id))))
    (and id (list (notifications-channel id)))))

(defmethod updatable-wrapper ((self bell-count)) (values "span" '()))
(defmethod updatable-wrapper ((self bell-panel)) (values "div" '(:class "lt-dropdown-panel lt-bell-panel")))

(defmethod render ((self bell-count))
  (let* ((user (littoral.auth:current-user))
         (unread (if user (unread-notification-count user) 0))
         (poll (bell-poll (part-bell self))))
    (span (:class "lt-bell-unread"
           :periodical (and poll (periodical poll :update (list self (bell-panel (part-bell self))))))
      (when (plusp unread)
        (span (:class "lt-bell-count" :aria-hidden "true") (text (if (> unread 99) "99+" unread)))
        (text " "))
      (span (:class "lt-visually-hidden") (text (translate-plural unread "~D unread" "~D unread"))))))

(defun time-ago (time)
  "How long ago TIME, a universal time, was, for people."
  (let ((seconds (max 0 (- (get-universal-time) time))))
    (cond ((< seconds 60) (translate "just now"))
          ((< seconds 3600) (translate-plural (floor seconds 60) "~D minute ago" "~D minutes ago"))
          ((< seconds 86400) (translate-plural (floor seconds 3600) "~D hour ago" "~D hours ago"))
          (t (multiple-value-bind (s m h day month year) (decode-universal-time time)
               (declare (ignore s m h))
               (localized-date year month day))))))

(defun follow-notification (bell notification)
  "Mark NOTIFICATION read, then go to its URL, if it has one."
  (let ((user (littoral.auth:current-user)))
    (when user
      (mark-notification-read user (notification-id notification))
      (when (notification-url notification)
        (redirect-to (notification-url notification)))))
  bell)

(defmethod render ((self bell-panel))
  (let* ((bell (part-bell self))
         (user (littoral.auth:current-user))
         (notifications (and user (user-notifications user :limit (bell-limit bell))))
         (parts (list (bell-count bell) self)))
    (div (:class "lt-bell-heading")
      (strong () (translate "Notifications"))
      (when (some (lambda (n) (not (notification-read-p n))) notifications)
        (button (:class "lt-bell-all"
                 :on-click (ajax :callback (lambda () (let ((user (littoral.auth:current-user)))
                                                        (when user (mark-all-notifications-read user))))
                                 :update parts))
          (translate "Mark all as read"))))
    (if (null notifications)
        (p (:class "lt-bell-none") (translate "No notifications."))
        (ul ()
          (dolist (notification notifications)
            (let ((notification notification))
              (li (:class (list "lt-notification" (format nil "lt-notification-~(~A~)" (notification-kind notification))
                                (unless (notification-read-p notification) "lt-unread")))
                (flet ((body ()
                         (unless (notification-read-p notification)
                           (span (:class "lt-visually-hidden") (translate "Unread:") " "))
                         (span (:class "lt-notification-message") (text (notification-message notification)))
                         (text " ")
                         (span (:class "lt-notification-time") (text (time-ago (notification-created notification))))))
                  (if (notification-url notification)
                      (anchor (:callback (lambda () (follow-notification bell notification))) (body))
                      (button (:on-click (ajax :callback (lambda () (follow-notification bell notification))
                                               :update parts))
                        (body)))))))))))

(defparameter *bell-icon*
  (concatenate 'string
               "<svg class=\"lt-bell-icon\" viewBox=\"0 0 24 24\" width=\"20\" height=\"20\" "
               "aria-hidden=\"true\" focusable=\"false\"><path fill=\"currentColor\" d=\""
               "M12 22a2.5 2.5 0 0 0 2.45-2h-4.9A2.5 2.5 0 0 0 12 22Zm7-6V11a7 7 0 0 0-5.5-6.84V3.5"
               "a1.5 1.5 0 0 0-3 0v.66A7 7 0 0 0 5 11v5l-2 2v1h18v-1Z\"/></svg>")
  "The bell, as inline SVG in the text's colour.")

(defmethod render ((self notification-bell))
  (when (littoral.auth:current-user)
    (details (:class "lt-dropdown lt-bell")
      (summary (:title (translate "Notifications"))
        (raw *bell-icon*)
        (span (:class "lt-visually-hidden") (translate "Notifications") " ")
        (render-component (bell-count self)))
      (render-component (bell-panel self)))))
