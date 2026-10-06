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
  ((name :initarg :name :reader field-name)
   (label :initarg :label :reader field-label)
   (reader :initarg :reader :reader field-reader)
   (writer :initarg :writer :reader field-writer)
   (required :initarg :required :initform nil :reader field-required-p)
   (default :initarg :default :initform nil :reader field-default)
   (help :initarg :help :initform nil :reader field-help
         :documentation "A line of text shown under the input.")
   (validator :initarg :validate :initform nil :reader field-validator
              :documentation "Function of the parsed value: NIL, or what is wrong.")
   (read-only :initarg :read-only :initform nil :reader field-read-only-p)
   (in-report :initarg :in-report :initform t :reader field-in-report-p))
  (:documentation "One described property of an object.  Subclasses say how
its values are entered, parsed, shown and checked."))

(define-condition field-error (error)
  ((message :initarg :message :reader field-error-message))
  (:report (lambda (condition stream) (write-string (field-error-message condition) stream)))
  (:documentation "Signalled by PARSE-FIELD when input is not a value of the field's kind."))

(defun field-problem (format-control &rest arguments)
  "Signal a FIELD-ERROR with the formatted message."
  (error 'field-error :message (apply #'format nil format-control arguments)))

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
           (format nil "~A is required." (field-label field)))
          ((and value (field-validator field))
           (funcall (field-validator field) value))
          (t nil))))

(defgeneric render-field-input (field id text callback)
  (:documentation "Write the input for FIELD, with DOM id ID, showing TEXT;
CALLBACK receives what is submitted.")
  (:method ((field field) id text callback)
    (text-input (:id id :value text :callback callback
                 :required (field-required-p field)))))

(defgeneric render-field-value (field value)
  (:documentation "Write VALUE for reading, in a viewer or report.")
  (:method ((field field) value)
    (text (format-field field value))))

;;; Field kinds

(defclass string-field (field)
  ((max-length :initarg :max-length :initform nil :reader field-max-length)
   (pattern :initarg :pattern :initform nil :reader field-pattern
            :documentation "A regular expression the whole value must match.")
   (pattern-message :initarg :pattern-message :initform nil :reader field-pattern-message))
  (:documentation "A line of text."))

(defmethod check-field ((field string-field) value)
  (or (call-next-method)
      (cond ((null value) nil)
            ((and (field-max-length field) (> (length value) (field-max-length field)))
             (format nil "~A must be at most ~D characters." (field-label field) (field-max-length field)))
            ((and (field-pattern field)
                  (not (cl-ppcre:scan (format nil "^(?:~A)$" (field-pattern field)) value)))
             (or (field-pattern-message field)
                 (format nil "~A is not in the expected form." (field-label field))))
            (t nil))))

(defclass text-field (string-field) ()
  (:documentation "Several lines of text."))

(defmethod parse-field ((field text-field) string)
  (if (string= (string-trim '(#\Space #\Newline #\Return #\Tab) string) "")
      nil
      (string-right-trim '(#\Space #\Newline #\Return #\Tab) string)))

(defmethod render-field-input ((field text-field) id text callback)
  (text-area (:id id :value text :rows 4 :callback callback)))

(defmethod render-field-value ((field text-field) value)
  (when value
    (dolist (line (cl-ppcre:split "\\n" value))
      (text line) (br))))

(defclass password-field (string-field) ()
  (:documentation "Text that is never shown."))

(defmethod render-field-input ((field password-field) id text callback)
  (declare (ignore text))
  (password-input (:id id :callback callback :autocomplete "new-password")))

(defmethod render-field-value ((field password-field) value)
  (when value (text "••••••")))

(defclass email-field (string-field) ()
  (:default-initargs :pattern "[^@\\s]+@[^@\\s]+\\.[^@\\s]+")
  (:documentation "An email address."))

(defmethod check-field ((field email-field) value)
  (let ((problem (call-next-method)))
    (if (and problem value (cl-ppcre:scan "is not in the expected form" problem))
        (format nil "~A must be an email address." (field-label field))
        problem)))

(defmethod render-field-input ((field email-field) id text callback)
  (emit-tag "input" (list :type "email" :id id :value text
                          :name (register :value callback)
                          :required (field-required-p field))
            nil))

(defclass url-field (string-field) ()
  (:default-initargs :pattern "https?://\\S+")
  (:documentation "An http or https URL."))

(defmethod check-field ((field url-field) value)
  (let ((problem (call-next-method)))
    (if (and problem value (cl-ppcre:scan "is not in the expected form" problem))
        (format nil "~A must be a web address starting http:// or https://." (field-label field))
        problem)))

(defmethod render-field-value ((field url-field) value)
  ;; Only http(s), so a stored value cannot become a javascript: link.
  (when value (anchor (:href value :rel "noopener") (text value))))

(defclass integer-field (field)
  ((min :initarg :min :initform nil :reader field-min)
   (max :initarg :max :initform nil :reader field-max))
  (:documentation "A whole number, optionally between MIN and MAX."))

(defmethod parse-field ((field integer-field) string)
  (let ((trimmed (string-trim " " string)))
    (cond ((string= trimmed "") nil)
          ((handler-case (parse-integer trimmed) (error () nil)))
          (t (field-problem "~A must be a whole number." (field-label field))))))

(defmethod check-field ((field integer-field) value)
  (or (call-next-method)
      (cond ((null value) nil)
            ((and (field-min field) (< value (field-min field)))
             (format nil "~A must be at least ~D." (field-label field) (field-min field)))
            ((and (field-max field) (> value (field-max field)))
             (format nil "~A must be at most ~D." (field-label field) (field-max field)))
            (t nil))))

(defmethod render-field-input ((field integer-field) id text callback)
  (emit-tag "input" (list :type "number" :id id :value text :min (field-min field) :max (field-max field)
                          :name (register :value callback) :required (field-required-p field))
            nil))

(defclass boolean-field (field) ()
  (:documentation "Yes or no.  Never required: unchecked is an answer."))

(defmethod parse-field ((field boolean-field) string)
  (and (member string '("on" "true" "t" "yes") :test #'string-equal) t))

(defmethod format-field ((field boolean-field) value)
  (if value "Yes" "No"))

(defmethod check-field ((field boolean-field) value)
  (and (field-validator field) (funcall (field-validator field) value)))

(defmethod render-field-input ((field boolean-field) id text callback)
  (checkbox (:id id :value (string= text "Yes")
             :callback (lambda (on) (funcall callback (if on "on" "off"))))))

(defclass choice-field (field)
  ((choices :initarg :choices :initform '() :reader choices-designator
            :documentation "A list, or a function returning one each time it is needed.")
   (label-function :initarg :labels :initform #'princ-to-string :reader field-labels))
  (:documentation "One of CHOICES, shown through LABELS."))

(defun field-choices (field)
  "FIELD's choices now."
  (let ((choices (choices-designator field)))
    (if (functionp choices) (funcall choices) choices)))

(defmethod parse-field ((field choice-field) string)
  ;; The input posts the chosen item's position.
  (let ((index (handler-case (parse-integer string) (error () nil))))
    (cond ((or (null index) (minusp index)) nil)
          ((< index (length (field-choices field))) (nth index (field-choices field)))
          (t (field-problem "~A is not one of the choices." (field-label field))))))

(defmethod format-field ((field choice-field) value)
  (if (null value) "" (funcall (field-labels field) value)))

(defmethod render-field-input ((field choice-field) id text callback)
  (let ((selected (position text (field-choices field)
                            :key (lambda (c) (format-field field c)) :test #'string=)))
    (emit-tag "select" (list :id id :name (register :value callback))
              (lambda ()
                (unless (field-required-p field)
                  (emit-tag "option" (list :value "-1" :selected (null selected)) nil))
                (loop for choice in (field-choices field)
                      for index from 0
                      do (let ((choice choice))
                           (emit-tag "option" (list :value index :selected (eql index selected))
                                     (lambda () (text (format-field field choice))))))))))

(defclass date-field (field) ()
  (:documentation "A calendar date, held as (YEAR MONTH DAY)."))

(defmethod parse-field ((field date-field) string)
  (let ((trimmed (string-trim " " string)))
    (if (string= trimmed "")
        nil
        (or (cl-ppcre:register-groups-bind ((#'parse-integer year month day))
                ("^(\\d{4})-(\\d{1,2})-(\\d{1,2})$" trimmed)
              (and (<= 1 month 12)
                   (<= 1 day (days-in-month* year month))
                   (list year month day)))
            (field-problem "~A must be a date, like 2026-10-06." (field-label field))))))

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

(defparameter *field-kinds*
  '((:string . string-field) (:text . text-field) (:password . password-field)
    (:email . email-field) (:url . url-field) (:integer . integer-field)
    (:boolean . boolean-field) (:choice . choice-field) (:date . date-field))
  "Keyword → field class, for :TYPE in DEFINE-DESCRIPTION.  Push your own.")

;;; Descriptions

(defclass description ()
  ((name :initarg :name :reader description-name)
   (fields :initarg :fields :reader description-fields)
   (validator :initarg :validate :initform nil :reader description-validator
              :documentation "Function of a plist of field values: NIL, or what is wrong with them together."))
  (:documentation "The fields of a kind of object, in order."))

(defvar *descriptions* (make-hash-table :test 'eq)
  "Name → DESCRIPTION.")

(defun find-description (designator)
  "The description DESIGNATOR names, or that of DESIGNATOR's class."
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

(defmacro define-description (name fields &key validate)
  "Describe the objects of class NAME: each of FIELDS is (PROPERTY &rest
options), options being :TYPE (see *FIELD-KINDS*), :LABEL, :REQUIRED,
:DEFAULT, :HELP, :VALIDATE, :READ-ONLY, :IN-REPORT, :ACCESSOR or :READER and
:WRITER, and those of the field's kind (:MAX-LENGTH, :PATTERN, :MIN, :MAX,
:CHOICES, :LABELS).  VALIDATE checks the values together."
  `(setf (gethash ',name *descriptions*)
         (make-instance 'description
                        :name ',name
                        :validate ,validate
                        :fields (list ,@(mapcar (lambda (field)
                                                  (destructuring-bind (property &rest options) field
                                                    ;; :ACCESSOR names a function; the rest are evaluated.
                                                    (let ((accessor (getf options :accessor)))
                                                      `(make-field ',property
                                                                   ,@(when accessor `(:accessor ',accessor))
                                                                   ,@(alexandria:remove-from-plist options :accessor)))))
                                                fields)))))

(defun field-value (field object)
  "FIELD's value in OBJECT."
  (funcall (field-reader field) object))

(defun (setf field-value) (value field object)
  (funcall (field-writer field) value object)
  value)

(defun find-field (description name)
  "The field of DESCRIPTION for the property NAME."
  (find name (description-fields (find-description description)) :key #'field-name))

(defun validate (object &optional (description object))
  "Alist of (FIELD-NAME . PROBLEM) for the fields of OBJECT that fail their
checks, then (NIL . PROBLEM) when the values fail the description's own."
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
object on Save (after writing the values back) and NIL on Cancel."))

(defmethod initialize-instance :after ((self description-editor) &key)
  (dolist (field (description-fields (editor-description self)))
    (setf (gethash (field-name field) (editor-texts self))
          (format-field field (or (field-value field (editor-object self))
                                  (field-default field))))))

(defmethod states ((self description-editor))
  (list self (editor-texts self)))

(defun make-editor (object &key (description object) title (save-label "Save") (write t))
  "An editor for OBJECT, described by DESCRIPTION (default: by its class).
On Save it writes the values to OBJECT and answers it; with WRITE NIL it
leaves OBJECT alone and answers the values as a plist keyed by field name
keywords, for objects shared between sessions that the application changes
under its own lock."
  (make-instance 'description-editor :object object :description (find-description description)
                                     :title title :save-label save-label :write write))

(defun editor-values (editor)
  "Parse every field's text: an alist of (FIELD . VALUE) and an alist of
(FIELD-NAME . PROBLEM)."
  (let ((values '()) (problems '()))
    (dolist (field (description-fields (editor-description editor)))
      (unless (field-read-only-p field)
        (handler-case
            (let* ((value (parse-field field (gethash (field-name field) (editor-texts editor))))
                   (problem (check-field field value)))
              (if problem
                  (push (cons (field-name field) problem) problems)
                  (push (cons field value) values)))
          (field-error (e) (push (cons (field-name field) (field-error-message e)) problems)))))
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

(defmethod render ((self description-editor))
  (let ((problems (editor-problems self)))
    (div (:class "lt-editor")
      (when (editor-title self) (h2 () (text (editor-title self))))
      (let ((general (cdr (assoc nil problems))))
        (when general (p (:class "lt-validation-error") (text general))))
      (form ()
        (dolist (field (description-fields (editor-description self)))
          (let* ((name (field-name field))
                 (id (string-downcase (symbol-name name)))
                 (problem (cdr (assoc name problems))))
            (div (:class (list "lt-field" (when problem "lt-field-invalid")))
              (label (:for id) (text (field-label field))
                (when (field-required-p field) (span (:class "lt-required" :title "required") " *")))
              (if (field-read-only-p field)
                  (span (:id id :class "lt-read-only")
                    (render-field-value field (field-value field (editor-object self))))
                  (render-field-input field id (gethash name (editor-texts self))
                                      (lambda (text) (setf (gethash name (editor-texts self)) text))))
              (when problem (div (:class "lt-validation-error") (text problem)))
              (when (field-help field) (div (:class "lt-help") (text (field-help field)))))))
        (div (:class "lt-buttons")
          (submit-button (:callback (lambda () (save-editor self))) (text (editor-save-label self)))
          (cancel-button (:callback (lambda () (answer self nil))) "Cancel"))))))

;;; Viewer and report columns

(defclass description-viewer (component)
  ((object :initarg :object :reader viewer-object)
   (description :initarg :description :reader viewer-description))
  (:documentation "Shows an object's described values; answers on Close."))

(defun make-viewer (object &key (description object))
  "A read-only view of OBJECT, described by DESCRIPTION."
  (make-instance 'description-viewer :object object :description (find-description description)))

(defmethod render ((self description-viewer))
  (table (:class "lt-table lt-viewer")
    (dolist (field (description-fields (viewer-description self)))
      (unless (typep field 'password-field)
        (tr () (th () (text (field-label field)))
          (td () (render-field-value field (field-value field (viewer-object self))))))))
  (p () (anchor (:callback (lambda () (answer self))) "Close")))

(defun description-columns (description &rest names)
  "REPORT columns for DESCRIPTION's fields: those named in NAMES, or every
field shown in reports."
  (let ((description (find-description description)))
    (loop for field in (if names
                           (mapcar (lambda (n) (find-field description n)) names)
                           (remove-if-not #'field-in-report-p (description-fields description)))
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
