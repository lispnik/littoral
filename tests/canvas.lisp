;;;; canvas.lisp — HTML generation

(in-package #:littoral/tests)

(def-suite canvas :in littoral)
(in-suite canvas)

(defmacro html (&body body)
  `(let ((littoral:*render-context* nil))
     (with-canvas-to-string () ,@body)))

(test escaping
  (is (string= "&lt;b&gt; &amp; &quot;q&quot; &#39;s&#39;" (html-escape "<b> & \"q\" 's'")))
  (is (string= "<p>1 &lt; 2</p>" (html (p () "1 < 2"))))
  (is (string= "<p>42</p>" (html (p () (text 42)))))
  (is (string= "<p><b>raw</b></p>" (html (p () (raw "<b>raw</b>"))))))

(test attributes
  (is (string= "<div class=\"a b\" id=\"x\">hi</div>"
               (html (div (:class '("a" nil "b") :id "x") "hi"))))
  (is (string= "<input type=\"text\" disabled>" (html (tag "input" (:type "text" :disabled t :hidden nil)))))
  (is (string= "<a title=\"&quot;\">x</a>" (html (tag "a" (:title "\"") "x")))))

(test omitted-attributes
  (is (string= "<ul><li>one</li><li>two</li></ul>" (html (ul (li "one") (li "two")))))
  (is (string= "<br>" (html (br))))
  (is (string= "<em></em>" (html (em)))))

(test callbacks-register
  (let* ((registry (make-instance 'littoral::callback-registry))
         (littoral:*render-context* (make-instance 'littoral::render-context
                                                   :callbacks registry
                                                   :action-url "/app?_s=S&_k=K"))
         (hit nil)
         (out (with-canvas-to-string ()
                (anchor (:callback (lambda () (setf hit t))) "go")
                (text-input (:value "v" :callback (lambda (v) (setf hit v)))))))
    (is (search "href=\"/app?_s=S&amp;_k=K&amp;1\"" out))
    (is (search "name=\"2\" value=\"v\"" out))
    (littoral::process-callbacks '(("1")) registry)
    (is (eq t hit))
    (littoral::process-callbacks '(("2" . "typed")) registry)
    (is (equal "typed" hit))))

(test value-callbacks-before-action
  (let* ((registry (make-instance 'littoral::callback-registry))
         (log '()))
    (let ((littoral:*render-context* (make-instance 'littoral::render-context
                                                    :callbacks registry :action-url "/")))
      (with-canvas-to-string ()
        (submit-button (:callback (lambda () (push :action log))) "Go")
        (text-input (:callback (lambda (v) (push v log))))))
    ;; The button rendered first, but fields always run before actions.
    (littoral::process-callbacks '(("1" . "1") ("2" . "field")) registry)
    (is (equal '(:action "field") log))))

(test select-and-checkbox
  (let* ((registry (make-instance 'littoral::callback-registry))
         (chosen nil) (checked :unset))
    (let ((littoral:*render-context* (make-instance 'littoral::render-context
                                                    :callbacks registry :action-url "/")))
      (let ((out (with-canvas-to-string ()
                   (select-list (:items '(:a :b :c) :selected :b :labels #'string-downcase
                                 :callback (lambda (x) (setf chosen x))))
                   (checkbox (:value t :callback (lambda (x) (setf checked x)))))))
        (is (search "<option value=\"1\" selected>b</option>" out))
        (is (search "type=\"checkbox\" name=\"2\" value=\"on\" checked" out))))
    (littoral::process-callbacks '(("1" . "2") ("2" . "off")) registry)
    (is (eq :c chosen))
    (is (eq nil checked))
    (littoral::process-callbacks '(("2" . "off") ("2" . "on")) registry)
    (is (eq t checked))))
