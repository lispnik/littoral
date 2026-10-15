;;;; The examples for littoral.generator: the skeleton of a new application.

;;;; Example: littoral.generator:make-project
;;; A new project from the basic template, written into a temporary directory (deleted afterwards).  The project's name fills in its file names and contents; MAKE-PROJECT also prints how to test and run it, which the example discards.
(let ((directory (merge-pathnames "littoral-example-bookshop/" (uiop:temporary-directory))))
  (unwind-protect
       (progn
         (let ((*standard-output* (make-broadcast-stream)))
           (littoral.generator:make-project "bookshop" :directory directory :author "Ada Lovelace" :port 8090))
         (list (sort (mapcar #'file-namestring (uiop:directory-files directory)) #'string<)
               (sort (mapcar #'file-namestring (uiop:directory-files (merge-pathnames "src/" directory))) #'string<)
               (find-if (lambda (line) (search ":author" line))
                        (uiop:read-file-lines (merge-pathnames "bookshop.asd" directory)))))
    (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore)))
;; ⇒ ((".gitignore" "LICENSE" "Makefile" "README.md" "bookshop.asd") ("app.lisp" "package.lisp") "  :author \"Ada Lovelace\"")

;;;; Example: littoral.generator:make-project
;;; A name must be lower-case letters, digits and dashes, starting with a letter.  Existing files are never replaced.
(handler-case (littoral.generator:make-project "Book Shop")
  (error () :refused))
;; ⇒ :REFUSED
(let ((directory (merge-pathnames "littoral-example-twice/" (uiop:temporary-directory)))
      (*standard-output* (make-broadcast-stream)))
  (unwind-protect
       (progn
         (littoral.generator:make-project "twice" :directory directory :author "Ada")
         (handler-case (littoral.generator:make-project "twice" :directory directory :author "Ada")
           (error () :refused)))
    (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore)))
;; ⇒ :REFUSED

;;;; Example: littoral.generator:project-templates
;;; The templates there are: "basic" (a root component and its tests) and "app" (with a database, signing in and an admin).
(sort (littoral.generator:project-templates) #'string<)
;; ⇒ ("app" "basic")
