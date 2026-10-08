;;;; generator.lisp — start a new Littoral application
;;;;
;;;;   (littoral.generator:make-project "bookshop")
;;;;
;;;; or `make new NAME=bookshop DIR=~/src/bookshop` from Littoral's checkout.
;;;; Copies a template directory (templates/basic/), replacing {{name}},
;;;; {{title}}, {{author}}, {{license}}, {{year}}, {{port}} and
;;;; {{littoral}} in file names and contents.  The result is a system with a
;;;; root component, FiveAM tests through the fake browser, and a Makefile
;;;; that tests, serves and builds an executable.

(defpackage #:littoral.generator
  (:use #:cl)
  (:documentation "Generate the skeleton of a new Littoral application.")
  (:export #:make-project #:project-templates))

(in-package #:littoral.generator)

(defun templates-directory ()
  (asdf:system-relative-pathname :littoral "templates/"))

(defun project-templates ()
  "The names of the templates MAKE-PROJECT can start from."
  (mapcar (lambda (dir) (car (last (pathname-directory dir))))
          (uiop:subdirectories (templates-directory))))

(defun valid-name-p (name)
  (and (stringp name) (cl-ppcre:scan "^[a-z][a-z0-9-]*$" name)
       (not (alexandria:starts-with-subseq "littoral" name))))

(defun title-from-name (name)
  "\"book-shop\" → \"Book Shop\"."
  (format nil "~{~:(~A~)~^ ~}" (cl-ppcre:split "-" name)))

(defun git-user-name ()
  (or (ignore-errors
       (let ((name (string-trim '(#\Space #\Newline)
                                (uiop:run-program '("git" "config" "user.name")
                                                  :output :string :ignore-error-status t))))
         (and (plusp (length name)) name)))
      ""))

(defun substitute-placeholders (text values)
  "TEXT with each {{key}} replaced by its value from the plist VALUES."
  (cl-ppcre:regex-replace-all
   "\\{\\{([a-z]+)\\}\\}" text
   (lambda (match key)
     (let ((value (getf values (intern (string-upcase key) :keyword) :missing)))
       (if (eq value :missing) match (princ-to-string value))))
   :simple-calls t))

(defun template-files (template)
  "The files of TEMPLATE, as (SOURCE . RELATIVE-PATH-STRING), dot files included."
  (let ((root (merge-pathnames (format nil "~A/" template) (templates-directory)))
        (files '()))
    (unless (uiop:directory-exists-p root)
      (error "No template ~S; there are ~{~S~^, ~}." template (project-templates)))
    (uiop:collect-sub*directories
     root (constantly t) (constantly t)
     (lambda (dir)
       (dolist (file (uiop:directory-files dir))
         (push (cons file (enough-namestring file root)) files))))
    (sort files #'string< :key #'cdr)))

(defun make-project (name &key directory (title (title-from-name name)) (author (git-user-name))
                            (license "MIT") (port 8080) (template "basic"))
  "Write a new Littoral application called NAME (lower-case letters, digits
and dashes) into DIRECTORY, by default ./NAME/, from TEMPLATE.  Refuses to
replace existing files.  The LICENSE file is written for the MIT license
only.  Returns the directory."
  (unless (valid-name-p name)
    (error "~S won't do as a project name: use lower-case letters, digits and dashes, ~
starting with a letter (and not \"littoral\")." name))
  (let* ((directory (uiop:ensure-directory-pathname
                     (or directory (merge-pathnames (format nil "~A/" name) (uiop:getcwd)))))
         (values (list :name name :title title :author author :license license :port port
                       :year (nth-value 5 (decode-universal-time (get-universal-time)))
                       :littoral (namestring (asdf:system-source-directory :littoral))))
         (files (remove-if (lambda (file)
                             (and (string= (cdr file) "LICENSE") (string/= license "MIT")))
                           (template-files template)))
         (targets (mapcar (lambda (file)
                            (merge-pathnames (substitute-placeholders (cdr file) values) directory))
                          files)))
    (let ((existing (remove-if-not #'probe-file targets)))
      (when existing
        (error "Not replacing ~{~A~^, ~}." (mapcar #'namestring existing))))
    (loop for (source) in files
          for target in targets
          do (ensure-directories-exist target)
             (with-open-file (out target :direction :output :external-format :utf-8)
               (write-string (substitute-placeholders
                              (uiop:read-file-string source :external-format :utf-8) values)
                             out)))
    (format t "~&Wrote ~A to ~A~%~%  cd ~A~%  make test~%  make run     # then open http://127.0.0.1:~D/~%"
            name (namestring directory) (namestring directory) port)
    directory))
