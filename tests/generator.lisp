;;;; generator.lisp — a generated project loads and its own tests pass

(in-package #:littoral/tests)

(def-suite generator :in littoral)
(in-suite generator)

(defun scratch-directory ()
  ;; SBCL starts every process with the same random state: seed afresh, so
  ;; runs don't share paths, nor the fasls compiled from them.
  (uiop:ensure-directory-pathname
   (merge-pathnames (format nil "littoral-generator-~36R/" (random (expt 36 8) (make-random-state t)))
                    (uiop:temporary-directory))))

(defun first-line (file)
  (with-open-file (in file :external-format :utf-8 :if-does-not-exist nil)
    (and in (format nil "~S (~D bytes, written at ~D)" (or (read-line in nil) "") (file-length in)
                    (file-write-date file)))))

(defun loading-context (condition directory)
  "What was being read when CONDITION was signalled, for a report: the file,
and for a fasl the sources of that name under DIRECTORY."
  (let* ((file (or *compile-file-truename* *load-truename*))
         (sources (cond ((null file) '())
                        ((equal (pathname-type file) "lisp") (list file))
                        (t (directory (merge-pathnames (make-pathname :directory '(:relative :wild-inferiors)
                                                                      :name (pathname-name file) :type "lisp")
                                                       directory))))))
    (format nil "~A: ~A~%  compiling ~A, loading ~A~@[ (written at ~D)~], in package ~A; #\\; is ~:[not ~;~]a comment~{~%  ~A starts ~A~}"
            (type-of condition) condition *compile-file-truename* *load-truename*
            (and *load-truename* (file-write-date *load-truename*)) (package-name *package*) (get-macro-character #\;)
            (loop for source in sources collect (enough-namestring source directory) collect (first-line source)))))

(defun load-generated-system (asd system)
  "Load ASD, then SYSTEM, failing the test with what was being read if it
signals: the app template's tests once failed to load in CI, with the
variable APP.LISP unbound, as if a file's first comment had been read as code."
  (let ((contexts '()))
    (handler-case
        ;; Every error, even those handled inside: the last few are reported.
        (handler-bind ((error (lambda (c) (push (or (ignore-errors (loading-context c (uiop:pathname-directory-pathname asd))) "?") contexts))))
          (asdf:load-asd asd)
          (asdf:load-system system))
      (error (c)
        (error "Loading ~A signalled ~A~%~{~A~%~}" system c
               (reverse (subseq contexts 0 (min 3 (length contexts)))))))))

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
           (load-generated-system (merge-pathnames "lt-generated.asd" dir) "lt-generated/tests")
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
           (is (search "INSTANCE_ID=%i" (uiop:read-file-string (merge-pathnames "deploy/lt-generated-app@.service" dir))))
           (is (probe-file (merge-pathnames "deploy/handover.sh" dir)))
           (is (search "PUBLIC_URL" (uiop:read-file-string (merge-pathnames "README.md" dir))))
           (load-generated-system (merge-pathnames "lt-generated-app.asd" dir) "lt-generated-app/tests")
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
