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

;;; The data grid: the contacts example's description, edited in place

(defclass grid-section (component)
  ((contacts :initform (append (sample-contacts)
                               (list (make-instance 'contact :name "Alan Turing" :email "alan@example.org" :role :colleague
                                                             :birthday '(1912 6 23))
                                     (make-instance 'contact :name "Katherine Johnson" :email "katherine@example.org"
                                                             :role :friend :birthday '(1918 8 26))))
             :reader section-contacts)
   (grid :reader section-grid)
   (saved :initform nil :accessor section-saved)))

(defmethod initialize-instance :after ((self grid-section) &key)
  (setf (slot-value self 'grid)
        (make-instance 'data-grid :description 'contact :rows (section-contacts self) :page-size 4
                                  :fields '(name email role birthday)
                                  :on-save (lambda (contact) (setf (section-saved self) (slot-value contact 'name))))))

(defmethod children ((self grid-section)) (list (section-grid self)))
(defmethod states ((self grid-section)) (list self))

(defmethod render ((self grid-section))
  (h2 () "Data grid")
  (p () "The contacts example's description, as a grid: type in a column's filter box, sort by a heading, "
    "and edit a row in place, with the description's own inputs and checks.")
  (render-component (section-grid self))
  (when (section-saved self)
    (p (:role "status") (text (format nil "Saved ~A." (section-saved self))))))

;;; Charts

(defclass charts-section (component) ())

(defmethod render ((self charts-section))
  (h2 () "Charts")
  (p () "Inline SVG, each with its data as a table behind it for screen readers.")
  (bar-chart '(("Mon" . 12) ("Tue" . 19) ("Wed" . 7) ("Thu" . 23) ("Fri" . 15) ("Sat" . 4) ("Sun" . 2))
             :title "Orders this week")
  (line-chart '(("Visits" 120 180 150 220 260 240 300) ("Sign-ups" 12 20 18 30 34 28 41))
              :title "Visits and sign-ups" :x-labels '("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul"))
  (p () "A sparkline, inline: " (sparkline '(3 5 2 8 6 9 4 11 7 12) :label "Ten days of support tickets")))

;;; Calendar

(defclass calendar-section (component)
  ((calendar :reader section-calendar)
   (chosen :initform nil :accessor section-chosen)))

(defun sample-events ()
  (multiple-value-bind (s m h day month year) (decode-universal-time (get-universal-time))
    (declare (ignore s m h))
    (list (cons (list year month day) "Today")
          (cons (list year month (min 28 (+ day 2))) "Team lunch")
          (cons (list year month (min 28 (+ day 2))) "Release")
          (cons (list year month (max 1 (- day 5))) "Planning"))))

(defmethod initialize-instance :after ((self calendar-section) &key)
  (setf (slot-value self 'calendar)
        (make-instance 'calendar :events #'sample-events
                                 :on-select (lambda (date) (setf (section-chosen self) date)))))

(defmethod children ((self calendar-section)) (list (section-calendar self)))
(defmethod states ((self calendar-section)) (list self))

(defmethod render ((self calendar-section))
  (h2 () "Calendar")
  (render-component (section-calendar self))
  (when (section-chosen self)
    (p (:role "status") "You chose " (text (apply #'localized-date (section-chosen self))) ".")))

;;; Kanban

(defclass kanban-section (component)
  ((board :initform (make-instance 'kanban :columns '(("To do" "Write the docs" "Fix the login bug" "Plan the release")
                                                      ("Doing" "Review the data grid")
                                                      ("Done" "Ship the charts")))
          :reader section-board)))

(defmethod children ((self kanban-section)) (list (section-board self)))

(defmethod render ((self kanban-section))
  (h2 () "Kanban")
  (p () "Drag cards between columns, or use the arrows on each card.")
  (render-component (section-board self)))

;;; Markdown

(defclass markdown-section (component updatable)
  ((source :initform "# A heading

Some *emphasis*, some **strong** text and `code`.

- A list
- with [a link](https://lispnik.github.io/littoral/)

> A quote. <script>alert('escaped, never run')</script>"
           :accessor section-source)))

(defmethod states ((self markdown-section)) (list self))

(defmethod render ((self markdown-section))
  (h2 () "Markdown")
  (p () "The " (code () ":markdown") " field kind shows text written in Markdown as safe HTML: "
    "any HTML in it is escaped, and links go only to http(s), mailto or this site.")
  (div (:class "markdown-demo")
    (form ()
      (text-area (:id "markdown-source" :label "Markdown" :rows 9 :value (section-source self)
                  :callback (lambda (v) (setf (section-source self) v))
                  :on-input (ajax-update self))))
    (div (:class "lt-markdown markdown-preview" :aria-label "Preview")
      (raw (markdown-html (section-source self))))))

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
                     (cons "Sortable" (make-instance 'sortable-section :list (demo-tasks self)))
                     (cons "Data grid" (make-instance 'grid-section))
                     (cons "Charts" (make-instance 'charts-section))
                     (cons "Calendar" (make-instance 'calendar-section))
                     (cons "Kanban" (make-instance 'kanban-section))
                     (cons "Markdown" (make-instance 'markdown-section))))))

(defmethod children ((self widget-demo)) (list (demo-navigation self)))

(defmethod states ((self widget-demo)) (list self))

(defmethod style ((self widget-demo))
  ".markdown-demo { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 1rem; }
.markdown-demo textarea { width: 100%; font-family: ui-monospace, monospace; }
.markdown-preview { border: 1px solid var(--lt-border); border-radius: 6px; padding: .6rem; }
@media (max-width: 40rem) { .markdown-demo { grid-template-columns: minmax(0, 1fr); } }")

(defmethod render ((self widget-demo))
  (h1 () "Widgets")
  (render-component (demo-navigation self)))
