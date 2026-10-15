;;;; The outbox: mail kept in the database until it has gone, and sent in the background.

;;;; Example: littoral.mail:create-mail-tables littoral.mail:queue-mail littoral.mail:deliver-queued-mail littoral.mail:outbox-messages littoral.mail:drop-mail-tables
;;; Queued mail waits in the outbox until it is delivered; a test can deliver it at once.  Dropping the tables (and the job queue CREATE-MAIL-TABLES made) puts things back as they were.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (mailer (littoral.mail:make-memory-mailer)))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((row (littoral.mail:queue-mail
                   (littoral.mail:make-mail :to "ada@example.org" :subject "Welcome" :text "Hello, Ada."))))
         (list (littoral.mail:outbox-status row)
               (littoral.mail:deliver-queued-mail :mailer mailer)
               (littoral.mail:outbox-status (first (littoral.mail:outbox-messages)))
               (length (littoral.mail:mailer-messages mailer))
               (littoral.mail:deliver-queued-mail :mailer mailer)))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "sent" 1 0)

;;;; Example: littoral.mail:outbox-mail littoral.mail:outbox-id littoral.mail:outbox-sender-address littoral.mail:outbox-recipients littoral.mail:outbox-subject littoral.mail:outbox-message littoral.mail:outbox-created littoral.mail:outbox-next-attempt littoral.mail:outbox-sent
;;; What the outbox keeps of a message: the envelope, the MIME message itself, and when it was queued and sent.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail
          (littoral.mail:make-mail :from "Shop <shop@example.org>" :to "Ada <ada@example.org>"
                                   :cc "bob@example.org" :subject "Your order" :text "Shipped."))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (integerp (littoral.mail:outbox-id row))
                 (littoral.mail:outbox-sender-address row)
                 (littoral.mail:outbox-recipients row)
                 (littoral.mail:outbox-subject row)
                 (littoral.mail:message-header (littoral.mail:outbox-message row) "To")
                 (<= (littoral.mail:outbox-created row) (littoral.mail:outbox-sent row) (get-universal-time))
                 (integerp (littoral.mail:outbox-next-attempt row)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (T "shop@example.org" "ada@example.org bob@example.org" "Your order" "Ada <ada@example.org>" T T)

;;;; Example: littoral.mail:outbox-status littoral.mail:outbox-attempts littoral.mail:outbox-last-error littoral.mail:retry-mail
;;; A failure that may pass leaves the message queued for a later try; RETRY-MAIL makes it due now.
(defclass unreachable-mailer () ())
(defmethod littoral.mail:send-message ((mailer unreachable-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error "Connection refused"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((id (littoral.mail:outbox-id
                  (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hello")))))
         (littoral.mail:deliver-queued-mail :mailer (make-instance 'unreachable-mailer))
         (let ((row (first (littoral.mail:outbox-messages))))
           (list (littoral.mail:outbox-status row)
                 (littoral.mail:outbox-attempts row)
                 (littoral.mail:outbox-last-error row)
                 (> (littoral.mail:outbox-next-attempt row) (get-universal-time))
                 (progn (littoral.mail:retry-mail id)
                        (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer)))
                 (littoral.mail:outbox-status (first (littoral.mail:outbox-messages))))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" 1 "Connection refused" T 1 "sent")

;;;; Example: littoral.mail:*mail-attempts* littoral.mail:*mail-retry-seconds*
;;; A message is tried *MAIL-ATTEMPTS* times, waiting *MAIL-RETRY-SECONDS* after the first failure and twice as long after each one since.
(defclass unreachable-mailer () ())
(defmethod littoral.mail:send-message ((mailer unreachable-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error "Connection refused"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.mail:*mail-attempts* 2)
      (littoral.mail:*mail-retry-seconds* 300))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (flet ((try ()
                (littoral.mail:deliver-queued-mail :mailer (make-instance 'unreachable-mailer))
                (let ((row (first (littoral.mail:outbox-messages))))
                  (list (littoral.mail:outbox-status row)
                        (- (littoral.mail:outbox-next-attempt row) (get-universal-time))))))
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "Hello"))
         (let ((first-try (try)))
           ;; As if the wait were over.
           (littoral.db:db-execute "UPDATE mail_outbox SET next_attempt = 0")
           (list (first first-try) (<= 299 (second first-try) 300) (first (try)))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("queued" T "failed")

;;;; Example: littoral.mail:outbox-messages littoral.mail:purge-sent-mail
;;; OUTBOX-MESSAGES can pick out one status; PURGE-SENT-MAIL deletes sent mail once it is a week old.
(defclass unreachable-mailer () ())
(defmethod littoral.mail:send-message ((mailer unreachable-mailer) from recipients message)
  (declare (ignore from recipients message))
  (error "Connection refused"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :subject "First" :text "1"))
         (littoral.mail:deliver-queued-mail :mailer (littoral.mail:make-memory-mailer))
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "bob@example.org" :subject "Second" :text "2"))
         (littoral.mail:deliver-queued-mail :mailer (make-instance 'unreachable-mailer))
         (list (mapcar #'littoral.mail:outbox-subject (littoral.mail:outbox-messages))
               (mapcar #'littoral.mail:outbox-subject (littoral.mail:outbox-messages :status "sent"))
               (littoral.mail:purge-sent-mail)
               (progn
                 ;; As if it had been sent a month ago.
                 (littoral.db:db-execute "UPDATE mail_outbox SET sent = sent - 2592000 WHERE status = 'sent'")
                 (littoral.mail:purge-sent-mail))
               (mapcar #'littoral.mail:outbox-subject (littoral.mail:outbox-messages))))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ (("Second" "First") ("First") 0 1 ("Second"))

;;;; Example: littoral.mail:outbox-sender
;;; A function that queues plain-text mail, as LITTORAL.AUTH:*SEND-MAIL* wants for password resets.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (send (littoral.mail:outbox-sender :from "Shop <shop@example.org>")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (let ((row (funcall send "ada@example.org" "Reset your password" "Follow this link.")))
         (list (littoral.mail:outbox-sender-address row)
               (littoral.mail:outbox-recipients row)
               (littoral.mail:outbox-subject row)
               (littoral.mail:outbox-status row)))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ ("shop@example.org" "ada@example.org" "Reset your password" "queued")

;;;; Example: littoral.mail:queue-mail
;;; Mail queued in a transaction is kept only if the transaction commits.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.mail:create-mail-tables)
  (unwind-protect
       (progn
         (ignore-errors
          (littoral.db:with-transaction ()
            (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :text "Your order"))
            (error "The order couldn't be saved.")))
         (littoral.mail:outbox-messages))
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)))
;; ⇒ NIL

;;;; Example: littoral.mail:start-mail-delivery littoral.mail:stop-mail-delivery littoral.mail:mail-delivery-running-p
;;; Delivery in the background, by a job runner thread.  That thread has its own connection, so the database is a file here rather than ":memory:".
(let* ((file (merge-pathnames (format nil "outbox-~36R.sqlite3" (random (expt 36 8))) (uiop:temporary-directory)))
       (littoral.db:*database* (list :sqlite3 :database-name (namestring file)))
       (mailer (littoral.mail:make-memory-mailer)))
  (unwind-protect
       (progn
         (littoral.mail:create-mail-tables)
         (littoral.mail:start-mail-delivery :mailer mailer :interval 1)
         (littoral.mail:queue-mail (littoral.mail:make-mail :to "ada@example.org" :subject "Soon" :text "Hello"))
         (loop repeat 50 until (littoral.mail:mailer-messages mailer) do (sleep 0.1))
         (list (littoral.mail:mail-delivery-running-p)
               (length (littoral.mail:mailer-messages mailer))
               (progn (littoral.mail:stop-mail-delivery)
                      (littoral.mail:mail-delivery-running-p))))
    (littoral.mail:stop-mail-delivery)
    (littoral.mail:drop-mail-tables)
    (littoral.jobs:drop-job-tables)
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string (namestring file) suffix)))))
;; ⇒ (T 1 NIL)
