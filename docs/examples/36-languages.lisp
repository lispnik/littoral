;;;; The examples for languages: translated text, plural forms, numbers and dates.

;;;; Example: littoral:translate littoral:*language*
;;; Source strings are English and are their own keys.  With arguments, the translation is a FORMAT control string for them.  A string with no translation shows as written.  Binding *LANGUAGE* chooses the language whatever the session's.
(let ((*language* "fr"))
  (list (translate "Save")
        (translate "~A is required." "Nom")
        (translate "Feed the otters")))
;; ⇒ ("Enregistrer" "Nom est obligatoire." "Feed the otters")

;;;; Example: littoral:define-translations littoral:translate-plural
;;; An entry is the source string and its translation, or one form per plural form, in the order the language's rule numbers them.  TRANSLATE-PLURAL formats the form for COUNT with COUNT.  French counts zero as singular.
(define-translations "fr"
  ("Your basket" "Votre panier")
  ("~D otter" "~D loutre" "~D loutres"))
;; ⇒ "fr"
(let ((*language* "fr"))
  (list (translate "Your basket")
        (translate-plural 0 "~D otter" "~D otters")
        (translate-plural 2 "~D otter" "~D otters")))
;; ⇒ ("Votre panier" "0 loutre" "2 loutres")
(let ((*language* "en"))
  (list (translate-plural 0 "~D otter" "~D otters")
        (translate-plural 1 "~D otter" "~D otters")))
;; ⇒ ("0 otters" "1 otter")

;;;; Example: littoral:add-translations
;;; DEFINE-TRANSLATIONS's function, for entries made at run time, such as read from a database.  A translation may not call functions with ~/…/.
(add-translations "de" (list (list "Opening hours" "Öffnungszeiten")))
;; ⇒ "de"
(let ((*language* "de")) (translate "Opening hours"))
;; ⇒ "Öffnungszeiten"
(handler-case (add-translations "de" '(("Hi" "~/cl-user::steal/")))
  (error () :refused))
;; ⇒ :REFUSED

;;;; Example: littoral:load-translations
;;; A file of entries, one list per entry, as translators can edit them; it is read, never evaluated.
(let ((file (merge-pathnames "doc-example-es.lisp" (uiop:temporary-directory))))
  (unwind-protect
       (progn
         (with-open-file (out file :direction :output :if-exists :supersede :external-format :utf-8)
           (write-line "(\"Tide tables\" \"Tablas de mareas\")" out)
           (write-line "(\"~D wave\" \"~D ola\" \"~D olas\")" out))
         (load-translations "es" file)
         (let ((*language* "es"))
           (list (translate "Tide tables") (translate-plural 3 "~D wave" "~D waves"))))
    (delete-file file)))
;; ⇒ ("Tablas de mareas" "3 olas")

;;;; Example: littoral:define-language littoral:language-display-name
;;; Describe a language Littoral doesn't know: what it calls itself, its plural rule, separators, months and date format.  Unsupplied details are English's.  A regional code such as "pt-BR" falls back to "pt".
(define-language "pt" :name "Português"
  :decimal "," :group "."
  :months '("janeiro" "fevereiro" "março" "abril" "maio" "junho" "julho"
            "agosto" "setembro" "outubro" "novembro" "dezembro")
  :date (lambda (year month day months)
          (format nil "~D de ~A de ~D" day (nth (1- month) months) year)))
;; ⇒ "pt"
(let ((*language* "pt-BR"))
  (list (language-display-name "pt-BR")
        (localized-number 1234.5)
        (localized-date 2026 3 14)))
;; ⇒ ("Português" "1.234,50" "14 de março de 2026")

;;;; Example: littoral:localized-number
;;; Integers get no decimals unless asked; other numbers two.
(let ((*language* "en"))
  (list (localized-number 1234567) (localized-number -0.5) (localized-number 3 :decimals 1)))
;; ⇒ ("1,234,567" "-0.50" "3.0")
(let ((*language* "de"))
  (localized-number 1234.567))
;; ⇒ "1.234,57"

;;;; Example: littoral:localized-date
(list (let ((*language* "en")) (localized-date 2026 10 7))
      (let ((*language* "de")) (localized-date 2026 10 7))
      (let ((*language* "es")) (localized-date 2026 10 7)))
;; ⇒ ("October 7, 2026" "7. Oktober 2026" "7 de octubre de 2026")

;;;; Example: littoral:set-language littoral:current-language
;;; A session starts in the application's language (or the browser's choice among its :LANGUAGES); SET-LANGUAGE changes it from then on.
(defclass greeter (component) ())
(defmethod render ((self greeter))
  (p () (text (current-language)) ": " (translate "Yes"))
  (anchor (:callback (lambda () (set-language "es"))) "Español"))
(with-fresh-applications (("/greeter" 'greeter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greeter")
    (let ((before (body-text b)))
      (click b "Español")
      (list before (body-text b)))))
;; ⇒ ("en: Yes Español" "es: Sí Español")

;;;; Example: littoral:application-languages littoral:language-chooser
;;; A new session takes the first language the browser's Accept-Language asks for among the application's :LANGUAGE and :LANGUAGES.  A LANGUAGE-CHOOSER links to each, named in itself; the current one is not a link.
(defclass shop (component)
  ((chooser :initform (make-instance 'language-chooser) :reader chooser)))
(defmethod children ((self shop)) (list (chooser self)))
(defmethod render ((self shop))
  (render-component (chooser self))
  (p () (translate "Cancel")))
(with-fresh-applications (("/shop" 'shop :mode :deployment :languages '("fr" "de")))
  (let ((b (make-instance 'browser :headers '(("accept-language" . "de-CH, de;q=0.9")))))
    (visit b "/shop")
    (let ((german (body-text b)))
      (click b "Français")
      (list (application-languages (find-application "/shop"))
            german
            (body-text b)
            (null (find-link b "Français"))))))
;; ⇒ (("fr" "de") "English Français Deutsch Abbrechen" "English Français Deutsch Annuler" T)

;;;; Example: littoral:translate-label
;;; For labels that may be absent: a non-empty string is translated, anything else returned as it is.
(let ((*language* "fr"))
  (list (translate-label "Cancel") (translate-label "") (translate-label nil)))
;; ⇒ ("Annuler" "" NIL)

;;;; Example: littoral:missing-translations
;;; The source strings shown in a language whose catalogue lacks them, for the translators.
(let ((*language* "nl"))
  (translate "Opening hours")
  (translate "~D otter" 2)
  (missing-translations "nl"))
;; ⇒ ("Opening hours" "~D otter")

;;;; Example: littoral:translated-languages littoral:*source-language*
;;; The languages with a catalogue, the source language (which needs none) first.
(let ((languages (translated-languages)))
  (list (first languages) *source-language*
        (not (null (member "fr" languages :test #'string=)))))
;; ⇒ ("en" "en" T)
