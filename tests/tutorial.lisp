;;;; tutorial.lisp — the tutorial's applications work as docs/tutorial.md says
;;;;
;;;; The CHECK- functions below follow the text step by step, asserting
;;;; what it says a reader will see.  They use only the tutorial's paths,
;;;; so they run twice: against the finished files in docs/tutorial/
;;;; (READING-LIST:REGISTER, MY-BOOKS:REGISTER), and against the
;;;; applications made by pasting the tutorial's blocks, in order, into
;;;; fresh packages (TUTORIAL-PASTED-IN-ORDER).

(in-package #:littoral/tests)

(def-suite tutorial :in littoral)
(in-suite tutorial)

;;; Reading the tutorial

(defun tutorial-path (name)
  (merge-pathnames name (asdf:system-source-directory :littoral)))

(defun tutorial-blocks ()
  "The ```lisp blocks of docs/tutorial.md in order, each as (STEP . TEXT):
STEP is the number of the \"## N.\" heading above it, 0 before the first."
  (let ((step 0) (blocks '()) (lines nil))
    (with-open-file (in (tutorial-path "docs/tutorial.md") :external-format :utf-8)
      (loop for line = (read-line in nil)
            while line
            do (cond ((and lines (string= line "```"))
                      (push (cons step (format nil "~{~A~%~}" (rest (reverse lines)))) blocks)
                      (setf lines nil))
                     (lines (push line lines))
                     ((string= line "```lisp") (setf lines (list line)))
                     ((cl-ppcre:scan "^## \\d+\\." line)
                      (setf step (parse-integer line :start 3 :junk-allowed t))))))
    (nreverse blocks)))

(defun tutorial-source-files ()
  "The Lisp files of docs/tutorial/."
  (directory (tutorial-path "docs/tutorial/*.lisp")))

(defun finished-code-block-p (text)
  "True for the block that loads the finished files instead of pasting."
  (search "(asdf:load-system :littoral/tutorial)" text))

(defun stepping-stone-p (text)
  "True for a block the text marks as replaced later: its first line is a
comment saying \"step N replaces it\" (or \"them\")."
  (cl-ppcre:scan "\\A;;[^\\n]*\\bstep \\d+ replaces (it|them)\\b" text))

(defun definitions-p (text)
  "True when TEXT has a top-level definition, rather than only things to run."
  (cl-ppcre:scan "(?m)^\\((?:[\\w.]+:)?(?:def|in-package)" text))

(defun squeeze (string)
  "STRING with every run of whitespace made one space."
  (string-trim " " (cl-ppcre:regex-replace-all "\\s+" string " ")))

(defun top-level-form-texts (text)
  "The text of each top-level form in TEXT, comments between them left out."
  (let ((forms '()) (position 0) (length (length text)))
    (loop
      ;; Skip whitespace and whole-line comments.
      (loop while (< position length)
            do (let ((char (char text position)))
                 (cond ((member char '(#\Space #\Tab #\Newline #\Return)) (incf position))
                       ((char= char #\;) (setf position (or (position #\Newline text :start position) length)))
                       (t (return)))))
      (when (>= position length) (return (nreverse forms)))
      (let ((end (nth-value 1 (let ((*read-suppress* t)) (read-from-string text t nil :start position)))))
        (push (subseq text position end) forms)
        (setf position end)))))

(test tutorial-text-matches-the-code
  ;; Each definition in the tutorial is in docs/tutorial/, apart from the
  ;; stepping stones a later step replaces; blocks that only run things
  ;; (start the server, open the database) are left out.
  (let ((code (mapcar (lambda (file) (squeeze (alexandria:read-file-into-string file :external-format :utf-8)))
                      (tutorial-source-files)))
        (blocks (tutorial-blocks)))
    (is (> (length blocks) 40))
    (dolist (block blocks)
      (let ((text (rest block)))
        (when (and (definitions-p text) (not (stepping-stone-p text)) (not (finished-code-block-p text)))
          ;; A block may quote several forms that are apart in the files.
          (dolist (piece (cl-ppcre:split "\\n\\n(?=\\()" text))
            (is (some (lambda (file) (search (squeeze piece) file)) code)
                "Not in docs/tutorial/:~%~A" piece)))))))

(test tutorial-shows-all-the-code
  ;; And each form in docs/tutorial/ is in the tutorial, so a reader who
  ;; pastes the blocks has the whole of each application.
  (let ((shown (squeeze (format nil "~{~A~^ ~}" (mapcar #'rest (tutorial-blocks))))))
    (dolist (file (tutorial-source-files))
      (dolist (form (top-level-form-texts (alexandria:read-file-into-string file :external-format :utf-8)))
        (is (search (squeeze form) shown) "~A: not in docs/tutorial.md:~%~A" (file-namestring file) form)))))

(test tutorial-links-resolve
  ;; Every relative link in the tutorial names a file in docs/, and every
  ;; #anchor one of the README's headings (docs/index.md is the README).
  (let* ((text (alexandria:read-file-into-string (tutorial-path "docs/tutorial.md") :external-format :utf-8))
         (readme (alexandria:read-file-into-string (tutorial-path "README.md") :external-format :utf-8))
         (anchors (let ((anchors '()))
                    (cl-ppcre:do-register-groups (heading) ("(?m)^#+ (.*)$" readme)
                      (push (cl-ppcre:regex-replace-all
                             " " (cl-ppcre:regex-replace-all "[^a-z0-9 -]" (string-downcase heading) "") "-")
                            anchors))
                    anchors)))
    (cl-ppcre:do-register-groups (target) ("\\]\\(([^)]+)\\)" text)
      (unless (cl-ppcre:scan "^https?:" target)
        (let* ((hash (position #\# target))
               (file (subseq target 0 hash))
               (anchor (and hash (subseq target (1+ hash)))))
          (is (probe-file (merge-pathnames file (tutorial-path "docs/"))) "No file for the link ~A" target)
          (when anchor
            (is (string= file "index.md") "~A: anchors are checked only in index.md" target)
            (is (member anchor anchors :test #'string=) "No README heading for ~A" target)))))))

;;; What a reader sees, step by step

(defun shows-p (b text)
  "True when B's page shows TEXT, read as a reader sees it (BODY-TEXT)."
  (search text (body-text b)))


(defun check-hello ()
  "Step 1."
  (let ((b (make-instance 'browser)))
    (visit b "/tutorial/hello")
    (is (= 200 (browser-status b)))
    (is (shows-p b "Hello, world"))))

(defun check-counter ()
  "Step 2: ++ three times, back twice, ++ shows 2, not 4."
  (let ((b (make-instance 'browser)) (pages '()))
    (visit b "/tutorial/counter")
    (is (= 0 (count-shown b)))
    (dotimes (i 3)
      (click b "++")
      (push (browser-url b) pages))
    (is (= 3 (count-shown b)))
    (back-to b (third pages))
    (is (= 1 (count-shown b)))
    (click b "++")
    (is (= 2 (count-shown b)))))

(defun book-count (b)
  "How many books B's page lists."
  (length (cl-ppcre:all-matches-as-strings "<li[ >]" (browser-html b))))

(defun check-first-list ()
  "Step 3: the list, adding a title, and reloading.  Returns the browser."
  (let ((b (make-instance 'browser)))
    (visit b "/tutorial/reading-list")
    (is (shows-p b "Reading list"))
    (is (shows-p b "Structure and Interpretation of Computer Programs by Abelson and Sussman"))
    (is (shows-p b "Paradigms of Artificial Intelligence Programming by Peter Norvig"))
    (is (search "aria-label=\"Title to add\"" (browser-html b)))
    (fill-in b "new-title" "On Lisp")
    (press b "Add")
    (is (shows-p b "On Lisp"))
    (is (= 3 (book-count b)))
    ;; Reloading never adds a book twice.
    (visit b (browser-url b))
    (is (= 3 (book-count b)))
    (is (= 1 (length (cl-ppcre:all-matches-as-strings "On Lisp" (body-text b)))))
    ;; A blank title adds nothing.
    (fill-in b "new-title" "   ")
    (press b "Add")
    (is (= 3 (book-count b)))
    b))

(defun check-removing ()
  "Step 5: remove asks; No keeps the book, Yes removes it; back shows the dialog."
  (let ((b (make-instance 'browser)))
    (visit b "/tutorial/reading-list")
    (click-nth b "remove" 0)
    (is (shows-p b "Remove Structure and Interpretation of Computer Programs?"))
    (is (not (shows-p b "Paradigms")) "The dialog is in the list's place")
    (let ((dialog (browser-url b)))
      (press b "No")
      (is (= 2 (book-count b)))
      (is (shows-p b "Structure and Interpretation"))
      (click-nth b "remove" 0)
      (press b "Yes")
      (is (= 1 (book-count b)))
      (is (shows-p b "Paradigms"))
      (back-to b dialog)
      (is (shows-p b "Remove Structure and Interpretation of Computer Programs?")))))

(defun check-editing ()
  "Step 6: the editor saves, cancels, and refuses a blank title."
  (let ((b (make-instance 'browser)))
    (visit b "/tutorial/reading-list")
    (fill-in b "new-title" "On Lisp")
    (press b "Add")
    (click-nth b "edit" 2)
    (is (shows-p b "Edit book"))
    (fill-in b "author" "Paul Graham")
    (press b "Save")
    (is (shows-p b "On Lisp by Paul Graham"))
    (click-nth b "edit" 2)
    (fill-in b "author" "Nobody")
    (press b "Cancel")
    (is (shows-p b "On Lisp by Paul Graham"))
    (click-nth b "edit" 2)
    (fill-in b "title" "")
    (press b "Save")
    (is (shows-p b "Title is required."))
    (press b "Cancel")
    (is (shows-p b "On Lisp by Paul Graham"))))

(defun check-task ()
  "Step 7: the questions, a blank title, No, and the back button inside the flow."
  (let ((b (make-instance 'browser)))
    (visit b "/tutorial/reading-list")
    (click b "Add a book, step by step")
    (is (shows-p b "What is the book called?"))
    (answer-input b "Let Over Lambda")
    (is (shows-p b "Who wrote it? (leave blank if you don't know)"))
    (let ((second-question (browser-url b)))
      (answer-input b "Doug Hoyte")
      (is (shows-p b "Add Let Over Lambda to the list?"))
      (press b "Yes")
      (is (shows-p b "Let Over Lambda by Doug Hoyte"))
      (is (= 3 (book-count b)))
      ;; Back to the second question: another author, and that one is used instead.
      (back-to b second-question)
      (answer-input b "D. Hoyte")
      (press b "Yes")
      (is (shows-p b "Let Over Lambda by D. Hoyte"))
      (is (not (shows-p b "Doug Hoyte")))
      (is (= 3 (book-count b))))
    ;; A blank title ends the task with nothing added.
    (click b "Add a book, step by step")
    (answer-input b "  ")
    (is (shows-p b "Reading list"))
    (is (= 3 (book-count b)))
    ;; So does No, and a blank author is no author.
    (click b "Add a book, step by step")
    (answer-input b "Anonymous")
    (answer-input b "")
    (press b "No")
    (is (not (shows-p b "Anonymous")))
    (click b "Add a book, step by step")
    (answer-input b "Anonymous")
    (answer-input b " ")
    (press b "Yes")
    (is (shows-p b "Anonymous edit"))
    (is (not (shows-p b "Anonymous by")))))

(defun check-search ()
  "Step 8: typing in the search box redraws the shelf."
  (let ((b (make-instance 'browser)))
    (visit b "/tutorial/reading-list")
    (let ((spec (first (ajax-specs b "on-input"))))
      (flet ((search-for (query)
               (ajax-request b (first spec) (rest spec) :fields (list (cons (element-name b "query") query)))))
        (let ((json (search-for "norvig")))
          (is (search "Paradigms" json))
          (is (not (search "Structure" json))))
        (is (search "Nothing matches." (search-for "no such book")))))))

(defun check-finishing ()
  "Steps 8 and 9: ticking a box updates its row, and every open list hears of it."
  (let ((b (make-instance 'browser))
        (other (make-instance 'browser))
        (sink (make-instance 'sink)))
    (visit b "/tutorial/reading-list")
    (visit other "/tutorial/reading-list")
    (is (search "data-lt-events" (browser-html other)) "A page with a subscriber opens a stream")
    (let ((stream (open-stream other sink))
          (spec (first (ajax-specs b "on-change")))
          (box (cl-ppcre:register-groups-bind (n) ("type=\"checkbox\" name=\"(\\d+)\"" (browser-html b)) n)))
      (is (wait-for (lambda () (search "retry:" (sink-text sink)))))
      (let ((json (ajax-request b (first spec) (rest spec) :fields (list (cons box "on")))))
        ;; The row's <li> comes back marked finished, which the style strikes through.
        (is (search "lt-updatable finished" json)))
      (is (search "li.finished strong { text-decoration: line-through" (browser-html b)))
      (is (wait-for (lambda ()
                      (search "Recently finished by readers here: Structure and Interpretation of Computer Programs"
                              (sink-text sink)))))
      (close-event-streams)
      (is (wait-for (lambda () (not (sb-thread:thread-alive-p stream))))))
    (visit b (browser-url b))
    (is (shows-p b "Recently finished by readers here: Structure and Interpretation of Computer Programs"))))

(defun check-reading-list ()
  "Steps 4 to 10, on the finished list."
  (check-first-list)
  (check-removing)
  (check-editing)
  (check-task)
  (check-search)
  (check-finishing))

(defmacro with-tutorial ((b) &body body)
  "Run BODY with the tutorial's applications served and a browser B."
  `(with-fresh-applications ()
     (reading-list:register :mode :deployment)
     (let ((,b (make-instance 'browser)))
       (declare (ignorable ,b))
       ,@body)))

(defclass counter-without-states (component)
  ((count :initform 0 :accessor count-without-states))
  (:documentation "Step 2's counter with no STATES method."))

(defmethod render ((self counter-without-states))
  (h:h1 () (h:text (count-without-states self)))
  (h:anchor (:callback (lambda () (incf (count-without-states self)))) "++"))

(test tutorial-steps-1-and-2
  (with-tutorial (b)
    (check-hello)
    (check-counter))
  ;; "Leave states out and the counter would act on its latest value instead."
  (with-fresh-applications (("/tutorial/counter" 'counter-without-states :mode :deployment))
    (let ((b (make-instance 'browser)) (pages '()))
      (visit b "/tutorial/counter")
      (dotimes (i 3) (click b "++") (push (browser-url b) pages))
      (back-to b (third pages))
      (click b "++")
      (is (= 4 (count-shown b))))))

(test tutorial-steps-3-to-10
  (setf reading-list::*recently-finished* '())
  (with-tutorial (b)
    (check-reading-list)))

(test tutorial-step-12-tests
  ;; The reader's tests pass: "It reports 6 checks, all passing".
  (let* ((fiveam:*test-dribble* (make-broadcast-stream))
         (results (fiveam:run 'reading-list/tests::reading-list-tests)))
    (is (= 6 (length results)))
    (is (every (lambda (r) (typep r 'fiveam::test-passed)) results))))

;;; Steps 13 to 15: the list in a database

(defun temporary-database-file ()
  (namestring (merge-pathnames (format nil "littoral-tutorial-~36R.db" (random (expt 36 8) (make-random-state t)))
                               (uiop:temporary-directory))))

(defun forget-database-file (file)
  "Drop the sign-in tables of the current database, FILE, and delete FILE."
  (ignore-errors (littoral.auth:drop-auth-tables))
  (ignore-errors (dbi:disconnect (littoral.db:database-connection)))
  (dolist (suffix '("" "-wal" "-shm"))
    (uiop:delete-file-if-exists (concatenate 'string file suffix))))

(defun book-rows ()
  "The books table's rows, as (TITLE AUTHOR READER)."
  (mapcar (lambda (row) (list (getf row :|title|) (getf row :|author|) (getf row :|reader|)))
          (littoral.db:db-query "SELECT title, author, reader FROM books ORDER BY id")))

(defun check-stored-list (open-list)
  "Step 13: adding, editing, another browser, a stale save and removing.
OPEN-LIST makes a browser showing the list.  Leaves one book on it, On Lisp."
  (let ((b (funcall open-list)))
    (is (shows-p b "My books"))
    (is (shows-p b "No books yet."))
    (fill-in b "new-title" "On Lisp")
    (press b "Add")
    (fill-in b "new-title" "Let Over Lambda")
    (press b "Add")
    (is (shows-p b "Let Over Lambda edit remove"))
    (is (shows-p b "On Lisp edit remove"))
    ;; Going back shows the books as they are now, not as they were.
    (let ((before (browser-url b)))
      (fill-in b "new-title" "Gone Soon")
      (press b "Add")
      (back-to b before)
      (is (shows-p b "Gone Soon edit remove"))
      (click-nth b "remove" 0)
      (press b "Yes")
      (is (not (shows-p b "Gone Soon"))))
    (click-nth b "edit" 1)
    (is (shows-p b "Edit book"))
    (fill-in b "author" "Paul Graham")
    (press b "Save")
    (is (shows-p b "On Lisp by Paul Graham"))
    ;; In the database, so another browser sees it.
    (let ((other (funcall open-list)))
      (is (shows-p other "On Lisp by Paul Graham"))
      ;; Both edit it; the second save would overwrite the first, so it signals.
      (click-nth b "edit" 1)
      (click-nth other "edit" 1)
      (fill-in other "author" "P. Graham")
      (press other "Save")
      (fill-in b "author" "Someone else")
      (press b "Save")
      (is (= 500 (browser-status b)))
      (is (equal "P. Graham" (second (find "On Lisp" (book-rows) :key #'first :test #'string=))))
      (is (shows-p other "On Lisp by P. Graham")))
    (let ((b (funcall open-list)))
      (click-nth b "remove" 0)
      (is (shows-p b "Remove Let Over Lambda?"))
      (press b "Yes")
      (is (not (shows-p b "Let Over Lambda")))
      (is (shows-p b "On Lisp by P. Graham")))))

(defun check-my-books-shared ()
  "Step 13, before signing in exists.  Returns a browser on the page."
  (flet ((open-list ()
           (let ((b (make-instance 'browser)))
             (visit b "/tutorial/my-books")
             b)))
    (check-stored-list #'open-list)
    (is (equal '(("On Lisp" "P. Graham" nil)) (book-rows)))
    (open-list)))

(defun sign-in (b name password)
  (click b "Sign in")
  (fill-in b "sign-in-name" name)
  (fill-in b "sign-in-password" password)
  (press b "Sign in"))

(defun remembered-sign-in-cookie (b name password)
  "Sign in on B's page with Keep me signed in ticked; the sign-in cookie
the response sets, with its attributes."
  (click b "Sign in")
  (fill-in b "sign-in-name" name)
  (fill-in b "sign-in-password" password)
  (set-checkbox b 0 t)
  (let ((button (cl-ppcre:register-groups-bind (n)
                    ("<button[^>]*name=\"([^\"]+)\"[^>]*>Sign in</button>" (browser-html b))
                  n)))
    (multiple-value-bind (status headers)
        (littoral.test:raw-request b :post (form-action b)
                                     :body (encode-fields (append (browser-fields b) (list (cons button "1")))))
      (declare (ignore status))
      (loop for (key value) on headers by #'cddr
            when (and (eq key :set-cookie) (alexandria:starts-with-subseq "_lta" value))
              return value))))

(defun check-my-books-readers (&optional (b (let ((b (make-instance 'browser))) (visit b "/tutorial/my-books") b)))
  "Step 14: signing in, a list each, and staying signed in.  B shows the
page, from before the sign-in mixins when the steps were pasted."
  (visit b (browser-url b))
  (is (shows-p b "Please sign in to see this."))
  (is (not (shows-p b "My books")))
  (sign-in b "ada" "a long passphrase")
  (is (shows-p b "Signed in as ada."))
  (is (shows-p b "No books yet."))
  (fill-in b "new-title" "On Lisp")
  (press b "Add")
  (is (shows-p b "Signed in as ada. Sign out My books On Lisp edit remove"))
  ;; A new tab: still signed in.
  (let ((tab (make-instance 'browser)))
    (setf (browser-cookies tab) (browser-cookies b))
    (visit tab "/tutorial/my-books")
    (is (shows-p tab "Signed in as ada."))
    (is (shows-p tab "On Lisp")))
  (click b "Sign out")
  (is (shows-p b "Please sign in to see this."))
  (sign-in b "bob" "another passphrase")
  (is (shows-p b "Signed in as bob."))
  (is (shows-p b "No books yet."))
  ;; Keep me signed in: the cookie lasts 30 days.
  (click b "Sign out")
  (let ((cookie (remembered-sign-in-cookie b "ada" "a long passphrase")))
    (is (search (format nil "Max-Age=~D" (* 30 86400)) cookie) "~A" cookie)))

(defun check-my-books-in-french ()
  "Step 15: French for a browser that asks, and at /tutorial/mes-livres."
  (let ((english (make-instance 'browser))
        (french (make-instance 'browser :headers '(("accept-language" . "fr")))))
    (visit english "/tutorial/my-books")
    (is (shows-p english "Please sign in to see this."))
    (visit french "/tutorial/my-books")
    (is (search "<html lang=\"fr\"" (browser-html french)))
    (is (shows-p french "Connectez-vous pour voir ceci.")))
  (let ((b (make-instance 'browser)))
    (visit b "/tutorial/mes-livres")
    (is (search "<html lang=\"fr\"" (browser-html b)))
    (is (shows-p b "Connectez-vous pour voir ceci."))
    (click b "Se connecter")
    ;; The sign-in form is littoral's, in French.
    (is (shows-p b "Nom"))
    (is (shows-p b "Mot de passe"))
    (is (shows-p b "Rester connecté"))
    (is (not (shows-p b "Password")))
    (is (not (shows-p b "Sign in")))
    (fill-in b "sign-in-name" "ada")
    (fill-in b "sign-in-password" "a long passphrase")
    (press b "Se connecter")
    (is (shows-p b "Connecté en tant que ada. Se déconnecter Mes livres On Lisp modifier supprimer"))
    (is (search "placeholder=\"Ajouter un titre\"" (browser-html b)))
    (click b "modifier")
    (is (shows-p b "Modifier le livre Titre * Auteur Enregistrer Annuler"))
    (press b "Annuler")
    (click b "supprimer")
    (is (shows-p b "Supprimer On Lisp ?"))
    (is (shows-p b "Oui"))
    (is (shows-p b "Non"))))

(test tutorial-steps-13-to-15
  (let ((file (temporary-database-file))
        (littoral.db:*database* nil))
    (unwind-protect
         (with-fresh-applications ()
           (my-books:register :file file :mode :deployment)
           (littoral.auth:add-user "ada" "ada@example.org" "a long passphrase")
           (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
           ;; Step 13's list, now for ada.
           (check-stored-list (lambda ()
                                (let ((b (make-instance 'browser)))
                                  (visit b "/tutorial/my-books")
                                  (sign-in b "ada" "a long passphrase")
                                  b)))
           (let ((ada (littoral.auth:user-id (littoral.auth:find-user "ada"))))
             (is (equal `(("On Lisp" "P. Graham" ,ada)) (book-rows))))
           (littoral.db:db-execute "DELETE FROM books")
           (check-my-books-readers)
           (check-my-books-in-french))
      (forget-database-file file))))

;;; Pasting the tutorial

(defun copy-table (table)
  "A copy of hash table TABLE, with any tables among its values copied too."
  (alexandria:copy-hash-table
   table :key (lambda (value) (if (hash-table-p value) (alexandria:copy-hash-table value) value))))

(defun catalogues-without-the-tutorial ()
  "A copy of the translation catalogues, without the French that loading
docs/tutorial/my-books.lisp added, so that pasting must add it again."
  (let* ((catalogues (copy-table littoral::*translations*))
         (form (find-if (lambda (form) (alexandria:starts-with-subseq "(define-translations" form))
                        (top-level-form-texts
                         (alexandria:read-file-into-string (tutorial-path "docs/tutorial/my-books.lisp")
                                                           :external-format :utf-8)))))
    (dolist (entry (cddr (let ((*package* (find-package '#:littoral))) (read-from-string form))))
      (remhash (first entry) (gethash "fr" catalogues)))
    catalogues))

(defvar *not-yet-defined* '()
  "(STEP . NAME) for each function the pasted code called before defining it.")

(defun paste-block (text file step)
  "Evaluate TEXT's forms in turn, as a REPL reads them, with FILE for the
database the text names.  Calls to ASDF:LOAD-SYSTEM and LITTORAL:START
are left out: this image has every system loaded, and tests open no
sockets.  A FIVEAM:RUN! must return true, and a warning is a failure.
SBCL's style warnings about functions not yet defined are noted, with
STEP, in *NOT-YET-DEFINED*."
  (let ((text (cl-ppcre:regex-replace-all "\"my-books.db\"" text (prin1-to-string file)))
        (position 0))
    (loop
      (multiple-value-bind (form end) (read-from-string text nil text :start position)
        (when (eq form text) (return))
        (setf position end)
        (unless (and (consp form) (member (first form) '(asdf:load-system littoral:start)))
          (let ((value (handler-bind ((style-warning
                                        (lambda (w)
                                          (when (and (typep w 'simple-condition)
                                                     (search "undefined function: " (princ-to-string w)))
                                            (push (cons step (car (last (simple-condition-format-arguments w))))
                                                  *not-yet-defined*))
                                          (muffle-warning w)))
                                      (warning (lambda (w) (fail "~S warned: ~A" form w) (muffle-warning w))))
                         ;; Its own compilation unit, as at a REPL: inside
                         ;; ASDF's (make test), SBCL would otherwise hold
                         ;; undefined-function warnings back until the end.
                         (with-compilation-unit (:override t)
                           (eval form)))))
            (when (and (consp form) (eq (first form) 'fiveam:run!))
              (is (eq t value) "~S failed" form))))))))

(test tutorial-pasted-in-order
  ;; The tutorial's blocks, pasted in order into fresh packages, make
  ;; applications that behave as the text says, step by step.
  (let* ((blocks (remove-if (lambda (block) (finished-code-block-p (rest block))) (tutorial-blocks)))
         (names (let ((names '()))
                  (dolist (block blocks (nreverse names))
                    (cl-ppcre:do-register-groups (name) ("\\(defpackage #:([^\\s)]+)" (rest block))
                      (push (string-upcase name) names)))))
         (file (temporary-database-file))
         (loaded '()))
    (is (equal '("READING-LIST" "READING-LIST/TESTS" "MY-BOOKS") names))
    (unwind-protect
         (progn
           ;; The finished files' packages have the names; move them aside.
           (dolist (name names)
             (let ((package (find-package name)))
               (when package
                 (rename-package package (format nil "~A (AS LOADED)" name))
                 (push (cons package name) loaded))))
           (let ((littoral::*applications* (make-hash-table :test 'equal))
                 (littoral::*translations* (catalogues-without-the-tutorial))
                 (littoral::*missing* (copy-table littoral::*missing*))
                 (littoral.db:*database* nil)
                 (*package* (find-package '#:common-lisp-user))
                 (fiveam::*suite* (make-instance 'fiveam::test-suite :name 'pasted-tutorial))
                 (fiveam:*test-dribble* (make-broadcast-stream))
                 (step-3-page nil)
                 (step-13-page nil)
                 (*not-yet-defined* '()))
             (unwind-protect
                  (progn
                   (dolist (step (remove-duplicates (mapcar #'first blocks) :from-end t))
                    (dolist (block blocks)
                      (when (= step (first block))
                        (paste-block (rest block) file step)))
                    (case step
                      (1 (check-hello))
                      (2 (check-counter))
                      (3 (setf step-3-page (check-first-list)))
                      (10
                       ;; A page left open from step 3 can't show the new version.
                       (visit step-3-page (browser-url step-3-page))
                       (is (= 500 (browser-status step-3-page)))
                       (check-reading-list))
                      (11
                       (funcall (find-symbol "REGISTER" "READING-LIST") :mode :deployment)
                       (check-hello)
                       (check-counter)
                       (check-first-list))
                      (13 (setf step-13-page (check-my-books-shared)))
                      (14 (check-my-books-readers step-13-page))
                      (15
                       (check-my-books-in-french)
                       ;; The finished register opens the database again, which is safe.
                       (funcall (find-symbol "REGISTER" "MY-BOOKS") :file file :mode :deployment)
                       (check-my-books-in-french))))
                   ;; Steps 4 and 8 say SBCL will warn of functions not yet
                   ;; defined; the later steps define them all.
                   (is (equal '(4 8) (sort (remove-duplicates (mapcar #'first *not-yet-defined*)) #'<))
                       "Undefined functions: ~S" *not-yet-defined*)
                   (flet ((names (step)
                            (sort (remove-duplicates
                                   (loop for (s . name) in *not-yet-defined* when (= s step) collect (symbol-name name))
                                   :test #'string=)
                                  #'string<)))
                     (is (subsetp '("REMOVE-BOOK" "ROWS") (names 4) :test #'string=) "~S" (names 4))
                     (is (equal '("QUERY") (names 8))))
                   (is (every #'fboundp (mapcar #'rest *not-yet-defined*))
                       "Never defined: ~S" (remove-if #'fboundp (mapcar #'rest *not-yet-defined*))))
               (when littoral.db:*database*
                 (forget-database-file file)))))
      ;; Give the names back to the finished files' packages.
      (dolist (name names)
        (let ((package (find-package name)))
          (when package (delete-package package))))
      (loop for (package . name) in loaded
            do (rename-package package name)))))
