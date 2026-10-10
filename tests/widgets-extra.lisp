;;;; widgets-extra.lisp — the data grid, charts, calendar, kanban and Markdown

(in-package #:littoral/tests)

(def-suite widgets-extra :in littoral)
(in-suite widgets-extra)

(test markdown-is-safe-and-useful
  (let ((html (markdown-html "# Title

Some *em*, **strong** and `<b>code</b>`.

- one
- [link](https://example.org/?a=1&b=2)
- [bad](javascript:alert(1))

> quoted

<script>alert(1)</script>
<img src=x onerror=alert(1)>

```
(defun f () '<x>)
```")))
    (is (search "<h3>Title</h3>" html))
    (is (search "<em>em</em>" html))
    (is (search "<strong>strong</strong>" html))
    (is (search "<code>&lt;b&gt;code&lt;/b&gt;</code>" html))
    (is (search "<ul><li>one</li>" html))
    (is (search "<a href=\"https://example.org/?a=1&amp;b=2\" rel=\"nofollow noopener\">link</a>" html))
    (is (not (search "href=\"javascript" html)))
    (is (search "<blockquote>" html))
    (is (not (search "<script" html)))
    (is (not (search "<img" html)))
    (is (search "<pre><code>(defun f () &#39;&lt;x&gt;)" html))))

(test charts-are-accessible-svg
  (let ((html (with-canvas-to-string ()
                (bar-chart '(("Mon" . 3) ("Tue" . 7)) :title "Orders")
                (line-chart '(("Visits" 1 4 2)) :title "Visits" :x-labels '("a" "b" "c"))
                (sparkline '(1 3 2) :label "Trend"))))
    (is (= 3 (length (cl-ppcre:all-matches-as-strings "role=\"img\"" html))))
    (is (search "<figcaption" html))
    (is (search "Orders" html))
    (is (search "<th>Tue</th><td>7</td>" html))
    (is (search "<polyline" html))
    (is (search "aria-label=\"Trend\"" html))))

(test the-calendar
  (let ((calendar (make-instance 'calendar :year 2026 :month 10
                                           :events '(((2026 10 9) . "Release")))))
    (let ((html (with-canvas-to-string () (render calendar))))
      (is (search "October 2026" html))
      (is (search "Release" html))
      ;; October 2026 begins on a Thursday: three blank days first.
      (is (= 3 (length (cl-ppcre:all-matches-as-strings "lt-calendar-blank" (subseq html 0 (search ">1<" html)))))))
    (littoral::shift-month calendar 3)
    (is (= 2027 (calendar-year calendar)))
    (is (= 1 (calendar-month calendar)))
    (is (= 29 (littoral::days-in 2028 2)))
    (is (= 28 (littoral::days-in 2027 2)))))

(test kanban-moves
  (let ((moves '())
        (board (make-instance 'kanban :columns '(("To do" "a" "b") ("Done" "c")))))
    (setf (slot-value board 'littoral::on-move) (lambda (item from to position) (push (list item from to position) moves)))
    (is (move-card board 0 0 1 1))
    (is (equal '(("To do" "b") ("Done" "c" "a")) (kanban-columns board)))
    (is (equal '(("a" "To do" "Done" 1)) moves))
    (littoral::apply-card-move board "1,0,0,0")
    (is (equal '(("To do" "c" "b") ("Done" "a")) (kanban-columns board)))
    ;; Nonsense is ignored.
    (is (null (littoral::apply-card-move board "9,9,9,9")))
    (is (null (littoral::apply-card-move board "rubbish")))))

(test the-data-grid-in-the-widgets-example
  (with-fresh-applications (("/widgets" 'littoral-examples:widget-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/widgets")
      (click b "Data grid")
      (is (has-text-p b "5 rows"))
      ;; Filtering, as littoral.js sends it while typing.
      (let* ((filter (cl-ppcre:register-groups-bind (name) ("<input[^>]*name=\"([0-9]+)\"[^>]*aria-label=\"Filter Name\"" (browser-html b)) name))
             (spec (first (ajax-specs b "on-input"))))
        (is (not (null filter)))
        (let ((json (ajax-request b (car spec) (cdr spec) :fields (list (cons filter "turing")))))
          (is (search "Alan Turing" json))
          (is (search "1 row" json))
          (is (not (search "Grace Hopper" json)))))
      ;; Editing in place, with the description's checks.  The filter stays:
      ;; the row shown is Alan Turing's.
      (visit b (browser-url b))
      (click b "Edit")
      (fill-in b "grid-email" "not an email")
      (press b "Save")
      (is (has-text-p b "must be an email address"))
      (fill-in b "grid-email" "alan@bletchley.example")
      (press b "Save")
      (is (has-text-p b "Saved Alan Turing."))
      (is (has-text-p b "alan@bletchley.example")))))

(test the-other-widget-tabs
  (with-fresh-applications (("/widgets" 'littoral-examples:widget-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/widgets")
      (click b "Charts")
      (is (has-text-p b "Orders this week"))
      (click b "Calendar")
      (is (has-text-p b "Today"))
      (click b "Kanban")
      (is (has-text-p b "Write the docs"))
      (click b "→")
      (is (search "Doing</span>" (cl-ppcre:regex-replace-all "<span class=\"lt-kanban-count\">[^<]*</span>" (browser-html b) "</span>")))
      (click b "Markdown")
      (is (search "<h3>A heading</h3>" (browser-html b)))
      (is (not (search "<script>alert" (browser-html b)))))))

(test the-monitoring-example
  (with-fresh-applications (("/monitoring" 'littoral-examples:monitoring-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/monitoring")
      (is (has-text-p b "Collecting samples"))
      (let ((spec (cl-ppcre:register-groups-bind (s) ("data-lt-periodical=\"[0-9]+;([^\"]*)\"" (browser-html b)) (unescape s))))
        (destructuring-bind (callback targets) (cl-ppcre:split ";" spec)
          (ajax-request b callback targets)
          (let ((json (ajax-request b callback targets)))
            (is (search "Requests" json))
            (is (search "<polyline" json))))))))
