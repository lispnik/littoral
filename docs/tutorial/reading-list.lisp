;;;; reading-list.lisp — the application docs/tutorial.md builds
;;;;
;;;; The tutorial quotes this file section by section (the ";;; Step"
;;;; comments), and the test suite runs it, so the two cannot drift apart.

;;; Step 1: a package and a component

(defpackage #:reading-list
  (:use #:cl #:littoral #:littoral.html)
  (:export #:reading-list #:hello #:counter #:register)
  (:documentation "The application the Littoral tutorial builds."))

(in-package #:reading-list)

(defclass hello (component) ()
  (:documentation "The smallest application."))

(defmethod render ((self hello))
  (h1 () "Hello, world"))

;;; Step 2: callbacks and the back button

(defclass counter (component)
  ((count :initform 0 :accessor count-of))
  (:documentation "A number with links that change it."))

(defmethod states ((self counter))
  (list self))

(defmethod render ((self counter))
  (h1 () (text (count-of self)))
  (anchor (:callback (lambda () (incf (count-of self)))) "++")
  (text " ")
  (anchor (:callback (lambda () (decf (count-of self)))) "--"))

;;; Step 3: the model and a form

(defclass book ()
  ((title :initarg :title :initform nil :accessor book-title)
   (author :initarg :author :initform nil :accessor book-author)
   (finished :initarg :finished :initform nil :accessor book-finished-p))
  (:documentation "A book on the list."))

(defvar *finished-channel* (make-channel "finished books")
  "Published whenever anyone finishes a book (step 9).")

(defvar *recently-finished* '()
  "The last few books anyone finished, newest first, shared by every session.")

;;; Step 4: components inside components

(defclass book-row (component updatable)
  ((book :initarg :book :reader row-book)
   (owner :initarg :owner :reader row-list))
  (:documentation "One book on the list, with its controls."))

(defmethod render ((self book-row))
  (let ((book (row-book self)))
    (li (:class (when (book-finished-p book) "finished"))
      ;; Step 8: ticking the box updates this row in place.
      (checkbox (:value (book-finished-p book)
                 :callback (lambda (finished) (setf (book-finished-p book) finished))
                 :on-change (ajax :callback (lambda () (book-changed book)) :update self)))
      (text " ")
      (strong () (text (book-title book)))
      (when (book-author book) (text (format nil " by ~A" (book-author book))))
      (text " ")
      (anchor (:callback (lambda () (edit-book (row-list self) book))) "edit")
      (text " ")
      (anchor (:callback (lambda () (remove-book (row-list self) book))) "remove"))))

;;; Step 5: call and answer (and step 6: descriptions)

(define-description book
  ((title :required t :max-length 100)
   (author :max-length 60)
   (finished :type :boolean :label "Finished")))

(defun edit-book (list book)
  "Edit BOOK in place of LIST."
  (show list (make-editor book :title "Edit book")))

(defun remove-book (list book)
  "Ask, then take BOOK off LIST."
  (show list (make-instance 'confirm-dialog
                            :message (format nil "Remove ~A?" (book-title book)))
        :on-answer (lambda (yes)
                     (when yes
                       (setf (books list) (remove book (books list)))))))

;;; Step 7: a task

(defclass add-book-task (task) ()
  (:documentation "Ask for a book one question at a time."))

(define-flow add-book-task (self)
  (let ((title (request-input self "What is the book called?")))
    (unless (string= (string-trim " " title) "")
      (let ((author (request-input self "Who wrote it? (leave blank if you don't know)")))
        (when (confirm self (format nil "Add ~A to the list?" title))
          (make-instance 'book :title (string-trim " " title)
                               :author (let ((a (string-trim " " author)))
                                         (if (string= a "") nil a))))))))

;;; Step 8: AJAX (search as you type)

(defclass reading-list (component)
  ((books :initform (list (make-instance 'book :title "Structure and Interpretation of Computer Programs"
                                               :author "Abelson and Sussman")
                          (make-instance 'book :title "Paradigms of Artificial Intelligence Programming"
                                               :author "Peter Norvig"))
          :accessor books)
   (new-title :initform "" :accessor new-title)
   (query :initform "" :accessor query)
   (rows :initform (make-hash-table :test 'eq) :reader rows)
   (shelf :reader shelf)
   (ticker :initform (make-instance 'recently-finished) :reader ticker))
  (:documentation "The reading list."))

(defclass shelf (component updatable)
  ((owner :initarg :owner :reader shelf-list))
  (:documentation "The books that match the search."))

(defmethod initialize-instance :after ((self reading-list) &key)
  (setf (slot-value self 'shelf) (make-instance 'shelf :owner self)))

(defmethod states ((self reading-list))
  (list self))

(defun row-for (list book)
  "The BOOK-ROW showing BOOK, made once and kept."
  (or (gethash book (rows list))
      (setf (gethash book (rows list)) (make-instance 'book-row :book book :owner list))))

(defun matching-books (list)
  "LIST's books that match its search."
  (let ((q (string-trim " " (query list))))
    (remove-if-not (lambda (book)
                     (or (string= q "")
                         (search q (book-title book) :test #'char-equal)
                         (and (book-author book) (search q (book-author book) :test #'char-equal))))
                   (books list))))

(defmethod children ((self reading-list))
  (list (ticker self) (shelf self)))

(defmethod children ((self shelf))
  (mapcar (lambda (book) (row-for (shelf-list self) book)) (matching-books (shelf-list self))))

(defmethod render ((self shelf))
  (let ((books (matching-books (shelf-list self))))
    (if books
        (ul (:class "books")
          (dolist (book books)
            (render-component (row-for (shelf-list self) book))))
        (p () (em () "Nothing matches.")))))

(defun add-quickly (list)
  "Add the typed title to LIST."
  (let ((title (string-trim " " (new-title list))))
    (unless (string= title "")
      (setf (books list) (append (books list) (list (make-instance 'book :title title)))
            (new-title list) ""))))

(defun add-with-questions (list)
  "Run the add-a-book task, adding what it answers."
  (show list (make-instance 'add-book-task)
        :on-answer (lambda (book)
                     (when book
                       (setf (books list) (append (books list) (list book)))))))

;;; Step 9: server push

(defun book-changed (book)
  "Note BOOK's new state; tell everyone when it was just finished."
  (when (book-finished-p book)
    (push (book-title book) *recently-finished*)
    (setf *recently-finished* (subseq *recently-finished* 0 (min 5 (length *recently-finished*))))
    (publish *finished-channel*)))

(defclass recently-finished (component updatable) ()
  (:documentation "What everyone has finished lately, kept current by push."))

(defmethod subscriptions ((self recently-finished))
  (list *finished-channel*))

(defmethod render ((self recently-finished))
  (when *recently-finished*
    (p (:class "recent") "Recently finished by readers here: "
      (text (format nil "~{~A~^; ~}" *recently-finished*)))))

(defmethod render ((self reading-list))
  (h1 () "Reading list")
  (render-component (ticker self))
  (p (:class "search")
    (text-input (:id "query" :value (query self) :placeholder "Search"
                 :callback (lambda (v) (setf (query self) v))
                 :on-input (ajax-update (shelf self)))))
  (render-component (shelf self))
  (form ()
    (text-input (:id "new-title" :value (new-title self) :placeholder "Add a title"
                 :callback (lambda (v) (setf (new-title self) v))))
    (submit-button (:callback (lambda () (add-quickly self))) "Add"))
  (p () (anchor (:callback (lambda () (add-with-questions self))) "Add a book, step by step")))

(defmethod style ((self reading-list))
  ".books { list-style: none; padding: 0; } .books li { margin: .3rem 0; }
.books li.finished strong { text-decoration: line-through; color: var(--lt-muted); }
.recent { font-size: .9rem; color: var(--lt-muted); }")

;;; Step 10: shipping

(defun register (&key (mode :development))
  "Serve the tutorial's applications under /tutorial."
  (register-application "/tutorial/hello" 'hello :mode mode)
  (register-application "/tutorial/counter" 'counter :mode mode)
  (register-application "/tutorial/reading-list" 'reading-list :mode mode :title "Reading list"))
