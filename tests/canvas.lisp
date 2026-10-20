;;;; canvas.lisp — HTML generation

(in-package #:littoral/tests)

(def-suite canvas :in littoral)
(in-suite canvas)

(defmacro html (&body body)
  "The HTML BODY writes, with no render context."
  `(let ((littoral:*render-context* nil))
     (h:with-canvas-to-string () ,@body)))

(test escaping
  (is (string= "&lt;b&gt; &amp; &quot;q&quot; &#39;s&#39;" (h:html-escape "<b> & \"q\" 's'")))
  (is (string= "<p>1 &lt; 2</p>" (html (h:p () "1 < 2"))))
  (is (string= "<p>42</p>" (html (h:p () (h:text 42)))))
  (is (string= "<p><b>raw</b></p>" (html (h:p () (h:raw "<b>raw</b>"))))))

(test attributes
  (is (string= "<div class=\"a b\" id=\"x\">hi</div>"
               (html (h:div (:class '("a" nil "b") :id "x") "hi"))))
  (is (string= "<input type=\"text\" disabled>" (html (h:tag "input" (:type "text" :disabled t :hidden nil)))))
  (is (string= "<a title=\"&quot;\">x</a>" (html (h:tag "a" (:title "\"") "x")))))

(test omitted-attributes
  (is (string= "<ul><li>one</li><li>two</li></ul>" (html (h:ul (h:li "one") (h:li "two")))))
  (is (string= "<br>" (html (h:br))))
  (is (string= "<em></em>" (html (h:em)))))

(test callbacks-register
  (let* ((registry (make-instance 'littoral::callback-registry))
         (littoral:*render-context* (make-instance 'littoral::render-context
                                                   :callbacks registry
                                                   :action-url "/app?_s=S&_k=K"))
         (hit nil)
         (out (h:with-canvas-to-string ()
                (h:anchor (:callback (lambda () (setf hit t))) "go")
                (h:text-input (:value "v" :callback (lambda (v) (setf hit v)))))))
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
      (h:with-canvas-to-string ()
        (h:submit-button (:callback (lambda () (push :action log))) "Go")
        (h:text-input (:callback (lambda (v) (push v log))))))
    ;; The button rendered first, but fields always run before actions.
    (littoral::process-callbacks '(("1" . "1") ("2" . "field")) registry)
    (is (equal '(:action "field") log))))

(test select-and-checkbox
  (let* ((registry (make-instance 'littoral::callback-registry))
         (chosen nil) (checked :unset))
    (let ((littoral:*render-context* (make-instance 'littoral::render-context
                                                    :callbacks registry :action-url "/")))
      (let ((out (h:with-canvas-to-string ()
                   (h:select-list (:items '(:a :b :c) :selected :b :labels #'string-downcase
                                 :callback (lambda (x) (setf chosen x))))
                   (h:checkbox (:value t :callback (lambda (x) (setf checked x)))))))
        (is (search "<option value=\"1\" selected>b</option>" out))
        (is (search "type=\"checkbox\" name=\"2\" value=\"on\" checked" out))))
    (littoral::process-callbacks '(("1" . "2") ("2" . "off")) registry)
    (is (eql :c chosen))
    (is (eq nil checked))
    (littoral::process-callbacks '(("2" . "off") ("2" . "on")) registry)
    (is (eq t checked))))

(test tags-stay-macros
  ;; A DEFUN in a package using LITTORAL.HTML on a name like LABEL or MAIN
  ;; replaces the tag for everyone; this notices.
  (do-external-symbols (symbol :littoral.html)
    (when (and (fboundp symbol)
               (not (member symbol '(littoral.html:text littoral.html:raw littoral.html:html-escape
                                     littoral.html:file-name littoral.html:file-content-type
                                     littoral.html:file-contents))))
      (is (macro-function symbol) "~S is no longer a macro" symbol))))

(test every-element-has-a-tag
  ;; The elements of the HTML standard (html.spec.whatwg.org, 2025); FORM and
  ;; BUTTON are brushes, the rest plain tags.
  (dolist (name '("a" "abbr" "address" "area" "article" "aside" "audio" "b" "base" "bdi" "bdo"
                  "blockquote" "body" "br" "button" "canvas" "caption" "cite" "code" "col" "colgroup"
                  "data" "datalist" "dd" "del" "details" "dfn" "dialog" "div" "dl" "dt" "em" "embed"
                  "fieldset" "figcaption" "figure" "footer" "form" "h1" "h2" "h3" "h4" "h5" "h6" "head"
                  "header" "hgroup" "hr" "html" "i" "iframe" "img" "input" "ins" "kbd" "label" "legend"
                  "li" "link" "main" "map" "mark" "menu" "meta" "meter" "nav" "noscript" "object" "ol"
                  "optgroup" "option" "output" "p" "picture" "pre" "progress" "q" "rp" "rt" "ruby" "s"
                  "samp" "script" "search" "section" "select" "selectedcontent" "slot" "small" "source"
                  "span" "strong" "style" "sub" "summary" "sup" "table" "tbody" "td" "template"
                  "textarea" "tfoot" "th" "thead" "time" "title" "tr" "track" "u" "ul" "var" "video" "wbr"))
    (multiple-value-bind (symbol status) (find-symbol (string-upcase name) '#:littoral.html)
      (is (eq :external status) "No tag for ~A" name)
      (is (and symbol (macro-function symbol)) "~A isn't a macro" name)))
  ;; CL's names stay CL's.
  (is (not (eq 'h:time 'cl:time)))
  (is (not (eq 'h:map 'cl:map)))
  (is (not (eq 'h:search 'cl:search)))
  (is (string= "<time datetime=\"2026-10-20\">today</time><search><input type=\"search\"></search>"
               (html (h:time (:datetime "2026-10-20") "today") (h:search () (h:input (:type "search"))))))
  (is (string= "<p>a<wbr>b <var>n</var> <q>hi</q> <s>old</s></p>"
               (html (h:p () "a" (h:wbr) "b " (h:var () "n") " " (h:q () "hi") " " (h:s () "old")))))
  (is (string= "<select><optgroup label=\"Fruit\"><option value=\"1\" selected>Fig</option></optgroup></select>"
               (html (h:select () (h:optgroup (:label "Fruit") (h:option (:value 1 :selected t) "Fig")))))))

(test inputs-and-buttons-take-one-type
  (is (string= "<input type=\"search\"><button type=\"submit\">x</button>"
               (h:with-canvas-to-string () (h:text-input (:type "search")) (h:button (:type "submit") "x"))))
  (is (string= "<input type=\"text\"><button type=\"button\">x</button>"
               (h:with-canvas-to-string () (h:text-input ()) (h:button () "x")))))
