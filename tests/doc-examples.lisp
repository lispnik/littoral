;;;; doc-examples.lisp — the API reference's examples work as written

(in-package #:littoral/tests)

(def-suite doc-examples :in littoral)
(in-suite doc-examples)

(test doc-examples-name-exported-symbols
  (dolist (example (littoral-doc-examples:all-examples))
    (is (littoral-doc-examples:example-symbols example) "~A names no symbol" example)
    (dolist (name (littoral-doc-examples:example-symbols example))
      (let ((colon (position #\: name)))
        (is (and colon
                 (find-package (string-upcase (subseq name 0 colon)))
                 (eq :external (nth-value 1 (find-symbol (string-upcase (subseq name (1+ colon)))
                                                         (string-upcase (subseq name 0 colon))))))
            "~A: ~A isn't an exported symbol" example name)))))

(test doc-examples-work
  (dolist (example (littoral-doc-examples:all-examples))
    (let ((problems (littoral-doc-examples:run-example example)))
      (is (null problems) "~A:~{~%~A~}" example problems))))
