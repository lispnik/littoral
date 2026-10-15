;;;; The examples for the data grid, charts, the calendar, the kanban board and Markdown.

;;;; Example: littoral:data-grid
;;; A data grid shows a description's objects in a table and edits a row in place, with the description's own inputs and checks.  `:on-save` is called with the object once an edit is written to it.
(defclass person ()
  ((name :initarg :name)
   (email :initarg :email)))
(define-description person
  ((name :required t)
   (email :type :email :required t)))
(defclass people (component)
  ((grid :reader grid)
   (saved :initform nil :accessor saved)))
(defmethod initialize-instance :after ((self people) &key)
  (setf (slot-value self 'grid)
        (make-instance 'data-grid
                       :description 'person
                       :rows (list (make-instance 'person :name "Ada" :email "ada@example.org")
                                   (make-instance 'person :name "Alan" :email "alan@example.org"))
                       :on-save (lambda (person) (setf (saved self) (slot-value person 'name))))))
(defmethod states ((self people))
  (list self))
(defmethod children ((self people))
  (list (grid self)))
(defmethod render ((self people))
  (render-component (grid self))
  (when (saved self) (p () "Saved " (text (saved self)))))
(with-fresh-applications (("/people" 'people :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/people")
    (click-nth b "Edit" 1)
    (fill-in b "grid-email" "turing@example.org")
    (press b "Save")
    (body-text b)))
;; ⇒ "Name Email Actions Ada ada@example.org Edit Alan turing@example.org Edit 2 rows Saved Alan"

;;;; Example: littoral:data-grid
;;; Each column has a filter box; littoral.js sends what is typed over AJAX and the grid redraws with the rows that match.  `:fields` chooses the columns and `:page-size` the rows per page (10 by default).
(defclass city ()
  ((name :initarg :name)
   (country :initarg :country)))
(define-description city
  ((name :required t)
   (country :required t)))
(defclass cities (data-grid) ()
  (:default-initargs
   :description 'city
   :fields '(name)
   :page-size 2
   :rows (list (make-instance 'city :name "Lyon" :country "France")
               (make-instance 'city :name "Lille" :country "France")
               (make-instance 'city :name "Leeds" :country "England")
               (make-instance 'city :name "York" :country "England"))))
(with-fresh-applications (("/cities" 'cities :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/cities")
    (let* ((before (body-text b))
           (typing (first (ajax-specs b "on-input")))
           (filter (element-name b (cl-ppcre:register-groups-bind (id) ("<input[^>]*id=\"([^\"]+)\"" (browser-html b)) id)))
           (json (ajax-request b (first typing) (rest typing) :fields (list (cons filter "ly")))))
      (list before (not (null (search "1 row" json))) (not (null (search "Lille" json)))))))
;; ⇒ ("Name Actions Lyon Edit Lille Edit 4 rows 1 / 2 Next »" T NIL)

;;;; Example: littoral:bar-chart
;;; A bar chart is SVG in a figure, captioned by `title`, with the data as a table for screen readers.  Each bar's title gives its label and value, written by `:format-value`.
(let ((html (with-canvas-to-string ()
              (bar-chart '(("Mon" . 3) ("Tue" . 7) ("Wed" . 5))
                         :title "Orders"
                         :format-value (lambda (n) (format nil "~D orders" n))))))
  (list (cl-ppcre:all-matches-as-strings "<title>[^<]*</title>" html)
        (not (null (search "<figcaption" html)))))
;; ⇒ (("<title>Mon: 3 orders</title>" "<title>Tue: 7 orders</title>" "<title>Wed: 5 orders</title>") T)

;;;; Example: littoral:line-chart
;;; One line per series, each a name and its values; `:x-labels` name the points.  With more than one series the chart has a legend.
(let ((html (with-canvas-to-string ()
              (line-chart '(("Visits" 10 40 25) ("Sign-ups" 1 4 2))
                          :title "This week" :x-labels '("Mon" "Tue" "Wed")))))
  (list (length (cl-ppcre:all-matches-as-strings "<polyline" html))
        (cl-ppcre:all-matches-as-strings "● [^<]*" html)))
;; ⇒ (2 ("● Visits" "● Sign-ups"))

;;;; Example: littoral:sparkline
;;; A small line with no axes, labelled for screen readers.
(with-canvas-to-string ()
  (sparkline '(1 3 2) :label "Errors this hour" :width 40 :height 10))
;; ⇒ "<svg class=\"lt-sparkline\" width=\"40\" height=\"10\" viewBox=\"0 0 40 10\" role=\"img\" aria-label=\"Errors this hour\"><polyline points=\"1.0,6.3 20.0,1.0 39.0,3.7\"/></svg>"

;;;; Example: littoral:calendar littoral:calendar-year littoral:calendar-month
;;; A month of days with their events, Monday first.  `:year` and `:month` default to the current month.
(let* ((calendar (make-instance 'calendar :year 2026 :month 10
                                          :events '(((2026 10 9) . "Release"))))
       (html (with-canvas-to-string () (render calendar))))
  (list (calendar-year calendar) (calendar-month calendar)
        (not (null (search "October 2026" html)))
        (not (null (search "<li>Release</li>" html)))))
;; ⇒ (2026 10 T T)

;;;; Example: littoral:calendar
;;; With `:on-select`, each day is a link that calls it with the date.  The arrows go to the months before and after.
(defclass planner (component)
  ((calendar :reader planner-calendar)
   (day :initform nil :accessor day)))
(defmethod initialize-instance :after ((self planner) &key)
  (setf (slot-value self 'calendar)
        (make-instance 'calendar :year 2026 :month 10
                                 :on-select (lambda (date) (setf (day self) date)))))
(defmethod states ((self planner))
  (list self))
(defmethod children ((self planner))
  (list (planner-calendar self)))
(defmethod render ((self planner))
  (render-component (planner-calendar self))
  (when (day self) (p (:id "chosen") (text (format nil "Chose ~{~D-~2,'0D-~2,'0D~}" (day self))))))
(with-fresh-applications (("/planner" 'planner :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/planner")
    (click b "›")
    (click b "9")
    (list (not (null (has-text-p b "November 2026")))
          (cl-ppcre:scan-to-strings "Chose \\S+" (body-text b)))))
;; ⇒ (T "Chose 2026-11-09")

;;;; Example: littoral:kanban littoral:kanban-columns littoral:move-card
;;; A board's columns are (`title` . `items`).  `move-card` moves a card by column and position, and calls `:on-move` with the card, the titles of the columns it left and joined, and its new position.
(let* ((moves '())
       (board (make-instance 'kanban :columns '(("To do" "Write" "Test") ("Done" "Plan"))
                                     :on-move (lambda (card from to position)
                                                (push (list card from to position) moves)))))
  (move-card board 0 1 1 0)
  (list (kanban-columns board) moves (move-card board 5 0 0 0)))
;; ⇒ ((("To do" "Write") ("Done" "Test" "Plan")) (("Test" "To do" "Done" 0)) NIL)

;;;; Example: littoral:kanban
;;; In a page, cards are dragged between columns (with littoral.js) or moved with the arrows on each card.  Each column's heading counts its cards.
(defclass chores-board (kanban) ()
  (:default-initargs :columns '(("To do" "Shop" "Cook") ("Done"))))
(with-fresh-applications (("/board" 'chores-board :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/board")
    (click b "→")
    (body-text b)))
;; ⇒ "To do 1 Cook → Done 1 Shop ←"

;;;; Example: littoral:markdown-html
;;; Markdown as HTML.  Headings start at h3 for #, h4 for ##, so they sit under a page's own.
(markdown-html "## Notes

Bring *two* copies of the **form**.

- A pen
- Your `ticket`")
;; ⇒ "<h4>Notes</h4><p>Bring <em>two</em> copies of the <strong>form</strong>.</p><ul><li>A pen</li><li>Your <code>ticket</code></li></ul>"

;;;; Example: littoral:markdown-html
;;; Whoever wrote it, the result is safe to show: HTML in the text is escaped, and links go only to http(s), mailto or this site.
(markdown-html "<script>alert(1)</script> [home](/) [bad](javascript:alert(1))")
;; ⇒ "<p>&lt;script&gt;alert(1)&lt;/script&gt; <a href=\"/\" rel=\"nofollow noopener\">home</a> [bad](javascript:alert(1))</p>"

;;;; Example: littoral:markdown-field
;;; The description field kind `:markdown`: entered in a text area, shown as HTML.
(defclass announcement ()
  ((body :initform "Doors open at **seven**.")))
(define-description announcement
  ((body :type :markdown)))
(let ((field (find-field 'announcement 'body)))
  (with-canvas-to-string ()
    (render-field-value field (field-value field (make-instance 'announcement)))))
;; ⇒ "<div class=\"lt-markdown\"><p>Doors open at <strong>seven</strong>.</p></div>"
