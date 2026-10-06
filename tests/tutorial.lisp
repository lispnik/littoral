;;;; tutorial.lisp — the tutorial's application works as the tutorial says

(in-package #:littoral/tests)

(def-suite tutorial :in littoral)
(in-suite tutorial)

(defmacro with-tutorial ((b) &body body)
  "Run BODY with the tutorial's applications served and a browser B."
  `(with-fresh-applications ()
     (reading-list:register :mode :deployment)
     (let ((,b (make-instance 'browser)))
       ,@body)))

(test tutorial-steps-1-and-2
  (with-tutorial (b)
    (visit b "/tutorial/hello")
    (is (has-text-p b "Hello, world"))
    (visit b "/tutorial/counter")
    (click b "++") (click b "++")
    (let ((at-two (browser-url b)))
      (click b "++")
      (back-to b at-two)
      (click b "--")
      (is (= 1 (count-shown b))))))

(test tutorial-steps-3-to-6
  (setf reading-list::*recently-finished* '())
  (with-tutorial (b)
    (visit b "/tutorial/reading-list")
    (is (has-text-p b "Structure and Interpretation"))
    (fill-in b "new-title" "On Lisp")
    (press b "Add")
    (is (has-text-p b "On Lisp"))
    ;; Edit with the generated editor.
    (click-nth b "edit" 2)
    (is (has-text-p b "Edit book"))
    (fill-in b "author" "Paul Graham")
    (press b "Save")
    (is (has-text-p b "On Lisp by Paul Graham"))
    ;; Remove, after confirming.
    (click-nth b "remove" 0)
    (press b "No")
    (is (has-text-p b "Structure and Interpretation"))
    (click-nth b "remove" 0)
    (press b "Yes")
    (is (not (has-text-p b "Structure and Interpretation")))))

(test tutorial-step-7-task
  (with-tutorial (b)
    (visit b "/tutorial/reading-list")
    (click b "Add a book, step by step")
    (is (has-text-p b "What is the book called?"))
    (answer-input b "Let Over Lambda")
    (is (has-text-p b "Who wrote it?"))
    (answer-input b "Doug Hoyte")
    (press b "Yes")
    (is (has-text-p b "Let Over Lambda by Doug Hoyte"))
    ;; A blank title ends the task with nothing added.
    (click b "Add a book, step by step")
    (answer-input b "  ")
    (is (has-text-p b "Reading list"))
    (is (= 3 (length (cl-ppcre:all-matches-as-strings "<li[ >]" (browser-html b)))))))

(test tutorial-steps-8-and-9
  (setf reading-list::*recently-finished* '())
  (with-tutorial (b)
    (visit b "/tutorial/reading-list")
    ;; Search as you type.
    (let* ((spec (first (ajax-specs b "on-input")))
           (json (ajax-request b (first spec) (rest spec)
                               :fields (list (cons (element-name b "query") "norvig")))))
      (is (search "Paradigms" json))
      (is (not (search "Structure" json))))
    ;; Finishing a book updates its row and tells everyone.
    (visit b (browser-url b))
    (let ((other (make-instance 'browser)) (sink (make-instance 'sink)))
      (visit other "/tutorial/reading-list")
      (is (search "data-lt-events" (browser-html other)))
      (let ((stream (open-stream other sink))
            (spec (first (ajax-specs b "on-change")))
            (box (cl-ppcre:register-groups-bind (n) ("type=\"checkbox\" name=\"(\\d+)\"" (browser-html b)) n)))
        (is (wait-for (lambda () (search "retry:" (sink-text sink)))))
        (let ((json (ajax-request b (first spec) (rest spec) :fields (list (cons box "on")))))
          (is (search "class=\\\"finished\\\"" json)))
        (is (wait-for (lambda () (search "Recently finished by readers here" (sink-text sink)))))
        (close-event-streams)
        (is (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))))

(defun squeeze (string)
  "STRING with every run of whitespace made one space."
  (string-trim " " (cl-ppcre:regex-replace-all "\\s+" string " ")))

(test tutorial-text-matches-the-code
  ;; Every Lisp block in docs/tutorial.md, apart from the ones that only
  ;; show how to start things, is in the source file the tests run.
  (let* ((root (asdf:system-source-directory :littoral))
         (text (alexandria:read-file-into-string (merge-pathnames "docs/tutorial.md" root)))
         (code (squeeze (alexandria:read-file-into-string
                         (merge-pathnames "docs/tutorial/reading-list.lisp" root))))
         (blocks '()))
    (cl-ppcre:do-register-groups (block) ("(?s)```lisp\\n(.*?)```" text)
      (push block blocks))
    (is (> (length blocks) 10))
    (dolist (block blocks)
      (unless (or (search "(start " block) (search "(asdf:load-system" block))
        ;; A block may quote several forms that are apart in the file.
        (dolist (piece (cl-ppcre:split "\\n\\n(?=\\()" block))
          (is (search (squeeze piece) code) "Not in reading-list.lisp:~%~A" piece))))))
