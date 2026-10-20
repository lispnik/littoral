;;;; The examples for the widgets: batched lists, reports, tabs, trees, autocomplete, sortable lists.

;;;; Example: littoral:batched-list littoral:batch littoral:batch-items littoral:batch-size littoral:batch-page littoral:go-to-page
;;; A batched list keeps the items and the page; `batch` is what the current page holds.  `go-to-page` keeps the page in range.
(let ((list (make-instance 'batched-list :items (loop for i from 1 to 25 collect i) :batch-size 10)))
  (go-to-page list 99)
  (list (batch-page list) (batch list) (batch-size list) (length (batch-items list))))
;; ⇒ (2 (21 22 23 24 25) 10 25)

;;;; Example: littoral:batched-list littoral:batch
;;; In a page: render the current batch yourself, then render the batched list for its page links.
(defclass fruit-list (component)
  ((pages :initform (make-instance 'batched-list :batch-size 2
                                                 :items '("Apple" "Banana" "Cherry" "Damson" "Elder"))
          :reader pages)))
(defmethod children ((self fruit-list))
  (list (pages self)))
(defmethod render ((self fruit-list))
  (h:ul () (dolist (fruit (batch (pages self))) (h:li () (h:text fruit))))
  (render-component (pages self)))
(with-fresh-applications (("/fruit" 'fruit-list :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/fruit")
    (click b "Next »")
    (body-text b)))
;; ⇒ "Cherry Damson « Previous123Next »"

;;;; Example: littoral:report littoral:column littoral:sort-by
;;; A report shows rows in columns; a column's value is a function of the row.  Clicking a heading sorts by it, and clicking it again reverses the order.
(defclass planets (report) ()
  (:default-initargs
   :rows '(("Mercury" 0.39) ("Venus" 0.72) ("Earth" 1.0) ("Mars" 1.52))
   :columns (list (column "Planet" #'first)
                  (column "Distance (AU)" #'second :class "number"))))
(with-fresh-applications (("/planets" 'planets :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/planets")
    (click b "Planet")
    (click b "Planet")
    (body-text b)))
;; ⇒ "Planet ▼ Distance (AU) Venus 0.72 Mercury 0.39 Mars 1.52 Earth 1.0"

;;;; Example: littoral:report littoral:column littoral:report-rows
;;; Rows given as a function are fetched on every render, so the report follows its data.  A column with no value and its own `:render` can hold links; `:sortable` `nil` leaves its heading plain.
(defclass order-book (component)
  ((orders :initform (list "Tea" "Scones" "Jam") :accessor orders)
   (report :reader order-report)))
(defmethod initialize-instance :after ((self order-book) &key)
  (setf (slot-value self 'report)
        (make-instance 'report
                       :rows (lambda () (orders self))
                       :columns (list (column "Order" #'identity)
                                      (column "" nil :sortable nil
                                                     :render (lambda (row value)
                                                               (declare (ignore value))
                                                               (h:anchor (:callback (lambda () (setf (orders self) (remove row (orders self)))))
                                                                 "cancel")))))))
(defmethod states ((self order-book))
  (list self))
(defmethod children ((self order-book))
  (list (order-report self)))
(defmethod render ((self order-book))
  (render-component (order-report self)))
(with-fresh-applications (("/orders" 'order-book :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/orders")
    (click-nth b "cancel" 1)
    (body-text b)))
;; ⇒ "Order Tea cancel Jam cancel"

;;;; Example: littoral:report-rows littoral:report-columns
;;; A report's rows and columns can be replaced; the next render shows the new ones.
(let ((report (make-instance 'report :rows '(("Tea" 2)) :columns (list (column "Item" #'first)))))
  (setf (report-columns report) (append (report-columns report) (list (column "Qty" #'second)))
        (report-rows report) '(("Tea" 2) ("Jam" 1)))
  (list (length (report-columns report)) (length (report-rows report))))
;; ⇒ (2 2)

;;;; Example: littoral:report
;;; `:batch-size` pages the report; `:row-class` gives each row a CSS class.
(defclass squares (report) ()
  (:default-initargs
   :rows (loop for n from 1 to 7 collect n)
   :columns (list (column "N" #'identity) (column "N²" (lambda (n) (* n n))))
   :row-class (lambda (n) (when (evenp n) "even"))
   :batch-size 3))
(with-fresh-applications (("/squares" 'squares :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/squares")
    (click b "3")
    (body-text b)))
;; ⇒ "N N² 7 49 « Previous123Next »"

;;;; Example: littoral:tab-panel littoral:panel-tabs
;;; A tab panel shows one component of several, picked by a row of tabs; the current tab is not a link.
(defclass note (component)
  ((words :initarg :words :reader words)))
(defmethod render ((self note))
  (h:p () (h:text (words self))))
(defclass settings (tab-panel) ()
  (:default-initargs
   :tabs (list (cons "Profile" (make-instance 'note :words "Your name and photo."))
               (cons "Security" (make-instance 'note :words "Passwords and keys.")))))
(with-fresh-applications (("/settings" 'settings :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/settings")
    (click b "Security")
    (list (body-text b) (find-link b "Security"))))
;; ⇒ ("Profile Security Passwords and keys." NIL)

;;;; Example: littoral:select-tab littoral:selected-tab littoral:panel-selected
;;; Choosing a tab from code: `select-tab` finds it by label.
(let* ((profile (make-instance 'component))
       (security (make-instance 'component))
       (panel (make-instance 'tab-panel :tabs (list (cons "Profile" profile) (cons "Security" security)))))
  (select-tab panel "Security")
  (list (panel-selected panel) (eq (selected-tab panel) security) (select-tab panel "Billing")))
;; ⇒ (1 T NIL)

;;;; Example: littoral:navigation
;;; The same as a menu beside the content.
(defclass chapter (component)
  ((words :initarg :words :reader words)))
(defmethod render ((self chapter))
  (h:p () (h:text (words self))))
(defclass handbook (navigation) ()
  (:default-initargs
   :tabs (list (cons "Start" (make-instance 'chapter :words "Welcome."))
               (cons "Install" (make-instance 'chapter :words "Run make.")))))
(with-fresh-applications (("/handbook" 'handbook :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/handbook")
    (click b "Install")
    (list (body-text b) (not (null (search "lt-menu" (browser-html b)))))))
;; ⇒ ("Start Install Run make." T)

;;;; Example: littoral:tree littoral:tree-selected
;;; A tree needs its roots and a function giving an item's children.  A toggle (▸) expands an item; clicking a label selects it and calls `:on-select`.
(defparameter *kingdoms* '((:animals :cats :dogs) (:plants :trees)))
(defclass kingdoms (component)
  ((tree :reader kingdom-tree)
   (chosen :initform nil :accessor chosen)))
(defmethod initialize-instance :after ((self kingdoms) &key)
  (setf (slot-value self 'tree)
        (make-instance 'tree :roots '(:animals :plants)
                             :children (lambda (item) (rest (assoc item *kingdoms*)))
                             :labels #'string-capitalize
                             :on-select (lambda (item) (setf (chosen self) item)))))
(defmethod states ((self kingdoms))
  (list self))
(defmethod children ((self kingdoms))
  (list (kingdom-tree self)))
(defmethod render ((self kingdoms))
  (render-component (kingdom-tree self))
  (when (chosen self) (h:p () "Chose " (h:text (string-capitalize (chosen self))))))
(with-fresh-applications (("/kingdoms" 'kingdoms :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/kingdoms")
    (click b "▸")
    (click b "Dogs")
    (body-text b)))
;; ⇒ "▾ Animals · Cats · Dogs ▸ Plants Chose Dogs"

;;;; Example: littoral:toggle-item littoral:expand-all littoral:tree-expanded
;;; Expanding and collapsing from code.
(let ((tree (make-instance 'tree :roots '(:animals :plants)
                                 :children (lambda (item)
                                             (rest (assoc item '((:animals :cats :dogs) (:plants :trees))))))))
  (expand-all tree)
  (toggle-item tree :plants)
  (tree-expanded tree))
;; ⇒ (:ANIMALS)

;;;; Example: littoral:autocomplete littoral:autocomplete-value
;;; An autocomplete suggests completions as you type (over AJAX, as littoral.js sends them); its value is the text in the field.
(defparameter *colours* '("Teal" "Tomato" "Turquoise" "Violet"))
(defclass colour-form (component)
  ((field :initform (make-instance 'autocomplete
                                   :input-id "colour"
                                   :suggest (lambda (typed)
                                              (remove-if-not (lambda (c) (eql 0 (search typed c :test #'char-equal)))
                                                             *colours*)))
          :reader colour-field)
   (picked :initform nil :accessor picked)))
(defmethod states ((self colour-form))
  (list self))
(defmethod children ((self colour-form))
  (list (colour-field self)))
(defmethod render ((self colour-form))
  (h:form ()
    (render-component (colour-field self))
    (h:submit-button (:callback (lambda () (setf (picked self) (autocomplete-value (colour-field self)))))
      "Pick"))
  (when (picked self) (h:p () "Picked " (h:text (picked self)))))
(with-fresh-applications (("/colours" 'colour-form :mode :deployment))
  (let* ((b (make-instance 'browser))
         (field (progn (visit b "/colours") (element-name b "colour")))
         (typing (first (ajax-specs b "on-input")))
         (json (ajax-request b (first typing) (rest typing) :fields (list (cons field "t")))))
    (fill-in b "colour" "Teal")
    (press b "Pick")
    (list (count-if (lambda (c) (search c json)) *colours*)
          (not (null (has-text-p b "Picked Teal"))))))
;; ⇒ (3 T)

;;;; Example: littoral:sortable-list littoral:sortable-items littoral:move-item
;;; `move-item` reorders from code and calls `:on-reorder` with the new order.
(let* ((seen nil)
       (list (make-instance 'sortable-list :items '("Wash" "Dry" "Fold")
                                           :on-reorder (lambda (items) (setf seen items)))))
  (move-item list 2 0)
  (list (sortable-items list) seen))
;; ⇒ (("Fold" "Wash" "Dry") ("Fold" "Wash" "Dry"))

;;;; Example: littoral:sortable-list
;;; In a page, each item has up and down links (and can be dragged, with littoral.js).
(defclass chores (sortable-list) ()
  (:default-initargs :items '("Wash" "Dry" "Fold")))
(with-fresh-applications (("/chores" 'chores :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/chores")
    (click-nth b "↓" 0)
    (body-text b)))
;; ⇒ "⠿Dry↓ ⠿Wash↑↓ ⠿Fold↑"

;;;; Example: littoral:report-csv littoral:csv-text
;;; `report-csv` gives every row, not just the page shown, in the report's order, under the titles of the columns that have values.  With `:csv-filename` the report also shows a Download CSV link.  CSV-TEXT quotes what needs quoting and keeps cells from starting spreadsheet formulas.
(let ((report (make-instance 'report :rows '(("Ada" 36) ("=HYPERLINK(\"x\")" 1))
                                     :columns (list (column "Name" #'first) (column "Age" #'second)))))
  ;; Its lines end with CRLF, as RFC 4180 says.
  (cl-ppcre:split "\\r\\n" (report-csv report)))
;; ⇒ ("Name,Age" "Ada,36" "\"'=HYPERLINK(\"\"x\"\")\",1")

;;;; Example: littoral:send-download
;;; From a callback, answer the request with a file for the browser to save, instead of the next page; the page stays as it was.
(defclass export-button (component) ())
(defmethod render ((self export-button))
  (h:anchor (:callback (lambda () (send-download "id,total" :filename "orders.csv" :content-type "text/csv")))
    "Export"))
(with-fresh-applications (("/export" 'export-button :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/export")
    (multiple-value-bind (status headers body) (raw-request b :get (find-link b "Export"))
      (list status (getf headers :content-disposition) body))))
;; ⇒ (200 "attachment; filename=\"orders.csv\"" "id,total")
