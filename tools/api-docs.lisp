;;;; api-docs.lisp — write docs/API.md from the exported symbols' docstrings
;;;;
;;;;   make docs
;;;;
;;;; Sections follow the ";; Heading" comments in src/package.lisp, so the
;;;; reference reads in the order the exports are listed.

(defpackage #:littoral-api-docs
  (:use #:cl)
  (:export #:write-api-docs)
  (:documentation "Writes docs/API.md from Littoral's docstrings."))

(in-package #:littoral-api-docs)

(defun export-sections (package-file package-name)
  "Alist of (HEADING . SYMBOL-NAMES) for PACKAGE-NAME's :export list in PACKAGE-FILE."
  (let* ((text (alexandria:read-file-into-string package-file))
         (start (cl-ppcre:scan (format nil "\\(defpackage #:~(~A~)\\s" (cl-ppcre:quote-meta-chars package-name))
                               text))
         (export (search "(:export" text :start2 start))
         (end (search "))" text :start2 export))
         (sections '())
         (current (list "General")))
    (dolist (line (cl-ppcre:split "\\n" (subseq text export end)))
      (let ((heading (cl-ppcre:register-groups-bind (h) ("^\\s*;;\\s*(.+)$" line) h)))
        (if heading
            (progn (push (nreverse current) sections)
                   (setf current (list heading)))
            (cl-ppcre:do-register-groups (name) ("#:([^\\s()]+)" line)
              (push (string-upcase name) current)))))
    (push (nreverse current) sections)
    (remove-if (lambda (s) (null (rest s))) (nreverse sections))))

(defun accessor-documentation (symbol)
  "For a slot reader or writer, the documentation of its slot, introduced."
  (dolist (method (closer-mop:generic-function-methods (fdefinition symbol)))
    (when (typep method 'closer-mop:standard-accessor-method)
      (let* ((slot (closer-mop:accessor-method-slot-definition method))
             (class (first (closer-mop:method-specializers method)))
             (doc (documentation slot t)))
        (let ((class-name (string-downcase
                           (class-name (if (typep class 'class) class
                                           (second (closer-mop:method-specializers method)))))))
          (return (format nil "Reads the ~(~A~) of ~:[a~;an~] ~A.~@[  ~A~]"
                          (closer-mop:slot-definition-name slot)
                          (find (char class-name 0) "aeiou")
                          class-name
                          doc)))))))

(defun kinds (symbol)
  "What SYMBOL names, as (KIND . DOCUMENTATION) pairs."
  (let ((kinds '()))
    (when (find-class symbol nil)
      (push (cons (if (subtypep symbol 'condition) "Condition" "Class")
                  (documentation symbol 'type))
            kinds))
    (cond ((macro-function symbol) (push (cons "Macro" (documentation symbol 'function)) kinds))
          ((and (fboundp symbol) (typep (fdefinition symbol) 'generic-function))
           (push (cons "Generic function" (or (documentation symbol 'function)
                                              (accessor-documentation symbol)))
                 kinds))
          ((fboundp symbol) (push (cons "Function" (documentation symbol 'function)) kinds))
          (t nil))
    (when (boundp symbol)
      (push (cons "Variable" (documentation symbol 'variable)) kinds))
    (nreverse kinds)))

(defparameter *cc-lambda-lists*
  '((littoral:call self other)
    (littoral:inform self message)
    (littoral:confirm self question)
    (littoral:request-input self prompt &optional (default ""))
    (littoral:choose-from self items &optional prompt))
  "DEFUN/CC functions take &REST internally; these are what callers pass.")

(defun unqualified (form)
  "FORM printed in lower case with no package prefixes."
  (cond ((null form) "()")
        ((stringp form) (prin1-to-string form))
        ((symbolp form) (if (keywordp form)
                            (format nil ":~(~A~)" (symbol-name form))
                            (string-downcase (symbol-name form))))
        ((consp form) (format nil "(~{~A~^ ~})" (mapcar #'unqualified form)))
        (t (prin1-to-string form))))

(defun lambda-list-string (symbol)
  "SYMBOL's lambda list as callers write it."
  (let ((list (or (rest (assoc symbol *cc-lambda-lists*))
                  (sb-introspect:function-lambda-list symbol))))
    (format nil "~{~A~^ ~}" (mapcar #'unqualified list))))

(defun markdown-doc (doc)
  "DOC, a docstring, as Markdown: the paragraphs kept, NAMES in capitals as code."
  (cl-ppcre:regex-replace-all
   "(?<![\\w*-])([A-Z][A-Z0-9*+-]*[A-Z0-9*])(?![\\w-])" doc
   (lambda (match name)
     (declare (ignore match))
     (if (> (length name) 1) (format nil "`~(~A~)`" name) name))
   :simple-calls t))

(defun write-entry (symbol out)
  "Write SYMBOL's reference entries to OUT; true when it is undocumented."
  (let ((kinds (kinds symbol))
        (name (string-downcase (symbol-name symbol))))
    (dolist (kind kinds)
      (destructuring-bind (label . doc) kind
        (format out "~%#### `~A`~@[ `~A`~] — ~(~A~)~%~%"
                name
                (when (member label '("Function" "Macro" "Generic function") :test #'string=)
                  (let ((ll (lambda-list-string symbol))) (and (string/= ll "") ll)))
                label)
        (if doc
            (format out "~A~%" (markdown-doc doc))
            (format out "*Undocumented.*~%"))))
    (null (remove nil (mapcar #'cdr kinds)))))

(defun write-api-docs (&key (root (asdf:system-source-directory :littoral))
                         (output (merge-pathnames "docs/API.md" root)))
  "Write the API reference; return the exported symbols that lack documentation."
  (let ((undocumented '()))
    (with-open-file (out output :direction :output :if-exists :supersede :external-format :utf-8)
      (format out "# Littoral API reference~%~%Generated from the docstrings by `make docs`; ~
do not edit by hand.~%")
      (dolist (entry '(("littoral" "src/package.lisp") ("littoral.html" "src/package.lisp")
                       ("littoral.test" "testing/package.lisp")))
        (destructuring-bind (package file) entry
        (format out "~%## Package `~A`~%~%~A~%" package
                (or (documentation (find-package (string-upcase package)) t) ""))
        (dolist (section (export-sections (merge-pathnames file root) package))
          (format out "~%### ~A~%" (first section))
          (dolist (name (rest section))
            (let ((symbol (find-symbol name (string-upcase package))))
              (when (and symbol (write-entry symbol out))
                (push symbol undocumented))))))))
    (nreverse undocumented)))
