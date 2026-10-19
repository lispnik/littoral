;;;; widgets-more.lisp — tabs, navigation, tree, autocomplete, sortable

(in-package #:littoral/tests)

(def-suite widgets-more :in littoral)
(in-suite widgets-more)

(defun widgets-browser ()
  "A browser on the widgets example."
  (let ((b (make-instance 'browser)))
    (visit b "/widgets")
    b))

(defmacro with-widgets ((b) &body body)
  "Run BODY with the widgets example served and a browser on it as B."
  `(with-fresh-applications (("/widgets" 'littoral-examples:widget-demo :mode :deployment))
     (let ((,b (widgets-browser)))
       ,@body)))

(test navigation-and-tabs
  (with-widgets (b)
    (is (has-text-p b "The first tab."))
    (click b "Two")
    (is (has-text-p b "The second tab."))
    (is (not (has-text-p b "The first tab.")))
    ;; The current tab is not a link.
    (is (not (find-link b "Two")))
    (click b "Tree")
    (is (has-text-p b "condition types"))
    ;; Back to the tabs: the inner selection was kept.
    (click b "Tabs")
    (is (has-text-p b "The second tab."))))

(test tree-expands-and-selects
  (with-widgets (b)
    (click b "Tree")
    (is (has-text-p b "serious-condition"))
    (is (not (has-text-p b "arithmetic-error")))
    ;; Expand error under serious-condition.
    (let ((toggles (find-links b "▸")))
      (is (plusp (length toggles))))
    (labels ((expand (label)
               (let ((href (cl-ppcre:register-groups-bind (h)
                               ((format nil "<a href=\"([^\"]*)\" class=\"lt-tree-toggle\" ~
title=\"Expand\"[^>]*>▸</a> <a[^>]*>~A</a>" label)
                                (browser-html b))
                             (unescape h))))
                 (is (not (null href)) "no expander for ~A" label)
                 (visit b href))))
      (expand "serious-condition")
      (expand "error")
      (is (has-text-p b "arithmetic-error")))
    (click b "arithmetic-error")
    (is (has-text-p b "Selected: arithmetic-error"))
    (is (search "class=\"lt-selected\"" (browser-html b)))))

(test autocomplete-suggests-and-chooses
  (with-widgets (b)
    (click b "Autocomplete")
    (let* ((spec (first (ajax-specs b "on-input")))
           (field (element-name b "symbol"))
           (json (ajax-request b (first spec) (rest spec) :fields (list (cons field "mapc")))))
      (is (search "mapcan" json))
      (is (search "mapcar" json))
      (is (not (search "reduce" json)))
      ;; Nothing for nonsense.
      (is (not (search "lt-suggestion" (ajax-request b (first spec) (rest spec)
                                                     :fields (list (cons field "zzz")))))))
    ;; Choose one: the suggestion buttons are in the last fragment.
    (let* ((field (element-name b "symbol"))
           (json (ajax-request b "" (rest (first (ajax-specs b "on-input")))
                               :fields (list (cons field "mapcar")))))
      (let ((choose (cl-ppcre:register-groups-bind (cb targets)
                        ("data-lt-on-click=\\\\\"(\\d+);([^\\\\]*)\\\\\"" json)
                      (cons cb targets))))
        (ajax-request b (first choose) (rest choose))))
    (visit b (browser-url b))
    (is (has-text-p b "Chose mapcar"))))

(test sortable-moves
  (with-widgets (b)
    (click b "Sortable")
    (is (has-text-p b "Order: Write the tests, Make them pass, Refactor, Ship it"))
    (click-nth b "↓" 0)
    (is (has-text-p b "Order: Make them pass, Write the tests, Refactor, Ship it"))
    (click-nth b "↑" 2)                  ; Ship it up one
    (is (has-text-p b "Order: Make them pass, Write the tests, Ship it, Refactor"))
    ;; A drag posts the new order of old positions.
    (let ((spec (first (ajax-specs b "sortable"))))
      (ajax-request b (first spec) (rest spec) :fields '(("_lt_value" . "3,2,1,0")))
      ;; Malformed orders are ignored.
      (ajax-request b (first spec) (rest spec) :fields '(("_lt_value" . "0,0,1,2")))
      (ajax-request b (first spec) (rest spec) :fields '(("_lt_value" . "nonsense"))))
    (visit b (browser-url b))
    (is (has-text-p b "Order: Refactor, Ship it, Write the tests, Make them pass"))))

(test sortable-backtracks
  (with-widgets (b)
    (click b "Sortable")
    (let ((before (browser-url b)))
      (click-nth b "↓" 0)
      (back-to b before)
      (is (has-text-p b "Order: Write the tests, Make them pass, Refactor, Ship it")))))

(test component-ids-are-unique-on-a-page
  ;; Every id attribute on a page appears once.
  (with-widgets (b)
    (dolist (tab '("Tabs" "Tree" "Autocomplete" "Sortable"))
      (when (find-link b tab) (click b tab))   ; the current tab is not a link
      (let ((ids (cl-ppcre:all-matches-as-strings "\\bid=\"[^\"]*\"" (browser-html b))))
        (is (= (length ids) (length (remove-duplicates ids :test #'string=)))
            "duplicate ids on ~A: ~A" tab ids)))))

;;; Breadcrumbs and in-place editing: the pantry tab

(defun open-pantry-item (b)
  "From the widgets page, open the Apples on the Fruit shelf."
  (click b "Breadcrumbs")
  (click b "Fruit")
  (click b "Apples"))

(test breadcrumbs-follow-the-calls
  (with-widgets (b)
    (click b "Breadcrumbs")
    (is (search "<nav class=\"lt-breadcrumbs\" aria-label=\"Breadcrumbs\">" (browser-html b)))
    (is (search "<span aria-current=\"page\">Pantry</span>" (browser-html b)))
    (is (not (find-link b "Pantry")) "The current level is not a link")
    (click b "Fruit")
    (click b "Apples")
    (is (search "Pantry Fruit Apples" (body-text b)))
    (is (find-link b "Pantry"))
    (is (find-link b "Fruit"))
    ;; Back two levels at once.
    (click b "Pantry")
    (is (find-link b "Vegetables"))
    (is (search "<span aria-current=\"page\">Pantry</span>" (browser-html b)) "The trail is back to one level")
    (is (not (has-text-p b "Apples")))
    ;; Answering still works after that: open a shelf and go back by its own link.
    (click b "Vegetables")
    (is (has-text-p b "Leeks"))
    (click b "Back to the pantry")
    (is (search "<span aria-current=\"page\">Pantry</span>" (browser-html b)))))

(test home-forgets-the-dismissed-components-callers
  (let* ((caller (make-instance 'component))
         (called (make-instance 'component)))
    (show caller called)
    (is (= 1 (count-if (lambda (d) (typep d 'littoral::answer-handler)) (decorations called))))
    (home caller)
    (is (null (decorations caller)))
    (is (null (decorations called)) "No answer handler is left behind")
    (is (null (answer called)) "Nothing called it now")))

(defun start-in-place-edit (b label)
  "Press the Edit button labelled LABEL (\"Edit Name\") by AJAX, then
reload: the page now has the editor's form.  The id of its input."
  (let* ((html (browser-html b))
         (at (search (format nil "aria-label=\"~A\"" label) html))
         (spec (cl-ppcre:register-groups-bind (s) ("data-lt-on-click=\"([^\"]*)\"" html :start at) (unescape s)))
         (semi (position #\; spec)))
    (ajax-request b (subseq spec 0 semi) (subseq spec (1+ semi)))
    (visit b (browser-url b))
    (cl-ppcre:register-groups-bind (id) ("id=\"([^\"]*-input)\"" (browser-html b)) id)))

(defun save-in-place (b id text)
  "Submit the in-place editor's form with TEXT in input ID; the JSON."
  (let ((spec (first (ajax-specs b "on-submit"))))
    (ajax-request b (first spec) (rest spec) :fields (list (cons (element-name b id) text)))))

(test in-place-editing
  (with-widgets (b)
    (open-pantry-item b)
    (is (search "aria-label=\"Edit Name\"" (browser-html b)))
    (let ((id (start-in-place-edit b "Edit Name")))
      (is (not (null id)))
      (is (search "value=\"Apples\"" (browser-html b)) "The input starts from the value")
      ;; The description's checks apply.
      (is (search "Name is required." (save-in-place b id "")))
      (let ((json (save-in-place b id "Green apples")))
        (is (search "Green apples" json))
        (is (search "lt-breadcrumbs" json) "The trail is updated too")))
    (visit b (browser-url b))
    (is (search "Pantry Fruit Green apples" (body-text b)))
    (is (not (search "lt-in-place-editing" (browser-html b))))
    ;; A number: parsed and checked.
    (let ((id (start-in-place-edit b "Edit In stock")))
      (is (search "In stock must be at least 0." (save-in-place b id "-2")))
      (is (search "lt-in-place-editing" (browser-html b)))
      (save-in-place b id "7"))
    (visit b (browser-url b))
    (is (search "In stock 7" (body-text b)))))

;;; Edit conflicts: someone else saved first

(defclass shared-note ()
  ((text :initarg :text :accessor shared-note-text)
   (id :initarg :id :initform 1 :reader shared-note-id)))

(define-description shared-note ((text :required t)))

(defvar *shared-note* (make-instance 'shared-note :text "Original"))
(defvar *fresh-note* nil "What a test's :RELOAD gives.")
(defvar *refuse-save* nil "True to have the next :ON-SAVE refuse, as a stale save would.")

(defun refusing-save (note)
  (when *refuse-save*
    (setf *refuse-save* nil)
    (error 'edit-conflict :object note)))

(defclass shared-note-page (component)
  ((editor :initform (make-in-place-editor *shared-note* 'text :on-save #'refusing-save
                                                               :reload (lambda (note) (declare (ignore note)) *fresh-note*))
           :reader note-editor)))
(defmethod children ((self shared-note-page)) (list (note-editor self)))
(defmethod render ((self shared-note-page)) (render-component (note-editor self)))

(test in-place-edits-notice-other-peoples-changes
  (setf *shared-note* (make-instance 'shared-note :text "Original")
        *refuse-save* nil)
  (with-fresh-applications (("/note" 'shared-note-page :mode :deployment))
    (let ((a (make-instance 'browser)) (b (make-instance 'browser)))
      (visit a "/note")
      (visit b "/note")
      (let ((a-input (start-in-place-edit a "Edit Text"))
            (b-input (start-in-place-edit b "Edit Text")))
        (save-in-place b b-input "From B")
        (is (string= "From B" (shared-note-text *shared-note*)))
        ;; A's save would overwrite B's: it says so instead.
        (is (search "Someone else changed this to “From B” meanwhile." (save-in-place a a-input "From A")))
        (is (string= "From B" (shared-note-text *shared-note*)))
        ;; Saving again replaces it, knowingly.
        (save-in-place a a-input "From A")
        (is (string= "From A" (shared-note-text *shared-note*)))))))

(test in-place-edits-report-refused-saves
  (setf *shared-note* (make-instance 'shared-note :text "Original")
        *fresh-note* (make-instance 'shared-note :text "Theirs")
        *refuse-save* t)
  (with-fresh-applications (("/note" 'shared-note-page :mode :deployment))
    (let ((a (make-instance 'browser)))
      (visit a "/note")
      (let ((input (start-in-place-edit a "Edit Text")))
        ;; :ON-SAVE signals EDIT-CONFLICT: the object is put back, the
        ;; editor reloads it and says what it now reads.
        (is (search "Someone else changed this to “Theirs” meanwhile." (save-in-place a input "Mine")))
        (is (string= "Original" (shared-note-text *shared-note*)) "Put back")
        (save-in-place a input "Mine")
        (is (string= "Mine" (shared-note-text *fresh-note*)) "Saved to the object as it is now")))))

(defvar *shared-notes* '())

(defclass shared-notes-grid (component)
  ((grid :initform (make-instance 'data-grid :description 'shared-note :rows (lambda () *shared-notes*)
                                             :row-key #'shared-note-id :on-save #'refusing-save)
         :reader notes-grid)))
(defmethod children ((self shared-notes-grid)) (list (notes-grid self)))
(defmethod render ((self shared-notes-grid)) (render-component (notes-grid self)))

(test data-grids-notice-other-peoples-changes
  (setf *shared-notes* (list (make-instance 'shared-note :text "Original")) *refuse-save* nil)
  (with-fresh-applications (("/notes" 'shared-notes-grid :mode :deployment))
    (let ((a (make-instance 'browser)) (b (make-instance 'browser)))
      (visit a "/notes") (click a "Edit")
      (visit b "/notes") (click b "Edit")
      (fill-in b "grid-text" "From B")
      (press b "Save")
      (is (string= "From B" (shared-note-text (first *shared-notes*))))
      (fill-in a "grid-text" "From A")
      (press a "Save")
      (is (has-text-p a "Someone else changed this to “From B” meanwhile."))
      (is (string= "From B" (shared-note-text (first *shared-notes*))))
      (press a "Save")
      (is (string= "From A" (shared-note-text (first *shared-notes*))))
      ;; Rows read afresh (here, a new copy each time) are found by :ROW-KEY.
      (setf *shared-notes* (list (make-instance 'shared-note :text "Copy")))
      (visit a "/notes") (click a "Edit")
      (is (search "value=\"Copy\"" (browser-html a)) "The row being edited is shown as an editor")
      ;; A save the store refuses is reported, and nothing is kept.
      (setf *refuse-save* t)
      (fill-in a "grid-text" "Refused")
      (press a "Save")
      (is (has-text-p a "Someone else changed this row meanwhile; nothing was saved."))
      (is (string= "Copy" (shared-note-text (first *shared-notes*)))))))

;;; Tags, times and date ranges

(test new-field-kinds-parse-check-and-format
  (let ((tags (littoral::make-field 'tags :type :tags :choices '("red" "green") :max 2))
        (only (littoral::make-field 'tags :type :tags :choices '("red" "green") :only-choices t))
        (time (littoral::make-field 'meet :type :time))
        (dates (littoral::make-field 'dates :type :date-range)))
    (is (equal '("red" "Blue") (parse-field tags " red, Blue ,, RED ")) "Trimmed, blanks and repeats dropped")
    (is (string= "red, Blue" (format-field tags '("red" "Blue"))))
    (is (search "at most 2" (check-field tags '("a" "b" "c"))))
    (is (search "can only be red, green" (check-field only '("red" "pink"))))
    (is (null (check-field only '("Red"))))
    (is (equal '(9 5) (parse-field time "9:05")))
    (is (equal '(23 59) (parse-field time "23:59:30")) "Seconds, as some browsers send them, are dropped")
    (is (string= "09:05" (format-field time '(9 5))))
    (signals field-error (parse-field time "24:00"))
    (is (equal '((2026 11 6) . (2026 11 8)) (parse-field dates "2026-11-06/2026-11-08")))
    (is (string= "2026-11-06/2026-11-08" (format-field dates '((2026 11 6) . (2026 11 8)))))
    (is (null (parse-field dates "/")))
    (signals field-error (parse-field dates "2026-11-06/"))
    (is (search "must not end before it starts" (check-field dates '((2026 11 8) . (2026 11 6)))))))

(test the-forms-tab
  (with-widgets (b)
    (click b "Forms")
    (is (search "data-lt-tags=\"Remove ~A\"" (browser-html b)))
    (is (search "<datalist id=\"tags-tags\"><option value=\"hiking\">" (browser-html b)))
    (is (search "type=\"time\"" (browser-html b)))
    (is (search "value=\"food, museums\"" (browser-html b)))
    (fill-in b "tags" "food, Beach, food")
    (fill-in b "meet" "25:00")
    (fill-in b "dates" "2026-11-09")
    (fill-in b "dates-to" "2026-11-07")
    (press b "Save")
    (is (has-text-p b "Meeting time must be a time, like 09:30."))
    (is (has-text-p b "Dates must not end before it starts."))
    (fill-in b "meet" "10:15")
    (fill-in b "dates-to" "2026-11-10")
    (press b "Save")
    (is (search "Meeting time 10:15" (body-text b)))
    (is (search "Tags food Beach" (body-text b)))
    (is (search "Dates 2026-11-09/2026-11-10" (body-text b)))))

;;; Menus, accordions and disclosures

(test the-menus-tab
  (with-widgets (b)
    (click b "Menus")
    (is (search "<nav class=\"lt-menu-bar\" aria-label=\"Menu\">" (browser-html b)))
    (is (search "<details class=\"lt-dropdown\"><summary>File</summary>" (browser-html b)))
    (is (search "role=\"separator\"" (browser-html b)))
    ;; A dropdown's items are ordinary links.
    (click b "Duplicate")
    (is (has-text-p b "You chose Duplicate."))
    (click b "Close")
    (is (has-text-p b "You chose Close."))
    ;; The accordion: the first section open, one at a time.
    (flet ((open-sections () (cl-ppcre:count-matches "<details class=\"lt-accordion-section\" open" (browser-html b)))
           (toggle (n)
             (let ((spec (nth n (ajax-specs b "on-click"))))
               (ajax-request b (car spec) (cdr spec))
               (visit b (browser-url b)))))
      (is (= 1 (open-sections)))
      (is (search "open name=\"" (browser-html b)) "Sections share a name: one open at a time without JavaScript too")
      (toggle 1)                        ; the second section
      (is (= 1 (open-sections)))
      (toggle 1)                        ; closed again
      (is (= 0 (open-sections)))
      ;; The disclosure, closed at first, and remembered once opened.
      (is (not (search "<details class=\"lt-disclosure\" open" (browser-html b))))
      (toggle 3)
      (is (search "<details class=\"lt-disclosure\" open" (browser-html b))))))
