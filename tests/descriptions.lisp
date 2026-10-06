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
