;;;; ajax.lisp — fragment updates

(in-package #:littoral/tests)

(def-suite ajax :in littoral)
(in-suite ajax)

(test ajax-counter
  (with-fresh-applications (("/ajax" 'littoral-examples:ajax-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/ajax")
      (is (search "<script src=\"/littoral/files/littoral.js?v=" (browser-html b)))
      (let* ((specs (ajax-specs b "on-click"))
             (plus (first specs)))
        (is (= 2 (length specs)))
        (multiple-value-bind (json status) (ajax-request b (car plus) (cdr plus))
          (is (= 200 status))
          (is (search "ajax-count\\\">1<" json))
          (is (search "\"missing\":[]" json)))
        (ajax-request b (car plus) (cdr plus))
        ;; AJAX changes stay when the page is reloaded or acted on.
        (visit b (browser-url b))
        (is (search "<span class=\"ajax-count\">2</span>" (browser-html b)))))))

(test ajax-field-update
  (with-fresh-applications (("/ajax" 'littoral-examples:ajax-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/ajax")
      (let* ((spec (first (ajax-specs b "on-input")))
             (field (cl-ppcre:register-groups-bind (n) ("<input type=\"text\" name=\"(\\d+)\"" (browser-html b)) n))
             (json (ajax-request b (car spec) (cdr spec) :fields (list (cons field "hello <you>")))))
        (is (string= "" (car spec)))
        (is (search "You typed: <strong>hello &lt;you&gt;</strong>" json))))))

(test ajax-periodical-attribute
  (with-fresh-applications (("/ajax" 'littoral-examples:ajax-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/ajax")
      (is (cl-ppcre:scan "data-lt-periodical=\"1000;;c[0-9a-z]+\"" (browser-html b))))))

(test ajax-missing-target
  (with-fresh-applications (("/ajax" 'littoral-examples:ajax-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/ajax")
      (is (search "\"missing\":[\"nope\"]" (ajax-request b "" "nope"))))))
