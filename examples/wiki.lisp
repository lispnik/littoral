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
  (sb-thread:with-mutex (*wiki-lock*) (gethash name *wiki*)))

(defun page-text (name)
  (let ((latest (first (page-revisions name))))
    (and latest (revision-text latest))))

(defun save-page (name text summary)
  (sb-thread:with-mutex (*wiki-lock*)
    (push (make-revision :text text :summary summary :time (get-universal-time))
          (gethash name *wiki*))))

(defun all-pages ()
  (sort (sb-thread:with-mutex (*wiki-lock*) (alexandria:hash-table-keys *wiki*)) #'string-lessp))

(defun reset-wiki ()
  (sb-thread:with-mutex (*wiki-lock*) (clrhash *wiki*))
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
      (text (subseq string start ms))
      (let ((link (and (aref rs 0) (subseq string (aref rs 0) (aref re 0))))
            (bold (and (aref rs 1) (subseq string (aref rs 1) (aref re 1))))
            (italic (and (aref rs 2) (subseq string (aref rs 2) (aref re 2)))))
        (cond (link (let ((name (string-trim " " link)))
                      (anchor (:class (if (page-revisions name) "wiki-link" "wiki-link missing")
                               :callback (lambda () (visit-page wiki name)))
                        (text name))))
              (bold (strong () (text bold)))
              (italic (em () (text italic)))))
      (setf start me))
    (text (subseq string start))))

(defun render-markup (text wiki)
  (dolist (block (cl-ppcre:split "\\n\\s*\\n" text))
    (let ((lines (cl-ppcre:split "\\n" (string-trim '(#\Newline #\Return #\Space) block))))
      (cond ((null lines))
            ((every (lambda (l) (alexandria:starts-with-subseq "- " l)) lines)
             (ul () (dolist (l lines) (li () (render-inline (subseq l 2) wiki)))))
            ((alexandria:starts-with-subseq "= " (first lines))
             (h2 () (render-inline (subseq (first lines) 2) wiki)))
            (t (p () (render-inline (format nil "~{~A~^ ~}" lines) wiki)))))))

;;; Components

(defclass wiki-editor (component)
  ((name :initarg :name :reader editor-page)
   (text :initarg :text :accessor editor-text)
   (summary :initform "" :accessor editor-summary)
   (preview-p :initform nil :accessor editor-preview-p)))

(defmethod render ((self wiki-editor))
  (h2 () "Editing " (text (editor-page self)))
  (when (editor-preview-p self)
    (div (:class "wiki-preview")
      (render-markup (editor-text self) nil)))
  (form ()
    (text-area (:id "text" :rows 14 :value (editor-text self)
                :callback (lambda (v) (setf (editor-text self) v))))
    (label () "Summary "
      (text-input (:id "summary" :value (editor-summary self)
                   :callback (lambda (v) (setf (editor-summary self) v)))))
    (div (:class "lt-buttons")
      (submit-button (:callback (lambda () (setf (editor-preview-p self) t))) "Preview")
      (submit-button (:callback (lambda () (answer self (cons (editor-text self) (editor-summary self)))))
        "Save")
      (cancel-button (:callback (lambda () (answer self nil))) "Cancel"))))

(defclass wiki-history (component)
  ((name :initarg :name :reader history-page)
   (shown :initform nil :accessor history-shown)))

(defmethod render ((self wiki-history))
  (let* ((name (history-page self))
         (revisions (page-revisions name))
         (count (length revisions)))
    (h2 () "History of " (text name))
    (table (:class "lt-table")
      (tr () (th () "#") (th () "When") (th () "Summary") (th ()))
      (loop for revision in revisions
            for n downfrom count
            do (let ((revision revision) (n n))
                 (tr ()
                   (td () (text n))
                   (td () (text (format-time (revision-time revision))))
                   (td () (text (revision-summary revision)))
                   (td () (anchor (:callback (lambda () (setf (history-shown self) revision))) "view")
                     (unless (= n count)
                       (text " ")
                       (anchor (:callback (lambda ()
                                            (save-page name (revision-text revision)
                                                       (format nil "Reverted to #~D" n))
                                            (answer self t)))
                         "revert")))))))
    (when (history-shown self)
      (div (:class "wiki-preview") (render-markup (revision-text (history-shown self)) nil)))
    (p () (anchor (:callback (lambda () (answer self nil))) "Back to the page"))))

(defun format-time (universal-time)
  (multiple-value-bind (s m h day month year) (decode-universal-time universal-time)
    (declare (ignore s))
    (format nil "~D-~2,'0D-~2,'0D ~2,'0D:~2,'0D" year month day h m)))

(defclass wiki (component)
  ((page :initform "FrontPage" :accessor wiki-page)
   (query :initform "" :accessor wiki-query)
   (results :initform nil :accessor wiki-results)
   (trail :initform '() :accessor wiki-trail :documentation "Pages visited, newest first.")))

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
  (when wiki                              ; previews render links inertly
    (setf (wiki-trail wiki) (cons (wiki-page wiki) (remove name (wiki-trail wiki) :test #'string=))
          (wiki-page wiki) name
          (wiki-results wiki) nil)))

(defun edit-page (wiki)
  (let ((name (wiki-page wiki)))
    (show wiki (make-instance 'wiki-editor :name name
                                           :text (or (page-text name) ""))
          :on-answer (lambda (edit)
                       (when edit
                         (save-page name (car edit)
                                    (if (string= (cdr edit) "") "Edited" (cdr edit))))))))

(defun search-wiki (wiki)
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
    (header (:class "wiki-header")
      (anchor (:class "wiki-home" :callback (lambda () (visit-page self "FrontPage"))) "Wiki")
      (form (:class "wiki-search")
        (text-input (:id "query" :value (wiki-query self) :placeholder "Search"
                     :callback (lambda (v) (setf (wiki-query self) v))))
        (submit-button (:callback (lambda () (search-wiki self))) "Search")))
    (let ((results (wiki-results self)))
      (when results
        (div (:class "lt-dialog")
          (if (eq results :none)
              (p () "Nothing matches.")
              (progn
                (p () (text (format nil "~D page~:P match:" (length results))))
                (ul () (dolist (r results)
                         (let ((r r))
                           (li () (anchor (:callback (lambda () (visit-page self r))) (text r)))))))))))
    (article (:class "wiki-page")
      (h1 () (text name))
      (let ((text (page-text name)))
        (if text
            (render-markup text self)
            (p (:class "empty") "This page does not exist yet. "
              (anchor (:callback (lambda () (edit-page self))) "Write it")
              "."))))
    (nav (:class "wiki-actions")
      (anchor (:callback (lambda () (edit-page self))) "Edit")
      (when (page-revisions name)
        (anchor (:callback (lambda () (show self (make-instance 'wiki-history :name name))))
          "History"))
      (span (:class "wiki-pages") "All pages: "
        (dolist (page (all-pages))
          (let ((page page))
            (anchor (:callback (lambda () (visit-page self page))) (text page))
            (text " ")))))
    (when (wiki-trail self)
      (p (:class "wiki-trail") "Recently: "
        (loop for page in (subseq (wiki-trail self) 0 (min 5 (length (wiki-trail self))))
              do (let ((page page))
                   (anchor (:callback (lambda () (visit-page self page))) (text page))
                   (text " ")))))))

(defmethod style ((self wiki))
  ".wiki-header { display: flex; justify-content: space-between; align-items: center;
                border-bottom: 1px solid var(--lt-border); padding-bottom: .4rem; }
.wiki-home { font-weight: 700; font-size: 1.2rem; text-decoration: none; }
.wiki-link.missing { color: var(--lt-error); text-decoration: underline dotted; }
.wiki-actions { display: flex; gap: 1rem; flex-wrap: wrap; border-top: 1px solid var(--lt-border);
                padding-top: .5rem; font-size: .9rem; }
.wiki-pages a { margin-right: .2rem; }
.wiki-trail { font-size: .85rem; color: var(--lt-muted); }
.wiki-preview { border: 1px dashed var(--lt-border); padding: .2rem 1rem; margin: .5rem 0; }
textarea#text { width: 100%; font-family: ui-monospace, monospace; }")
