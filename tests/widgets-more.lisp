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
