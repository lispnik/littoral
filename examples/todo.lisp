;;;; todo.lisp — forms, checkboxes, editing with call

(in-package #:littoral-examples)

(defclass todo-item ()
  ((title :initarg :title :accessor item-title)
   (done :initform nil :accessor item-done-p)))

(defclass todo-list (component)
  ((items :initform '() :accessor items)
   (new-title :initform "" :accessor new-title)))

(defmethod states ((self todo-list))
  (cons self (items self)))

(defun add-item (self)
  (let ((title (string-trim " " (new-title self))))
    (unless (string= title "")
      (setf (items self) (append (items self) (list (make-instance 'todo-item :title title)))
            (new-title self) ""))))

(defun edit-item (self item)
  (show self (make-instance 'input-dialog :message "Rename" :value (item-title item))
        :on-answer (lambda (title)
                     (unless (string= title "")
                       (setf (item-title item) title)))))

(defmethod render ((self todo-list))
  (h1 () "To do")
  (form ()
    (ul (:class "todo")
      (dolist (item (items self))
        (let ((item item))
          (li ()
            (checkbox (:value (item-done-p item)
                       :callback (lambda (v) (setf (item-done-p item) v))))
            " "
            (span (:class (when (item-done-p item) "done")) (text (item-title item)))
            " "
            (anchor (:callback (lambda () (edit-item self item))) "edit")
            " "
            (anchor (:callback (lambda () (setf (items self) (remove item (items self)))))
              "remove")))))
    (text-input (:id "new-title" :value (new-title self) :placeholder "Something to do"
                 :callback (lambda (v) (setf (new-title self) v))))
    (submit-button (:callback (lambda () (add-item self))) "Add")
    (submit-button () "Save")))

(defmethod style ((self todo-list))
  ".todo { list-style: none; padding: 0; } .todo .done { text-decoration: line-through; color: gray; }")
