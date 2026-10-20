;;;; widgets-layout.lisp — popovers, tooltips, drawers and split panes

(in-package #:littoral/tests)

(def-suite widgets-layout :in littoral)
(in-suite widgets-layout)

(defun spec-of (b pattern)
  "The (CALLBACK . TARGETS) of the data-lt-on-click of the first element
whose start tag matches PATTERN, a regular expression."
  (cl-ppcre:register-groups-bind (spec)
      ((format nil "<[a-z]+\\b[^>]*~A[^>]*data-lt-on-click=\"([^\"]*)\"" pattern) (browser-html b))
    (let* ((spec (unescape spec)) (semi (position #\; spec)))
      (cons (subseq spec 0 semi) (subseq spec (1+ semi))))))

(test popovers
  (is (equal (concatenate 'string
                          "<button type=\"button\" class=\"lt-popover-button\" popovertarget=\"more\">More</button>"
                          "<div id=\"more\" popover=\"auto\" class=\"lt-popover wide\"><p>Hidden until asked for.</p></div>")
             (h:with-canvas-to-string () (with-popover ("More" :id "more" :class "wide") (h:p () "Hidden until asked for.")))))
  (with-widgets (b)
    (click b "Layout")
    (let* ((html (browser-html b))
           (id (cl-ppcre:register-groups-bind (id) ("popovertarget=\"([^\"]+)\"" html) id)))
      (is (search (format nil "<div id=\"~A\" popover=\"auto\" class=\"lt-popover\"><p>A box over the page" id) html)))))

(test tooltips
  (is (equal (concatenate 'string
                          "<span class=\"lt-tooltip\"><button type=\"button\">Copy</button>"
                          "<span id=\"tip\" role=\"tooltip\" class=\"lt-tooltip-text\">Copies the link</span></span>")
             (h:with-canvas-to-string () (with-tooltip ("Copies the link" :id "tip") (h:button () "Copy")))))
  (with-widgets (b)
    (click b "Layout")
    (is (search "class=\"lt-tooltip-text\">Nothing is copied: this only shows a tooltip.</span>" (browser-html b)))))

(test drawers
  (with-widgets (b)
    (click b "Layout")
    (is (search "class=\"lt-drawer-toggle\" aria-expanded=\"false\"" (browser-html b)))
    (is (not (has-text-p b "Drawers hold navigation")))
    ;; Without JavaScript, links open and close it.
    (click b "Open the drawer")
    (is (has-text-p b "Drawers hold navigation"))
    (is (cl-ppcre:scan "aria-expanded=\"true\" aria-controls=\"([^\"]+)\".*<div id=\"\\1\" role=\"dialog\" aria-label=\"A drawer\" class=\"lt-drawer lt-drawer-left\">"
                       (browser-html b)))
    (is (search "class=\"lt-drawer-close\" aria-label=\"Close\" autofocus" (browser-html b)))
    (click b "×")
    (is (not (has-text-p b "Drawers hold navigation")))
    ;; Over AJAX, and kept on the server.
    (let* ((spec (spec-of b "class=\"lt-drawer-toggle\""))
           (json (ajax-request b (car spec) (cdr spec))))
      (is (search "Drawers hold navigation" json))
      (is (search "lt-drawer-backdrop" json)))
    (visit b (browser-url b))
    (is (has-text-p b "Drawers hold navigation"))
    (let ((spec (spec-of b "class=\"lt-drawer-close\"")))
      (is (not (search "Drawers hold navigation" (ajax-request b (car spec) (cdr spec))))))
    (visit b (browser-url b))
    (is (not (has-text-p b "Drawers hold navigation")))))

(test drawers-open-on-either-side
  (let ((drawer (make-instance 'drawer :side :right :label "Filters" :open t
                                       :content (make-instance 'littoral-examples::note :text "Only red ones."))))
    (is (equal (list (drawer-content drawer)) (children drawer)))
    (toggle-drawer drawer)
    (is (not (drawer-open-p drawer)))
    (is (null (children drawer)) "Its content isn't on the page while closed")
    (toggle-drawer drawer t)
    (is (drawer-open-p drawer))))

(test split-panes
  (with-widgets (b)
    (click b "Layout")
    (let ((html (browser-html b)))
      (is (search "<div class=\"lt-split\" style=\"--lt-split: 30%\">" html))
      (is (cl-ppcre:scan "<div id=\"([^\"]+)-first\" class=\"lt-split-pane\">.*role=\"separator\" tabindex=\"0\" aria-orientation=\"vertical\" aria-controls=\"\\1-first\" aria-label=\"Resize the planet list\" aria-valuenow=\"30\" aria-valuetext=\"30%\" aria-valuemin=\"15\" aria-valuemax=\"85\""
                         html))
      (is (has-text-p b "The only one known to have life.")))
    ;; littoral.js posts the new share once the divider stops moving.
    (flet ((move-to (value)
             (let ((spec (first (ajax-specs b "split"))))
               (ajax-request b (car spec) (cdr spec) :fields (list (cons "_lt_value" value))))
             (visit b (browser-url b))
             (cl-ppcre:register-groups-bind (n) ("--lt-split: (\\d+)%" (browser-html b)) n)))
      (is (equal "55" (move-to "55")))
      (is (equal "85" (move-to "99")) "Kept within its limits")
      (is (equal "85" (move-to "wide"))))
    ;; The list and the detail beside it.
    (click b "Mars")
    (is (has-text-p b "Red with iron oxide dust"))
    (is (search "aria-current=\"true\"" (browser-html b)))
    (let* ((spec (cl-ppcre:register-groups-bind (spec) ("data-lt-on-click=\"([^\"]*)\">Jupiter</a>" (browser-html b))
                   (unescape spec)))
           (semi (position #\; spec))
           (json (ajax-request b (subseq spec 0 semi) (subseq spec (1+ semi)))))
      (is (search "a gas giant" json))
      (is (search "Jupiter</a>" json) "The list is redrawn too"))
    (let ((pane (make-instance 'split-pane :first (make-instance 'littoral-examples::note :text "a")
                                           :second (make-instance 'littoral-examples::note :text "b"))))
      (is (= 40 (split-position pane)))
      (is (= 15 (set-split-position pane 3))))))
