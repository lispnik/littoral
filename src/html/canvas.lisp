;;;; canvas.lisp — writing HTML
;;;;
;;;; Seaside's canvas is an object brushes are asked of (`html div`).  Here
;;;; the canvas is the stream in *CANVAS* and brushes are macros that write
;;;; to it, so a render method reads like the markup it produces:
;;;;
;;;;   (div (:class "counter")
;;;;     (h1 () (text (count-of self)))
;;;;     (anchor (:callback (lambda () (incf (count-of self)))) "++"))
;;;;
;;;; The first argument of a tag is its attribute plist, whose values are
;;;; evaluated.  It may be omitted when the tag has no attributes and its
;;;; first body form is not a list starting with a keyword.  Literal
;;;; strings in a body are written as escaped text; anything else is
;;;; evaluated for effect, so computed values go through TEXT.

(in-package #:littoral)

(defvar *canvas* (make-broadcast-stream)
  "The stream render methods write HTML to.")

(defun text (thing)
  "Write THING, printed with PRINC and HTML-escaped."
  (write-string (html-escape thing) *canvas*)
  nil)

(defun raw (string)
  "Write STRING verbatim."
  (write-string string *canvas*)
  nil)

(defgeneric emit-attribute (key value stream)
  (:documentation "Write one attribute.  KEY is a keyword, VALUE non-NIL.")
  (:method (key value stream)
    (format stream " ~(~A~)" key)
    (unless (eq value t)
      (write-string "=\"" stream)
      (write-string (html-escape (if (and (listp value) (eq key :class))
                                     (join-strings (remove nil value))
                                     value))
                    stream)
      (write-char #\" stream))))

(defun emit-attributes (attributes stream)
  (loop for (key value) on attributes by #'cddr
        when value do (emit-attribute key value stream)))

(defparameter *void-elements*
  '("area" "base" "br" "col" "embed" "hr" "img" "input" "link" "meta" "source" "track" "wbr"))

(defun emit-tag (name attributes body &key (void (member name *void-elements* :test #'string-equal)))
  "Write element NAME with ATTRIBUTES around the output of the thunk BODY.
Void elements such as input and br get no closing tag."
  (let ((stream *canvas*))
    (write-char #\< stream)
    (write-string name stream)
    (emit-attributes attributes stream)
    (write-char #\> stream)
    (unless void
      (when body (funcall body))
      (write-string "</" stream)
      (write-string name stream)
      (write-char #\> stream))
    nil))

(defun attribute-list-p (form)
  (or (null form) (and (consp form) (keywordp (car form)))))

(defun body-thunk (body)
  "A LAMBDA form for BODY with literal strings turned into TEXT calls."
  (when body
    `(lambda ()
       ,@(mapcar (lambda (form) (if (stringp form) `(text ,form) form)) body))))

(defun split-tag-arguments (arguments)
  "Separate a tag macro's (ATTRIBUTES . BODY) when ATTRIBUTES may be omitted."
  (if (and arguments (attribute-list-p (first arguments)))
      (values (first arguments) (rest arguments))
      (values nil arguments)))

(defmacro with-canvas-to-string (() &body body)
  "Evaluate BODY with *CANVAS* collecting into a string, which is returned."
  `(with-output-to-string (*canvas*)
     ,@body))

(defmacro tag (name &rest arguments)
  "Write an element whose NAME (a string) is computed."
  (multiple-value-bind (attributes body) (split-tag-arguments arguments)
    `(emit-tag ,name (list ,@attributes) ,(body-thunk body))))
