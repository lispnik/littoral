;;;; parenscript.lisp — browser behaviour written in Lisp

(in-package #:littoral/tests)

(def-suite parenscript :in littoral)
(in-suite parenscript)

(test client-handlers-and-callbacks
  (with-fresh-applications (("/ps" 'littoral-parenscript-demo:ps-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/ps")
      ;; The handler is compiled JavaScript, defined by the page's own script;
      ;; the attribute only names it.
      (is (cl-ppcre:scan "data-lt-on-click-js=\"@c[0-9A-Za-z]+\"" (browser-html b)))
      (is (search "setAttribute('aria-pressed'" (browser-html b)))
      (is (search "__ltCode[" (browser-html b)))
      ;; The page-level script, with the component's id spliced in.
      (is (cl-ppcre:scan "console.log\\('ps-demo ready, component ' \\+ 'c[0-9a-z]+'\\)" (browser-html b)))
      ;; littoral.call's spec names a callback and the component to update.
      (let ((spec (cl-ppcre:register-groups-bind (s) ("littoral.call\\('([0-9]+;c[0-9a-z]+)'" (browser-html b)) s)))
        (is (not (null spec)))
        (let* ((parts (cl-ppcre:split ";" spec))
               (json (ajax-request b (first parts) (second parts) :fields '(("_lt_value" . "quiet please")))))
          (is (search "\"value\":\"QUIET PLEASE\"" json))
          (is (search "Asked 1 time." json)))))))

(test define-script-compiles-parenscript
  (let ((demo (make-instance 'littoral-parenscript-demo:ps-demo)))
    (is (search (component-id demo) (script demo)))))
