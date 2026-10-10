;;;; main.lisp — the database, serving, and the executable's entry point

(in-package #:{{name}})

(defun database-spec ()
  "The database to use: $DATABASE_URL (postgres://user:password@host:port/db),
or SQLite in $DATA_DIR (default data/), as CONNECT-DATABASE takes it."
  (let ((url (uiop:getenv "DATABASE_URL")))
    (if (and url (plusp (length url)))
        (let* ((uri (quri:uri url))
               (userinfo (or (quri:uri-userinfo uri) ""))
               (colon (position #\: userinfo)))
          (list :postgres
                :database-name (string-left-trim "/" (quri:uri-path uri))
                :host (quri:uri-host uri) :port (or (quri:uri-port uri) 5432)
                :username (if colon (subseq userinfo 0 colon) userinfo)
                :password (if colon (quri:url-decode (subseq userinfo (1+ colon))) "")))
        (let ((directory (uiop:ensure-directory-pathname (or (uiop:getenv "DATA_DIR") "data/"))))
          (ensure-directories-exist directory)
          (list :sqlite3 :database-name (namestring (merge-pathnames "{{name}}.sqlite3" directory)))))))

(defun call-with-database (spec thunk)
  (funcall (apply #'littoral.db:using-database spec) thunk))

(defun setup-database (spec)
  "Create the tables unless they exist; safe at every start."
  (call-with-database spec (lambda ()
                             (littoral.db:create-table 'note)
                             (littoral.auth:create-auth-tables)
                             (littoral.mail:create-mail-tables)
                             (littoral.jobs:create-job-tables))))

(defun create-user (name email password &key admin (database (database-spec)))
  "Add a user who can sign in; with ADMIN, one who may use /admin too."
  (call-with-database database
                      (lambda ()
                        (littoral.auth:add-user name email password :roles (when admin '(:admin))))))

(defun register-app (&key (path "/") (mode :development) (database (database-spec)))
  "Serve the application at PATH and its admin at /admin, over DATABASE.
:DEVELOPMENT adds the toolbar and halos."
  (setup-database database)
  (register-application path 'app-root :title "{{title}}" :mode mode
                        ;; Mail, such as password reset links, goes to the outbox:
                        ;; the delivery thread SERVE starts sends it.
                        :around-request (let ((use-database (apply #'littoral.db:using-database database))
                                              (send-mail (littoral.mail:outbox-sender)))
                                          (lambda (thunk)
                                            (let ((littoral.auth:*send-mail* send-mail))
                                              (funcall use-database thunk))))
                        ;; Each request's callbacks in one transaction.
                        :around-actions (littoral.db:transactional))
  ;; The admin answers only this machine unless given :CREDENTIALS.
  (littoral.admin:register-admin "/admin" '(note) :title "{{title}} admin" :database database))

(defun mailer ()
  "What sends mail: the SMTP server $SMTP_URL names (smtp://user:password@host:587
for STARTTLS, smtps://… for TLS), or else one that prints mail to the log."
  (let ((url (uiop:getenv "SMTP_URL")))
    (if (and url (plusp (length url)))
        (littoral.mail:smtp-mailer-from-url url)
        littoral.mail:*mailer*)))

;; Background jobs: (enqueue-job (list 'some-job 42)) inside a request queues
;; one, in the request's transaction, for the runner SERVE starts.
(littoral.jobs:define-job (tidy-up :every (littoral.jobs:daily-at 3)) ()
  "Every night, forget sent mail and finished jobs more than a week old."
  (littoral.mail:purge-sent-mail)
  (littoral.jobs:purge-durable-jobs))

(defun serve (&key (port {{port}}) (address "127.0.0.1") (mode :development) (database (database-spec)))
  "Register the application, start sending its mail and running its jobs, and
start the web server.  Mail comes from $MAIL_FROM."
  (let ((from (uiop:getenv "MAIL_FROM")))
    (when (and from (plusp (length from)))
      (setf littoral.mail:*mail-from* from)))
  (register-app :mode mode :database database)
  (littoral.mail:start-mail-delivery :database database :mailer (mailer))
  (littoral.jobs:start-job-runner :database database)
  (start :port port :address address))

(defun toplevel ()
  "The entry point of the executable `make build` writes: serves in deployment
mode on $PORT (default {{port}}) and $ADDRESS, with $PUBLIC_URL as the address
mail links use, and $TRUST_PROXY set when behind a reverse proxy.  With the
arguments create-user NAME EMAIL PASSWORD [admin], adds that user instead."
  (let ((arguments (uiop:command-line-arguments)))
    (when (equal (first arguments) "create-user")
      (destructuring-bind (name email password &optional admin) (rest arguments)
        (setup-database (database-spec))
        (create-user name email password :admin (equal admin "admin"))
        (format t "Added ~A.~%" name)
        (uiop:quit 0))))
  (let ((public-url (uiop:getenv "PUBLIC_URL")))
    (setf littoral.auth:*public-url* (and public-url (plusp (length public-url)) public-url)
          *trust-forwarded-for* (and (uiop:getenv "TRUST_PROXY") t)))
  (serve :port (parse-integer (or (uiop:getenv "PORT") "{{port}}"))
         :address (or (uiop:getenv "ADDRESS") "127.0.0.1")
         :mode :deployment)
  (loop (sleep 3600)))
