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
;;;; to set up), with no applications registered, and compare each ⇒.
;;;; make docs copies the code, exactly as tested, into docs/API.md.

(defpackage #:littoral-doc-examples
  (:use #:cl)
  (:export #:example #:example-symbols #:example-prose #:example-code #:example-file #:example-line
           #:read-examples #:all-examples #:example-files #:run-example #:*example-packages*)
  (:documentation "Reads and runs the examples in docs/examples/."))

(in-package #:littoral-doc-examples)

(defparameter *example-packages* '("COMMON-LISP" "LITTORAL" "LITTORAL.HTML" "LITTORAL.TEST")
  "The packages an example's package uses, as the reference's set-up does.")

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

(defun run-example (example)
  "Run EXAMPLE in a package of its own.  Returns a list of problems, each a
string; NIL when it works as written."
  (let* ((name (format nil "LITTORAL-EXAMPLE-~D" (random (expt 10 9))))
         (package (make-package name :use *example-packages*))
         (problems '()))
    (unwind-protect
         (handler-case
             (let ((littoral::*applications* (make-hash-table :test 'equal))
                   (*package* package))
               (dolist (piece (forms-and-results (example-code example)))
                 (destructuring-bind (text . expected) piece
                   (let* ((form (read-from-string text))
                          (value (eval form)))
                     (when expected
                       (let ((got (let ((*print-pretty* nil) (*print-readably* nil))
                                    (prin1-to-string value))))
                         (unless (string= got expected)
                           (push (format nil "~A~%  wanted ~A~%  got    ~A" text expected got) problems))))))))
           (error (e)
             (push (format nil "signalled ~A: ~A" (type-of e) e) problems)))
      (delete-package package))
    (nreverse problems)))
