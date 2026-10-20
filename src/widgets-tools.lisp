;;;; widgets-tools.lisp — lazy panels, differences between texts, a command palette

(in-package #:littoral)

;;; Lazy panels: what's slow to make, filled in once the page has arrived

(defclass lazy-panel (component updatable)
  ((source :initarg :content :reader lazy-panel-source
           :documentation "A component, or a function of no arguments making one.")
   (content :initform nil :accessor lazy-panel-content
            :documentation "The component shown, once loaded.")
   (loaded :initform nil :accessor lazy-panel-loaded-p)
   (placeholder :initarg :placeholder :initform "Loading…" :reader lazy-panel-placeholder)
   (when-visible :initarg :when-visible :initform nil :reader lazy-panel-when-visible-p))
  (:documentation "A placeholder, :PLACEHOLDER (translated; \"Loading…\"),
that littoral.js replaces over AJAX, as soon as the page has loaded, with
:CONTENT: a component, or a function of no arguments making one, called
then rather than when the page is made.  The page arrives without waiting
for what is slow to compute, such as a big report or a chart over a slow
query.  With :WHEN-VISIBLE T it waits until the placeholder is scrolled
into view.  Without JavaScript a link loads it.  Once loaded it stays
loaded, and it shows its content straight away when the page is drawn
again."))

(defmethod states ((self lazy-panel)) (list self))

(defmethod children ((self lazy-panel))
  (and (lazy-panel-loaded-p self) (lazy-panel-content self) (list (lazy-panel-content self))))

(defun load-lazy-panel (panel)
  "Make PANEL's content, unless it has been made, so PANEL shows it."
  (unless (lazy-panel-loaded-p panel)
    (let ((source (lazy-panel-source panel)))
      (setf (lazy-panel-content panel) (if (functionp source) (funcall source) source)
            (lazy-panel-loaded-p panel) t)))
  panel)

(defmethod render ((self lazy-panel))
  (if (lazy-panel-loaded-p self)
      (when (lazy-panel-content self)
        (render-component (lazy-panel-content self)))
      (h:div (:class "lt-lazy" :aria-busy "true"
            :lazy (ajax :callback (lambda () (load-lazy-panel self)) :update self)
            :data-lt-lazy-visible (lazy-panel-when-visible-p self))
        (h:span (:class "lt-lazy-placeholder") (h:text (translate-label (lazy-panel-placeholder self))))
        (h:noscript ()
          (h:text " ")
          (h:anchor (:callback (lambda () (load-lazy-panel self))) (translate "Show it"))))))

;;; Differences between two texts

(defun text-lines (text)
  "TEXT's lines, without their line ends (LF or CRLF); a final line end
doesn't start another line."
  (let ((lines (cl-ppcre:split "\\r?\\n" text :limit most-positive-fixnum)))
    (if (and lines (string= (car (last lines)) "")) (butlast lines) lines)))

(defparameter *diff-cell-limit* 4000000
  "The most cells SEQUENCE-DIFF's table may have.  Beyond it, the part that
differs is reported as all removed, then all added.")

(defun sequence-diff (old new &key (test #'equal))
  "OLD and NEW, vectors, compared item by item: a list of (OP . ITEM), OP
:SAME, :REMOVED or :ADDED, in order, keeping as many items the same as
possible.  Within a change, removals come before additions."
  (let* ((n (length old)) (m (length new))
         (start (or (loop for i below (min n m) unless (funcall test (aref old i) (aref new i)) return i)
                    (min n m)))
         (end-old n) (end-new m))
    (loop while (and (> end-old start) (> end-new start)
                     (funcall test (aref old (1- end-old)) (aref new (1- end-new))))
          do (decf end-old) (decf end-new))
    (let ((head (loop for i below start collect (cons :same (aref old i))))
          (tail (loop for i from end-old below n collect (cons :same (aref old i))))
          (rows (- end-old start)) (columns (- end-new start)))
      (append
       head
       (if (> (* (1+ rows) (1+ columns)) *diff-cell-limit*)
           (append (loop for i from start below end-old collect (cons :removed (aref old i)))
                   (loop for j from start below end-new collect (cons :added (aref new j))))
           ;; LCS lengths of the suffixes, then a walk from the front.
           (let ((table (make-array (list (1+ rows) (1+ columns)) :element-type 'fixnum :initial-element 0)))
             (loop for i from (1- rows) downto 0
                   do (loop for j from (1- columns) downto 0
                            do (setf (aref table i j)
                                     (if (funcall test (aref old (+ start i)) (aref new (+ start j)))
                                         (1+ (aref table (1+ i) (1+ j)))
                                         (max (aref table (1+ i) j) (aref table i (1+ j)))))))
             (let ((i 0) (j 0) (out '()))
               (loop while (or (< i rows) (< j columns))
                     do (cond ((and (< i rows) (< j columns)
                                    (funcall test (aref old (+ start i)) (aref new (+ start j))))
                               (push (cons :same (aref old (+ start i))) out) (incf i) (incf j))
                              ((and (< i rows) (or (= j columns) (>= (aref table (1+ i) j) (aref table i (1+ j)))))
                               (push (cons :removed (aref old (+ start i))) out) (incf i))
                              (t (push (cons :added (aref new (+ start j))) out) (incf j))))
               (nreverse out))))
       tail))))

(defun text-diff (old new)
  "The lines of OLD and NEW, two strings, compared: a list of (OP . LINE),
OP :SAME, :REMOVED or :ADDED, in order, with as many lines kept the same as
possible.  Lines end at LF or CRLF."
  (sequence-diff (coerce (text-lines old) 'vector) (coerce (text-lines new) 'vector)))

(defun word-tokens (line)
  "LINE as words, runs of spaces and single other characters."
  (coerce (cl-ppcre:all-matches-as-strings "\\w+|\\s+|[^\\w\\s]" line) 'vector))

(defun word-changes (old new)
  "For a removed line OLD replaced by NEW: each as a list of (CHANGED-P . TEXT)
runs, or NIL when they have no word in common."
  (let* ((diff (sequence-diff (word-tokens old) (word-tokens new)))
         (common (find-if (lambda (d) (and (eq (car d) :same) (cl-ppcre:scan "\\w" (cdr d)))) diff)))
    (when common
      (flet ((runs (keep)
               (let ((runs '()))
                 (dolist (d diff (nreverse runs))
                   (when (member (car d) (list :same keep))
                     (let ((changed (not (eq (car d) :same))))
                       (if (and runs (eq (car (first runs)) changed))
                           (setf (cdr (first runs)) (concatenate 'string (cdr (first runs)) (cdr d)))
                           (push (cons changed (cdr d)) runs))))))))
        (values (runs :removed) (runs :added))))))

(defclass diff-view (component)
  ((old :initarg :old :initform "" :accessor diff-view-old :documentation "The text before.")
   (new :initarg :new :initform "" :accessor diff-view-new :documentation "The text after.")
   (old-label :initarg :old-label :initform "Before" :reader diff-view-old-label)
   (new-label :initarg :new-label :initform "After" :reader diff-view-new-label)
   (layout :initarg :layout :initform :inline :accessor diff-view-layout
           :documentation ":INLINE or :SIDE-BY-SIDE.")
   (context :initarg :context :initform 3 :reader diff-view-context
            :documentation "Unchanged lines to show around each change; NIL for all.")
   (expanded :initform nil :accessor diff-view-expanded))
  (:documentation "The differences between two texts, :OLD and :NEW, line
by line (TEXT-DIFF): removed lines struck through, added ones marked, and
within a changed line the words that changed.  :LAYOUT is :INLINE, one
column, or :SIDE-BY-SIDE, the two texts in columns headed :OLD-LABEL and
:NEW-LABEL (translated; \"Before\" and \"After\"); links switch between
them.  Unchanged stretches are cut to :CONTEXT lines (3) either side of a
change, with a link to show everything; :CONTEXT NIL shows everything."))

(defmethod states ((self diff-view)) (list self))

(defun diff-rows (diff)
  "DIFF (from TEXT-DIFF) as rows (OP OLD-NUMBER NEW-NUMBER LINE OLD-RUNS
NEW-RUNS): line numbers counted from 1, and for a removed line paired with
an added one in the same change, each one's word runs (WORD-CHANGES)."
  (let ((rows '()) (old-number 0) (new-number 0) (rest diff))
    (loop while rest
          do (if (eq (car (first rest)) :same)
                 (push (list :same (incf old-number) (incf new-number) (cdr (pop rest))) rows)
                 (let ((removed (loop while (and rest (eq (car (first rest)) :removed)) collect (cdr (pop rest))))
                       (added (loop while (and rest (eq (car (first rest)) :added)) collect (cdr (pop rest)))))
                   (let ((pairs (loop for r in removed for a in added
                                      collect (multiple-value-list (word-changes r a)))))
                     (loop for line in removed for k from 0
                           do (push (list :removed (incf old-number) nil line (first (nth k pairs))) rows))
                     (loop for line in added for k from 0
                           do (push (list :added nil (incf new-number) line (second (nth k pairs))) rows))))))
    (nreverse rows)))

(defun visible-diff-rows (rows context)
  "ROWS with unchanged stretches further than CONTEXT lines from a change
replaced by (:SKIPPED COUNT)."
  (if (null context)
      rows
      (let* ((vector (coerce rows 'vector))
             (count (length vector))
             (near (make-array count :initial-element nil)))
        (loop for i below count
              unless (eq (first (aref vector i)) :same)
                do (loop for k from (max 0 (- i context)) to (min (1- count) (+ i context))
                         do (setf (aref near k) t)))
        (let ((out '()) (skipped 0))
          (loop for i below count
                do (cond ((or (aref near i) (not (eq (first (aref vector i)) :same)))
                          (when (plusp skipped) (push (list :skipped skipped) out) (setf skipped 0))
                          (push (aref vector i) out))
                         (t (incf skipped))))
          (when (plusp skipped) (push (list :skipped skipped) out))
          (nreverse out)))))

(defun render-diff-line (op line runs)
  "LINE, of a row whose change is OP, with RUNS' changed words marked."
  (flet ((body ()
           (if runs
               (dolist (run runs)
                 (if (car run) (h:mark (:class "lt-diff-word") (h:text (cdr run))) (h:text (cdr run))))
               (h:text line))))
    (case op
      (:removed (h:span (:class "lt-visually-hidden") (translate "Removed:") " ") (h:del () (body)))
      (:added (h:span (:class "lt-visually-hidden") (translate "Added:") " ") (h:ins () (body)))
      (otherwise (body)))))

(defun render-skipped-row (view count columns)
  "A row of VIEW's table, COLUMNS wide, standing for COUNT unchanged lines."
  (h:tr (:class "lt-diff-skipped")
    (h:td (:colspan columns)
      (h:text (translate-plural count "~D unchanged line" "~D unchanged lines"))
      (h:text " ")
      (h:anchor (:callback (lambda () (setf (diff-view-expanded view) t))) (translate "Show all")))))

(defun render-inline-diff (view rows)
  "VIEW's ROWS (from VISIBLE-DIFF-ROWS) in one column, numbered both ways."
  (h:table (:class "lt-diff-table lt-diff-inline")
    (h:thead ()
      (h:tr () (h:th (:scope "col" :class "lt-diff-number") (h:text (translate-label (diff-view-old-label view))))
             (h:th (:scope "col" :class "lt-diff-number") (h:text (translate-label (diff-view-new-label view))))
             (h:th (:scope "col") (translate "Line"))))
    (h:tbody ()
      (dolist (row rows)
        (if (eq (first row) :skipped)
            (render-skipped-row view (second row) 3)
            (destructuring-bind (op old-number new-number line &optional runs) row
              (h:tr (:class (format nil "lt-diff-~(~A~)" op))
                (h:td (:class "lt-diff-number") (when old-number (h:text old-number)))
                (h:td (:class "lt-diff-number") (when new-number (h:text new-number)))
                (h:td (:class "lt-diff-text") (render-diff-line op line runs)))))))))

(defun side-by-side-pairs (rows)
  "ROWS paired up for two columns: (LEFT . RIGHT), either NIL, or (:SKIPPED COUNT)."
  (let ((out '()) (rest rows))
    (loop while rest
          do (case (first (first rest))
               ((:same :skipped) (let ((row (pop rest))) (push (if (eq (first row) :skipped) row (cons row row)) out)))
               (t (let ((removed (loop while (and rest (eq (first (first rest)) :removed)) collect (pop rest)))
                        (added (loop while (and rest (eq (first (first rest)) :added)) collect (pop rest))))
                    (loop for k below (max (length removed) (length added))
                          do (push (cons (nth k removed) (nth k added)) out))))))
    (nreverse out)))

(defun render-side-by-side-diff (view rows)
  "VIEW's ROWS (from VISIBLE-DIFF-ROWS) as the two texts side by side."
  (h:table (:class "lt-diff-table lt-diff-sides")
    (h:thead ()
      (h:tr () (h:th (:scope "col" :colspan 2) (h:text (translate-label (diff-view-old-label view))))
             (h:th (:scope "col" :colspan 2) (h:text (translate-label (diff-view-new-label view))))))
    (h:tbody ()
      (dolist (pair (side-by-side-pairs rows))
        (if (eq (first pair) :skipped)
            (render-skipped-row view (second pair) 4)
            (destructuring-bind (left . right) pair
              (h:tr ()
                (flet ((side (row number-index)
                         (cond (row
                                (destructuring-bind (op old-number new-number line &optional runs) row
                                  (let ((number (if (= number-index 1) old-number new-number)))
                                    (h:td (:class (list "lt-diff-number" (format nil "lt-diff-~(~A~)" op))) (h:text number))
                                    (h:td (:class (list "lt-diff-text" (format nil "lt-diff-~(~A~)" op)))
                                      (render-diff-line op line runs)))))
                               (t (h:td (:class "lt-diff-number lt-diff-empty"))
                                  (h:td (:class "lt-diff-text lt-diff-empty"))))))
                  (side left 1)
                  (side right 2)))))))))

(defmethod render ((self diff-view))
  (let* ((rows (diff-rows (text-diff (diff-view-old self) (diff-view-new self))))
         (added (count :added rows :key #'first))
         (removed (count :removed rows :key #'first)))
    (h:div (:class "lt-diff")
      (h:div (:class "lt-diff-heading")
        (h:p (:class "lt-diff-summary")
          (if (zerop (+ added removed))
              (h:text (translate "No differences."))
              (h:text (format nil "~A, ~A"
                            (translate-plural added "~D line added" "~D lines added")
                            (translate-plural removed "~D line removed" "~D lines removed")))))
        (h:ul (:class "lt-diff-layouts")
          (loop for (layout label) in '((:inline "Inline") (:side-by-side "Side by side"))
                do (let ((layout layout))
                     (h:li ()
                       (if (eq layout (diff-view-layout self))
                           (h:strong (:aria-current "true") (h:text (translate label)))
                           (h:anchor (:callback (lambda () (setf (diff-view-layout self) layout)))
                             (h:text (translate label)))))))))
      (unless (zerop (+ added removed))
        (let ((visible (visible-diff-rows rows (and (not (diff-view-expanded self)) (diff-view-context self)))))
          (if (eq (diff-view-layout self) :side-by-side)
              (render-side-by-side-diff self visible)
              (render-inline-diff self visible)))))))

;;; A command palette

(defstruct (palette-command (:constructor %make-palette-command (h:label action group keywords)))
  label action group keywords)

(setf (documentation 'palette-command-label 'function) "The command's label, as given."
      (documentation 'palette-command-action 'function) "The command's function, or URL to go to."
      (documentation 'palette-command-group 'function) "The group the command is listed under, or NIL."
      (documentation 'palette-command-keywords 'function) "More words the command is found by.")

(defun palette-command (label action &key group keywords)
  "A command for a COMMAND-PALETTE: LABEL, its name (translated when shown),
and ACTION, a function of no arguments called when it is chosen, as a
link's callback (so it may SHOW, ANSWER or REDIRECT-TO), or a URL to go
to.  GROUP, such as \"Tables\", is shown beside it; KEYWORDS, a list of
strings, are more words it is found by."
  (%make-palette-command label action group keywords))

(defun subsequence-in-p (characters text start)
  "True when CHARACTERS appear in TEXT, in order, from START on."
  (loop with at = start
        for c across characters
        do (let ((found (position c text :start at)))
             (if found (setf at (1+ found)) (return nil)))
        finally (return t)))

(defun word-start-p (text index)
  "True when the character at INDEX in TEXT starts a word."
  (or (zerop index) (not (alphanumericp (char text (1- index))))))

(defun palette-match-score (query text)
  "How well QUERY matches TEXT, ignoring case: NIL unless QUERY's
characters appear in TEXT in order, else a score, higher for a better
match.  A run of the query found whole scores best, then characters at the
starts of words and next to each other.  An empty QUERY scores 0."
  (let ((query (string-downcase (string-trim " " query)))
        (text (string-downcase text)))
    (cond ((zerop (length query)) 0)
          ((search query text)
           (let ((at (search query text)))
             (+ 100 (if (word-start-p text at) 50 0) (- (min at 40)) (- (min (length text) 40)))))
          (t
           (let ((score 0) (position 0) (previous -2)
                 (query (remove #\Space query)))
             (loop for c across query
                   for k from 1
                   do (let ((found (position c text :start position)))
                          (unless found (return-from palette-match-score nil))
                          ;; Prefer the start of a word further on to a letter
                          ;; mid-word here, when the rest still matches after it.
                          (let ((start (loop for i from found below (length text)
                                             when (and (char= (char text i) c) (word-start-p text i)) return i)))
                            (when (and start (/= found (1+ previous))
                                       (subsequence-in-p (subseq query k) text (1+ start)))
                              (setf found start)))
                          (incf score (cond ((= found (1+ previous)) 5)
                                            ((word-start-p text found) 8)
                                            (t 1)))
                          (setf previous found position (1+ found))))
             score)))))

(defun command-score (query command)
  "QUERY's best score against COMMAND's label and keywords, or NIL."
  (let ((scores (remove nil (mapcar (lambda (text) (palette-match-score query text))
                                    (cons (translate-label (palette-command-label command))
                                          (palette-command-keywords command))))))
    (and scores (reduce #'max scores))))

(defun rank-commands (query commands)
  "COMMANDS matching QUERY, best first; all of them, in order, for an empty QUERY."
  (let ((scored (loop for command in commands
                      for score = (command-score query command)
                      when score collect (cons score command))))
    (mapcar #'cdr (stable-sort scored #'> :key #'car))))

(defclass palette-results (component updatable)
  ((palette :initarg :palette :reader results-palette))
  (:documentation "The commands a COMMAND-PALETTE finds for its query."))

(defclass command-palette (component updatable)
  ((commands :initarg :commands :initform '() :reader palette-commands
             :documentation "PALETTE-COMMANDs, or a function of no arguments returning them.")
   (search :initarg :search :initform nil :reader palette-search
           :documentation "A function of the query giving more commands, or NIL.")
   (query :initarg :query :initform "" :accessor palette-query)
   (submitted :initform nil :accessor palette-submitted-p
              :documentation "True after its box was submitted without JavaScript, so it shows open.")
   (limit :initarg :limit :initform 10 :reader palette-limit)
   (label :initarg :label :initform "Commands" :reader palette-label)
   (shortcut :initarg :shortcut :initform t :reader palette-shortcut-p)
   (results :reader palette-results-component))
  (:documentation "A search box for commands, opened with Ctrl-K (⌘K on a
Mac) or its button, :LABEL (translated; \"Commands\").  Typing ranks
:COMMANDS, a list of PALETTE-COMMANDs or a function of no arguments
returning one, by PALETTE-MATCH-SCORE against their labels and keywords,
and shows the best :LIMIT (10); :SEARCH, a function of the text typed,
can add commands of its own, such as records whose names match, listed
after them.  The arrow keys move through the results and Enter follows
one; Escape closes it.  Each result is a link, so a palette works without
JavaScript too: Enter in the box shows the results.  :SHORTCUT NIL leaves
Ctrl-K alone (one palette a page should have it)."))

(defmethod initialize-instance :after ((self command-palette) &key)
  (setf (slot-value self 'results) (make-instance 'palette-results :palette self)))

(defmethod states ((self command-palette)) (list self))
(defmethod children ((self command-palette)) (list (palette-results-component self)))

(defun palette-matches (palette &optional (query (palette-query palette)))
  "The commands PALETTE shows for QUERY: its commands ranked against it,
at most its limit, then those its search function gives."
  (let* ((commands (palette-commands palette))
         (ranked (rank-commands query (if (functionp commands) (funcall commands) commands)))
         (searched (and (palette-search palette) (plusp (length (string-trim " " query)))
                        (funcall (palette-search palette) (string-trim " " query)))))
    (append (subseq-list ranked (palette-limit palette)) searched)))

(defun run-palette-command (palette command)
  "Forget PALETTE's query and run COMMAND."
  (setf (palette-query palette) ""
        (palette-submitted-p palette) nil)
  (let ((action (palette-command-action command)))
    (if (stringp action) (redirect-to action) (funcall action))))

(defmethod updatable-wrapper ((self palette-results))
  (values "div" '(:aria-live "polite" :class "lt-palette-found")))

(defmethod render ((self palette-results))
  (let* ((palette (results-palette self))
         (commands (palette-matches palette)))
    (h:span (:class "lt-visually-hidden")
      (h:text (translate-plural (length commands) "~D command" "~D commands")))
    (if (null commands)
        (h:p (:class "lt-palette-none") (translate "No matching commands."))
        (h:ul (:class "lt-palette-results")
          (dolist (command commands)
            (let ((command command))
              (h:li ()
                (h:anchor (:callback (lambda () (run-palette-command palette command)))
                  (h:span (:class "lt-palette-label") (h:text (translate-label (palette-command-label command))))
                  (when (palette-command-group command)
                    (h:text " ")
                    (h:span (:class "lt-palette-group") (h:text (translate-label (palette-command-group command)))))))))))))

(defmethod render ((self command-palette))
  (let ((input-id (format nil "~A-q" (component-id self))))
    (h:details (:class "lt-palette" :data-lt-palette (if (palette-shortcut-p self) "shortcut" "")
              :open (palette-submitted-p self))
      (h:summary ()
        (h:text (translate-label (palette-label self)))
        (when (palette-shortcut-p self)
          (h:text " ")
          (h:kbd (:class "lt-palette-key") "Ctrl K")))
      (h:div (:class "lt-palette-box")
        (h:form (:role "search" :default-action (lambda () (setf (palette-submitted-p self) t)))
          (h:label (:for input-id :class "lt-visually-hidden") (translate "Search commands"))
          (h:text-input (:id input-id :type "search" :value (palette-query self)
                       :placeholder (translate "Search commands")
                       :autocomplete "off" :spellcheck "false"
                       :aria-controls (component-id (palette-results-component self))
                       :callback (lambda (v) (setf (palette-query self) v))
                       :on-input (ajax-update (palette-results-component self)))))
        (render-component (palette-results-component self))))))
