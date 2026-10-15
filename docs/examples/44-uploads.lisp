;;;; The example for fields that upload files.  See tools/doc-examples.lisp for the format.

;;;; Example: littoral:field-multipart-p
;;; Description editors and wizards make their form multipart when any field says it uploads a file.  A field kind of your own whose input is a file input says so with a method; littoral.storage:file-field (in littoral/storage) already does.
(defclass scan-field (field) ())
(defmethod field-multipart-p ((field scan-field))
  t)
(list (field-multipart-p (make-instance 'string-field :name 'title :label "Title"))
      (field-multipart-p (make-instance 'scan-field :name 'scan :label "Scanned letter"))
      (field-multipart-p (make-instance 'littoral.storage:file-field :name 'photo :label "Photo")))
;; ⇒ (NIL T T)
