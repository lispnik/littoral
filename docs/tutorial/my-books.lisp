;;;; my-books.lisp — the reading list kept in a database, one list per reader
;;;;
;;;; Steps 13 to 15 of docs/tutorial.md build this file, as reading-list.lisp
;;;; is built by the steps before; the same tests keep the two in step.

;;; Step 13: keeping the books in a database

(defpackage #:my-books
  (:use #:cl #:littoral)
  (:local-nicknames (#:h #:littoral.html))
  (:export #:my-books #:open-database #:register)
  (:documentation "The tutorial's reading list, kept in a database, one list per reader."))

(in-package #:my-books)

(defclass stored-book (littoral.db:persistent)
  ((title :initarg :title :initform nil :accessor book-title)
   (author :initarg :author :initform nil :accessor book-author)
   (reader :initarg :reader :initform nil :accessor book-reader))
  (:documentation "A book on someone's list, kept in the books table."))

(define-description stored-book
  ((title :required t :max-length 100)
   (author :max-length 60)
   (reader :type :integer :hidden t)))

(littoral.db:define-table stored-book :name "books")

(defun edit-stored-book (list book)
  "Edit a fresh copy of BOOK in place of LIST; save it if the reader does."
  (show list (make-editor (littoral.db:db-reload book) :title (translate "Edit book"))
        :on-answer (lambda (edited)
                     (when edited
                       (littoral.db:db-save edited)))))

(defun remove-stored-book (list book)
  "Ask, then delete BOOK."
  (show list (make-instance 'confirm-dialog
                            :message (translate "Remove ~A?" (book-title book)))
        :on-answer (lambda (yes)
                     (when yes
                       (littoral.db:db-delete (littoral.db:db-reload book))))))

;;; Step 14: users signing in, each with a list of their own

(defclass my-books (littoral.auth:auth-root littoral.auth:restricted component)
  ((new-title :initform "" :accessor new-title))
  (:documentation "The signed-in reader's books, and a form to add one."))

;; The page itself, shown in step 13.
(defmethod render ((self my-books))
  (h:h1 () (translate "My books"))
  (let ((books (shelf-books)))
    (if books
        (h:ul (:class "books")
          (dolist (book books)
            (h:li ()
              (h:strong () (h:text (book-title book)))
              (when (book-author book)
                (h:text " ")
                (h:text (translate "by ~A" (book-author book))))
              (h:text " ")
              (h:anchor (:callback (lambda () (edit-stored-book self book))) (translate "edit"))
              (h:text " ")
              (h:anchor (:callback (lambda () (remove-stored-book self book))) (translate "remove")))))
        (h:p () (h:em () (translate "No books yet.")))))
  (h:form ()
    (h:text-input (:id "new-title" :value (new-title self)
                 :placeholder (translate "Add a title") :label (translate "Title to add")
                 :callback (lambda (v) (setf (new-title self) v))))
    (h:submit-button (:callback (lambda () (add-stored-book self))) (translate "Add"))))

(defun open-database (file)
  "Keep the books, and the users, in the SQLite database FILE."
  (littoral.db:connect-database :sqlite3 :database-name file)
  (littoral.db:create-table 'stored-book)
  (littoral.auth:create-auth-tables))

(defun shelf-books ()
  "The signed-in reader's books, by title."
  (littoral.db:db-select 'stored-book :where "reader = ?"
                                      :params (list (littoral.auth:user-id (littoral.auth:current-user)))
                                      :order-by "title"))

(defun add-stored-book (list)
  "Save the typed title as a new book on the signed-in reader's list."
  (let ((title (string-trim " " (new-title list))))
    (unless (string= title "")
      (littoral.db:db-save (make-instance 'stored-book
                                          :title title
                                          :reader (littoral.auth:user-id (littoral.auth:current-user))))
      (setf (new-title list) ""))))

(defmethod render :before ((self my-books))
  (h:p (:class "who")
    (h:text (translate "Signed in as ~A." (littoral.auth:user-name (littoral.auth:current-user))))
    (h:text " ")
    (littoral.auth:sign-out-link)))

;;; Step 15: another language

(define-translations "fr"
  ("My books" "Mes livres")
  ("by ~A" "de ~A")
  ("edit" "modifier")
  ("remove" "supprimer")
  ("No books yet." "Pas encore de livres.")
  ("Add a title" "Ajouter un titre")
  ("Title to add" "Titre à ajouter")
  ("Add" "Ajouter")
  ("Edit book" "Modifier le livre")
  ("Remove ~A?" "Supprimer ~A ?")
  ("Title" "Titre")
  ("Author" "Auteur")
  ("Signed in as ~A." "Connecté en tant que ~A.")
  ("Sign out" "Se déconnecter"))

(defun register (&key (file "my-books.db") (mode :development))
  "Open the database FILE, then serve the list at /tutorial/my-books, in
English or French as the browser asks, and in French at /tutorial/mes-livres."
  (open-database file)
  (register-application "/tutorial/my-books" 'my-books :mode mode :title "My books" :languages '("fr"))
  (register-application "/tutorial/mes-livres" 'my-books :mode mode :title "Mes livres" :language "fr"))
