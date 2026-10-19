;;;; widgets-tools.lisp — lazy panels, differences between texts, command palettes

(in-package #:littoral/tests)

(def-suite widgets-tools :in littoral)
(in-suite widgets-tools)

;;; Lazy panels

(test lazy-panels-load-over-ajax
  (let ((littoral-examples::*slow-seconds* 0))
    (with-widgets (b)
      (click b "Tools")
      (is (has-text-p b "Finding primes…"))
      (is (not (has-text-p b "The first 20 primes")))
      (is (search "aria-busy=\"true\"" (browser-html b)))
      ;; littoral.js asks for it as soon as the page is in.
      (let* ((spec (first (ajax-specs b "lazy")))
             (json (ajax-request b (car spec) (cdr spec))))
        (is (search "The first 20 primes" json))
        (is (search "71" json)))
      ;; Loaded once, it's drawn with the page.
      (visit b (browser-url b))
      (is (has-text-p b "The first 20 primes"))
      (is (null (ajax-specs b "lazy"))))))

(test lazy-panels-load-without-javascript
  (let ((littoral-examples::*slow-seconds* 0))
    (with-widgets (b)
      (click b "Tools")
      (is (search "<noscript>" (browser-html b)))
      (click b "Show it")
      (is (has-text-p b "The first 20 primes")))))

(test the-report-chart-waits-to-be-seen
  (let ((littoral-examples::*chart-seconds* 0))
    (with-fresh-applications (("/report" 'littoral-examples:element-table :mode :deployment))
      (let ((b (make-instance 'browser)))
        (visit b "/report")
        (is (has-text-p b "Working out the chart…"))
        (is (search "data-lt-lazy-visible" (browser-html b)))
        (let ((spec (first (ajax-specs b "lazy"))))
          (is (search "Standard atomic weights" (ajax-request b (car spec) (cdr spec)))))
        ;; Sorting the table afterwards leaves the chart loaded.
        (click b "Name")
        (is (has-text-p b "Standard atomic weights"))))))

(defclass lazy-note-page (component)
  ((panel :initform (make-instance 'lazy-panel :content (make-instance 'littoral-examples::note :text "Ready."))
          :reader page-panel))
  (:documentation "A lazy panel whose content is a component made beforehand."))

(defmethod children ((self lazy-note-page)) (list (page-panel self)))
(defmethod render ((self lazy-note-page)) (render-component (page-panel self)))

(test lazy-panels-made-from-components
  (with-fresh-applications (("/lazy" 'lazy-note-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/lazy")
      (is (has-text-p b "Loading…"))
      (let ((spec (first (ajax-specs b "lazy"))))
        (is (search "Ready." (ajax-request b (car spec) (cdr spec))))))))

;;; Differences

(test text-diff-keeps-what-is-the-same
  (is (equal '((:same . "a") (:removed . "b") (:added . "B") (:same . "c") (:added . "d"))
             (text-diff (format nil "a~%b~%c~%") (format nil "a~%B~%c~%d"))))
  (is (equal '((:same . "one") (:same . "two")) (text-diff (format nil "one~C~%two" #\Return) (format nil "one~%two~%")))
      "CRLF and LF lines are the same, and a final line end starts no line")
  (is (equal '((:added . "x")) (text-diff "" "x")))
  (is (equal '((:removed . "x")) (text-diff "x" "")))
  (is (null (text-diff "" "")))
  ;; Removals come before additions within a change.
  (is (equal '((:removed . "1") (:removed . "2") (:added . "3") (:added . "4"))
             (text-diff (format nil "1~%2") (format nil "3~%4"))))
  ;; Beyond the size limit, the middle is all removed, then all added.
  (let ((littoral::*diff-cell-limit* 4))
    (is (equal '((:same . "a") (:removed . "b") (:removed . "c") (:added . "c") (:added . "d") (:same . "z"))
               (text-diff (format nil "a~%b~%c~%z") (format nil "a~%c~%d~%z"))))))

(test text-diff-finds-the-longest-common-lines
  (let* ((old (format nil "~{~A~^~%~}" '("a" "b" "c" "d" "e" "f" "g")))
         (new (format nil "~{~A~^~%~}" '("a" "x" "c" "d" "y" "f" "g" "h")))
         (diff (text-diff old new)))
    (is (= 5 (count :same diff :key #'car)))
    (is (equal '("a" "b" "c" "d" "e" "f" "g") (mapcar #'cdr (remove :added diff :key #'car))))
    (is (equal '("a" "x" "c" "d" "y" "f" "g" "h") (mapcar #'cdr (remove :removed diff :key #'car))))))

(test diff-views-in-the-tools-tab
  (with-widgets (b)
    (click b "Tools")
    (let ((html (browser-html b)))
      (is (has-text-p b "2 lines added, 2 lines removed"))
      (is (search "<del>milk</del>" (strip-hidden html)) "A line removed whole has no words marked")
      ;; "bread" became "brown bread": the words added are marked.
      (is (search "<ins><mark class=\"lt-diff-word\">brown </mark>bread</ins>" (strip-hidden html)))
      (is (search "Removed:" html) "Screen readers hear what changed")
      (is (search "<th scope=\"col\" class=\"lt-diff-number\">Monday</th>" html)))
    ;; Side by side.
    (click b "Side by side")
    (is (search "lt-diff-sides" (browser-html b)))
    (is (search "<strong aria-current=\"true\">Side by side</strong>" (browser-html b)))
    ;; New texts to compare.
    (fill-in b "diff-old" (format nil "~{line ~D~%~}" (alexandria:iota 20 :start 1)))
    (fill-in b "diff-new" (format nil "~{line ~D~%~}" (substitute 99 10 (alexandria:iota 20 :start 1))))
    (press b "Compare")
    (is (has-text-p b "1 line added, 1 line removed"))
    ;; Three lines either side of the change; the rest are counted.
    (is (has-text-p b "6 unchanged lines"))
    (is (has-text-p b "7 unchanged lines"))
    (is (search ">line 7</td>" (browser-html b)))
    (is (not (search ">line 2</td>" (browser-html b))))
    (click b "Show all")
    (is (not (has-text-p b "unchanged lines")))
    (is (search ">line 2</td>" (browser-html b)))
    (fill-in b "diff-new" (format nil "~{line ~D~%~}" (alexandria:iota 20 :start 1)))
    (press b "Compare")
    (is (has-text-p b "No differences."))))

(defun count-matches (regex text)
  "How many times REGEX matches in TEXT."
  (cl-ppcre:count-matches regex text))

(defun strip-hidden (html)
  "HTML without the visually hidden spans."
  (cl-ppcre:regex-replace-all "<span class=\"lt-visually-hidden\">[^<]*</span> ?" html ""))

(test wiki-history-shows-each-revisions-changes
  (littoral-examples:reset-wiki)
  (with-fresh-applications (("/wiki" 'littoral-examples:wiki :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/wiki/Diff%20Page")
      (click b "Write it")
      (fill-in b "text" (format nil "First line~%Second line"))
      (fill-in b "summary" "start")
      (press b "Save")
      (click b "Edit")
      (fill-in b "text" (format nil "First line~%Second line, changed~%Third line"))
      (press b "Save")
      (click b "History")
      (click-nth b "changes" 0)          ; the newest, #2
      (is (has-text-p b "2 lines added, 1 line removed"))
      (is (search "<th scope=\"col\" class=\"lt-diff-number\">#1</th>" (browser-html b)))
      (is (search "<mark class=\"lt-diff-word\">, changed</mark>" (browser-html b)))
      ;; The first revision's changes: everything added.
      (click-nth b "changes" 1)
      (is (has-text-p b "2 lines added, 0 lines removed"))
      (is (search ">Nothing</th>" (browser-html b)))
      ;; Viewing a revision puts the changes away.
      (click-nth b "view" 0)
      (is (not (has-text-p b "lines added"))))))

;;; Command palettes

(test palette-match-scores
  (is (eql 0 (palette-match-score "" "Anything")))
  (is (null (palette-match-score "xyz" "New project")))
  (is (palette-match-score "np" "New project") "The starts of words")
  (is (> (palette-match-score "proj" "New project") (palette-match-score "nwpj" "New project"))
      "A run found whole beats scattered letters")
  (is (> (palette-match-score "pro" "Projects") (palette-match-score "pro" "Go to Projects"))
      "Earlier and shorter is better")
  (is (> (palette-match-score "gp" "Go to Projects") (palette-match-score "gp" "Bigger pumpkins"))
      "Starts of words beat letters within them")
  (is (palette-match-score "NEW" "new project") "Case doesn't matter")
  ;; A word start further on isn't taken when the rest wouldn't match after it.
  (is (palette-match-score "ab" "a xa b")))

(defun palette-type (b query)
  "Type QUERY into the page's palette as littoral.js would: the JSON answer."
  (let* ((input (cl-ppcre:register-groups-bind (name) ("<input type=\"search\" name=\"([^\"]+)\"" (browser-html b)) name))
         (spec (find-if (lambda (spec)
                          (search (format nil "id=\"~A\" class=\"lt-updatable lt-palette-found\"" (cdr spec)) (browser-html b)))
                        (ajax-specs b "on-input"))))
    (ajax-request b (car spec) (cdr spec) :fields (list (cons input query)))))

(test the-widgets-palette
  (with-widgets (b)
    (is (search "<details class=\"lt-palette\" data-lt-palette=\"shortcut\">" (browser-html b)))
    (is (search "<kbd class=\"lt-palette-key\">Ctrl K</kbd>" (browser-html b)))
    ;; The first ten at first, in order.
    (is (has-text-p b "Show Tabs"))
    (is (= 10 (count-matches "<span class=\"lt-palette-label\">" (browser-html b))))
    (is (not (has-text-p b "Open the Wiki example")))
    (is (search "Open the Wiki example" (palette-type b "wiki")))
    ;; Typing narrows and ranks them.
    (let ((json (palette-type b "kan")))
      (is (search "Show Kanban" json))
      (is (not (search "Show Tabs" json)))
      (is (search "1 command" json)))
    ;; Keywords count too.
    (is (search "Open the Chat example" (palette-type b "talk")))
    (is (search "No matching commands." (palette-type b "zzzz")))
    ;; Choosing one runs it, and forgets the query.
    (palette-type b "kan")
    (visit b (browser-url b))
    (click b "Show Kanban")
    (is (has-text-p b "Write the docs"))
    (is (has-text-p b "Show Tabs"))
    ;; The search function adds commands of its own.
    (let ((json (palette-type b "mapc")))
      (is (search "Look up mapcan" json))
      (is (search "Symbols" json)))
    (visit b (browser-url b))
    (click b "Look up mapcar")
    (is (has-text-p b "Chose mapcar"))
    ;; A URL command is a redirect.
    (palette-type b "counter")
    (visit b (browser-url b))
    (click b "Open the Counter example")
    (is (search "/examples/counter" (browser-url b)))))

(test palettes-work-without-javascript
  (with-widgets (b)
    (is (not (search "<details class=\"lt-palette\" data-lt-palette=\"shortcut\" open" (browser-html b))))
    ;; Enter in the box submits its form: the page comes back with it open.
    (let ((input (cl-ppcre:register-groups-bind (name) ("<input type=\"search\" name=\"([^\"]+)\"" (browser-html b)) name))
          (default (cl-ppcre:register-groups-bind (name) ("<input type=\"hidden\" name=\"([^\"]+)\" value=\"1\">" (browser-html b)) name)))
      (visit b (form-action b) :method :post :body (encode-fields (list (cons input "calendar") (cons default "1")))))
    (is (search "data-lt-palette=\"shortcut\" open" (browser-html b)))
    (click b "Show Calendar")
    (is (has-text-p b "Today"))
    (is (not (search "data-lt-palette=\"shortcut\" open" (browser-html b))))))

(test the-admin-palette
  (with-admin (b)
    (is (search "lt-palette" (browser-html b)))
    (is (has-text-p b "Go to Jobs"))
    (is (search "Go to Jobs" (palette-type b "jobs")))
    (visit b (browser-url b))
    (click b "Go to Jobs")
    (is (has-text-p b "3 jobs"))
    (click b "New project")
    (is (has-text-p b "New project"))
    (fill-in b "name" "Palette")
    (press b "Create")
    (is (has-text-p b "Created Project #3."))))
