;;;; descriptions.lisp — generated editors, viewers and validation

(in-package #:littoral/tests)

(def-suite descriptions :in littoral)
(in-suite descriptions)

(test parsing-and-checking
  (let ((d (find-description 'littoral-examples:contact)))
    (flet ((parse (name text) (parse-field (find-field d name) text))
           (check (name value) (check-field (find-field d name) value)))
      (is (null (parse 'littoral-examples::name "   ")))
      (is (string= "Ada" (parse 'littoral-examples::name " Ada ")))
      (is (string= "Name is required." (check 'littoral-examples::name nil)))
      (is (search "at most 60" (check 'littoral-examples::name (make-string 61 :initial-element #\a))))
      (is (search "email address" (check 'littoral-examples::email "nope")))
      (is (null (check 'littoral-examples::email "a@b.co")))
      (is (equal '(2026 2 28) (parse 'littoral-examples::birthday "2026-02-28")))
      (signals field-error (parse 'littoral-examples::birthday "2026-02-30"))
      (signals field-error (parse 'littoral-examples::birthday "yesterday"))
      (is (eq :family (parse 'littoral-examples::role "2")))
      (is (null (parse 'littoral-examples::role "-1")))
      (is (eq t (parse 'littoral-examples::favourite "on")))
      (is (null (parse 'littoral-examples::favourite "off")))
      (is (search "web address" (check 'littoral-examples::website "javascript:alert(1)"))))))

(test integer-fields
  (let ((field (make-instance 'integer-field :name 'age :label "Age" :min 0 :max 150
                                             :reader #'identity :writer #'identity)))
    (is (= 42 (parse-field field " 42 ")))
    (signals field-error (parse-field field "4x"))
    (is (search "at least 0" (check-field field -1)))
    (is (search "at most 150" (check-field field 151)))))

(test validate-objects
  (let ((ok (make-instance 'littoral-examples:contact :name "A" :email "a@b.co"))
        (bad (make-instance 'littoral-examples:contact :email "x")))
    (is (null (validate ok)))
    (is (equal '(littoral-examples::name littoral-examples::email) (mapcar #'car (validate bad))))
    ;; The description's own check runs once the fields pass.
    (setf (slot-value ok 'littoral-examples::role) :family)
    (is (equal '((nil . "Family members need a birthday.")) (validate ok)))))

(test contacts-crud
  (with-fresh-applications (("/contacts" 'littoral-examples:contacts-app :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/contacts")
      (is (has-text-p b "Ada Lovelace"))
      (is (has-text-p b "1815-12-10"))
      ;; Add, with mistakes first.
      (click b "Add a contact")
      (is (has-text-p b "New contact"))
      (fill-in b "email" "not an email")
      (fill-in b "birthday" "1999-13-01")
      (press b "Add")
      (is (has-text-p b "Name is required."))
      (is (has-text-p b "Email must be an email address."))
      (is (has-text-p b "Birthday must be a date"))
      ;; What was typed is kept.
      (is (search "value=\"not an email\"" (browser-html b)))
      (fill-in b "name" "Alan Turing")
      (fill-in b "email" "alan@example.org")
      (fill-in b "birthday" "")
      (select-option b "role" "Family")
      (press b "Add")
      (is (has-text-p b "Family members need a birthday."))
      (fill-in b "birthday" "1912-06-23")
      (press b "Add")
      (is (has-text-p b "Alan Turing"))
      (is (has-text-p b "1912-06-23"))
      ;; Cancel discards edits.
      (click-nth b "edit" 0)
      (fill-in b "name" "Countess Lovelace")
      (press b "Cancel")
      (is (not (has-text-p b "Countess")))
      ;; Save keeps them.
      (click-nth b "edit" 0)
      (fill-in b "name" "Countess Lovelace")
      (press b "Save")
      (is (has-text-p b "Countess Lovelace"))
      ;; The viewer.
      (click-nth b "view" 2)
      (is (has-text-p b "Website"))
      (is (search "href=\"https://en.wikipedia.org/wiki/Grace_Hopper\"" (browser-html b)))
      (click b "Close")
      ;; Sorting comes from the generated columns.
      (click b "Name")
      (is (search "Alan Turing" (page-text b)))
      (is (< (search "Alan Turing" (page-text b)) (search "Charles Babbage" (page-text b))))
      ;; Remove.
      (click-nth b "remove" 0)
      (press b "Yes")
      (is (not (has-text-p b "Alan Turing"))))))

(test editor-backtracks
  (with-fresh-applications (("/contacts" 'littoral-examples:contacts-app :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/contacts")
      (click b "Add a contact")
      (fill-in b "name" "First")
      (press b "Add")                    ; fails: no email
      (let ((page (browser-url b)))
        (fill-in b "name" "Second")
        (press b "Add")
        (back-to b page)
        ;; The entry as that page showed it.
        (is (search "value=\"First\"" (browser-html b)))))))

(defvar *colours* '(:red :green))

(defclass swatch ()
  ((colour :initform nil)
   (title :initform "untitled"))
  (:documentation "Something with a colour chosen from a list that changes."))

(define-description swatch
  ((title :required t)
   (colour :type :choice :choices (lambda () *colours*) :labels #'string-downcase)))

(test dynamic-choices
  (let ((field (find-field 'swatch 'colour)))
    (is (equal '(:red :green) (field-choices field)))
    (let ((*colours* '(:blue)))
      (is (equal '(:blue) (field-choices field)))
      (is (eq :blue (parse-field field "0"))))))

(test editor-without-writing
  (let* ((swatch (make-instance 'swatch))
         (editor (make-editor swatch :write nil))
         (answer :none))
    (show (make-instance 'component) editor :on-answer (lambda (v) (setf answer v)))
    (setf (gethash 'title (littoral::editor-texts editor)) "Sunset"
          (gethash 'colour (littoral::editor-texts editor)) "1")
    (littoral::save-editor editor)
    (is (equal '(:title "Sunset" :colour :green) answer))
    ;; The object itself is untouched.
    (is (string= "untitled" (slot-value swatch 'title)))))

;;; Passwords left blank

(defclass locker ()
  ((owner :initarg :owner :accessor locker-owner)
   (code :initarg :code :initform nil :accessor locker-code)))

(define-description locker
  ((owner :required t)
   (code :type :password :required t)))

(defclass locker-page (component)
  ((locker :initform (make-instance 'locker :owner "ada" :code "1234") :reader page-locker)
   (via :initarg :via :initform :editor :reader page-via)))

(defmethod render ((self locker-page))
  (h:p () "Code: " (h:text (or (locker-code (page-locker self)) "none")))
  (h:anchor (:callback (lambda ()
                       (show self (ecase (page-via self)
                                    (:editor (make-editor (page-locker self)))
                                    (:wizard (make-wizard (page-locker self)
                                                          :steps '(("Owner" owner) ("Code" code))))
                                    (:owner-only (make-wizard (page-locker self) :steps '(("Owner" owner))))))))
    "Edit"))

(defclass editor-locker-page (locker-page) ())
(defclass wizard-locker-page (locker-page) () (:default-initargs :via :wizard))
(defclass owner-locker-page (locker-page) () (:default-initargs :via :owner-only))

(test blank-passwords-are-kept
  (with-fresh-applications (("/locker-e" 'editor-locker-page :mode :deployment)
                            ("/locker-w" 'wizard-locker-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/locker-e")
      (click b "Edit")
      (fill-in b "owner" "grace")
      (press b "Save")
      (is (search "Code: 1234" (body-text b)) "A required password left blank keeps its value")
      (click b "Edit")
      (fill-in b "code" "9876")
      (press b "Save")
      (is (search "Code: 9876" (body-text b)) "A password typed in replaces it"))
    (let ((b (make-instance 'browser)))
      (visit b "/locker-w")
      (click b "Edit")
      (press b "Next")
      (press b "Next")
      (press b "Finish")
      (is (search "Code: 1234" (body-text b)) "The wizard keeps it too"))))

(test wizard-checks-see-every-field
  ;; A whole-object check sees fields the steps leave out, as the editor's does.
  (let ((seen nil))
    (define-description locker
      ((owner :required t)
       (code :type :password))
      :validate (lambda (values) (setf seen (list (getf values :owner) (getf values :code))) nil))
    (unwind-protect
         (with-fresh-applications (("/locker-o" 'owner-locker-page :mode :deployment))
           (let ((b (make-instance 'browser)))
             (visit b "/locker-o")
             (click b "Edit")
             (press b "Next")
             (press b "Finish")
             (is (equal '("ada" "1234") seen))))
      (define-description locker
        ((owner :required t)
         (code :type :password :required t))))))

(test descriptions-name-their-objects
  (is (equal '("Shelves" "Categories" "Days" "Boxes" "Matches" "People" "Reading Lists" "Books" "CHILDREN")
             (mapcar #'english-plural '("Shelf" "Category" "Day" "Box" "Match" "Person" "Reading List"
                                        "Book" "CHILD"))))
  (let ((plain (make-instance 'description :name 'reading-list :fields '()))
        (named (make-instance 'description :name 'cactus :fields '() :label "Cactus" :plural "Cacti")))
    (is (equal '("Reading List" "Reading Lists") (list (description-label plain) (description-plural plain))))
    (is (equal '("Cactus" "Cacti") (list (description-label named) (description-plural named))))))
