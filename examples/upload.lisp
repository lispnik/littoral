;;;; upload.lisp — receiving files

(in-package #:littoral-examples)

(defclass upload-demo (component)
  ((file :initform nil :accessor uploaded))
  (:documentation "Receives a file and describes it."))

(defun text-preview (file)
  "The first lines of FILE when it looks like text, else NIL."
  (when (alexandria:starts-with-subseq "text/" (h:file-content-type file))
    (let ((text (handler-case (sb-ext:octets-to-string (h:file-contents file) :external-format :utf-8)
                  (error () nil))))
      (and text (subseq text 0 (min 2000 (length text)))))))

(defmethod render ((self upload-demo))
  (h:h1 () "Upload")
  (h:form (:multipart t)
    ;; A drop zone: littoral.js takes dropped files, and shows a progress
    ;; bar while the form uploads.
    (h:div (:class "lt-drop")
      (h:label (:for "file") "File to upload ")
      (h:file-input (:id "file" :callback (lambda (file) (setf (uploaded self) file))))
      (h:span (:class "lt-drop-hint") "or drop a file here")
      (h:span (:class "lt-drop-files" :aria-live "polite")))
    (h:submit-button () "Upload"))
  (let ((file (uploaded self)))
    (when file
      (h:table (:class "lt-table")
        (h:tr () (h:th () "Name") (h:td () (h:text (h:file-name file))))
        (h:tr () (h:th () "Type") (h:td () (h:text (h:file-content-type file))))
        (h:tr () (h:th () "Size") (h:td () (h:text (format nil "~:D bytes" (length (h:file-contents file)))))))
      (let ((preview (text-preview file)))
        (when preview (h:pre () (h:text preview)))))))
