;;;; Examples for littoral.admin: an administration interface generated from descriptions and tables.

;;;; Example: littoral.admin:register-admin littoral.admin:admin
;;; An admin over stored classes: a command palette, a menu of tables, a searchable list of each, and a page per record to edit or delete it.  Without :ROLE or :CREDENTIALS it answers only requests from this machine, as the fake browser's are.
(defclass book (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (pages :initarg :pages :initform nil)))
(define-description book
  ((title :required t)
   (pages :type :integer :min 1)))
(littoral.db:define-table book)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'book)
  (littoral.db:db-save (make-instance 'book :title "Moby-Dick" :pages 635))
  (littoral.db:db-save (make-instance 'book :title "Walden" :pages 352))
  (with-fresh-applications ()
    (littoral.admin:register-admin "/admin" '(book) :title "Library admin")
    (let ((b (make-instance 'browser)))
      (visit b "/admin")
      (let ((list (body-text b)))
        (click-nth b "2" 0)               ; record #2
        (click b "Edit")
        (fill-in b "pages" "354")
        (press b "Save")
        (list list (slot-value (littoral.db:db-find 'book 2) 'pages))))))
;; ⇒ ("Library admin Commands Ctrl K Search commands 3 commands Go to Books Tables New book Create Audit log Books Audit log Books New book 2 books # Title Pages 1 Moby-Dick 635 2 Walden 352" 354)

;;;; Example: littoral.admin:register-admin
;;; With :ROLE, users of littoral/auth with that role sign in to it, from anywhere; the database holds their tables too.  The audit log names who changed what.
(defclass genre (littoral.db:persistent)
  ((name :initarg :name :initform nil)))
(define-description genre ((name :required t)))
(littoral.db:define-table genre)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery" :roles '(:librarian))
  (littoral.db:create-table 'genre)
  (with-fresh-applications ()
    (littoral.admin:register-admin "/genres" '(genre) :role :librarian)
    (let ((b (make-instance 'browser)))
      (visit b "/genres")
      (fill-in b "sign-in-name" "ada")
      (fill-in b "sign-in-password" "correct horse battery")
      (press b "Sign in")
      (click b "New genre")
      (fill-in b "name" "Poetry")
      (press b "Create")
      (let ((event (first (littoral.audit:audit-events :action "record.created"))))
        (list (not (null (has-text-p b "Created Genre #1.")))
              (littoral.audit:audit-event-subject-label event)
              (littoral.audit:audit-event-actor-name event))))))
;; ⇒ (T "Genre #1 Poetry" "ada")

;;;; Example: littoral.admin:register-admin
;;; With :CREDENTIALS, a (USER . PASSWORD) pair, it asks for HTTP basic auth instead.
(defclass note (littoral.db:persistent)
  ((text :initarg :text :initform nil)))
(define-description note ((text :required t)))
(littoral.db:define-table note)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'note)
  (with-fresh-applications ()
    (littoral.admin:register-admin "/notes-admin" '(note) :credentials '("admin" . "s3cret"))
    (list (browser-status (visit (make-instance 'browser) "/notes-admin"))
          (let ((b (make-instance 'browser
                                  :headers `(("authorization" . ,(format nil "Basic ~A"
                                                                         (cl-base64:string-to-base64-string "admin:s3cret")))))))
            (visit b "/notes-admin")
            (browser-status b)))))
;; ⇒ (401 200)

;;;; Example: littoral.admin:job-queue-view
;;; The durable jobs of the current database, by status, with Retry and Cancel.  The admin shows it as "Job queue" where the job tables are; put it in an application of your own only where those who may see every job can.
(littoral.jobs:define-job send-digest (list-id)
  (format nil "Sent digest ~D" list-id))
(defclass operations (component)
  ((jobs :initform (make-instance 'littoral.admin:job-queue-view) :reader operations-jobs)))
(defmethod children ((self operations)) (list (operations-jobs self)))
(defmethod render ((self operations)) (render-component (operations-jobs self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.jobs:create-job-tables)
  (let ((id (littoral.jobs:enqueue-job '(send-digest 42))))
    (with-fresh-applications (("/ops" 'operations :mode :deployment))
      (let ((b (make-instance 'browser)))
        (visit b "/ops")
        (let ((shown (not (null (has-text-p b "(send-digest 42)")))))
          (click-nth b "Cancel" 0)
          (list shown
                (littoral.jobs:durable-job-status (littoral.jobs:find-durable-job id))
                (not (null (has-text-p b "Cancelled (1)")))))))))
;; ⇒ (T "cancelled" T)
