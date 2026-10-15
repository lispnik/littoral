;;;; The examples for writing HTML: the canvas, attributes and the plain tags.

;;;; Example: littoral.html:with-canvas-to-string
;;; Render code writes to the canvas; this macro collects what it writes into a string, which is handy at the REPL and in tests.
(with-canvas-to-string ()
  (h1 () "Menu")
  (p (:class "note") "Fish & chips"))
;; ⇒ "<h1>Menu</h1><p class=\"note\">Fish &amp; chips</p>"

;;;; Example: littoral.html:*canvas*
;;; Tags write to whatever stream *CANVAS* is bound to.  Outside rendering it discards what it is given.
(let ((*canvas* (make-string-output-stream)))
  (p () "Saved.")
  (get-output-stream-string *canvas*))
;; ⇒ "<p>Saved.</p>"

;;;; Example: littoral.html:text
;;; A literal string in a tag's body is written as text, but any other form is only evaluated, so a computed value needs TEXT.  TEXT prints with PRINC and escapes.
(defun price-tag (pence)
  (span (:class "price")
    "£" (text (/ pence 100.0))))
(with-canvas-to-string ()
  (price-tag 450)
  (p () (format nil "~D items" 3))  ; written nowhere: the value is dropped
  (p () (text "<3 items>")))
;; ⇒ "<span class=\"price\">£4.5</span><p></p><p>&lt;3 items&gt;</p>"

;;;; Example: littoral.html:raw
;;; RAW writes a string as it is, for markup you trust, such as HTML your own code made.
(with-canvas-to-string ()
  (div (:class "icon")
    (raw "<svg width=\"8\" height=\"8\"></svg>")))
;; ⇒ "<div class=\"icon\"><svg width=\"8\" height=\"8\"></svg></div>"

;;;; Example: littoral.html:html-escape
;;; The escaping TEXT does, as a function.  Anything that isn't a string is printed first.
(list (html-escape "Tom & \"Jerry\" <tj@example.com>")
      (html-escape 42))
;; ⇒ ("Tom &amp; &quot;Jerry&quot; &lt;tj@example.com&gt;" "42")

;;;; Example: littoral.html:tag littoral.html:div littoral.html:span
;;; The first argument of a tag is a plist of attributes, whose values are evaluated.  A NIL value leaves the attribute out, T writes it bare (a boolean attribute), and a :CLASS list is joined with spaces, its NILs dropped.  Values are escaped.
(let ((selected t) (disabled nil))
  (with-canvas-to-string ()
    (div (:id "row-1" :class (list "row" (and selected "selected") nil)
          :hidden disabled :data-note "say \"hi\"")
      (span (:title "Ready" :aria-busy t) "Go"))))
;; ⇒ "<div id=\"row-1\" class=\"row selected\" data-note=\"say &quot;hi&quot;\"><span title=\"Ready\" aria-busy>Go</span></div>"

;;;; Example: littoral.html:div littoral.html:span littoral.html:p
;;; The attribute list may be left out when the tag has none and its body does not start with a keyword list; () works too.
(with-canvas-to-string ()
  (div
    (p "No attributes.")
    (p () "Empty attributes.")
    (span (text 3))))
;; ⇒ "<div><p>No attributes.</p><p>Empty attributes.</p><span>3</span></div>"

;;;; Example: littoral.html:tag
;;; TAG writes an element whose name is computed, for elements without a macro of their own.
(defun stamp (element when label)
  (tag element (:datetime when) (text label)))
(with-canvas-to-string ()
  (stamp "time" "2026-10-15" "today"))
;; ⇒ "<time datetime=\"2026-10-15\">today</time>"

;;;; Example: littoral.html:main littoral.html:header littoral.html:nav littoral.html:section littoral.html:article littoral.html:aside littoral.html:footer littoral.html:div littoral.html:span
;;; The document-structure tags.
(with-canvas-to-string ()
  (header () (nav (:aria-label "Site") "Home"))
  (main ()
    (section (:id "news")
      (article () "First post")
      (aside () "Related")))
  (footer () (span () "2026")))
;; ⇒ "<header><nav aria-label=\"Site\">Home</nav></header><main><section id=\"news\"><article>First post</article><aside>Related</aside></section></main><footer><span>2026</span></footer>"

;;;; Example: littoral.html:h1 littoral.html:h2 littoral.html:h3 littoral.html:h4 littoral.html:h5 littoral.html:h6 littoral.html:p
;;; Headings and paragraphs.
(with-canvas-to-string ()
  (h1 () "Guide")
  (h2 () "Setup")
  (h3 () "Linux")
  (h4 () "Debian")
  (h5 () "Packages")
  (h6 () "Notes")
  (p () "Install SBCL first."))
;; ⇒ "<h1>Guide</h1><h2>Setup</h2><h3>Linux</h3><h4>Debian</h4><h5>Packages</h5><h6>Notes</h6><p>Install SBCL first.</p>"

;;;; Example: littoral.html:em littoral.html:strong littoral.html:b littoral.html:i littoral.html:u littoral.html:small littoral.html:mark littoral.html:sup littoral.html:sub
;;; Inline text tags for emphasis and position.
(with-canvas-to-string ()
  (p ()
    (em () "really") " " (strong () "must") " " (b () "bold") " " (i () "aside") " "
    (u () "misspelt") " " (small () "fine print") " " (mark () "found") " "
    "x" (sup () "2") " H" (sub () "2") "O"))
;; ⇒ "<p><em>really</em> <strong>must</strong> <b>bold</b> <i>aside</i> <u>misspelt</u> <small>fine print</small> <mark>found</mark> x<sup>2</sup> H<sub>2</sub>O</p>"

;;;; Example: littoral.html:code littoral.html:pre littoral.html:kbd littoral.html:samp littoral.html:var-tag
;;; Tags for code and computer text.  The HTML var element is VAR-TAG, as VAR is too useful a name to take from your code.
(with-canvas-to-string ()
  (p () "Press " (kbd () "Ctrl-C") " to stop " (code () "(main)") "; it prints "
     (samp () "Bye") ". Let " (var-tag () "n") " be the port.")
  (pre () "(+ 1 2) ⇒ 3"))
;; ⇒ "<p>Press <kbd>Ctrl-C</kbd> to stop <code>(main)</code>; it prints <samp>Bye</samp>. Let <var>n</var> be the port.</p><pre>(+ 1 2) ⇒ 3</pre>"

;;;; Example: littoral.html:blockquote littoral.html:cite littoral.html:abbr littoral.html:dfn
;;; Quotations, citations, abbreviations and definitions.
(with-canvas-to-string ()
  (blockquote (:cite "https://example.com/talk")
    (p () "Make it work, then make it fast."))
  (p () (cite () "The Talk") ": " (dfn () (abbr (:title "Server-sent events") "SSE"))
     " streams events to a page."))
;; ⇒ "<blockquote cite=\"https://example.com/talk\"><p>Make it work, then make it fast.</p></blockquote><p><cite>The Talk</cite>: <dfn><abbr title=\"Server-sent events\">SSE</abbr></dfn> streams events to a page.</p>"

;;;; Example: littoral.html:ul littoral.html:ol littoral.html:li littoral.html:dl littoral.html:dt littoral.html:dd
;;; Lists.  A body may contain any Lisp code, such as a loop writing one item per element.
(with-canvas-to-string ()
  (ul (:class "tags")
    (dolist (tag '("lisp" "web"))
      (li () (text tag))))
  (ol () (li () "Clone") (li () "Build"))
  (dl ()
    (dt () "SBCL") (dd () "A Common Lisp compiler")))
;; ⇒ "<ul class=\"tags\"><li>lisp</li><li>web</li></ul><ol><li>Clone</li><li>Build</li></ol><dl><dt>SBCL</dt><dd>A Common Lisp compiler</dd></dl>"

;;;; Example: littoral.html:table littoral.html:caption littoral.html:thead littoral.html:tbody littoral.html:tfoot littoral.html:tr littoral.html:th littoral.html:td
;;; Tables.
(let ((rows '(("Apples" 3) ("Pears" 5))))
  (with-canvas-to-string ()
    (table (:class "stock")
      (caption () "Stock")
      (thead () (tr () (th (:scope "col") "Fruit") (th (:scope "col") "Count")))
      (tbody ()
        (loop for (fruit count) in rows
              do (tr () (td () (text fruit)) (td () (text count)))))
      (tfoot () (tr () (th () "Total") (td () (text (reduce #'+ rows :key #'second))))))))
;; ⇒ "<table class=\"stock\"><caption>Stock</caption><thead><tr><th scope=\"col\">Fruit</th><th scope=\"col\">Count</th></tr></thead><tbody><tr><td>Apples</td><td>3</td></tr><tr><td>Pears</td><td>5</td></tr></tbody><tfoot><tr><th>Total</th><td>8</td></tr></tfoot></table>"

;;;; Example: littoral.html:fieldset littoral.html:legend littoral.html:label
;;; Grouping and labelling form controls.  The controls themselves are brushes, such as TEXT-INPUT.
(with-canvas-to-string ()
  (fieldset ()
    (legend () "Contact")
    (label (:for "email") "Email")
    (text-input (:id "email" :name "email"))))
;; ⇒ "<fieldset><legend>Contact</legend><label for=\"email\">Email</label><input type=\"text\" name=\"email\" id=\"email\"></fieldset>"

;;;; Example: littoral.html:figure littoral.html:figcaption littoral.html:img littoral.html:br littoral.html:hr
;;; Figures and images.  IMG, BR and HR are void elements: they take attributes but no body, and have no closing tag.
(with-canvas-to-string ()
  (figure ()
    (img (:src "/static/boat.png" :alt "A boat" :width 120))
    (figcaption () "Low tide" (br) "at noon"))
  (hr))
;; ⇒ "<figure><img src=\"/static/boat.png\" alt=\"A boat\" width=\"120\"><figcaption>Low tide<br>at noon</figcaption></figure><hr>"

;;;; Example: littoral.html:details littoral.html:summary
;;; A disclosure box the browser opens and closes by itself; :OPEN T starts it open.
(with-canvas-to-string ()
  (details (:open t)
    (summary () "More")
    (p () "Hidden until opened.")))
;; ⇒ "<details open><summary>More</summary><p>Hidden until opened.</p></details>"
