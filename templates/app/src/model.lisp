;;;; model.lisp — what the application keeps
;;;;
;;;; A class, a description (validation, editors, reports and the admin all
;;;; come from it) and a table.  Add fields here; CREATE-TABLE makes the
;;;; table, so a new column on an existing database needs an ALTER TABLE.

(in-package #:{{name}})

(defclass note (littoral.db:persistent)
  ((title :initarg :title :initform nil :accessor note-title)
   (body :initarg :body :initform nil :accessor note-body)
   (owner :initarg :owner :initform nil :accessor note-owner
          :documentation "The USER-ID of whoever wrote it, as text."))
  (:documentation "A note, private to the user who wrote it."))

(define-description note
  ((title :required t :max-length 120)
   (body :type :text)
   (owner :hidden t)))

(littoral.db:define-table note :name "notes")
