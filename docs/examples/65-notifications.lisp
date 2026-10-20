;;;; Notifications: messages for users, kept until they're read, and the bell that counts them.

;;;; Example: littoral.notifications:notify-user littoral.notifications:user-notifications littoral.notifications:unread-notification-count littoral.notifications:create-notification-tables littoral.notifications:drop-notification-tables
;;; A notification waits in the notifications table until its user reads it.  Users are given as user objects or their ids.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.notifications:create-notification-tables)
  (unwind-protect
       (progn
         (littoral.notifications:notify-user 1 "Your export is ready." :url "/exports/7")
         (littoral.notifications:notify-user 1 "Bob replied to you.")
         (littoral.notifications:notify-user 2 "Welcome!")
         (list (littoral.notifications:unread-notification-count 1)
               (mapcar #'littoral.notifications:notification-message
                       (littoral.notifications:user-notifications 1))))
    (littoral.notifications:drop-notification-tables)))
;; ⇒ (2 ("Bob replied to you." "Your export is ready."))

;;;; Example: littoral.notifications:notification littoral.notifications:notification-id littoral.notifications:notification-message littoral.notifications:notification-url littoral.notifications:notification-kind littoral.notifications:notification-created
;;; Each one as USER-NOTIFICATIONS reads it: its message, where it leads, its kind and when it was made.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.notifications:create-notification-tables)
  (let* ((id (littoral.notifications:notify-user "ada" "Disk nearly full" :url "/admin/disks" :kind :warning))
         (n (first (littoral.notifications:user-notifications "ada"))))
    (list (= id (littoral.notifications:notification-id n))
          (littoral.notifications:notification-message n)
          (littoral.notifications:notification-url n)
          (littoral.notifications:notification-kind n)
          (<= (- (get-universal-time) (littoral.notifications:notification-created n)) 5))))
;; ⇒ (T "Disk nearly full" "/admin/disks" :WARNING T)

;;;; Example: littoral.notifications:mark-notification-read littoral.notifications:mark-all-notifications-read littoral.notifications:notification-read-p littoral.notifications:notification-read-at
;;; Reading one marks it read; only its own user can.  Mark all as read does the rest.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.notifications:create-notification-tables)
  (let ((first (littoral.notifications:notify-user 1 "One")))
    (littoral.notifications:notify-user 1 "Two")
    (littoral.notifications:notify-user 1 "Three")
    (list (littoral.notifications:mark-notification-read 2 first)       ; someone else's
          (littoral.notifications:mark-notification-read 1 first)
          (mapcar #'littoral.notifications:notification-read-p (littoral.notifications:user-notifications 1))
          (progn (littoral.notifications:mark-all-notifications-read 1)
                 (every #'littoral.notifications:notification-read-at (littoral.notifications:user-notifications 1))))))
;; ⇒ (NIL T (NIL NIL T) T)

;;;; Example: littoral.notifications:purge-notifications
;;; For a nightly job: delete what was read long ago (90 days by default), and with :UNREAD, what was never read either.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.notifications:create-notification-tables)
  (littoral.notifications:mark-notification-read 1 (littoral.notifications:notify-user 1 "Old news"))
  (littoral.notifications:notify-user 1 "Still unread")
  (littoral.db:db-execute "UPDATE notifications SET created = created - 100, read_at = read_at - 100")
  (littoral.notifications:purge-notifications :older-than 60)
  (mapcar #'littoral.notifications:notification-message (littoral.notifications:user-notifications 1)))
;; ⇒ ("Still unread")

;;;; Example: littoral.notifications:notifications-channel
;;; Each user's channel is published when their notifications change in this process, once the change commits; a user and their id name the same one.
(let ((channel (littoral.notifications:notifications-channel 42)))
  (list (eq channel (littoral.notifications:notifications-channel "42"))
        (eq channel (littoral.notifications:notifications-channel 7))
        (typep channel 'channel)))
;; ⇒ (T NIL T)

;;;; Example: littoral.notifications:notification-bell
;;; The bell shows the signed-in user's unread count and opens onto their latest notifications; following one marks it read.  It subscribes to their channel, so on a real page the count goes up by server push.
(defclass inbox-page (littoral.auth:auth-root component)
  ((bell :initform (make-instance 'littoral.notifications:notification-bell) :reader bell)))
(defmethod children ((self inbox-page)) (list (bell self)))
(defmethod render ((self inbox-page))
  (render-component (bell self))
  (unless (littoral.auth:current-user)
    (h:anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in)))) "Sign in")))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.notifications:create-notification-tables)
  (let ((bob (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")))
    (littoral.notifications:notify-user bob "Your order has shipped.")
    (with-fresh-applications (("/inbox" 'inbox-page :mode :deployment))
      (let ((b (make-instance 'browser)))
        (visit b "/inbox")
        (click b "Sign in")
        (fill-in b "sign-in-name" "bob")
        (fill-in b "sign-in-password" "another passphrase")
        (press b "Sign in")
        (let ((before (body-text b)))
          (littoral.notifications:mark-all-notifications-read bob)
          (visit b (browser-url b))
          (list before (body-text b)))))))
;; ⇒ ("Notifications 1 1 unread Notifications Mark all as read Unread: Your order has shipped. just now" "Notifications 0 unread Notifications Your order has shipped. just now")
