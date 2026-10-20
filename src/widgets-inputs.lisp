;;;; widgets-inputs.lisp — more field kinds: sliders, steppers, ratings,
;;;; colours, multiple choices, transfer lists and new passwords
;;;;
;;;; Each is a kind of field for DEFINE-DESCRIPTION (:RANGE, :STEPPER,
;;;; :RATING, :COLOR, :MULTIPLE-CHOICE, :TRANSFER, :NEW-PASSWORD), so
;;;; editors, wizards and data grids get it, and each works without
;;;; JavaScript: littoral.js only adds to it.

(in-package #:littoral)

;;; Sliders and steppers

(defclass stepped-field (integer-field)
  ((step :initarg :step :initform 1 :reader field-step))
  (:documentation "A whole number that goes in steps of :STEP from :MIN."))

(defmethod check-field ((field stepped-field) value)
  (or (call-next-method)
      (and value (> (field-step field) 1)
           (not (zerop (mod (- value (or (field-min field) 0)) (field-step field))))
           (translate "~A must go in steps of ~D." (translate (field-label field)) (field-step field)))))

(defun clamp-to-field (field n)
  "N, kept within FIELD's :MIN and :MAX."
  (let ((n (if (field-min field) (max n (field-min field)) n)))
    (if (field-max field) (min n (field-max field)) n)))

(defclass range-field (stepped-field) ()
  (:default-initargs :min 0 :max 100)
  (:documentation "A whole number from :MIN to :MAX (0 and 100 by default), in
steps of :STEP, entered with a slider; the number beside it follows the
slider as it moves.  A slider always has a value, so a field left blank
starts from the middle."))

(defmethod render-field-input ((field range-field) id text callback)
  (let* ((low (field-min field)) (high (field-max field))
         (value (or (ignore-errors (parse-integer (string-trim " " text)))
                    (+ low (* (field-step field) (round (- high low) (* 2 (field-step field))))))))
    (h:span (:class "lt-range")
      (emit-tag "input" (list :type "range" :id id :value value :min low :max high :step (field-step field)
                              :name (register :value callback)
                              :data-lt-range (format nil "~A-value" id))
                nil)
      (emit-tag "output" (list :id (format nil "~A-value" id) :for id :class "lt-range-value" :aria-hidden "true")
                (lambda () (h:text value))))))

(defclass stepper-field (stepped-field) ()
  (:documentation "A whole number in a box between − and + buttons, which
change it by :STEP, within :MIN and :MAX.  Without JavaScript the buttons
submit the form, and the page comes back with the number changed."))

(defmethod render-field-input ((field stepper-field) id text callback)
  (let ((typed text))
    (flet ((step-by (delta)
             (lambda ()
               (let ((n (ignore-errors (parse-integer (string-trim " " typed)))))
                 (funcall callback (princ-to-string (clamp-to-field field (if n (+ n delta) (or (field-min field) 0)))))))))
      (h:span (:class "lt-stepper")
        (h:submit-button (:class "lt-stepper-down" :data-lt-step "-1" :formnovalidate t
                        :aria-label (translate "Decrease")
                        :callback (step-by (- (field-step field))))
          "−")
        (emit-tag "input" (list :type "number" :id id :value text :min (field-min field) :max (field-max field)
                                :step (field-step field) :required (field-required-p field)
                                :name (register :value (lambda (v) (setf typed v) (funcall callback v))))
                  nil)
        (h:submit-button (:class "lt-stepper-up" :data-lt-step "1" :formnovalidate t
                        :aria-label (translate "Increase")
                        :callback (step-by (field-step field)))
          "+")))))

;;; Star ratings

(defclass rating-field (field)
  ((stars :initarg :max :initform 5 :reader rating-stars))
  (:documentation "A rating from 1 to :MAX stars (5 by default), held as a
whole number and entered with radio buttons drawn as stars, so it works
without JavaScript.  Unless the field is required, a No rating choice
stands for NIL."))

(defmethod parse-field ((field rating-field) string)
  (let ((trimmed (string-trim " " string)))
    (if (member trimmed '("" "0") :test #'string=)
        nil
        (let ((n (ignore-errors (parse-integer trimmed))))
          (if (and n (<= 1 n (rating-stars field)))
              n
              (field-problem "~A must be from 1 to ~D." (translate (field-label field)) (rating-stars field)))))))

(defmethod render-field-value ((field rating-field) value)
  (when value
    (h:span (:class "lt-stars" :role "img" :aria-label (translate "~D out of ~D" value (rating-stars field)))
      (h:text (make-string value :initial-element #\★))
      (h:span (:class "lt-stars-empty") (h:text (make-string (max 0 (- (rating-stars field) value)) :initial-element #\☆))))))

(defmethod render-field-input ((field rating-field) id text callback)
  ;; The group takes what the editor gives the field's input: the radio
  ;; buttons have labels of their own.
  (let* ((attributes *next-field-attributes*)
         (name (register :value callback))
         (current (or (ignore-errors (parse-integer (string-trim " " text))) 0)))
    (setf *next-field-attributes* '())
    (emit-tag "span" (list* :id id :class "lt-rating" :role "radiogroup"
                            :aria-label (or (getf attributes :aria-label) (translate (field-label field)))
                            (alexandria:remove-from-plist attributes :aria-label))
              (lambda ()
                (flet ((choice (n class label)
                         (let ((input-id (format nil "~A-~D" id n)))
                           (emit-tag "input" (list :type "radio" :name name :value n :id input-id
                                                   :checked (= n current) :required (field-required-p field))
                                     nil)
                           (emit-tag "label" (list :for input-id :class class) label))))
                  ;; No rating comes first, so the stars after the checked
                  ;; one are those left grey (see littoral.css).
                  (unless (field-required-p field)
                    (choice 0 "lt-rating-none" (lambda () (h:text (translate "No rating")))))
                  (loop for n from 1 to (rating-stars field)
                        do (let ((n n))
                             (choice n "lt-rating-star"
                                     (lambda ()
                                       (h:span (:aria-hidden "true") "★")
                                       (h:span (:class "lt-visually-hidden")
                                         (h:text (translate-plural n "~D star" "~D stars"))))))))))))

;;; Colours: "#rrggbb"

(defun normalize-color (string)
  "STRING as a colour code, #rrggbb in lower case, or NIL when it is not
#rgb or #rrggbb (the # may be left out)."
  (let ((code (string-trim " " (or string ""))))
    (when (and (plusp (length code)) (char/= (char code 0) #\#))
      (setf code (concatenate 'string "#" code)))
    (cond ((cl-ppcre:scan "^#[0-9A-Fa-f]{6}$" code) (string-downcase code))
          ((cl-ppcre:scan "^#[0-9A-Fa-f]{3}$" code)
           (string-downcase (format nil "#~{~C~}" (loop for c across (subseq code 1) collect c collect c))))
          (t nil))))

(defclass color-field (field) ()
  (:documentation "A colour, held as its code: text like \"#3366cc\" (#36c
is taken as #3366cc).  It is entered with the browser's colour picker and a
box for the code beside it; clearing the box leaves no colour, which the
picker alone can't."))

(defmethod parse-field ((field color-field) string)
  (let ((trimmed (string-trim " " string)))
    (if (string= trimmed "")
        nil
        (or (normalize-color trimmed)
            (field-problem "~A must be a colour, like #3366cc." (translate (field-label field)))))))

(defmethod render-field-value ((field color-field) value)
  (let ((code (normalize-color value)))
    (when code
      (h:span (:class "lt-swatch" :style (format nil "background: ~A" code) :aria-hidden "true"))
      (h:code () (h:text code)))))

(defmethod render-field-input ((field color-field) id text callback)
  ;; Two inputs, one value: whichever was changed wins.
  (let* ((swatch (or (normalize-color text) "#000000"))
         (picked swatch))
    (h:span (:class "lt-color")
      (emit-tag "input" (list :type "color" :id id :value swatch
                              :name (register :value (lambda (v) (setf picked (string-downcase v)))))
                nil)
      (emit-tag "input" (list :type "text" :class "lt-color-code" :value text :size 8
                              :spellcheck "false" :autocomplete "off" :placeholder "#rrggbb"
                              :aria-label (translate "Colour code") :required (field-required-p field)
                              :name (register :value
                                              (lambda (typed)
                                                (funcall callback
                                                         (if (and (string= (string-trim " " typed) (string-trim " " text))
                                                                  (string/= picked swatch))
                                                             picked
                                                             typed)))))
                nil))))

;;; Multiple choices: a list of some of the choices

(defclass multiple-choice-field (choice-field)
  ((min-chosen :initarg :min :initform nil :reader field-min-chosen)
   (max-chosen :initarg :max :initform nil :reader field-max-chosen))
  (:documentation "Any number of :CHOICES, held as a list in the choices'
order and entered with a list box that takes several (Ctrl- or ⌘-click, or
Shift for a run).  :MIN and :MAX bound how many; :REQUIRED means at least
one.  As text, the chosen labels are written one to a line."))

(defun choice-label (field choice)
  "CHOICE as FIELD shows it."
  (funcall (field-labels field) choice))

(defun chosen-text (field indexes)
  "The text naming the choices of FIELD at INDEXES, in the choices' order."
  (let ((choices (field-choices field)))
    (format nil "~{~A~^~%~}"
            (loop for index in (sort (remove-duplicates (copy-list indexes)) #'<)
                  when (< -1 index (length choices))
                    collect (choice-label field (nth index choices))))))

(defun chosen-indexes (field text)
  "The positions among FIELD's choices of those TEXT names."
  (let ((choices (field-choices field)))
    (loop for line in (cl-ppcre:split "\\r?\\n" (or text ""))
          for index = (position (string-trim " " line) choices
                                :key (lambda (c) (choice-label field c)) :test #'string=)
          when index collect index)))

(defun posted-indexes (field values)
  "The choice positions VALUES, strings as a list box posts them, name."
  (let ((count (length (field-choices field))))
    (loop for v in values
          for index = (ignore-errors (parse-integer v))
          when (and index (< -1 index count)) collect index)))

(defmethod parse-field ((field multiple-choice-field) string)
  (let ((choices (field-choices field)) (chosen '()))
    (dolist (line (cl-ppcre:split "\\r?\\n" string))
      (let ((label (string-trim " " line)))
        (unless (string= label "")
          (let ((index (position label choices :key (lambda (c) (choice-label field c)) :test #'string=)))
            (if index
                (pushnew index chosen)
                (field-problem "~A is not one of the choices." label))))))
    (mapcar (lambda (index) (nth index choices)) (sort chosen #'<))))

(defmethod format-field ((field multiple-choice-field) value)
  (format nil "~{~A~^~%~}" (mapcar (lambda (c) (choice-label field c)) value)))

(defmethod render-field-value ((field multiple-choice-field) value)
  (h:text (format nil "~{~A~^, ~}" (mapcar (lambda (c) (choice-label field c)) value))))

(defmethod check-field ((field multiple-choice-field) value)
  (or (call-next-method)
      (let ((label (translate (field-label field))))
        (cond ((and (field-min-chosen field) (< (length value) (field-min-chosen field)))
               (translate "~A needs at least ~D." label (field-min-chosen field)))
              ((and (field-max-chosen field) (> (length value) (field-max-chosen field)))
               (translate "~A can have at most ~D." label (field-max-chosen field)))
              (t nil)))))

(defun list-box-size (field)
  "How many rows FIELD's list boxes show."
  (max 4 (min 10 (length (field-choices field)))))

(defun render-choice-options (field indexes)
  "Options for the choices of FIELD at INDEXES, each valued by its position."
  (let ((choices (field-choices field)))
    (dolist (index indexes)
      (let ((choice (nth index choices)))
        (emit-tag "option" (list :value index) (lambda () (h:text (choice-label field choice))))))))

(defmethod render-field-input ((field multiple-choice-field) id text callback)
  (let* ((choices (field-choices field))
         (chosen (chosen-indexes field text))
         (name (register :values (lambda (values) (funcall callback (chosen-text field (posted-indexes field values)))))))
    ;; With nothing chosen a list box posts nothing; this blank twin makes
    ;; it post that.
    (emit-tag "input" (list :type "hidden" :name name :value "") nil)
    (emit-tag "select" (list :id id :name name :multiple t :size (list-box-size field)
                             :required (field-required-p field))
              (lambda ()
                (loop for choice in choices
                      for index from 0
                      do (let ((choice choice))
                           (emit-tag "option" (list :value index :selected (and (member index chosen) t))
                                     (lambda () (h:text (choice-label field choice))))))))
    (h:div (:class "lt-help") (translate "Hold Ctrl or ⌘ to choose several."))))

;;; Transfer lists: what's left and what's chosen, side by side

(defclass transfer-field (multiple-choice-field)
  ((available-label :initarg :available-label :initform "Available" :reader transfer-available-label)
   (chosen-label :initarg :chosen-label :initform "Chosen" :reader transfer-chosen-label))
  (:documentation "Like :MULTIPLE-CHOICE, but entered with two lists side
by side, the choices left (:AVAILABLE-LABEL, \"Available\") and those
chosen (:CHOSEN-LABEL, \"Chosen\"), and buttons that move what is selected
from one to the other: for roles, permissions and the like.  littoral.js
moves them in place, and a double click moves one; without it, the
buttons submit the form and the page comes back with them moved."))

(defmethod render-field-input ((field transfer-field) id text callback)
  (let* ((count (length (field-choices field)))
         (chosen (chosen-indexes field text))
         (now chosen)
         (selected-left '()) (selected-right '())
         (left-id id)
         (right-id (format nil "~A-chosen" id)))
    (flet ((save (indexes) (funcall callback (chosen-text field indexes)))
           (list-box (box-id class heading indexes setter)
             (h:div (:class "lt-transfer-list")
               (h:label (:for box-id) (h:text (translate-label heading)))
               (emit-tag "select" (list :id box-id :class class :multiple t :size (list-box-size field)
                                        :name (register :values (lambda (values) (funcall setter (posted-indexes field values)))))
                         (lambda () (render-choice-options field indexes))))))
      (h:div (:class "lt-transfer" :role "group" :aria-label (translate (field-label field)))
        ;; What is chosen, as littoral.js leaves it; the buttons' callbacks
        ;; start from it.
        (emit-tag "input" (list :type "hidden" :class "lt-transfer-value" :value (format nil "~{~D~^,~}" chosen)
                                :name (register :value (lambda (v)
                                                         (setf now (posted-indexes field (cl-ppcre:split "," v)))
                                                         (save now))))
                  nil)
        (list-box left-id "lt-transfer-available" (transfer-available-label field)
                  (loop for index below count unless (member index chosen) collect index)
                  (lambda (indexes) (setf selected-left indexes)))
        (h:div (:class "lt-transfer-buttons")
          (h:submit-button (:data-lt-move "add" :formnovalidate t
                          :callback (lambda () (save (union now selected-left))))
            (translate "Add") (h:span (:aria-hidden "true") " →"))
          (h:submit-button (:data-lt-move "remove" :formnovalidate t
                          :callback (lambda () (save (set-difference now selected-right))))
            (h:span (:aria-hidden "true") "← ") (translate "Remove")))
        (list-box right-id "lt-transfer-chosen" (transfer-chosen-label field) chosen
                  (lambda (indexes) (setf selected-right indexes)))
        (h:span (:class "lt-visually-hidden lt-transfer-status" :role "status"))))))

;;; Password strength

(defparameter *common-passwords*
  '("password" "123456" "12345678" "123456789" "1234567890" "qwerty" "qwertyuiop" "abc123"
    "111111" "123123" "000000" "654321" "letmein" "welcome" "monkey" "dragon" "football"
    "baseball" "iloveyou" "admin" "login" "master" "sunshine" "princess" "shadow" "superman"
    "trustno1" "starwars" "whatever" "hello" "freedom" "secret" "michael" "jennifer"
    "charlie" "computer" "qazwsx" "zaq12wsx" "asdfghjkl" "changeme" "default" "access"
    "mustang" "batman" "hunter" "pokemon" "cookie" "summer" "winter" "flower" "ginger"
    "chocolate" "liverpool" "chelsea" "arsenal" "soccer" "hockey" "killer" "pepper" "jordan"
    "harley" "ranger" "buster" "thomas" "tigger" "robert" "daniel" "andrew" "joshua"
    "matrix" "maggie" "silver" "orange" "banana" "purple" "yellow" "nothing" "internet"
    "samsung" "google" "apple" "linux" "windows" "passport" "blink182" "q1w2e3r4")
  "Passwords too common to be any good, in lower case.  PASSWORD-STRENGTH
rates them, and them with digits or symbols added at either end, as weak as
can be.")

(defun unleet (string)
  "STRING with the digits and symbols often written for letters made letters."
  (map 'string (lambda (c) (case c (#\0 #\o) (#\1 #\i) (#\3 #\e) (#\4 #\a) (#\5 #\s) (#\7 #\t) (#\@ #\a) (#\$ #\s) (otherwise c)))
       string))

(defun common-password-p (password)
  "True when PASSWORD is one of *COMMON-PASSWORDS*, perhaps with digits
written for letters, or digits and symbols added at either end."
  (let ((lower (string-downcase password)))
    (flet ((common-p (text) (member text *common-passwords* :test #'string=))
           (core (text) (string-trim "0123456789!@#$%^&*?.-_+= " text)))
      (or (common-p lower)
          (common-p (unleet lower))
          (let ((core (core lower)))
            (and (>= (length core) 4)
                 (or (common-p core) (common-p (unleet core)))))))))

(defun character-pool (password)
  "How many characters each of PASSWORD's could have been, judging by the
kinds it uses."
  (let ((pool 0))
    (when (find-if #'lower-case-p password) (incf pool 26))
    (when (find-if #'upper-case-p password) (incf pool 26))
    (when (find-if #'digit-char-p password) (incf pool 10))
    (when (find-if (lambda (c) (and (< (char-code c) 128) (not (alphanumericp c)))) password) (incf pool 33))
    (when (find-if (lambda (c) (>= (char-code c) 128)) password) (incf pool 100))
    (max pool 2)))

(defun word-parts (text)
  "The runs of letters and digits in TEXT."
  (let ((parts '()) (start nil))
    (loop for i from 0 to (length text)
          for c = (and (< i (length text)) (char text i))
          do (cond ((and c (alphanumericp c)) (unless start (setf start i)))
                   (start (push (subseq text start i) parts) (setf start nil))
                   (t nil)))
    (nreverse parts)))

(defun password-strength (password &key words)
  "How hard PASSWORD would be to guess, from 0 (very weak) to 4 (strong),
and a list of hints (translated sentences) for doing better.  A rough
estimate, not a promise: common passwords, repeated characters, runs like
abc or 123, and WORDS (such as the person's name and email address) count
for little; length counts for most.  The meter of a :NEW-PASSWORD field
shows it as the password is typed."
  (let* ((length (length password))
         (lower (string-downcase password))
         (hints '())
         (predictable 0) (repeats nil) (runs nil))
    (when (zerop length)
      (return-from password-strength (values 0 '())))
    ;; Characters that follow from those before them barely count.
    (loop for i from 1 below length
          for c = (char-code (char password i))
          for b = (char-code (char password (1- i)))
          do (cond ((= c b)
                    (incf predictable)
                    (when (and (>= i 2) (= b (char-code (char password (- i 2))))) (setf repeats t)))
                   ((and (>= i 2) (member (- c b) '(1 -1))
                         (= (- c b) (- b (char-code (char password (- i 2))))))
                    (incf predictable)
                    (setf runs t))
                   (t nil)))
    (let ((found-words
            (loop for word in (loop for text in (if (functionp words) (funcall words) words)
                                    when text
                                      append (word-parts (string-downcase text)))
                  when (and (>= (length word) 3) (search word lower))
                    collect word)))
      (let* ((effective (max 1 (- length predictable
                                  (reduce #'+ found-words :key (lambda (w) (1- (length w)))))))
             (common (common-password-p password))
             (bits (if common 0 (* effective (log (character-pool password) 2))))
             (score (cond ((< bits 28) 0) ((< bits 40) 1) ((< bits 56) 2) ((< bits 80) 3) (t 4))))
        (when common (push (translate "This is one of the most common passwords.") hints))
        (when found-words (push (translate "Avoid words from your name or email address.") hints))
        (when repeats (push (translate "Avoid repeated characters, like aaa.") hints))
        (when runs (push (translate "Avoid sequences, like abc or 123.") hints))
        (when (and (< score 3) (not common))
          (push (translate "Add another word or two: longer is better.") hints))
        (values score (nreverse hints))))))

(defun password-strength-label (score)
  "The word for a PASSWORD-STRENGTH score, translated."
  (translate (nth (max 0 (min 4 score)) '("Very weak" "Weak" "Fair" "Good" "Strong"))))

(defun strength-verdict (password words)
  "What a strength meter shows for PASSWORD, as JSON for littoral.js."
  (multiple-value-bind (score hints) (password-strength password :words words)
    (list :score score
          :length (length password)
          :text (format nil "~A.~{ ~A~}" (password-strength-label score) hints))))

(defun render-new-password-input (id callback &key required words)
  "Write a password input with the element id ID, for choosing a new
password, and a strength meter beneath it.  CALLBACK receives what is
submitted.  As the password is typed, littoral.js asks the server for its
PASSWORD-STRENGTH, with WORDS (a list of texts, or a function returning
one, such as the person's name and email address), and shows the verdict;
without JavaScript, the meter stays hidden."
  (emit-tag "input" (list :type "password" :id id :autocomplete "new-password" :required required
                          :name (register :value callback)
                          :on-input (ajax :callback (lambda (password) (strength-verdict password words))
                                          :value "this.value"
                                          :on-complete "littoral.strength(this, value)"))
            nil)
  (h:div (:id (format nil "~A-strength" id) :class "lt-strength" :hidden t)
    (emit-tag "meter" (list :min 0 :max 4 :low 2 :high 3 :optimum 4 :value 0
                            :aria-label (translate "Password strength"))
              nil)
    (h:span (:class "lt-strength-text" :aria-live "polite"))))

(defclass new-password-field (password-field)
  ((min-strength :initarg :min-strength :initform nil :reader field-min-strength
                 :documentation "The least PASSWORD-STRENGTH score accepted, or NIL for any."))
  (:documentation "A password being chosen: a password field with a meter
beneath it that littoral.js keeps up to date as it is typed, from
PASSWORD-STRENGTH on the server.  With :MIN-STRENGTH (0 to 4), weaker
passwords are refused."))

(defmethod check-field ((field new-password-field) value)
  (or (call-next-method)
      (and value (field-min-strength field)
           (multiple-value-bind (score hints) (password-strength value)
             (when (< score (field-min-strength field))
               (format nil "~A~@[ ~A~]"
                       (translate "~A is too easy to guess." (translate (field-label field)))
                       (first hints)))))))

(defmethod render-field-input ((field new-password-field) id text callback)
  (declare (ignore text))
  (render-new-password-input id callback :required (field-required-p field)))

(dolist (kind '((:range . range-field) (:stepper . stepper-field) (:rating . rating-field)
                (:color . color-field) (:multiple-choice . multiple-choice-field)
                (:transfer . transfer-field) (:new-password . new-password-field)))
  (setf *field-kinds* (cons kind (remove (first kind) *field-kinds* :key #'car))))
