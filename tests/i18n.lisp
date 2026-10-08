;;;; i18n.lisp — translations, plural forms, numbers, dates, negotiation

(in-package #:littoral/tests)

(def-suite i18n :in littoral)
(in-suite i18n)

(define-translations "xx"
  ("Hello" "Ahoy")
  ("Hello, ~A!" "Ahoy, ~A!")
  ("~D apple" "~D zero-or-one apple" "~D apples" "~D many apples"))

(define-language "xx" :name "Test speak"
  :plural (lambda (n) (cond ((< n 2) 0) ((< n 5) 1) (t 2))))

(test translate-looks-up-and-falls-back
  (let ((*language* "xx"))
    (is (string= "Ahoy" (translate "Hello")))
    (is (string= "Ahoy, Ada!" (translate "Hello, ~A!" "Ada")))
    (is (string= "Goodbye" (translate "Goodbye")))
    (is (member "Goodbye" (missing-translations "xx") :test #'string=)))
  ;; A regional variant falls back to its language.
  (let ((*language* "xx-YY"))
    (is (string= "Ahoy" (translate "Hello"))))
  ;; The source language needs no catalogue, and nothing is missing from it.
  (let ((*language* "en-GB"))
    (is (string= "Hello" (translate "Hello")))
    (is (null (missing-translations "en-GB"))))
  ;; Without a format argument, tildes are left alone.
  (let ((*language* "fr"))
    (is (string= "100~" (translate "100~")))))

(test plural-forms
  (let ((*language* "en"))
    (is (string= "1 apple" (translate-plural 1 "~D apple" "~D apples")))
    (is (string= "0 apples" (translate-plural 0 "~D apple" "~D apples"))))
  (let ((*language* "xx"))
    (is (string= "1 zero-or-one apple" (translate-plural 1 "~D apple" "~D apples")))
    (is (string= "3 apples" (translate-plural 3 "~D apple" "~D apples")))
    (is (string= "7 many apples" (translate-plural 7 "~D apple" "~D apples"))))
  ;; French counts zero as singular.
  (define-translations "fr" ("~D file" "~D fichier" "~D fichiers"))
  (let ((*language* "fr"))
    (is (string= "0 fichier" (translate-plural 0 "~D file" "~D files")))
    (is (string= "2 fichiers" (translate-plural 2 "~D file" "~D files")))))

(test numbers-and-dates
  (let ((*language* "en"))
    (is (string= "1,234,567" (localized-number 1234567)))
    (is (string= "-1,234.50" (localized-number -1234.5)))
    (is (string= "999" (localized-number 999)))
    (is (string= "0.07" (localized-number 0.07)))
    (is (string= "October 7, 2026" (localized-date 2026 10 7))))
  (let ((*language* "de"))
    (is (string= "1.234,50" (localized-number 1234.5)))
    (is (string= "7. Oktober 2026" (localized-date 2026 10 7))))
  (let ((*language* "fr"))
    (is (string= (format nil "1~C234,5" (code-char #x202F)) (localized-number 1234.5 :decimals 1)))
    (is (string= "7 octobre 2026" (localized-date 2026 10 7))))
  (let ((*language* "es"))
    (is (string= "7 de octubre de 2026" (localized-date 2026 10 7)))))

(test accept-language
  (is (equal '("de-DE" "de" "en") (littoral::parse-accept-language "de-DE,de;q=0.9,en;q=0.5")))
  (is (equal '("fr" "en") (littoral::parse-accept-language "en;q=0.4, fr, *;q=0.1, es;q=0")))
  (is (null (littoral::parse-accept-language nil)))
  (is (string= "de" (littoral::negotiate-language "de-DE,en;q=0.5" '("en" "fr" "de"))))
  (is (string= "pt-BR" (littoral::negotiate-language "pt-PT" '("en" "pt-BR"))))
  (is (string= "en" (littoral::negotiate-language "it, en;q=0.2" '("en" "fr"))))
  (is (null (littoral::negotiate-language "it" '("en" "fr")))))

(test framework-strings-are-translated
  (let ((*language* "fr"))
    (is (string= "Oui" (translate "Yes")))
    (is (string= "Nom est obligatoire." (translate "~A is required." "Nom")))))

(defun translated-keys ()
  "Every literal string Littoral's own code passes to TRANSLATE."
  (let ((keys '()))
    (dolist (file (directory (merge-pathnames "src/**/*.lisp" (asdf:system-source-directory :littoral))))
      (let ((text (uiop:read-file-string file)))
        (loop for start = (search "(translate \"" text) then (search "(translate \"" text :start2 (1+ start))
              while start
              do (pushnew (let ((*read-eval* nil))
                            (read-from-string text t nil :start (+ start (length "(translate "))))
                          keys :test #'string=))
        ;; FIELD-PROBLEM translates its message too.
        (loop for start = (search "(field-problem \"" text) then (search "(field-problem \"" text :start2 (1+ start))
              while start
              do (pushnew (read-from-string text t nil :start (+ start (length "(field-problem ")))
                          keys :test #'string=))))
    keys))

(test catalogues-cover-littoral
  (let ((keys (translated-keys)))
    (is (> (length keys) 50))
    (dolist (language '("fr" "de" "es"))
      (let ((missing (remove-if (lambda (key) (littoral::translation-forms key language)) keys)))
        (is (null missing) "~A lacks ~S" language missing)))))

(test load-translations-reads-without-evaluating
  (uiop:with-temporary-file (:stream out :pathname path :external-format :utf-8)
    (write-string "(\"Tea\" \"Thé\")
(\"Danger\" #.(error \"evaluated\"))" out)
    :close-stream
    (signals error (load-translations "fr" path)))
  (uiop:with-temporary-file (:stream out :pathname path :external-format :utf-8)
    (write-string "(\"Tea\" \"Thé\")" out)
    :close-stream
    (load-translations "fr" path)
    (let ((*language* "fr")) (is (string= "Thé" (translate "Tea"))))))

;;; In an application

(defclass polyglot (component)
  ((chooser :initform (make-instance 'language-chooser) :reader polyglot-chooser)
   (answer :initform nil :accessor polyglot-answer)))

(defmethod children ((self polyglot)) (list (polyglot-chooser self)))

(defmethod render ((self polyglot))
  (render-component (polyglot-chooser self))
  (p (:class "count") (translate-plural 3 "~D item" "~D items"))
  (p (:class "today") (text (localized-date 2026 10 7)))
  (anchor (:callback (lambda () (show self (make-instance 'confirm-dialog :message "Sure?")))) "Ask"))

(test sessions-take-the-browsers-language
  (with-fresh-applications (("/poly" 'polyglot :mode :deployment :languages '("fr" "de")))
    (let ((b (make-instance 'browser :headers '(("accept-language" . "de-CH,de;q=0.9,en;q=0.5")))))
      (visit b "/poly")
      (is (search "<html lang=\"de\"" (browser-html b)))
      (is (has-text-p b "7. Oktober 2026"))
      (click b "Ask")
      (is (has-text-p b "Ja"))
      (is (has-text-p b "Nein")))
    ;; Asking for nothing offered gets the application's language.
    (let ((b (make-instance 'browser :headers '(("accept-language" . "it")))))
      (visit b "/poly")
      (is (search "<html lang=\"en\"" (browser-html b)))
      (is (has-text-p b "October 7, 2026")))))

(test the-chooser-switches-language
  (with-fresh-applications (("/poly" 'polyglot :mode :deployment :languages '("fr" "de")))
    (let ((b (make-instance 'browser)))
      (visit b "/poly")
      (is (has-text-p b "English"))
      (is (null (find-link b "English")))
      (click b "Français")
      (is (search "<html lang=\"fr\"" (browser-html b)))
      (is (has-text-p b "7 octobre 2026"))
      (is (find-link b "English"))
      (click b "Ask")
      (is (has-text-p b "Oui")))))

(test single-language-applications-ignore-the-browser
  (with-fresh-applications (("/poly" 'polyglot :mode :deployment :language "fr"))
    (let ((b (make-instance 'browser :headers '(("accept-language" . "de")))))
      (visit b "/poly")
      (is (search "<html lang=\"fr\"" (browser-html b)))
      (click b "Ask")
      (is (has-text-p b "Oui")))))

(test the-contacts-example-in-german
  (with-fresh-applications (("/contacts" 'littoral-examples:contacts-app :mode :deployment
                                         :languages '("fr" "de")))
    (let ((b (make-instance 'browser :headers '(("accept-language" . "de")))))
      (visit b "/contacts")
      (is (has-text-p b "Kontakte"))
      (is (has-text-p b "Geburtstag"))
      (is (has-text-p b "Kollege"))
      (click b "Kontakt hinzufügen")
      (fill-in b "phone" "call me")
      (press b "Hinzufügen")
      (is (has-text-p b "Name ist erforderlich."))
      (is (has-text-p b "Telefonnummern bestehen aus Ziffern"))
      (is (has-text-p b "Jahr, Monat und Tag")))))

(test validation-messages-in-the-sessions-language
  (with-fresh-applications (("/contacts" 'littoral-examples:contacts-app :mode :deployment :language "fr"))
    (let ((b (make-instance 'browser)))
      (visit b "/contacts")
      (click b "Ajouter un contact")
      (press b "Ajouter")
      (is (has-text-p b "Nom est obligatoire.")))))
