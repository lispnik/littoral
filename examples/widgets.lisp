;;;; widgets.lisp — tabs, a command palette, breadcrumbs, a tree, autocomplete, a sortable list, lazy panels, diffs

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

;;; Breadcrumbs and in-place editing: a pantry to look through

(defclass pantry-item ()
  ((name :initarg :name :accessor pantry-item-name)
   (stock :initarg :stock :accessor pantry-item-stock))
  (:documentation "Something on a pantry shelf."))

(define-description pantry-item
  ((name :required t :max-length 40)
   (stock :type :integer :min 0 :label "In stock")))

(defclass pantry-level (component)
  ((trail :initarg :trail :accessor level-trail :documentation "The breadcrumb trail above the pantry."))
  (:documentation "A page of the pantry: it knows the trail, which an item's new name updates."))

(defclass pantry-page (pantry-level)
  ((shelves :initarg :shelves :reader pantry-shelves :documentation "Alist of shelf name → items."))
  (:documentation "The shelves; each opens a SHELF-PAGE."))

(defclass shelf-page (pantry-level)
  ((name :initarg :name :reader shelf-name)
   (items :initarg :items :reader shelf-items))
  (:documentation "A shelf's items; each opens an ITEM-PAGE."))

(defclass item-page (pantry-level)
  ((item :initarg :item :reader page-item)
   (editors :reader page-editors))
  (:documentation "An item, its fields edited in place."))

(defmethod breadcrumb-label ((self pantry-page)) "Pantry")
(defmethod breadcrumb-label ((self shelf-page)) (shelf-name self))
(defmethod breadcrumb-label ((self item-page)) (pantry-item-name (page-item self)))

(defmethod initialize-instance :after ((self item-page) &key)
  (setf (slot-value self 'editors)
        ;; A new name shows in the trail at once.
        (list (make-in-place-editor (page-item self) 'name :update (level-trail self))
              (make-in-place-editor (page-item self) 'stock))))

(defmethod children ((self item-page)) (page-editors self))

(defmethod render ((self pantry-page))
  (ul ()
    (loop for (name . items) in (pantry-shelves self)
          do (let ((name name) (items items))
               (li () (anchor (:callback (lambda ()
                                           (show self (make-instance 'shelf-page :name name :items items
                                                                                 :trail (level-trail self)))))
                        (text name)))))))

(defmethod render ((self shelf-page))
  (ul ()
    (dolist (item (shelf-items self))
      (let ((item item))
        (li () (anchor (:callback (lambda ()
                                    (show self (make-instance 'item-page :item item :trail (level-trail self)))))
                 (text (pantry-item-name item)))))))
  (p () (anchor (:callback (lambda () (answer self))) "Back to the pantry")))

(defmethod render ((self item-page))
  (dl (:class "pantry-item")
    (loop for editor in (page-editors self)
          for label in '("Name" "In stock")
          do (dt () (text label))
             (dd () (render-component editor)))))

(defclass crumbs-section (component)
  ((pantry :reader section-pantry)
   (trail :reader section-trail))
  (:documentation "A pantry to look through, with a breadcrumb trail."))

(defmethod initialize-instance :after ((self crumbs-section) &key)
  (let* ((pantry (make-instance 'pantry-page
                                :shelves (list (cons "Fruit" (list (make-instance 'pantry-item :name "Apples" :stock 12)
                                                                   (make-instance 'pantry-item :name "Pears" :stock 3)))
                                               (cons "Vegetables" (list (make-instance 'pantry-item :name "Leeks" :stock 4))))))
         (trail (make-instance 'breadcrumb-trail :of pantry)))
    (setf (level-trail pantry) trail
          (slot-value self 'pantry) pantry
          (slot-value self 'trail) trail)))

(defmethod children ((self crumbs-section)) (list (section-trail self) (section-pantry self)))

(defmethod render ((self crumbs-section))
  (h2 () "Breadcrumbs and in-place editing")
  (p () "Open a shelf, then an item. The trail follows the calls, and its links go back to that level. "
    "An item's fields are edited where they are shown.")
  (render-component (section-trail self))
  (render-component (section-pantry self)))

;;; Forms: tags, a time and a date range, in a description's editor

(defclass outing ()
  ((title :initarg :title :accessor outing-title)
   (tags :initarg :tags :accessor outing-tags)
   (meet :initarg :meet :accessor outing-meet)
   (dates :initarg :dates :accessor outing-dates))
  (:documentation "A trip, to edit."))

(define-description outing
  ((title :required t)
   (tags :type :tags :choices '("hiking" "museums" "food" "beach") :max 5 :help "Pick some, or type your own.")
   (meet :type :time :label "Meeting time")
   (dates :type :date-range :label "Dates")))

(defclass forms-section (component)
  ((outing :initform (make-instance 'outing :title "Lyon" :tags '("food" "museums") :meet '(9 30)
                                            :dates '((2026 11 6) . (2026 11 8)))
           :reader section-outing)
   (editor :reader section-editor))
  (:documentation "A description editor using the tags, time and date-range field kinds."))

(defmethod initialize-instance :after ((self forms-section) &key)
  (setf (slot-value self 'editor) (make-editor (section-outing self) :title "An outing")))

(defmethod children ((self forms-section)) (list (section-editor self)))

(defmethod render ((self forms-section))
  (h2 () "Tags, times and date ranges")
  (p () "Tags turn into chips as you type (Enter or a comma adds one); without JavaScript they're a comma-separated list.")
  (render-component (section-editor self))
  (let ((description (find-description 'outing)))
    (dl (:class "outing-saved")
      (dolist (field (description-fields description))
        (dt () (text (field-label field)))
        (dd () (render-field-value field (field-value field (section-outing self))))))))

;;; Menus, accordions and disclosures

(defclass menus-section (component)
  ((chosen :initform nil :accessor menus-chosen)
   (bar :reader menus-bar)
   (actions :reader menus-actions)
   (faq :reader menus-faq)
   (more :reader menus-more))
  (:documentation "A menu bar, a dropdown of actions, an accordion and a disclosure."))

(defmethod initialize-instance :after ((self menus-section) &key)
  (flet ((choose (what) (lambda () (setf (menus-chosen self) what))))
    (setf (slot-value self 'bar)
          (make-instance 'menu-bar :items (list (cons "Home" (url-for "/examples"))
                                                (cons "File" (list (cons "New" (choose "New"))
                                                                   (cons "Open…" (choose "Open"))
                                                                   :separator
                                                                   (cons "Close" (choose "Close"))))
                                                (cons "Help" (list (cons "About" (choose "About"))))))
          (slot-value self 'actions)
          (make-instance 'dropdown-menu :label "Actions"
                                        :items (list (cons "Rename" (choose "Rename"))
                                                     (cons "Duplicate" (choose "Duplicate"))
                                                     :separator
                                                     (cons "Delete" (choose "Delete"))))
          (slot-value self 'faq)
          (make-instance 'accordion
                         :sections (list (cons "What is an accordion?" (make-instance 'note :text "Sections that open one at a time."))
                                         (cons "Does it need JavaScript?" (make-instance 'note :text "No: each section is a details element."))
                                         (cons "Is it remembered?" (make-instance 'note :text "Yes: what is open is kept on the server.")))
                         :open '(0))
          (slot-value self 'more)
          (make-instance 'disclosure :summary "Show the small print"
                                     :content (make-instance 'note :text "Menus close on Escape or a click elsewhere.")))))

(defmethod children ((self menus-section))
  (list (menus-bar self) (menus-actions self) (menus-faq self) (menus-more self)))

(defmethod states ((self menus-section)) (list self))

(defmethod render ((self menus-section))
  (h2 () "Menus, accordions and disclosures")
  (render-component (menus-bar self))
  (p () (render-component (menus-actions self))
    (when (menus-chosen self) (text " ") (span (:class "menus-chosen" :role "status") (text (format nil "You chose ~A." (menus-chosen self))))))
  (render-component (menus-faq self))
  (render-component (menus-more self)))


;;; Tools: a lazy panel and the differences between two texts

(defvar *slow-seconds* 0.8 "How long the lazy panel's content pretends to take.")

(defclass primes-note (component)
  ((primes :initarg :primes :reader note-primes))
  (:documentation "Primes, which took a while to find."))

(defmethod render ((self primes-note))
  (p () (text (format nil "The first ~D primes, found after the page arrived: ~{~D~^, ~}."
                      (length (note-primes self)) (note-primes self)))))

(defun first-primes (count)
  "The first COUNT primes."
  (loop with found = '()
        for n from 2
        while (< (length found) count)
        when (loop for p in found never (zerop (mod n p))) do (setf found (append found (list n)))
        finally (return found)))

(defclass tools-section (component)
  ((lazy :initform (make-instance 'lazy-panel
                                  :placeholder "Finding primes…"
                                  :content (lambda ()
                                             (sleep *slow-seconds*)
                                             (make-instance 'primes-note :primes (first-primes 20))))
         :reader tools-lazy)
   (old :initform (format nil "Shopping:~%apples~%bread~%milk~%cheese~%") :accessor tools-old)
   (new :initform (format nil "Shopping:~%apples~%brown bread~%cheese~%eggs~%") :accessor tools-new)
   (diff :initform (make-instance 'diff-view :old-label "Monday" :new-label "Tuesday") :reader tools-diff))
  (:documentation "A lazy panel, and two texts compared."))

(defmethod initialize-instance :after ((self tools-section) &key)
  (setf (diff-view-old (tools-diff self)) (tools-old self)
        (diff-view-new (tools-diff self)) (tools-new self)))

(defmethod children ((self tools-section)) (list (tools-lazy self) (tools-diff self)))

(defmethod states ((self tools-section)) (list self))

(defmethod render ((self tools-section))
  (h2 () "Lazy panel")
  (p () "This part of the page was left out when it was sent, then filled in over AJAX.")
  (render-component (tools-lazy self))
  (h2 () "Differences")
  (form (:class "tools-texts")
    (div (:class "lt-field")
      (label (:for "diff-old") "Monday's list")
      (text-area (:id "diff-old" :rows 6 :value (tools-old self) :callback (lambda (v) (setf (tools-old self) v)))))
    (div (:class "lt-field")
      (label (:for "diff-new") "Tuesday's list")
      (text-area (:id "diff-new" :rows 6 :value (tools-new self) :callback (lambda (v) (setf (tools-new self) v)))))
    (div (:class "lt-buttons")
      (submit-button (:callback (lambda ()
                                  (setf (diff-view-old (tools-diff self)) (tools-old self)
                                        (diff-view-new (tools-diff self)) (tools-new self))))
        "Compare")))
  (render-component (tools-diff self)))

(defclass widget-demo (component)
  ((navigation :reader demo-navigation)
   (palette :reader demo-palette)
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
                     (cons "Breadcrumbs" (make-instance 'crumbs-section))
                     (cons "Forms" (make-instance 'forms-section))
                     (cons "Menus" (make-instance 'menus-section))
                     (cons "Data grid" (make-instance 'grid-section))
                     (cons "Charts" (make-instance 'charts-section))
                     (cons "Calendar" (make-instance 'calendar-section))
                     (cons "Kanban" (make-instance 'kanban-section))
                     (cons "Markdown" (make-instance 'markdown-section))
                     (cons "Tools" (make-instance 'tools-section)))))
  (setf (slot-value self 'palette)
        (make-instance 'command-palette
                       :commands (lambda () (widget-commands self))
                       :search (lambda (query)
                                 ;; Common Lisp symbols, opened in the Autocomplete tab.
                                 (loop for symbol in (cl-symbols-starting query)
                                       repeat 3
                                       collect (let ((symbol symbol))
                                                 (palette-command (format nil "Look up ~(~A~)" symbol)
                                                                  (lambda ()
                                                                    (select-tab (demo-navigation self) "Autocomplete")
                                                                    (setf (chosen-symbol self) symbol))
                                                                  :group "Symbols")))))))

(defun widget-commands (demo)
  "The palette's commands: a tab to show, or another example to open."
  (append (loop for (label) in (panel-tabs (demo-navigation demo))
                collect (let ((label label))
                          (palette-command (format nil "Show ~A" label)
                                           (lambda () (select-tab (demo-navigation demo) label))
                                           :group "Tabs")))
          (loop for (label path keywords) in '(("Counter" "/examples/counter" ("click"))
                                               ("Wiki" "/examples/wiki" ("pages" "history"))
                                               ("Report" "/examples/report" ("table" "elements"))
                                               ("Chat" "/examples/chat" ("room" "talk")))
                collect (palette-command (format nil "Open the ~A example" label) (url-for path)
                                         :group "Examples" :keywords keywords))))

(defmethod children ((self widget-demo)) (list (demo-palette self) (demo-navigation self)))

(defmethod states ((self widget-demo)) (list self))

(defmethod style ((self widget-demo))
  ".markdown-demo { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 1rem; }
.markdown-demo textarea { width: 100%; font-family: ui-monospace, monospace; }
.markdown-preview { border: 1px solid var(--lt-border); border-radius: 6px; padding: .6rem; }
@media (max-width: 40rem) { .markdown-demo { grid-template-columns: minmax(0, 1fr); } }
.widgets-heading { display: flex; justify-content: space-between; align-items: center; gap: 1rem; flex-wrap: wrap; }
.tools-texts { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 0 1rem; }
.tools-texts .lt-buttons { grid-column: 1 / -1; }
.tools-texts textarea { width: 100%; font-family: ui-monospace, monospace; }
@media (max-width: 40rem) { .tools-texts { grid-template-columns: minmax(0, 1fr); } }")

(defmethod render ((self widget-demo))
  (div (:class "widgets-heading")
    (h1 () "Widgets")
    (render-component (demo-palette self)))
  (render-component (demo-navigation self)))
