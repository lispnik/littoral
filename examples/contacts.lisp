;;;; contacts.lisp — a whole application from one description
;;;;
;;;; The table, the editor (with validation) and the detail view are all
;;;; generated from DEFINE-DESCRIPTION; only the list and its buttons are
;;;; written by hand.

(in-package #:littoral-examples)

(defclass contact ()
  ((name :initarg :name :initform nil)
   (email :initarg :email :initform nil)
   (phone :initarg :phone :initform nil)
   (role :initarg :role :initform nil)
   (birthday :initarg :birthday :initform nil)
   (website :initarg :website :initform nil)
   (favourite :initarg :favourite :initform nil)
   (notes :initarg :notes :initform nil))
  (:documentation "Someone in the address book."))

(define-description contact
  ((name :required t :max-length 60)
   (email :type :email :required t)
   (phone :pattern "[0-9 +()-]{5,20}" :pattern-message "Phone numbers are digits, spaces and + ( ) -.")
   (role :type :choice :choices '(:friend :colleague :family :other) :labels #'string-capitalize)
   (birthday :type :date :help "Year, month and day, like 1990-04-23.")
   (website :type :url :in-report nil)
   (favourite :type :boolean)
   (notes :type :text :in-report nil))
  :validate (lambda (values)
              (when (and (eq (getf values :role) :family) (null (getf values :birthday)))
                "Family members need a birthday.")))

(defun sample-contacts ()
  (list (make-instance 'contact :name "Ada Lovelace" :email "ada@example.org" :role :colleague
                                :birthday '(1815 12 10) :favourite t)
        (make-instance 'contact :name "Charles Babbage" :email "charles@example.org" :role :colleague
                                :birthday '(1791 12 26))
        (make-instance 'contact :name "Grace Hopper" :email "grace@example.org" :role :friend
                                :website "https://en.wikipedia.org/wiki/Grace_Hopper")))

(defclass contacts-app (component)
  ((contacts :initform (sample-contacts) :accessor contacts)
   (report :reader contacts-report))
  (:documentation "An address book: list, add, view, edit and remove contacts."))

(defmethod initialize-instance :after ((self contacts-app) &key)
  (setf (slot-value self 'report)
        (make-instance
         'report
         :rows (lambda () (contacts self))
         :batch-size 10
         :columns (append
                   (description-columns 'contact)
                   (list (column "" nil :sortable nil
                                 :render (lambda (contact value)
                                           (declare (ignore value))
                                           (anchor (:callback (lambda () (show self (make-viewer contact))))
                                             "view")
                                           (text " ")
                                           (anchor (:callback (lambda () (edit-contact self contact)))
                                             "edit")
                                           (text " ")
                                           (anchor (:callback (lambda () (remove-contact self contact)))
                                             "remove"))))))))

(defmethod states ((self contacts-app))
  ;; The list is replaced, never changed in place, so a shallow snapshot
  ;; keeps the back button honest.
  (list self))

(defmethod children ((self contacts-app))
  (list (contacts-report self)))

(defun edit-contact (app contact)
  (show app (make-editor contact :title (format nil "Edit ~A" (slot-value contact 'name)))))

(defun add-contact (app)
  (let ((contact (make-instance 'contact)))
    (show app (make-editor contact :title "New contact" :save-label "Add")
          :on-answer (lambda (added)
                       (when added
                         (setf (contacts app) (append (contacts app) (list added))))))))

(defun remove-contact (app contact)
  (show app (make-instance 'confirm-dialog
                           :message (format nil "Remove ~A?" (slot-value contact 'name)))
        :on-answer (lambda (yes)
                     (when yes (setf (contacts app) (remove contact (contacts app)))))))

(defmethod render ((self contacts-app))
  (h1 () "Contacts")
  (p () (anchor (:callback (lambda () (add-contact self))) "Add a contact"))
  (render-component (contacts-report self)))
