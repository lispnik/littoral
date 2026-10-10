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
   (editing :initform nil :accessor grid-editing :documentation "The object being edited, or NIL.")
   (texts :initform '() :accessor grid-texts :documentation "(FIELD-NAME . TEXT) typed into the row being edited.")
   (problems :initform '() :accessor grid-problems))
  (:documentation "A table of a description's objects: a filter box per column,
sorting by column, paging, and editing a row in place with the description's
own inputs and validation."))

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
                (grid-all-rows grid))))
    (let ((field (and (grid-sort-field grid) (find (grid-sort-field grid) fields :key #'field-name))))
      (if field
          (let ((sorted (stable-sort (copy-list rows) #'value<
                                     :key (lambda (row) (let ((v (field-value field row)))
                                                          (if (or (realp v) (null v)) v (format-field field v)))))))
            (if (grid-descending-p grid) (reverse sorted) sorted))
          rows))))

(defun set-grid-filter (grid name text)
  (setf (grid-filters grid) (acons name text (remove name (grid-filters grid) :key #'car))
        (grid-page grid) 0))

(defun sort-grid (grid name)
  (if (eq (grid-sort-field grid) name)
      (setf (grid-descending-p grid) (not (grid-descending-p grid)))
      (setf (grid-sort-field grid) name (grid-descending-p grid) nil)))

(defun edit-grid-row (grid row)
  (setf (grid-editing grid) row
        (grid-problems grid) '()
        (grid-texts grid) (mapcar (lambda (field) (cons (field-name field) (format-field field (field-value field row))))
                                  (grid-fields grid))))

(defun save-grid-row (grid)
  "Check the row being edited; write it and call ON-SAVE, or keep the problems."
  (let ((row (grid-editing grid)) (values '()) (problems '()))
    (dolist (field (grid-fields grid))
      (let ((text (or (cdr (assoc (field-name field) (grid-texts grid))) "")))
        (handler-case
            (let* ((value (parse-field field text))
                   (problem (check-field field value)))
              (if problem
                  (push (cons (field-name field) problem) problems)
                  (push (cons field value) values)))
          (field-error (e) (push (cons (field-name field) (field-error-message e)) problems)))))
    (if problems
        (setf (grid-problems grid) problems)
        (progn
          (loop for (field . value) in values do (setf (field-value field row) value))
          (setf (grid-editing grid) nil (grid-problems grid) '())
          (when (grid-on-save grid) (funcall (grid-on-save grid) row))))))

(defmethod render ((self data-grid))
  (let* ((fields (grid-fields self))
         (rows (grid-visible-rows self))
         (pages (max 1 (ceiling (length rows) (grid-page-size self))))
         (page (min (grid-page self) (1- pages)))
         (shown (subseq rows (min (length rows) (* page (grid-page-size self)))
                        (min (length rows) (* (1+ page) (grid-page-size self))))))
    (form (:class "lt-grid")
      (div (:class "lt-grid-scroll" :tabindex "0" :role "region" :aria-label (translate "Table"))
        (table (:class "lt-table")
          (thead ()
            (tr ()
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
            (tr (:class "lt-grid-filters")
              (dolist (field fields)
                (let ((name (field-name field)))
                  (td ()
                    (text-input (:value (or (cdr (assoc name (grid-filters self))) "")
                                 :label (translate "Filter ~A" (translate (field-label field)))
                                 :placeholder (translate "Filter")
                                 :callback (lambda (v) (set-grid-filter self name v))
                                 :on-input (ajax-update self))))))
              (td ())))
          (tbody ()
            (if (null shown)
                (tr () (td (:colspan (princ-to-string (1+ (length fields)))) (translate "Nothing matches.")))
                (dolist (row shown)
                  (let ((row row))
                    (if (eq row (grid-editing self))
                        (tr (:class "lt-grid-editing")
                          (dolist (field fields)
                            (let* ((name (field-name field))
                                   (problem (cdr (assoc name (grid-problems self)))))
                              (td ()
                                (let ((*next-field-attributes* (list :aria-label (translate (field-label field))
                                                                     :aria-invalid (when problem "true"))))
                                  (render-field-input field (format nil "grid-~(~A~)" name)
                                                      (or (cdr (assoc name (grid-texts self))) "")
                                                      (lambda (text) (setf (grid-texts self)
                                                                           (acons name text (remove name (grid-texts self) :key #'car))))))
                                (when problem (div (:class "lt-validation-error") (text problem))))))
                          (td (:class "lt-grid-actions")
                            (submit-button (:callback (lambda () (save-grid-row self))) (translate "Save"))
                            (cancel-button (:callback (lambda () (setf (grid-editing self) nil))) (translate "Cancel"))))
                        (tr ()
                          (dolist (field fields)
                            (td () (render-field-value field (field-value field row))))
                          (td (:class "lt-grid-actions")
                            (anchor (:callback (lambda () (edit-grid-row self row))) (translate "Edit")))))))))))
      (div (:class "lt-batch")
        (text (translate-plural (length rows) "~D row" "~D rows"))
        (when (> pages 1)
          (when (plusp page)
            (anchor (:on-click (ajax :callback (lambda () (setf (grid-page self) (1- page))) :update self) :href "#")
              (translate "« Previous")))
          (text (format nil " ~D / ~D " (1+ page) pages))
          (when (< page (1- pages))
            (anchor (:on-click (ajax :callback (lambda () (setf (grid-page self) (1+ page))) :update self) :href "#")
              (translate "Next »"))))))))

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

(defun chart-figure (title data-table body)
  "A figure holding an SVG chart, its TITLE, and its data as a table for
screen readers (and anyone who opens it)."
  (let ((id (format nil "lt-chart-~D" (incf *chart-counter*))))
    (figure (:class "lt-chart")
      (raw (funcall body id))
      (figcaption (:id id) (text title))
      (details (:class "lt-chart-data")
        (summary () (translate "Data"))
        (table (:class "lt-table")
          (dolist (row data-table)
            (tr () (th () (text (first row))) (dolist (cell (rest row)) (td () (text cell))))))))))

(defun bar-chart (data &key (title "") (width 480) (height 220) (format-value #'princ-to-string))
  "Write a bar chart of DATA, a list of (LABEL . VALUE), as accessible SVG."
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
the same length, as accessible SVG.  X-LABELS name the points."
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
                 do (format out "<polyline class=\"lt-chart-line lt-series-~D\" points=\"~{~A~^ ~}\"><title>~A</title></polyline>"
                            (mod n 4)
                            (loop for v in values for i from 0 collect (format nil "~A,~A" (svg-number (x i)) (svg-number (y v))))
                            (html-escape (princ-to-string name))))
           (when (> (length series) 1)
             (loop for (name) in series for n from 0
                   do (format out "<text class=\"lt-chart-legend lt-series-~D\" x=\"~A\" y=\"~A\">● ~A</text>"
                              (mod n 4) (+ left 6 (* n 110)) (+ above 12) (html-escape (princ-to-string name)))))
           (format out "</svg>")))))))

(defun sparkline (values &key (label "") (width 120) (height 28))
  "Write a small line of VALUES, with LABEL for screen readers."
  (let* ((top (max 1 (reduce #'max values :initial-value 0)))
         (count (length values)))
    (raw (format nil "<svg class=\"lt-sparkline\" width=\"~D\" height=\"~D\" viewBox=\"0 0 ~D ~D\" role=\"img\" aria-label=\"~A\"><polyline points=\"~{~A~^ ~}\"/></svg>"
                 width height width height (html-escape label)
                 (loop for v in values for i from 0
                       collect (format nil "~A,~A" (svg-number (if (> count 1) (* (- width 2) (/ i (1- count))) 1))
                                       (svg-number (+ 1 (* (- height 2) (- 1 (/ (max 0 v) top)))))))))))

;;; A month calendar

(defun weekday (year month day)
  "0 for Monday … 6 for Sunday."
  (nth-value 6 (decode-universal-time (encode-universal-time 0 0 12 day month year 0) 0)))

(defun days-in (year month)
  (if (= month 12) 31 (- (nth-value 3 (decode-universal-time (- (encode-universal-time 0 0 12 1 (1+ month) year 0) 86400) 0))
                         0)))

(defclass calendar (component)
  ((year :initarg :year :initform nil :accessor calendar-year)
   (month :initarg :month :initform nil :accessor calendar-month)
   (events :initarg :events :initform '() :reader calendar-events-designator
           :documentation "(DATE . TITLE) pairs, DATE as (YEAR MONTH DAY): a list, or a function returning one.")
   (on-select :initarg :on-select :initform nil :reader calendar-on-select
              :documentation "Called with the (YEAR MONTH DAY) chosen, or NIL for none to choose."))
  (:documentation "A month of days, Monday first, with their events, and links
to the months before and after."))

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
buttons on each card (which work without JavaScript or a mouse)."))

(defmethod states ((self kanban)) (list self))

(defun move-card (board from-column from-index to-column to-index)
  "Move the card at FROM-INDEX of FROM-COLUMN to TO-INDEX of TO-COLUMN; NIL if out of range."
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
this site, so the result is safe to show whoever wrote it."
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
  (:documentation "Text written in Markdown, shown as safe HTML."))

(defmethod render-field-input ((field markdown-field) id text callback)
  (text-area (:id id :value text :rows 6 :callback callback))
  (div (:class "lt-help") (translate "Markdown: **strong**, *emphasis*, `code`, [links](https://…), - lists, # headings.")))

(defmethod render-field-value ((field markdown-field) value)
  (when value
    (div (:class "lt-markdown") (raw (markdown-html value)))))

(push '(:markdown . markdown-field) *field-kinds*)
