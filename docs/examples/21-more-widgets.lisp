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

;;;; Example: littoral:breadcrumb-trail littoral:breadcrumb-label littoral:breadcrumb-trail-of
;;; A trail names a component, then what it has called, and so on down to what shows now, which is not a link.  Following a link goes back to that level.  Render the trail outside the component it follows, which a call replaces.
(defclass inbox (component) ())
(defclass letter (component) ())
(defmethod breadcrumb-label ((self letter)) "Hello, Ada")
(defmethod render ((self inbox))
  (anchor (:callback (lambda () (show self (make-instance 'letter)))) "Open"))
(defmethod render ((self letter))
  (p () "Dear Ada,"))
(defclass mail-page (component)
  ((inbox :initform (make-instance 'inbox) :reader inbox)
   (trail :reader trail)))
(defmethod initialize-instance :after ((self mail-page) &key)
  (setf (slot-value self 'trail) (make-instance 'breadcrumb-trail :of (inbox self))))
(defmethod children ((self mail-page)) (list (trail self) (inbox self)))
(defmethod render ((self mail-page))
  (render-component (trail self))
  (render-component (inbox self)))
(with-fresh-applications (("/mail" 'mail-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/mail")
    (click b "Open")
    (let ((opened (body-text b)))
      (click b "Inbox")
      (list opened (body-text b)))))
;; ⇒ ("Inbox Hello, Ada Dear Ada," "Inbox Open")

;;;; Example: littoral:in-place-editor littoral:make-in-place-editor
;;; One field of one object, edited where it is shown: Edit turns it into the field's input, and Save checks the text as the description says and writes the value.  Both go over AJAX; here the fake browser reloads the page to see each step.
(defclass guest () ((name :initarg :name :accessor guest-name)))
(define-description guest ((name :required t)))
(defvar *ada* (make-instance 'guest :name "Ada"))
(defclass guest-page (component)
  ((editor :initform (make-in-place-editor *ada* 'name) :reader editor)))
(defmethod children ((self guest-page)) (list (editor self)))
(defmethod render ((self guest-page)) (render-component (editor self)))
(with-fresh-applications (("/guest" 'guest-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/guest")
    (let ((before (body-text b))
          (edit (first (ajax-specs b "on-click"))))
      (ajax-request b (car edit) (cdr edit))
      (visit b (browser-url b))
      (let ((save (first (ajax-specs b "on-submit")))
            (input (cl-ppcre:register-groups-bind (name) ("<input[^>]* name=\"(\\d+)\"" (browser-html b)) name)))
        (ajax-request b (car save) (cdr save) :fields (list (cons input "Ada Lovelace")))
        (visit b (browser-url b))
        (list before (body-text b) (guest-name *ada*))))))
;; ⇒ ("Ada Edit" "Ada Lovelace Edit" "Ada Lovelace")

;;;; Example: littoral:data-grid-csv
;;; A data grid's rows as CSV: what its filters let through, in its order, each field as the grid shows it.  `:csv-filename` adds a Download CSV link.
(defclass city () ((name :initarg :name) (people :initarg :people)))
(define-description city ((name) (people :type :integer)))
(cl-ppcre:split "\\r\\n" (data-grid-csv (make-instance 'data-grid :description 'city
                                                               :rows (list (make-instance 'city :name "Lyon" :people 520000)
                                                                           (make-instance 'city :name "Nice" :people 340000)))))
;; ⇒ ("Name,People" "Lyon,520000" "Nice,340000")

;;;; Example: littoral:edit-conflict littoral:edit-conflict-object
;;; When someone else changed the value since Edit was pressed, Save says so and leaves theirs; saving again replaces it.  An :ON-SAVE that signals EDIT-CONFLICT (as littoral.db's STALE-OBJECT does, for rows changed meanwhile) is reported the same way, and nothing is kept.
(defclass memo () ((text :initarg :text :accessor memo-text)))
(define-description memo ((text)))
(defvar *memo* (make-instance 'memo :text "Draft"))
(defclass memo-page (component)
  ((editor :initform (make-in-place-editor *memo* 'text) :reader editor)))
(defmethod children ((self memo-page)) (list (editor self)))
(defmethod render ((self memo-page)) (render-component (editor self)))
(defun press-edit (b)
  (let ((spec (first (ajax-specs b "on-click"))))
    (ajax-request b (car spec) (cdr spec))
    (visit b (browser-url b))))
(defun save-as (b text)
  (let ((spec (first (ajax-specs b "on-submit")))
        (input (cl-ppcre:register-groups-bind (name) ("<input[^>]* name=\"(\\d+)\"" (browser-html b)) name)))
    (ajax-request b (car spec) (cdr spec) :fields (list (cons input text)))))
(with-fresh-applications (("/memo" 'memo-page :mode :deployment))
  (let ((mine (make-instance 'browser)) (theirs (make-instance 'browser)))
    (visit mine "/memo") (press-edit mine)
    (visit theirs "/memo") (press-edit theirs)
    (save-as theirs "Their text")
    (list (and (search "Someone else changed this to “Their text” meanwhile." (save-as mine "My text")) t)
          (memo-text *memo*)
          (progn (save-as mine "My text") (memo-text *memo*))
          (eq *memo* (edit-conflict-object (make-condition 'edit-conflict :object *memo*))))))
;; ⇒ (T "Their text" "My text" T)

;;;; Example: littoral:disclosure littoral:disclosure-open-p
;;; A line that opens and closes a component beneath it.  It is an HTML details element, so it works without JavaScript; with it, opening goes over AJAX and is remembered.
(defclass small-print (component) ())
(defmethod render ((self small-print)) (p () "No refunds after 30 days."))
(defclass terms (component)
  ((more :initform (make-instance 'disclosure :summary "Small print" :content (make-instance 'small-print))
         :reader more)))
(defmethod children ((self terms)) (list (more self)))
(defmethod render ((self terms)) (render-component (more self)))
(with-fresh-applications (("/terms" 'terms :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/terms")
    (let ((closed (search "<details class=\"lt-disclosure\" open" (browser-html b)))
          (toggle (first (ajax-specs b "on-click"))))
      (ajax-request b (car toggle) (cdr toggle))
      (visit b (browser-url b))
      (list closed
            (and (search "<details class=\"lt-disclosure\" open" (browser-html b)) t)
            (body-text b)))))
;; ⇒ (NIL T "Small print No refunds after 30 days.")

;;;; Example: littoral:accordion littoral:accordion-sections littoral:accordion-open
;;; Sections that open one at a time (or several, with `:multiple t`).  ACCORDION-OPEN lists the indexes open.
(defclass answer-text (component) ((words :initarg :words :reader words)))
(defmethod render ((self answer-text)) (p () (text (words self))))
(defun open-sections (html)
  "The titles of the accordion sections open in HTML."
  (let ((titles '()))
    (cl-ppcre:do-register-groups (title) ("<details class=\"lt-accordion-section\" open[^>]*><summary[^>]*>([^<]*)<" html)
      (push title titles))
    (nreverse titles)))
(defclass faq-page (component)
  ((faq :initform (make-instance 'accordion :open '(0)
                                            :sections (list (cons "Shipping" (make-instance 'answer-text :words "Two days."))
                                                            (cons "Returns" (make-instance 'answer-text :words "Thirty days."))))
        :reader faq)))
(defmethod children ((self faq-page)) (list (faq self)))
(defmethod render ((self faq-page)) (render-component (faq self)))
(with-fresh-applications (("/faq" 'faq-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/faq")
    (let ((before (open-sections (browser-html b)))
          (returns (second (ajax-specs b "on-click"))))
      (ajax-request b (car returns) (cdr returns))   ; open Returns: Shipping closes
      (visit b (browser-url b))
      (let ((faq (make-instance 'accordion :sections (list (cons "One" nil)) :open '(0))))
        (list before (open-sections (browser-html b))
              (mapcar #'car (accordion-sections faq)) (accordion-open faq))))))
;; ⇒ (("Shipping") ("Returns") ("One") (0))

;;;; Example: littoral:dropdown-menu littoral:menu-bar littoral:menu-items
;;; A dropdown lists items, each a label and a function to call or a URL to go to; a menu bar is a row of links and dropdowns.  Both are details elements, so they open without JavaScript; littoral.js closes them on Escape or a click elsewhere.
(defvar *chosen* nil)
(defclass toolbar (component)
  ((bar :initform (make-instance 'menu-bar
                                 :items (list (cons "Home" "/")
                                              (cons "Edit" (list (cons "Undo" (lambda () (setf *chosen* "Undo")))
                                                                 :separator
                                                                 (cons "Select all" (lambda () (setf *chosen* "Select all")))))))
        :reader bar)))
(defmethod children ((self toolbar)) (list (bar self)))
(defmethod render ((self toolbar)) (render-component (bar self)))
(with-fresh-applications (("/tools" 'toolbar :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tools")
    (click b "Select all")
    (list *chosen* (length (menu-items (make-instance 'dropdown-menu :label "More" :items '(("A" . "/a") :separator)))))))
;; ⇒ ("Select all" 2)

;;;; Example: littoral:lazy-panel littoral:lazy-panel-loaded-p littoral:lazy-panel-content
;;; A lazy panel is sent as a placeholder; littoral.js asks for its content over AJAX as soon as the page is in (the `lazy` spec here), and only then is the function making it called.  Once loaded, it is drawn with the page.
(defclass slow-total (component)
  ((total :initarg :total :reader total)))
(defmethod render ((self slow-total))
  (p () (text (format nil "Total: ~D" (total self)))))
(defvar *made* 0)
(defclass ledger (component)
  ((panel :initform (make-instance 'lazy-panel
                                   :placeholder "Adding it up…"
                                   :content (lambda ()
                                              (incf *made*)
                                              (make-instance 'slow-total :total (reduce #'+ (alexandria:iota 101)))))
          :reader panel)))
(defmethod children ((self ledger)) (list (panel self)))
(defmethod render ((self ledger)) (render-component (panel self)))
(with-fresh-applications (("/ledger" 'ledger :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/ledger")
    (let ((first-page (list (not (null (has-text-p b "Adding it up…"))) *made*))
          (spec (first (ajax-specs b "lazy"))))
      (ajax-request b (car spec) (cdr spec))
      (visit b (browser-url b))
      (list first-page *made* (body-text b)))))
;; ⇒ ((T 0) 1 "Total: 5050")

;;;; Example: littoral:load-lazy-panel
;;; Loading it from Lisp, as a callback might, makes the content at once; loading it again changes nothing.
(let ((panel (make-instance 'lazy-panel :content (lambda () (make-instance 'component)))))
  (list (lazy-panel-loaded-p panel)
        (progn (load-lazy-panel panel) (lazy-panel-loaded-p panel))
        (eq (lazy-panel-content panel) (lazy-panel-content (load-lazy-panel panel)))))
;; ⇒ (NIL T T)

;;;; Example: littoral:text-diff
;;; The lines of two texts compared, keeping as many the same as possible; within a change, what was removed comes first.
(text-diff (format nil "eggs~%milk~%bread~%") (format nil "eggs~%oat milk~%bread~%jam~%"))
;; ⇒ ((:SAME . "eggs") (:REMOVED . "milk") (:ADDED . "oat milk") (:SAME . "bread") (:ADDED . "jam"))

;;;; Example: littoral:diff-view littoral:diff-view-old littoral:diff-view-new littoral:diff-view-layout
;;; A diff view shows two texts' differences, line by line, with the words that changed in a changed line marked.  Its texts can be changed, and its layout switched between :INLINE and :SIDE-BY-SIDE.
(defclass recipe-changes (component)
  ((diff :initform (make-instance 'diff-view :old (format nil "Flour~%Butter~%Sugar")
                                             :new (format nil "Flour~%Salted Butter~%Sugar")
                                             :old-label "Saturday" :new-label "Sunday")
         :reader diff)))
(defmethod children ((self recipe-changes)) (list (diff self)))
(defmethod render ((self recipe-changes)) (render-component (diff self)))
(with-fresh-applications (("/recipe" 'recipe-changes :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/recipe")
    (let ((inline (body-text b))
          (marked (cl-ppcre:all-matches-as-strings "<mark class=\"lt-diff-word\">[^<]*</mark>" (browser-html b))))
      (click b "Side by side")
      (list inline marked (not (null (search "lt-diff-sides" (browser-html b))))))))
;; ⇒ ("1 line added, 1 line removed Inline Side by side Saturday Sunday Line 1 1 Flour 2 Removed: Butter 2 Added: Salted Butter 3 3 Sugar" ("<mark class=\"lt-diff-word\">Salted </mark>") T)

;;;; Example: littoral:diff-view-old littoral:diff-view-new littoral:diff-view-layout
;;; The accessors, for showing other texts or the other layout.
(let ((view (make-instance 'diff-view :old "a" :new "b")))
  (setf (diff-view-new view) "c"
        (diff-view-layout view) :side-by-side)
  (list (diff-view-old view) (diff-view-new view) (diff-view-layout view)))
;; ⇒ ("a" "c" :SIDE-BY-SIDE)

;;;; Example: littoral:command-palette littoral:palette-command
;;; A command palette ranks its commands against what is typed into it (littoral.js sends that over AJAX, as `on-input` here) and lists the best as links; following one runs it.  Ctrl-K or ⌘K opens it in a browser.
(defclass editor-page (component)
  ((saved :initform nil :accessor saved)
   (palette :reader palette)))
(defmethod initialize-instance :after ((self editor-page) &key)
  (setf (slot-value self 'palette)
        (make-instance 'command-palette
                       :commands (list (palette-command "Save" (lambda () (setf (saved self) t)) :group "File")
                                       (palette-command "Save as…" (lambda ()) :group "File")
                                       (palette-command "Find" (lambda ()) :keywords '("search"))
                                       (palette-command "Help" "/help")))))
(defmethod children ((self editor-page)) (list (palette self)))
(defmethod render ((self editor-page))
  (render-component (palette self))
  (when (saved self) (p () "Saved.")))
(with-fresh-applications (("/edit" 'editor-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/edit")
    (let* ((box (cl-ppcre:register-groups-bind (name) ("<input type=\"search\" name=\"([^\"]+)\"" (browser-html b)) name))
           (typing (first (ajax-specs b "on-input")))
           (json (ajax-request b (car typing) (cdr typing) :fields (list (cons box "sav")))))
      (visit b (browser-url b))
      (list (not (null (search "Save as…" json)))
            (not (null (search "Find" json)))
            (progn (click b "Save") (not (null (has-text-p b "Saved."))))))))
;; ⇒ (T NIL T)

;;;; Example: littoral:palette-matches littoral:palette-match-score littoral:palette-query littoral:palette-command-label littoral:palette-command-action littoral:palette-command-group littoral:palette-command-keywords
;;; What a palette shows for its query: its commands ranked by PALETTE-MATCH-SCORE (a run of the query found whole scores best, then the starts of words), then what its :SEARCH function adds.
(let ((palette (make-instance 'command-palette
                              :commands (list (palette-command "New project" "/projects/new" :group "Projects")
                                              (palette-command "Go to projects" "/projects" :keywords '("list"))
                                              (palette-command "Audit log" "/audit"))
                              :search (lambda (query)
                                        (list (palette-command (format nil "Search the docs for ~S" query) "/docs"))))))
  (setf (palette-query palette) "proj")
  (let ((best (first (palette-matches palette))))
    (list (mapcar #'palette-command-label (palette-matches palette))
          (list (palette-command-action best) (palette-command-group best) (palette-command-keywords best))
          (palette-match-score "np" "New project")
          (palette-match-score "xyz" "New project"))))
;; ⇒ (("New project" "Go to projects" "Search the docs for \"proj\"") ("/projects/new" "Projects" NIL) 16 NIL)
