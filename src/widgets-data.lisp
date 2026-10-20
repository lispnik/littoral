;;;; widgets-data.lisp — lists loaded in batches, and conditions to filter by
;;;;
;;;;   (make-instance 'load-more-list :items (lambda () (all-orders)) :batch-size 20
;;;;                                  :render-item #'render-order :automatic t)
;;;;   (make-instance 'filter-builder :description 'task :update grid)
;;;;   (remove-if-not (lambda (task) (filter-matches-p builder task)) tasks)

(in-package #:littoral)

;;; Load more: a long list shown a batch at a time

(defclass load-more-list (component)
  ((items :initarg :items :initform '() :reader load-more-items-designator
          :documentation "A list, or a function returning one on every render.")
   (fetch :initarg :fetch :initform nil :reader load-more-fetch
          :documentation "Instead of :ITEMS, a function of START and COUNT returning at most COUNT items from START.")
   (batch-size :initarg :batch-size :initform 20 :reader load-more-batch-size)
   (shown :accessor load-more-shown :documentation "How many items are shown.")
   (render-item :initarg :render-item :initform (lambda (item) (text item)) :reader load-more-renderer)
   (automatic :initarg :automatic :initform nil :reader load-more-automatic-p
              :documentation "True to load the next batch as the end of the list is scrolled into view.")
   (label :initarg :label :initform "Load more" :reader load-more-label)
   (list-label :initarg :list-label :initform nil :reader load-more-list-label
               :documentation "What the list is called to assistive technology, translated.")
   (focus :initform nil :accessor load-more-focus
          :documentation "The position of the first item of the batch the button loaded last, which can take the focus.")
   (move-focus :initform nil :accessor load-more-move-focus-p
               :documentation "True when that item takes the focus as the page arrives: after the button, not scrolling.")
   (subscriptions :initarg :subscriptions :initform '() :reader load-more-subscriptions
                  :documentation "Channels whose PUBLISH draws the list again, as its items change.")
   (body :reader load-more-body)
   (status :reader load-more-status))
  (:documentation "A long list shown a batch at a time, with a Load more
button after it; with :AUTOMATIC true the next batch also comes as the
end of the list scrolls into view (infinite scrolling), and the button
stays for keyboards and for pages without JavaScript.  :ITEMS is a list, or
a function returning one, called on every render; or :FETCH, a function of
a start and a count, returns just the items wanted, for a database to page
through (it is asked for one more than it shows, to tell whether there are
more).  :SUBSCRIPTIONS, channels, draw it again on open pages when they are
published, as when its items change.  :BATCH-SIZE is 20 by default.  :RENDER-ITEM, a function of an item,
writes each one inside its li (as text by default).  How many are shown is
kept on the server, so the page comes back as it was left.  After the
button loads a batch, the focus moves to the first new item, and a status
line says how many are shown."))

(defclass load-more-part (component updatable)
  ((owner :initarg :owner :reader part-owner))
  (:documentation "A part of a LOAD-MORE-LIST drawn again on its own."))

(defclass load-more-body (load-more-part) ()
  (:documentation "A LOAD-MORE-LIST's items and button."))

(defclass load-more-status (load-more-part) ()
  (:documentation "A LOAD-MORE-LIST's line saying how many are shown, announced as it changes."))

;; Loading more draws the list again: littoral.js keeps the focus on what had it.
(defmethod updatable-wrapper ((self load-more-body))
  (values "div" '(:class "lt-load-more-body" :data-lt-keep-focus t)))
(defmethod updatable-wrapper ((self load-more-status))
  (values "p" '(:class "lt-load-more-status" :role "status" :aria-live "polite")))

(defmethod initialize-instance :after ((self load-more-list) &key)
  (setf (load-more-shown self) (load-more-batch-size self)
        (slot-value self 'body) (make-instance 'load-more-body :owner self)
        (slot-value self 'status) (make-instance 'load-more-status :owner self)))

(defmethod states ((self load-more-list)) (list self))
(defmethod subscriptions ((self load-more-part)) (load-more-subscriptions (part-owner self)))
(defmethod children ((self load-more-list)) (list (load-more-body self) (load-more-status self)))

(defun load-more-window (list)
  "Three values: the items LIST shows, whether there are more, and how many
there are in all (NIL when its :FETCH can't say)."
  (let ((shown (load-more-shown list)))
    (if (load-more-fetch list)
        (let ((items (funcall (load-more-fetch list) 0 (1+ shown))))
          (values (subseq items 0 (min shown (length items))) (> (length items) shown) nil))
        (let* ((designator (load-more-items-designator list))
               (items (if (functionp designator) (funcall designator) designator))
               (total (length items)))
          (values (subseq items 0 (min shown total)) (> total shown) total)))))

(defun load-more (list &key (focus t))
  "Show LIST's next batch too.  With FOCUS true, as for the button, the
first new item takes the focus once it is shown."
  (when focus
    (setf (load-more-focus list) (load-more-shown list)))
  (setf (load-more-move-focus-p list) focus)
  (incf (load-more-shown list) (load-more-batch-size list)))

(defun reset-load-more (list)
  "Show only LIST's first batch again, as after its items change."
  (setf (load-more-shown list) (load-more-batch-size list)
        (load-more-focus list) nil
        (load-more-move-focus-p list) nil))

(defmethod render ((self load-more-list))
  (div (:class "lt-load-more")
    (render-component (load-more-body self))
    (render-component (load-more-status self))))

(defmethod render ((self load-more-body))
  (let ((list (part-owner self)))
    (multiple-value-bind (items more) (load-more-window list)
      (let ((focus (load-more-focus list))
            (move (load-more-move-focus-p list))
            (targets (children list)))
        (ul (:class "lt-load-more-items"
             :aria-label (when (load-more-list-label list) (translate-label (load-more-list-label list))))
          (loop for item in items for i from 0
                do (let ((here (eql i focus)))
                     (li (:tabindex (when here "-1") :autofocus (and here move))
                       (funcall (load-more-renderer list) item)))))
        (when more
          (anchor (:class "lt-load-more-button"
                   :callback (lambda () (load-more list))
                   :on-click (ajax :callback (lambda () (load-more list)) :update targets)
                   :lazy (when (load-more-automatic-p list)
                           (ajax :callback (lambda () (load-more list :focus nil)) :update targets))
                   :data-lt-lazy-visible (load-more-automatic-p list))
            (text (translate-label (load-more-label list)))))))))

(defmethod render ((self load-more-status))
  (multiple-value-bind (items more total) (load-more-window (part-owner self))
    (declare (ignore more))
    (if total
        (text (translate "Showing ~D of ~D." (length items) total))
        (text (translate "Showing ~D." (length items))))))

;;; Filter builders: conditions on a description's fields

(defclass filter-builder (component updatable)
  ((description :initarg :description :reader filter-description)
   (field-names :initarg :fields :initform nil :reader filter-field-names
                :documentation "The fields conditions may name; NIL for those shown in reports.")
   (conditions :initarg :conditions :initform '() :accessor filter-conditions
               :documentation "(FIELD-NAME OPERATOR TEXT) lists, replaced, never changed.")
   (match :initarg :match :initform :all :accessor filter-match
          :documentation ":ALL when every condition must hold, :ANY when one is enough.")
   (update :initarg :update :initform nil :reader filter-update
           :documentation "The components re-rendered after each change; by default the builder.")
   (on-change :initarg :on-change :initform nil :reader filter-on-change
              :documentation "Called with no arguments after each change.")
   (focus :initform nil :accessor filter-focus
          :documentation "What takes the focus after the next change: a condition's position, or :ADD."))
  (:documentation "Conditions on a description's fields, such as \"Status is
Open\" and \"Due is before 2026-11-01\", that must all hold (or, with
:MATCH :ANY, any one).  Each condition is a field, a comparison suited to
its kind (text, number, date, time, choice, several choices, yes or no)
and a value, entered with an input of the field's kind.  FILTER-MATCHES-P
says whether an object passes; a condition not yet complete, or whose
value doesn't parse, is left out (and says why).

:DESCRIPTION names the description and :FIELDS the fields offered (by
default those in reports, without passwords).  :CONDITIONS starts it with
some, as (FIELD-NAME OPERATOR TEXT) lists, TEXT as it would be typed (a
choice by its position).  :UPDATE is the component, or list of them, that
shows what's filtered, re-rendered after each change: include the builder
unless it is inside one of them, as it is in a DATA-GRID's :CONDITIONS.
:ON-CHANGE is called after each change.  Changes go over AJAX; without
JavaScript an Apply button submits them."))

(defmethod states ((self filter-builder)) (list self))

(defun filter-builder-fields (builder)
  "The fields BUILDER's conditions may name."
  (let ((description (find-description (filter-description builder))))
    (if (filter-field-names builder)
        (mapcar (lambda (name) (find-field description name)) (filter-field-names builder))
        (remove-if-not (lambda (f) (and (field-in-report-p f) (not (field-hidden-p f))
                                        (not (typep f 'password-field))))
                       (description-fields description)))))

(defun filter-operators (field)
  "The comparisons a condition on FIELD can make: (OPERATOR . LABEL) pairs."
  (let ((blank '((:empty . "is empty") (:not-empty . "isn't empty"))))
    (typecase field
      (boolean-field '((:yes . "is yes") (:no . "is no")))
      (multiple-choice-field (list* '(:includes . "includes") '(:excludes . "doesn't include") blank))
      (choice-field (list* '(:is . "is") '(:is-not . "is not") blank))
      ((or integer-field rating-field)
       (list* '(:= . "is") '(:/= . "is not") '(:< . "is less than") '(:<= . "is at most")
              '(:> . "is more than") '(:>= . "is at least") blank))
      ((or date-field time-field)
       (list* '(:= . "is") '(:< . "is before") '(:> . "is after") blank))
      (otherwise (list* '(:contains . "contains") '(:not-contains . "doesn't contain") '(:is . "is")
                '(:starts . "starts with") blank)))))

(defun operator-takes-value-p (operator)
  "True when a condition with OPERATOR compares with a value."
  (not (member operator '(:empty :not-empty :yes :no))))

(defun condition-field (builder condition)
  "The field BUILDER's CONDITION names, or NIL when it isn't offered."
  (find (first condition) (filter-builder-fields builder) :key #'field-name))

(defun condition-target (field operator text)
  "What the condition compares with: two values, the value TEXT stands for
for FIELD and OPERATOR, and true when there is one; or NIL and NIL for a
blank TEXT, or NIL and a problem when TEXT doesn't parse."
  (let ((trimmed (string-trim " " (or text ""))))
    (cond ((not (operator-takes-value-p operator)) (values nil t))
          ((string= trimmed "") (values nil nil))
          ((typep field 'choice-field)
           (let ((index (ignore-errors (parse-integer trimmed)))
                 (choices (field-choices field)))
             (if (and index (< -1 index (length choices)))
                 (values (nth index choices) t)
                 (values nil nil))))
          ((typep field '(or integer-field rating-field))
           (let ((n (ignore-errors (parse-integer trimmed))))
             (if n (values n t) (values nil (translate "Give a whole number.")))))
          ((typep field 'date-field)
           (handler-case (values (parse-field field trimmed) t)
             (field-error () (values nil (translate "Give a date, like 2026-10-06.")))))
          ((typep field 'time-field)
           (handler-case (values (parse-field field trimmed) t)
             (field-error () (values nil (translate "Give a time, like 09:30.")))))
          (t (values trimmed t)))))

(defun numbers-list< (a b)
  "True when the list of numbers A comes before B, comparing in order."
  (loop for x in a for y in b
        do (cond ((< x y) (return t)) ((> x y) (return nil)) (t nil))
        finally (return nil)))

(defun compare-values (operator value target)
  "Whether VALUE, a number or a list of numbers, stands in OPERATOR to TARGET."
  (let ((less (if (realp value) (< value target) (numbers-list< value target)))
        (more (if (realp value) (> value target) (numbers-list< target value))))
    (ecase operator
      (:= (equal value target)) (:/= (not (equal value target)))
      (:< less) (:<= (not more)) (:> more) (:>= (not less)))))

(defun condition-holds-p (field operator target object)
  "True when OBJECT's value of FIELD stands in OPERATOR to TARGET."
  (let* ((value (field-value field object))
         (blank (or (null value) (and (stringp value) (string= value ""))
                    (string= (format-field field value) ""))))
    (case operator
      (:empty blank)
      (:not-empty (not blank))
      (:yes (and value t))
      (:no (not value))
      (:includes (and (listp value) (member target value :test #'equal) t))
      (:excludes (not (and (listp value) (member target value :test #'equal))))
      (:is-not (not (equal value target)))
      ((:= :/= :< :<= :> :>=)
       (cond ((not blank) (compare-values operator value target))
             (t (eq operator :/=))))
      (otherwise
       (let ((shown (format-field field value)))
         (if (typep field 'choice-field)
             (equal value target)
             (ecase operator
               (:contains (and (search target shown :test #'char-equal) t))
               (:not-contains (not (search target shown :test #'char-equal)))
               (:is (string-equal target shown))
               (:starts (and (<= (length target) (length shown))
                             (string-equal target shown :end2 (length target)))))))))))

(defun complete-conditions (builder)
  "BUILDER's conditions that can be applied: (FIELD OPERATOR TARGET) lists."
  (loop for condition in (filter-conditions builder)
        for field = (condition-field builder condition)
        when field
          append (destructuring-bind (name operator text) condition
                   (declare (ignore name))
                   (multiple-value-bind (target ok) (condition-target field operator text)
                     (when (eq ok t) (list (list field operator target)))))))

(defun filter-matches-p (builder object)
  "True when OBJECT passes BUILDER's complete conditions: all of them, or
with its match :ANY, at least one.  With none, everything passes."
  (let ((conditions (complete-conditions builder)))
    (or (null conditions)
        (funcall (if (eq (filter-match builder) :any) #'some #'every)
                 (lambda (c) (destructuring-bind (field operator target) c
                               (condition-holds-p field operator target object)))
                 conditions))))

(defun filter-changed (builder &optional focus)
  "Note a change to BUILDER: FOCUS, if any, takes the focus next, and its :ON-CHANGE is called."
  (setf (filter-focus builder) focus)
  (when (filter-on-change builder) (funcall (filter-on-change builder))))

(defun add-filter-condition (builder &optional field-name operator (text ""))
  "Add a condition to BUILDER: on FIELD-NAME (by default its first field)
with OPERATOR (by default the field's first) and TEXT."
  (let* ((field (if field-name
                    (find field-name (filter-builder-fields builder) :key #'field-name)
                    (first (filter-builder-fields builder))))
         (operator (or operator (car (first (filter-operators field))))))
    (setf (filter-conditions builder)
          (append (filter-conditions builder) (list (list (field-name field) operator text))))
    (filter-changed builder (1- (length (filter-conditions builder))))))

(defun remove-filter-condition (builder index)
  "Remove BUILDER's condition at INDEX, counting from 0."
  (setf (filter-conditions builder)
        (loop for c in (filter-conditions builder) for i from 0 unless (= i index) collect c))
  (filter-changed builder :add))

(defun clear-filter-conditions (builder)
  "Remove all BUILDER's conditions."
  (setf (filter-conditions builder) '())
  (filter-changed builder :add))

(defun change-condition (builder index part value)
  "Set PART (:FIELD, :OPERATOR or :TEXT) of BUILDER's condition at INDEX to
VALUE.  A new field keeps the operator when the field allows it."
  (setf (filter-conditions builder)
        (loop for c in (filter-conditions builder) for i from 0
              collect (if (/= i index)
                          c
                          (destructuring-bind (name operator text) c
                            (ecase part
                              (:field
                               (let ((field (find value (filter-builder-fields builder) :key #'field-name))
                                     (old (condition-field builder c)))
                                 (if (or (null field) (eq value name))
                                     c
                                     (list value
                                           (if (assoc operator (filter-operators field))
                                               operator
                                               (car (first (filter-operators field))))
                                           ;; What was typed for another kind of field means nothing here.
                                           (if (eq (class-of field) (class-of old)) text "")))))
                              (:operator (if (assoc value (filter-operators (condition-field builder c)))
                                             (list name value text)
                                             c))
                              (:text (list name operator value)))))))
  (filter-changed builder))

(defun filter-targets (builder)
  "The components a change to BUILDER draws again."
  (or (alexandria:ensure-list (filter-update builder)) (list builder)))

(defun render-condition-value (builder field text id index)
  "Write the input for the value of BUILDER's condition at INDEX."
  (let* ((targets (filter-targets builder))
         (set (lambda (v) (change-condition builder index :text v)))
         (value-label (translate "Value")))
    (cond ((typep field 'choice-field)
           (let ((choices (field-choices field))
                 (chosen (ignore-errors (parse-integer text))))
             (emit-tag "select" (list :id id :aria-label value-label :name (register :value set)
                                      :on-change (ajax :update targets))
                       (lambda ()
                         (emit-tag "option" (list :value "" :selected (null chosen)) nil)
                         (loop for choice in choices for i from 0
                               do (let ((choice choice))
                                    (emit-tag "option" (list :value i :selected (eql i chosen))
                                              (lambda () (text (format-field field choice))))))))))
          (t
           (emit-tag "input" (list :type (typecase field
                                            (date-field "date") (time-field "time")
                                            ((or integer-field rating-field) "number") (otherwise "text"))
                                   :id id :aria-label value-label :value text :name (register :value set)
                                   (if (typep field '(or date-field time-field)) :on-change :on-input)
                                   (ajax :update targets))
                     nil)))))

(defmethod render ((self filter-builder))
  (let* ((id (component-id self))
         (fields (filter-builder-fields self))
         (targets (filter-targets self))
         (conditions (filter-conditions self))
         (focus (filter-focus self)))
    (flet ((add () (add-filter-condition self)))
      (form (:class "lt-filter" :role "search" :aria-label (translate "Conditions"))
        (when (> (length conditions) 1)
          (div (:class "lt-filter-match")
            (label (:for (format nil "~A-match" id)) (translate "Show what matches"))
            (text " ")
            (select-list (:id (format nil "~A-match" id) :items '(:all :any) :selected (filter-match self)
                          :labels (lambda (m) (translate (if (eq m :all) "all of these conditions" "any of these conditions")))
                          :callback (lambda (m) (when m (setf (filter-match self) m) (filter-changed self)))
                          :on-change (ajax :update targets)))))
        (when conditions
          (ol (:class "lt-filter-conditions")
            (loop for condition in conditions for index from 0
                  do (let ((index index))
                       (destructuring-bind (name operator text) condition
                         (declare (ignore name))
                         (let ((field (condition-field self condition))
                               (prefix (format nil "~A-~D" id index)))
                           (when field
                             (li ()
                              (div (:role "group" :aria-label (translate "Condition ~D" (1+ index)))
                               (select-list (:id (format nil "~A-field" prefix) :aria-label (translate "Field")
                                             :items fields :selected field :autofocus (eql focus index)
                                             :labels (lambda (f) (translate (field-label f)))
                                             :callback (lambda (f) (when f (change-condition self index :field (field-name f))))
                                             :on-change (ajax :update targets)))
                               (text " ")
                               (let ((operators (filter-operators field)))
                                 (select-list (:id (format nil "~A-operator" prefix) :aria-label (translate "Comparison")
                                               :items operators :selected (assoc operator operators)
                                               :labels (lambda (o) (translate (cdr o)))
                                               :callback (lambda (o) (when o (change-condition self index :operator (car o))))
                                               :on-change (ajax :update targets))))
                               (when (operator-takes-value-p operator)
                                 (text " ")
                                 (render-condition-value self field text (format nil "~A-value" prefix) index))
                               (text " ")
                               (flet ((remove-it () (remove-filter-condition self index)))
                                 (submit-button (:class "lt-filter-remove" :formnovalidate t
                                                 :aria-label (translate "Remove condition ~D" (1+ index))
                                                 :callback #'remove-it
                                                 :on-click (ajax :callback #'remove-it :update targets))
                                   (translate "Remove")))
                               (multiple-value-bind (target problem) (condition-target field operator text)
                                 (declare (ignore target))
                                 (when (stringp problem)
                                   (div (:class "lt-validation-error") (text problem)))))))))))))
        (div (:class "lt-buttons")
          (submit-button (:id (format nil "~A-add" id) :class "lt-filter-add" :formnovalidate t
                          :autofocus (eq focus :add)
                          :callback #'add :on-click (ajax :callback #'add :update targets))
            (translate "Add a condition"))
          (when conditions
            (flet ((clear () (clear-filter-conditions self)))
              (submit-button (:formnovalidate t :callback #'clear :on-click (ajax :callback #'clear :update targets))
                (translate "Clear"))))
          (when conditions
            (emit-tag "noscript" '()
                      (lambda () (submit-button (:callback (lambda () (filter-changed self))) (translate "Apply"))))))))))
