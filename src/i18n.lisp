;;;; i18n.lisp — translated text, plural forms, numbers and dates by language
;;;;
;;;;   (define-translations "fr"
;;;;     ("Save" "Enregistrer")
;;;;     ("~D item" "~D élément" "~D éléments"))      ; plural forms
;;;;
;;;;   (translate "Save")                              ; "Enregistrer" in French
;;;;   (translate-plural n "~D item" "~D items")       ; formats with N
;;;;
;;;; Source strings are English (*SOURCE-LANGUAGE*) and are their own keys;
;;;; a string with no translation shows as written.  The language is the
;;;; session's: chosen from the browser's Accept-Language among the
;;;; application's :LANGUAGES when the session starts, changed with
;;;; SET-LANGUAGE.  Inside a tag body, (translate ...) is written as text,
;;;; like a literal string.

(in-package #:littoral)

(defstruct (language (:constructor %make-language))
  "How a language counts, writes numbers and dates, and what it calls itself."
  code name
  (plural (lambda (n) (if (eql n 1) 0 1)))
  (decimal ".") (group ",")
  (months '("January" "February" "March" "April" "May" "June" "July"
            "August" "September" "October" "November" "December"))
  (date (lambda (year month day months) (format nil "~A ~D, ~D" (nth (1- month) months) day year))))

(defvar *languages* (make-hash-table :test 'equalp)
  "Language code → LANGUAGE.")

(defvar *translations* (make-hash-table :test 'equalp)
  "Language code → hash table of source string → list of forms.")

(defvar *translations-lock* (sb-thread:make-mutex :name "littoral translations"))

(defvar *source-language* "en"
  "The language source strings are written in; it needs no catalogue.")

(defvar *language* nil
  "When bound to a language code, the language to use regardless of the session.")

(defun define-language (code &key name plural decimal group months date)
  "Describe the language CODE (such as \"fr\" or \"pt-BR\"): its NAME in
itself, its PLURAL rule (a function of a count returning the index of the
plural form to use), its DECIMAL and GROUP separators, its MONTHS' names and
its DATE function of (YEAR MONTH DAY MONTHS) returning a string.  Unsupplied
details are English's."
  (let ((language (%make-language :code code :name (or name code))))
    (when plural (setf (language-plural language) plural))
    (when decimal (setf (language-decimal language) decimal))
    (when group (setf (language-group language) group))
    (when months (setf (language-months language) months))
    (when date (setf (language-date language) date))
    (setf (gethash code *languages*) language)
    code))

(defun primary-subtag (code)
  "\"pt\" for \"pt-BR\"."
  (subseq code 0 (position #\- code)))

(defun find-language (code)
  "The LANGUAGE for CODE, or for its primary subtag, or English."
  (or (gethash code *languages*)
      (gethash (primary-subtag code) *languages*)
      (gethash "en" *languages*)))

(defun language-display-name (code)
  "What the language CODE calls itself."
  (let ((language (or (gethash code *languages*) (gethash (primary-subtag code) *languages*))))
    (if language (language-name language) code)))

(defun current-language ()
  "The language this request is answered in: *LANGUAGE*, else the
session's, else the application's."
  (or *language*
      (and *session* (session-property :language *session*))
      (and *application* (application-language *application*))
      *source-language*))

(defun set-language (code &optional (session *session*))
  "From now on, show SESSION in the language CODE."
  (setf (session-property :language session) code))

;;; Catalogues

(defmacro define-translations (language &body entries)
  "Add ENTRIES, unevaluated, to LANGUAGE's catalogue.  Each is (SOURCE FORM
...): one form for plain text, or one per plural form, in the order the
language's plural rule numbers them."
  `(add-translations ,language ',entries))

(defun check-translation (entry)
  "Signal an error unless ENTRY is a list of strings safe to use as FORMAT
control strings: ~/ would call a function named in the text."
  (unless (and (consp entry) (every #'stringp entry) (rest entry))
    (error "A translation is a list of a source string and its forms: ~S" entry))
  (dolist (string (rest entry))
    ;; Past any ~~ (a literal tilde), ~/ with optional parameters and modifiers.
    (when (cl-ppcre:scan "~(?:[0-9,#vV+-]|'.)*[:@]*/" (cl-ppcre:regex-replace-all "~~" string ""))
      (error "Translations may not call functions with ~~/…/: ~S" string))))

(defun add-translations (language entries)
  "Add ENTRIES, a list as DEFINE-TRANSLATIONS takes, to LANGUAGE's catalogue."
  (mapc #'check-translation entries)
  (sb-thread:with-mutex (*translations-lock*)
    (let ((table (or (gethash language *translations*)
                     (setf (gethash language *translations*) (make-hash-table :test 'equal)))))
      (dolist (entry entries)
        (setf (gethash (first entry) table) (rest entry)))))
  language)

(defun load-translations (language pathname)
  "Add the entries read from the file PATHNAME, each a list (SOURCE FORM ...),
to LANGUAGE's catalogue.  Nothing in the file is evaluated."
  (with-open-file (in pathname :external-format :utf-8)
    (with-standard-io-syntax
      (let ((*read-eval* nil))
        (add-translations language
                          (loop for entry = (read in nil in) until (eq entry in) collect entry))))))

(defun translated-languages ()
  "The languages that have a catalogue, with the source language."
  (sb-thread:with-mutex (*translations-lock*)
    (cons *source-language*
          (loop for code being the hash-keys of *translations* collect code))))

(defvar *missing* (make-hash-table :test 'equalp)
  "Language → source strings asked for that its catalogue lacks.")

(defun note-missing (language source)
  (sb-thread:with-mutex (*translations-lock*)
    (pushnew source (gethash language *missing*) :test #'string=)))

(defun missing-translations (language)
  "The source strings shown in LANGUAGE so far that its catalogue lacks;
for translators."
  (sb-thread:with-mutex (*translations-lock*)
    (reverse (gethash language *missing*))))

(defun translation-forms (source language)
  "The forms LANGUAGE's catalogue (or its primary subtag's) gives for SOURCE, or NIL."
  (unless (string-equal (primary-subtag language) (primary-subtag *source-language*))
    (let ((forms (sb-thread:with-mutex (*translations-lock*)
                   (let ((full (gethash language *translations*))
                         (primary (gethash (primary-subtag language) *translations*)))
                     (or (and full (gethash source full))
                         (and primary (gethash source primary)))))))
      (or forms (progn (note-missing language source) nil)))))

(defun translate (source &rest arguments)
  "SOURCE in the current language; with ARGUMENTS, used as a FORMAT control
string for them."
  (let ((text (or (first (translation-forms source (current-language))) source)))
    (if arguments (apply #'format nil text arguments) text)))

(defun translate-plural (count singular plural &rest arguments)
  "The current language's form of SINGULAR (PLURAL in English) for COUNT,
formatted with COUNT and then ARGUMENTS."
  (let* ((language (current-language))
         (forms (translation-forms singular language))
         (text (if forms
                   (let ((index (funcall (language-plural (find-language language)) count)))
                     (nth (min index (1- (length forms))) forms))
                   (if (eql count 1) singular plural))))
    (apply #'format nil text count arguments)))

;;; Numbers and dates

(defun group-digits (digits separator)
  "DIGITS (a string) with SEPARATOR between each group of three from the right."
  (with-output-to-string (out)
    (loop for char across digits
          for left downfrom (length digits)
          do (write-char char out)
             (when (and (> left 1) (zerop (mod (1- left) 3)))
               (write-string separator out)))))

(defun localized-number (number &key (decimals (if (integerp number) 0 2)))
  "NUMBER as the current language writes it, with DECIMALS places."
  (let* ((language (find-language (current-language)))
         (scaled (round (* (abs number) (expt 10 decimals))))
         (whole (floor scaled (expt 10 decimals)))
         (fraction (mod scaled (expt 10 decimals))))
    (format nil "~:[~;-~]~A~:[~;~A~v,'0D~]"
            (and (minusp number) (plusp scaled))
            (group-digits (princ-to-string whole) (language-group language))
            (plusp decimals) (language-decimal language) decimals fraction)))

(defun localized-date (year month day)
  "The date as the current language writes it in full, such as
\"October 7, 2026\" or \"7 octobre 2026\"."
  (let ((language (find-language (current-language))))
    (funcall (language-date language) year month day (language-months language))))

;;; Languages that come with Littoral

(define-language "en" :name "English")

(define-language "fr" :name "Français"
  :plural (lambda (n) (if (< (abs n) 2) 0 1))
  :decimal "," :group (string (code-char #x202F))
  :months '("janvier" "février" "mars" "avril" "mai" "juin" "juillet"
            "août" "septembre" "octobre" "novembre" "décembre")
  :date (lambda (year month day months) (format nil "~D ~A ~D" day (nth (1- month) months) year)))

(define-language "de" :name "Deutsch"
  :decimal "," :group "."
  :months '("Januar" "Februar" "März" "April" "Mai" "Juni" "Juli"
            "August" "September" "Oktober" "November" "Dezember")
  :date (lambda (year month day months) (format nil "~D. ~A ~D" day (nth (1- month) months) year)))

(define-language "es" :name "Español"
  :decimal "," :group "."
  :months '("enero" "febrero" "marzo" "abril" "mayo" "junio" "julio"
            "agosto" "septiembre" "octubre" "noviembre" "diciembre")
  :date (lambda (year month day months) (format nil "~D de ~A de ~D" day (nth (1- month) months) year)))

;;; Choosing a language from the browser's

(defun parse-quality (text)
  "The q-value TEXT (\"0.8\") as a number from 0 to 1; 0 when malformed."
  (cl-ppcre:register-groups-bind (whole fraction) ("^([01])(?:\\.(\\d{0,3}))?$" text)
    (return-from parse-quality
      (min 1 (+ (parse-integer whole)
                (if (plusp (length fraction))
                    (/ (parse-integer fraction) (expt 10 (length fraction)))
                    0)))))
  0)

(defun parse-accept-language (header)
  "The language codes HEADER (an Accept-Language value) names, best first."
  (let ((choices
          (loop for part in (subseq-list (cl-ppcre:split "\\s*,\\s*" (or header "")) 20)
                for (code . parameters) = (cl-ppcre:split "\\s*;\\s*" part)
                for q = (let ((p (find-if (lambda (s) (alexandria:starts-with-subseq "q=" s)) parameters)))
                          (if p (parse-quality (subseq p 2)) 1.0))
                when (and (plusp (length code)) (string/= code "*") (plusp q))
                  collect (cons code q))))
    (mapcar #'car (stable-sort choices #'> :key #'cdr))))

(defun negotiate-language (header offered)
  "The language of OFFERED that HEADER's languages ask for first: for each
in turn, one matching exactly, else one with the same primary subtag.  NIL
when none matches."
  (loop for code in (parse-accept-language header)
        thereis (or (find code offered :test #'string-equal)
                    (find (primary-subtag code) offered
                          :test #'string-equal :key #'primary-subtag))))

(defun translate-label (label)
  "LABEL translated when it is a non-empty string; anything else as it is."
  (if (and (stringp label) (plusp (length label))) (translate label) label))

(defun subseq-list (list n)
  "The first N elements of LIST at most."
  (if (> (length list) n) (subseq list 0 n) list))
