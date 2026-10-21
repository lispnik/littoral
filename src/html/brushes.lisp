;;;; brushes.lisp — elements that call back into the session
;;;;
;;;; A :CALLBACK attribute registers a closure for this render; the element
;;;; is written so that a request naming it runs the closure.  Links and
;;;; buttons take thunks; fields take a function of their submitted value.

(in-package #:littoral)

(defun ensure-render-context ()
  "The active render context, or a throwaway one when rendering outside a
request (to a string, in a test)."
  (or *render-context*
      (make-instance 'render-context
                     :callbacks (make-instance 'callback-registry)
                     :action-url "")))

(defun callback-url (id)
  (let ((base (render-action-url (ensure-render-context))))
    (concatenate 'string base (if (find #\? base) "&" "?") id)))

(defun register (kind function)
  (register-callback kind function (render-callbacks (ensure-render-context))))

(defun strip-attributes (attributes &rest keys)
  "ATTRIBUTES without KEYS; a :LABEL becomes the element's aria-label."
  (loop for (key value) on attributes by #'cddr
        unless (member key keys)
          append (if (eq key :label) (list :aria-label value) (list key value))))

;;; Anchors and forms

(defun %anchor (attributes body)
  (let ((callback (getf attributes :callback))
        (href (getf attributes :href)))
    (emit-tag "a"
              (list* :href (cond (callback (callback-url (register :action callback)))
                                 (href href)
                                 ((getf attributes :on-click) "#")
                                 (t nil))
                     (strip-attributes attributes :callback :href))
              body)))

(defmacro h:anchor (&rest arguments)
  "A link.  :CALLBACK is a thunk run when it is followed; :HREF a plain URL.
With neither, an AJAX :ON-CLICK gets the href \"#\".  :LABEL becomes the
aria-label; other attributes are written as given."
  (multiple-value-bind (attributes body) (split-tag-arguments arguments)
    `(%anchor (list ,@attributes) ,(body-thunk body))))

(defun %form (attributes body)
  (let ((default (getf attributes :default-action))
        (multipart (getf attributes :multipart)))
    (emit-tag "form"
              ;; Given attributes replace the ones a form has by default.
              (list* :method (getf attributes :method "post")
                     :action (or (getf attributes :action) (render-action-url (ensure-render-context)))
                     :accept-charset (getf attributes :accept-charset "utf-8")
                     :enctype (getf attributes :enctype (when multipart "multipart/form-data"))
                     ;; The progress bar's name, while littoral.js uploads.
                     :data-lt-uploading (when multipart (translate "Uploading"))
                     (strip-attributes attributes :multipart :default-action
                                       :method :action :accept-charset :enctype))
              (lambda ()
                ;; Always submitted, but run only when no button was.
                (when default
                  (emit-tag "input" (list :type "hidden" :name (register :default default) :value "1") nil))
                (when body (funcall body))))))

(defmacro h:form (&rest arguments)
  "A form posting back to the session.  Its fields' callbacks run before
the action of the button that submitted it.  :DEFAULT-ACTION is a thunk run
when the form is submitted without a button; :MULTIPART T allows FILE-INPUT.
A given :METHOD, :ACTION, :ACCEPT-CHARSET or :ENCTYPE replaces the form's
own: :METHOD \"dialog\" closes the dialog the form is in, with no request."
  (multiple-value-bind (attributes body) (split-tag-arguments arguments)
    `(%form (list ,@attributes) ,(body-thunk body))))

;;; Fields

(defun field-callback-name (attributes &optional (convert #'identity))
  (let ((callback (getf attributes :callback)))
    (when callback
      (register :value (lambda (value) (funcall callback (funcall convert value)))))))

(defun %input (type attributes &optional (convert #'identity))
  (emit-tag "input"
            (list* :type (or (getf attributes :type) type) ; :type "search" makes a search field
                   :name (or (field-callback-name attributes convert) (getf attributes :name))
                   :value (getf attributes :value)
                   (strip-attributes attributes :callback :name :value :type))
            nil))

(defmacro h:text-input (&optional attributes)
  "A text field showing :VALUE.  :CALLBACK receives the submitted string;
without one, the field is named :NAME."
  `(%input "text" (list ,@attributes)))

(defmacro h:password-input (&optional attributes)
  "A password field, empty unless given a :VALUE.  :CALLBACK receives the
submitted string."
  `(%input "password" (list ,@attributes)))

(defun parse-number-or-nil (string)
  (handler-case (let ((n (parse-integer string :junk-allowed nil))) n)
    (error () nil)))

(defmacro h:number-input (&optional attributes)
  "An integer field.  :CALLBACK receives an integer, or NIL when the
submission does not parse."
  `(%input "number" (list ,@attributes) #'parse-number-or-nil))

(defmacro h:hidden-input (&optional attributes)
  "A hidden field.  :CALLBACK receives its :VALUE when the form is submitted."
  `(%input "hidden" (list ,@attributes)))

(defun %text-area (attributes)
  (let ((value (getf attributes :value)))
    (emit-tag "textarea"
              (list* :name (or (field-callback-name attributes) (getf attributes :name))
                     (strip-attributes attributes :callback :name :value))
              (lambda () (when value (h:text value))))))

(defmacro h:text-area (&optional attributes)
  "A multi-line text field showing :VALUE.  :CALLBACK receives the submitted string."
  `(%text-area (list ,@attributes)))

(defun %checkbox (attributes)
  (let ((name (field-callback-name attributes (lambda (value) (string= value "on")))))
    ;; An unchecked box submits nothing, so a hidden twin of the same name
    ;; goes first: the box's own value, when sent, comes last and wins.
    (when name
      (emit-tag "input" (list :type "hidden" :name name :value "off") nil))
    (emit-tag "input"
              (list* :type "checkbox" :name name :value "on"
                     :checked (and (getf attributes :value) t)
                     (strip-attributes attributes :callback :value))
              nil)))

(defmacro h:checkbox (&optional attributes)
  "A checkbox.  :VALUE is its state; :CALLBACK receives T or NIL."
  `(%checkbox (list ,@attributes)))

(defun item-label (attributes item)
  (let ((labeler (getf attributes :labels)))
    (if labeler (funcall labeler item) item)))

(defun item-chooser (attributes)
  "Register a value callback mapping a submitted index back to its item."
  (let ((items (getf attributes :items))
        (callback (getf attributes :callback)))
    (when callback
      (register :value
                (lambda (value)
                  (let ((index (parse-number-or-nil value)))
                    (funcall callback (and index (< -1 index (length items))
                                           (nth index items)))))))))

(defun %select-list (attributes)
  (let ((items (getf attributes :items))
        (selected (getf attributes :selected))
        (test (or (getf attributes :test) #'eql))
        (name (item-chooser attributes)))
    (emit-tag "select"
              (list* :name name (strip-attributes attributes :items :selected :callback :labels :test))
              (lambda ()
                (loop for item in items
                      for index from 0
                      do (emit-tag "option"
                                   (list :value index
                                         :selected (and selected (funcall test item selected)))
                                   (let ((item item))
                                     (lambda () (h:text (item-label attributes item))))))))))

(defmacro h:select-list (&optional attributes)
  "A drop-down of :ITEMS shown through :LABELS (a function, default PRINC).
:CALLBACK receives the chosen item, or NIL when the submission names none;
:SELECTED is the current one, compared with :TEST (default EQL)."
  `(%select-list (list ,@attributes)))

(defun %radio-group (attributes)
  (let ((items (getf attributes :items))
        (selected (getf attributes :selected))
        (test (or (getf attributes :test) #'eql))
        (name (item-chooser attributes)))
    (emit-tag "span"
              (list* :class "lt-radio-group"
                     (strip-attributes attributes :items :selected :callback :labels :test))
              (lambda ()
                (loop for item in items
                      for index from 0
                      do (let ((item item) (index index))
                           (emit-tag "label" nil
                                     (lambda ()
                                       (emit-tag "input"
                                                 (list :type "radio" :name name :value index
                                                       :checked (and selected (funcall test item selected)))
                                                 nil)
                                       (h:text (item-label attributes item))))))))))

(defmacro h:radio-group (&optional attributes)
  "Radio buttons, one per item of :ITEMS; otherwise like SELECT-LIST."
  `(%radio-group (list ,@attributes)))

;;; File upload

(defclass h:uploaded-file ()
  ((filename :initarg :filename :reader h:file-name
             :documentation "The name the browser gave, without directories.")
   (content-type :initarg :content-type :reader h:file-content-type
                 :documentation "The MIME type the browser gave.")
   (contents :initarg :contents :reader h:file-contents
             :documentation "The file's bytes, an (UNSIGNED-BYTE 8) vector."))
  (:documentation "A file submitted through FILE-INPUT."))

(defmethod print-object ((file h:uploaded-file) stream)
  (print-unreadable-object (file stream :type t)
    (format stream "~S ~A ~D bytes" (h:file-name file) (h:file-content-type file)
            (length (h:file-contents file)))))

(defun read-octets (stream)
  (let ((out (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))
        (buffer (make-array 8192 :element-type '(unsigned-byte 8))))
    (loop for n = (read-sequence buffer stream)
          while (plusp n)
          do (loop for i below n do (vector-push-extend (aref buffer i) out)))
    (coerce out '(simple-array (unsigned-byte 8) (*)))))

(defun parse-upload (value)
  "An UPLOADED-FILE from lack's (STREAM FILENAME CONTENT-TYPE), or NIL when
no file was chosen."
  (when (and (consp value) (streamp (first value))
             (second value) (string/= (second value) ""))
    (make-instance 'h:uploaded-file
                   :filename (second value)
                   :content-type (or (third value) "application/octet-stream")
                   :contents (read-octets (first value)))))

(defun %file-input (attributes)
  (let* ((callback (getf attributes :callback))
         (name (when callback
                 (register :value (lambda (value)
                                    (let ((file (parse-upload value)))
                                      (when file (funcall callback file))))))))
    (emit-tag "input"
              (list* :type "file" :name (or name (getf attributes :name))
                     (strip-attributes attributes :callback :name))
              nil)))

(defmacro h:file-input (&optional attributes)
  "A file chooser.  :CALLBACK receives an UPLOADED-FILE, and is not called
when no file was chosen.  The enclosing FORM needs :MULTIPART T."
  `(%file-input (list ,@attributes)))

;;; Buttons

(defun %submit-button (attributes body)
  (let ((callback (getf attributes :callback)))
    (emit-tag "button"
              (list* :type "submit"
                     :name (when callback (register :action callback))
                     :value (when callback "1")
                     (strip-attributes attributes :callback))
              body)))

(defmacro h:submit-button (&rest arguments)
  "A button submitting its form, then running the thunk :CALLBACK."
  (multiple-value-bind (attributes body) (split-tag-arguments arguments)
    `(%submit-button (list ,@attributes) ,(body-thunk body))))

(defun %cancel-button (attributes body)
  (let ((callback (getf attributes :callback)))
    (emit-tag "button"
              (list* :type "submit" :formnovalidate t
                     :name (when callback (register :cancel callback))
                     :value (when callback "1")
                     (strip-attributes attributes :callback))
              body)))

(defmacro h:cancel-button (&rest arguments)
  "A button that runs the thunk :CALLBACK and nothing else: the form's
fields are not applied."
  (multiple-value-bind (attributes body) (split-tag-arguments arguments)
    `(%cancel-button (list ,@attributes) ,(body-thunk body))))

(defmacro h:button (&rest arguments)
  "A button that submits nothing; give it an AJAX :ON-CLICK."
  (multiple-value-bind (attributes body) (split-tag-arguments arguments)
    `(let ((attributes (list ,@attributes)))
       (emit-tag "button" (list* :type (or (getf attributes :type) "button") (strip-attributes attributes :type))
                 ,(body-thunk body)))))
