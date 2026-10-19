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
