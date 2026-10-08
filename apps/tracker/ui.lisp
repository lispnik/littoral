;;;; ui.lisp — Tracker's pages

(in-package #:littoral-tracker)

;;; Descriptions

(defclass registration ()
  ((name :initform nil) (email :initform nil) (password :initform nil) (confirm :initform nil))
  (:documentation "The form for a new account."))

(define-description registration
  ((name :required t :max-length 30 :pattern "[A-Za-z0-9_.-]+"
         :pattern-message "Names are letters, digits, dots, dashes and underscores."
         :validate (lambda (name) (when (find-user name) "That name is taken.")))
   (email :type :email :required t)
   (password :type :password :required t
             :validate (lambda (p) (when (< (length p) 8) "Passwords need at least 8 characters.")))
   (confirm :type :password :required t :label "Password again"))
  :validate (lambda (values)
              (unless (equal (getf values :password) (getf values :confirm))
                "The passwords differ.")))

(defclass issue-draft ()
  ((title :initform nil) (body :initform nil) (status :initform :open) (priority :initform :normal)
   (assignee :initform nil) (due :initform nil))
  (:documentation "What an editor works on, so shared issues change only
through UPDATE-ISSUE, under the store's lock."))

(defun draft-of (values)
  "A draft holding the plist VALUES."
  (let ((draft (make-instance 'issue-draft)))
    (loop for (key value) on values by #'cddr
          do (setf (slot-value draft (find-symbol (symbol-name key) :littoral-tracker)) value))
    draft))

(define-description issue-draft
  ((title :required t :max-length 120)
   (body :type :text :label "Description")
   (status :type :choice :choices *statuses* :labels #'status-label :required t)
   (priority :type :choice :choices *priorities* :labels #'string-capitalize :required t)
   (assignee :type :choice :choices #'user-names :labels #'identity)
   (due :type :date :label "Due date")))

;;; Logging in

(defclass sign-in (component)
  ((message :initform nil :accessor sign-in-message))
  (:documentation "Log in, or create an account."))

(defun try-login (self)
  "Ask for credentials; answer the user they belong to."
  (show self (validate-with (make-instance 'login-dialog :message "Log in to Tracker")
                            (lambda (answer)
                              (when (and answer (not (authenticate (car answer) (cdr answer))))
                                "Unknown user or wrong password.")))
        :on-answer (lambda (answer)
                     (when answer
                       (answer self (find-user (car answer)))))))

(defun register (self)
  "Ask for a new account's details; create it and answer its user."
  (show self (make-editor (make-instance 'registration) :title "Create an account"
                                                         :save-label "Create account" :write nil)
        :on-answer (lambda (values)
                     (when values
                       (handler-case
                           (progn (add-user (getf values :name) (getf values :email) (getf values :password))
                                  (answer self (find-user (getf values :name))))
                         (error (e) (setf (sign-in-message self) (princ-to-string e))))))))

(defmethod render ((self sign-in))
  (div (:class "tracker-sign-in")
    (h1 () "Tracker")
    (p () "An issue tracker built with Littoral.")
    (when (sign-in-message self) (p (:class "lt-validation-error") (text (sign-in-message self))))
    (p () (anchor (:callback (lambda () (try-login self))) "Log in")
      " or " (anchor (:callback (lambda () (register self))) "create an account") ".")))

;;; The issue list

(defclass issue-list (component updatable)
  ((app :initarg :app :reader list-app)
   (filter :initform :open :accessor list-filter
           :documentation "A status, :MINE or :ALL.")
   (query :initform "" :accessor list-query)
   (report :reader list-report))
  (:documentation "Issues, filtered and searchable, updated when anyone changes one."))

(defmethod initialize-instance :after ((self issue-list) &key)
  (setf (slot-value self 'report)
        (make-instance
         'report
         :rows (lambda () (filtered-issues self))
         :batch-size 15
         :row-class (lambda (issue) (string-downcase (issue-priority issue)))
         :columns (list (column "#" #'issue-id :class "number")
                        (column "Title" #'issue-title
                                :render (lambda (issue title)
                                          (anchor (:callback (lambda () (open-issue (list-app self) issue)))
                                            (text title))))
                        (column "Status" #'issue-status
                                :render (lambda (issue status)
                                          (declare (ignore issue))
                                          (span (:class (list "status" (string-downcase status)))
                                            (text (status-label status)))))
                        (column "Priority" #'issue-priority
                                :sort-key (lambda (issue) (position (issue-priority issue) *priorities*))
                                :render (lambda (issue p) (declare (ignore issue)) (text (string-capitalize p))))
                        (column "Assignee" #'issue-assignee)
                        (column "Due" #'issue-due
                                :sort-key (lambda (issue) (and (issue-due issue) (format-date (issue-due issue))))
                                :render (lambda (issue due) (declare (ignore issue))
                                          (when due (text (format-date due)))))
                        (column "Updated" #'issue-updated
                                :render (lambda (issue time) (declare (ignore issue))
                                          (text (format-ago time))))))))

(defmethod states ((self issue-list))
  (list self))

(defmethod children ((self issue-list))
  (list (list-report self)))

(defmethod subscriptions ((self issue-list))
  (list *tracker-channel*))

(defun format-date (date)
  "DATE, a (YEAR MONTH DAY) list, as YYYY-MM-DD."
  (format nil "~4,'0D-~2,'0D-~2,'0D" (first date) (second date) (third date)))

(defun format-ago (time)
  "How long ago the universal TIME was, roughly."
  (let ((seconds (- (get-universal-time) time)))
    (cond ((< seconds 60) "just now")
          ((< seconds 3600) (format nil "~D min ago" (floor seconds 60)))
          ((< seconds 86400) (format nil "~D h ago" (floor seconds 3600)))
          (t (format nil "~D days ago" (floor seconds 86400))))))

(defun filtered-issues (list)
  "The issues LIST shows: by its filter, then its query."
  (let ((filter (list-filter list))
        (query (string-trim " " (list-query list)))
        (me (user-name (app-user (list-app list)))))
    (remove-if-not (lambda (issue)
                     (and (case filter
                            (:all t)
                            (:mine (equal (issue-assignee issue) me))
                            (otherwise (eq (issue-status issue) filter)))
                          (or (string= query "")
                              (search query (issue-title issue) :test #'char-equal)
                              (and (issue-body issue) (search query (issue-body issue) :test #'char-equal)))))
                   (all-issues))))

(defun count-issues (status)
  "How many issues have STATUS."
  (count status (all-issues) :key #'issue-status))

(defmethod render ((self issue-list))
  (div (:class "issue-list")
    (ul (:class "lt-tabs tracker-filters")
      (loop for (filter label) in `((:open ,(format nil "Open (~D)" (count-issues :open)))
                                    (:in-progress ,(format nil "In progress (~D)" (count-issues :in-progress)))
                                    (:closed ,(format nil "Closed (~D)" (count-issues :closed)))
                                    (:mine "Assigned to me")
                                    (:all "All"))
            do (let ((filter filter))
                 (li (:class (when (eq filter (list-filter self)) "lt-active"))
                   (if (eq filter (list-filter self))
                       (span () (text label))
                       (anchor (:callback (lambda () (setf (list-filter self) filter))) (text label)))))))
    (p (:class "tracker-search")
      (text-input (:id "query" :value (list-query self) :placeholder "Search titles and descriptions"
                   :callback (lambda (v) (setf (list-query self) v))
                   :on-input (ajax-update self))))
    (if (null (filtered-issues self))
        (p (:class "empty") "No issues here.")
        (render-component (list-report self)))))

;;; One issue

(defclass issue-page (component)
  ((issue :initarg :issue :reader page-issue)
   (app :initarg :app :reader page-app)
   (draft-comment :initform "" :accessor draft-comment)
   (thread :reader page-thread))
  (:documentation "An issue, its comments, and what can be done to it."))

(defclass comment-thread (component updatable)
  ((page :initarg :page :reader thread-page))
  (:documentation "An issue's comments, updated when anyone adds one."))

(defmethod subscriptions ((self comment-thread))
  (list *tracker-channel*))

(defmethod render ((self comment-thread))
  (let ((comments (issue-comments (page-issue (thread-page self)))))
    (div (:class "comments")
      (h2 () (text (format nil "~D comment~:P" (length comments))))
      (dolist (c comments)
        (div (:class "comment")
          (div (:class "comment-head") (strong () (text (comment-author c))) " "
            (span (:class "muted") (text (format-ago (comment-time c)))))
          (div (:class "comment-text")
            (dolist (line (cl-ppcre:split "\\n" (comment-text c))) (text line) (br))))))))

(defmethod initialize-instance :after ((self issue-page) &key)
  (setf (slot-value self 'thread) (make-instance 'comment-thread :page self)))

(defmethod children ((self issue-page))
  (list (page-thread self)))

(defmethod states ((self issue-page))
  (list self))

(defun edit-issue (page)
  "Edit PAGE's issue through a draft, then update it."
  (let ((issue (page-issue page)))
    (show page (make-editor (draft-of (issue-values issue))
                            :title (format nil "Edit #~D" (issue-id issue)) :write nil)
          :on-answer (lambda (values) (when values (update-issue issue values))))))

(defun post-comment (page)
  "Add PAGE's draft comment to its issue."
  (let ((text (string-trim '(#\Space #\Newline #\Return #\Tab) (draft-comment page))))
    (unless (string= text "")
      (add-comment (page-issue page) (user-name (app-user (page-app page))) text)
      (setf (draft-comment page) ""))))

(defmethod render ((self issue-page))
  (let ((issue (page-issue self))
        (me (user-name (app-user (page-app self)))))
    (div (:class "issue-page")
      (p () (anchor (:callback (lambda () (answer self))) "← All issues"))
      (h1 () (text (format nil "#~D ~A" (issue-id issue) (issue-title issue))))
      (p (:class "issue-meta")
        (span (:class (list "status" (string-downcase (issue-status issue))))
          (text (status-label (issue-status issue))))
        (text (format nil " · ~A priority · reported by ~A~@[ · assigned to ~A~]~@[ · due ~A~]"
                      (string-downcase (issue-priority issue)) (issue-reporter issue)
                      (issue-assignee issue)
                      (and (issue-due issue) (format-date (issue-due issue))))))
      (div (:class "issue-body")
        (if (issue-body issue)
            (dolist (line (cl-ppcre:split "\\n" (issue-body issue))) (text line) (br))
            (em () "No description.")))
      (div (:class "lt-buttons")
        (anchor (:class "action" :callback (lambda () (edit-issue self))) "Edit")
        (unless (equal (issue-assignee issue) me)
          (anchor (:class "action" :callback (lambda () (update-issue issue (list :assignee me))))
            "Assign to me"))
        (case (issue-status issue)
          (:open (anchor (:class "action" :callback (lambda () (update-issue issue '(:status :in-progress))))
                   "Start work"))
          (:in-progress (anchor (:class "action" :callback (lambda () (update-issue issue '(:status :closed))))
                          "Close"))
          (:closed (anchor (:class "action" :callback (lambda () (update-issue issue '(:status :open))))
                     "Reopen"))))
      (render-component (page-thread self))
      (form (:class "new-comment")
        (text-area (:id "comment" :rows 3 :value (draft-comment self) :placeholder "Add a comment"
                    :callback (lambda (v) (setf (draft-comment self) v))))
        (submit-button (:callback (lambda () (post-comment self))) "Comment")))))

;;; The application

(defclass tracker (component)
  ((user :initform nil :accessor app-user)
   (issues :reader app-issues)
   (wanted :initform nil :accessor app-wanted
           :documentation "The issue a bookmark asked for, opened after signing in."))
  (:documentation "Tracker's root: signs people in, then shows the issues."))

(defmethod initialize-instance :after ((self tracker) &key)
  (setf (slot-value self 'issues) (make-instance 'issue-list :app self)))

(defmethod states ((self tracker))
  (list self))

(defmethod children ((self tracker))
  (list (app-issues self)))

(defmethod initial-request ((self tracker) request)
  (declare (ignore request))
  ;; /tracker/issue/12 from a bookmark: remember 12 for after signing in.
  (let ((path (request-extra-path)))
    (when (and (equal (first path) "issue") (second path))
      (setf (app-wanted self) (ignore-errors (parse-integer (second path))))))
  (sign-in-then-show self))

(defun sign-in-then-show (app)
  "Ask APP's user to sign in, then open the issue a bookmark named, if any."
  (show app (make-instance 'sign-in)
        :on-answer (lambda (user)
                     (setf (app-user app) user)
                     (let ((issue (and (app-wanted app) (find-issue (app-wanted app)))))
                       (setf (app-wanted app) nil)
                       (when issue (open-issue app issue))))))

(defmethod update-url ((self tracker) url)
  (let ((active (active-component self)))
    (when (typep active 'issue-page)
      (add-to-path url "issue" (issue-id (page-issue active))))))

(defun open-issue (app issue)
  "Show ISSUE in place of APP's list."
  (show app (make-instance 'issue-page :issue issue :app app)))

(defun new-issue (app)
  "File a new issue, then open it."
  (show app (make-editor (make-instance 'issue-draft) :title "New issue" :save-label "File issue" :write nil)
        :on-answer (lambda (values)
                     (when values
                       (open-issue app (apply #'create-issue (user-name (app-user app)) values))))))

(defun log-out (app)
  "Forget APP's user and ask someone to sign in."
  (setf (app-user app) nil)
  (home app)
  (sign-in-then-show app))

(defmethod render ((self tracker))
  (header (:class "tracker-header")
    (strong (:class "tracker-name") "Tracker")
    (when (app-user self)
      (span ()
        (anchor (:callback (lambda () (new-issue self))) "New issue")
        (text " · ")
        (text (user-name (app-user self)))
        (text " · ")
        (anchor (:callback (lambda () (log-out self))) "Log out"))))
  (render-component (app-issues self)))

(defmethod style ((self tracker))
  ".tracker-header { display: flex; flex-wrap: wrap; gap: .4rem 1rem; justify-content: space-between; align-items: baseline;
                   border-bottom: 1px solid var(--lt-border); padding-bottom: .4rem; margin-bottom: .8rem; }
.tracker-name { font-size: 1.2rem; }
.tracker-filters { margin-bottom: .6rem; }
.tracker-search input { width: min(100%, 24rem); }
.status { font-size: .8rem; padding: .05rem .45rem; border-radius: 999px; border: 1px solid var(--lt-border); }
.status.open { color: #0a7d3b; border-color: #0a7d3b; }
.status.in-progress { color: #9a6700; border-color: #9a6700; }
.status.closed { color: var(--lt-muted); }
.lt-report tr.urgent td:first-child { box-shadow: inset 3px 0 #c62828; }
.lt-report tr.high td:first-child { box-shadow: inset 3px 0 #ef6c00; }
.issue-meta { color: var(--lt-muted); }
.issue-body { margin: 1rem 0; }
.comment { border-top: 1px solid var(--lt-border); padding: .5rem 0; }
.muted { color: var(--lt-muted); font-size: .85rem; }
.new-comment textarea { width: min(100%, 36rem); display: block; margin-bottom: .4rem; }
a.action { margin-right: .8rem; }")

;;; Running it

(defun register-tracker (&key (path "/tracker") file)
  "Serve Tracker at PATH, keeping its data in FILE (loaded if it exists)."
  (setf *tracker-file* file)
  (when (and file (probe-file file))
    (load-store file))
  (register-application path 'tracker :title "Tracker" :mode :deployment))

(defun start-tracker (&key (port 8080) file (path "/tracker"))
  "Serve Tracker at PATH on PORT, keeping its data in FILE (loaded if it exists)."
  (register-tracker :path path :file file)
  (start :port port))
