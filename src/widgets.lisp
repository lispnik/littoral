;;;; widgets.lisp — Seaside's batched list and table report
;;;;
;;;;   (make-instance 'report
;;;;     :rows (lambda () (all-orders))
;;;;     :columns (list (column "Order" #'order-id)
;;;;                    (column "Total" #'order-total :render #'render-money)
;;;;                    (column "" nil :sortable nil
;;;;                            :render (lambda (row value) (declare (ignore value))
;;;;                                      (h:anchor (:callback (lambda () (open-order row))) "open"))))
;;;;     :batch-size 20)

(in-package #:littoral)

;;; Batched list

(defclass batched-list (component)
  ((items :initarg :items :initform '()
          :documentation "A list, or a thunk returning one when needed.")
   (batch-size :initarg :batch-size :initform 10 :accessor batch-size
               :documentation "How many items a page holds.")
   (page :initform 0 :accessor batch-page :documentation "The page shown, counting from 0."))
  (:documentation "Pages through :ITEMS (a list, or a function returning
one), :BATCH-SIZE (10 by default) at a time.  Render the current BATCH
yourself and RENDER-COMPONENT the batched list for its page links, as with
Seaside's WABatchedList."))

(defmethod states ((self batched-list))
  (list self))

(defun batch-items (list)
  "All of LIST's items, calling its items function when it has one.
SETF replaces them (with a list or a function), keeping the page in range."
  (let ((items (slot-value list 'items)))
    (if (functionp items) (funcall items) items)))

(defun page-count (list)
  "How many pages LIST's items fill; at least one."
  (max 1 (ceiling (length (batch-items list)) (batch-size list))))

(defun (setf batch-items) (items list)
  "Replace the items, keeping the page in range."
  (setf (slot-value list 'items) items
        (batch-page list) (min (batch-page list) (1- (page-count list))))
  items)

(defun batch (list)
  "The items on LIST's current page."
  (let* ((items (batch-items list))
         (page (min (batch-page list) (1- (page-count list))))
         (start (* page (batch-size list))))
    (subseq items
            (min start (length items))
            (min (+ start (batch-size list)) (length items)))))

(defun go-to-page (list page)
  "Show page PAGE (counting from 0) of LIST, kept in range.  Returns the
page shown."
  (setf (batch-page list) (max 0 (min page (1- (page-count list))))))

(defmethod render ((self batched-list))
  (let* ((pages (page-count self))
         (current (min (batch-page self) (1- pages))))
    (when (> pages 1)
      (h:nav (:class "lt-batch" :aria-label (translate "Pages"))
        (if (plusp current)
            (h:anchor (:callback (lambda () (go-to-page self (1- current))) :rel "prev") (translate "« Previous"))
            (h:span (:class "lt-disabled") (translate "« Previous")))
        (dotimes (page pages)
          (let ((page page))
            (if (= page current)
                (h:strong (:class "lt-current" :aria-current "page") (h:text (1+ page)))
                (h:anchor (:callback (lambda () (go-to-page self page))) (h:text (1+ page))))))
        (if (< current (1- pages))
            (h:anchor (:callback (lambda () (go-to-page self (1+ current))) :rel "next") (translate "Next »"))
            (h:span (:class "lt-disabled") (translate "Next »")))))))

;;; Report

(defclass report-column ()
  ((title :initarg :title :reader column-title)
   (value :initarg :value :reader column-value
          :documentation "Function of a row giving the cell's value, or NIL.")
   (render :initarg :render :initform nil :reader column-render
           :documentation "Function of (ROW VALUE) writing the cell, or NIL for TEXT.")
   (sort-key :initarg :sort-key :initform nil :reader column-sort-key)
   (sort-predicate :initarg :sort-predicate :initform #'value< :reader column-sort-predicate)
   (sortable :initarg :sortable :initform t :reader column-sortable-p)
   (css-class :initarg :class :initform nil :reader column-class))
  (:documentation "One column of a REPORT: its title, value, rendering and sorting."))

(defun column (title value &rest initargs &key render sort-key sort-predicate sortable class)
  "A REPORT column titled TITLE (translated) showing (FUNCALL VALUE ROW);
VALUE NIL gives every cell the value NIL.  RENDER, a function of the row
and the value, writes the cell; by default the value is written as text,
and NIL as nothing.  SORTABLE NIL leaves the heading a plain title.  The
column sorts by SORT-KEY, a function of the row (the value by default),
under SORT-PREDICATE (by default numbers by <, anything else by its
printed form, NIL last).  CLASS is the CSS class of the column's cells."
  (declare (ignore render sort-key sort-predicate sortable class))
  (apply #'make-instance 'report-column :title title :value value initargs))

(defun value< (a b)
  "Numbers by <, everything else by its printed form; NIL sorts last."
  (cond ((null b) (not (null a)))
        ((null a) nil)
        ((and (realp a) (realp b)) (< a b))
        (t (string-lessp (princ-to-string a) (princ-to-string b)))))

(defun column-cell-value (column row)
  "The value COLUMN shows for ROW."
  (and (column-value column) (funcall (column-value column) row)))

(defclass report (component)
  ((rows :initarg :rows :initform '() :accessor report-rows
         :documentation "A list, or a thunk returning one on every render.")
   (columns :initarg :columns :initform '() :accessor report-columns
            :documentation "The columns, made with COLUMN, in order.")
   (sort-column :initform nil :accessor report-sort-column)
   (descending :initform nil :accessor report-descending-p)
   (row-class :initarg :row-class :initform nil :accessor report-row-class
              :documentation "Function of a row giving its CSS class, or NIL.")
   (csv-filename :initarg :csv-filename :initform nil :reader report-csv-filename
                 :documentation "When given, the name of the CSV file a Download CSV link gives.")
   (batcher :initform nil :reader report-batcher))
  (:documentation "A table of :ROWS (a list, or a function returning one,
called on every render) in :COLUMNS (made with COLUMN), sorted by clicking
a heading, like Seaside's WATableReport.  :ROW-CLASS, a function of a row,
gives its CSS class.  Give :BATCH-SIZE to page it, and :CSV-FILENAME
(\"orders.csv\") for a Download CSV link (see REPORT-CSV)."))

(defmethod initialize-instance :after ((self report) &key batch-size)
  (when batch-size
    (setf (slot-value self 'batcher)
          (make-instance 'batched-list :batch-size batch-size
                                       :items (lambda () (sorted-rows self))))))

(defmethod states ((self report))
  (list self))

(defmethod children ((self report))
  (and (report-batcher self) (list (report-batcher self))))

(defun current-rows (report)
  "REPORT's rows, calling its thunk when it has one."
  (let ((rows (report-rows report)))
    (if (functionp rows) (funcall rows) rows)))

(defun sorted-rows (report)
  "REPORT's rows in its current sort order."
  (let ((rows (copy-list (current-rows report)))
        (column (report-sort-column report)))
    (if (null column)
        rows
        (let ((sorted (stable-sort rows (column-sort-predicate column)
                                   :key (or (column-sort-key column)
                                            (lambda (row) (column-cell-value column row))))))
          (if (report-descending-p report) (reverse sorted) sorted)))))

(defun sort-by (report column)
  "Sort REPORT by COLUMN, one of its columns, in ascending order, or
reverse the order when REPORT is sorted by COLUMN already.  A paged report
goes back to its first page."
  (if (eq column (report-sort-column report))
      (setf (report-descending-p report) (not (report-descending-p report)))
      (setf (report-sort-column report) column
            (report-descending-p report) nil))
  (when (report-batcher report)
    (go-to-page (report-batcher report) 0)))

(defun report-csv (report)
  "REPORT as CSV: every row, not just the page shown, in its current order,
under the titles of the columns that have values."
  (let ((columns (remove nil (report-columns report) :key #'column-value)))
    (csv-text (mapcar (lambda (c) (translate-label (column-title c))) columns)
              (mapcar (lambda (row) (mapcar (lambda (c) (column-cell-value c row)) columns))
                      (sorted-rows report)))))

(defmethod render ((self report))
  (let* ((rows (sorted-rows self))
         (batcher (report-batcher self))
         (shown (if batcher (batch batcher) rows)))
    (h:table (:class "lt-table lt-report")
      (h:thead ()
        (h:tr ()
          (dolist (column (report-columns self))
            (let ((column column))
              (h:th (:class (column-class column)
                   :aria-sort (when (and (column-sortable-p column) (eq column (report-sort-column self)))
                                (if (report-descending-p self) "descending" "ascending")))
                (if (column-sortable-p column)
                    (h:anchor (:callback (lambda () (sort-by self column)))
                      (h:text (translate-label (column-title column)))
                      (when (eq column (report-sort-column self))
                        (h:text (if (report-descending-p self) " ▼" " ▲"))))
                    (h:text (translate-label (column-title column)))))))))
      (h:tbody ()
        (dolist (row shown)
          (h:tr (:class (and (report-row-class self) (funcall (report-row-class self) row)))
            (dolist (column (report-columns self))
              (let ((value (column-cell-value column row)))
                (h:td (:class (column-class column))
                  (if (column-render column)
                      (funcall (column-render column) row value)
                      (when value (h:text value))))))))))
    (when batcher
      (render-component batcher))
    (when (report-csv-filename self)
      (h:p (:class "lt-csv")
        (h:anchor (:callback (lambda () (send-download (report-csv self) :filename (report-csv-filename self)
                                                                        :content-type "text/csv; charset=utf-8")))
          (translate "Download CSV"))))))
