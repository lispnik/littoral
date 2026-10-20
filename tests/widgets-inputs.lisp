;;;; widgets-inputs.lisp — sliders, steppers, ratings, colours, multiple choices, new passwords

(in-package #:littoral/tests)

(def-suite widgets-inputs :in littoral)
(in-suite widgets-inputs)

(defun party-saved-text (b)
  "The party example's saved values, as the page lists them."
  (cl-ppcre:register-groups-bind (dl) ("(?s)<dl class=\"party-saved\">(.*?)</dl>" (browser-html b))
    (cl-ppcre:regex-replace-all "\\s+" (strip-tags (cl-ppcre:regex-replace-all "<" dl " <")) " ")))

(defmacro with-party ((b) &body body)
  "The widgets example's Inputs tab, in a browser B."
  `(with-widgets (,b)
     (click ,b "Inputs")
     ,@body))

;;; Sliders and steppers

(test sliders-and-steppers
  (with-party (b)
    (let ((html (browser-html b)))
      (is (search "type=\"range\" id=\"volume\" value=\"40\" min=\"0\" max=\"100\" step=\"5\"" html))
      (is (search "<output id=\"volume-value\" for=\"volume\" class=\"lt-range-value\" aria-hidden=\"true\">40</output>" html))
      (is (search "data-lt-range=\"volume-value\"" html)))
    ;; Without JavaScript, + submits the form and comes back with one more.
    (press b "+")
    (is (search "id=\"guests\" value=\"9\"" (browser-html b)))
    (is (search "Guests 8" (party-saved-text b)) "Not saved yet")
    (press b "−")
    (press b "−")
    (is (search "id=\"guests\" value=\"7\"" (browser-html b)))
    (fill-in b "guests" "30")
    (press b "+")
    (is (search "id=\"guests\" value=\"30\"" (browser-html b)) "Kept within :max")
    (fill-in b "volume" "53")
    (press b "Save")
    (is (has-text-p b "Music volume must go in steps of 5."))
    (fill-in b "volume" "60")
    (press b "Save")
    (is (search "Guests 30 Music volume 60" (party-saved-text b)))))

(test a-slider-left-blank-starts-in-the-middle
  (let ((field (littoral::make-field 'level :type :range :min 10 :max 20 :step 2)))
    (is (search "value=\"14\""
                (h:with-canvas-to-string () (render-field-input field "level" "" (lambda (v) v)))))
    (is (equal "Level must go in steps of 2." (check-field field 13)))
    (is (null (check-field field 12)))
    (is (equal "Level must be at most 20." (check-field field 22)))))

;;; Star ratings

(test star-ratings
  (with-party (b)
    (let ((html (browser-html b)))
      (is (search "<span id=\"rating\" class=\"lt-rating\" role=\"radiogroup\" aria-label=\"Last year&#39;s party\">" html))
      (is (search "id=\"rating-4\" checked" html))
      (is (search "<label for=\"rating-0\" class=\"lt-rating-none\">No rating</label>" html))
      (is (search "<span class=\"lt-visually-hidden\">3 stars</span>" html))
      (is (search "role=\"img\" aria-label=\"4 out of 5\"" html)))
    (fill-in b "rating-2" "2")
    (press b "Save")
    (is (search "role=\"img\" aria-label=\"2 out of 5\">★★<span class=\"lt-stars-empty\">☆☆☆</span>" (browser-html b)))
    (fill-in b "rating-0" "0")
    (press b "Save")
    (is (search "Last year's party Theme colour" (party-saved-text b)) "No rating")))

(test rating-values
  (let ((field (littoral::make-field 'stars :type :rating :max 3 :required t)))
    (is (= 3 (parse-field field "3")))
    (is (null (parse-field field "0")))
    (signals field-error (parse-field field "4"))
    (is (equal "Stars is required." (check-field field nil)))
    (is (not (search "No rating" (h:with-canvas-to-string () (render-field-input field "s" "" (lambda (v) v)))))
        "A required rating has no blank choice")))

;;; Colours

(test colour-codes
  (is (equal "#3366cc" (normalize-color "#36C")))
  (is (equal "#3366cc" (normalize-color "3366CC")))
  (is (null (normalize-color "#12345")))
  (is (null (normalize-color "red")))
  (is (null (normalize-color nil)))
  (let ((field (littoral::make-field 'paint :type :color)))
    (is (equal "#aabbcc" (parse-field field " #abc ")))
    (is (null (parse-field field "")))
    (signals field-error (parse-field field "blue"))))

(test colour-fields
  (with-party (b)
    (let ((html (browser-html b)))
      (is (search "<input type=\"color\" id=\"colour\" value=\"#0e7490\"" html))
      (is (search "class=\"lt-color-code\" value=\"#0e7490\"" html))
      (is (search "<span class=\"lt-swatch\" style=\"background: #0e7490\" aria-hidden=\"true\"></span><code>#0e7490</code>" html)))
    ;; The code typed wins…
    (fill-in b "Colour code" "#36C")
    (press b "Save")
    (is (search "Theme colour #3366cc" (party-saved-text b)))
    ;; …or the colour picked, when the code wasn't touched.
    (fill-in b "colour" "#FF0000")
    (press b "Save")
    (is (search "Theme colour #ff0000" (party-saved-text b)))
    ;; A cleared code is no colour, which the picker alone can't say.
    (fill-in b "Colour code" "")
    (press b "Save")
    (is (search "Theme colour Possible days" (party-saved-text b)))
    (is (search "<input type=\"color\" id=\"colour\" value=\"#000000\"" (browser-html b)))
    (fill-in b "Colour code" "teal")
    (press b "Save")
    (is (has-text-p b "Theme colour must be a colour, like #3366cc."))))

;;; Multiple choices and transfer lists

(test multiple-choice-values
  (let ((field (littoral::make-field 'days :type :multiple-choice :choices '(:mon :tue :wed)
                                           :labels #'string-capitalize :max 2)))
    (is (equal (format nil "Mon~%Wed") (format-field field '(:mon :wed))))
    (is (equal '(:mon :wed) (parse-field field (format nil "Wed~C~%Mon~%~%" #\Return))) "In the choices' order")
    (is (null (parse-field field "")))
    (signals field-error (parse-field field "Thu"))
    (is (equal "Days can have at most 2." (check-field field '(:mon :tue :wed))))
    (is (equal "Mon, Tue" (h:with-canvas-to-string () (render-field-value field '(:mon :tue)))))))

(test multiple-choice-lists
  (with-party (b)
    (let ((html (browser-html b)))
      (is (search "<select id=\"days\" name=" html))
      (is (search "multiple size=\"4\"" html))
      (is (search "<option value=\"1\" selected>Saturday</option>" html))
      ;; A blank twin, so choosing none is posted.
      (is (cl-ppcre:scan "<input type=\"hidden\" name=\"(\\d+)\" value=\"\"><select id=\"days\" name=\"\\1\"" html)))
    (select-options b "days" '("Friday" "Sunday"))
    (press b "Save")
    (is (search "Possible days Friday, Sunday" (party-saved-text b)))
    (select-options b "days" '())
    (press b "Save")
    (is (has-text-p b "Possible days needs at least 1."))))

(defun chosen-options (b id)
  "The labels of the options in the select with id ID."
  (cl-ppcre:register-groups-bind (options) ((format nil "(?s)<select id=\"~A\"[^>]*>(.*?)</select>" id) (browser-html b))
    (let ((labels '()))
      (cl-ppcre:do-register-groups (label) ("<option[^>]*>(.*?)</option>" options)
        (push label labels))
      (nreverse labels))))

(test transfer-lists
  (with-party (b)
    (is (equal '("Ada" "Barbara" "Edsger" "Alan" "Margaret") (chosen-options b "helpers")))
    (is (equal '("Grace") (chosen-options b "helpers-chosen")))
    (is (search "<label for=\"helpers\">Friends</label>" (browser-html b)))
    (is (search "<label for=\"helpers-chosen\">Helping</label>" (browser-html b)))
    (is (search "class=\"lt-transfer\" role=\"group\" aria-label=\"Helpers\"" (browser-html b)))
    ;; Without JavaScript the buttons submit the form and move what's selected.
    (select-options b "helpers" '("Ada" "Alan"))
    (press b "Add")
    (is (equal '("Ada" "Grace" "Alan") (chosen-options b "helpers-chosen")) "In the choices' order")
    (is (equal '("Barbara" "Edsger" "Margaret") (chosen-options b "helpers")))
    (is (search "Helpers Grace" (party-saved-text b)) "Not saved yet")
    (select-options b "helpers-chosen" '("Grace"))
    (press b "Remove")
    (is (equal '("Ada" "Alan") (chosen-options b "helpers-chosen")))
    (press b "Save")
    (is (search "Helpers Ada, Alan" (party-saved-text b)))
    ;; littoral.js moves them in place and leaves the positions chosen in the
    ;; hidden field.
    (let ((name (cl-ppcre:register-groups-bind (name)
                    ("class=\"lt-transfer-value\" value=\"0,4\" name=\"([^\"]+)\"" (browser-html b))
                  name)))
      (is (stringp name))
      (setf (browser-fields b) (acons name "5,2" (remove name (browser-fields b) :key #'car :test #'string=)))
      (press b "Save")
      (is (search "Helpers Barbara, Margaret" (party-saved-text b))))))

;;; New passwords

(test password-strength-estimates
  (is (= 0 (password-strength "")))
  (multiple-value-bind (score hints) (password-strength "password")
    (is (= 0 score))
    (is (equal "This is one of the most common passwords." (first hints))))
  (is (= 0 (password-strength "Password1!")) "A common one dressed up")
  (is (= 0 (password-strength "5unsh1ne")) "Letters written as digits")
  (multiple-value-bind (score hints) (password-strength "aaaaaaaaaaaa")
    (is (= 0 score))
    (is (member "Avoid repeated characters, like aaa." hints :test #'string=)))
  (multiple-value-bind (score hints) (password-strength "abcdefghijk")
    (is (= 0 score))
    (is (member "Avoid sequences, like abc or 123." hints :test #'string=)))
  (is (= 1 (password-strength "elephant")))
  (is (= 3 (password-strength "Tr0ub4dor&3")))
  (multiple-value-bind (score hints) (password-strength "correct horse battery staple")
    (is (= 4 score))
    (is (null hints)))
  ;; The person's own name counts for little.
  (multiple-value-bind (score hints) (password-strength "ada-lovelace-1815" :words '("Ada Lovelace" nil))
    (is (< score (password-strength "ada-lovelace-1815")))
    (is (member "Avoid words from your name or email address." hints :test #'string=)))
  (is (equal "Fair" (password-strength-label 2)))
  (is (equal "Strong" (password-strength-label 9))))

(defun strength-json (b password)
  "The strength meter's verdict on PASSWORD, as littoral.js would ask for it."
  (let ((spec (find-if (lambda (spec) (string= (cdr spec) ""))
                       (field-ajax-specs b "on-input"))))
    (ajax-request b (car spec) (cdr spec) :fields (list (cons "_lt_value" password)))))

(test new-passwords
  (with-party (b)
    (let ((html (browser-html b)))
      (is (search "<input type=\"password\" id=\"password\" autocomplete=\"new-password\"" html))
      (is (search "data-lt-on-input-value=" html))
      (is (search "<div id=\"password-strength\" class=\"lt-strength\" hidden><meter min=\"0\" max=\"4\" low=\"2\" high=\"3\" optimum=\"4\" value=\"0\" aria-label=\"Password strength\"></meter>" html)))
    ;; Asked as it's typed.
    (let ((json (strength-json b "letmein")))
      (is (search "\"score\":0" json))
      (is (search "\"length\":7" json))
      (is (search "Very weak. This is one of the most common passwords." json)))
    (is (search "\"text\":\"Strong.\"" (strength-json b "correct horse battery staple")))
    ;; :MIN-STRENGTH refuses the weak.
    (fill-in b "password" "elephant")
    (press b "Save")
    (is (has-text-p b "Wi-Fi password is too easy to guess. Add another word or two: longer is better."))
    (fill-in b "password" "purple monkey dishwasher")
    (press b "Save")
    (is (search "Wi-Fi password ••••••" (party-saved-text b)))))

;;; Several values under one name

(defclass several-values-page (component)
  ((got :initform :nothing :accessor got))
  (:documentation "A form with a field posting several values."))

(defmethod render ((self several-values-page))
  (h:form ()
    (littoral::emit-tag "select" (list :id "several" :multiple t :name (littoral::register :values (lambda (v) (setf (got self) v))))
              (lambda ()
                (dolist (v '("a" "b" "c")) (littoral::emit-tag "option" (list :value v) (lambda () (h:text v))))))
    (h:submit-button () "Go"))
  (h:p () (h:text (format nil "Got ~S" (got self)))))

(test values-callbacks-get-every-value
  (with-fresh-applications (("/several" 'several-values-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/several")
      (select-options b "several" '("a" "c"))
      (press b "Go")
      (is (has-text-p b "Got (\"\" \"a\" \"c\")")))))
