;;;; widgets-more.lisp — tabs, navigation, trees, autocomplete, sortable lists

(in-package #:littoral)

;;; Tab panel and navigation

(defclass tab-panel (component)
  ((tabs :initarg :tabs :initform '() :accessor panel-tabs
         :documentation "Alist of (LABEL . COMPONENT).")
   (selected :initarg :selected :initform 0 :accessor panel-selected
             :documentation "Index of the tab shown."))
  (:documentation "Shows one of several components, chosen by a row of tabs,
like Seaside's WATabPanel."))

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
  "Show the tab of PANEL labelled LABEL."
  (let ((index (position label (panel-tabs panel) :key #'first :test #'equal)))
    (when index (setf (panel-selected panel) index))))

(defun render-tab-links (panel)
  "Write the links to PANEL's tabs, the current one not a link."
  (loop for (label) in (panel-tabs panel)
        for index from 0
        do (let ((index index))
             (li (:class (when (= index (panel-selected panel)) "lt-active"))
               (if (= index (panel-selected panel))
                   (span (:aria-current "page") (text (translate-label label)))
                   (anchor (:callback (lambda () (setf (panel-selected panel) index)))
                     (text (translate-label label))))))))

(defmethod render ((self tab-panel))
  (div (:class "lt-tab-panel")
    (nav (:aria-label (translate "Tabs")) (ul (:class "lt-tabs") (render-tab-links self)))
    (div (:class "lt-tab-body")
      (let ((tab (selected-tab self)))
        (when tab (render-component tab))))))

(defmethod render ((self navigation))
  (div (:class "lt-navigation")
    (nav () (ul (:class "lt-menu") (render-tab-links self)))
    (div (:class "lt-navigation-body")
      (let ((tab (selected-tab self)))
        (when tab (render-component tab))))))

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
   (selected :initform nil :accessor tree-selected))
  (:documentation "Items in a hierarchy, each expandable, like Seaside's WATree."))

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
  (ul (:class "lt-tree")
    (dolist (item items)
      (let* ((item item)
             (kids (funcall (tree-children-function tree) item))
             (open (member item (tree-expanded tree))))
        (li ()
          (if kids
              (anchor (:class "lt-tree-toggle" :title (if open (translate "Collapse") (translate "Expand"))
                       :aria-expanded (if open "true" "false")
                       :aria-label (format nil "~:[Expand~;Collapse~] ~A" open
                                           (funcall (tree-label-function tree) item))
                       :callback (lambda () (toggle-item tree item)))
                (text (if open "▾" "▸")))
              (span (:class "lt-tree-leaf") "·"))
          (text " ")
          (anchor (:class (when (eq item (tree-selected tree)) "lt-selected")
                   :aria-current (when (eq item (tree-selected tree)) "true")
                   :callback (lambda ()
                               (setf (tree-selected tree) item)
                               (when (tree-on-select tree) (funcall (tree-on-select tree) item))))
            (text (funcall (tree-label-function tree) item)))
          (when (and kids open)
            (render-tree-items tree kids)))))))

(defmethod render ((self tree))
  (render-tree-items self (tree-roots self)))

;;; Autocomplete

(defclass suggestion-list (component updatable)
  ((field :initarg :field :reader suggestions-field))
  (:documentation "The suggestions under an AUTOCOMPLETE's input."))

(defclass autocomplete (component updatable)
  ((value :initarg :value :initform "" :accessor autocomplete-value)
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
  (:documentation "A text field suggesting completions as you type."))

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
      (span (:class "lt-visually-hidden")
        (text (format nil "~D suggestion~:P." (length suggestions))))
      (ul (:class "lt-suggestions")
        (dolist (suggestion suggestions)
          (let ((suggestion suggestion))
            (li ()
              (button (:class "lt-suggestion"
                       :on-click (ajax :callback (lambda () (choose-suggestion field suggestion))
                                       :update field))
                (text (funcall (autocomplete-labels field) suggestion))))))))))

(defmethod render ((self autocomplete))
  (div (:class "lt-autocomplete")
    (text-input (:id (autocomplete-input-id self)
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
  ((items :initarg :items :initform '() :accessor sortable-items)
   (render-item :initarg :render-item :initform (lambda (item) (text item)) :reader sortable-renderer
                :documentation "Function writing one item.")
   (on-reorder :initarg :on-reorder :initform nil :reader sortable-on-reorder
               :documentation "Function called with the new list after every move."))
  (:documentation "A list the user can reorder by dragging, or with the
up and down buttons beside each item (which work without JavaScript)."))

(defmethod states ((self sortable-list))
  (list self))

(defun reordered (list)
  "Tell LIST's ON-REORDER about its new order."
  (when (sortable-on-reorder list)
    (funcall (sortable-on-reorder list) (sortable-items list))))

(defun move-item (list from to)
  "Move the item at FROM to position TO in LIST."
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
                           (li (:draggable "true" :data-lt-index index)
                             (span (:class "lt-handle" :aria-hidden "true") "⠿")
                             (span (:class "lt-sortable-item") (funcall (sortable-renderer self) item))
                             (span (:class "lt-sortable-buttons")
                               (when (plusp index)
                                 (anchor (:title (translate "Move up") :aria-label (translate "Move item ~D up" (1+ index))
                                          :callback (lambda () (move-item self index (1- index))))
                                   "↑"))
                               (when (< index (1- count))
                                 (anchor (:title (translate "Move down") :aria-label (translate "Move item ~D down" (1+ index))
                                          :callback (lambda () (move-item self index (1+ index))))
                                   "↓"))))))))))

;;; Choosing a language

(defclass language-chooser (component)
  ((languages :initarg :languages :initform nil :reader chooser-languages
              :documentation "Codes to offer; NIL for the application's."))
  (:documentation "Links to show the session in each language offered,
each named in its own language; the current one is not a link."))

(defmethod render ((self language-chooser))
  (let ((current (current-language)))
    (nav (:class "lt-languages" :aria-label (translate "Language"))
      (ul ()
        (dolist (code (or (chooser-languages self)
                          (application-offered-languages *application*)))
          (let ((code code))
            (li (:lang code)
              (if (string-equal code current)
                  (strong (:aria-current "true") (text (language-display-name code)))
                  (anchor (:callback (lambda () (set-language code)) :hreflang code)
                    (text (language-display-name code)))))))))))
