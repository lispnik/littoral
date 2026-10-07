# Littoral tutorial: a reading list

This tutorial builds a small application, a reading list, one idea at a time. By the end it uses components, callbacks, the back button, forms, components inside components, call and answer, descriptions, a task, AJAX and server push. Every piece of code here comes from [`docs/tutorial/reading-list.lisp`](tutorial/reading-list.lisp), which the test suite runs. To follow along, either type the pieces in as you go or load that file:

```lisp
(asdf:load-system :littoral/tutorial)
(reading-list:register)
(littoral:start :port 8080)
```

Then open <http://127.0.0.1:8080/tutorial/hello>. This assumes you've cloned littoral and run `ocicl install` (see the README).

## 1. A component

A littoral application is a tree of **components**. A component is a CLOS object that remembers its own state and knows how to draw itself. To draw itself it writes HTML in its `render` method, using macros named after HTML tags.

```lisp
(defpackage #:reading-list
  (:use #:cl #:littoral #:littoral.html)
  (:export #:reading-list #:hello #:counter #:register)
  (:documentation "The application the Littoral tutorial builds."))

(defclass hello (component) ()
  (:documentation "The smallest application."))

(defmethod render ((self hello))
  (h1 () "Hello, world"))
```

`littoral.html` holds the tags (`h1`, `div`, `p` and the rest) and `littoral` holds everything else; a package normally uses both. A tag's first argument is its attributes, written as a plist like `(:class "intro")`. You can leave it out, or write `()`. A literal string in a tag's body is written as escaped text.

To serve the component, register it at a path:

```lisp
(register-application "/tutorial/hello" 'hello)
(start :port 8080)
```

There are no routes, templates or request handlers to write. Each visitor gets a **session** with their own `hello` instance.

## 2. Callbacks and the back button

Links don't point at URLs you design. They carry closures, called **callbacks**:

```lisp
(defclass counter (component)
  ((count :initform 0 :accessor count-of))
  (:documentation "A number with links that change it."))

(defmethod states ((self counter))
  (list self))

(defmethod render ((self counter))
  (h1 () (text (count-of self)))
  (anchor (:callback (lambda () (incf (count-of self)))) "++")
  (text " ")
  (anchor (:callback (lambda () (decf (count-of self)))) "--"))
```

`(anchor (:callback …) "++")` writes a link. Clicking it runs the closure, which changes this visitor's own counter, and then the page is drawn again. Use `text` to write a value that isn't a literal string; it escapes the value too.

The `states` method names the objects whose slots should **backtrack**. Click ++ three times, press the browser's back button twice, then click ++. You'll see 2, not 4. Littoral saves a snapshot of those objects for every page it shows, and acting on an old page first restores that page's state. Leave `states` out and the counter would act on its latest value instead.

## 3. A model and a form

Next, the reading list itself. A book is ordinary data:

```lisp
(defclass book ()
  ((title :initarg :title :initform nil :accessor book-title)
   (author :initarg :author :initform nil :accessor book-author)
   (finished :initarg :finished :initform nil :accessor book-finished-p))
  (:documentation "A book on the list."))
```

Forms work the same way as links. A field's `:callback` receives what was typed, and a button's `:callback` runs after all the fields have been applied:

```lisp
(form ()
  (text-input (:id "new-title" :value (new-title self) :placeholder "Add a title" :label "Title to add"
               :callback (lambda (v) (setf (new-title self) v))))
  (submit-button (:callback (lambda () (add-quickly self))) "Add"))
```

```lisp
(defun add-quickly (list)
  "Add the typed title to LIST."
  (let ((title (string-trim " " (new-title list))))
    (unless (string= title "")
      (setf (books list) (append (books list) (list (make-instance 'book :title title)))
            (new-title list) ""))))
```

That's the whole story for forms: no field names to invent, no request parsing, and no redirect-after-post to remember. Littoral redirects after every action anyway, so reloading never adds a book twice.

## 4. Components inside components

Each book on the list is drawn by a component of its own, a `book-row`:

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
    (checkbox (:value (book-finished-p book)
               :label (format nil "Finished ~A" (book-title book))
               :callback (lambda (finished) (setf (book-finished-p book) finished))
               :on-change (ajax :callback (lambda () (book-changed book)) :update self)))
    (text " ")
    (strong () (text (book-title book)))
    (when (book-author book) (text (format nil " by ~A" (book-author book))))
    (text " ")
    (anchor (:callback (lambda () (edit-book (row-list self) book))) "edit")
    (text " ")
    (anchor (:callback (lambda () (remove-book (row-list self) book))) "remove")))
```

Because `book-row` is `updatable`, littoral writes it inside an element carrying its id, so that AJAX can replace it (step 8). That element is normally a `div`. Here `updatable-wrapper` makes it the row's `li`, so the list stays a proper list for screen readers. `:label` on the checkbox gives it an accessible name where there's no visible label.

A parent draws a child with `render-component`. It must not call the child's `render` directly. The parent also lists its children in a `children` method, so that littoral can find them for backtracking, AJAX and the development tools. The list keeps one row per book:

```lisp
(defun row-for (list book)
  "The BOOK-ROW showing BOOK, made once and kept."
  (or (gethash book (rows list))
      (setf (gethash book (rows list)) (make-instance 'book-row :book book :owner list))))

(defmethod children ((self shelf))
  (mapcar (lambda (book) (row-for (shelf-list self) book)) (matching-books (shelf-list self))))

(defmethod render ((self shelf))
  (let ((books (matching-books (shelf-list self))))
    (if books
        (ul (:class "books")
          (dolist (book books)
            (render-component (row-for (shelf-list self) book))))
        (p () (em () "Nothing matches.")))))
```

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

The list is replaced by the dialog until the visitor chooses Yes or No, then it comes back. The back button follows along too: go back to the dialog's page and you'll see the dialog again. Writing your own dialog is just writing a component that calls `(answer self value)`.

## 6. Descriptions

Writing an edit form for every model gets tedious. Instead, describe the model once:

```lisp
(define-description book
  ((title :required t :max-length 100)
   (author :max-length 60)
   (finished :type :boolean :label "Finished")))
```

`make-editor` builds a validating form from the description. It writes to the book when the visitor clicks Save, and leaves it alone on Cancel:

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

```lisp
(defun add-with-questions (list)
  "Run the add-a-book task, adding what it answers."
  (show list (make-instance 'add-book-task)
        :on-answer (lambda (book)
                     (when book
                       (setf (books list) (append (books list) (list book)))))))
```

Under the hood, `define-flow` rewrites the body in continuation-passing style, so each call suspends the flow until the answer arrives. The back button works inside the flow too. One caution: a flow can't put a `call` inside `unwind-protect` or `handler-case`.

## 8. AJAX

Two parts of the page update without reloading it. The checkbox on each row updates just that row (see step 4). `book-row` mixes in **`updatable`**, and its checkbox has an `:on-change (ajax …)` that runs a callback and re-renders the row.

The search box filters the list as you type:

```lisp
(text-input (:id "query" :value (query self) :placeholder "Search" :label "Search"
             :callback (lambda (v) (setf (query self) v))
             :on-input (ajax-update (shelf self))))
```

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

On each keystroke, the field's callback stores the query and the `shelf` component is drawn again and swapped into the page. The JavaScript involved is littoral's own, about 200 lines, with no dependencies.

## 9. Server push

When anyone finishes a book, every open reading list should hear about it straight away. A component **subscribes** to a channel, and any code can **publish** that channel:

```lisp
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
    (p (:class "recent") "Recently finished by readers here: "
      (text (format nil "~{~A~^; ~}" *recently-finished*)))))
```

Pages showing a subscriber open a server-sent event stream. After `publish`, littoral renders the subscribers on each of those pages and swaps them in. Note that `*recently-finished*` is shared by every session and kept out of backtracking: going back shows an older list, never an older history of what people read.

## 10. Shipping it

```lisp
(defun register (&key (mode :development))
  "Serve the tutorial's applications under /tutorial."
  (register-application "/tutorial/hello" 'hello :mode mode)
  (register-application "/tutorial/counter" 'counter :mode mode)
  (register-application "/tutorial/reading-list" 'reading-list :mode mode :title "Reading list"))
```

In `:development` mode, each page ends with a toolbar. **Halos** frame every component with buttons to inspect its slots, see its HTML, or read (and edit) its source. **Profile** times each component's rendering. Turn halos on and try them on the reading list.

For production:

- Register applications with `:mode :deployment`.
- Keep `/config` local, or give it credentials with `configure-admin`.
- Read the README's Security and Deployment sections: request limits, cookie sessions, running behind a proxy, and several processes.

## Where next

- The examples under `/examples` (run `make run`), especially the sushi store, the wiki and the chat.
- `apps/tracker`, a complete issue tracker built the same way.
- [The API reference](API.md).
