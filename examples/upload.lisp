;;;; upload.lisp — receiving files

(in-package #:littoral-examples)

(defclass upload-demo (component)
  ((file :initform nil :accessor uploaded))
  (:documentation "Receives a file and describes it."))

(defun text-preview (file)
  "The first lines of FILE when it looks like text, else NIL."
  (when (alexandria:starts-with-subseq "text/" (file-content-type file))
    (let ((text (handler-case (sb-ext:octets-to-string (file-contents file) :external-format :utf-8)
                  (error () nil))))
      (and text (subseq text 0 (min 2000 (length text)))))))

(defmethod render ((self upload-demo))
  (h1 () "Upload")
  (form (:multipart t)
    (file-input (:id "file" :callback (lambda (file) (setf (uploaded self) file))))
    (submit-button () "Upload"))
  (let ((file (uploaded self)))
    (when file
      (table (:class "lt-table")
        (tr () (th () "Name") (td () (text (file-name file))))
        (tr () (th () "Type") (td () (text (file-content-type file))))
        (tr () (th () "Size") (td () (text (format nil "~:D bytes" (length (file-contents file)))))))
      (let ((preview (text-preview file)))
        (when preview (pre () (text preview)))))))
