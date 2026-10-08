;;;; admin.lisp — an administration interface generated from descriptions
;;;;
;;;;   (register-admin "/admin" '(project job)
;;;;                   :database '(:sqlite3 :database-name "app.db")
;;;;                   :credentials '("admin" . "secret"))
;;;;
;;;; For each stored class (see littoral/db): a searchable, filterable,
;;;; sortable list; a page per object with its fields, links to the objects
;;;; it refers to and lists of those referring to it; editing that notices
;;;; someone else's concurrent change; creation; deletion after asking.
;;;; Without credentials the admin answers only requests from this machine.

(defpackage #:littoral.admin
  (:use #:cl #:littoral #:littoral.html #:littoral.db)
  (:documentation "An administration interface generated from descriptions.")
  (:export #:register-admin #:admin))

(in-package #:littoral.admin)

(defvar *admins* (make-hash-table :test 'equal)
  "Application path → the classes its admin manages.")

(defun admin-classes ()
  "The classes the current admin application manages."
  (gethash (application-path *application*) *admins*))

(defun class-label (class &optional plural)
  "CLASS's name for people: \"Job\", or with PLURAL \"Jobs\"."
  (let ((name (string-capitalize (substitute #\Space #\- (symbol-name class)))))
    (if plural (format nil "~A~:[s~;es~]" name (find (char name (1- (length name))) "sx")) name)))

(defun class-fields (class)
  "CLASS's described fields."
  (description-fields (find-description class)))

(defun text-fields (class)
  "CLASS's fields searched by the search box."
  (remove-if-not (lambda (f) (and (typep f 'string-field) (not (typep f 'password-field))))
                 (class-fields class)))

(defun filter-fields (class)
  "CLASS's fields offered as filters: choices and yes/no."
  (remove-if-not (lambda (f) (and (typep f '(or choice-field boolean-field))
                                  (not (typep f 'reference-field))))
                 (class-fields class)))

(defun referring-fields (class)
  "Pairs (OTHER-CLASS . FIELD) for the reference fields, among the admin's
classes, that point at CLASS."
  (loop for other in (admin-classes)
        append (loop for field in (class-fields other)
                     when (and (typep field 'reference-field) (eq (reference-class field) class))
                       collect (cons other field))))

;;; One object

(defclass object-page (component)
  ((class :initarg :class :reader page-class)
   (id :initarg :object-id :reader page-object-id)
   (admin :initarg :admin :reader page-admin))
  (:documentation "One stored object: its fields, references, and actions."))

(defun render-value (field value admin)
  "VALUE of FIELD; references link to the object they refer to."
  (if (and (typep field 'reference-field) value)
      (anchor (:callback (lambda () (open-object admin (reference-class field) (object-id value))))
        (text (format-field field value)))
      (render-field-value field value)))

(defmethod render ((self object-page))
  (let* ((class (page-class self))
         (admin (page-admin self))
         (object (db-find class (page-object-id self))))
    (if (null object)
        (progn (p () (translate "This record no longer exists."))
               (p () (anchor (:callback (lambda () (answer self))) (translate "Back"))))
        (progn
          (h2 () (text (format nil "~A #~D" (class-label class) (object-id object))))
          (table (:class "lt-table lt-viewer")
            (dolist (field (class-fields class))
              (unless (or (typep field 'password-field) (field-hidden-p field))
                (tr () (th () (text (field-label field)))
                  (td () (render-value field (field-value field object) admin))))))
          (div (:class "lt-buttons")
            (anchor (:class "action" :callback (lambda () (edit-object admin class (object-id object))))
              "Edit")
            (anchor (:class "action" :callback (lambda () (delete-object admin self object)))
              "Delete")
            (anchor (:callback (lambda () (answer self))) (translate "Back to the list")))
          ;; Those that refer to this one.
          (loop for (other . field) in (referring-fields class)
                for related = (db-select other :where (format nil "~A = ?"
                                                              (substitute #\_ #\- (string-downcase (symbol-name (field-name field)))))
                                               :params (list (object-id object)))
                when related
                  do (h3 () (text (format nil "~A with this ~A" (class-label other t)
                                          (string-downcase (class-label class)))))
                     (ul ()
                       (dolist (r related)
                         (let ((r r) (other other))
                           (li () (anchor (:callback (lambda () (open-object admin other (object-id r))))
                                    (text (object-title r))))))))))))

(defun object-title (object)
  "A line naming OBJECT: its first text field, or its number."
  (let ((field (first (text-fields (class-name (class-of object))))))
    (or (and field (field-value field object))
        (format nil "#~D" (object-id object)))))

;;; The list of one class

(defclass class-list (component updatable)
  ((class :initarg :class :reader list-class)
   (admin :initarg :admin :reader list-admin)
   (query :initform "" :accessor list-query)
   (filters :initform '() :accessor list-filters
            :documentation "Alist of field name → the value it must have.")
   (report :reader list-report))
  (:documentation "The stored objects of one class, searchable and filterable."))

(defmethod states ((self class-list))
  (list self))

(defmethod children ((self class-list))
  (list (list-report self)))

(defun matching-objects (list)
  "LIST's objects that match its search and filters, as SQL decides."
  (let ((clauses '()) (params '())
        (query (string-trim " " (list-query list)))
        (class (list-class list)))
    (when (and (string/= query "") (text-fields class))
      (push (format nil "(~{~A LIKE ?~^ OR ~})"
                    (mapcar (lambda (f) (substitute #\_ #\- (string-downcase (symbol-name (field-name f)))))
                            (text-fields class)))
            clauses)
      (dolist (f (text-fields class))
        (declare (ignore f))
        (push (format nil "%~A%" query) params)))
    (loop for (name . value) in (list-filters list)
          for field = (find-field class name)
          do (push (format nil "~A = ?" (substitute #\_ #\- (string-downcase (symbol-name name)))) clauses)
             (push (to-sql field value) params))
    (db-select class :where (and clauses (format nil "~{~A~^ AND ~}" (reverse clauses)))
                     :params (reverse params))))

(defmethod initialize-instance :after ((self class-list) &key)
  (let ((class (list-class self)) (admin (list-admin self)))
    (setf (slot-value self 'report)
          (make-instance
           'report
           :rows (lambda () (matching-objects self))
           :batch-size 20
           :columns (append
                     (list (column "#" #'object-id :class "number"
                                   :render (lambda (object id)
                                             (declare (ignore object))
                                             (anchor (:callback (lambda () (open-object admin class id)))
                                               (text id)))))
                     (loop for field in (class-fields class)
                           unless (or (typep field 'password-field) (typep field 'text-field)
                                      (field-hidden-p field)
                                      (not (littoral::field-in-report-p field)))
                             collect (let ((field field))
                                       (column (field-label field) (littoral::field-reader field)
                                               :sort-key (lambda (o)
                                                           (let ((v (field-value field o)))
                                                             (if (typep field 'reference-field)
                                                                 (and v (format-field field v))
                                                                 (if (listp v) (format-field field v) v))))
                                               :render (lambda (object value)
                                                         (declare (ignore object))
                                                         (render-value field value admin))))))))))

(defun set-filter (list name value)
  "Filter LIST on field NAME having VALUE, or not at all for :ANY."
  (setf (list-filters list)
        (if (eq value :any)
            (remove name (list-filters list) :key #'car)
            (acons name value (remove name (list-filters list) :key #'car)))))

(defmethod render ((self class-list))
  (let ((class (list-class self)))
    (div (:class "admin-list")
      (div (:class "admin-controls")
        (text-input (:id "search" :label "Search" :placeholder "Search" :value (list-query self)
                     :callback (lambda (v) (setf (list-query self) v))
                     :on-input (ajax-update self)))
        (dolist (field (filter-fields class))
          (let* ((field field)
                 (name (field-name field))
                 (current (or (cdr (assoc name (list-filters self))) :any)))
            (label () (text (field-label field)) " "
              (select-list (:items (cons :any (if (typep field 'boolean-field) '(t nil) (field-choices field)))
                            :selected current
                            :labels (lambda (v)
                                      (cond ((eq v :any) (translate "Any"))
                                            ((typep field 'boolean-field) (if v (translate "Yes") (translate "No")))
                                            (t (format-field field v))))
                            :callback (lambda (v) (set-filter self name v))
                            :on-change (ajax-update self)))))))
      (let ((count (length (matching-objects self))))
        (p (:class "admin-count") (text (format nil "~D ~A" count (string-downcase (class-label class (/= count 1)))))))
      (render-component (list-report self)))))

;;; The application

(defclass admin (component)
  ((lists :initform (make-hash-table) :reader admin-lists)
   (selected :accessor admin-selected)
   (message :initform nil :accessor admin-message)
   (main :reader admin-main))
  (:documentation "The root of an admin application: header, messages and
menu stay; pages replace the main area."))

(defclass main-area (component)
  ((admin :initarg :admin :reader area-admin))
  (:documentation "Where an admin shows the selected class's list, or the
page shown in its place."))

(defmethod initialize-instance :after ((self admin) &key)
  (setf (admin-selected self) (first (admin-classes))
        (slot-value self 'main) (make-instance 'main-area :admin self)))

(defmethod states ((self admin))
  (list self))

(defun class-list-for (admin class)
  "ADMIN's list for CLASS, made once."
  (or (gethash class (admin-lists admin))
      (setf (gethash class (admin-lists admin)) (make-instance 'class-list :class class :admin admin))))

(defmethod children ((self admin))
  (list (admin-main self)))

(defmethod children ((self main-area))
  (list (class-list-for (area-admin self) (admin-selected (area-admin self)))))

(defmethod render ((self main-area))
  (let* ((admin (area-admin self))
         (class (admin-selected admin)))
    (h1 () (text (class-label class t)))
    (p () (anchor (:callback (lambda () (create-object admin class)))
            (text (translate "New ~A" (string-downcase (class-label class))))))
    (render-component (class-list-for admin class))))

(defun show-page (admin page &rest show-arguments)
  "Show PAGE in ADMIN's main area, replacing whatever page was there."
  (home (admin-main admin))
  (apply #'show (admin-main admin) page show-arguments))

(defun open-object (admin class id)
  "Show the object of CLASS numbered ID in ADMIN's main area."
  (show-page admin (make-instance 'object-page :class class :object-id id :admin admin)))

(defun save-edited (admin class edited)
  "Save EDITED; on someone else's change, say so and show theirs."
  (handler-case (progn (db-save edited)
                       (setf (admin-message admin) (translate "Saved ~A #~D." (class-label class) (object-id edited)))
                       (open-object admin class (object-id edited)))
    (stale-object ()
      (setf (admin-message admin) (translate "Someone else changed this record meanwhile; here it is as they left it."))
      (open-object admin class (object-id edited)))))

(defun edit-object (admin class id)
  "Edit the object of CLASS numbered ID, then save it."
  (let ((object (db-find class id)))
    (when object
      (show-page admin (make-editor object :title (translate "Edit ~A #~D" (class-label class) id))
            :on-answer (lambda (edited)
                         (if edited
                             (save-edited admin class edited)
                             (open-object admin class id)))))))

(defun create-object (admin class)
  "Ask for a new object of CLASS, then store it."
  (show-page admin (make-editor (make-instance class) :title (translate "New ~A" (string-downcase (class-label class)))
                                                  :save-label "Create")
        :on-answer (lambda (object)
                     (when object
                       (db-insert object)
                       (setf (admin-message admin)
                             (translate "Created ~A #~D." (class-label class) (object-id object)))
                       (open-object admin class (object-id object))))))

(defun delete-object (admin page object)
  "Ask, then delete OBJECT."
  (show page (make-instance 'confirm-dialog
                            :message (translate "Delete ~A #~D, ~A?" (class-label (page-class page))
                                             (object-id object) (object-title object)))
        :on-answer (lambda (yes)
                     (when yes
                       (handler-case
                           (progn (db-delete object)
                                  (setf (admin-message admin)
                                        (translate "Deleted ~A #~D." (class-label (page-class page))
                                                (page-object-id page))))
                         (stale-object ()
                           (setf (admin-message admin)
                                 "Someone else changed or deleted this record meanwhile; nothing was deleted.")))
                       (home (admin-main admin))))))

(defmethod render ((self admin))
  (header (:class "admin-header")
    (strong () (text (or (application-title *application*) "Admin"))))
  (when (admin-message self)
    (p (:class "lt-message notice" :role "status") (text (admin-message self))))
  (div (:class "admin-body")
    (nav (:class "admin-menu" :aria-label (translate "Tables"))
      (ul ()
        (dolist (class (admin-classes))
          (let ((class class))
            (li (:class (when (eq class (admin-selected self)) "lt-active"))
              (anchor (:aria-current (when (eq class (admin-selected self)) "page")
                       :callback (lambda ()
                                   (home (admin-main self))
                                   (setf (admin-selected self) class
                                         (admin-message self) nil)))
                (text (class-label class t))))))))
    (section (:class "admin-main")
      (render-component (admin-main self)))))

(defmethod style ((self admin))
  ".admin-header { border-bottom: 1px solid var(--lt-border); padding-bottom: .4rem; margin-bottom: .8rem; }
.admin-body { display: grid; grid-template-columns: 11rem minmax(0, 1fr); gap: 1.5rem; }
@media (max-width: 40rem) { .admin-body { grid-template-columns: minmax(0, 1fr); } }
.admin-menu ul { list-style: none; padding: 0; margin: 0; }
.admin-menu a { display: block; padding: .3rem .6rem; border-radius: 4px; text-decoration: none; }
.admin-menu li.lt-active a { background: var(--lt-panel); font-weight: 600; }
.admin-controls { display: flex; flex-wrap: wrap; gap: .8rem; align-items: center; margin-bottom: .4rem; }
.admin-count { color: var(--lt-muted); font-size: .9rem; }
.admin-main { overflow-x: auto; }
a.action { margin-right: .8rem; }")

(defun register-admin (path classes &key (title "Admin") database credentials (mode :deployment))
  "Serve an admin for CLASSES (stored classes, see DEFINE-TABLE) at PATH.
DATABASE (a driver and parameters, as CONNECT-DATABASE takes them) gives
it its own database; otherwise it uses the current one.  Without
CREDENTIALS it answers only requests from this machine."
  (setf (gethash (littoral::normalize-path path) *admins*) classes)
  (register-application path 'admin
                        :title title :mode mode
                        :credentials credentials
                        :local-only (null credentials)
                        :around-request (and database (apply #'using-database database))
                        :around-actions (transactional)))
