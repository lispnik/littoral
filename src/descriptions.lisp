;;;; descriptions.lisp — describe a model once, get editors, viewers, reports
;;;;
;;;; Littoral's Magritte.  A description lists an object's fields: how to
;;;; read and write each one, what kind of value it holds and what makes a
;;;; value acceptable.  From it come
;;;;
;;;;   (make-editor object)   a form that validates and, on Save, writes back
;;;;   (make-viewer object)   a read-only table
;;;;   (description-columns 'contact)   columns for a REPORT
;;;;   (validate object)      the problems, field by field
;;;;
;;;;   (define-description contact
;;;;     ((name :type :string :required t :max-length 60)
;;;;      (email :type :email :required t)
;;;;      (age :type :integer :min 0 :max 150)
;;;;      (role :type :choice :choices '(:friend :colleague) :labels #'string-capitalize)))
;;;;
;;;; A field reads and writes the slot of its name unless given :ACCESSOR
;;;; (a SETF-able function) or :READER and :WRITER.  Editors work on a copy
;;;; of the values, so Cancel leaves the object untouched.

(in-package #:littoral)

;;; Fields

(defclass field ()
  ((name :initarg :name :reader field-name
         :documentation "The property described, a symbol.")
   (label :initarg :label :reader field-label
          :documentation "The text naming the field on the page, translated when shown.")
   (reader :initarg :reader :reader field-reader)
   (writer :initarg :writer :reader field-writer)
   (required :initarg :required :initform nil :reader field-required-p)
   (default :initarg :default :initform nil :reader field-default)
   (help :initarg :help :initform nil :reader field-help
         :documentation "A line of text shown under the input.")
   (validator :initarg :validate :initform nil :reader field-validator
              :documentation "Function of the parsed value: NIL, or what is wrong.")
   (read-only :initarg :read-only :initform nil :reader field-read-only-p)
   (in-report :initarg :in-report :initform t :reader field-in-report-p)
   (hidden :initarg :hidden :initform nil :reader field-hidden-p
           :documentation "Stored and validated, but never shown: not in editors, viewers or reports."))
  (:documentation "One described property of an object.  Subclasses say how
its values are entered, parsed, shown and checked.  DEFINE-DESCRIPTION makes
them from the options it is given."))

(define-condition field-error (error)
  ((message :initarg :message :reader field-error-message))
  (:report (lambda (condition stream) (write-string (field-error-message condition) stream)))
  (:documentation "Signalled by PARSE-FIELD when input is not a value of the field's kind."))

(defun field-problem (format-control &rest arguments)
  "Signal a FIELD-ERROR whose message is FORMAT-CONTROL, translated, applied
to ARGUMENTS.  For PARSE-FIELD methods rejecting what was typed."
  (error 'field-error :message (apply #'translate format-control arguments)))

(defgeneric parse-field (field string)
  (:documentation "The value STRING, as typed, stands for; NIL for blank.
Signals FIELD-ERROR when STRING is not acceptable input.")
  (:method ((field field) string)
    (let ((trimmed (string-trim " " string)))
      (if (string= trimmed "") nil trimmed))))

(defgeneric format-field (field value)
  (:documentation "VALUE as text, for showing and for an input to start from.")
  (:method ((field field) value)
    (if (null value) "" (princ-to-string value))))

(defgeneric check-field (field value)
  (:documentation "NIL when VALUE suits FIELD, or a sentence saying why not.
Methods should call CALL-NEXT-METHOD to keep the general checks.")
  (:method ((field field) value)
    (cond ((and (field-required-p field) (null value))
           (translate "~A is required." (translate (field-label field))))
          ((and value (field-validator field))
           (funcall (field-validator field) value))
          (t nil))))

(defgeneric field-multipart-p (field)
  (:documentation "True when FIELD's input uploads a file, so its form must be multipart.")
  (:method ((field field)) nil))

(defgeneric render-field-input (field id text callback)
  (:documentation "Write the input for FIELD, with the element id ID, showing
TEXT; CALLBACK receives what is submitted.  Editors, wizards and data grids
call it.")
  (:method ((field field) id text callback)
    (h:text-input (:id id :value text :callback callback
                 :required (field-required-p field)))))

(defgeneric render-field-value (field value)
  (:documentation "Write VALUE for reading, in a viewer or report.")
  (:method ((field field) value)
    (h:text (format-field field value))))

;;; Field kinds

(defclass string-field (field)
  ((max-length :initarg :max-length :initform nil :reader field-max-length)
   (pattern :initarg :pattern :initform nil :reader field-pattern
            :documentation "A regular expression the whole value must match.")
   (pattern-message :initarg :pattern-message :initform nil :reader field-pattern-message))
  (:documentation "A line of text, at most :MAX-LENGTH characters when given.
:PATTERN is a regular expression the whole value must match, and
:PATTERN-MESSAGE the sentence shown when it does not."))

(defun not-in-form-message (field)
  (translate "~A is not in the expected form." (translate (field-label field))))

(defmethod check-field ((field string-field) value)
  (or (call-next-method)
      (cond ((null value) nil)
            ((and (field-max-length field) (> (length value) (field-max-length field)))
             (translate "~A must be at most ~D characters." (translate (field-label field)) (field-max-length field)))
            ((and (field-pattern field)
                  (not (cl-ppcre:scan (format nil "^(?:~A)$" (field-pattern field)) value)))
             (if (field-pattern-message field)
                 (translate (field-pattern-message field))
                 (not-in-form-message field)))
            (t nil))))

(defclass text-field (string-field) ()
  (:documentation "Several lines of text, entered in a text area and shown with
a line break after each."))

(defmethod parse-field ((field text-field) string)
  (if (string= (string-trim '(#\Space #\Newline #\Return #\Tab) string) "")
      nil
      (string-right-trim '(#\Space #\Newline #\Return #\Tab) string)))

(defmethod render-field-input ((field text-field) id text callback)
  (h:text-area (:id id :value text :rows 4 :callback callback)))

(defmethod render-field-value ((field text-field) value)
  (when value
    (dolist (line (cl-ppcre:split "\\n" value))
      (h:text line) (h:br))))

(defclass password-field (string-field) ()
  (:documentation "Text that is never shown: its input starts empty, its value
is written as dots, and viewers, report columns and data grids leave it out.
Left blank in an editor or wizard for an object that has a value, it keeps
that value."))

(defmethod render-field-input ((field password-field) id text callback)
  (declare (ignore text))
  (h:password-input (:id id :callback callback :autocomplete "new-password")))

(defmethod render-field-value ((field password-field) value)
  (when value (h:text "••••••")))

(defclass email-field (string-field) ()
  (:default-initargs :pattern "[^@\\s]+@[^@\\s]+\\.[^@\\s]+")
  (:documentation "An email address: text with one @ and a dot after it."))

(defmethod check-field ((field email-field) value)
  (let ((problem (call-next-method)))
    (if (and problem value (string= problem (not-in-form-message field)))
        (translate "~A must be an email address." (translate (field-label field)))
        problem)))

(defmethod render-field-input ((field email-field) id text callback)
  (emit-tag "input" (list :type "email" :id id :value text
                          :name (register :value callback)
                          :required (field-required-p field))
            nil))

(defclass url-field (string-field) ()
  (:default-initargs :pattern "https?://\\S+")
  (:documentation "An http or https URL, shown as a link."))

(defmethod check-field ((field url-field) value)
  (let ((problem (call-next-method)))
    (if (and problem value (string= problem (not-in-form-message field)))
        (translate "~A must be a web address starting http:// or https://." (translate (field-label field)))
        problem)))

(defmethod render-field-value ((field url-field) value)
  ;; Only http(s), so a stored value cannot become a javascript: link.
  (when value (h:anchor (:href value :rel "noopener") (h:text value))))

(defclass integer-field (field)
  ((min :initarg :min :initform nil :reader field-min)
   (max :initarg :max :initform nil :reader field-max))
  (:documentation "A whole number, between :MIN and :MAX when given."))

(defmethod parse-field ((field integer-field) string)
  (let ((trimmed (string-trim " " string)))
    (cond ((string= trimmed "") nil)
          ((handler-case (parse-integer trimmed) (error () nil)))
          (t (field-problem "~A must be a whole number." (translate (field-label field)))))))

(defmethod check-field ((field integer-field) value)
  (or (call-next-method)
      (cond ((null value) nil)
            ((and (field-min field) (< value (field-min field)))
             (translate "~A must be at least ~D." (translate (field-label field)) (field-min field)))
            ((and (field-max field) (> value (field-max field)))
             (translate "~A must be at most ~D." (translate (field-label field)) (field-max field)))
            (t nil))))

(defmethod render-field-input ((field integer-field) id text callback)
  (emit-tag "input" (list :type "number" :id id :value text :min (field-min field) :max (field-max field)
                          :name (register :value callback) :required (field-required-p field))
            nil))

(defclass boolean-field (field) ()
  (:documentation "Yes or no, entered as a checkbox.  Never required: unchecked
is an answer."))

(defmethod parse-field ((field boolean-field) string)
  (and (member string '("on" "true" "t" "yes") :test #'string-equal) t))

(defmethod format-field ((field boolean-field) value)
  (if value "Yes" "No"))

(defmethod render-field-value ((field boolean-field) value)
  (h:text (translate (format-field field value))))

(defmethod check-field ((field boolean-field) value)
  (and (field-validator field) (funcall (field-validator field) value)))

(defmethod render-field-input ((field boolean-field) id text callback)
  (h:checkbox (:id id :value (string= text "Yes")
             :callback (lambda (on) (funcall callback (if on "on" "off"))))))

(defclass choice-field (field)
  ((choices :initarg :choices :initform '() :reader choices-designator
            :documentation "A list, or a function returning one each time it is needed.")
   (label-function :initarg :labels :initform #'princ-to-string :reader field-labels))
  (:documentation "One of :CHOICES (a list, or a function returning one each
time it is needed), shown through :LABELS (a function of a choice;
PRINC-TO-STRING by default) and entered with a select.  Unless the field is
required, the select offers a blank option too."))

(defun field-choices (field)
  "FIELD's choices now, calling its choices function when it has one."
  (let ((choices (choices-designator field)))
    (if (functionp choices) (funcall choices) choices)))

(defmethod parse-field ((field choice-field) string)
  ;; The input posts the chosen item's position; a choice's label (as
  ;; FORMAT-FIELD writes it, before anything is posted) means it too.
  (let ((index (or (handler-case (parse-integer string) (error () nil))
                   (position string (field-choices field)
                             :key (lambda (c) (format-field field c)) :test #'string=))))
    (cond ((or (null index) (minusp index)) nil)
          ((< index (length (field-choices field))) (nth index (field-choices field)))
          (t (field-problem "~A is not one of the choices." (translate (field-label field)))))))

(defmethod format-field ((field choice-field) value)
  (if (null value) "" (funcall (field-labels field) value)))

(defmethod render-field-input ((field choice-field) id text callback)
  (let ((selected (or (position text (field-choices field)
                                :key (lambda (c) (format-field field c)) :test #'string=)
                      ;; A position, as posted.
                      (let ((index (ignore-errors (parse-integer text))))
                        (and index (< -1 index (length (field-choices field))) index)))))
    (emit-tag "select" (list :id id :name (register :value callback))
              (lambda ()
                (unless (field-required-p field)
                  (emit-tag "option" (list :value "-1" :selected (null selected)) nil))
                (loop for choice in (field-choices field)
                      for index from 0
                      do (let ((choice choice))
                           (emit-tag "option" (list :value index :selected (eql index selected))
                                     (lambda () (h:text (format-field field choice))))))))))

(defclass date-field (field) ()
  (:documentation "A calendar date, held as (YEAR MONTH DAY) and written like
2026-10-06."))

(defmethod parse-field ((field date-field) string)
  (let ((trimmed (string-trim " " string)))
    (if (string= trimmed "")
        nil
        (or (cl-ppcre:register-groups-bind ((#'parse-integer year month day))
                ("^(\\d{4})-(\\d{1,2})-(\\d{1,2})$" trimmed)
              (and (<= 1 month 12)
                   (<= 1 day (days-in-month* year month))
                   (list year month day)))
            (field-problem "~A must be a date, like 2026-10-06." (translate (field-label field)))))))

(defun days-in-month* (year month)
  "The number of days in MONTH of YEAR."
  (if (= month 2)
      (if (and (zerop (mod year 4)) (or (plusp (mod year 100)) (zerop (mod year 400)))) 29 28)
      (nth (1- month) '(31 28 31 30 31 30 31 31 30 31 30 31))))

(defmethod format-field ((field date-field) value)
  (if (null value) "" (format nil "~4,'0D-~2,'0D-~2,'0D" (first value) (second value) (third value))))

(defmethod render-field-input ((field date-field) id text callback)
  (emit-tag "input" (list :type "date" :id id :value text :name (register :value callback)
                          :required (field-required-p field))
            nil))

;;; Times of day: (HOUR MINUTE), written 09:30

(defclass time-field (field) ()
  (:documentation "A time of day, held as (HOUR MINUTE) and written like 09:30;
entered with the browser's time input."))

(defmethod parse-field ((field time-field) string)
  (let ((trimmed (string-trim " " string)))
    (if (string= trimmed "")
        nil
        (or (cl-ppcre:register-groups-bind ((#'parse-integer hour minute))
                ("^(\\d{1,2}):(\\d{2})(?::\\d{2})?$" trimmed)
              (and (<= 0 hour 23) (<= 0 minute 59) (list hour minute)))
            (field-problem "~A must be a time, like 09:30." (translate (field-label field)))))))

(defmethod format-field ((field time-field) value)
  (if (null value) "" (format nil "~2,'0D:~2,'0D" (first value) (second value))))

(defmethod render-field-input ((field time-field) id text callback)
  (emit-tag "input" (list :type "time" :id id :value text :name (register :value callback)
                          :required (field-required-p field))
            nil))

;;; Date ranges: ((Y M D) . (Y M D)), written 2026-10-01/2026-10-07

(defclass date-range-field (field) ()
  (:documentation "Two dates, the first no later than the second, held as
\((YEAR MONTH DAY) . (YEAR MONTH DAY)) and written as an ISO 8601 interval,
2026-10-01/2026-10-07; entered with two date inputs, From and To."))

(defun range-dates (field text)
  "The two date texts of TEXT, split at its slash."
  (declare (ignore field))
  (let ((slash (position #\/ text)))
    (if slash
        (values (string-trim " " (subseq text 0 slash)) (string-trim " " (subseq text (1+ slash))))
        (values (string-trim " " text) ""))))

(defmethod parse-field ((field date-range-field) string)
  (multiple-value-bind (from to) (range-dates field string)
    (cond ((and (string= from "") (string= to "")) nil)
          ((or (string= from "") (string= to ""))
           (field-problem "~A needs both a first and a last day." (translate (field-label field))))
          (t
           (let ((day (make-instance 'date-field :name (field-name field) :label (field-label field))))
             (cons (parse-field day from) (parse-field day to)))))))

(defmethod format-field ((field date-range-field) value)
  (if (null value)
      ""
      (let ((day (make-instance 'date-field :name (field-name field))))
        (format nil "~A/~A" (format-field day (car value)) (format-field day (cdr value))))))

(defmethod check-field ((field date-range-field) value)
  (or (call-next-method)
      (and value
           (let ((from (car value)) (to (cdr value)))
             (when (> (+ (* 10000 (first from)) (* 100 (second from)) (third from))
                      (+ (* 10000 (first to)) (* 100 (second to)) (third to)))
               (translate "~A must not end before it starts." (translate (field-label field))))))))

(defmethod render-field-input ((field date-range-field) id text callback)
  ;; Each input sends its half; together they make the range, whichever
  ;; callback runs last.
  (multiple-value-bind (from to) (range-dates field text)
    (let ((attributes *next-field-attributes*))
      (setf *next-field-attributes* '())
      ;; The first input has ID, so a label for the field names it.
      (emit-tag "span" (list :class "lt-date-range" :role (when (getf attributes :aria-label) "group")
                             :aria-label (getf attributes :aria-label))
                (lambda ()
                  (h:label (:for id) (translate "From"))
                  (let ((*next-field-attributes* (alexandria:remove-from-plist attributes :aria-label)))
                    (emit-tag "input" (list :type "date" :id id :value from
                                            :required (field-required-p field)
                                            :name (register :value (lambda (v) (setf from v)
                                                                     (funcall callback (format nil "~A/~A" from to)))))
                              nil))
                  (h:label (:for (format nil "~A-to" id)) (translate "To"))
                  (emit-tag "input" (list :type "date" :id (format nil "~A-to" id) :value to
                                          :required (field-required-p field)
                                          :name (register :value (lambda (v) (setf to v)
                                                                   (funcall callback (format nil "~A/~A" from to)))))
                            nil))))))

;;; Tags: a list of short texts, typed separated by commas

(defclass tags-field (field)
  ((suggestions :initarg :choices :initform '() :reader tags-suggestions-designator
                :documentation "Texts offered while typing: a list, or a function returning one.")
   (only-suggestions :initarg :only-choices :initform nil :reader tags-only-suggestions-p)
   (max-tags :initarg :max :initform nil :reader tags-max))
  (:documentation "A list of tags, short texts, typed separated by commas
and shown as removable chips once littoral.js has loaded.  :CHOICES (a
list, or a function returning one) are offered while typing; with
:ONLY-CHOICES T no others are accepted.  :MAX caps how many.  Repeats are
dropped, ignoring case."))

(defun tags-suggestions (field)
  (let ((designator (tags-suggestions-designator field)))
    (mapcar #'princ-to-string (if (functionp designator) (funcall designator) designator))))

(defmethod parse-field ((field tags-field) string)
  (let ((tags '()))
    (dolist (part (cl-ppcre:split "," string))
      (let ((tag (string-trim '(#\Space #\Tab #\Newline) part)))
        (unless (or (string= tag "") (member tag tags :test #'string-equal))
          (push tag tags))))
    (nreverse tags)))

(defmethod format-field ((field tags-field) value)
  (format nil "~{~A~^, ~}" value))

(defmethod check-field ((field tags-field) value)
  (or (call-next-method)
      (cond ((and (tags-max field) (> (length value) (tags-max field)))
             (translate "~A can have at most ~D." (translate (field-label field)) (tags-max field)))
            ((and (tags-only-suggestions-p field)
                  (find-if-not (lambda (tag) (member tag (tags-suggestions field) :test #'string-equal)) value))
             (translate "~A can only be ~{~A~^, ~}." (translate (field-label field)) (tags-suggestions field)))
            (t nil))))

(defmethod render-field-input ((field tags-field) id text callback)
  (let ((suggestions (tags-suggestions field)))
    (emit-tag "input" (list :type "text" :id id :value text :name (register :value callback)
                            :required (field-required-p field)
                            :autocomplete "off"
                            :list (and suggestions (format nil "~A-tags" id))
                            :data-lt-tags (translate "Remove ~A")
                            :aria-description (translate "Separate tags with commas."))
              nil)
    (when suggestions
      (emit-tag "datalist" (list :id (format nil "~A-tags" id))
                (lambda ()
                  (dolist (s suggestions)
                    (emit-tag "option" (list :value s) nil)))))))

(defmethod render-field-value ((field tags-field) value)
  (emit-tag "ul" (list :class "lt-tags")
            (lambda ()
              (dolist (tag value)
                (h:li () (h:text tag))))))

(defparameter *field-kinds*
  '((:string . string-field) (:text . text-field) (:password . password-field)
    (:email . email-field) (:url . url-field) (:integer . integer-field)
    (:boolean . boolean-field) (:choice . choice-field) (:date . date-field)
    (:time . time-field) (:date-range . date-range-field) (:tags . tags-field))
  "Alist of keyword → field class name, for :TYPE in DEFINE-DESCRIPTION.
Push your own (KEYWORD . CLASS-NAME).")

;;; Descriptions

(defclass description ()
  ((name :initarg :name :reader description-name)
   (fields :initarg :fields :reader description-fields)
   (validator :initarg :validate :initform nil :reader description-validator
              :documentation "Function of a plist of field values: NIL, or what is wrong with them together.")
   (label :initarg :label :initform nil)
   (plural :initarg :plural :initform nil))
  (:documentation "The fields of a kind of object, in order, as
DEFINE-DESCRIPTION makes them."))

(defun description-label (description)
  "What one of DESCRIPTION's objects is called on a page: its :LABEL, or
its name capitalised, with spaces for hyphens (\"Reading List\")."
  (or (slot-value description 'label)
      (string-capitalize (substitute #\Space #\- (symbol-name (description-name description))))))

(defun description-plural (description)
  "What several of DESCRIPTION's objects are called: its :PLURAL, or the
English plural of its label (\"Shelves\", \"Categories\", \"People\")."
  (or (slot-value description 'plural)
      (english-plural (description-label description))))

(defparameter *irregular-plurals*
  '(("person" . "people") ("child" . "children") ("man" . "men") ("woman" . "women")
    ("mouse" . "mice") ("foot" . "feet") ("tooth" . "teeth") ("datum" . "data")
    ("criterion" . "criteria") ("leaf" . "leaves") ("life" . "lives") ("knife" . "knives")
    ("wife" . "wives") ("thief" . "thieves") ("series" . "series") ("species" . "species"))
  "Singular → plural for the last words ENGLISH-PLURAL doesn't get by rule.")

(defun english-plural (phrase)
  "PHRASE with its last word made plural, keeping its capitalisation."
  (let* ((start (1+ (or (position #\Space phrase :from-end t) -1)))
         (word (subseq phrase start))
         (lower (string-downcase word))
         (n (length lower)))
    (flet ((ends (suffix) (alexandria:ends-with-subseq suffix lower))
           (stem (drop add) (concatenate 'string (subseq word 0 (- (length word) drop)) add)))
      (let ((plural
              (cond ((zerop n) word)
                    ((assoc lower *irregular-plurals* :test #'string=)
                     (let ((irregular (cdr (assoc lower *irregular-plurals* :test #'string=))))
                       (cond ((every #'upper-case-p (remove-if-not #'alpha-char-p word)) (string-upcase irregular))
                             ((upper-case-p (char word 0)) (string-capitalize irregular))
                             (t irregular))))
                    ((or (ends "s") (ends "x") (ends "z") (ends "ch") (ends "sh")) (stem 0 "es"))
                    ((and (ends "y") (> n 1) (not (find (char lower (- n 2)) "aeiou"))) (stem 1 "ies"))
                    ((ends "lf") (stem 1 "ves"))
                    (t (stem 0 "s")))))
        (concatenate 'string (subseq phrase 0 start) plural)))))

(defvar *descriptions* (make-hash-table :test 'eq)
  "Name → DESCRIPTION.")

(defun find-description (designator)
  "The description DESIGNATOR names: DESIGNATOR itself when it is a
DESCRIPTION, the one defined under it when it is a symbol, or else that of
its class.  Signals an error when there is none."
  (cond ((typep designator 'description) designator)
        ((symbolp designator) (or (gethash designator *descriptions*)
                                  (error "No description named ~S." designator)))
        (t (find-description (class-name (class-of designator))))))

(defun make-field (name &rest options &key (type :string) label accessor reader writer
                   &allow-other-keys)
  "A field of kind TYPE for the property NAME, as DEFINE-DESCRIPTION makes them."
  (let ((class (or (cdr (assoc type *field-kinds*))
                   (error "Unknown field type ~S; see *FIELD-KINDS*." type)))
        (reader (or reader (and accessor (fdefinition accessor))
                    (lambda (object) (and (slot-boundp object name) (slot-value object name)))))
        (writer (or writer (and accessor (fdefinition (list 'setf accessor)))
                    (lambda (value object) (setf (slot-value object name) value)))))
    (apply #'make-instance class
           :name name
           :label (or label (string-capitalize (substitute #\Space #\- (symbol-name name))))
           :reader reader :writer writer
           (alexandria:remove-from-plist options :type :label :accessor :reader :writer))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun field-form (field)
    "The MAKE-FIELD form for FIELD, a (PROPERTY &rest OPTIONS) list.
  :ACCESSOR names a function, so it is quoted; the other options are evaluated."
    (destructuring-bind (property &rest options) field
      (let ((accessor (getf options :accessor)))
        `(make-field ',property
                     ,@(when accessor `(:accessor ',accessor))
                     ,@(alexandria:remove-from-plist options :accessor))))))

(defmacro define-description (name fields &key validate label plural)
  "Describe the objects of class NAME, replacing any description of that
name, and return the DESCRIPTION.  Each of FIELDS is (PROPERTY &rest
options).  :TYPE is the field's kind, a keyword in *FIELD-KINDS* (:STRING by
default), and :LABEL its name on the page (by default PROPERTY,
capitalised).  :REQUIRED makes a value necessary; :DEFAULT is the value an
editor starts from when the object has none; :HELP is a line shown under
the input; :VALIDATE is a function of the value returning NIL, or what is
wrong.  :READ-ONLY fields are shown but not edited; :HIDDEN ones are
checked by VALIDATE but never shown; :IN-REPORT NIL leaves a field out of
DESCRIPTION-COLUMNS and data grids.  A field reads and writes the slot named
PROPERTY, unless given :ACCESSOR (the name of a SETF-able function) or
:READER and :WRITER (functions of OBJECT, and of VALUE and OBJECT).  The
field's kind may take more: :MAX-LENGTH, :PATTERN and :PATTERN-MESSAGE for
text, :MIN and :MAX for integers, :CHOICES and :LABELS for choices, and
:CHOICES (offered while typing), :ONLY-CHOICES and :MAX for :TAGS.  :TIME
holds (HOUR MINUTE), :DATE-RANGE two dates as ((Y M D) . (Y M D)), and
:TAGS a list of strings.  The options are evaluated, except :ACCESSOR.

VALIDATE, a function of a plist of the values keyed by keywords, checks
them together: it returns NIL, or what is wrong.

LABEL and PLURAL name one object and several on pages, such as the
admin's; by default they come from NAME (see DESCRIPTION-LABEL and
DESCRIPTION-PLURAL)."
  `(setf (gethash ',name *descriptions*)
         (make-instance 'description
                        :name ',name
                        :validate ,validate
                        :label ,label
                        :plural ,plural
                        :fields (list ,@(mapcar (lambda (field)
                                                  (field-form field))
                                                fields)))))

(defun field-value (field object)
  "FIELD's value in OBJECT, through the field's reader.  SETF writes it
through the field's writer."
  (funcall (field-reader field) object))

(defun (setf field-value) (value field object)
  (funcall (field-writer field) value object)
  value)

(defun find-field (description name)
  "The field of DESCRIPTION (anything FIND-DESCRIPTION takes) for the
property NAME, or NIL."
  (find name (description-fields (find-description description)) :key #'field-name))

(defun validate (object &optional (description object))
  "What is wrong with OBJECT's stored values, by DESCRIPTION (by default its
class's): an alist of (FIELD-NAME . PROBLEM) for the fields that fail
CHECK-FIELD.  When they all pass but the description's own :VALIDATE does
not, ((NIL . PROBLEM)).  NIL when all is well."
  (let* ((description (find-description description))
         (problems (loop for field in (description-fields description)
                         for problem = (check-field field (field-value field object))
                         when problem collect (cons (field-name field) problem))))
    (or problems
        (let ((validator (description-validator description)))
          (when validator
            (let ((problem (funcall validator (description-plist description object))))
              (when problem (list (cons nil problem)))))))))

(defun description-plist (description object)
  "OBJECT's described values as a plist keyed by field name keywords."
  (loop for field in (description-fields (find-description description))
        append (list (intern (symbol-name (field-name field)) :keyword)
                     (field-value field object))))

;;; Editor

(defclass description-editor (component)
  ((object :initarg :object :reader editor-object)
   (description :initarg :description :reader editor-description)
   (title :initarg :title :initform nil :reader editor-title)
   (save-label :initarg :save-label :initform "Save" :reader editor-save-label)
   (write-p :initarg :write :initform t :reader editor-write-p
            :documentation "When NIL, Save answers the values as a plist instead of writing them.")
   (texts :initform (make-hash-table) :reader editor-texts
          :documentation "Field name → the text entered, the editor's memento.")
   (problems :initform '() :accessor editor-problems))
  (:documentation "Edits an object through its description; answers the
object on Save (after writing the values back) and NIL on Cancel.  Make one
with MAKE-EDITOR."))

(defmethod initialize-instance :after ((self description-editor) &key)
  (dolist (field (description-fields (editor-description self)))
    (setf (gethash (field-name field) (editor-texts self))
          (format-field field (or (field-value field (editor-object self))
                                  (field-default field))))))

(defmethod states ((self description-editor))
  (list self (editor-texts self)))

(defun make-editor (object &key (description object) title (save-label "Save") (write t))
  "A DESCRIPTION-EDITOR for OBJECT, described by DESCRIPTION (anything
FIND-DESCRIPTION takes; by default OBJECT's class), headed by TITLE when
given, its submit button labelled SAVE-LABEL (translated).  Save parses and
checks every field that is neither read-only nor hidden, then the
description's own check, and shows the problems beside the inputs; once
they pass it writes the values to OBJECT and answers it.  With WRITE NIL it
leaves OBJECT alone and answers those values as a plist keyed by field name
keywords, for objects shared between sessions that the application changes
under its own lock.  Cancel answers NIL."
  (make-instance 'description-editor :object object :description (find-description description)
                                     :title title :save-label save-label :write write))

(defun kept-password (field object text)
  "True, and the stored value, when FIELD is a password field left blank
(TEXT) on an OBJECT that has one: the input starts empty, so a blank
means \"unchanged\", not \"none\"."
  (when (and (typep field 'password-field) object
             (string= "" (string-trim " " (or text ""))))
    (let ((stored (ignore-errors (field-value field object))))
      (when stored (values t stored)))))

(defun editor-values (editor)
  "Parse every field's text: an alist of (FIELD . VALUE) and an alist of
(FIELD-NAME . PROBLEM)."
  (let ((values '()) (problems '()))
    (dolist (field (description-fields (editor-description editor)))
      (unless (or (field-read-only-p field) (field-hidden-p field))
        (let ((text (gethash (field-name field) (editor-texts editor))))
          (multiple-value-bind (kept stored) (kept-password field (editor-object editor) text)
            (if kept
                (push (cons field stored) values)
                (handler-case
                    (let* ((value (parse-field field text))
                           (problem (check-field field value)))
                      (if problem
                          (push (cons (field-name field) problem) problems)
                          (push (cons field value) values)))
                  (field-error (e) (push (cons (field-name field) (field-error-message e)) problems))))))))
    (values (nreverse values) (nreverse problems))))

(defun save-editor (editor)
  "Validate EDITOR's entries; write them to the object and answer it, or
keep the problems to show."
  (multiple-value-bind (values problems) (editor-values editor)
    (let* ((description (editor-description editor))
           (whole (and (null problems)
                       (description-validator description)
                       (funcall (description-validator description)
                                (loop for field in (description-fields description)
                                      for entry = (assoc field values)
                                      append (list (intern (symbol-name (field-name field)) :keyword)
                                                   (if entry
                                                       (cdr entry)
                                                       (field-value field (editor-object editor)))))))))
      (setf (editor-problems editor)
            (append problems (when whole (list (cons nil whole)))))
      (unless (editor-problems editor)
        (if (editor-write-p editor)
            (progn
              (loop for (field . value) in values
                    do (setf (field-value field (editor-object editor)) value))
              (answer editor (editor-object editor)))
            (answer editor (loop for (field . value) in values
                                 append (list (intern (symbol-name (field-name field)) :keyword)
                                              value))))))))

(defun field-description-ids (field id problem)
  "The ids of the error and help text describing FIELD's input, or NIL."
  (let ((ids (remove nil (list (when problem (format nil "~A-error" id))
                               (when (field-help field) (format nil "~A-help" id))))))
    (when ids (join-strings ids))))

(defmethod breadcrumb-label ((self description-editor))
  (or (editor-title self) (call-next-method)))

(defmethod render ((self description-editor))
  (let ((problems (editor-problems self)))
    (h:div (:class "lt-editor")
      (when (editor-title self) (h:h2 () (h:text (editor-title self))))
      (let ((general (cdr (assoc nil problems))))
        (when general (h:p (:class "lt-validation-error" :role "alert") (h:text general))))
      (h:form (:multipart (some #'field-multipart-p (description-fields (editor-description self))))
        (dolist (field (remove-if #'field-hidden-p (description-fields (editor-description self))))
          (let* ((name (field-name field))
                 (id (string-downcase (symbol-name name)))
                 (problem (cdr (assoc name problems))))
            (h:div (:class (list "lt-field" (when problem "lt-field-invalid")))
              (h:label (:for id) (h:text (translate (field-label field)))
                (when (field-required-p field) (h:span (:class "lt-required" :title (translate "required")) " *")))
              (if (field-read-only-p field)
                  (h:span (:id id :class "lt-read-only")
                    (render-field-value field (field-value field (editor-object self))))
                  (let ((*next-field-attributes* (list :aria-invalid (when problem "true")
                                                       :aria-describedby (field-description-ids field id problem))))
                    (render-field-input field id (gethash name (editor-texts self))
                                        (lambda (text) (setf (gethash name (editor-texts self)) text)))))
              (when problem (h:div (:id (format nil "~A-error" id) :class "lt-validation-error") (h:text problem)))
              (when (field-help field)
                (h:div (:id (format nil "~A-help" id) :class "lt-help") (h:text (translate-label (field-help field))))))))
        (h:div (:class "lt-buttons")
          (h:submit-button (:callback (lambda () (save-editor self))) (h:text (translate (editor-save-label self))))
          (h:cancel-button (:callback (lambda () (answer self nil))) (translate "Cancel")))))))

;;; Viewer and report columns

(defclass description-viewer (component)
  ((object :initarg :object :reader viewer-object)
   (description :initarg :description :reader viewer-description))
  (:documentation "Shows an object's described values in a table, except
password and hidden fields, with a Close link that answers NIL.  Make one
with MAKE-VIEWER."))

(defun make-viewer (object &key (description object))
  "A DESCRIPTION-VIEWER of OBJECT, described by DESCRIPTION (anything
FIND-DESCRIPTION takes; by default OBJECT's class)."
  (make-instance 'description-viewer :object object :description (find-description description)))

(defmethod render ((self description-viewer))
  (h:table (:class "lt-table lt-viewer")
    (dolist (field (description-fields (viewer-description self)))
      (unless (or (typep field 'password-field) (field-hidden-p field))
        (h:tr () (h:th () (h:text (translate (field-label field))))
          (h:td () (render-field-value field (field-value field (viewer-object self))))))))
  (h:p () (h:anchor (:callback (lambda () (answer self))) (translate "Close"))))

(defun description-columns (description &rest names)
  "REPORT columns for DESCRIPTION's fields: those named in NAMES, in that
order, or else every field neither hidden nor :IN-REPORT NIL.  Password
fields are always left out.  Each column writes its value with
RENDER-FIELD-VALUE and sorts by it (dates by their text); integer columns
get the CSS class \"number\"."
  (let ((description (find-description description)))
    (loop for field in (if names
                           (mapcar (lambda (n) (find-field description n)) names)
                           (remove-if-not (lambda (f) (and (field-in-report-p f) (not (field-hidden-p f))))
                                          (description-fields description)))
          unless (typep field 'password-field)
            collect (let ((field field))
                      (column (field-label field)
                              (field-reader field)
                              :class (when (typep field 'integer-field) "number")
                              :sort-key (lambda (row)
                                          (let ((value (field-value field row)))
                                            (if (typep field 'date-field)
                                                (and value (format-field field value))
                                                value)))
                              :render (lambda (row value)
                                        (declare (ignore row))
                                        (render-field-value field value)))))))
