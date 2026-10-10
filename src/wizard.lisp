;;;; wizard.lisp — a description's fields, a few at a time
;;;;
;;;;   (call self (make-wizard (make-instance 'signup)
;;;;                           :steps '(("Account" name email) ("About you" birthday plan))))
;;;;
;;;; Each step shows some fields; Next checks them before moving on, Back
;;;; keeps what was typed.  The last step shows everything for a final look,
;;;; with links back to each step; Finish runs the description's own check,
;;;; then writes the values to the object and answers it (or, with :WRITE
;;;; NIL, answers them as a plist).  Cancel answers NIL.

(in-package #:littoral)

(defclass wizard (component)
  ((object :initarg :object :reader wizard-object)
   (description :initarg :description :reader wizard-description)
   (steps :initarg :steps :reader wizard-steps :documentation "(TITLE FIELD-NAME …) for each step.")
   (title :initarg :title :initform nil :reader wizard-title)
   (write-p :initarg :write :initform t :reader wizard-write-p)
   (step :initform 0 :accessor wizard-step :documentation "The step shown; the number of steps for the review.")
   (texts :initform '() :accessor wizard-texts :documentation "(FIELD-NAME . TEXT), replaced, never changed.")
   (problems :initform '() :accessor wizard-problems))
  (:documentation "A description's fields in steps, with a review before finishing."))

(defmethod states ((self wizard)) (list self))

(defun make-wizard (object &key (description object) steps title (write t))
  "A wizard for OBJECT, described by DESCRIPTION, in STEPS: (TITLE FIELD-NAME …)
lists.  Without STEPS, one step per field not hidden."
  (let* ((description (find-description description))
         (shown (remove-if #'field-hidden-p (description-fields description)))
         (wizard (make-instance 'wizard :object object :description description :title title :write write
                                        :steps (or steps (mapcar (lambda (f) (list (field-label f) (field-name f))) shown)))))
    (setf (wizard-texts wizard)
          (mapcar (lambda (field) (cons (field-name field)
                                        (format-field field (or (field-value field object) (field-default field)))))
                  shown))
    wizard))

(defun step-fields (wizard index)
  (mapcar (lambda (name) (find-field (wizard-description wizard) name))
          (rest (nth index (wizard-steps wizard)))))

(defun wizard-text (wizard name)
  (or (cdr (assoc name (wizard-texts wizard))) ""))

(defun check-fields (wizard fields)
  "Parse and check FIELDS' texts: their values as (FIELD . VALUE), and problems as (NAME . TEXT)."
  (let ((values '()) (problems '()))
    (dolist (field fields)
      (handler-case
          (let* ((value (parse-field field (wizard-text wizard (field-name field))))
                 (problem (check-field field value)))
            (if problem (push (cons (field-name field) problem) problems) (push (cons field value) values)))
        (field-error (e) (push (cons (field-name field) (field-error-message e)) problems))))
    (values (nreverse values) (nreverse problems))))

(defun wizard-next (wizard)
  (multiple-value-bind (values problems) (check-fields wizard (step-fields wizard (wizard-step wizard)))
    (declare (ignore values))
    (setf (wizard-problems wizard) problems)
    (unless problems (incf (wizard-step wizard)))))

(defun wizard-finish (wizard)
  "Check everything and the description's whole-object check; answer, or show the problems."
  (let* ((fields (loop for i below (length (wizard-steps wizard)) append (step-fields wizard i))))
    (multiple-value-bind (values problems) (check-fields wizard fields)
      (let ((whole (and (null problems) (description-validator (wizard-description wizard))
                        (funcall (description-validator (wizard-description wizard))
                                 (loop for (field . value) in values
                                       append (list (intern (symbol-name (field-name field)) :keyword) value))))))
        (cond (problems
               ;; Back to the first step with a problem.
               (setf (wizard-problems wizard) problems
                     (wizard-step wizard) (or (position-if (lambda (step) (some (lambda (name) (assoc name problems)) (rest step)))
                                                           (wizard-steps wizard))
                                              0)))
              (whole (setf (wizard-problems wizard) (list (cons nil whole))))
              ((wizard-write-p wizard)
               (loop for (field . value) in values do (setf (field-value field (wizard-object wizard)) value))
               (answer wizard (wizard-object wizard)))
              (t (answer wizard (loop for (field . value) in values
                                      append (list (intern (symbol-name (field-name field)) :keyword) value)))))))))

(defun render-wizard-progress (wizard)
  (progn
    (ol (:class "lt-wizard-steps" :aria-label (translate "Steps"))
      (loop for (title) in (append (wizard-steps wizard) (list (list (translate "Review"))))
            for i from 0
            do (li (:class (list (when (< i (wizard-step wizard)) "lt-done") (when (= i (wizard-step wizard)) "lt-current"))
                    :aria-current (when (= i (wizard-step wizard)) "step"))
                 (span (:class "lt-wizard-number") (text (1+ i))) " " (text (translate-label title)))))))

(defmethod render ((self wizard))
  (let* ((step (wizard-step self))
         (steps (wizard-steps self))
         (review (>= step (length steps)))
         (general (cdr (assoc nil (wizard-problems self)))))
    (div (:class "lt-dialog lt-wizard")
      (when (wizard-title self) (h2 () (text (wizard-title self))))
      (render-wizard-progress self)
      (when general (p (:class "lt-validation-error" :role "alert") (text general)))
      (form (:multipart (some #'field-multipart-p (loop for i below (length steps) append (step-fields self i))))
        (if review
            (progn
              (h3 () (translate "Review"))
              (dl (:class "lt-wizard-review")
                (loop for (title . names) in steps for i from 0
                      do (let ((i i))
                           (dolist (name names)
                             (let ((field (find-field (wizard-description self) name)))
                               (dt () (text (translate (field-label field))))
                               (dd () (if (typep field 'password-field)
                                          (text "••••••")
                                          ;; As the field shows it, not as it was posted.
                                          (render-field-value field (handler-case (parse-field field (wizard-text self name))
                                                                      (error () nil))))
                                 (text " ")
                                 (anchor (:callback (lambda () (setf (wizard-step self) i (wizard-problems self) '()))
                                          :aria-label (translate "Change ~A" (translate (field-label field))))
                                   (translate "Change")))))))))
            (progn
              (h3 () (text (translate-label (first (nth step steps)))))
              (dolist (field (step-fields self step))
                (let* ((name (field-name field))
                       (id (string-downcase (symbol-name name)))
                       (problem (cdr (assoc name (wizard-problems self)))))
                  (div (:class (list "lt-field" (when problem "lt-field-invalid")))
                    (label (:for id) (text (translate (field-label field)))
                      (when (field-required-p field) (span (:class "lt-required" :title (translate "required")) " *")))
                    (let ((*next-field-attributes* (list :aria-invalid (when problem "true")
                                                         :aria-describedby (field-description-ids field id problem))))
                      (render-field-input field id (wizard-text self name)
                                          (lambda (text) (setf (wizard-texts self)
                                                               (acons name text (remove name (wizard-texts self) :key #'car))))))
                    (when problem (div (:id (format nil "~A-error" id) :class "lt-validation-error") (text problem)))
                    (when (field-help field)
                      (div (:id (format nil "~A-help" id) :class "lt-help") (text (translate-label (field-help field))))))))))
        (div (:class "lt-buttons")
          (when (plusp step)
            (submit-button (:callback (lambda () (setf (wizard-problems self) '()) (decf (wizard-step self))))
              (translate "Back")))
          (if review
              (submit-button (:callback (lambda () (wizard-finish self))) (translate "Finish"))
              (submit-button (:callback (lambda () (wizard-next self))) (translate "Next")))
          (cancel-button (:callback (lambda () (answer self nil))) (translate "Cancel")))))))
