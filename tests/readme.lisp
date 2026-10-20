;;;; readme.lisp — the README's code blocks read, and the complete ones work

(in-package #:littoral/tests)

(def-suite readme :in littoral)
(in-suite readme)

(defun readme-blocks ()
  "The Lisp blocks of README.md, in order."
  (let ((text (alexandria:read-file-into-string
               (asdf:system-relative-pathname :littoral "README.md") :external-format :utf-8))
        (blocks '()))
    (cl-ppcre:do-register-groups (block) ("(?s)```lisp\\n(.*?)```" text)
      (push block blocks))
    (nreverse blocks)))

(defun readme-block (marker)
  "The one README block containing MARKER."
  (let ((found (remove-if-not (lambda (block) (search marker block)) (readme-blocks))))
    (unless (= 1 (length found))
      (error "~D README blocks contain ~S." (length found) marker))
    (first found)))

(defun fresh-readme-package ()
  (let ((package (make-package (format nil "README-BLOCK-~D" (random (expt 10 9)))
                               :use '(#:cl #:littoral #:littoral.test))))
    (sb-ext:add-package-local-nickname '#:h '#:littoral.html package)
    package))

(defun littoral-package-name-p (name)
  (let ((name (string-upcase (string name))))
    (or (string= name "LITTORAL") (alexandria:starts-with-subseq "LITTORAL." name))))

(defun read-readme-block (block)
  "Read BLOCK's forms, as a reader pasting it would, evaluating only its
DEFPACKAGE and IN-PACKAGE forms (so later forms read in the right
package), and delete the packages it made.  A reference to a package of
the reader's own (such as my-app) ends the reading; one to a Littoral
package that doesn't export the name is an error, as at the REPL.
Returns the forms read."
  (let ((before (list-all-packages)) (*package* (fresh-readme-package)) (forms '()) (position 0))
    (unwind-protect
         (handler-case
             (loop
               (multiple-value-bind (form end) (read-from-string block nil block :start position)
                 (when (eq form block) (return))
                 (setf position end)
                 (push form forms)
                 (when (and (consp form) (member (first form) '(defpackage in-package)))
                   (eval form))))
           (package-error (e)
             (let ((package (package-error-package e)))
               (when (littoral-package-name-p (if (packagep package) (package-name package) package))
                 (error e)))))
      (dolist (package (set-difference (list-all-packages) before))
        (ignore-errors (delete-package package))))
    (nreverse forms)))

(defun run-readme-block (block &key (replace '()) (skip '(asdf:load-system littoral:start)) check)
  "Evaluate BLOCK's forms in turn in a fresh package and a thread of its own,
with no applications registered and a database of its own, leaving out
calls to the operators in SKIP.  REPLACE is a list of (OLD . NEW) strings
substituted first, such as a temporary file for \"app.db\".  Then call
CHECK, if given, in the same thread; returns its value.  The packages the
block made are deleted afterwards."
  (dolist (pair replace)
    (setf block (cl-ppcre:regex-replace-all (cl-ppcre:quote-meta-chars (car pair)) block (cdr pair))))
  (let ((result nil) (problem nil) (before (list-all-packages)))
    (sb-thread:join-thread
     (sb-thread:make-thread
      (lambda ()
        (handler-case
            (let ((littoral::*applications* (make-hash-table :test 'equal))
                  (littoral.db:*database* nil)
                  (*package* (fresh-readme-package))
                  (position 0))
              (loop
                (multiple-value-bind (form end) (read-from-string block nil block :start position)
                  (when (eq form block) (return))
                  (setf position end)
                  (unless (and (consp form) (member (first form) skip))
                    (eval form))))
              (setf result (and check (funcall check))))
          (error (e) (setf problem e))))
      :name "README block"))
    ;; The packages the block made, such as hello, go: later tests may
    ;; make their own of the same name.
    (dolist (package (set-difference (list-all-packages) before))
      (ignore-errors (delete-package package)))
    (when problem (error problem))
    result))

(defmacro with-readme-database ((file) &body body)
  "BODY with FILE, a namestring, naming a SQLite file deleted afterwards."
  `(let ((,file (namestring (merge-pathnames (format nil "littoral-readme-~36R.sqlite3" (random (expt 36 8)))
                                             (uiop:temporary-directory)))))
     (unwind-protect (progn ,@body)
       (dolist (suffix '("" "-wal" "-shm"))
         (uiop:delete-file-if-exists (concatenate 'string ,file suffix))))))

(test readme-blocks-read
  ;; Every block reads, and names only what Littoral exports.
  (let ((blocks (readme-blocks)))
    (is (> (length blocks) 25))
    (dolist (block blocks)
      (let ((problem (handler-case (progn (read-readme-block block) nil)
                       (error (e) (princ-to-string e)))))
        (is (null problem) "This README block doesn't read (~A):~%~A" problem block)))))

(test readme-hello
  ;; The first example: a counter, with the back button.
  (is (equal '(0 3 2)
             (run-readme-block
              (readme-block "(defpackage #:hello")
              :check (lambda ()
                       (let ((b (make-instance 'browser)) (shown '()))
                         (flet ((count-shown ()
                                  (parse-integer (cl-ppcre:scan-to-strings "(?<=<h1>)\\d+" (browser-html b)))))
                           (visit b "/counter")
                           (push (count-shown) shown)
                           (click b "++") (click b "++")
                           (let ((two (browser-url b)))
                             (click b "++")
                             (push (count-shown) shown)
                             (back-to b two)
                             (push (count-shown) shown)))
                         (nreverse shown)))))))

(test readme-database
  (with-readme-database (file)
    (is (equal '("Ada")
               (run-readme-block (readme-block "(defclass contact (littoral.db:persistent)")
                                 :replace (list (cons "\"app.db\"" (prin1-to-string file)))
                                 :check (lambda ()
                                          (mapcar (lambda (contact) (slot-value contact (find-symbol "NAME")))
                                                  (littoral.db:db-select (find-symbol "CONTACT")))))))))

(test readme-signing-in
  (with-readme-database (file)
    (is (string= "ada"
                 (run-readme-block (readme-block "(littoral.auth:add-user \"ada\"")
                                   :replace (list (cons "\"app.db\"" (prin1-to-string file)))
                                   :check (lambda ()
                                            (prog1 (littoral.auth:user-name (littoral.auth:find-user "ada"))
                                              (littoral.auth:drop-auth-tables))))))))

(test readme-audit
  ;; Recorded on a database with the audit tables, and found again.
  (let ((events nil))
    (run-readme-block (concatenate 'string
                                   "(setf littoral.db:*database* '(:sqlite3 :database-name \":memory:\"))
(littoral.audit:create-audit-tables)
"
                                   (readme-block "(littoral.audit:audit \"invoice.sent\""))
                      :check (lambda ()
                               (setf events (littoral.audit:audit-events :action "invoice"))
                               (littoral.audit:drop-audit-tables)))
    (is (equal '(("invoice.sent" "Invoice 42"))
               (mapcar (lambda (e) (list (littoral.audit:audit-event-action e)
                                         (littoral.audit:audit-event-subject-label e)))
                       events)))))

(test readme-parenscript
  (is (search "Ask the server"
              (run-readme-block
               (readme-block "(defclass buttons (updatable component)")
               :check (lambda ()
                        (with-fresh-applications (((format nil "/buttons-~D" (random 1000))
                                                   (find-symbol "BUTTONS" *package*) :mode :deployment))
                          (let ((b (make-instance 'browser)))
                            (visit b (application-path (first (list-applications))))
                            (body-text b))))))))

(test readme-testing
  ;; The testing section's test passes, run against the todo example.
  (is (eq t (run-readme-block
             (readme-block "(test adding-to-the-list")
             :replace '(("my-app:todo-list" . "littoral-examples:todo-list")
                        ("#:my-app/tests" . "#:littoral-readme-tests"))
             :check (lambda ()
                      (prog1 (fiveam:run! (find-symbol "ADDING-TO-THE-LIST" "LITTORAL-README-TESTS"))
                        (delete-package "LITTORAL-README-TESTS")))))))
