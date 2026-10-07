;;;; admin.lisp — the generated administration interface

(in-package #:littoral/tests)

(def-suite admin :in littoral)
(in-suite admin)

(defparameter *admin-database* '(:sqlite3 :database-name ":memory:"))

(defmacro with-admin ((b) &body body)
  "Serve an admin of projects and jobs, seeded, and give it a browser B."
  `(with-fresh-applications ()
     (apply #'littoral.db:connect-database *admin-database*)
     (littoral.db:drop-table 'job)
     (littoral.db:drop-table 'project)
     (littoral.db:create-table 'project)
     (littoral.db:create-table 'job)
     (let ((littoral (littoral.db:db-save (make-instance 'project :name "Littoral" :budget 100)))
           (seaside (littoral.db:db-save (make-instance 'project :name "Seaside" :budget 50))))
       (littoral.db:db-save (make-instance 'job :title "Write docs" :state :todo :project littoral))
       (littoral.db:db-save (make-instance 'job :title "Fix tabs" :state :doing :project littoral :done nil))
       (littoral.db:db-save (make-instance 'job :title "Port halos" :state :done :project seaside :done t)))
     (littoral.admin:register-admin "/admin" '(project job) :database *admin-database* :title "Test admin")
     (let ((,b (make-instance 'browser)))
       (visit ,b "/admin")
       ,@body)))

(test admin-lists-and-search
  (with-admin (b)
    (is (has-text-p b "Test admin"))
    (is (has-text-p b "Projects"))
    (is (has-text-p b "2 projects"))
    (is (has-text-p b "Littoral"))
    (click b "Jobs")
    (is (has-text-p b "3 jobs"))
    ;; Search over text fields, by AJAX.
    (let* ((spec (first (ajax-specs b "on-input")))
           (json (ajax-request b (first spec) (rest spec)
                               :fields (list (cons (element-name b "search") "tabs")))))
      (is (search "Fix tabs" json))
      (is (not (search "Write docs" json)))
      (is (search "1 job<" json)))))

(test admin-filters
  (with-admin (b)
    (click b "Jobs")
    ;; The State filter: choose "doing".
    (let* ((spec (first (ajax-specs b "on-change")))
           (select (cl-ppcre:register-groups-bind (name) ("<select name=\"(\\d+)\" data-lt-on-change" (browser-html b)) name))
           (json (ajax-request b (first spec) (rest spec) :fields (list (cons select "2")))))
      (is (search "Fix tabs" json))
      (is (not (search "Port halos" json))))))

(test admin-object-pages-and-references
  (with-admin (b)
    (click b "Jobs")
    (click-nth b "1" 0)                 ; job #1
    (is (has-text-p b "Job #1"))
    (is (has-text-p b "Write docs"))
    ;; Follow the reference to its project...
    (click b "Littoral")
    (is (has-text-p b "Project #1"))
    ;; ...which lists the jobs that refer to it.
    (is (has-text-p b "Jobs with this project"))
    (is (find-link b "Write docs"))
    (is (find-link b "Fix tabs"))
    (is (not (find-link b "Port halos")))))

(test admin-edit-create-delete
  (with-admin (b)
    (click-nth b "1" 0)
    (click b "Edit")
    (fill-in b "budget" "-5")
    (press b "Save")
    (is (has-text-p b "Budget must be at least 0."))
    (fill-in b "budget" "250")
    (press b "Save")
    (is (has-text-p b "Saved Project #1."))
    (is (has-text-p b "250"))
    ;; Someone else changes it while it is being edited.
    (click b "Edit")
    (let ((other (littoral.db:db-find 'project 1)))
      (setf (slot-value other 'name) "Theirs")
      (littoral.db:db-save other))
    (fill-in b "name" "Mine")
    (press b "Save")
    (is (has-text-p b "Someone else changed this record meanwhile"))
    (is (has-text-p b "Theirs"))
    ;; Create.
    (click b "Back to the list")
    (click b "New project")
    (fill-in b "name" "Pharo")
    (press b "Create")
    (is (has-text-p b "Created Project #3."))
    ;; Delete, after asking.
    (click b "Delete")
    (press b "No")
    (is (has-text-p b "Project #3"))
    (click b "Delete")
    (press b "Yes")
    (is (has-text-p b "Deleted Project #3."))
    (is (= 2 (littoral.db:db-count 'project)))))

(test admin-is-local-only-without-credentials
  (with-admin (b)
    (let ((remote (make-env :get "/admin")))
      (setf (getf remote :remote-addr) "203.0.113.9")
      (is (= 403 (first (funcall (make-lack-app) remote)))))))

(test admin-demo-leaves-littoral-classes-alone
  ;; The demo's own TASK class must not replace LITTORAL:TASK.
  (is (subtypep 'littoral:task 'littoral:component))
  (is (not (eq 'littoral-admin-demo:task 'littoral:task))))
