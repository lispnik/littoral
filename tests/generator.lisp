;;;; generator.lisp — a generated project loads and its own tests pass

(in-package #:littoral/tests)

(def-suite generator :in littoral)
(in-suite generator)

(defun scratch-directory ()
  (uiop:ensure-directory-pathname
   (merge-pathnames (format nil "littoral-generator-~36R/" (random (expt 36 8)))
                    (uiop:temporary-directory))))

(test generated-projects-work
  (let ((dir (scratch-directory)))
    (unwind-protect
         (let ((*standard-output* (make-broadcast-stream)))
           (littoral.generator:make-project "lt-generated" :directory dir :author "A. Tester"
                                                           :port 8123)
           (is (probe-file (merge-pathnames "lt-generated.asd" dir)))
           (is (probe-file (merge-pathnames ".gitignore" dir)))
           (is (search "A. Tester" (uiop:read-file-string (merge-pathnames "LICENSE" dir))))
           (let ((makefile (uiop:read-file-string (merge-pathnames "Makefile" dir))))
             (is (search (namestring (asdf:system-source-directory :littoral)) makefile))
             (is (search (format nil "~Ctest:" #\Newline) makefile))
             (is (search (format nil "~C$(SBCL)" #\Tab) makefile)))
           (is (null (search "{{" (uiop:read-file-string (merge-pathnames "src/app.lisp" dir)))))
           (is (search "Lt Generated" (uiop:read-file-string (merge-pathnames "src/app.lisp" dir))))
           ;; Load it and run its own suite.
           (asdf:load-asd (merge-pathnames "lt-generated.asd" dir))
           (asdf:load-system "lt-generated/tests")
           (let ((results (let ((fiveam:*test-dribble* (make-broadcast-stream)))
                            (fiveam:run (uiop:find-symbol* '#:lt-generated '#:lt-generated/tests)))))
             (is (>= (length results) 8))
             (is (every (lambda (r) (typep r 'fiveam::test-passed)) results)))
           ;; It doesn't overwrite.
           (signals error (littoral.generator:make-project "lt-generated" :directory dir)))
      (asdf:clear-system "lt-generated")
      (asdf:clear-system "lt-generated/tests")
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test project-names-are-checked
  (dolist (bad '("Bookshop" "book shop" "1shop" "littoral-extra" ""))
    (signals error (littoral.generator:make-project bad :directory (scratch-directory))))
  (is (string= "Book Shop" (littoral.generator::title-from-name "book-shop")))
  (is (member "basic" (littoral.generator:project-templates) :test #'string=))
  (is (string= "a 1 {{other}}" (littoral.generator::substitute-placeholders
                                "a {{n}} {{other}}" '(:n 1)))))

(test the-license-follows-the-choice
  (let ((dir (scratch-directory)))
    (unwind-protect
         (let ((*standard-output* (make-broadcast-stream)))
           (littoral.generator:make-project "lt-other" :directory dir :license "BSD-2-Clause")
           (is (null (probe-file (merge-pathnames "LICENSE" dir))))
           (is (search "BSD-2-Clause" (uiop:read-file-string (merge-pathnames "lt-other.asd" dir)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test the-app-template-works
  ;; A database, signing in and an admin: its own tests pass here too.
  (let ((dir (scratch-directory)))
    (unwind-protect
         (let ((*standard-output* (make-broadcast-stream)))
           (littoral.generator:make-project "lt-generated-app" :directory dir :template "app")
           (is (probe-file (merge-pathnames "deploy/lt-generated-app.service" dir)))
           (is (search "PUBLIC_URL" (uiop:read-file-string (merge-pathnames "README.md" dir))))
           (asdf:load-asd (merge-pathnames "lt-generated-app.asd" dir))
           (asdf:load-system "lt-generated-app/tests")
           (let ((results (let ((fiveam:*test-dribble* (make-broadcast-stream)))
                            (fiveam:run (uiop:find-symbol* '#:lt-generated-app '#:lt-generated-app/tests)))))
             (is (>= (length results) 10))
             (is (every (lambda (r) (typep r 'fiveam::test-passed)) results)
                 "~{~A~%~}" (mapcar #'fiveam::reason (remove-if (lambda (r) (typep r 'fiveam::test-passed)) results)))))
      ;; Its tests set the iteration count for themselves; put ours back.
      (setf littoral.auth:*pbkdf2-iterations* 1000)
      (asdf:clear-system "lt-generated-app")
      (asdf:clear-system "lt-generated-app/tests")
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))
