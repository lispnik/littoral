# Littoral tutorial: a reading list

This tutorial builds a small application, a reading list, one idea at a time. By the end it uses components, callbacks, the back button, forms, components inside components, call and answer, descriptions, a task, AJAX and server push. Then it tests the list, keeps it in a database, gives each reader a list of their own, and translates it into French.

Every piece of code here comes from three files, which the test suite runs: [`reading-list.lisp`](tutorial/reading-list.lisp) (steps 1 to 11), [`reading-list-tests.lisp`](tutorial/reading-list-tests.lisp) (step 12) and [`my-books.lisp`](tutorial/my-books.lisp) (steps 13 to 15), all in `docs/tutorial/`. The suite also pastes this page's code into fresh packages, block by block in order, the way you will, and checks that the applications it makes behave as the text says.

## Before you start

You need SBCL and a clone of littoral with its dependencies installed by `ocicl install` (see the README's [Getting started](index.md#getting-started)). Start SBCL in the littoral directory, as `make` does, and load littoral:

```lisp
(asdf:load-system :littoral)
```

Then type or paste each block below into the REPL, in order. A block that begins with a comment such as `;; The first version; step 10 replaces it.` is a stepping stone: paste it too, and a later step gives the finished definition.

If you'd rather read with the finished applications running, load them instead:

```lisp
(asdf:load-system :littoral/tutorial)
(reading-list:register)
(my-books:register)        ; steps 13 to 15; it makes my-books.db in the current directory
(littoral:start :port 8080)
```

To sign in to the stored list, add users as step 14 shows.

## 1. A component

A littoral application is a tree of **components**. A component is a CLOS object that remembers its own state and knows how to draw itself. To draw itself it writes HTML in its `render` method, using macros named after HTML tags.

```lisp
(defpackage #:reading-list
  (:use #:cl #:littoral)
  (:local-nicknames (#:h #:littoral.html))
  (:export #:reading-list #:hello #:counter #:register)
  (:documentation "The application the Littoral tutorial builds."))

(in-package #:reading-list)

(defclass hello (component) ()
  (:documentation "The smallest application."))

(defmethod render ((self hello))
  (h:h1 () "Hello, world"))
```

`littoral.html` holds the tags (`h1`, `div`, `p` and every other HTML element) and `littoral` holds everything else. The package uses `littoral` and gives `littoral.html` the nickname `h`, so tags are written `h:h1`, `h:div` and `h:p`: element names such as `time`, `map` and `label` would otherwise clash with CL's and your own. `in-package` makes `reading-list` the REPL's current package, so the code in the next steps goes into it too. A tag's first argument is its attributes, written as a plist like `(:class "intro")`. You can leave it out, or write `()`. A literal string in a tag's body is written as escaped text.

To serve the component, register it at a path and start the server:

```lisp
(register-application "/tutorial/hello" 'hello)
(start :port 8080)
```

Open <http://127.0.0.1:8080/tutorial/hello>. There are no routes, templates or request handlers to write. Each visitor gets a **session** with their own `hello` instance.

## 2. Callbacks and the back button

Links don't point at URLs you design. They carry closures, called **callbacks**:

```lisp
(defclass counter (component)
  ((count :initform 0 :accessor count-of))
  (:documentation "A number with links that change it."))

(defmethod states ((self counter))
  (list self))

(defmethod render ((self counter))
  (h:h1 () (h:text (count-of self)))
  (h:anchor (:callback (lambda () (incf (count-of self)))) "++")
  (h:text " ")
  (h:anchor (:callback (lambda () (decf (count-of self)))) "--"))
```

`(h:anchor (:callback …) "++")` writes a link. Clicking it runs the closure, which changes this visitor's own counter, and then the page is drawn again. Use `h:text` to write a value that isn't a literal string; it escapes the value too.

The server is already running, so registering the counter is enough:

```lisp
(register-application "/tutorial/counter" 'counter)
```

The `states` method names the objects whose slots should **backtrack**. Open <http://127.0.0.1:8080/tutorial/counter>, click ++ three times, press the browser's back button twice, then click ++. You'll see 2, not 4. Littoral saves a snapshot of those objects for every page it shows, and acting on an old page first restores that page's state. Leave `states` out and the counter would act on its latest value instead.

## 3. A model and a form

Next, the reading list itself. A book is ordinary data:

```lisp
(defclass book ()
  ((title :initarg :title :initform nil :accessor book-title)
   (author :initarg :author :initform nil :accessor book-author)
   (finished :initarg :finished :initform nil :accessor book-finished-p))
  (:documentation "A book on the list."))
```

The list is a component that holds the books and the title being typed. This is its first version; step 10 adds what the later steps need.

```lisp
;; The first version; step 10 replaces it.
(defclass reading-list (component)
  ((books :initform (list (make-instance 'book :title "Structure and Interpretation of Computer Programs"
                                               :author "Abelson and Sussman")
                          (make-instance 'book :title "Paradigms of Artificial Intelligence Programming"
                                               :author "Peter Norvig"))
          :accessor books)
   (new-title :initform "" :accessor new-title))
  (:documentation "The reading list."))
```

Its books backtrack, like the counter's count, and a function adds the typed title to them:

```lisp
(defmethod states ((self reading-list))
  (list self))

(defun add-quickly (list)
  "Add the typed title to LIST."
  (let ((title (string-trim " " (new-title list))))
    (unless (string= title "")
      (setf (books list) (append (books list) (list (make-instance 'book :title title)))
            (new-title list) ""))))
```

Forms work the same way as links. A field's `:callback` receives what was typed, and a button's `:callback` runs after all the fields have been applied:

```lisp
;; The first version; step 10 replaces it.
(defmethod render ((self reading-list))
  (h:h1 () "Reading list")
  (h:ul (:class "books")
    (dolist (book (books self))
      (h:li ()
        (h:strong () (h:text (book-title book)))
        (when (book-author book) (h:text (format nil " by ~A" (book-author book)))))))
  (h:form ()
    (h:text-input (:id "new-title" :value (new-title self) :placeholder "Add a title" :label "Title to add"
                 :callback (lambda (v) (setf (new-title self) v))))
    (h:submit-button (:callback (lambda () (add-quickly self))) "Add")))
```

`:label` gives the field an accessible name, for screen readers, where there's no visible label. Register the list and open <http://127.0.0.1:8080/tutorial/reading-list>:

```lisp
(register-application "/tutorial/reading-list" 'reading-list :title "Reading list")
```

Type a title and click Add. That's the whole story for forms: no field names to invent, no request parsing, and no redirect-after-post to remember. Littoral redirects after every action anyway, so reloading never adds a book twice.

## 4. Components inside components

Steps 4 to 9 write the parts of the finished list, and step 10 puts them together. Until then, /tutorial/reading-list keeps showing the first version.

Each book on the finished list is drawn by a component of its own, a `book-row`:

```lisp
(defclass book-row (component updatable)
  ((book :initarg :book :reader row-book)
   (owner :initarg :owner :reader row-list))
  (:documentation "One book on the list, with its controls."))

(defmethod updatable-wrapper ((self book-row))
  ;; The row is written inside an <li>, which AJAX replaces as a whole.
  (values "li" (list :class (when (book-finished-p (row-book self)) "finished"))))

(defmethod render ((self book-row))
  (let ((book (row-book self)))
    ;; Step 8: ticking the box updates this row in place.
    (h:checkbox (:value (book-finished-p book)
               :label (format nil "Finished ~A" (book-title book))
               :callback (lambda (finished) (setf (book-finished-p book) finished))
               :on-change (ajax :callback (lambda () (book-changed book)) :update self)))
    (h:text " ")
    (h:strong () (h:text (book-title book)))
    (when (book-author book) (h:text (format nil " by ~A" (book-author book))))
    (h:text " ")
    (h:anchor (:callback (lambda () (edit-book (row-list self) book))) "edit")
    (h:text " ")
    (h:anchor (:callback (lambda () (remove-book (row-list self) book))) "remove")))
```

The row's checkbox and its two links call `book-changed`, `edit-book` and `remove-book`, which steps 9, 6 and 5 write.

Because `book-row` is `updatable`, littoral writes it inside an element carrying its id, so that AJAX can replace it (step 8). That element is normally a `div`. Here `updatable-wrapper` makes it the row's `li`, so the list stays a proper list for screen readers.

The rows are drawn by a `shelf`, the part of the page that lists the books. `row-for` makes each book's row the first time it's needed, and the list keeps it:

```lisp
(defclass shelf (component updatable)
  ((owner :initarg :owner :reader shelf-list))
  (:documentation "The books that match the search."))

(defun row-for (list book)
  "The BOOK-ROW showing BOOK, made once and kept."
  (or (gethash book (rows list))
      (setf (gethash book (rows list)) (make-instance 'book-row :book book :owner list))))

(defmethod children ((self shelf))
  (mapcar (lambda (book) (row-for (shelf-list self) book)) (matching-books (shelf-list self))))

(defmethod render ((self shelf))
  (let ((books (matching-books (shelf-list self))))
    (if books
        (h:ul (:class "books")
          (dolist (book books)
            (render-component (row-for (shelf-list self) book))))
        (h:p () (h:em () "Nothing matches.")))))
```

A parent draws a child with `render-component`. It must not call the child's `render` directly. The parent also lists its children in a `children` method, so that littoral can find them for backtracking, AJAX and the development tools. `matching-books` (step 8) gives the books that match the search box, which is all of them until you search.

When you paste these, SBCL warns that some of the functions they call, such as `remove-book` and `rows`, are undefined. That's expected: steps 5 to 10 define them.

## 5. Call and answer

Removing a book asks for confirmation first. **`show`** puts another component, here a ready-made `confirm-dialog`, in place of this one until it **answers**. The answer is passed to `:on-answer`:

```lisp
(defun remove-book (list book)
  "Ask, then take BOOK off LIST."
  (show list (make-instance 'confirm-dialog
                            :message (format nil "Remove ~A?" (book-title book)))
        :on-answer (lambda (yes)
                     (when yes
                       (setf (books list) (remove book (books list)))))))
```

On the finished list, clicking remove replaces the list with the dialog until the visitor chooses Yes or No, and then the list comes back. The back button follows along too: go back to the dialog's page and you'll see the dialog again. Writing your own dialog is just writing a component that calls `(answer self value)`.

## 6. Descriptions

Writing an edit form for every model gets tedious. Instead, describe the model once:

```lisp
(define-description book
  ((title :required t :max-length 100)
   (author :max-length 60)
   (finished :type :boolean :label "Finished")))
```

`make-editor` builds a validating form from the description. It writes to the book when the visitor clicks Save, and leaves it alone on Cancel. Saving with the title left blank shows "Title is required." instead:

```lisp
(defun edit-book (list book)
  "Edit BOOK in place of LIST."
  (show list (make-editor book :title "Edit book")))
```

The same description can give you a read-only `make-viewer`, `description-columns` for a sortable `report` table, and `validate`. Field kinds include `:string`, `:text`, `:email`, `:url`, `:integer`, `:boolean`, `:choice` and `:date`.

## 7. A task

Sometimes a job takes several screens in a row, like a wizard. A **task** writes that sequence as straight-line code. Each `call` (and `request-input` and `confirm`, which are calls too) seems to wait until the component answers:

```lisp
(defclass add-book-task (task) ()
  (:documentation "Ask for a book one question at a time."))

(define-flow add-book-task (self)
  (let ((title (request-input self "What is the book called?")))
    (unless (string= (string-trim " " title) "")
      (let ((author (request-input self "Who wrote it? (leave blank if you don't know)")))
        (when (confirm self (format nil "Add ~A to the list?" title))
          (make-instance 'book :title (string-trim " " title)
                               :author (let ((a (string-trim " " author)))
                                         (if (string= a "") nil a))))))))
```

When the flow ends, the task answers the flow's value: the new book, or NIL if the title was blank or the visitor said No. The list shows the task and adds what it answers:

```lisp
(defun add-with-questions (list)
  "Run the add-a-book task, adding what it answers."
  (show list (make-instance 'add-book-task)
        :on-answer (lambda (book)
                     (when book
                       (setf (books list) (append (books list) (list book)))))))
```

Under the hood, `define-flow` rewrites the body in continuation-passing style, so each call suspends the flow until the answer arrives. The back button works inside the flow too: go back to the second question, give another author, and the book is added with that one instead. One caution: a flow can't put a `call` inside `unwind-protect`, `catch` or `handler-case`.

## 8. AJAX

Two parts of the finished page update without reloading it. The checkbox on each row updates just that row (see step 4). `book-row` mixes in **`updatable`**, and its checkbox has an `:on-change (ajax …)` that runs a callback and re-renders the row.

The search box filters the list as you type. In step 10, the list draws it as an `h:text-input` with `:on-input (ajax-update (shelf self))`. On each keystroke, the field's callback stores the query, and the shelf is drawn again and swapped into the page. The shelf draws only the books that match:

```lisp
(defun matching-books (list)
  "LIST's books that match its search."
  (let ((q (string-trim " " (query list))))
    (remove-if-not (lambda (book)
                     (or (string= q "")
                         (search q (book-title book) :test #'char-equal)
                         (and (book-author book) (search q (book-author book) :test #'char-equal))))
                   (books list))))
```

SBCL warns that `query` is undefined: it reads the search box's text, and comes with the finished class in step 10. The JavaScript involved is littoral's own, `static/littoral.js`, with no dependencies.

## 9. Server push

When anyone finishes a book, every open reading list should hear about it straight away. A component **subscribes** to a channel, and any code can **publish** that channel:

```lisp
(defvar *finished-channel* (make-channel "finished books")
  "Published whenever anyone finishes a book.")

(defvar *recently-finished* '()
  "The last few books anyone finished, newest first, shared by every session.")

(defun book-changed (book)
  "Note BOOK's new state; tell everyone when it was just finished."
  (when (book-finished-p book)
    (push (book-title book) *recently-finished*)
    (setf *recently-finished* (subseq *recently-finished* 0 (min 5 (length *recently-finished*))))
    (publish *finished-channel*)))

(defclass recently-finished (component updatable) ()
  (:documentation "What everyone has finished lately, kept current by push."))

(defmethod subscriptions ((self recently-finished))
  (list *finished-channel*))

(defmethod render ((self recently-finished))
  (when *recently-finished*
    (h:p (:class "recent") "Recently finished by readers here: "
      (h:text (format nil "~{~A~^; ~}" *recently-finished*)))))
```

Pages showing a subscriber open a server-sent event stream. After `publish`, littoral renders the subscribers on each of those pages and swaps them in. Note that `*recently-finished*` is shared by every session and kept out of backtracking: going back shows an older list, never an older history of what people read.

## 10. The whole list

Now the list gets its finished class, with the search query, the rows, the shelf and the recently-finished line as well as the books. The shelf needs to know its list, so it's made once the list exists. The rows are a cache, which grows as books are added and is never undone by the back button, so `shared-state-slots` says so; otherwise, in development mode, Littoral would warn that the table is changed in place:

```lisp
(defclass reading-list (component)
  ((books :initform (list (make-instance 'book :title "Structure and Interpretation of Computer Programs"
                                               :author "Abelson and Sussman")
                          (make-instance 'book :title "Paradigms of Artificial Intelligence Programming"
                                               :author "Peter Norvig"))
          :accessor books)
   (new-title :initform "" :accessor new-title)
   (query :initform "" :accessor query)
   (rows :initform (make-hash-table :test 'eq) :reader rows)
   (shelf :reader shelf)
   (ticker :initform (make-instance 'recently-finished) :reader ticker))
  (:documentation "The reading list."))

(defmethod initialize-instance :after ((self reading-list) &key)
  (setf (slot-value self 'shelf) (make-instance 'shelf :owner self)))

(defmethod shared-state-slots ((self reading-list))
  '(rows))
```

The `states` method from step 3 still applies. The list's children are the recently-finished line and the shelf. Its `render` draws them, with the search box, the form from step 3, and a link that starts the task. A `style` method gives the page some CSS:

```lisp
(defmethod children ((self reading-list))
  (list (ticker self) (shelf self)))

(defmethod render ((self reading-list))
  (h:h1 () "Reading list")
  (render-component (ticker self))
  (h:p (:class "search")
    (h:text-input (:id "query" :value (query self) :placeholder "Search" :label "Search"
                 :callback (lambda (v) (setf (query self) v))
                 :on-input (ajax-update (shelf self)))))
  (render-component (shelf self))
  (h:form ()
    (h:text-input (:id "new-title" :value (new-title self) :placeholder "Add a title" :label "Title to add"
                 :callback (lambda (v) (setf (new-title self) v))))
    (h:submit-button (:callback (lambda () (add-quickly self))) "Add"))
  (h:p () (h:anchor (:callback (lambda () (add-with-questions self))) "Add a book, step by step")))

(defmethod style ((self reading-list))
  ".books { list-style: none; padding: 0; } .books li { margin: .3rem 0; }
.books li.finished strong { text-decoration: line-through; color: var(--lt-muted); }
.recent { font-size: .9rem; color: var(--lt-muted); }")
```

Open <http://127.0.0.1:8080/tutorial/reading-list> again. That starts a new session, whose list is made by the new class; a page left open from step 3 can't show the new version, since its list has no shelf. Then try each step's part:

- **Search** (step 8): type "norvig" in the search box, and only Norvig's book is left.
- **Remove** (step 5): click remove, then No, and the book stays; remove, then Yes, and it goes.
- **Edit** (step 6): click edit, give an author, and click Save.
- **Add a book, step by step** (step 7): answer each question and click OK, then Yes.
- **Finish a book** (steps 8 and 9): open the list in a second browser window, then tick a book in the first. Its row is struck through, and both windows say "Recently finished by readers here".

## 11. Shipping it

The finished file registers all three applications with one function:

```lisp
(defun register (&key (mode :development))
  "Serve the tutorial's applications under /tutorial."
  (register-application "/tutorial/hello" 'hello :mode mode)
  (register-application "/tutorial/counter" 'counter :mode mode)
  (register-application "/tutorial/reading-list" 'reading-list :mode mode :title "Reading list"))
```

In `:development` mode, the default, each page ends with a toolbar. **Halos** frame every component with buttons to inspect and change its slots, see its HTML, and read its source (and edit it in Emacs, when SLIME is connected). **Profile** times each component's rendering. Turn halos on and try them on the reading list.

For production:

- Register applications with `:mode :deployment`.
- Keep `/config` local, as it is unless you give it credentials with `configure-admin`.
- Read the README's [Security](index.md#security) section, on request limits and running behind a proxy, and [the deployment guide](deployment.md), on executables, services, TLS and several processes.

## 12. Testing it

`littoral/test` is a fake browser. It calls your application in-process, with no sockets and no real browser, so tests are fast. Load it, and FiveAM to run the tests:

```lisp
(asdf:load-system :fiveam)
(asdf:load-system :littoral/test)
```

Tests go in a package of their own, which uses `littoral.test` for the browser. They name the reading list's classes with its package prefix, as `reading-list:reading-list`:

```lisp
(defpackage #:reading-list/tests
  (:use #:cl #:fiveam #:littoral #:littoral.test)
  (:documentation "Tests of the tutorial's reading list."))

(in-package #:reading-list/tests)

(def-suite reading-list-tests :description "The reading list, used as a visitor uses it.")
(in-suite reading-list-tests)
```

Each test registers the application it needs with `with-fresh-applications`, which keeps those registrations to the test. `:mode :deployment` leaves the development toolbar off the page. Then a browser visits pages, fills in fields by their DOM id, presses buttons and clicks links by their text, and checks what the page says:

```lisp
(test adding-a-book
  (with-fresh-applications (("/tutorial/reading-list" 'reading-list:reading-list :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/tutorial/reading-list")
      (fill-in b "new-title" "On Lisp")
      (press b "Add")
      (is (has-text-p b "On Lisp")))))

(test removing-asks-first
  (with-fresh-applications (("/tutorial/reading-list" 'reading-list:reading-list :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/tutorial/reading-list")
      (click-nth b "remove" 0)
      (is (has-text-p b "Remove Structure and Interpretation of Computer Programs?"))
      (press b "No")
      (is (= 2 (length (find-links b "remove"))))
      (click-nth b "remove" 0)
      (press b "Yes")
      (is (= 1 (length (find-links b "remove"))))
      (is (has-text-p b "Paradigms of Artificial Intelligence Programming")))))
```

`click` follows the first link whose text contains its argument. `click-nth` picks among the links whose text is exactly its argument, counting from 0, and `find-links` lists them; counting the remove links shows a book has gone even when the recently-finished line still names it. `back-to` returns to an earlier page, as the back button does, and `body-text` gives the page's text as a reader sees it. This test checks step 2's claim:

```lisp
(test the-back-button
  (with-fresh-applications (("/tutorial/counter" 'reading-list:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/tutorial/counter")
      (click b "++")
      (let ((one (browser-url b)))
        (click b "++")
        (click b "++")
        (back-to b one)
        (click b "++")
        (is (string= "2 ++ --" (body-text b)))))))
```

Run the suite:

```lisp
(run! 'reading-list-tests)
```

It reports 6 checks, all passing, and returns T. The fake browser can also make AJAX requests and open event streams (`ajax-request`, `open-stream`); the README's [Testing your application](index.md#testing-your-application) section has more.

## 13. Keeping the books in a database

The reading list forgets everything when Lisp stops. `littoral/db` keeps described objects in SQL, here SQLite. Load it and the SQLite driver:

```lisp
(asdf:load-system :littoral/db)
(asdf:load-system :dbd-sqlite3)
```

Loading them, SBCL prints warnings that cl-dbi, the database library underneath, redefines some types as classes. They're harmless.

The stored list is a new application, in a package of its own:

```lisp
(defpackage #:my-books
  (:use #:cl #:littoral)
  (:local-nicknames (#:h #:littoral.html))
  (:export #:my-books #:open-database #:register)
  (:documentation "The tutorial's reading list, kept in a database, one list per reader."))

(in-package #:my-books)
```

A stored book is a `persistent` object, which gives it an id and a version. Its description says what to store, and `define-table` keeps it in a table called books, one column per field. The `reader` field will say whose list a book is on (step 14). It's `:hidden`, so editors don't show it.

```lisp
(defclass stored-book (littoral.db:persistent)
  ((title :initarg :title :initform nil :accessor book-title)
   (author :initarg :author :initform nil :accessor book-author)
   (reader :initarg :reader :initform nil :accessor book-reader))
  (:documentation "A book on someone's list, kept in the books table."))

(define-description stored-book
  ((title :required t :max-length 100)
   (author :max-length 60)
   (reader :type :integer :hidden t)))

(littoral.db:define-table stored-book :name "books")
```

`connect-database` says where the data lives, and `create-table` makes the table unless it exists:

```lisp
;; The first version; step 14 replaces it.
(defun open-database (file)
  "Keep the books in the SQLite database FILE."
  (littoral.db:connect-database :sqlite3 :database-name file)
  (littoral.db:create-table 'stored-book))
```

```lisp
(open-database "my-books.db")
```

That makes my-books.db in the directory SBCL started in. `create-table` is fine for trying things out; once the data matters, keep the schema in migration files instead (see the README's [Schema migrations](index.md#schema-migrations)).

The page's component holds only the title being typed. The books stay in the database, and the page reads them each time it's drawn. It has no `states` method, so going back shows the books as they are now, not as they were.

```lisp
;; The first version; step 14 replaces it.
(defclass my-books (component)
  ((new-title :initform "" :accessor new-title))
  (:documentation "The books in the database, and a form to add one."))
```

`db-select` reads objects, and `db-save` writes one, inserting it if it's new:

```lisp
;; The first versions; step 14 replaces them.
(defun shelf-books ()
  "Every book in the database, by title."
  (littoral.db:db-select 'stored-book :order-by "title"))

(defun add-stored-book (list)
  "Save the typed title as a new book."
  (let ((title (string-trim " " (new-title list))))
    (unless (string= title "")
      (littoral.db:db-save (make-instance 'stored-book :title title))
      (setf (new-title list) ""))))
```

To edit a book, read a fresh copy with `db-reload`, give it to the editor, and save what the editor answers. Saving checks the row's version, so if the book changed since the copy was read (in another window, say), `db-save` signals `stale-object` instead of overwriting the change. `db-delete` deletes a row:

```lisp
(defun edit-stored-book (list book)
  "Edit a fresh copy of BOOK in place of LIST; save it if the reader does."
  (show list (make-editor (littoral.db:db-reload book) :title (translate "Edit book"))
        :on-answer (lambda (edited)
                     (when edited
                       (littoral.db:db-save edited)))))

(defun remove-stored-book (list book)
  "Ask, then delete BOOK."
  (show list (make-instance 'confirm-dialog
                            :message (translate "Remove ~A?" (book-title book)))
        :on-answer (lambda (yes)
                     (when yes
                       (littoral.db:db-delete (littoral.db:db-reload book))))))
```

The text a reader sees goes through `translate`, ready for step 15. Until there are translations it returns its argument, used as a `format` control string when more arguments follow. Inside a tag's body, a `(translate …)` form is written as text, like a literal string. Here is the page:

```lisp
(defmethod render ((self my-books))
  (h:h1 () (translate "My books"))
  (let ((books (shelf-books)))
    (if books
        (h:ul (:class "books")
          (dolist (book books)
            (h:li ()
              (h:strong () (h:text (book-title book)))
              (when (book-author book)
                (h:text " ")
                (h:text (translate "by ~A" (book-author book))))
              (h:text " ")
              (h:anchor (:callback (lambda () (edit-stored-book self book))) (translate "edit"))
              (h:text " ")
              (h:anchor (:callback (lambda () (remove-stored-book self book))) (translate "remove")))))
        (h:p () (h:em () (translate "No books yet.")))))
  (h:form ()
    (h:text-input (:id "new-title" :value (new-title self)
                 :placeholder (translate "Add a title") :label (translate "Title to add")
                 :callback (lambda (v) (setf (new-title self) v))))
    (h:submit-button (:callback (lambda () (add-stored-book self))) (translate "Add"))))
```

```lisp
(register-application "/tutorial/my-books" 'my-books :title "My books")
```

Open <http://127.0.0.1:8080/tutorial/my-books>. It says "No books yet." Add a book, then edit it and give it an author. Open the page in a second browser: the same book is there, because it's in the database, not in a session. The REPL can read the titles too:

```lisp
(mapcar #'book-title (littoral.db:db-select 'stored-book))
```

## 14. Signing in

Everyone shares that one list. `littoral/auth` adds users who sign in, so that each reader can have a list of their own:

```lisp
(asdf:load-system :littoral/auth)
```

Users and their sign-ins live in the database too. `create-auth-tables` makes those tables, and like `create-table` it's safe to run again:

```lisp
(defun open-database (file)
  "Keep the books, and the users, in the SQLite database FILE."
  (littoral.db:connect-database :sqlite3 :database-name file)
  (littoral.db:create-table 'stored-book)
  (littoral.auth:create-auth-tables))
```

Open the database again, and add two readers. `add-user` stores a hash of the password, never the password itself. It signals an error if the name is taken, so run it once:

```lisp
(open-database "my-books.db")
(littoral.auth:add-user "ada" "ada@example.org" "a long passphrase")
(littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
```

Two mixins make the page need a sign-in. `restricted` shows a sign-in prompt in a component's place until someone is signed in. `auth-root`, for an application's root, restores a sign-in kept from an earlier session and answers password-reset links:

```lisp
(defclass my-books (littoral.auth:auth-root littoral.auth:restricted component)
  ((new-title :initform "" :accessor new-title))
  (:documentation "The signed-in reader's books, and a form to add one."))
```

`current-user` is the signed-in user, and `user-id` their id. The list shows only the reader's own books, and a new book goes on their list:

```lisp
(defun shelf-books ()
  "The signed-in reader's books, by title."
  (littoral.db:db-select 'stored-book :where "reader = ?"
                                      :params (list (littoral.auth:user-id (littoral.auth:current-user)))
                                      :order-by "title"))

(defun add-stored-book (list)
  "Save the typed title as a new book on the signed-in reader's list."
  (let ((title (string-trim " " (new-title list))))
    (unless (string= title "")
      (littoral.db:db-save (make-instance 'stored-book
                                          :title title
                                          :reader (littoral.auth:user-id (littoral.auth:current-user))))
      (setf (new-title list) ""))))
```

The page should say who is signed in, with a link to sign out. A `:before` method on `render` draws that above the list, leaving the `render` method from step 13 as it is:

```lisp
(defmethod render :before ((self my-books))
  (h:p (:class "who")
    (h:text (translate "Signed in as ~A." (littoral.auth:user-name (littoral.auth:current-user))))
    (h:text " ")
    (littoral.auth:sign-out-link)))
```

Reload <http://127.0.0.1:8080/tutorial/my-books>. It now says "Please sign in to see this." Click Sign in, and sign in as ada with her password. The page says "Signed in as ada." and "No books yet.": the books from step 13 have no reader, so they're on nobody's list. Add one, then sign out and sign in as bob. His list is empty.

Open the page in a new tab, and you're still signed in. The sign-in is kept in the database, and the browser holds a cookie for it. Tick "Keep me signed in" on the sign-in form and it lasts across browser restarts, for 30 days. The README's [Users and signing in](index.md#users-and-signing-in) covers roles, password reset, second factors and signing in with other sites.

## 15. Another language

All of the page's text already goes through `translate`. A catalogue gives the French:

```lisp
(define-translations "fr"
  ("My books" "Mes livres")
  ("by ~A" "de ~A")
  ("edit" "modifier")
  ("remove" "supprimer")
  ("No books yet." "Pas encore de livres.")
  ("Add a title" "Ajouter un titre")
  ("Title to add" "Titre à ajouter")
  ("Add" "Ajouter")
  ("Edit book" "Modifier le livre")
  ("Remove ~A?" "Supprimer ~A ?")
  ("Title" "Titre")
  ("Author" "Auteur")
  ("Signed in as ~A." "Connecté en tant que ~A.")
  ("Sign out" "Se déconnecter"))
```

"Title" and "Author" are the editor's labels: field labels go through `translate` too. Littoral's own text, such as the sign-in form and the dialog's Yes and No, comes translated into French, German and Spanish already.

Each session has a language. `:languages` lists the languages an application offers besides English, and a new session takes the one the browser asks for first. `:language` sets an application's language whatever the browser asks, so this serves the same list in French at a second path:

```lisp
(register-application "/tutorial/my-books" 'my-books :title "My books" :languages '("fr"))
(register-application "/tutorial/mes-livres" 'my-books :title "Mes livres" :language "fr")
```

Open <http://127.0.0.1:8080/tutorial/mes-livres>: it says "Connectez-vous pour voir ceci." Sign in (Se connecter) as ada, and her list is there, in French. A browser set to prefer French gets the same at /tutorial/my-books. In a test, the fake browser asks for French with `(make-instance 'browser :headers '(("accept-language" . "fr")))`.

The finished file's `register` opens the database and serves both paths in one call, `(my-books:register)`:

```lisp
(defun register (&key (file "my-books.db") (mode :development))
  "Open the database FILE, then serve the list at /tutorial/my-books, in
English or French as the browser asks, and in French at /tutorial/mes-livres."
  (open-database file)
  (register-application "/tutorial/my-books" 'my-books :mode mode :title "My books" :languages '("fr"))
  (register-application "/tutorial/mes-livres" 'my-books :mode mode :title "Mes livres" :language "fr"))
```

## Where next

- The examples under `/examples` (run `make run`), especially the sushi store, the wiki and the chat.
- `apps/tracker`, a complete issue tracker built the same way.
- `make new NAME=…` starts a project of your own, with tests; `TEMPLATE=app` adds a database, signing in and an admin.
- [The API reference](API.md).
