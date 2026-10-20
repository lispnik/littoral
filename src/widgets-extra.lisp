;;;; widgets-extra.lisp — a data grid, charts, a calendar, a kanban board, Markdown
;;;;
;;;;   (make-instance 'data-grid :description 'contact :rows (lambda () (all-contacts))
;;;;                             :on-save (lambda (contact) (save contact)))
;;;;   (bar-chart '(("Mon" . 3) ("Tue" . 7)) :title "Orders")      ; inline SVG
;;;;   (make-instance 'calendar :events (lambda () '(((2026 10 9) . "Release"))))
;;;;   (make-instance 'kanban :columns '(("To do" "A" "B") ("Done" "C")))
;;;;   (markdown-html "Some *Markdown*")                            ; safe HTML
;;;;
;;;; and the description field kind :MARKDOWN.

(in-package #:littoral)

(define-condition edit-conflict (error)
  ((object :initarg :object :initform nil :reader edit-conflict-object))
  (:report "Someone else changed this meanwhile.")
  (:documentation "What an editor's :ON-SAVE signals when the object was
changed by someone else since it was read: IN-PLACE-EDITOR and DATA-GRID
then say so instead of failing.  littoral.db's STALE-OBJECT is one."))

(setf (documentation 'edit-conflict-object 'function)
      "The object someone else changed, as the EDIT-CONFLICT's :OBJECT gave it, or NIL.")

(defun conflict-text (field text)
  "TEXT, FIELD's value as someone else left it, for a sentence."
  (if (typep field 'password-field) "…" (if (string= text "") (translate "nothing") text)))


;;; A data grid: a description's objects, filtered, sorted, paged, edited in place

(defclass data-grid (component updatable)
  ((description :initarg :description :reader grid-description)
   (rows :initarg :rows :initform '() :reader grid-rows-designator
         :documentation "A list, or a function returning one on every render.")
   (field-names :initarg :fields :initform nil :reader grid-field-names
                :documentation "The fields to show, by name; NIL for those shown in reports.")
   (on-save :initarg :on-save :initform nil :reader grid-on-save
            :documentation "Called with an object after an edit is written to it.")
   (page-size :initarg :page-size :initform 10 :reader grid-page-size)
   (page :initform 0 :accessor grid-page)
   (sort-field :initform nil :accessor grid-sort-field)
   (descending :initform nil :accessor grid-descending-p)
   (filters :initform '() :accessor grid-filters :documentation "(FIELD-NAME . TEXT), replaced, never changed.")
   (csv-filename :initarg :csv-filename :initform nil :reader grid-csv-filename
                 :documentation "When given, the name of the CSV file a Download CSV link gives.")
   (row-key :initarg :row-key :initform #'identity :reader grid-row-key
            :documentation "Function of a row giving what identifies it, compared with EQUAL.")
   (editing :initform nil :accessor grid-editing :documentation "The object being edited, or NIL.")
   (texts :initform '() :accessor grid-texts :documentation "(FIELD-NAME . TEXT) typed into the row being edited.")
   (originals :initform '() :accessor grid-originals
              :documentation "(FIELD-NAME . TEXT): the row being edited as it was when editing began.")
   (problems :initform '() :accessor grid-problems)
   (virtual :initarg :virtual :initform nil :reader grid-virtual
            :documentation "NIL to page the rows, or how many rows to show at once, scrolling through the rest.")
   (rows-part :initform nil :reader grid-rows-part)
   (builder :initform nil :reader data-grid-filter
            :documentation "The grid's FILTER-BUILDER, when it has :CONDITIONS."))
  (:documentation "A table of a description's objects: a filter box per column,
sorting by column, paging, and editing a row in place with the description's
own inputs and validation.  :DESCRIPTION names the description (anything
FIND-DESCRIPTION takes) and :ROWS gives the objects (a list, or a function
returning one, called on every render).  :FIELDS lists the field names to
show; by default those in reports, without password fields.  :PAGE-SIZE is
the rows per page (10).  After an edit is written to an object, :ON-SAVE is
called with it.  :ROW-KEY, a function of a row (IDENTITY by default; use
OBJECT-ID for rows read afresh from a database), says which rows are the
same.  A field someone else changed while the row was being edited is
reported rather than overwritten, and saving again replaces it; so is an
EDIT-CONFLICT signalled by :ON-SAVE (as STALE-OBJECT is).  :CSV-FILENAME
adds a Download CSV link (see DATA-GRID-CSV).  Filtering, sorting and
paging go over AJAX.

:VIRTUAL, a number of rows, shows that many at once in a box that scrolls
through all of them instead of paging, writing only the rows near those on
screen and fetching others as it scrolls, so a table of thousands of rows
stays quick.  Rows are then one line high.  Without JavaScript it pages.

:CONDITIONS T adds a FILTER-BUILDER above the table, for conditions such as
\"Birthday is before 1950-01-01\"; a list of (FIELD-NAME OPERATOR TEXT)
starts it with those.  The grid shows only the rows that pass."))

(defmethod initialize-instance :after ((self data-grid) &key conditions)
  (when (grid-virtual self)
    (setf (slot-value self 'rows-part) (make-instance 'grid-rows :grid self)))
  (when conditions
    (setf (slot-value self 'builder)
          (make-instance 'filter-builder :description (grid-description self) :fields (grid-field-names self)
                                         :conditions (if (listp conditions) conditions '())
                                         :update self :on-change (lambda () (reset-grid-position self))))))

(defmethod children ((self data-grid))
  (remove nil (list (data-grid-filter self) (grid-rows-part self))))

(defun data-grid-csv (grid)
  "GRID's rows as CSV: those its filters let through, every page, in its
current order, each field as the grid shows it."
  (let ((fields (grid-fields grid)))
    (csv-text (mapcar (lambda (f) (translate (field-label f))) fields)
              (mapcar (lambda (row) (mapcar (lambda (f) (format-field f (field-value f row))) fields))
                      (grid-visible-rows grid)))))

(defmethod states ((self data-grid)) (list self))

(defun grid-fields (grid)
  (let ((description (find-description (grid-description grid))))
    (if (grid-field-names grid)
        (mapcar (lambda (name) (find-field description name)) (grid-field-names grid))
        (remove-if-not (lambda (f) (and (field-in-report-p f) (not (field-hidden-p f))
                                        (not (typep f 'password-field))))
                       (description-fields description)))))

(defun grid-all-rows (grid)
  (let ((rows (grid-rows-designator grid)))
    (if (functionp rows) (funcall rows) rows)))

(defun grid-visible-rows (grid)
  "The rows that pass every filter, in the chosen order."
  (let* ((fields (grid-fields grid))
         (rows (remove-if-not
                (lambda (row)
                  (every (lambda (filter)
                           (let ((field (find (car filter) fields :key #'field-name)))
                             (or (null field) (string= (cdr filter) "")
                                 (search (cdr filter) (format-field field (field-value field row)) :test #'char-equal))))
                         (grid-filters grid)))
                (let ((rows (grid-all-rows grid))
                      (builder (data-grid-filter grid)))
                  (if builder
                      (remove-if-not (lambda (row) (filter-matches-p builder row)) rows)
                      rows)))))
    (let ((field (and (grid-sort-field grid) (find (grid-sort-field grid) fields :key #'field-name))))
      (if field
          (let ((sorted (stable-sort (copy-list rows) #'value<
                                     :key (lambda (row) (let ((v (field-value field row)))
                                                          (if (or (realp v) (null v)) v (format-field field v)))))))
            (if (grid-descending-p grid) (reverse sorted) sorted))
          rows))))

(defun reset-grid-position (grid)
  "Show GRID's first page, or scroll a virtual one back to its top."
  (setf (grid-page grid) 0)
  (when (grid-rows-part grid)
    (setf (rows-start (grid-rows-part grid)) 0)))

(defun set-grid-filter (grid name text)
  (setf (grid-filters grid) (acons name text (remove name (grid-filters grid) :key #'car)))
  (reset-grid-position grid))

(defun sort-grid (grid name)
  (if (eq (grid-sort-field grid) name)
      (setf (grid-descending-p grid) (not (grid-descending-p grid)))
      (setf (grid-sort-field grid) name (grid-descending-p grid) nil))
  (when (grid-rows-part grid)
    (setf (rows-start (grid-rows-part grid)) 0)))

(defun row-texts (grid row)
  "(FIELD-NAME . TEXT) for each of GRID's fields of ROW."
  (mapcar (lambda (field) (cons (field-name field) (format-field field (field-value field row))))
          (grid-fields grid)))

(defun same-row-p (grid a b)
  (equal (funcall (grid-row-key grid) a) (funcall (grid-row-key grid) b)))

(defun current-row (grid row)
  "ROW as GRID's rows hold it now (a fresh copy, for rows read afresh), or ROW."
  (or (find-if (lambda (r) (same-row-p grid r row)) (grid-all-rows grid)) row))

(defun edit-grid-row (grid row)
  (setf (grid-editing grid) row
        (grid-problems grid) '()
        (grid-texts grid) (row-texts grid row)
        (grid-originals grid) (row-texts grid row)))

(defun save-grid-row (grid)
  "Check the row being edited; write it and call ON-SAVE, or keep the problems."
  (let* ((row (grid-editing grid))
         (current (current-row grid row))
         (values '()) (problems '()))
    (dolist (field (grid-fields grid))
      (let* ((name (field-name field))
             (text (or (cdr (assoc name (grid-texts grid))) ""))
             (original (cdr (assoc name (grid-originals grid))))
             (now (format-field field (field-value field current))))
        (if (and original (string/= now original) (string/= now text))
            ;; Changed by someone else since editing began: say so, once.
            (progn
              (push (cons name (translate "Someone else changed this to “~A” meanwhile. Save again to replace it."
                                          (conflict-text field now)))
                    problems)
              (setf (grid-originals grid) (acons name now (grid-originals grid))))
            (handler-case
                (let* ((value (parse-field field text))
                       (problem (check-field field value)))
                  (if problem
                      (push (cons name problem) problems)
                      (push (cons field value) values)))
              (field-error (e) (push (cons name (field-error-message e)) problems))))))
    (if problems
        (setf (grid-problems grid) problems)
        (let ((before (mapcar (lambda (pair) (cons (car pair) (field-value (car pair) row))) values)))
          (loop for (field . value) in values do (setf (field-value field row) value))
          (handler-case
              (progn
                (when (grid-on-save grid) (funcall (grid-on-save grid) row))
                (setf (grid-editing grid) nil (grid-problems grid) '()))
            (edit-conflict ()
              ;; Nothing was saved: put the row back, and edit it as it is now.
              (loop for (field . value) in before do (setf (field-value field row) value))
              (let ((now (current-row grid row)))
                (setf (grid-editing grid) now
                      (grid-originals grid) (row-texts grid now)
                      (grid-problems grid)
                      (list (cons :row (translate "Someone else changed this row meanwhile; nothing was saved. Save again to replace their changes.")))))))))))

(defun render-grid-row (grid row fields &optional index)
  "Write GRID's row for ROW, as an editor when it is the row being edited.
INDEX, when given, is its aria-rowindex."
  (if (and (grid-editing grid) (same-row-p grid row (grid-editing grid)))
      (tr (:class "lt-grid-editing" :aria-rowindex index)
        (dolist (field fields)
          (let* ((name (field-name field))
                 (problem (cdr (assoc name (grid-problems grid)))))
            (td ()
              (let ((*next-field-attributes* (list :aria-label (translate (field-label field))
                                                   :aria-invalid (when problem "true"))))
                (render-field-input field (format nil "grid-~(~A~)" name)
                                    (or (cdr (assoc name (grid-texts grid))) "")
                                    (lambda (text) (setf (grid-texts grid)
                                                         (acons name text (remove name (grid-texts grid) :key #'car))))))
              (when problem (div (:class "lt-validation-error") (text problem))))))
        (td (:class "lt-grid-actions")
          (let ((problem (cdr (assoc :row (grid-problems grid)))))
            (when problem (div (:class "lt-validation-error") (text problem))))
          (submit-button (:callback (lambda () (save-grid-row grid))) (translate "Save"))
          (cancel-button (:callback (lambda () (setf (grid-editing grid) nil))) (translate "Cancel"))))
      (tr (:aria-rowindex index)
        (dolist (field fields)
          (td () (render-field-value field (field-value field row))))
        (td (:class "lt-grid-actions")
          (anchor (:callback (lambda () (edit-grid-row grid row))) (translate "Edit"))))))

(defun render-nothing-row (fields)
  (tr () (td (:colspan (princ-to-string (1+ (length fields)))) (translate "Nothing matches."))))

;;; A virtual grid's rows: only those near the ones on screen are written

(defclass grid-rows (component updatable)
  ((grid :initarg :grid :reader rows-grid)
   (start :initform 0 :accessor rows-start :documentation "The position of the first row written."))
  (:documentation "The body of a DATA-GRID with :VIRTUAL rows."))

(defmethod updatable-wrapper ((self grid-rows)) (values "tbody" '(:class "lt-grid-rows")))
(defmethod states ((self grid-rows)) (list self))

(defun grid-window (grid)
  "How many rows a virtual GRID writes at once: three screens' worth."
  (* 3 (grid-virtual grid)))

(defun grid-rows-span (part total)
  "The first row PART writes, and the one after its last, of TOTAL."
  (let* ((window (grid-window (rows-grid part)))
         (start (max 0 (min (rows-start part) (- total window)))))
    (values start (min total (+ start window)))))

(defun spacer-style (rows)
  (format nil "height: calc(~D * var(--lt-grid-row))" rows))

(defmethod render ((self grid-rows))
  (let* ((grid (rows-grid self))
         (fields (grid-fields grid))
         (rows (grid-visible-rows grid))
         (total (length rows))
         (columns (princ-to-string (1+ (length fields)))))
    (multiple-value-bind (start end) (grid-rows-span self total)
      ;; Spacers stand for the rows not written, so the scroll bar is right.
      (tr (:class "lt-grid-spacer" :aria-hidden "true" :style (spacer-style start)
           :data-lt-start start :data-lt-total total :data-lt-window (grid-window grid)
           :data-lt-visible (grid-virtual grid)
           :virtual (ajax :callback (lambda (value)
                                      (let ((n (ignore-errors (parse-integer value))))
                                        (when n (setf (rows-start self) (max 0 n)))))
                          :update self :value "this.getAttribute('data-lt-want')"))
        (td (:colspan columns)))
      (if (zerop total)
          (render-nothing-row fields)
          (loop for row in (subseq rows start end)
                for index from (+ start 3)
                do (render-grid-row grid row fields index)))
      (tr (:class "lt-grid-spacer" :aria-hidden "true" :style (spacer-style (- total end)))
        (td (:colspan columns))))))

(defun render-virtual-pager (grid total)
  "Links to the rows before and after, for pages without JavaScript, which
can't scroll a virtual grid to them."
  (let ((part (grid-rows-part grid)))
    (multiple-value-bind (start end) (grid-rows-span part total)
      (emit-tag "noscript" '()
                (lambda ()
                  (raw "<style>.lt-grid-spacer { display: none; }</style>")
                  (when (plusp total)
                    (text (format nil " ~A " (translate "Rows ~D–~D of ~D" (1+ start) end total))))
                  (when (plusp start)
                    (anchor (:callback (lambda () (setf (rows-start part) (max 0 (- start (grid-window grid)))))
                             :rel "prev")
                      (translate "« Previous")))
                  (when (< end total)
                    (text " ")
                    (anchor (:callback (lambda () (setf (rows-start part) end)) :rel "next")
                      (translate "Next »"))))))))

(defmethod render ((self data-grid))
  (let* ((fields (grid-fields self))
         (virtual (grid-virtual self))
         (rows (grid-visible-rows self))
         (pages (max 1 (ceiling (length rows) (grid-page-size self))))
         (page (min (grid-page self) (1- pages))))
    (when (data-grid-filter self)
      (render-component (data-grid-filter self)))
    (form (:class "lt-grid")
      (div (:class (list "lt-grid-scroll" (when virtual "lt-grid-virtual"))
            :style (when virtual (format nil "--lt-grid-visible: ~D" virtual))
            :tabindex "0" :role "region" :aria-label (translate "Table"))
        (table (:class "lt-table" :aria-rowcount (when virtual (+ 2 (length rows))))
          (thead ()
            (tr (:aria-rowindex (when virtual 1))
              (dolist (field fields)
                (let ((name (field-name field)))
                  (th (:aria-sort (when (eq name (grid-sort-field self))
                                    (if (grid-descending-p self) "descending" "ascending")))
                    (anchor (:on-click (ajax :callback (lambda () (sort-grid self name)) :update self)
                             :href "#")
                      (text (translate (field-label field)))
                      (when (eq name (grid-sort-field self))
                        (text (if (grid-descending-p self) " ▼" " ▲")))))))
              (th () (span (:class "lt-visually-hidden") (translate "Actions"))))
            (tr (:class "lt-grid-filters" :aria-rowindex (when virtual 2))
              (dolist (field fields)
                (let ((name (field-name field)))
                  (td ()
                    (text-input (:value (or (cdr (assoc name (grid-filters self))) "")
                                 :label (translate "Filter ~A" (translate (field-label field)))
                                 :placeholder (translate "Filter")
                                 :callback (lambda (v) (set-grid-filter self name v))
                                 :on-input (ajax-update self))))))
              (td ())))
          (if virtual
              (render-component (grid-rows-part self))
              (let ((shown (subseq rows (min (length rows) (* page (grid-page-size self)))
                                   (min (length rows) (* (1+ page) (grid-page-size self))))))
                (tbody ()
                  (if (null shown)
                      (render-nothing-row fields)
                      (dolist (row shown) (render-grid-row self row fields))))))))
      (div (:class "lt-batch")
        (text (translate-plural (length rows) "~D row" "~D rows"))
        (when (grid-csv-filename self)
          (text " ")
          (anchor (:class "lt-csv"
                   :callback (lambda () (send-download (data-grid-csv self) :filename (grid-csv-filename self)
                                                                            :content-type "text/csv; charset=utf-8")))
            (translate "Download CSV")))
        (cond (virtual (render-virtual-pager self (length rows)))
              ((> pages 1)
               (when (plusp page)
                 (anchor (:on-click (ajax :callback (lambda () (setf (grid-page self) (1- page))) :update self) :href "#")
                   (translate "« Previous")))
               (text (format nil " ~D / ~D " (1+ page) pages))
               (when (< page (1- pages))
                 (anchor (:on-click (ajax :callback (lambda () (setf (grid-page self) (1+ page))) :update self) :href "#")
                   (translate "Next »")))))))))

;;; Charts, as inline SVG

(defun nice-step (span ticks)
  "A round step dividing SPAN into about TICKS parts."
  (if (<= span 0) 1
      (let* ((rough (/ span ticks))
             (magnitude (expt 10 (floor (log rough 10))))
             (fraction (/ rough magnitude)))
        (* magnitude (cond ((<= fraction 1) 1) ((<= fraction 2) 2) ((<= fraction 5) 5) (t 10))))))

(defun svg-number (x) (format nil "~,1F" x))

(defvar *chart-counter* 0)

(defun series-class (n)
  "The CSS class giving series N its colour (and, in a scatter chart, shape)."
  (format nil "lt-series-~D" (mod n 6)))

(defun chart-key (names)
  "Write a key matching each of NAMES to its series' colour."
  (ul (:class "lt-chart-key")
    (loop for name in names for n from 0
          do (li () (span (:class (list "lt-chart-swatch" (series-class n)))) (text (princ-to-string name))))))

(defun chart-figure (title data-table body &optional key)
  "A figure holding an SVG chart, its TITLE, and its data as a table for
screen readers (and anyone who opens it).  KEY, when given, is a thunk
writing the chart's key."
  (let ((id (format nil "lt-chart-~D" (incf *chart-counter*))))
    (figure (:class "lt-chart")
      (raw (funcall body id))
      (when key (funcall key))
      (figcaption (:id id) (text title))
      (details (:class "lt-chart-data")
        (summary () (translate "Data"))
        (table (:class "lt-table")
          (dolist (row data-table)
            (tr () (th () (text (first row))) (dolist (cell (rest row)) (td () (text cell))))))))))

(defun bar-chart (data &key (title "") (width 480) (height 220) (format-value #'princ-to-string))
  "Write a bar chart of DATA, a list of (LABEL . VALUE) with VALUE a
non-negative number, as accessible SVG: a figure captioned by TITLE, each
bar titled with its label and value, and the data as a table for screen
readers.  FORMAT-VALUE, a function of a number, writes the values and the
axis.  WIDTH and HEIGHT are in SVG units; the chart scales to fit."
  (let* ((top (max 1 (reduce #'max data :key #'cdr :initial-value 0)))
         (step (nice-step top 4))
         (top (* step (ceiling top step)))
         (left 44) (bottom 28) (right 8) (above 8)
         (plot-w (- width left right)) (plot-h (- height bottom above))
         (slot (/ plot-w (max 1 (length data)))))
    (chart-figure
     title (mapcar (lambda (d) (list (princ-to-string (car d)) (funcall format-value (cdr d)))) data)
     (lambda (id)
       (with-output-to-string (out)
         (format out "<svg class=\"lt-chart-svg\" viewBox=\"0 0 ~D ~D\" role=\"img\" aria-labelledby=\"~A\" preserveAspectRatio=\"xMidYMid meet\">" width height id)
         (loop for tick from 0 to top by step
               for y = (+ above (* plot-h (- 1 (/ tick top))))
               do (format out "<line class=\"lt-chart-grid\" x1=\"~A\" x2=\"~A\" y1=\"~A\" y2=\"~A\"/><text class=\"lt-chart-axis\" x=\"~A\" y=\"~A\" text-anchor=\"end\">~A</text>"
                          left (- width right) (svg-number y) (svg-number y) (- left 6) (svg-number (+ y 4))
                          (html-escape (funcall format-value tick))))
         (loop for (label . value) in data
               for i from 0
               for h = (* plot-h (/ (max 0 value) top))
               for x = (+ left (* i slot) (* slot 0.15))
               do (format out "<rect class=\"lt-chart-bar\" x=\"~A\" y=\"~A\" width=\"~A\" height=\"~A\" rx=\"2\"><title>~A: ~A</title></rect>"
                          (svg-number x) (svg-number (- (+ above plot-h) h)) (svg-number (* slot 0.7)) (svg-number h)
                          (html-escape (princ-to-string label)) (html-escape (funcall format-value value)))
                  (format out "<text class=\"lt-chart-axis\" x=\"~A\" y=\"~A\" text-anchor=\"middle\">~A</text>"
                          (svg-number (+ x (* slot 0.35))) (- height 8) (html-escape (princ-to-string label))))
         (format out "</svg>"))))))

(defun line-chart (series &key (title "") (width 480) (height 220) x-labels (format-value #'princ-to-string))
  "Write a line chart of SERIES, a list of (NAME . VALUES), the values all
the same length and non-negative, as accessible SVG, like BAR-CHART: a
figure captioned by TITLE, with the data as a table.  X-LABELS name the
points; FORMAT-VALUE writes the values and the axis.  More than one series
gets a legend."
  (let* ((count (reduce #'max series :key (lambda (s) (length (rest s))) :initial-value 0))
         (top (max 1 (reduce #'max (mapcan (lambda (s) (copy-list (rest s))) series) :initial-value 0)))
         (step (nice-step top 4))
         (top (* step (ceiling top step)))
         (left 44) (bottom 28) (right 8) (above 8)
         (plot-w (- width left right)) (plot-h (- height bottom above)))
    (flet ((x (i) (+ left (if (> count 1) (* plot-w (/ i (1- count))) (/ plot-w 2))))
           (y (v) (+ above (* plot-h (- 1 (/ (max 0 v) top))))))
      (chart-figure
       title
       (cons (cons "" (or (mapcar #'princ-to-string x-labels) (loop for i from 1 to count collect (princ-to-string i))))
             (mapcar (lambda (s) (cons (princ-to-string (first s)) (mapcar format-value (rest s)))) series))
       (lambda (id)
         (with-output-to-string (out)
           (format out "<svg class=\"lt-chart-svg\" viewBox=\"0 0 ~D ~D\" role=\"img\" aria-labelledby=\"~A\" preserveAspectRatio=\"xMidYMid meet\">" width height id)
           (loop for tick from 0 to top by step
                 for yy = (y tick)
                 do (format out "<line class=\"lt-chart-grid\" x1=\"~A\" x2=\"~A\" y1=\"~A\" y2=\"~A\"/><text class=\"lt-chart-axis\" x=\"~A\" y=\"~A\" text-anchor=\"end\">~A</text>"
                            left (- width right) (svg-number yy) (svg-number yy) (- left 6) (svg-number (+ yy 4))
                            (html-escape (funcall format-value tick))))
           (when x-labels
             (let ((every (max 1 (ceiling count 8))))
               (loop for label in x-labels for i from 0
                     when (zerop (mod i every))
                       do (format out "<text class=\"lt-chart-axis\" x=\"~A\" y=\"~A\" text-anchor=\"middle\">~A</text>"
                                  (svg-number (x i)) (- height 8) (html-escape (princ-to-string label))))))
           (loop for (name . values) in series for n from 0
                 do (format out "<polyline class=\"lt-chart-line ~A\" points=\"~{~A~^ ~}\"><title>~A</title></polyline>"
                            (series-class n)
                            (loop for v in values for i from 0 collect (format nil "~A,~A" (svg-number (x i)) (svg-number (y v))))
                            (html-escape (princ-to-string name))))
           (when (> (length series) 1)
             (loop for (name) in series for n from 0
                   do (format out "<text class=\"lt-chart-legend ~A\" x=\"~A\" y=\"~A\">● ~A</text>"
                              (series-class n) (+ left 6 (* n 110)) (+ above 12) (html-escape (princ-to-string name)))))
           (format out "</svg>")))))))

(defun sparkline (values &key (label "") (width 120) (height 28))
  "Write a small line of VALUES, non-negative numbers, as SVG WIDTH by
HEIGHT pixels, with LABEL for screen readers.  No axes, no figure."
  (let* ((top (max 1 (reduce #'max values :initial-value 0)))
         (count (length values)))
    (raw (format nil "<svg class=\"lt-sparkline\" width=\"~D\" height=\"~D\" viewBox=\"0 0 ~D ~D\" role=\"img\" aria-label=\"~A\"><polyline points=\"~{~A~^ ~}\"/></svg>"
                 width height width height (html-escape label)
                 (loop for v in values for i from 0
                       collect (format nil "~A,~A" (svg-number (if (> count 1) (+ 1 (* (- width 2) (/ i (1- count)))) 1))
                                       (svg-number (+ 1 (* (- height 2) (- 1 (/ (max 0 v) top)))))))))))

;;; A month calendar

(defun weekday (year month day)
  "0 for Monday … 6 for Sunday."
  (nth-value 6 (decode-universal-time (encode-universal-time 0 0 12 day month year 0) 0)))

(defun days-in (year month)
  (if (= month 12) 31 (- (nth-value 3 (decode-universal-time (- (encode-universal-time 0 0 12 1 (1+ month) year 0) 86400) 0))
                         0)))

(defclass calendar (component)
  ((year :initarg :year :initform nil :accessor calendar-year
         :documentation "The year of the month shown.")
   (month :initarg :month :initform nil :accessor calendar-month
          :documentation "The month shown, 1 to 12.")
   (events :initarg :events :initform '() :reader calendar-events-designator
           :documentation "(DATE . TITLE) pairs, DATE as (YEAR MONTH DAY): a list, or a function returning one.")
   (on-select :initarg :on-select :initform nil :reader calendar-on-select
              :documentation "Called with the (YEAR MONTH DAY) chosen, or NIL for none to choose."))
  (:documentation "A month of days, Monday first, with their events, and links
to the months before and after.  :YEAR and :MONTH (1 to 12) say which month
to show first, by default the current one.  :EVENTS are (DATE . TITLE)
pairs, DATE as (YEAR MONTH DAY): a list, or a function returning one.  With
:ON-SELECT each day is a link calling it with that day's date."))

(defmethod initialize-instance :after ((self calendar) &key)
  (multiple-value-bind (s m h day month year) (decode-universal-time (get-universal-time))
    (declare (ignore s m h day))
    (unless (calendar-year self) (setf (calendar-year self) year))
    (unless (calendar-month self) (setf (calendar-month self) month))))

(defmethod states ((self calendar)) (list self))

(defun shift-month (calendar delta)
  (let ((index (+ (* 12 (calendar-year calendar)) (1- (calendar-month calendar)) delta)))
    (setf (calendar-year calendar) (floor index 12)
          (calendar-month calendar) (1+ (mod index 12)))))

(defparameter *weekday-names* '("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"))

(defmethod render ((self calendar))
  (let* ((year (calendar-year self)) (month (calendar-month self))
         (language (find-language (current-language)))
         (events (let ((e (calendar-events-designator self))) (if (functionp e) (funcall e) e)))
         (today (multiple-value-bind (s m h d mo y) (decode-universal-time (get-universal-time))
                  (declare (ignore s m h)) (list y mo d)))
         (first (weekday year month 1))
         (days (days-in year month)))
    (div (:class "lt-calendar")
      (div (:class "lt-calendar-head")
        (anchor (:callback (lambda () (shift-month self -1)) :aria-label (translate "Previous month")) "‹")
        (h3 () (text (format nil "~:(~A~) ~D" (nth (1- month) (language-months language)) year)))
        (anchor (:callback (lambda () (shift-month self 1)) :aria-label (translate "Next month")) "›"))
      (table (:class "lt-calendar-grid")
        (thead () (tr () (dolist (name *weekday-names*) (th (:scope "col") (translate name)))))
        (tbody ()
          (loop for week from 0
                while (< (- (* 7 week) first) days)
                do (tr ()
                     (dotimes (column 7)
                       (let ((day (1+ (- (+ (* 7 week) column) first))))
                         (if (<= 1 day days)
                             (let* ((date (list year month day))
                                    (todays (remove-if-not (lambda (e) (equal (car e) date)) events)))
                               (td (:class (list (when (equal date today) "lt-today") (when todays "lt-busy")))
                                 (if (calendar-on-select self)
                                     (anchor (:class "lt-calendar-day"
                                              :callback (lambda () (funcall (calendar-on-select self) date)))
                                       (text day))
                                     (span (:class "lt-calendar-day") (text day)))
                                 (when todays
                                   (ul (:class "lt-calendar-events")
                                     (dolist (event todays) (li () (text (cdr event))))))))
                             (td (:class "lt-calendar-blank"))))))))))))

;;; A kanban board

(defclass kanban (component updatable)
  ((columns :initarg :columns :initform '() :accessor kanban-columns
            :documentation "(TITLE . ITEMS) for each column, replaced on every move.")
   (render-card :initarg :render-card :initform (lambda (item) (text item)) :reader kanban-card-renderer)
   (on-move :initarg :on-move :initform nil :reader kanban-on-move
            :documentation "Called with ITEM, the titles of the columns it left and joined, and its new position."))
  (:documentation "Columns of cards to drag between, or move with the arrow
links on each card (which work without JavaScript or a mouse).  :COLUMNS is
a list of (TITLE . ITEMS); :RENDER-CARD, a function of an item, writes a
card (as text by default); :ON-MOVE is called after every move with the
item, the titles of the columns it left and joined, and its new position."))

(defmethod states ((self kanban)) (list self))

(defun move-card (board from-column from-index to-column to-index)
  "Move the card at position FROM-INDEX of column FROM-COLUMN to position
TO-INDEX of column TO-COLUMN, all counting from 0, and call BOARD's ON-MOVE.
TO-INDEX is kept in range.  Returns T, or NIL, moving nothing, when a column
or FROM-INDEX is out of range."
  (let* ((columns (kanban-columns board))
         (count (length columns)))
    (when (and (< -1 from-column count) (< -1 to-column count))
      (let ((source (rest (nth from-column columns))))
        (when (< -1 from-index (length source))
          (let* ((item (nth from-index source))
                 (columns (loop for (title . items) in columns for i from 0
                                collect (cons title (if (= i from-column) (remove item items :count 1) items))))
                 (target (rest (nth to-column columns)))
                 (to-index (max 0 (min to-index (length target)))))
            (setf (rest (nth to-column columns))
                  (append (subseq target 0 to-index) (list item) (subseq target to-index))
                  (kanban-columns board) columns)
            (when (kanban-on-move board)
              (funcall (kanban-on-move board) item (first (nth from-column columns)) (first (nth to-column columns)) to-index))
            t))))))

(defun apply-card-move (board move)
  "MOVE is \"FROM-COLUMN,FROM-INDEX,TO-COLUMN,TO-INDEX\", as the browser sends after a drag."
  (let ((numbers (ignore-errors (mapcar #'parse-integer (cl-ppcre:split "," move)))))
    (when (= 4 (length numbers))
      (apply #'move-card board numbers))))

(defmethod render ((self kanban))
  (let* ((columns (kanban-columns self))
         (count (length columns)))
    (emit-tag "div"
              (list :class "lt-kanban"
                    :kanban (ajax :value "this.dataset.move"
                                  :callback (lambda (move) (apply-card-move self move))
                                  :update self))
              (lambda ()
                (loop for (title . items) in columns
                      for c from 0
                      do (let ((c c))
                           (section (:class "lt-kanban-column" :aria-label title)
                             (h3 () (text title) (span (:class "lt-kanban-count") (text (format nil " ~D" (length items)))))
                             (emit-tag "ol" (list :data-lt-column c :class "lt-kanban-cards")
                                       (lambda ()
                                         (loop for item in items for i from 0
                                               do (let ((i i))
                                                    (li (:draggable "true" :data-lt-index i)
                                                      (div (:class "lt-kanban-card") (funcall (kanban-card-renderer self) item))
                                                      (span (:class "lt-kanban-buttons")
                                                        (when (plusp c)
                                                          (anchor (:aria-label (translate "Move to ~A" (first (nth (1- c) columns)))
                                                                   :callback (lambda () (move-card self c i (1- c) 0)))
                                                            "←"))
                                                        (when (plusp i)
                                                          (anchor (:aria-label (translate "Move up")
                                                                   :callback (lambda () (move-card self c i c (1- i))))
                                                            "↑"))
                                                        (when (< i (1- (length items)))
                                                          (anchor (:aria-label (translate "Move down")
                                                                   :callback (lambda () (move-card self c i c (1+ i))))
                                                            "↓"))
                                                        (when (< c (1- count))
                                                          (anchor (:aria-label (translate "Move to ~A" (first (nth (1+ c) columns)))
                                                                   :callback (lambda () (move-card self c i (1+ c) 0)))
                                                            "→")))))))))))))))

;;; Markdown, rendered safely

(defun markdown-url-p (url)
  "True for the links Markdown may make: http(s), mailto, and this site's own paths."
  (cl-ppcre:scan "^(?:https?://|mailto:|/(?!/)|#)" url))

(defun markdown-inline (text)
  "TEXT (escaped already) with `code`, **strong**, *emphasis* and [links](url)."
  (let ((codes '()))
    ;; Code first, set aside so nothing inside it is touched.
    (setf text (cl-ppcre:regex-replace-all "`([^`]+)`" text
                                           (lambda (match code) (declare (ignore match))
                                             (push code codes)
                                             (format nil "~ACODE~D~A" (code-char 1) (1- (length codes)) (code-char 1)))
                                           :simple-calls t))
    (setf text (cl-ppcre:regex-replace-all "\\[([^\\]]+)\\]\\(([^)\\s]+)\\)" text
                                           (lambda (match label url)
                                             (let ((raw-url (cl-ppcre:regex-replace-all "&amp;" url "&")))
                                               (if (markdown-url-p raw-url)
                                                   (format nil "<a href=\"~A\" rel=\"nofollow noopener\">~A</a>" url label)
                                                   match)))
                                           :simple-calls t))
    (setf text (cl-ppcre:regex-replace-all "\\*\\*([^*]+)\\*\\*" text "<strong>\\1</strong>"))
    (setf text (cl-ppcre:regex-replace-all "(?<![\\w*])\\*([^*\\s][^*]*)\\*" text "<em>\\1</em>"))
    (setf text (cl-ppcre:regex-replace-all "(?<!\\w)_([^_\\s][^_]*)_(?!\\w)" text "<em>\\1</em>"))
    (cl-ppcre:regex-replace-all (format nil "~ACODE(\\d+)~A" (code-char 1) (code-char 1)) text
                                (lambda (match n) (declare (ignore match))
                                  (format nil "<code>~A</code>" (nth (- (length codes) 1 (parse-integer n)) codes)))
                                :simple-calls t)))

(defun markdown-html (markdown)
  "MARKDOWN as HTML: paragraphs, # headings, - and 1. lists, > quotes, ```
code blocks, `code`, **strong**, *emphasis* and [links](https://…).  All
of MARKDOWN's own HTML is escaped, and links go only to http(s), mailto or
this site, so the result is safe to show whoever wrote it.  Headings start
at h3 for #, so they sit under a page's own."
  (let ((lines (cl-ppcre:split "\\r?\\n" (or markdown "")))
        (paragraph '()) (list-kind nil)
        (out (make-string-output-stream)))
    (labels ((flush-paragraph ()
               (when paragraph
                 (format out "<p>~A</p>" (markdown-inline (format nil "~{~A~^ ~}" (reverse paragraph))))
                 (setf paragraph '())))
             (close-list ()
               (when list-kind (format out "</~A>" list-kind) (setf list-kind nil)))
             (flush () (flush-paragraph) (close-list)))
      (loop with code = nil
            for raw in lines
            for line = (html-escape raw)
            do (cond (code
                      (if (cl-ppcre:scan "^\\s*```" raw)
                          (progn (format out "</code></pre>") (setf code nil))
                          (format out "~A~%" line)))
                     ((cl-ppcre:scan "^\\s*```" raw)
                      (flush) (format out "<pre><code>") (setf code t))
                     ((cl-ppcre:scan "^\\s*$" raw) (flush))
                     ((cl-ppcre:scan "^#{1,6}\\s" raw)
                      (flush)
                      (let ((level (min 6 (+ 2 (position #\Space raw)))))
                        (format out "<h~D>~A</h~D>" level (markdown-inline (string-trim " #" line)) level)))
                     ((cl-ppcre:scan "^\\s*&gt;\\s?" line)
                      (flush)
                      (format out "<blockquote><p>~A</p></blockquote>"
                              (markdown-inline (cl-ppcre:regex-replace "^\\s*&gt;\\s?" line ""))))
                     ((cl-ppcre:scan "^\\s*[-*]\\s+" raw)
                      (flush-paragraph)
                      (unless (equal list-kind "ul") (close-list) (format out "<ul>") (setf list-kind "ul"))
                      (format out "<li>~A</li>" (markdown-inline (cl-ppcre:regex-replace "^\\s*[-*]\\s+" line ""))))
                     ((cl-ppcre:scan "^\\s*\\d+\\.\\s+" raw)
                      (flush-paragraph)
                      (unless (equal list-kind "ol") (close-list) (format out "<ol>") (setf list-kind "ol"))
                      (format out "<li>~A</li>" (markdown-inline (cl-ppcre:regex-replace "^\\s*\\d+\\.\\s+" line ""))))
                     (t (close-list) (push (string-trim " " line) paragraph)))
            finally (when code (format out "</code></pre>")))
      (flush))
    (get-output-stream-string out)))

(defclass markdown-field (text-field) ()
  (:documentation "Text written in Markdown, shown as safe HTML (see
MARKDOWN-HTML): the description field kind :MARKDOWN."))

(defmethod render-field-input ((field markdown-field) id text callback)
  (text-area (:id id :value text :rows 6 :callback callback))
  (div (:class "lt-help") (translate "Markdown: **strong**, *emphasis*, `code`, [links](https://…), - lists, # headings.")))

(defmethod render-field-value ((field markdown-field) value)
  (when value
    (div (:class "lt-markdown") (raw (markdown-html value)))))

(push '(:markdown . markdown-field) *field-kinds*)

;;; In-place editor: one field of one object, edited where it is shown

(defclass in-place-editor (component updatable)
  ((object :initarg :object :accessor in-place-object)
   (field :initarg :field :reader in-place-field)
   (on-save :initarg :on-save :initform nil :reader in-place-on-save)
   (update :initarg :update :initform '() :reader in-place-update
           :documentation "Other UPDATABLE components to re-render after a save.")
   (reload :initarg :reload :initform nil :reader in-place-reload
           :documentation "Function of the object giving it as it is now, or NIL when it has gone.")
   (editing :initform nil :accessor in-place-editing-p)
   (text :initform "" :accessor in-place-text :documentation "What has been typed.")
   (original :initform nil :accessor in-place-original :documentation "The value's text when editing began.")
   (problem :initform nil :accessor in-place-problem))
  (:documentation "One field of an object, shown with an Edit button; Edit
turns it into the field's input, with Save and Cancel, over AJAX.  Save
parses and checks the text as the description says, writes the value to
the object and calls :ON-SAVE, when given, with the object (to store it,
say); a problem is shown by the input instead.  :UPDATE lists other
UPDATABLE components the value shows in, re-rendered after a save.  When
someone else changed the value since Edit was pressed, Save says so and
leaves it; pressing it again replaces their value.  An EDIT-CONFLICT
signalled by :ON-SAVE (as littoral.db's STALE-OBJECT is) is reported the
same way, the object put back as it was, and :RELOAD, when given, called
with it to get it as it is now (#'littoral.db:db-reload, say).  Make one
with MAKE-IN-PLACE-EDITOR."))

(defmethod states ((self in-place-editor)) (list self))

(defun make-in-place-editor (object field-name &key (description object) on-save update reload)
  "An IN-PLACE-EDITOR of OBJECT's field FIELD-NAME, as DESCRIPTION
(anything FIND-DESCRIPTION takes; by default OBJECT's class) describes it.
ON-SAVE is called with OBJECT after a value is written to it, and UPDATE,
an UPDATABLE component or a list of them, is re-rendered with the editor.
RELOAD gets the object afresh after an EDIT-CONFLICT (see IN-PLACE-EDITOR)."
  (make-instance 'in-place-editor
                 :object object
                 :reload reload
                 :update (alexandria:ensure-list update)
                 :field (or (find-field description field-name)
                            (error "~S has no field ~S." (description-name (find-description description)) field-name))
                 :on-save on-save))

(defun in-place-value-text (editor)
  (let ((field (in-place-field editor)))
    (format-field field (field-value field (in-place-object editor)))))

(defun start-in-place-edit (editor)
  (setf (in-place-editing-p editor) t
        (in-place-problem editor) nil
        (in-place-text editor) (in-place-value-text editor)
        (in-place-original editor) (in-place-value-text editor)))

(defun in-place-conflict (editor)
  "After :ON-SAVE refused the save: get the object afresh, when it can be,
and say what happened."
  (let* ((reload (in-place-reload editor))
         (fresh (and reload (funcall reload (in-place-object editor)))))
    (cond (fresh
           (setf (in-place-object editor) fresh
                 (in-place-original editor) (in-place-value-text editor)
                 (in-place-problem editor)
                 (translate "Someone else changed this to “~A” meanwhile. Save again to replace it."
                            (conflict-text (in-place-field editor) (in-place-value-text editor)))))
          (reload
           (setf (in-place-problem editor) (translate "Someone else deleted this meanwhile; nothing was saved.")))
          (t
           (setf (in-place-problem editor) (translate "Someone else changed this meanwhile; nothing was saved."))))))

(defun save-in-place-edit (editor)
  "Write what was typed, or keep it with its problem."
  (let* ((field (in-place-field editor))
         (object (in-place-object editor))
         (now (in-place-value-text editor))
         (text (in-place-text editor)))
    (if (and (in-place-original editor) (string/= now (in-place-original editor)) (string/= now text))
        ;; Changed by someone else since Edit was pressed: say so, once.
        (setf (in-place-original editor) now
              (in-place-problem editor)
              (translate "Someone else changed this to “~A” meanwhile. Save again to replace it."
                         (conflict-text field now)))
        (handler-case
            (let* ((value (parse-field field text))
                   (problem (check-field field value)))
              (if problem
                  (setf (in-place-problem editor) problem)
                  (let ((before (field-value field object)))
                    (setf (field-value field object) value)
                    (handler-case
                        (progn
                          (when (in-place-on-save editor)
                            (funcall (in-place-on-save editor) object))
                          (setf (in-place-editing-p editor) nil
                                (in-place-problem editor) nil))
                      (edit-conflict ()
                        (setf (field-value field object) before)
                        (in-place-conflict editor))))))
          (field-error (e) (setf (in-place-problem editor) (field-error-message e)))))))

(defmethod render ((self in-place-editor))
  (let* ((field (in-place-field self))
         (label (translate (field-label field))))
    (if (in-place-editing-p self)
        (let ((problem (in-place-problem self))
              (id (format nil "~A-input" (component-id self))))
          (form (:class "lt-in-place lt-in-place-editing"
                 :on-submit (ajax :callback (lambda () (save-in-place-edit self))
                                  :update (cons self (in-place-update self))))
            (let ((*next-field-attributes* (list :aria-label label :autofocus t
                                                 :aria-invalid (when problem "true")
                                                 :aria-describedby (when problem (format nil "~A-problem" id)))))
              (render-field-input field id (in-place-text self)
                                  (lambda (text) (setf (in-place-text self) text))))
            (button (:type "submit") (translate "Save"))
            (button (:on-click (ajax :callback (lambda () (setf (in-place-editing-p self) nil)) :update self))
              (translate "Cancel"))
            (when problem
              (div (:class "lt-validation-error" :id (format nil "~A-problem" id)) (text problem)))))
        (span (:class "lt-in-place")
          (render-field-value field (field-value field (in-place-object self)))
          " "
          (button (:class "lt-in-place-edit" :aria-label (translate "Edit ~A" label)
                   :on-click (ajax :callback (lambda () (start-in-place-edit self)) :update self))
            (translate "Edit"))))))
