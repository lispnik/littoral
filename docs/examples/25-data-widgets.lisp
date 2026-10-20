;;;; The examples for lists that load more, filter builders, virtual data grids, pie, stacked bar and scatter charts, and event calendars.

;;;; Example: littoral:load-more-list littoral:load-more littoral:load-more-shown littoral:reset-load-more
;;; A `load-more-list` shows `:batch-size` items, then a Load more button for the next batch; with `:automatic t` the next batch also comes as the end of the list scrolls into view.  `:render-item` writes each item, and a status line says how many are shown.  `load-more` shows another batch, as the button does, and `reset-load-more` goes back to the first, as when the items change.
(defclass numbers-page (component)
  ((list :reader numbers
         :initform (make-instance 'load-more-list :items '(1 2 3 4 5 6 7) :batch-size 3
                                                  :render-item (lambda (n) (text (format nil "№ ~D" n)))))))
(defmethod children ((self numbers-page)) (list (numbers self)))
(defmethod render ((self numbers-page)) (render-component (numbers self)))
(with-fresh-applications (("/numbers" 'numbers-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/numbers")
    (let ((before (body-text b))
          (list (numbers (session-root (first (list-sessions (find-application "/numbers")))))))
      (click b "Load more")
      (list before (body-text b) (load-more-shown list)
            (progn (reset-load-more list) (load-more-shown list))))))
;; ⇒ ("№ 1 № 2 № 3 Load more Showing 3 of 7." "№ 1 № 2 № 3 № 4 № 5 № 6 Load more Showing 6 of 7." 6 3)

;;;; Example: littoral:filter-builder littoral:filter-matches-p littoral:filter-conditions littoral:filter-match
;;; A `filter-builder` holds conditions on a description's fields, each a field name, a comparison and the value as it would be typed (a choice by its position).  `filter-matches-p` says whether an object passes them all, or with `filter-match` `:any`, any one.  A condition without a value, or with one that doesn't parse, is left out.
(defclass bug ()
  ((title :initarg :title)
   (votes :initarg :votes)
   (severity :initarg :severity)))
(define-description bug
  ((title)
   (votes :type :integer)
   (severity :type :choice :choices '(:low :high))))
(let ((bugs (list (make-instance 'bug :title "Crash on save" :votes 12 :severity :high)
                  (make-instance 'bug :title "Typo on the about page" :votes 1 :severity :low)
                  (make-instance 'bug :title "Slow search" :votes 7 :severity :low)))
      (builder (make-instance 'filter-builder :description 'bug
                                              :conditions '((votes :>= "5") (severity :is "1")))))
  (flet ((passing () (loop for bug in bugs when (filter-matches-p builder bug) collect (slot-value bug 'title))))
    (list (passing)
          (progn (setf (filter-match builder) :any) (passing))
          (filter-conditions builder))))
;; ⇒ (("Crash on save") ("Crash on save" "Slow search") ((VOTES :>= "5") (SEVERITY :IS "1")))

;;;; Example: littoral:filter-operators
;;; The comparisons offered for a field depend on its kind: text, numbers, dates and times, choices, multiple choices, or yes and no.  Each is a keyword and the words shown for it.
(defclass trip ()
  ((leaving :initarg :leaving)
   (booked :initarg :booked)))
(define-description trip
  ((leaving :type :date)
   (booked :type :boolean)))
(list (filter-operators (find-field 'trip 'leaving))
      (filter-operators (find-field 'trip 'booked)))
;; ⇒ (((:= . "is") (:< . "is before") (:> . "is after") (:EMPTY . "is empty") (:NOT-EMPTY . "isn't empty")) ((:YES . "is yes") (:NO . "is no")))

;;;; Example: littoral:add-filter-condition littoral:remove-filter-condition littoral:clear-filter-conditions
;;; The builder's buttons call these: a new condition is on the first field with its first comparison unless told otherwise, and conditions are removed by position, from 0.
(defclass pet ()
  ((name :initarg :name)
   (age :initarg :age)))
(define-description pet
  ((name)
   (age :type :integer)))
(let ((builder (make-instance 'filter-builder :description 'pet)))
  (add-filter-condition builder)
  (add-filter-condition builder 'age :< "3")
  (list (filter-conditions builder)
        (progn (remove-filter-condition builder 0) (filter-conditions builder))
        (progn (clear-filter-conditions builder) (filter-conditions builder))))
;; ⇒ (((NAME :CONTAINS "") (AGE :< "3")) ((AGE :< "3")) NIL)

;;;; Example: littoral:data-grid-filter
;;; A data grid with `:conditions` has a filter builder above it, and shows only the rows that pass; `data-grid-filter` is that builder.  `:conditions t` starts with none, and a list of conditions starts with those.  `:virtual`, a number of rows, shows that many at once in a box that scrolls through the rest, writing only the rows near those on screen (three screens' worth) and fetching others as it scrolls; without JavaScript it has Previous and Next links.
(defclass reading ()
  ((hour :initarg :hour)
   (level :initarg :level)))
(define-description reading
  ((hour :type :integer)
   (level :type :integer)))
(defclass readings-page (component)
  ((grid :reader grid
         :initform (make-instance 'data-grid :description 'reading :virtual 5
                                             :rows (loop for hour below 100
                                                         collect (make-instance 'reading :hour hour :level (mod (* hour 7) 10)))
                                             :conditions '((level :> "6"))))))
(defmethod children ((self readings-page)) (list (grid self)))
(defmethod render ((self readings-page)) (render-component (grid self)))
(with-fresh-applications (("/readings" 'readings-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/readings")
    (list (filter-conditions (data-grid-filter (grid (session-root (first (list-sessions (find-application "/readings")))))))
          (cl-ppcre:count-matches "<tr aria-rowindex=\"\\d+\"><td>" (browser-html b))
          (cl-ppcre:scan-to-strings "\\d+ rows Rows 1–15 of \\d+" (body-text b)))))
;; ⇒ (((LEVEL :> "6")) 15 "30 rows Rows 1–15 of 30")

;;;; Example: littoral:pie-chart
;;; A pie chart of (label . value) pairs, as SVG: each slice titled with its label, value and share, a key, and the data as a table for screen readers.  `:donut t` cuts out the middle and writes the total there.
(let ((html (with-canvas-to-string ()
              (pie-chart '(("Tea" . 6) ("Coffee" . 3) ("Water" . 1)) :title "Drinks" :donut t))))
  (list (cl-ppcre:all-matches-as-strings "<title>[^<]*</title>" html)
        (cl-ppcre:register-groups-bind (total) ("<text class=\"lt-chart-total\"[^>]*>([^<]*)</text>" html) total)))
;; ⇒ (("<title>Tea: 6 (60%)</title>" "<title>Coffee: 3 (30%)</title>" "<title>Water: 1 (10%)</title>") "10")

;;;; Example: littoral:stacked-bar-chart
;;; A bar for each point of the series, each series' value stacked on the one before, with a key; the series are (name . values) as for `line-chart`.
(let ((html (with-canvas-to-string ()
              (stacked-bar-chart '(("Won" 3 5) ("Lost" 2 1)) :title "Matches" :x-labels '("Spring" "Autumn")))))
  (cl-ppcre:all-matches-as-strings "<title>[^<]*</title>" html))
;; ⇒ ("<title>Won, Spring: 3</title>" "<title>Lost, Spring: 2</title>" "<title>Won, Autumn: 5</title>" "<title>Lost, Autumn: 1</title>")

;;;; Example: littoral:scatter-chart
;;; Points, (x . y), for each series (name . points), each series with a colour and a shape of its own, and axes named by `:x-label` and `:y-label`.
(let ((html (with-canvas-to-string ()
              (scatter-chart '(("Hens" (1 . 250) (2 . 230)) ("Ducks" (1 . 180))) :title "Eggs a year"
                             :x-label "Age" :y-label "Eggs"))))
  (list (cl-ppcre:all-matches-as-strings "<title>[^<]*</title>" html)
        (cl-ppcre:all-matches-as-strings "<(circle|rect) class=\"lt-chart-point [^\"]*\"" html)))
;; ⇒ (("<title>Hens: 1, 250</title>" "<title>Hens: 2, 230</title>" "<title>Ducks: 1, 180</title>") ("<circle class=\"lt-chart-point lt-series-0\"" "<circle class=\"lt-chart-point lt-series-0\"" "<rect class=\"lt-chart-point lt-series-1\""))

;;;; Example: littoral:event-calendar littoral:event-calendar-view littoral:event-calendar-date
;;; A week (or, with `event-calendar-view` `:day`, a day) of timed events on a grid of hours, by default plists with `:title`, `:start` (year month day hour minute) and `:minutes`.  With `:on-move`, events can be dragged to another time or day; choosing one also shows buttons that move it, which work without JavaScript.  `:on-move` does the moving: here, by replacing the event's start.
(defclass diary-page (component)
  ((events :initform (list (list :title "Dentist" :start '(2026 10 20 9 0) :minutes 30))
           :accessor events)
   (calendar :reader calendar)))
(defmethod initialize-instance :after ((self diary-page) &key)
  (setf (slot-value self 'calendar)
        (make-instance 'event-calendar :date '(2026 10 19) :hours '(8 . 12)
                                       :events (lambda () (events self))
                                       :event-key (lambda (event) (getf event :title))
                                       :on-move (lambda (event start)
                                                  (setf (events self)
                                                        (list (list* :start start (alexandria:remove-from-plist event :start))))))))
(defmethod children ((self diary-page)) (list (calendar self)))
(defmethod render ((self diary-page)) (render-component (calendar self)))
(with-fresh-applications (("/diary" 'diary-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/diary")
    (click b "Dentist")
    (click b "Later")
    (click b "Day after")
    (let ((page (session-root (first (list-sessions (find-application "/diary"))))))
      (list (getf (first (events page)) :start)
            (event-calendar-view (calendar page))
            (event-calendar-date (calendar page))
            (cl-ppcre:scan-to-strings "Dentist Wed, [^,]*, 2026, [0-9:–]+" (body-text b))))))
;; ⇒ ((2026 10 21 9 30) :WEEK (2026 10 19) "Dentist Wed, October 21, 2026, 09:30–10:00")
