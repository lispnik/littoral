;;;; wiki.lisp — a wiki: shared state, bookmarkable pages, call for editing
;;;;
;;;; Pages are shared by every session and kept outside backtracking: going
;;;; back shows an older page *view*, never an older wiki.  Each page's URL
;;;; names it (/examples/wiki/FrontPage), so links can be bookmarked and
;;;; shared.  Editing calls an editor component and saves its answer.
;;;;
;;;; Markup: blank lines separate paragraphs, "- " starts a list item,
;;;; "= " a heading, *bold*, _italic_ and [[Page Name]] links.

(in-package #:littoral-examples)

;;; The shared store

(defstruct revision text summary time)

(defvar *wiki* (make-hash-table :test 'equal)
  "Page name → list of REVISIONs, newest first.")

(defvar *wiki-lock* (sb-thread:make-mutex :name "wiki"))

(defun page-revisions (name)
  "The revisions of page NAME, newest first."
  (sb-thread:with-mutex (*wiki-lock*) (gethash name *wiki*)))

(defun page-text (name)
  "The current text of page NAME, or NIL when it does not exist."
  (let ((latest (first (page-revisions name))))
    (and latest (revision-text latest))))

(defun save-page (name text summary)
  "Store TEXT as a new revision of page NAME."
  (sb-thread:with-mutex (*wiki-lock*)
    (push (make-revision :text text :summary summary :time (get-universal-time))
          (gethash name *wiki*))))

(defun all-pages ()
  "The names of every page, alphabetically."
  (sort (sb-thread:with-mutex (*wiki-lock*) (alexandria:hash-table-keys *wiki*)) #'string-lessp))

(defvar *wiki-comments* (make-instance 'memory-comment-store)
  "The comments on the wiki's pages.")

(defun reset-wiki ()
  "Start the wiki over with its welcome pages, and no comments."
  (sb-thread:with-mutex (*wiki-lock*) (clrhash *wiki*))
  (setf *wiki-comments* (make-instance 'memory-comment-store))
  (save-page "FrontPage"
             (format nil "= Welcome~%~%This wiki is a littoral example. Every page has its own URL, ~
so you can bookmark [[Littoral]] or [[Sandbox]].~%~%- Click *Edit* to change a page.~%~
- Link to a new page with [[Some Name]], then follow the link to write it.~%~
- _History_ shows every revision and can revert to one.")
             "Created")
  (save-page "Littoral"
             (format nil "A Seaside-style web framework for Common Lisp. Back to the [[FrontPage]].")
             "Created"))

(unless (page-revisions "FrontPage") (reset-wiki))

;;; Rendering markup

(defun render-inline (string wiki)
  "Write STRING with *bold*, _italic_ and [[links]], escaping the rest."
  (let ((start 0))
    (cl-ppcre:do-scans (ms me rs re "\\[\\[([^\\]]+)\\]\\]|\\*([^*]+)\\*|_([^_]+)_" string)
      (h:text (subseq string start ms))
      (let ((link (and (aref rs 0) (subseq string (aref rs 0) (aref re 0))))
            (bold (and (aref rs 1) (subseq string (aref rs 1) (aref re 1))))
            (italic (and (aref rs 2) (subseq string (aref rs 2) (aref re 2)))))
        (cond (link (let ((name (string-trim " " link)))
                      (h:anchor (:class (if (page-revisions name) "wiki-link" "wiki-link missing")
                               :callback (lambda () (visit-page wiki name)))
                        (h:text name))))
              (bold (h:strong () (h:text bold)))
              (t (h:em () (h:text italic)))))
      (setf start me))
    (h:text (subseq string start))))

(defun render-markup (text wiki)
  "Write TEXT's wiki markup as HTML, its links leading WIKI to other pages."
  (dolist (block (cl-ppcre:split "\\n\\s*\\n" text))
    (let ((lines (cl-ppcre:split "\\n" (string-trim '(#\Newline #\Return #\Space) block))))
      (when lines
        (cond ((every (lambda (l) (alexandria:starts-with-subseq "- " l)) lines)
               (h:ul () (dolist (l lines) (h:li () (render-inline (subseq l 2) wiki)))))
              ((alexandria:starts-with-subseq "= " (first lines))
               (h:h2 () (render-inline (subseq (first lines) 2) wiki)))
              (t (h:p () (render-inline (format nil "~{~A~^ ~}" lines) wiki))))))))

;;; Components

(defclass wiki-editor (component)
  ((name :initarg :name :reader editor-page)
   (text :initarg :text :accessor editor-text)
   (summary :initform "" :accessor editor-summary)
   (preview-p :initform nil :accessor editor-preview-p))
  (:documentation "Edits a page's text; answers (TEXT . SUMMARY) or NIL."))

(defmethod render ((self wiki-editor))
  (h:h2 () "Editing " (h:text (editor-page self)))
  (when (editor-preview-p self)
    (h:div (:class "wiki-preview")
      (render-markup (editor-text self) nil)))
  (h:form ()
    (h:text-area (:id "text" :rows 14 :value (editor-text self)
                :callback (lambda (v) (setf (editor-text self) v))))
    (h:label () "Summary "
      (h:text-input (:id "summary" :value (editor-summary self)
                   :callback (lambda (v) (setf (editor-summary self) v)))))
    (h:div (:class "lt-buttons")
      (h:submit-button (:callback (lambda () (setf (editor-preview-p self) t))) "Preview")
      (h:submit-button (:callback (lambda () (answer self (cons (editor-text self) (editor-summary self)))))
        "Save")
      (h:cancel-button (:callback (lambda () (answer self nil))) "Cancel"))))

(defclass wiki-history (component)
  ((name :initarg :name :reader history-page)
   (shown :initform nil :accessor history-shown)
   (changes :initform nil :accessor history-changes :documentation "A diff-view of one revision's changes, or NIL."))
  (:documentation "Lists a page's revisions, with view, what changed, and revert."))

(defmethod states ((self wiki-history)) (list self))

(defmethod children ((self wiki-history))
  (and (history-changes self) (list (history-changes self))))

(defun show-changes (history older newer n)
  "Show what revision N, NEWER, changed from OLDER (NIL for none)."
  (setf (history-shown history) nil
        (history-changes history)
        (make-instance 'diff-view :old (if older (revision-text older) "") :new (revision-text newer)
                                  :old-label (if older (format nil "#~D" (1- n)) "Nothing")
                                  :new-label (format nil "#~D" n))))

(defmethod render ((self wiki-history))
  (let* ((name (history-page self))
         (revisions (page-revisions name))
         (count (length revisions)))
    (h:h2 () "History of " (h:text name))
    (h:table (:class "lt-table")
      (h:tr () (h:th () "#") (h:th () "When") (h:th () "Summary") (h:th ()))
      (loop for revision in revisions
            for n downfrom count
            do (let ((revision revision) (n n))
                 (h:tr ()
                   (h:td () (h:text n))
                   (h:td () (h:text (format-time (revision-time revision))))
                   (h:td () (h:text (revision-summary revision)))
                   (h:td () (h:anchor (:callback (lambda () (setf (history-shown self) revision
                                                               (history-changes self) nil)))
                            "view")
                     (h:text " ")
                     (h:anchor (:callback (lambda () (show-changes self (nth (- count n -1) revisions) revision n))
                              :aria-label (format nil "Changes in #~D" n))
                       "changes")
                     (unless (= n count)
                       (h:text " ")
                       (h:anchor (:callback (lambda ()
                                            (save-page name (revision-text revision)
                                                       (format nil "Reverted to #~D" n))
                                            (answer self t)))
                         "revert")))))))
    (when (history-shown self)
      (h:div (:class "wiki-preview") (render-markup (revision-text (history-shown self)) nil)))
    (when (history-changes self)
      (render-component (history-changes self)))
    (h:p () (h:anchor (:callback (lambda () (answer self nil))) "Back to the page"))))

(defun format-time (universal-time)
  "UNIVERSAL-TIME as YYYY-MM-DD HH:MM."
  (multiple-value-bind (s m h day month year) (decode-universal-time universal-time)
    (declare (ignore s))
    (format nil "~D-~2,'0D-~2,'0D ~2,'0D:~2,'0D" year month day h m)))

(defclass wiki (component)
  ((page :initform "FrontPage" :accessor wiki-page)
   (query :initform "" :accessor wiki-query)
   (results :initform nil :accessor wiki-results)
   (trail :initform '() :accessor wiki-trail :documentation "Pages visited, newest first.")
   (readers :reader wiki-readers :documentation "Who else has this page open.")
   (comments :reader wiki-comments :documentation "The comments on the page shown."))
  (:documentation "The wiki: one page at a time, with search, editing and history."))

(defun page-presence (name)
  "The presence of everyone with wiki page NAME open, reading or editing."
  (find-presence (format nil "wiki:~A" name)))

(defmethod initialize-instance :after ((self wiki) &key)
  (setf (slot-value self 'readers)
        (make-instance 'presence-list :presence (lambda () (page-presence (wiki-page self))))
        (slot-value self 'comments)
        (make-instance 'live-comment-thread :thread (lambda () (format nil "wiki:~A" (wiki-page self)))
                                       :store (lambda () *wiki-comments*) :ask-name t :markdown t)))

(defmethod children ((self wiki)) (list (wiki-readers self) (wiki-comments self)))

;; Someone editing a page is still on it, and says so.
(defmethod presences ((self wiki-editor)) (list (page-presence (editor-page self))))
(defmethod presence-activity ((self wiki-editor)) "editing")

;; The page being viewed backtracks; the wiki's contents do not.
(defmethod states ((self wiki))
  (list self))

(defmethod update-url ((self wiki) url)
  (add-to-path url (wiki-page self)))

(defmethod initial-request ((self wiki) request)
  (declare (ignore request))
  (let ((name (first (request-extra-path))))
    (when (and name (string/= name ""))
      (setf (wiki-page self) name))))

(defun visit-page (wiki name)
  "Show page NAME in WIKI."
  (when wiki                              ; previews render links inertly
    (setf (wiki-trail wiki) (cons (wiki-page wiki) (remove name (wiki-trail wiki) :test #'string=))
          (wiki-page wiki) name
          (wiki-results wiki) nil)))

(defun edit-page (wiki)
  "Edit WIKI's current page and save what the editor answers."
  (let ((name (wiki-page wiki)))
    (show wiki (make-instance 'wiki-editor :name name
                                           :text (or (page-text name) ""))
          :on-answer (lambda (edit)
                       (when edit
                         (save-page name (first edit)
                                    (if (string= (rest edit) "") "Edited" (rest edit))))))))

(defun search-wiki (wiki)
  "Find the pages whose name or text holds WIKI's query."
  (let ((query (string-trim " " (wiki-query wiki))))
    (setf (wiki-results wiki)
          (if (string= query "")
              nil
              (or (remove-if-not (lambda (name)
                                   (or (search query name :test #'char-equal)
                                       (search query (page-text name) :test #'char-equal)))
                                 (all-pages))
                  :none)))))

(defmethod render ((self wiki))
  (let ((name (wiki-page self)))
    (h:header (:class "wiki-header")
      (h:anchor (:class "wiki-home" :callback (lambda () (visit-page self "FrontPage"))) "Wiki")
      (h:form (:class "wiki-search")
        (h:text-input (:id "query" :value (wiki-query self) :placeholder "Search"
                     :callback (lambda (v) (setf (wiki-query self) v))))
        (h:submit-button (:callback (lambda () (search-wiki self))) "Search")))
    (let ((results (wiki-results self)))
      (when results
        (h:div (:class "lt-dialog")
          (cond ((eql results :none)
                 (h:p () "Nothing matches."))
                (t
                 (h:p () (h:text (format nil "~D page~:P match:" (length results))))
                 (h:ul () (dolist (r results)
                          (let ((r r))
                            (h:li () (h:anchor (:callback (lambda () (visit-page self r))) (h:text r)))))))))))
    (h:article (:class "wiki-page")
      (h:h1 () (h:text name))
      (let ((text (page-text name)))
        (if text
            (render-markup text self)
            (h:p (:class "empty") "This page does not exist yet. "
              (h:anchor (:callback (lambda () (edit-page self))) "Write it")
              "."))))
    (h:aside (:class "wiki-readers" :aria-label "On this page")
      (render-component (wiki-readers self)))
    (h:nav (:class "wiki-actions")
      (h:anchor (:callback (lambda () (edit-page self))) "Edit")
      (when (page-revisions name)
        (h:anchor (:callback (lambda () (show self (make-instance 'wiki-history :name name))))
          "History"))
      (h:span (:class "wiki-pages") "All pages: "
        (dolist (page (all-pages))
          (let ((page page))
            (h:anchor (:callback (lambda () (visit-page self page))) (h:text page))
            (h:text " ")))))
    (render-component (wiki-comments self))
    (when (wiki-trail self)
      (h:p (:class "wiki-trail") "Recently: "
        (loop for page in (subseq (wiki-trail self) 0 (min 5 (length (wiki-trail self))))
              do (let ((page page))
                   (h:anchor (:callback (lambda () (visit-page self page))) (h:text page))
                   (h:text " ")))))))

(defmethod style ((self wiki))
  ".wiki-header { display: flex; flex-wrap: wrap; gap: .4rem 1rem; justify-content: space-between; align-items: center;
                border-bottom: 1px solid var(--lt-border); padding-bottom: .4rem; }
.wiki-home { font-weight: 700; font-size: 1.2rem; text-decoration: none; }
.wiki-link.missing { color: var(--lt-error); text-decoration: underline dotted; }
.wiki-actions { display: flex; gap: 1rem; flex-wrap: wrap; border-top: 1px solid var(--lt-border);
                padding-top: .5rem; font-size: .9rem; }
.wiki-pages a { margin-right: .2rem; }
.wiki-trail { font-size: .85rem; color: var(--lt-muted); }
.wiki-preview { border: 1px dashed var(--lt-border); padding: .2rem 1rem; margin: .5rem 0; }
textarea#text { width: 100%; font-family: ui-monospace, monospace; }")
