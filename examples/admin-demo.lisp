;;;; admin-demo.lisp — an admin over projects and tasks, in SQLite
;;;;
;;;; (asdf:load-system :littoral/admin-demo) (littoral-admin-demo:register)
;;;; serves it at /examples/admin, its data in a file in the temp directory.

(defpackage #:littoral-admin-demo
  (:use #:cl #:littoral #:littoral.db)
  ;; LITTORAL exports TASK (the component); this demo's TASK is a record.
  (:shadow #:task)
  (:documentation "A generated admin over a small SQLite database.")
  (:export #:register #:project #:task))

(in-package #:littoral-admin-demo)

(defclass project (persistent)
  ((name :initarg :name :initform nil)
   (owner :initarg :owner :initform nil)
   (budget :initarg :budget :initform nil)
   (status :initarg :status :initform :active))
  (:documentation "A project."))

(define-description project
  ((name :required t :max-length 80)
   (owner :type :email)
   (budget :type :integer :min 0)
   (status :type :choice :choices '(:active :paused :finished) :labels #'string-capitalize)))

(define-table project)

(defclass task (persistent)
  ((title :initarg :title :initform nil)
   (notes :initarg :notes :initform nil)
   (due :initarg :due :initform nil)
   (done :initarg :done :initform nil)
   (project :initarg :project :initform nil))
  (:documentation "A task within a project."))

(define-description task
  ((title :required t :max-length 120)
   (notes :type :text)
   (due :type :date)
   (done :type :boolean)
   (project :type :reference :to 'project)))

(define-table task)

(defun seed ()
  "Fill an empty database with a few projects and tasks."
  (when (zerop (db-count 'project))
    (let ((littoral (db-save (make-instance 'project :name "Littoral" :owner "matthew@example.org" :budget 1000)))
          (docs (db-save (make-instance 'project :name "Documentation" :budget 200 :status :paused))))
      (dolist (spec `(("Ship 0.2" ,littoral (2026 11 1) nil)
                      ("Database layer" ,littoral (2026 10 15) t)
                      ("Admin interface" ,littoral (2026 10 20) nil)
                      ("Tutorial chapter on admin" ,docs nil nil)))
        (destructuring-bind (title project due done) spec
          (db-save (make-instance 'task :title title :project project :due due :done done)))))))

(defun register (&key (path "/examples/admin")
                   (file (merge-pathnames "littoral-admin-demo.sqlite3" (uiop:temporary-directory))))
  "Serve the demo admin at PATH, keeping its data in FILE."
  (let ((database (list :sqlite3 :database-name (namestring file))))
    (let ((*database* database))
      (create-table 'project)
      (create-table 'task)
      (seed))
    (littoral.admin:register-admin path '(project task) :title "Littoral admin demo" :database database)))
