;;;; db.lisp — described objects in SQLite

(in-package #:littoral/tests)

(def-suite db :in littoral)
(in-suite db)

(defclass project (littoral.db:persistent)
  ((name :initarg :name :initform nil)
   (budget :initarg :budget :initform nil))
  (:documentation "A stored project."))

(define-description project
  ((name :required t)
   (budget :type :integer :min 0)))

(littoral.db:define-table project)

(defclass job (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (done :initarg :done :initform nil)
   (due :initarg :due :initform nil)
   (state :initarg :state :initform :todo)
   (project :initarg :project :initform nil))
  (:documentation "A stored job, belonging to a project."))

(define-description job
  ((title :required t)
   (done :type :boolean)
   (due :type :date)
   (state :type :choice :choices '(:todo :doing :done))
   (project :type :reference :to 'project)))

(littoral.db:define-table job :name "jobs")

(defmacro with-test-database (() &body body)
  "Run BODY against the test database, with both tables made afresh."
  `(progn
     (connect-test-database)
     (littoral.db:drop-table 'job)
     (littoral.db:drop-table 'project)
     (littoral.db:create-table 'project)
     (littoral.db:create-table 'job)
     ,@body))

(test crud-and-queries
  (with-test-database ()
    (let ((p (littoral.db:db-save (make-instance 'project :name "Littoral" :budget 10))))
      (is (integerp (littoral.db:object-id p)))
      (dolist (title '("write" "test" "ship"))
        (littoral.db:db-save (make-instance 'job :title title :project p :due '(2026 12 1)
                                                 :state (if (string= title "ship") :done :todo))))
      (is (= 3 (littoral.db:db-count 'job)))
      (let ((jobs (littoral.db:db-select 'job :order-by "title")))
        (is (equal '("ship" "test" "write") (mapcar (lambda (j) (slot-value j 'title)) jobs)))
        (let ((ship (first jobs)))
          (is (eq :done (slot-value ship 'state)))
          (is (equal '(2026 12 1) (slot-value ship 'due)))
          (is (null (slot-value ship 'done)))
          ;; References come back as objects.
          (is (string= "Littoral" (slot-value (slot-value ship 'project) 'name)))))
      (is (equal '("test")
                 (mapcar (lambda (j) (slot-value j 'title))
                         (littoral.db:db-select 'job :where "state = ?" :params '("TODO")
                                                     :order-by "title" :limit 1 :offset 0))))
      (is (= 2 (littoral.db:db-count 'job :where "state = ?" :params '("TODO"))))
      (let ((job (first (littoral.db:db-select 'job))))
        (littoral.db:db-delete job)
        (is (null (littoral.db:object-id job)))
        (is (= 2 (littoral.db:db-count 'job)))))))

(test optimistic-locking
  (with-test-database ()
    (let* ((p (littoral.db:db-save (make-instance 'project :name "A")))
           (mine (littoral.db:db-find 'project (littoral.db:object-id p)))
           (theirs (littoral.db:db-find 'project (littoral.db:object-id p))))
      (setf (slot-value theirs 'name) "B")
      (littoral.db:db-save theirs)
      (setf (slot-value mine 'name) "C")
      (signals littoral.db:stale-object (littoral.db:db-save mine))
      (signals littoral.db:stale-object (littoral.db:db-delete mine))
      ;; Reloading gives the current version, which then saves.
      (let ((fresh (littoral.db:db-reload mine)))
        (is (string= "B" (slot-value fresh 'name)))
        (setf (slot-value fresh 'name) "C")
        (littoral.db:db-save fresh)
        (is (string= "C" (slot-value (littoral.db:db-reload fresh) 'name)))))))

(defclass project-maker (component)
  ((fail :initform nil :accessor maker-fail))
  (:documentation "Saves two projects per click; the second save can fail."))

(defmethod render ((self project-maker))
  (p () (text (format nil "~D projects" (littoral.db:db-count 'project))))
  (anchor (:callback (lambda ()
                       (littoral.db:db-save (make-instance 'project :name "one"))
                       (littoral.db:db-save (make-instance 'project :name "two"))))
    "make two")
  (anchor (:callback (lambda ()
                       (littoral.db:db-save (make-instance 'project :name "one"))
                       (error "Something went wrong after the first save")))
    "make two badly"))

(test transactions-around-callbacks
  (with-test-database ()
    (with-fresh-applications (("/p" 'project-maker :mode :deployment
                                    :around-actions (littoral.db:transactional)))
      (let ((b (make-instance 'browser)))
        (visit b "/p")
        (click b "make two badly")
        (is (= 500 (browser-status b)))
        ;; The first save was rolled back with the failed request.
        (is (= 0 (littoral.db:db-count 'project)))
        (visit b "/p")
        (click b "make two")
        (is (has-text-p b "2 projects"))))))

(defclass project-editor-page (component)
  ((id :initarg :project-id :reader page-project-id)
   (message :initform nil :accessor page-message))
  (:documentation "Edits a stored project the recommended way: a fresh copy, then save."))

(defmethod render ((self project-editor-page))
  (let ((project (littoral.db:db-find 'project (page-project-id self))))
    (when (page-message self) (p (:class "message") (text (page-message self))))
    (p () "Project: " (text (slot-value project 'name)))
    (anchor (:callback
             (lambda ()
               (show self (make-editor (littoral.db:db-find 'project (page-project-id self)))
                     :on-answer (lambda (edited)
                                  (when edited
                                    (handler-case (progn (littoral.db:db-save edited)
                                                         (setf (page-message self) "Saved."))
                                      (littoral.db:stale-object ()
                                        (setf (page-message self)
                                              "Someone else changed it meanwhile; showing theirs."))))))))
      "edit")))

(defvar *project-to-edit* nil)

(defclass project-editor-root (project-editor-page) ()
  (:default-initargs :project-id *project-to-edit*))

(test editing-stored-objects
  (with-test-database ()
    (let ((p (littoral.db:db-save (make-instance 'project :name "First" :budget 5))))
      (setf *project-to-edit* (littoral.db:object-id p))
      (with-fresh-applications (("/e" 'project-editor-root :mode :deployment))
        (let ((b (make-instance 'browser)))
          (visit b "/e")
          (click b "edit")
          (fill-in b "name" "Second")
          (press b "Save")
          (is (has-text-p b "Saved."))
          (is (has-text-p b "Project: Second"))
          ;; Someone else saves while this editor is open.
          (click b "edit")
          (let ((other (littoral.db:db-find 'project (littoral.db:object-id p))))
            (setf (slot-value other 'name) "Theirs")
            (littoral.db:db-save other))
          (fill-in b "name" "Mine")
          (press b "Save")
          (is (has-text-p b "Someone else changed it meanwhile"))
          (is (has-text-p b "Project: Theirs")))))))

(test reference-field-choices
  (with-test-database ()
    (littoral.db:db-save (make-instance 'project :name "Alpha"))
    (littoral.db:db-save (make-instance 'project :name "Beta"))
    (let ((field (find-field 'job 'project)))
      (is (equal '("Alpha" "Beta") (mapcar (lambda (p) (format-field field p)) (field-choices field))))
      (is (string= "Beta" (slot-value (parse-field field "1") 'name))))))

;;; Full-text search

(defclass article (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (body :initarg :body :initform nil)))

(define-description article ((title :required t) (body :type :text)))

(littoral.db:define-table article :name "articles" :search (title body))

(test full-text-search
  (connect-test-database)
  (littoral.db:drop-table 'article)
  (littoral.db:create-table 'article)
  (dolist (spec '(("Lisp macros" "Macros transform code before it runs.")
                  ("Garbage collection" "Collectors free memory nobody refers to.")
                  ("Macro-writing macros" "Macros all the way down: writing macros that write macros.")))
    (littoral.db:db-save (make-instance 'article :title (first spec) :body (second spec))))
  (flet ((titles (query) (mapcar (lambda (a) (slot-value a 'title)) (littoral.db:db-search 'article query))))
    ;; Words match word starts; every word is required.
    (is (equal '("Garbage collection") (titles "collect")))
    (is (= 2 (length (titles "macro"))))
    (is (equal '("Macro-writing macros") (titles "writing macro")))
    ;; The page about macros most of all comes first.
    (is (string= "Macro-writing macros" (first (titles "macros"))))
    (is (null (titles "")))
    (is (null (titles "!!! ''")))
    ;; The index follows changes.
    (let ((gc (first (littoral.db:db-search 'article "garbage"))))
      (setf (slot-value gc 'body) "Now about compilers.")
      (littoral.db:db-save gc)
      (is (null (titles "memory")))
      (is (equal '("Garbage collection") (titles "compilers")))
      (littoral.db:db-delete gc)
      (is (null (titles "compilers"))))
    ;; A condition to combine with others.
    (multiple-value-bind (where params) (littoral.db:search-condition 'article "macros")
      (is (= 2 (length (littoral.db:db-select 'article :where where :params params)))))
    ;; Rows already there are indexed when the index is first made.
    (littoral.db:db-execute (format nil "DROP ~:[TABLE~;INDEX~] IF EXISTS articles_search" (postgres-test-p)))
    (littoral.db:create-table 'article)
    (is (= 2 (length (titles "macro"))))))

(test highlighting-matches
  (is (string= "Use <mark>Macros</mark> &amp; <mark>macrolet</mark>, not &lt;script&gt;"
               (littoral.db:highlight-matches "Use Macros & macrolet, not <script>" "macro")))
  (is (string= "a &amp; b" (littoral.db:highlight-matches "a & b" "amp"))))

(test the-search-example
  (let ((file (merge-pathnames (format nil "littoral-search-test-~36R.sqlite3" (random (expt 36 8))) (uiop:temporary-directory))))
    (unwind-protect
         (with-fresh-applications ()
           (littoral-search-demo:register :file file)
           (let ((b (make-instance 'browser)))
             (visit b "/examples/search")
             ;; The first query, "list", finds LIST itself among the first.
             (is (search "<mark>list</mark>" (browser-html b)))
             (let* ((input (element-name b "query"))
                    (spec (first (ajax-specs b "on-input")))
                    (json (ajax-request b (car spec) (cdr spec) :fields (list (cons input "hash table")))))
               (is (search "<mark>hash</mark>" json))
               (is (search "gethash" json)))))
      (uiop:delete-file-if-exists file))))
