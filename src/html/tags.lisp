;;;; tags.lisp — one macro per plain HTML element

(in-package #:littoral)

(defmacro define-tag (name &key (tag (string-downcase (symbol-name name))))
  "Define littoral.html's macro for the element named like NAME."
  (let ((name (intern (symbol-name name) '#:littoral.html)))
    `(defmacro ,name (&rest arguments)
       ,(format nil "Write an HTML ~A element.  Arguments are as for TAG, without the name." tag)
       (multiple-value-bind (attributes body) (split-tag-arguments arguments)
         (list 'emit-tag ,tag (cons 'list attributes) (body-thunk body))))))

(defmacro define-tags (&rest names)
  `(progn ,@(mapcar (lambda (name) `(define-tag ,name)) names)))

;; Every element in the HTML standard, but for FORM and BUTTON, which are
;; brushes (brushes.lisp).  MAP, TIME and SEARCH here are CL's symbols;
;; DEFINE-TAG takes the name of each.
(define-tags
  html head title base link meta style script noscript template slot body
  article section nav aside h1 h2 h3 h4 h5 h6 hgroup header footer address main search
  p hr pre blockquote ol ul menu li dl dt dd figure figcaption div
  a em strong small s cite q dfn abbr ruby rt rp data time code var samp kbd sub sup
  i b u mark bdi bdo span br wbr ins del
  picture source img iframe embed object video audio track map area canvas
  table caption colgroup col tbody thead tfoot tr td th
  fieldset legend label input select datalist optgroup option selectedcontent
  textarea output progress meter
  details summary dialog)
