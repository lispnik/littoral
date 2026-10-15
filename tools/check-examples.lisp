;;;; check-examples.lisp — run the API reference's examples
;;;;
;;;;   make examples                                   ; all of them
;;;;   make examples EXAMPLES=docs/examples/10-components.lisp

(asdf:load-system :littoral/tests)      ; every system an example may use
(let ((bad 0) (n 0)
      (files (let ((one (uiop:getenv "EXAMPLES")))
               (if (and one (string/= one ""))
                   (list (merge-pathnames one (uiop:getcwd)))
                   (littoral-doc-examples:example-files)))))
  (dolist (file files)
    (dolist (example (littoral-doc-examples:read-examples file))
      (incf n)
      (let ((problems (littoral-doc-examples:run-example example)))
        (when problems
          (incf bad)
          (format t "~&FAIL ~A~%" example)
          (dolist (problem problems)
            (dolist (line (uiop:split-string problem :separator '(#\Newline)))
              (format t "  | ~A~%" line)))))))
  (format t "~&~D examples, ~D failing~%" n bad)
  (uiop:quit (if (zerop bad) 0 1)))
