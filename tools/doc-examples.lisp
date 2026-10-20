;;;; doc-examples.lisp — the API reference's examples, read and checked
;;;;
;;;; Each file under docs/examples/ is a run of examples.  One starts at a
;;;; header naming the symbols it is for, may go on with prose, and then
;;;; has code.  A comment starting with ⇒ after a form is what the form
;;;; returns, as the REPL prints it:
;;;;
;;;;   ;;;; Example: littoral.html:with-canvas-to-string
;;;;   ;;; The HTML that rendering writes, as a string.
;;;;   (with-canvas-to-string () (p () "Hi"))
;;;;   ;; ⇒ "<p>Hi</p>"
;;;;
;;;; The tests run every example on its own, in a new package that uses
;;;; the packages *EXAMPLE-PACKAGES* names (as the reference tells readers
;;;; to set up), with no applications or endpoints registered and its
;;;; own copy of the translation catalogues, and compare each ⇒.
;;;; make docs copies the code, exactly as tested, into docs/API.md.

(defpackage #:littoral-doc-examples
  (:use #:cl)
  (:export #:example #:example-symbols #:example-prose #:example-code #:example-file #:example-line
           #:read-examples #:all-examples #:example-files #:run-example #:*example-packages*)
  (:documentation "Reads and runs the examples in docs/examples/."))

(in-package #:littoral-doc-examples)

(defparameter *example-packages* '("COMMON-LISP" "LITTORAL" "LITTORAL.TEST")
  "The packages an example's package uses, as the reference's set-up does.
LITTORAL.HTML is there too, as H.")

(defclass example ()
  ((symbols :initarg :symbols :reader example-symbols
            :documentation "The symbols the example is for, each as package:name.")
   (prose :initarg :prose :reader example-prose :documentation "What the example shows, or NIL.")
   (code :initarg :code :reader example-code :documentation "The example's code, as written.")
   (file :initarg :file :reader example-file)
   (line :initarg :line :reader example-line))
  (:documentation "One example in docs/examples/."))

(defmethod print-object ((self example) stream)
  (print-unreadable-object (self stream :type t)
    (format stream "~{~A~^ ~} at ~A:~D" (example-symbols self) (file-namestring (example-file self)) (example-line self))))

(defun example-files (&optional (root (asdf:system-source-directory :littoral)))
  "The example files, in order."
  (sort (directory (merge-pathnames "docs/examples/*.lisp" root)) #'string< :key #'namestring))

(defun read-examples (file)
  "The examples in FILE, in order."
  (let ((examples '()) (current nil) (number 0))
    (flet ((finish ()
             (when current
               (destructuring-bind (symbol line prose code) current
                 (push (make-instance 'example
                                      :symbols (remove "" (uiop:split-string symbol) :test #'string=)
                                      :file file :line line
                                      :prose (and prose (format nil "~{~A~^ ~}" (reverse prose)))
                                      :code (string-trim '(#\Newline #\Space)
                                                         (format nil "~{~A~%~}" (reverse code))))
                       examples)))))
      (with-open-file (in file :external-format :utf-8)
        (loop for text = (read-line in nil)
              while text
              do (incf number)
                 (cond ((alexandria:starts-with-subseq ";;;; Example:" text)
                        (finish)
                        (setf current (list (string-trim " " (subseq text 13)) number '() '())))
                       ((null current))  ; the file's own comments, before any example
                       ((and (null (fourth current)) (alexandria:starts-with-subseq ";;; " text))
                        (push (subseq text 4) (third current)))
                       ((and (null (fourth current)) (string= "" (string-trim " " text))))
                       (t (push text (fourth current))))))
      (finish))
    (nreverse examples)))

(defun all-examples ()
  "Every example, from every file."
  (mapcan #'read-examples (example-files)))

(defun forms-and-results (code)
  "CODE's forms as strings, each with the ⇒ text that follows it, or NIL."
  (let ((pieces '()) (position 0))
    (loop
      (let ((start (position-if-not (lambda (c) (member c '(#\Space #\Newline #\Tab))) code :start position)))
        ;; Skip whole-line comments that aren't results.
        (loop while (and start (char= (char code start) #\;)
                         (not (alexandria:starts-with-subseq ";; ⇒" code :start2 start)))
              do (setf start (position-if-not (lambda (c) (member c '(#\Space #\Newline #\Tab))) code
                                              :start (or (position #\Newline code :start start) (length code)))))
        (when (null start) (return))
        (when (alexandria:starts-with-subseq ";; ⇒" code :start2 start)
          (error "A ⇒ with no form before it, at ~S." (subseq code start (min (length code) (+ start 40)))))
        (let ((end (nth-value 1 (let ((*read-suppress* t)) (read-from-string code t nil :start start)))))
          (let* ((after (position-if-not (lambda (c) (member c '(#\Space #\Newline #\Tab))) code :start end))
                 (result (when (and after (alexandria:starts-with-subseq ";; ⇒" code :start2 after))
                           (let ((eol (or (position #\Newline code :start after) (length code))))
                             (prog1 (string-trim " " (subseq code (+ after (length ";; ⇒")) eol))
                               (setf end eol))))))
            (push (cons (string-right-trim '(#\Space #\Newline #\Tab)
                                           (subseq code start (if result (or after end) end)))
                        result)
                  pieces)
            (setf position end)))))
    (nreverse pieces)))

(defun copy-table (table)
  "A copy of hash table TABLE, with any tables among its values copied too."
  (alexandria:copy-hash-table
   table :key (lambda (value) (if (hash-table-p value) (alexandria:copy-hash-table value) value))))

(defparameter *optional-registries*
  '(("LITTORAL.OAUTH" "*PROVIDERS*" :empty)
    ("LITTORAL.ADMIN" "*ADMINS*" :empty)
    ("LITTORAL.AUTH" "*APPLICATION-ROLES*" :empty)
    ;; Keyed by database spec and user id, which every example's :memory: shares.
    ("LITTORAL.AUTH" "*ROLES-CACHE*" :empty)
    ;; Holds the jobs other systems define, such as mail delivery; job
    ;; runner threads read it, so it is restored rather than rebound.
    ("LITTORAL.JOBS" "*DEFINITIONS*" :restore)
    ("LITTORAL.DB" "*MIGRATION-SETS*" :restore)
    ;; Holds the built-in handlers, such as password reset.
    ("LITTORAL.AUTH" "*AUTH-PATHS*" :copy)
    ;; Which databases have a subsystem's tables, for /metrics and checks
    ;; like AUDIT-ENABLED-P.  Every example's :memory: database has the
    ;; same spec, so each starts with none, and the suite's are put back.
    ("LITTORAL.AUDIT" "*AUDIT-DATABASES*" :clear)
    ("LITTORAL.AUTH" "*AUTH-DATABASES*" :clear)
    ("LITTORAL.JOBS" "*JOB-DATABASES*" :clear)
    ("LITTORAL.MAIL" "*MAIL-DATABASES*" :clear)
    ("LITTORAL.DB" "*MIGRATED*" :clear))
  "Registries in systems this one doesn't depend on, as (PACKAGE NAME HOW):
each example gets its own, :EMPTY or a :COPY, when the system is loaded.
Registries other threads read are changed globally instead, and put back
afterwards: kept as they are (:RESTORE) or emptied (:CLEAR).")

(defun optional-registries (&rest hows)
  "The entries of *OPTIONAL-REGISTRIES* whose packages are loaded and whose
HOW is among HOWS, as (SYMBOL . HOW)."
  (loop for (package name how) in *optional-registries*
        for symbol = (and (find-package package) (find-symbol name package))
        when (and symbol (boundp symbol) (member how hows)) collect (cons symbol how)))

(defun call-restoring-registries (thunk)
  "Call THUNK with the :CLEAR registries emptied, then put back the
:RESTORE and :CLEAR registries as they were."
  (let ((saved (loop for (symbol . how) in (optional-registries :restore :clear)
                     for value = (symbol-value symbol)
                     collect (list symbol value (if (hash-table-p value) (copy-table value) (copy-tree value)))
                     when (eq how :clear)
                       do (if (hash-table-p value) (clrhash value) (setf (symbol-value symbol) '())))))
    (unwind-protect (funcall thunk)
      (loop for (symbol table copy) in saved
            do (if (hash-table-p table)
                   (progn (clrhash table)
                          (maphash (lambda (k v) (setf (gethash k table) v)) copy))
                   (setf (symbol-value symbol) copy))))))

(defun fresh-value (entry)
  "The value an example starts with for ENTRY, a (SYMBOL . HOW)."
  (destructuring-bind (symbol . how) entry
    (let ((value (symbol-value symbol)))
      (ecase how
        (:copy (if (hash-table-p value) (copy-table value) (copy-list value)))
        (:empty (if (hash-table-p value) (make-hash-table :test (hash-table-test value)) '()))))))

(defun run-example (example)
  "Run EXAMPLE in a package and a thread of its own.  Returns a list of
problems, each a string; NIL when it works as written.  The thread gives
it database connections of its own, as a reader's REPL would have: DBI
caches connections per thread, so a :memory: SQLite database would
otherwise be the test suite's."
  (call-restoring-registries
   (lambda ()
     (sb-thread:join-thread
      (sb-thread:make-thread (lambda () (run-example-here example)) :name "littoral doc example")))))

(defun run-example-here (example)
  "Run EXAMPLE in a package of its own, in this thread."
  (let* ((name (format nil "LITTORAL-EXAMPLE-~D" (random (expt 10 9))))
         (package (let ((package (make-package name :use *example-packages*)))
                    (sb-ext:add-package-local-nickname '#:h '#:littoral.html package)
                    package))
         (problems '()))
    (unwind-protect
         (handler-case
             (let ((littoral::*applications* (make-hash-table :test 'equal))
                   (littoral::*endpoints* (make-hash-table :test 'equal))
                   ;; Catalogues an example adds to or changes are its own.
                   (littoral::*languages* (copy-table littoral::*languages*))
                   (littoral::*translations* (copy-table littoral::*translations*))
                   (littoral::*missing* (copy-table littoral::*missing*))
                   (*package* package))
              (progv (mapcar #'car (optional-registries :empty :copy))
                     (mapcar #'fresh-value (optional-registries :empty :copy))
               (dolist (piece (forms-and-results (example-code example)))
                 (destructuring-bind (text . expected) piece
                   (let* ((form (read-from-string text))
                          (value (eval form)))
                     (when expected
                       (let ((got (let ((*print-pretty* nil) (*print-readably* nil))
                                    (prin1-to-string value))))
                         (unless (string= got expected)
                           (push (format nil "~A~%  wanted ~A~%  got    ~A" text expected got) problems)))))))))
           (error (e)
             (push (format nil "signalled ~A: ~A" (type-of e) e) problems)))
      (delete-package package))
    (nreverse problems)))
