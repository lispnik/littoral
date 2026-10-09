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
        (is (= 5 (length specs)))         ; ++, -- and the three server-talk buttons
        (multiple-value-bind (json status) (ajax-request b (first plus) (rest plus))
          (is (= 200 status))
          (is (search "ajax-count\\\">1<" json))
          (is (search "\"missing\":[]" json)))
        (ajax-request b (first plus) (rest plus))
        ;; AJAX changes stay when the page is reloaded or acted on.
        (visit b (browser-url b))
        (is (search "<span class=\"ajax-count\">2</span>" (browser-html b)))))))

(test ajax-field-update
  (with-fresh-applications (("/ajax" 'littoral-examples:ajax-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/ajax")
      (let* ((spec (first (ajax-specs b "on-input")))
             (field (cl-ppcre:register-groups-bind (n) ("<input type=\"text\" name=\"(\\d+)\"" (browser-html b)) n))
             (json (ajax-request b (first spec) (rest spec) :fields (list (cons field "hello <you>")))))
        (is (string= "" (first spec)))
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

(defun element-spec (browser id event)
  "The (CALLBACK . TARGETS) of EVENT on the element with DOM id ID."
  (cl-ppcre:register-groups-bind (spec)
      ((format nil "id=\"~A\"[^>]*data-lt-~A=\"([^\"]*)\"" id event) (browser-html browser))
    (let ((spec (unescape spec)))
      (cons (subseq spec 0 (position #\; spec)) (subseq spec (1+ (position #\; spec)))))))

(test ajax-value-result-and-options
  (with-fresh-applications (("/ajax" 'littoral-examples:ajax-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/ajax")
      ;; The value expression is defined by the page's script; the attribute names it.
      (is (cl-ppcre:scan "data-lt-on-click-value=\"@c[0-9A-Za-z]+\"" (browser-html b)))
      (is (search "return (window.innerWidth + 'x' + window.innerHeight);" (browser-html b)))
      (is (search "data-lt-on-click-complete=" (browser-html b)))
      (is (search "data-lt-on-click-confirm=\"Reset the counter to zero?\"" (browser-html b)))
      ;; The browser's value reaches the callback; its result comes back.
      (let* ((spec (element-spec b "measure" "on-click"))
             (json (ajax-request b (first spec) (rest spec) :fields '(("_lt_value" . "800x600")))))
        (is (search "\"value\":\"The server heard 800x600.\"" json)))
      ;; Scripts queued by the callback come back to run.
      (let ((plus (first (ajax-specs b "on-click"))))
        (ajax-request b (first plus) (rest plus)))
      (let* ((spec (element-spec b "retitle" "on-click"))
             (json (ajax-request b (first spec) (rest spec))))
        (is (search "\"scripts\":[\"document.title = \\\"Counter at 1\\\"\"]" json)))
      (let* ((spec (element-spec b "reset" "on-click"))
             (json (ajax-request b (first spec) (rest spec))))
        (is (search "ajax-count\\\">0<" json))))))

(test execute-script-outside-ajax
  (is (null (execute-script "alert(1)"))))

(test json-values
  (is (string= "null" (littoral::json-value nil)))
  (is (string= "true" (littoral::json-value t)))
  (is (string= "false" (littoral::json-value :false)))
  (is (string= "[1,2.5,\"a\\\"b\"]" (littoral::json-value (list 1 2.5 "a\"b"))))
  (is (string= "{\"total\":3,\"items\":[\"x\"]}" (littoral::json-value '(:total 3 :items ("x"))))))
