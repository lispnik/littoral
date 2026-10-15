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
         (end (and export (search "))" text :start2 export)))
         (sections '())
         (current (list "General")))
    (unless export
      (return-from export-sections '()))
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

(defparameter *acronyms*
  '("HTTP" "HTTPS" "URL" "URLS" "URI" "SQL" "JSON" "HTML" "CSS" "JS" "API" "AJAX" "SSE" "TOTP" "HOTP"
    "RFC" "QR" "SVG" "PNG" "CBOR" "IP" "SMTP" "TLS" "DKIM" "PBKDF2" "UTF-8" "OAUTH" "OIDC" "CSV"
    "STARTTLS" "CSP" "CSRF" "DNS" "MX" "WAL" "OK" "WCAG" "MIME" "ASCII" "CPU" "GC" "UUID" "XML" "PDF" "JWT")
  "Words in capitals that are written as words, not names.")

(defun markdown-doc (doc)
  "DOC, a docstring, as Markdown: the paragraphs kept, NAMES in capitals as code."
  (cl-ppcre:regex-replace-all
   ;; A name may be a keyword (:HOST) or have a package (LITTORAL.DB:*DATABASE*).
   "(?<![\\w*:.-])((?:[A-Z][A-Z0-9.-]*:)?:?\\*?[A-Z][A-Z0-9*+-]*[A-Z0-9*])(?![\\w-])" doc
   (lambda (match name)
     (declare (ignore match))
     (if (and (> (length name) 1) (not (member name *acronyms* :test #'string=)))
         (format nil "`~(~A~)`" name)
         name))
   :simple-calls t))

(defvar *examples* (make-hash-table :test 'equal)
  "\"PACKAGE:NAME\" → that symbol's examples, while WRITE-API-DOCS runs.")

(defvar *package-documented* nil
  "The name of the package WRITE-API-DOCS is writing about.")

(defun symbol-key (symbol)
  "SYMBOL as \"package:name\", the way example headers name it: in the
package being documented, which may export a symbol from another (as
littoral.mail does smtp's SMTP-ERROR)."
  (format nil "~(~A:~A~)" (or *package-documented* (package-name (symbol-package symbol))) (symbol-name symbol)))

(defun write-examples (symbol out)
  "Write SYMBOL's examples to OUT."
  (dolist (example (gethash (symbol-key symbol) *examples*))
    (format out "~%~@[~A~%~%~]```lisp~%~A~%```~%"
            (let ((prose (littoral-doc-examples:example-prose example)))
              (and prose (format nil "*Example:* ~A" (markdown-doc prose))))
            (littoral-doc-examples:example-code example))))

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
    (write-examples symbol out)
    (null (remove nil (mapcar #'cdr kinds)))))

(defun write-api-docs (&key (root (asdf:system-source-directory :littoral))
                         (output (merge-pathnames "docs/API.md" root)))
  "Write the API reference.  Return the exported symbols that lack
documentation, and the functions, macros and classes that lack examples."
  (let ((undocumented '()) (without-examples '())
        (*examples* (make-hash-table :test 'equal)))
    (dolist (example (reverse (littoral-doc-examples:all-examples)))
      (dolist (name (littoral-doc-examples:example-symbols example))
        (push example (gethash (string-downcase name) *examples*))))
    (with-open-file (out output :direction :output :if-exists :supersede :external-format :utf-8)
      (format out "# Littoral API reference~%~%Generated from the docstrings and docs/examples/ by ~
`make docs`; do not edit by hand.~%~%~A~%"
              (alexandria:read-file-into-string (merge-pathnames "docs/examples/README.md" root)
                                                :external-format :utf-8))
      (dolist (entry '(("littoral" "src/package.lisp") ("littoral.html" "src/package.lisp")
                       ("littoral.test" "testing/package.lisp")
                       ("littoral.browser-test" "testing/chrome.lisp")
                       ("littoral.mail" "src/mail.lisp")
                       ("littoral.jobs" "src/durable-jobs.lisp")
                       ("littoral.audit" "src/audit.lisp")
                       ("littoral.auth" "src/auth.lisp")
                       ("littoral.admin" "src/admin.lisp")
                       ("littoral.db" "src/db.lisp")
                       ("littoral.storage" "src/storage.lisp")
                       ("littoral.oauth" "src/oauth.lisp")
                       ("littoral.websocket" "src/websocket.lisp")
                       ("littoral.parenscript" "src/parenscript.lisp")
                       ("littoral.woo" "src/woo.lisp")
                       ("littoral.generator" "src/generator.lisp")))
        (destructuring-bind (package file) entry
         (let ((*package-documented* package))
        (format out "~%## Package `~A`~%~%~A~%" package
                (or (documentation (find-package (string-upcase package)) t) ""))
        (dolist (section (export-sections (merge-pathnames file root) package))
          (format out "~%### ~A~%" (first section))
          (dolist (name (rest section))
            (let ((symbol (find-symbol name (string-upcase package))))
              (when (and symbol (write-entry symbol out))
                (push symbol undocumented))
              (when (and symbol (or (fboundp symbol) (find-class symbol nil))
                         (null (gethash (symbol-key symbol) *examples*)))
                (push symbol without-examples)))))))))
    (values (nreverse undocumented) (nreverse without-examples))))
