;;;; widgets-data.lisp — load more, filter builders, virtual grids, more charts, event calendars

(in-package #:littoral/tests)

(def-suite widgets-data :in littoral)
(in-suite widgets-data)

(defun attribute-spec (b attribute pattern)
  "The (CALLBACK . TARGETS) of data-lt-ATTRIBUTE on the first element whose
start tag matches PATTERN."
  (cl-ppcre:register-groups-bind (spec)
      ((format nil "<[a-z0-9]+\\b[^>]*~A[^>]*data-lt-~A=\"([^\"]*)\"" pattern attribute) (browser-html b))
    (let* ((spec (unescape spec)) (semi (position #\; spec)))
      (cons (subseq spec 0 semi) (subseq spec (1+ semi))))))

(defun click-last (b text)
  "Follow the last link whose text is exactly TEXT."
  (click-nth b text (1- (length (find-links b text)))))

(defun id-matching (b regex)
  "The first match of REGEX's group in the page."
  (cl-ppcre:register-groups-bind (id) (regex (browser-html b)) id))

;;; Load more

(test load-more-lists
  (with-widgets (b)
    (click b "Load more")
    (let ((total (length (littoral-examples::cl-symbols-starting "")))
          (html (browser-html b)))
      (is (= 25 (count-matches "<li[ >]" (cl-ppcre:scan-to-strings "<ul class=\"lt-load-more-items\".*?</ul>" html))))
      (is (has-text-p b (format nil "Showing 25 of ~D." total)))
      (is (search "role=\"status\" aria-live=\"polite\"" html))
      (is (search "aria-label=\"Common Lisp symbols\"" html))
      ;; Infinite scrolling: littoral.js fires this as the button comes into view.
      (is (search "data-lt-lazy-visible" html))
      ;; Without JavaScript, the button is a link; the first new item takes the focus.
      (click-last b "Load more")
      (is (has-text-p b (format nil "Showing 50 of ~D." total)))
      (is (= 1 (count-matches "<li tabindex=\"-1\" autofocus>" (browser-html b))))
      (is (search (format nil "<li tabindex=\"-1\" autofocus><code>~(~A~)</code>"
                          (nth 25 (littoral-examples::cl-symbols-starting "")))
                  (browser-html b)))
      ;; Over AJAX, the list and its status are drawn again.
      (let* ((spec (attribute-spec b "on-click" "class=\"lt-load-more-button\""))
             (json (ajax-request b (car spec) (cdr spec))))
        (is (search (format nil "Showing 75 of ~D." total) json)))
      ;; Scrolling there loads more, but leaves the focus alone.
      (visit b (browser-url b))
      (let* ((spec (first (ajax-specs b "lazy")))
             (json (ajax-request b (car spec) (cdr spec))))
        (is (search (format nil "Showing 100 of ~D." total) json))
        (is (not (search "autofocus" json)))
        ;; The item the button gave the focus can keep it.
        (is (search "<li tabindex=\\\"-1\\\">" json))
        (is (search "data-lt-keep-focus" json)))
      ;; Kept on the server.
      (visit b (browser-url b))
      (is (has-text-p b (format nil "Showing 100 of ~D." total))))))

(defclass fetched-numbers (component)
  ((list :reader page-list
         :initform (make-instance 'load-more-list :batch-size 3
                                                  :fetch (lambda (start count)
                                                           (loop for i from start below (min 7 (+ start count))
                                                                 collect (format nil "number ~D" i))))))
  (:documentation "A load-more list fetching seven numbers three at a time."))

(defmethod children ((self fetched-numbers)) (list (page-list self)))
(defmethod render ((self fetched-numbers)) (render-component (page-list self)))

(test load-more-lists-fetch-a-batch-at-a-time
  (with-fresh-applications (("/numbers" 'fetched-numbers :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/numbers")
      (is (has-text-p b "number 2"))
      (is (not (has-text-p b "number 3")))
      (is (has-text-p b "Showing 3."))
      (click b "Load more")
      (click b "Load more")
      (is (has-text-p b "number 6"))
      (is (has-text-p b "Showing 7."))
      ;; Nothing left: no button.
      (is (not (search "lt-load-more-button" (browser-html b))))))
  (let ((list (make-instance 'load-more-list :items '(1 2 3) :batch-size 1)))
    (load-more list)
    (is (= 2 (load-more-shown list)))
    (reset-load-more list)
    (is (= 1 (load-more-shown list)))))

;;; Filter builders

(defclass sample-task ()
  ((name :initarg :name)
   (count :initarg :count :initform nil)
   (due :initarg :due :initform nil)
   (kind :initarg :kind :initform nil)
   (tags :initarg :tags :initform '())
   (urgent :initarg :urgent :initform nil))
  (:documentation "Something to do, with a field of each kind to filter by."))

(define-description sample-task
  ((name)
   (count :type :integer)
   (due :type :date)
   (kind :type :choice :choices '(:bug :feature :chore))
   (tags :type :multiple-choice :choices '("ui" "server" "docs"))
   (urgent :type :boolean)))

(defun sample-tasks ()
  "Four tasks to filter."
  (list (make-instance 'sample-task :name "Fix the login" :count 3 :due '(2026 10 20) :kind :bug
                                    :tags '("server") :urgent t)
        (make-instance 'sample-task :name "Dark mode" :count 12 :due '(2026 12 1) :kind :feature :tags '("ui"))
        (make-instance 'sample-task :name "Write the guide" :due '(2026 11 2) :kind :chore :tags '("docs" "ui"))
        (make-instance 'sample-task :name "fix typos" :count 1 :kind :chore)))

(defun names-passing (builder)
  "The names of the sample tasks BUILDER lets through."
  (loop for task in (sample-tasks)
        when (filter-matches-p builder task) collect (slot-value task 'name)))

(defun task-builder (&rest conditions)
  "A filter builder over sample tasks with CONDITIONS."
  (make-instance 'filter-builder :description 'sample-task :conditions conditions))

(test filter-conditions-by-kind
  (is (= 4 (length (names-passing (task-builder)))))
  (is (equal '("Fix the login" "fix typos") (names-passing (task-builder '(name :contains "FIX")))))
  (is (equal '("Dark mode" "Write the guide") (names-passing (task-builder '(name :not-contains "fix")))))
  (is (equal '("fix typos") (names-passing (task-builder '(name :is "Fix Typos")))))
  (is (equal '("Write the guide") (names-passing (task-builder '(name :starts "write")))))
  (is (equal '("Dark mode") (names-passing (task-builder '(count :> "3")))))
  (is (equal '("Fix the login" "Dark mode") (names-passing (task-builder '(count :>= "3")))))
  (is (equal '("Fix the login" "fix typos") (names-passing (task-builder '(count :<= "3")))))
  (is (equal '("Dark mode" "Write the guide" "fix typos") (names-passing (task-builder '(count :/= "3")))))
  (is (equal '("Write the guide") (names-passing (task-builder '(count :empty "")))))
  (is (equal '("Fix the login") (names-passing (task-builder '(due :< "2026-11-01")))))
  (is (equal '("Dark mode" "Write the guide") (names-passing (task-builder '(due :> "2026-10-20")))))
  (is (equal '("Write the guide") (names-passing (task-builder '(due := "2026-11-02")))))
  (is (equal '("Write the guide" "fix typos") (names-passing (task-builder '(kind :is "2")))))
  (is (equal '("Fix the login" "Dark mode") (names-passing (task-builder '(kind :is-not "2")))))
  (is (equal '("Dark mode" "Write the guide") (names-passing (task-builder '(tags :includes "0")))))
  (is (equal '("Fix the login" "fix typos") (names-passing (task-builder '(tags :excludes "0")))))
  (is (equal '("fix typos") (names-passing (task-builder '(tags :empty "")))))
  (is (equal '("Fix the login") (names-passing (task-builder '(urgent :yes "")))))
  (is (= 3 (length (names-passing (task-builder '(urgent :no "")))))))

(test filter-conditions-combine
  (is (equal '("Fix the login") (names-passing (task-builder '(name :contains "fix") '(count :> "2")))))
  (let ((any (task-builder '(name :contains "fix") '(count :> "10"))))
    (setf (filter-match any) :any)
    (is (equal '("Fix the login" "Dark mode" "fix typos") (names-passing any))))
  ;; Incomplete conditions, and values that don't parse, are left out.
  (is (= 4 (length (names-passing (task-builder '(name :contains "") '(due :< "soon") '(count :> "many"))))))
  (is (equal '("Dark mode") (names-passing (task-builder '(count :> "many") '(count :> "10"))))))

(test filter-operators-suit-the-field
  (let ((description (find-description 'sample-task)))
    (flet ((ops (name) (mapcar #'car (filter-operators (find-field description name)))))
      (is (equal '(:contains :not-contains :is :starts :empty :not-empty) (ops 'name)))
      (is (member :>= (ops 'count)))
      (is (equal '(:= :< :> :empty :not-empty) (ops 'due)))
      (is (equal '(:is :is-not :empty :not-empty) (ops 'kind)))
      (is (equal '(:includes :excludes :empty :not-empty) (ops 'tags)))
      (is (equal '(:yes :no) (ops 'urgent))))))

(test changing-filter-conditions
  (let ((b (task-builder)))
    (add-filter-condition b)
    (is (equal '((name :contains "")) (filter-conditions b)))
    (littoral::change-condition b 0 :text "fix")
    (littoral::change-condition b 0 :operator :starts)
    (is (equal '((name :starts "fix")) (filter-conditions b)))
    ;; A field of another kind: its first comparison, and no value.
    (littoral::change-condition b 0 :field 'count)
    (is (equal '((count := "")) (filter-conditions b)))
    ;; One it doesn't have is ignored.
    (littoral::change-condition b 0 :operator :starts)
    (is (equal '((count := "")) (filter-conditions b)))
    (add-filter-condition b 'kind)
    (is (equal '(kind :is "") (second (filter-conditions b))))
    (remove-filter-condition b 0)
    (is (equal '((kind :is "")) (filter-conditions b)))
    (clear-filter-conditions b)
    (is (null (filter-conditions b)))))

;;; The big table: a virtual grid with conditions

(defun shipments-where (test)
  "How many of the big table's shipments pass TEST."
  (count-if test (littoral-examples::sample-shipments 10000)))

(defun shipment-status (shipment)
  "SHIPMENT's status."
  (slot-value shipment 'littoral-examples::status))

(test virtual-grids-write-only-rows-near-the-screen
  (with-widgets (b)
    (click b "Big table")
    (let ((html (browser-html b))
          (on-the-way (shipments-where (lambda (s) (eq (shipment-status s) :on-the-way)))))
      (is (search "class=\"lt-grid-scroll lt-grid-virtual\" style=\"--lt-grid-visible: 12\"" html))
      (is (search (format nil "aria-rowcount=\"~D\"" (+ 2 on-the-way)) html))
      (is (has-text-p b (format nil "~D rows" on-the-way)))
      ;; Three screens of rows, and spacers for the rest.
      (is (= 36 (count-matches "<tr aria-rowindex=\"[0-9]+\"><td>" html)))
      (is (search "<tr aria-rowindex=\"3\"><td>" html))
      (is (search (format nil "data-lt-start=\"0\" data-lt-total=\"~D\" data-lt-window=\"36\" data-lt-visible=\"12\""
                          on-the-way)
                  html))
      (is (search (format nil "height: calc(~D * var(--lt-grid-row))" (- on-the-way 36)) html))
      ;; Scrolling: littoral.js posts the first row it wants.
      (let* ((spec (first (ajax-specs b "virtual")))
             (json (ajax-request b (car spec) (cdr spec) :fields '(("_lt_value" . "1000")))))
        (is (search "aria-rowindex=\\\"1003\\\"" json))
        (is (search "aria-rowindex=\\\"1038\\\"" json))
        (is (not (search "aria-rowindex=\\\"1002\\\"" json)))
        (is (search "height: calc(1000 * var(--lt-grid-row))" json))
        ;; Only the rows are drawn again.
        (is (not (search "lt-filter" json))))
      ;; The position is kept for the page coming back.
      (visit b (browser-url b))
      (is (search "data-lt-start=\"1000\"" (browser-html b)))
      ;; Past the end, the last rows.
      (let ((spec (first (ajax-specs b "virtual"))))
        (is (search (format nil "aria-rowindex=\\\"~D\\\"" (+ 2 on-the-way))
                    (ajax-request b (car spec) (cdr spec) :fields '(("_lt_value" . "99999")))))))))

(test virtual-grids-page-without-javascript
  (with-widgets (b)
    (click b "Big table")
    (is (search "<noscript><style>.lt-grid-spacer { display: none; }</style>" (browser-html b)))
    (is (has-text-p b "Rows 1–36 of"))
    (click b "Next »")
    (is (has-text-p b "Rows 37–72 of"))
    (is (search "<tr aria-rowindex=\"39\"><td>" (browser-html b)))
    (click b "« Previous")
    (is (has-text-p b "Rows 1–36 of"))))

(test the-big-table-has-conditions
  (with-widgets (b)
    (click b "Big table")
    (let ((html (browser-html b)))
      (is (search "class=\"lt-filter\" role=\"search\" aria-label=\"Conditions\"" html))
      (is (search "role=\"group\" aria-label=\"Condition 1\"" html))
      (is (search "<option value=\"1\" selected>On The Way</option>" html)))
    (let ((delivered (shipments-where (lambda (s) (eq (shipment-status s) :delivered)))))
      ;; Choosing another status, as littoral.js posts it.
      (let ((name (id-matching b "<select id=\"[^\"]+-0-value\" aria-label=\"Value\" name=\"([0-9]+)\""))
            (spec (attribute-spec b "on-change" "-0-value\"")))
        (is (not (null name)))
        (is (search (format nil "~D rows" delivered)
                    (ajax-request b (car spec) (cdr spec) :fields (list (cons name "2"))))))
      ;; A second condition, without JavaScript.
      (visit b (browser-url b))
      (press b "Add a condition")
      (is (search "aria-label=\"Condition 2\"" (browser-html b)))
      (is (search "autofocus" (cl-ppcre:scan-to-strings "<select[^>]*-1-field\"[^>]*>" (browser-html b))))
      (is (has-text-p b "Show what matches"))
      ;; Weight is at least 39 (of 1 to 40).
      (select-option b (id-matching b "id=\"([^\"]+-1-field)\"") "Weight (kg)")
      (press b "Apply")
      (select-option b (id-matching b "id=\"([^\"]+-1-operator)\"") "is at least")
      (fill-in b (id-matching b "id=\"([^\"]+-1-value)\"") "39")
      (press b "Apply")
      (is (has-text-p b (format nil "~D rows"
                                (shipments-where (lambda (s) (and (eq (shipment-status s) :delivered)
                                                                  (>= (slot-value s 'littoral-examples::weight) 39)))))))
      ;; A value that isn't a number says so, and is left out.
      (fill-in b (id-matching b "id=\"([^\"]+-1-value)\"") "heavy")
      (press b "Apply")
      (is (has-text-p b "Give a whole number."))
      (is (has-text-p b (format nil "~D rows" delivered)))
      ;; Removing the first leaves the second, which is incomplete.
      (press b "Remove")
      (is (not (search "aria-label=\"Condition 2\"" (browser-html b))))
      (is (search "autofocus" (cl-ppcre:scan-to-strings "<button[^>]*-add\"[^>]*>" (browser-html b))))
      (is (has-text-p b "10000 rows"))
      (press b "Clear")
      (is (not (search "aria-label=\"Condition 1\"" (browser-html b)))))))

;;; Charts

(test pie-charts
  (let ((html (h:with-canvas-to-string () (pie-chart '(("Email" . 3) ("Chat" . 1) ("None" . 0)) :title "Requests"))))
    (is (= 2 (count-matches "<path class=\"lt-chart-slice lt-series-[0-9]\"" html)))
    (is (search "<title>Email: 3 (75%)</title>" html))
    (is (search "<title>Chat: 1 (25%)</title>" html))
    (is (search "<ul class=\"lt-chart-key\"><li><span class=\"lt-chart-swatch lt-series-0\"></span>Email</li>" html))
    ;; The table has every row, nothing included.
    (is (search "<tr><th>None</th><td>0</td><td>0%</td></tr>" html))
    (is (not (search "lt-chart-total" html))))
  (let ((html (h:with-canvas-to-string () (pie-chart '(("All" . 5)) :title "One" :donut t))))
    (is (search "fill-rule=\"evenodd\"" html))
    (is (search "<text class=\"lt-chart-total\"" html))
    (is (search ">5</text>" html)))
  (let ((html (h:with-canvas-to-string () (pie-chart '(("A" . 0)) :title "Nothing"))))
    (is (search "<circle class=\"lt-chart-grid\"" html))
    (is (not (search "<path" html)))))

(test stacked-bar-charts
  (let ((html (h:with-canvas-to-string ()
                (stacked-bar-chart '(("Open" 2 0) ("Closed" 3 4)) :title "Tickets" :x-labels '("Q1" "Q2")))))
    ;; No segment for nothing.
    (is (= 3 (count-matches "<rect class=\"lt-chart-segment" html)))
    (is (search "<title>Closed, Q2: 4</title>" html))
    (is (search "<tr><th></th><td>Q1</td><td>Q2</td></tr>" html))
    (is (search "<tr><th>Open</th><td>2</td><td>0</td></tr>" html))
    (is (search "lt-chart-key" html))))

(test scatter-charts
  (let ((html (h:with-canvas-to-string ()
                (scatter-chart '(("Oaks" (1 . 2) (3 . 4)) ("Birches" (2 . 1))) :title "Trees"
                               :x-label "Age" :y-label "Height"))))
    (is (search "<circle class=\"lt-chart-point lt-series-0\"" html))
    ;; The second series has a shape of its own.
    (is (search "<rect class=\"lt-chart-point lt-series-1\"" html))
    (is (search "<title>Birches: 2, 1</title>" html))
    (is (search "<tr><th></th><td>Age</td><td>Height</td></tr>" html))
    (is (search "<tr><th>Oaks</th><td>3</td><td>4</td></tr>" html))
    (is (search ">Height</text>" html))
    (is (search "lt-chart-key" html)))
  ;; One series, no key; one point still makes axes.
  (let ((html (h:with-canvas-to-string () (scatter-chart '(("Only" (5 . 5))) :title "One"))))
    (is (not (search "lt-chart-key" html)))
    (is (search "lt-chart-grid" html))))

(test the-charts-tab-has-the-new-charts
  (with-widgets (b)
    (click b "Charts")
    (dolist (title '("Support requests by channel" "Tickets by quarter" "How trees grow"))
      (is (has-text-p b title)))))

;;; Event calendars

(test laying-out-a-day
  (is (equal '((a 0 60 0 1)) (littoral::lay-out-day '((0 60 a)))))
  (let ((layout (littoral::lay-out-day '((0 60 a) (30 90 b) (60 120 c) (200 230 d)))))
    (is (equal '(a 0 60 0 2) (find 'a layout :key #'first)))
    (is (equal '(b 30 90 1 2) (find 'b layout :key #'first)))
    ;; C starts as A ends, so it takes A's column.
    (is (equal '(c 60 120 0 2) (find 'c layout :key #'first)))
    (is (equal '(d 200 230 0 1) (find 'd layout :key #'first)))))

(test moments
  (is (equal '(2026 10 19 9 30) (littoral::minutes-moment (littoral::moment-minutes '(2026 10 19 9 30)))))
  (is (equal '(2026 10 20 0 15) (littoral::minutes-moment (+ (littoral::moment-minutes '(2026 10 19 23 45)) 30))))
  (is (equal '(2026 3 1) (littoral::add-days '(2026 2 28) 1)))
  (is (equal '(2026 10 19 9 30) (littoral::parse-moment "2026-10-19 09:30")))
  (is (null (littoral::parse-moment "2026-02-30 09:30")))
  (is (null (littoral::parse-moment "soon"))))

(defun week-event (b title)
  "The (CALLBACK . TARGETS) of the move spec on TITLE's link."
  (cl-ppcre:register-groups-bind (spec)
      ((format nil "data-lt-move=\"([^\"]*)\"[^>]*><span class=\"lt-schedule-time\">[^<]*</span> <span class=\"lt-schedule-title\">~A<" title)
       (browser-html b))
    (let* ((spec (unescape spec)) (semi (position #\; spec)))
      (cons (subseq spec 0 semi) (subseq spec (1+ semi))))))

(defun this-monday ()
  "This week's Monday, as the example's events have it."
  (littoral-examples::this-week-day 0))

(test the-week-calendar
  (with-widgets (b)
    (click b "Calendar")
    (let ((html (browser-html b)))
      (is (has-text-p b "This week"))
      (is (= 7 (count-matches "<section class=\"lt-schedule-day" html)))
      (is (search (format nil "data-lt-day=\"~A\"" (littoral::iso-date (this-monday))) html))
      (is (search "<span class=\"lt-schedule-time\">09:00–09:15</span> <span class=\"lt-schedule-title\">Standup</span>" html))
      ;; Pairing and the interview overlap on Wednesday: side by side.
      (is (search "--lt-from: 11.0; --lt-span: 3.0; --lt-col: 0; --lt-cols: 2" html))
      (is (search "--lt-from: 12.0; --lt-span: 2.0; --lt-col: 1; --lt-cols: 2" html))
      (is (search "aria-current=\"true\">Week</a>" html)))
    ;; Dragging the release to Friday at 10:30, as littoral.js posts it.
    (let* ((friday (littoral::add-days (this-monday) 4))
           (spec (week-event b "Release")))
      (ajax-request b (car spec) (cdr spec)
                    :fields (list (cons "_lt_value" (format nil "~A 10:30" (littoral::iso-date friday)))))
      (visit b (browser-url b))
      (is (search "10:30–11:00</span> <span class=\"lt-schedule-title\">Release" (browser-html b))))
    ;; Choosing an event, without JavaScript, shows buttons to move it.
    (click b "Retrospective")
    (is (search "role=\"group\" aria-label=\"Move Retrospective\"" (browser-html b)))
    (is (search "class=\"lt-button\" autofocus" (browser-html b)))
    (click b "Later")
    (is (has-text-p b "15:30–16:30"))
    (click b "Day before")
    (is (search (format nil "~A, 15:30–16:30" (littoral::day-label (littoral::add-days (this-monday) 3)))
                (browser-html b)))
    (click b "Close")
    (is (not (search "lt-schedule-move" (browser-html b))))
    ;; The focus goes back to the event.
    (is (search "class=\"lt-schedule-event-link\" autofocus" (browser-html b)))
    ;; The day view, and the next day.
    (click-nth b "Day" 0)
    (is (= 1 (count-matches "<section class=\"lt-schedule-day" (browser-html b))))
    (is (search "aria-label=\"Next day\"" (browser-html b)))
    (click-last b "›")
    (is (= 1 (count-matches "<section class=\"lt-schedule-day" (browser-html b))))))
