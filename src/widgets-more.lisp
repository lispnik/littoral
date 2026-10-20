;;;; widgets-more.lisp — tabs, navigation, breadcrumbs, trees, autocomplete, sortable lists

(in-package #:littoral)

;;; Tab panel and navigation

(defclass tab-panel (component)
  ((tabs :initarg :tabs :initform '() :accessor panel-tabs
         :documentation "Alist of (LABEL . COMPONENT).")
   (selected :initarg :selected :initform 0 :accessor panel-selected
             :documentation "Index of the tab shown."))
  (:documentation "Shows one of several components, chosen by a row of tabs,
like Seaside's WATabPanel.  :TABS is an alist of (LABEL . COMPONENT), the
labels translated when shown; :SELECTED is the index of the tab shown first
(0 by default).  The current tab is not a link."))

(defclass navigation (tab-panel) ()
  (:documentation "A TAB-PANEL drawn as a menu beside its content, like
Seaside's WASimpleNavigation."))

(defmethod states ((self tab-panel))
  (list self))

(defun selected-tab (panel)
  "The component PANEL shows, or NIL when it has no tabs."
  (rest (nth (panel-selected panel) (panel-tabs panel))))

(defmethod children ((self tab-panel))
  (let ((tab (selected-tab self)))
    (and tab (list tab))))

(defun select-tab (panel label)
  "Show the tab of PANEL labelled LABEL (compared with EQUAL), and return
its index; when no tab has that label, change nothing and return NIL."
  (let ((index (position label (panel-tabs panel) :key #'first :test #'equal)))
    (when index (setf (panel-selected panel) index))))

(defun render-tab-links (panel)
  "Write the links to PANEL's tabs, the current one not a link."
  (loop for (label) in (panel-tabs panel)
        for index from 0
        do (let ((index index))
             (h:li (:class (when (= index (panel-selected panel)) "lt-active"))
               (if (= index (panel-selected panel))
                   (h:span (:aria-current "page") (h:text (translate-label label)))
                   (h:anchor (:callback (lambda () (setf (panel-selected panel) index)))
                     (h:text (translate-label label))))))))

(defmethod render ((self tab-panel))
  (h:div (:class "lt-tab-panel")
    (h:nav (:aria-label (translate "Tabs")) (h:ul (:class "lt-tabs") (render-tab-links self)))
    (h:div (:class "lt-tab-body")
      (let ((tab (selected-tab self)))
        (when tab (render-component tab))))))

(defmethod render ((self navigation))
  (h:div (:class "lt-navigation")
    (h:nav () (h:ul (:class "lt-menu") (render-tab-links self)))
    (h:div (:class "lt-navigation-body")
      (let ((tab (selected-tab self)))
        (when tab (render-component tab))))))

;;; Breadcrumbs: the chain of calls

(defclass breadcrumb-trail (component updatable)
  ((of :initarg :of :reader breadcrumb-trail-of
       :documentation "The component whose calls the trail follows."))
  (:documentation "A trail of links naming :OF, the component it was made
for, then what that has called, then what that has called, and so on, to
the component showing now, which is not a link.  Following a link dismisses
everything that level called, as HOME does, so it shows itself again.  The
names are BREADCRUMB-LABEL's.  Render the trail outside :OF, which a call
replaces.  It is UPDATABLE, for AJAX callbacks that call or change a name."))

(defgeneric breadcrumb-label (component)
  (:documentation "COMPONENT's name in a BREADCRUMB-TRAIL, translated when
shown.  By default its class name, capitalised, with spaces for hyphens
(\"Book List\"); a DESCRIPTION-EDITOR's is its title.")
  (:method ((component component))
    (string-capitalize (substitute #\Space #\- (symbol-name (class-name (class-of component)))))))

(defun call-chain (component)
  "COMPONENT, then what it has called, then what that has called, and so on."
  (loop for c = component
          then (let ((delegation (find-if (lambda (d) (typep d 'delegation)) (decorations c))))
                 (and delegation (delegation-delegate delegation)))
        while c collect c))

(defmethod render ((self breadcrumb-trail))
  (h:nav (:class "lt-breadcrumbs" :aria-label (translate "Breadcrumbs"))
    (h:ol ()
      (loop for (component . more) on (call-chain (breadcrumb-trail-of self))
            do (let ((component component))
                 (h:li ()
                   (if more
                       (h:anchor (:callback (lambda () (home component)))
                         (h:text (translate-label (breadcrumb-label component))))
                       (h:span (:aria-current "page")
                         (h:text (translate-label (breadcrumb-label component)))))))))))

;;; Disclosures and accordions: <details>, remembered on the server

(defclass disclosure (component updatable)
  ((summary :initarg :summary :reader disclosure-summary :documentation "The line that opens and closes it.")
   (content :initarg :content :reader disclosure-content :documentation "The component shown when open.")
   (open :initarg :open :initform nil :accessor disclosure-open-p))
  (:documentation "A line, :SUMMARY (translated), that opens and closes
:CONTENT, a component, beneath it: an HTML details element, so it works
without JavaScript too.  With JavaScript, opening and closing goes over
AJAX and is remembered, so the page comes back as it was left.  :OPEN T
starts it open."))

(defmethod states ((self disclosure)) (list self))
(defmethod children ((self disclosure)) (list (disclosure-content self)))

(defmethod render ((self disclosure))
  (h:details (:class "lt-disclosure" :open (and (disclosure-open-p self) t))
    (h:summary (:on-click (ajax :callback (lambda () (setf (disclosure-open-p self) (not (disclosure-open-p self))))
                              :update self))
      (h:text (translate-label (disclosure-summary self))))
    (h:div (:class "lt-disclosure-content")
      (render-component (disclosure-content self)))))

(defclass accordion (component updatable)
  ((sections :initarg :sections :initform '() :reader accordion-sections
             :documentation "Alist of (TITLE . COMPONENT).")
   (open :initarg :open :initform '() :accessor accordion-open
         :documentation "The indexes of the sections open now.  Replaced, never changed in place.")
   (multiple :initarg :multiple :initform nil :reader accordion-multiple-p))
  (:documentation "Sections, each a title (translated) that opens and closes
its component: :SECTIONS is an alist of (TITLE . COMPONENT).  Opening one
closes the others, unless :MULTIPLE is true.  :OPEN lists the indexes open
at first.  Like DISCLOSURE, it is made of details elements, so it works
without JavaScript, and remembers what is open."))

(defmethod states ((self accordion)) (list self))
(defmethod children ((self accordion)) (mapcar #'cdr (accordion-sections self)))

(defun toggle-section (accordion index)
  (let ((open (accordion-open accordion)))
    (setf (accordion-open accordion)
          (cond ((member index open) (remove index open))
                ((accordion-multiple-p accordion) (cons index open))
                (t (list index))))))

(defmethod render ((self accordion))
  (h:div (:class "lt-accordion")
    (loop for (title . component) in (accordion-sections self)
          for index from 0
          do (let ((index index))
               ;; A shared name makes browsers open one at a time without
               ;; JavaScript, too.
               (h:details (:class "lt-accordion-section" :open (and (member index (accordion-open self)) t)
                         :name (unless (accordion-multiple-p self) (component-id self)))
                 (h:summary (:on-click (ajax :callback (lambda () (toggle-section self index)) :update self))
                   (h:text (translate-label title)))
                 (h:div (:class "lt-accordion-panel")
                   (render-component component)))))))

;;; Dropdown menus and menu bars

(defclass dropdown-menu (component)
  ((label :initarg :label :reader menu-label)
   (items :initarg :items :initform '() :reader menu-items
          :documentation "List of (LABEL . ACTION), or :SEPARATOR."))
  (:documentation "A button, :LABEL (translated), that opens a list of
:ITEMS: each (LABEL . ACTION), ACTION a function called when it is chosen
or a URL to go to, or :SEPARATOR for a dividing line.  It is a details
element, so it opens without JavaScript; littoral.js closes it on Escape or
a click elsewhere, keeps one open at a time, and moves between items with
the arrow keys."))

(defun render-menu-item (item)
  (if (eq item :separator)
      (h:li (:class "lt-menu-separator" :role "separator"))
      (destructuring-bind (label . action) item
        (h:li ()
          (if (stringp action)
              (h:anchor (:href action) (h:text (translate-label label)))
              (h:anchor (:callback action) (h:text (translate-label label))))))))

(defun render-dropdown (label items)
  (h:details (:class "lt-dropdown")
    (h:summary () (h:text (translate-label label)))
    (h:ul ()
      (dolist (item items) (render-menu-item item)))))

(defmethod render ((self dropdown-menu))
  (render-dropdown (menu-label self) (menu-items self)))

(defclass menu-bar (component)
  ((items :initarg :items :initform '() :reader menu-items
          :documentation "List of (LABEL . ACTION) or (LABEL . ITEMS)."))
  (:documentation "A row of menus for finding one's way around: :ITEMS are
\(LABEL . ACTION), a link as in DROPDOWN-MENU, or (LABEL . ITEMS), a
dropdown of ITEMS.  It is a nav element, its links ordinary links."))

(defmethod render ((self menu-bar))
  (h:nav (:class "lt-menu-bar" :aria-label (translate "Menu"))
    (h:ul ()
      (dolist (item (menu-items self))
        (if (and (consp item) (listp (cdr item)) (cdr item))
            (h:li () (render-dropdown (car item) (cdr item)))
            (render-menu-item item))))))

;;; Tree

(defclass tree (component)
  ((roots :initarg :roots :reader tree-roots :documentation "The top-level items.")
   (children-function :initarg :children :reader tree-children-function
                      :documentation "Function of an item giving its child items.")
   (label-function :initarg :labels :initform #'princ-to-string :reader tree-label-function)
   (on-select :initarg :on-select :initform nil :reader tree-on-select
              :documentation "Function called with an item when its label is clicked.")
   (expanded :initform '() :accessor tree-expanded
             :documentation "The items whose children show.  Replaced, never changed in place.")
   (selected :initform nil :accessor tree-selected
             :documentation "The item whose label was clicked last, or NIL."))
  (:documentation "Items in a hierarchy, each expandable, like Seaside's WATree.
:ROOTS are the top-level items and :CHILDREN a function of an item giving
its child items (NIL for none).  :LABELS, a function of an item, gives the
text shown (PRINC-TO-STRING by default).  Clicking a label selects the item
and calls :ON-SELECT, when given, with it.  Items are compared with EQL."))

(defmethod states ((self tree))
  (list self))

(defun toggle-item (tree item)
  "Expand ITEM in TREE, or collapse it."
  (setf (tree-expanded tree)
        (if (member item (tree-expanded tree))
            (remove item (tree-expanded tree))
            (cons item (tree-expanded tree)))))

(defun expand-all (tree)
  "Expand every item of TREE that has children."
  (let ((all '()))
    (labels ((walk (item)
               (let ((kids (funcall (tree-children-function tree) item)))
                 (when kids
                   (push item all)
                   (mapc #'walk kids)))))
      (mapc #'walk (tree-roots tree)))
    (setf (tree-expanded tree) all)))

(defun render-tree-items (tree items)
  "Write ITEMS of TREE, and the children of those expanded."
  (h:ul (:class "lt-tree")
    (dolist (item items)
      (let* ((item item)
             (kids (funcall (tree-children-function tree) item))
             (open (member item (tree-expanded tree))))
        (h:li ()
          (if kids
              (h:anchor (:class "lt-tree-toggle" :title (if open (translate "Collapse") (translate "Expand"))
                       :aria-expanded (if open "true" "false")
                       :aria-label (let ((label (funcall (tree-label-function tree) item)))
                                     (if open (translate "Collapse ~A" label) (translate "Expand ~A" label)))
                       :callback (lambda () (toggle-item tree item)))
                (h:text (if open "▾" "▸")))
              (h:span (:class "lt-tree-leaf") "·"))
          (h:text " ")
          (h:anchor (:class (when (eq item (tree-selected tree)) "lt-selected")
                   :aria-current (when (eq item (tree-selected tree)) "true")
                   :callback (lambda ()
                               (setf (tree-selected tree) item)
                               (when (tree-on-select tree) (funcall (tree-on-select tree) item))))
            (h:text (funcall (tree-label-function tree) item)))
          (when (and kids open)
            (render-tree-items tree kids)))))))

(defmethod render ((self tree))
  (render-tree-items self (tree-roots self)))

;;; Autocomplete

(defclass suggestion-list (component updatable)
  ((field :initarg :field :reader suggestions-field))
  (:documentation "The suggestions under an AUTOCOMPLETE's input."))

(defclass autocomplete (component updatable)
  ((value :initarg :value :initform "" :accessor autocomplete-value
          :documentation "The text in the field.")
   (suggest :initarg :suggest :reader autocomplete-suggest
            :documentation "Function of the text typed giving a list of suggestions.")
   (label-function :initarg :labels :initform #'princ-to-string :reader autocomplete-labels)
   (minimum :initarg :minimum :initform 1 :reader autocomplete-minimum
            :documentation "Characters to type before suggesting.")
   (limit :initarg :limit :initform 8 :reader autocomplete-limit)
   (on-choose :initarg :on-choose :initform nil :reader autocomplete-on-choose
              :documentation "Function called with a suggestion when it is chosen.")
   (placeholder :initarg :placeholder :initform nil :reader autocomplete-placeholder)
   (input-id :initarg :input-id :initform nil :reader autocomplete-input-id)
   (suggestions :reader autocomplete-list))
  (:documentation "A text field suggesting completions as you type, over
AJAX.  :SUGGEST is a function of the text typed (trimmed) returning a list
of suggestions; it is called once :MINIMUM characters are typed (1 by
default), and the first :LIMIT suggestions (8) are shown, through :LABELS (a
function of a suggestion; PRINC-TO-STRING by default).  Choosing one puts
its label in the field and calls :ON-CHOOSE, when given, with it.  :VALUE is
the starting text, :INPUT-ID the input's element id and :PLACEHOLDER its
placeholder.  The field's text is submitted with its form, like any input."))

(defmethod initialize-instance :after ((self autocomplete) &key)
  (setf (slot-value self 'suggestions) (make-instance 'suggestion-list :field self)))

(defmethod children ((self autocomplete))
  (list (autocomplete-list self)))

(defun current-suggestions (field)
  "What FIELD suggests for its current text."
  (let ((typed (string-trim " " (autocomplete-value field))))
    (when (>= (length typed) (autocomplete-minimum field))
      (let ((all (funcall (autocomplete-suggest field) typed)))
        (subseq all 0 (min (length all) (autocomplete-limit field)))))))

(defun choose-suggestion (field suggestion)
  "Put SUGGESTION in FIELD and tell its ON-CHOOSE."
  (setf (autocomplete-value field) (funcall (autocomplete-labels field) suggestion))
  (when (autocomplete-on-choose field)
    (funcall (autocomplete-on-choose field) suggestion)))

(defmethod updatable-wrapper ((self suggestion-list))
  ;; Announce how many suggestions there are as they change.
  (values "div" '(:aria-live "polite")))

(defmethod render ((self suggestion-list))
  (let* ((field (suggestions-field self))
         (suggestions (current-suggestions field)))
    (when suggestions
      (h:span (:class "lt-visually-hidden")
        (h:text (translate-plural (length suggestions) "~D suggestion." "~D suggestions.")))
      (h:ul (:class "lt-suggestions")
        (dolist (suggestion suggestions)
          (let ((suggestion suggestion))
            (h:li ()
              (h:button (:class "lt-suggestion"
                       :on-click (ajax :callback (lambda () (choose-suggestion field suggestion))
                                       :update field))
                (h:text (funcall (autocomplete-labels field) suggestion))))))))))

(defmethod render ((self autocomplete))
  (h:div (:class "lt-autocomplete")
    (h:text-input (:id (autocomplete-input-id self)
                 :value (autocomplete-value self)
                 :placeholder (autocomplete-placeholder self)
                 :autocomplete "off"
                 :aria-autocomplete "list"
                 :aria-controls (component-id (autocomplete-list self))
                 :callback (lambda (v) (setf (autocomplete-value self) v))
                 :on-input (ajax-update (autocomplete-list self))))
    (render-component (autocomplete-list self))))

;;; Sortable list

(defclass sortable-list (component updatable)
  ((items :initarg :items :initform '() :accessor sortable-items
          :documentation "The items, in their current order.")
   (render-item :initarg :render-item :initform (lambda (item) (h:text item)) :reader sortable-renderer
                :documentation "Function writing one item.")
   (on-reorder :initarg :on-reorder :initform nil :reader sortable-on-reorder
               :documentation "Function called with the new list after every move."))
  (:documentation "A list of :ITEMS the user can reorder by dragging, or with
the up and down links beside each item (which work without JavaScript).
:RENDER-ITEM, a function of an item, writes it (as text by default), and
:ON-REORDER is called with the new list after every move."))

(defmethod states ((self sortable-list))
  (list self))

(defun reordered (list)
  "Tell LIST's ON-REORDER about its new order."
  (when (sortable-on-reorder list)
    (funcall (sortable-on-reorder list) (sortable-items list))))

(defun move-item (list from to)
  "Move the item at position FROM to position TO in LIST, a SORTABLE-LIST,
counting from 0, and call its ON-REORDER.  Does nothing when either is out
of range or they are the same."
  (let* ((items (sortable-items list))
         (count (length items)))
    (when (and (< -1 from count) (< -1 to count) (/= from to))
      (let* ((item (nth from items))
             (without (append (subseq items 0 from) (subseq items (1+ from)))))
        (setf (sortable-items list)
              (append (subseq without 0 to) (list item) (subseq without to)))
        (reordered list)))))

(defun apply-order (list order)
  "Reorder LIST by ORDER, a string of comma-separated old positions, as the
browser sends after a drag.  Anything malformed is ignored."
  (let* ((items (sortable-items list))
         (indices (ignore-errors (mapcar #'parse-integer (cl-ppcre:split "," order)))))
    (when (and indices
               (= (length indices) (length items))
               (equal (sort (copy-list indices) #'<) (alexandria:iota (length items))))
      (setf (sortable-items list) (mapcar (lambda (i) (nth i items)) indices))
      (reordered list))))

(defmethod render ((self sortable-list))
  (let ((count (length (sortable-items self))))
    (emit-tag "ol"
              (list :class "lt-sortable"
                    :sortable (ajax :value "this.dataset.order"
                                            :callback (lambda (order) (apply-order self order))
                                            :update self))
              (lambda ()
                (loop for item in (sortable-items self)
                      for index from 0
                      do (let ((index index) (item item))
                           (h:li (:draggable "true" :data-lt-index index)
                             (h:span (:class "lt-handle" :aria-hidden "true") "⠿")
                             (h:span (:class "lt-sortable-item") (funcall (sortable-renderer self) item))
                             (h:span (:class "lt-sortable-buttons")
                               (when (plusp index)
                                 (h:anchor (:title (translate "Move up") :aria-label (translate "Move item ~D up" (1+ index))
                                          :callback (lambda () (move-item self index (1- index))))
                                   "↑"))
                               (when (< index (1- count))
                                 (h:anchor (:title (translate "Move down") :aria-label (translate "Move item ~D down" (1+ index))
                                          :callback (lambda () (move-item self index (1+ index))))
                                   "↓"))))))))))

;;; Choosing a language

(defclass language-chooser (component)
  ((languages :initarg :languages :initform nil :reader chooser-languages
              :documentation "Codes to offer; NIL for the application's."))
  (:documentation "Links to show the session in each language offered,
each named in its own language; the current one is not a link.  :LANGUAGES
lists the codes to offer; by default the application's LANGUAGE and
LANGUAGES."))

(defmethod render ((self language-chooser))
  (let ((current (current-language)))
    (h:nav (:class "lt-languages" :aria-label (translate "Language"))
      (h:ul ()
        (dolist (code (or (chooser-languages self)
                          (application-offered-languages *application*)))
          (let ((code code))
            (h:li (:lang code)
              (if (string-equal code current)
                  (h:strong (:aria-current "true") (h:text (language-display-name code)))
                  (h:anchor (:callback (lambda () (set-language code)) :hreflang code)
                    (h:text (language-display-name code)))))))))))
