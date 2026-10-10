;;;; search-demo.lisp — full-text search over Common Lisp's own documentation
;;;;
;;;; (asdf:load-system :littoral/search-demo) (littoral-search-demo:register)
;;;; serves /examples/search: every documented external symbol of COMMON-LISP,
;;;; kept in SQLite with a full-text index (DEFINE-TABLE :SEARCH), searched as
;;;; you type, best matches first, the words found marked.

(defpackage #:littoral-search-demo
  (:use #:cl #:littoral #:littoral.html)
  (:documentation "Full-text search over the COMMON-LISP package's documentation.")
  (:export #:register #:search-page))

(in-package #:littoral-search-demo)

(defclass entry (littoral.db:persistent)
  ((name :initarg :name :initform nil :accessor entry-name)
   (kind :initarg :kind :initform nil :accessor entry-kind)
   (documentation :initarg :documentation :initform nil :accessor entry-documentation))
  (:documentation "A documented symbol of COMMON-LISP."))

(define-description entry
  ((name :required t) (kind) (documentation :type :text)))

(littoral.db:define-table entry :name "cl_entries" :search (name documentation))

(defun seed ()
  "Fill the table, once, with every documented external symbol of COMMON-LISP."
  (when (zerop (littoral.db:db-count 'entry))
    (littoral.db:with-transaction ()
      (do-external-symbols (symbol :cl)
        (loop for (kind type) in '(("function" function) ("variable" variable) ("type" type))
              for text = (documentation symbol type)
              when text
                do (littoral.db:db-insert (make-instance 'entry :name (string-downcase symbol) :kind kind
                                                                :documentation text)))))))

(defclass search-page (component updatable)
  ((query :initform "list" :accessor page-query))
  (:documentation "A search box and the entries it finds."))

(defmethod states ((self search-page)) (list self))

(defmethod render ((self search-page))
  (h1 () "Search")
  (p () "Every documented external symbol of " (code () "COMMON-LISP") " ("
    (text (littoral.db:db-count 'entry)) " entries), kept in SQLite with a full-text index. "
    "Words match the start of words, all of them are required, and the best matches come first.")
  (form ()
    (text-input (:id "query" :label "Search the documentation" :value (page-query self)
                 :callback (lambda (v) (setf (page-query self) v))
                 :on-input (ajax-update self) :autofocus t)))
  (let* ((query (page-query self))
         (found (littoral.db:db-search 'entry query :limit 25)))
    (p (:role "status") (text (cond ((string= (string-trim " " query) "") "Type something to search for.")
                                    ((null found) "Nothing found.")
                                    (t (format nil "The best ~D match~:*~[es~;~:;es~]:" (length found))))))
    (ol (:class "search-results")
      (dolist (entry found)
        (li ()
          (p () (strong () (raw (littoral.db:highlight-matches (entry-name entry) query)))
            " " (span (:class "search-kind") (text (entry-kind entry))))
          (p (:class "search-doc")
            (raw (littoral.db:highlight-matches
                  (let ((doc (entry-documentation entry)))
                    (if (> (length doc) 280) (concatenate 'string (subseq doc 0 280) "…") doc))
                  query))))))))

(defmethod style ((self search-page))
  ".search-results { padding-left: 1.4rem; }
.search-results li { margin: .6rem 0; }
.search-results p { margin: .1rem 0; }
.search-kind { color: var(--lt-muted); font-size: .8rem; }
.search-doc { white-space: pre-wrap; font-size: .9rem; }
mark { background: color-mix(in srgb, var(--lt-accent) 30%, transparent); color: inherit; border-radius: 2px; }")

(defun register (&key (path "/examples/search")
                   (file (merge-pathnames "littoral-search-demo.sqlite3" (uiop:temporary-directory))))
  "Serve the search demo at PATH, its index in FILE."
  (let ((database (littoral.db:using-database :sqlite3 :database-name (namestring file))))
    (funcall database (lambda () (littoral.db:create-table 'entry) (seed)))
    (register-application path 'search-page :title "Search" :around-request database)))
