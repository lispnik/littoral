;;;; widgets.lisp — tabs, navigation, a tree, autocomplete, a sortable list

(in-package #:littoral-examples)

(defclass note (component)
  ((text :initarg :text :reader note-text))
  (:documentation "A paragraph, for showing in tabs."))

(defmethod render ((self note))
  (p () (text (note-text self))))

(defun condition-subclasses (class)
  "The direct subclasses of CLASS that live in the COMMON-LISP package."
  ;; REMOVE-IF-NOT may return its argument itself, and that list belongs to
  ;; the class; SORT is destructive, so copy first.
  (sort (copy-list (remove-if-not (lambda (c) (eq (symbol-package (class-name c)) (find-package :cl)))
                                  (closer-mop:class-direct-subclasses class)))
        #'string< :key #'class-name))

(defun cl-symbols-starting (prefix)
  "The external symbols of COMMON-LISP whose names start with PREFIX."
  (let ((matches '()))
    (do-external-symbols (symbol :cl)
      (when (alexandria:starts-with-subseq prefix (symbol-name symbol) :test #'char-equal)
        (push symbol matches)))
    (sort matches #'string< :key #'symbol-name)))

(defclass widget-demo (component)
  ((navigation :reader demo-navigation)
   (chosen-symbol :initform nil :accessor chosen-symbol)
   (selected-condition :initform nil :accessor selected-condition)
   (tasks :reader demo-tasks))
  (:documentation "A tour of the widgets."))

(defclass tree-section (component)
  ((demo :initarg :demo :reader section-demo)
   (tree :reader section-tree))
  (:documentation "The condition-type tree and what was picked."))

(defmethod initialize-instance :after ((self tree-section) &key)
  (setf (slot-value self 'tree)
        (make-instance 'tree :roots (list (find-class 'condition))
                             :children #'condition-subclasses
                             :labels (lambda (c) (string-downcase (class-name c)))
                             :on-select (lambda (c) (setf (selected-condition (section-demo self)) c))))
  (toggle-item (section-tree self) (find-class 'condition)))

(defmethod children ((self tree-section)) (list (section-tree self)))

(defmethod render ((self tree-section))
  (h2 () "Tree")
  (p () "Common Lisp's condition types.")
  (render-component (section-tree self))
  (let ((c (selected-condition (section-demo self))))
    (when c
      (p () "Selected: " (code () (text (string-downcase (class-name c))))))))

(defclass autocomplete-section (component)
  ((demo :initarg :demo :reader section-demo)
   (field :reader section-field))
  (:documentation "Autocomplete over the COMMON-LISP package."))

(defmethod initialize-instance :after ((self autocomplete-section) &key)
  (setf (slot-value self 'field)
        (make-instance 'autocomplete
                       :input-id "symbol"
                       :placeholder "Type the start of a CL symbol"
                       :suggest #'cl-symbols-starting
                       :labels (lambda (s) (string-downcase (symbol-name s)))
                       :on-choose (lambda (s) (setf (chosen-symbol (section-demo self)) s)))))

(defmethod children ((self autocomplete-section)) (list (section-field self)))

(defmethod render ((self autocomplete-section))
  (h2 () "Autocomplete")
  (render-component (section-field self))
  (let ((s (chosen-symbol (section-demo self))))
    (when s
      (p () "Chose " (code () (text (string-downcase (symbol-name s))))
        (let ((doc (or (documentation s 'function) (documentation s 'variable))))
          (when doc (text (format nil ": ~A" (first (cl-ppcre:split "\\n" doc))))))))))

(defclass sortable-section (component)
  ((list :initarg :list :reader section-list))
  (:documentation "A to-do list to reorder."))

(defmethod children ((self sortable-section)) (list (section-list self)))

(defmethod render ((self sortable-section))
  (h2 () "Sortable list")
  (p () "Drag the items, or use the arrows.")
  (render-component (section-list self))
  (p () "Order: " (text (format nil "~{~A~^, ~}" (sortable-items (section-list self))))))

(defmethod initialize-instance :after ((self widget-demo) &key)
  (setf (slot-value self 'tasks)
        (make-instance 'sortable-list :items (list "Write the tests" "Make them pass"
                                                   "Refactor" "Ship it")))
  (setf (slot-value self 'navigation)
        (make-instance
         'navigation
         :tabs (list (cons "Tabs"
                           (make-instance 'tab-panel
                                          :tabs (list (cons "One" (make-instance 'note :text "The first tab."))
                                                      (cons "Two" (make-instance 'note :text "The second tab."))
                                                      (cons "Three" (make-instance 'note :text "The third tab.")))))
                     (cons "Tree" (make-instance 'tree-section :demo self))
                     (cons "Autocomplete" (make-instance 'autocomplete-section :demo self))
                     (cons "Sortable" (make-instance 'sortable-section :list (demo-tasks self)))))))

(defmethod children ((self widget-demo)) (list (demo-navigation self)))

(defmethod states ((self widget-demo)) (list self))

(defmethod render ((self widget-demo))
  (h1 () "Widgets")
  (render-component (demo-navigation self)))
