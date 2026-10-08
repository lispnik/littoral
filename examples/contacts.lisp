;;;; contacts.lisp — a whole application from one description
;;;;
;;;; The table, the editor (with validation) and the detail view are all
;;;; generated from DEFINE-DESCRIPTION; only the list and its buttons are
;;;; written by hand.
;;;;
;;;; It is also the example of translation: its strings, the field labels
;;;; among them, have French and German catalogues below, and the language
;;;; chooser switches between them.

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
   (role :type :choice :choices '(:friend :colleague :family :other) :labels (lambda (role) (translate (string-capitalize role))))
   (birthday :type :date :help "Year, month and day, like 1990-04-23.")
   (website :type :url :in-report nil)
   (favourite :type :boolean)
   (notes :type :text :in-report nil))
  :validate (lambda (values)
              (when (and (eq (getf values :role) :family) (null (getf values :birthday)))
                (translate "Family members need a birthday."))))

(defun sample-contacts ()
  "A few contacts to start with."
  (list (make-instance 'contact :name "Ada Lovelace" :email "ada@example.org" :role :colleague
                                :birthday '(1815 12 10) :favourite t)
        (make-instance 'contact :name "Charles Babbage" :email "charles@example.org" :role :colleague
                                :birthday '(1791 12 26))
        (make-instance 'contact :name "Grace Hopper" :email "grace@example.org" :role :friend
                                :website "https://en.wikipedia.org/wiki/Grace_Hopper")))

(defclass contacts-app (component)
  ((contacts :initform (sample-contacts) :accessor contacts)
   (report :reader contacts-report)
   (chooser :initform (make-instance 'language-chooser) :reader contacts-chooser))
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
                                             (translate "view"))
                                           (text " ")
                                           (anchor (:callback (lambda () (edit-contact self contact)))
                                             (translate "edit"))
                                           (text " ")
                                           (anchor (:callback (lambda () (remove-contact self contact)))
                                             (translate "remove")))))))))

(defmethod states ((self contacts-app))
  ;; The list is replaced, never changed in place, so a shallow snapshot
  ;; keeps the back button honest.
  (list self))

(defmethod children ((self contacts-app))
  (list (contacts-chooser self) (contacts-report self)))

(defun edit-contact (app contact)
  "Edit CONTACT with its generated editor."
  (show app (make-editor contact :title (translate "Edit ~A" (slot-value contact 'name)))))

(defun add-contact (app)
  "Ask for a new contact and add it."
  (let ((contact (make-instance 'contact)))
    (show app (make-editor contact :title (translate "New contact") :save-label "Add")
          :on-answer (lambda (added)
                       (when added
                         (setf (contacts app) (append (contacts app) (list added))))))))

(defun remove-contact (app contact)
  "Ask, then remove CONTACT."
  (show app (make-instance 'confirm-dialog
                           :message (translate "Remove ~A?" (slot-value contact 'name)))
        :on-answer (lambda (yes)
                     (when yes (setf (contacts app) (remove contact (contacts app)))))))

(defmethod render ((self contacts-app))
  (render-component (contacts-chooser self))
  (h1 () (translate "Contacts"))
  (p () (anchor (:callback (lambda () (add-contact self))) (translate "Add a contact")))
  (render-component (contacts-report self)))

(define-translations "fr"
  ("Contacts" "Contacts") ("Add a contact" "Ajouter un contact") ("New contact" "Nouveau contact")
  ("Edit ~A" "Modifier ~A") ("Remove ~A?" "Supprimer ~A ?") ("Add" "Ajouter")
  ("view" "voir") ("edit" "modifier") ("remove" "supprimer")
  ("Name" "Nom") ("Email" "E-mail") ("Phone" "Téléphone") ("Role" "Rôle") ("Birthday" "Anniversaire")
  ("Website" "Site web") ("Favourite" "Favori") ("Notes" "Notes")
  ("Friend" "Ami") ("Colleague" "Collègue") ("Family" "Famille") ("Other" "Autre")
  ("Phone numbers are digits, spaces and + ( ) -." "Un numéro de téléphone se compose de chiffres, d'espaces et de + ( ) -.")
  ("Year, month and day, like 1990-04-23." "Année, mois et jour, comme 1990-04-23.")
  ("Family members need a birthday." "Il faut un anniversaire pour la famille."))

(define-translations "de"
  ("Contacts" "Kontakte") ("Add a contact" "Kontakt hinzufügen") ("New contact" "Neuer Kontakt")
  ("Edit ~A" "~A bearbeiten") ("Remove ~A?" "~A entfernen?") ("Add" "Hinzufügen")
  ("view" "ansehen") ("edit" "bearbeiten") ("remove" "entfernen")
  ("Name" "Name") ("Email" "E-Mail") ("Phone" "Telefon") ("Role" "Rolle") ("Birthday" "Geburtstag")
  ("Website" "Website") ("Favourite" "Favorit") ("Notes" "Notizen")
  ("Friend" "Freund") ("Colleague" "Kollege") ("Family" "Familie") ("Other" "Andere")
  ("Phone numbers are digits, spaces and + ( ) -." "Telefonnummern bestehen aus Ziffern, Leerzeichen und + ( ) -.")
  ("Year, month and day, like 1990-04-23." "Jahr, Monat und Tag, etwa 1990-04-23.")
  ("Family members need a birthday." "Familienmitglieder brauchen einen Geburtstag."))
