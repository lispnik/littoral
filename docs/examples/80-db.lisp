;;;; The examples for littoral.db: described objects in SQLite.  See tools/doc-examples.lisp for the format.

;;;; Example: littoral.db:connect-database littoral.db:*database* littoral.db:disconnect-database
;;; A program connects once at start-up; here the LET keeps the setting to the example.  Each thread then makes its own connection when it first needs one.
(let ((littoral.db:*database* nil))
  (littoral.db:connect-database :sqlite3 :database-name ":memory:")
  (list littoral.db:*database*
        (littoral.db:db-query "SELECT 1 + 1 AS two")
        (progn (littoral.db:disconnect-database) littoral.db:*database*)))
;; ⇒ ((:SQLITE3 :DATABASE-NAME ":memory:") ((:|two| 2)) NIL)

;;;; Example: littoral.db:database-connection
;;; This thread's connection, made the first time and kept.  With no database there is none to make.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (eq (littoral.db:database-connection) (littoral.db:database-connection)))
;; ⇒ T
(let ((littoral.db:*database* nil))
  (handler-case (littoral.db:database-connection)
    (error (e) (princ-to-string e))))
;; ⇒ "No database: call CONNECT-DATABASE first."

;;;; Example: littoral.db:database-label
;;; How logs and /metrics name a database: never with its password.
(littoral.db:database-label '(:postgres :database-name "shop" :host "db.internal" :port 5433
                              :username "shop" :password "secret"))
;; ⇒ "postgres://db.internal:5433/shop"
(littoral.db:database-label '(:sqlite3 :database-name "/var/lib/shop/shop.db"))
;; ⇒ "/var/lib/shop/shop.db"

;;;; Example: littoral.db:persistent littoral.db:define-table littoral.db:create-table littoral.db:db-save littoral.db:db-find
;;; A class with the PERSISTENT mixin and a description is kept in a table with a column for each field.  Saving a new object inserts it and gives it an id; DB-FIND reads it back.
(defclass book (littoral.db:persistent)
  ((title :initarg :title :initform nil :accessor book-title)
   (pages :initarg :pages :initform nil :accessor book-pages)))
(define-description book
  ((title :required t)
   (pages :type :integer :min 1)))
(littoral.db:define-table book)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'book)
  (let ((saved (littoral.db:db-save (make-instance 'book :title "Dune" :pages 412))))
    (let ((found (littoral.db:db-find 'book (littoral.db:object-id saved))))
      (list (book-title found) (book-pages found) (littoral.db:db-find 'book 99)))))
;; ⇒ ("Dune" 412 NIL)

;;;; Example: littoral.db:object-id littoral.db:object-version littoral.db:db-insert littoral.db:db-update
;;; An object has no id until it is first saved.  Each update adds one to its version, which is how a conflicting save is noticed (see STALE-OBJECT).  DB-SAVE calls DB-INSERT or DB-UPDATE as the object needs.
(defclass note (littoral.db:persistent)
  ((text :initarg :text :initform nil :accessor note-text)))
(define-description note ((text :required t)))
(littoral.db:define-table note)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'note)
  (let ((note (make-instance 'note :text "Buy milk")))
    (list (littoral.db:object-id note)
          (progn (littoral.db:db-insert note)
                 (list (littoral.db:object-id note) (littoral.db:object-version note)))
          (progn (setf (note-text note) "Buy oat milk")
                 (littoral.db:db-update note)
                 (list (littoral.db:object-id note) (littoral.db:object-version note))))))
;; ⇒ (NIL (1 0) (1 1))

;;;; Example: littoral.db:find-table littoral.db:table-name littoral.db:table-class
;;; DEFINE-TABLE's :NAME names the table; by default it is the class's name, with underscores for dashes.
(defclass line-item (littoral.db:persistent) ((sku :initarg :sku :initform nil)))
(define-description line-item ((sku :required t)))
(littoral.db:define-table line-item)
(defclass invoice (littoral.db:persistent) ((number :initarg :number :initform nil)))
(define-description invoice ((number :required t)))
(littoral.db:define-table invoice :name "invoices")
(list (littoral.db:table-name (littoral.db:find-table 'line-item))
      (littoral.db:table-name (littoral.db:find-table (make-instance 'invoice)))
      (littoral.db:table-class (littoral.db:find-table 'invoice)))
;; ⇒ ("line_item" "invoices" INVOICE)

;;;; Example: littoral.db:drop-table
;;; Dropping a table that isn't there does nothing.
(defclass draft (littoral.db:persistent) ((text :initarg :text :initform nil)))
(define-description draft ((text)))
(littoral.db:define-table draft)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (flet ((tables () (mapcar #'second (littoral.db:db-query "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'draft'"))))
    (littoral.db:create-table 'draft)
    (list (tables)
          (progn (littoral.db:drop-table 'draft) (tables))
          (progn (littoral.db:drop-table 'draft) (tables)))))
;; ⇒ (("draft") NIL NIL)

;;;; Example: littoral.db:db-select littoral.db:db-count
;;; WHERE and ORDER-BY are SQL, with ? for each of PARAMS.  LIMIT and OFFSET page through the results.
(defclass city (littoral.db:persistent)
  ((name :initarg :name :initform nil)
   (people :initarg :people :initform nil)))
(define-description city ((name :required t) (people :type :integer)))
(littoral.db:define-table city)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'city)
  (loop for (name people) in '(("Lyon" 522000) ("Nantes" 320000) ("Paris" 2100000) ("Lille" 236000))
        do (littoral.db:db-save (make-instance 'city :name name :people people)))
  (flet ((names (cities) (mapcar (lambda (c) (slot-value c 'name)) cities)))
    (list (names (littoral.db:db-select 'city))
          (names (littoral.db:db-select 'city :where "people > ?" :params '(300000)
                                              :order-by "people DESC"))
          (names (littoral.db:db-select 'city :order-by "name" :limit 2 :offset 1))
          (names (littoral.db:db-select 'city :order-by "name" :offset 2))
          (littoral.db:db-count 'city)
          (littoral.db:db-count 'city :where "name LIKE ?" :params '("L%")))))
;; ⇒ (("Lyon" "Nantes" "Paris" "Lille") ("Paris" "Lyon" "Nantes") ("Lyon" "Nantes") ("Nantes" "Paris") 4 2)

;;;; Example: littoral.db:db-delete littoral.db:db-reload
;;; Deleting forgets the object's id.  Reloading a copy whose row has gone gives NIL.
(defclass reminder (littoral.db:persistent) ((text :initarg :text :initform nil)))
(define-description reminder ((text :required t)))
(littoral.db:define-table reminder)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'reminder)
  (let* ((reminder (littoral.db:db-save (make-instance 'reminder :text "Call the plumber")))
         (copy (littoral.db:db-find 'reminder (littoral.db:object-id reminder))))
    (list (slot-value (littoral.db:db-reload copy) 'text)
          (littoral.db:object-id (littoral.db:db-delete reminder))
          (littoral.db:db-reload copy)
          (littoral.db:db-count 'reminder))))
;; ⇒ ("Call the plumber" NIL NIL 0)

;;;; Example: littoral.db:stale-object littoral.db:stale-object-object
;;; Two people edit the same row.  The second save would overwrite the first one's change, so it signals STALE-OBJECT instead; reloading gives the current row to show or merge.
(defclass wiki-page (littoral.db:persistent) ((body :initarg :body :initform nil)))
(define-description wiki-page ((body :type :text)))
(littoral.db:define-table wiki-page)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'wiki-page)
  (let* ((id (littoral.db:object-id (littoral.db:db-save (make-instance 'wiki-page :body "Draft"))))
         (mine (littoral.db:db-find 'wiki-page id))
         (theirs (littoral.db:db-find 'wiki-page id)))
    (setf (slot-value theirs 'body) "Theirs")
    (littoral.db:db-save theirs)
    (setf (slot-value mine 'body) "Mine")
    (handler-case (littoral.db:db-save mine)
      (littoral.db:stale-object (condition)
        (list (eq mine (littoral.db:stale-object-object condition))
              (slot-value (littoral.db:db-reload mine) 'body))))))
;; ⇒ (T "Theirs")

;;;; Example: littoral.db:db-query littoral.db:db-execute
;;; Plain SQL, with ? for each parameter.  DB-EXECUTE answers how many rows changed; DB-QUERY the rows, as plists keyed by column name, NULL as NIL.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:db-execute "CREATE TABLE visits (page TEXT, n INTEGER, note TEXT)")
  (list (littoral.db:db-execute "INSERT INTO visits (page, n) VALUES (?, ?), (?, ?)" "/" 10 "/about" 2)
        (littoral.db:db-execute "UPDATE visits SET n = n + 1 WHERE page = ?" "/about")
        (littoral.db:db-query "SELECT page, n, note FROM visits WHERE n > ? ORDER BY n" 0)))
;; ⇒ (2 1 ((:|page| "/about" :|n| 3 :|note| NIL) (:|page| "/" :|n| 10 :|note| NIL)))

;;;; Example: littoral.db:with-transaction
;;; A transaction that signals is rolled back: the first account is not kept.
(defclass account (littoral.db:persistent) ((owner :initarg :owner :initform nil)))
(define-description account ((owner :required t)))
(littoral.db:define-table account)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'account)
  (ignore-errors
   (littoral.db:with-transaction ()
     (littoral.db:db-save (make-instance 'account :owner "Ada"))
     (error "The bank is closed.")))
  (littoral.db:with-transaction ()
    (littoral.db:db-save (make-instance 'account :owner "Grace")))
  (mapcar (lambda (a) (slot-value a 'owner)) (littoral.db:db-select 'account)))
;; ⇒ ("Grace")

;;;; Example: littoral.db:transactional
;;; With :AROUND-ACTIONS (TRANSACTIONAL), a request's callbacks share one transaction: when one fails, what the others saved is rolled back too.
(defclass vote (littoral.db:persistent) ((choice :initarg :choice :initform nil)))
(define-description vote ((choice :required t)))
(littoral.db:define-table vote)
(defclass ballot (component) ())
(defmethod render ((self ballot))
  (p () (text (format nil "~D vote~:P" (littoral.db:db-count 'vote))))
  (anchor (:callback (lambda ()
                       (littoral.db:db-save (make-instance 'vote :choice "yes"))
                       (error "Counting failed.")))
    "Vote"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'vote)
  (with-fresh-applications (("/ballot" 'ballot :mode :deployment
                                               :around-actions (littoral.db:transactional)))
    (let ((b (make-instance 'browser)))
      (visit b "/ballot")
      (click b "Vote")
      (list (browser-status b) (littoral.db:db-count 'vote)))))
;; ⇒ (500 0)

;;;; Example: littoral.db:using-database
;;; An application with a database of its own, whatever *DATABASE* says (here it is NIL).
(defclass memo (littoral.db:persistent) ((text :initarg :text :initform nil)))
(define-description memo ((text :required t)))
(littoral.db:define-table memo)
(defclass memo-count (component) ())
(defmethod render ((self memo-count))
  (p () (text (format nil "~D memo~:P" (littoral.db:db-count 'memo)))))
(let ((spec '(:sqlite3 :database-name ":memory:")))
  (let ((littoral.db:*database* spec))
    (littoral.db:create-table 'memo)
    (littoral.db:db-save (make-instance 'memo :text "Buy milk")))
  (let ((littoral.db:*database* nil))
    (with-fresh-applications (("/memos" 'memo-count :mode :deployment
                                                    :around-request (apply #'littoral.db:using-database spec)))
      (let ((b (make-instance 'browser)))
        (visit b "/memos")
        (body-text b)))))
;; ⇒ "1 memo"

;;;; Example: littoral.db:db-search littoral.db:search-condition
;;; DEFINE-TABLE's :SEARCH fields are kept in a full-text index.  Each word of a query matches words starting with it, and all are required.  SEARCH-CONDITION gives the same test as a WHERE clause, to combine with others in DB-SELECT or DB-COUNT.
(defclass recipe (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (method :initarg :method :initform nil)))
(define-description recipe ((title :required t) (method :type :text)))
(littoral.db:define-table recipe :search (title method))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'recipe)
  (loop for (title method) in '(("Pancakes" "Whisk flour, eggs and milk; fry.")
                                ("Omelette" "Whisk the eggs and fry them in butter.")
                                ("Toast" "Grill the bread."))
        do (littoral.db:db-save (make-instance 'recipe :title title :method method)))
  (flet ((titles (recipes) (sort (mapcar (lambda (r) (slot-value r 'title)) recipes) #'string<)))
    (list (titles (littoral.db:db-search 'recipe "whisk egg"))
          (titles (littoral.db:db-search 'recipe "egg bread"))
          (multiple-value-bind (where params) (littoral.db:search-condition 'recipe "fry")
            (littoral.db:db-count 'recipe :where (format nil "~A AND title <> ?" where)
                                          :params (append params '("Omelette"))))
          (littoral.db:search-condition 'recipe "?!"))))
;; ⇒ (("Omelette" "Pancakes") NIL 1 NIL)

;;;; Example: littoral.db:highlight-matches
;;; For showing search results: the text escaped, with the words a query finds marked.
(littoral.db:highlight-matches "Fish & chips, fishcakes and chicken" "fish ch")
;; ⇒ "<mark>Fish</mark> &amp; <mark>chips</mark>, <mark>fishcakes</mark> and <mark>chicken</mark>"

;;;; Example: littoral.db:reference-field littoral.db:reference-class littoral.db:object-label
;;; A :REFERENCE field holds another stored object, kept as its id.  Its choices are that table's objects, named by their first string field.
(defclass author (littoral.db:persistent) ((name :initarg :name :initform nil)))
(define-description author ((name :required t)))
(littoral.db:define-table author)
(defclass novel (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (author :initarg :author :initform nil)))
(define-description novel ((title :required t) (author :type :reference :to 'author)))
(littoral.db:define-table novel)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'author)
  (littoral.db:create-table 'novel)
  (let* ((le-guin (littoral.db:db-save (make-instance 'author :name "Ursula K. Le Guin")))
         (novel (littoral.db:db-save (make-instance 'novel :title "The Dispossessed" :author le-guin)))
         (field (find-field 'novel 'author)))
    (list (littoral.db:reference-class field)
          (mapcar #'littoral.db:object-label (field-choices field))
          (littoral.db:object-label (slot-value (littoral.db:db-reload novel) 'author))
          (littoral.db:db-query "SELECT author FROM novel"))))
;; ⇒ (AUTHOR ("Ursula K. Le Guin") "Ursula K. Le Guin" ((:|author| 1)))

;;;; Example: littoral.db:sql-type littoral.db:to-sql littoral.db:from-sql
;;; How a field's values are kept: a boolean is an integer column.
(defclass chore (littoral.db:persistent)
  ((title :initarg :title :initform nil)
   (done :initarg :done :initform nil)))
(define-description chore ((title :required t) (done :type :boolean)))
(let ((field (find-field 'chore 'done)))
  (list (littoral.db:sql-type field) (littoral.db:to-sql field t) (littoral.db:from-sql field 0)))
;; ⇒ ("INTEGER" 1 NIL)

;;;; Example: littoral.db:sql-type littoral.db:to-sql littoral.db:from-sql
;;; A field kind of one's own: amounts of money, kept as whole cents so that sums are exact.  Binding *FIELD-KINDS* lets DEFINE-DESCRIPTION use it without adding it for everyone.
(defclass money-field (field) ()
  (:documentation "An amount of money, kept as whole cents."))
(defmethod littoral.db:sql-type ((field money-field)) "BIGINT")
(defmethod littoral.db:to-sql ((field money-field) value)
  (and value (round (* value 100))))
(defmethod littoral.db:from-sql ((field money-field) value)
  (and (integerp value) (/ value 100)))
(defclass product (littoral.db:persistent) ((price :initarg :price :initform nil)))
(let ((*field-kinds* (acons :money 'money-field *field-kinds*)))
  (define-description product ((price :type :money))))
(littoral.db:define-table product)
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.db:create-table 'product)
  (let ((id (littoral.db:object-id (littoral.db:db-save (make-instance 'product :price 12.5)))))
    (list (littoral.db:db-query "SELECT price FROM product")
          (slot-value (littoral.db:db-find 'product id) 'price))))
;; ⇒ (((:|price| 1250)) 25/2)

;;;; Example: littoral.db:*sqlite-journal-mode* littoral.db:*sqlite-synchronous* littoral.db:*sqlite-busy-timeout*
;;; A SQLite file is switched to write-ahead logging when Littoral first connects to it, so readers and the writer don't wait for each other.  A database spec's :JOURNAL-MODE, :SYNCHRONOUS and :BUSY-TIMEOUT override these variables for that database.
(let* ((file (namestring (merge-pathnames "littoral-example-journal.db" (uiop:temporary-directory))))
       (littoral.db:*database* (list :sqlite3 :database-name file)))
  (unwind-protect
       (list littoral.db:*sqlite-journal-mode* littoral.db:*sqlite-synchronous* littoral.db:*sqlite-busy-timeout*
             (littoral.db:db-query "PRAGMA journal_mode")
             (littoral.db:db-query "PRAGMA synchronous"))
    (dolist (suffix '("" "-wal" "-shm"))
      (uiop:delete-file-if-exists (concatenate 'string file suffix)))))
;; ⇒ (:WAL :NORMAL 5000 ((:|journal_mode| "wal")) ((:|synchronous| 1)))
