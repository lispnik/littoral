;;;; The examples for littoral.parenscript: browser behaviour written in Parenscript.

;;;; Example: littoral.parenscript:in-browser
;;; A handler that runs only in the browser, with no request: THIS is the element.  The attribute names code that the page's own script defines, so no code rides in attributes.  (Parenscript's names are written in full here; an application's package would use parenscript.)
(defclass light-switch (component) ())
(defmethod render ((self light-switch))
  (button (:on-click (littoral.parenscript:in-browser
                      (parenscript:ps (parenscript:chain this class-list (toggle "on")))))
    "Light"))
(with-fresh-applications (("/switch" 'light-switch :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/switch")
    (list (not (null (cl-ppcre:scan "<button type=\"button\" data-lt-on-click-js=\"@c\\w+\">Light</button>" (browser-html b))))
          (not (null (search "this.classList.toggle('on');" (browser-html b)))))))
;; ⇒ (T T)

;;;; Example: littoral.parenscript:client-callback
;;; A Lisp function the browser calls with littoral.call(spec, value).  Here the request littoral.js would send is made with AJAX-REQUEST; the function's answer comes back as the JSON's "value".
(defclass shouter (component) ())
(defmethod render ((self shouter))
  (let ((spec (littoral.parenscript:client-callback #'string-upcase)))
    (button (:on-click (littoral.parenscript:in-browser
                        (parenscript:ps
                          (parenscript:chain littoral (call (parenscript:lisp spec) "hello")
                                             (then (lambda (answer) (alert answer)))))))
      "Shout")))
(with-fresh-applications (("/shout" 'shouter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/shout")
    (let ((spec (cl-ppcre:register-groups-bind (s) ("littoral.call\\('([^']*)'" (browser-html b)) s)))
      (destructuring-bind (callback targets) (cl-ppcre:split ";" spec :limit 2)
        (ajax-request b callback targets :fields '(("_lt_value" . "quiet please")))))))
;; ⇒ "{\"fragments\":{},\"missing\":[],\"value\":\"QUIET PLEASE\",\"scripts\":[]}"

;;;; Example: littoral.parenscript:define-script
;;; Page-level JavaScript for a component, written in Parenscript; (LISP …) splices in Lisp values.
(defclass greeter (component)
  ((name :initarg :name :reader greeter-name)))
(littoral.parenscript:define-script greeter (self)
  (parenscript:chain console (log (+ "Hello, " (parenscript:lisp (greeter-name self))))))
(script (make-instance 'greeter :name "Ada"))
;; ⇒ "console.log('Hello, ' + 'Ada');"

;;;; Example: littoral.parenscript:client-callback
;;; With :UPDATE, the components named are drawn again after the function runs, and the page shows them before the promise resolves.
(defclass tally (component updatable)
  ((count :initform 0 :accessor tally-count)))
(defmethod render ((self tally))
  (let ((spec (littoral.parenscript:client-callback
               (lambda (value) (declare (ignore value)) (incf (tally-count self)))
               :update self)))
    (span () (text (format nil "~D so far" (tally-count self))))
    (button (:on-click (littoral.parenscript:in-browser
                        (parenscript:ps (parenscript:chain littoral (call (parenscript:lisp spec))))))
      "Count")))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tally")
    (let ((spec (cl-ppcre:register-groups-bind (s) ("littoral.call\\('([^']*)'" (browser-html b)) s)))
      (destructuring-bind (callback targets) (cl-ppcre:split ";" spec :limit 2)
        (let ((json (ajax-request b callback targets)))
          (list (not (null (search "1 so far" json)))
                (not (null (search "\"value\":1" json)))))))))
;; ⇒ (T T)
