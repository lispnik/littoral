## Running the examples

The examples are tested: the suite runs every one on its own and checks each result shown after `;; ⇒`, which is what the REPL prints. To try them, load Littoral and its fake browser, and make a package that uses the same packages they do:

```lisp
(asdf:load-system :littoral/test)
(defpackage #:try-littoral (:use #:cl #:littoral #:littoral.html #:littoral.test))
(in-package #:try-littoral)
```

Then paste any example. Most render pages in the fake browser (`visit`, `click`, `page-text`; see `littoral.test`), so they need no server. Examples for another package write its names in full, such as `littoral.db:db-save`, and need its system loaded first, such as `(asdf:load-system :littoral/db)`; each package's section says which.
