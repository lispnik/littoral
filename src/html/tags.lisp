;;;; tags.lisp — one macro per plain HTML element

(in-package #:littoral)

(defmacro define-tag (name &key (tag (string-downcase (symbol-name name))))
  `(defmacro ,name (&rest arguments)
     ,(format nil "Write a <~A> element." tag)
     (multiple-value-bind (attributes body) (split-tag-arguments arguments)
       (list 'emit-tag ,tag (cons 'list attributes) (body-thunk body)))))

(defmacro define-tags (&rest names)
  `(progn ,@(mapcar (lambda (name) `(define-tag ,name)) names)))

(define-tags div span p h1 h2 h3 h4 h5 h6 ul ol li dl dt dd
  table thead tbody tfoot tr td th caption
  em strong b i u small code pre blockquote sup sub
  section article aside nav header footer main figure figcaption
  fieldset legend label abbr cite mark dfn kbd samp details summary)

;; VAR is too useful a name to take from users.
(define-tag var-tag :tag "var")

(define-tags img br hr)
