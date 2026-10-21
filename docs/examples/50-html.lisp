;;;; The examples for writing HTML: the canvas, attributes and the plain tags.

;;;; Example: littoral.html:with-canvas-to-string
;;; Render code writes to the canvas; this macro collects what it writes into a string, which is handy at the REPL and in tests.
(h:with-canvas-to-string ()
  (h:h1 () "Menu")
  (h:p (:class "note") "Fish & chips"))
;; ⇒ "<h1>Menu</h1><p class=\"note\">Fish &amp; chips</p>"

;;;; Example: littoral.html:*canvas*
;;; Tags write to whatever stream *CANVAS* is bound to.  Outside rendering it discards what it is given.
(let ((h:*canvas* (make-string-output-stream)))
  (h:p () "Saved.")
  (get-output-stream-string h:*canvas*))
;; ⇒ "<p>Saved.</p>"

;;;; Example: littoral.html:text
;;; A literal string in a tag's body is written as text, but any other form is only evaluated, so a computed value needs TEXT.  TEXT prints with PRINC and escapes.
(defun price-tag (pence)
  (h:span (:class "price")
    "£" (h:text (/ pence 100.0))))
(h:with-canvas-to-string ()
  (price-tag 450)
  (h:p () (format nil "~D items" 3))  ; written nowhere: the value is dropped
  (h:p () (h:text "<3 items>")))
;; ⇒ "<span class=\"price\">£4.5</span><p></p><p>&lt;3 items&gt;</p>"

;;;; Example: littoral.html:raw
;;; RAW writes a string as it is, for markup you trust, such as HTML your own code made.
(h:with-canvas-to-string ()
  (h:div (:class "icon")
    (h:raw "<svg width=\"8\" height=\"8\"></svg>")))
;; ⇒ "<div class=\"icon\"><svg width=\"8\" height=\"8\"></svg></div>"

;;;; Example: littoral.html:html-escape
;;; The escaping TEXT does, as a function.  Anything that isn't a string is printed first.
(list (h:html-escape "Tom & \"Jerry\" <tj@example.com>")
      (h:html-escape 42))
;; ⇒ ("Tom &amp; &quot;Jerry&quot; &lt;tj@example.com&gt;" "42")

;;;; Example: littoral.html:tag littoral.html:div littoral.html:span
;;; The first argument of a tag is a plist of attributes, whose values are evaluated.  A NIL value leaves the attribute out, T writes it bare (a boolean attribute), and a :CLASS list is joined with spaces, its NILs dropped.  Values are escaped.
(let ((selected t) (disabled nil))
  (h:with-canvas-to-string ()
    (h:div (:id "row-1" :class (list "row" (and selected "selected") nil)
          :hidden disabled :data-note "say \"hi\"")
      (h:span (:title "Ready" :aria-busy t) "Go"))))
;; ⇒ "<div id=\"row-1\" class=\"row selected\" data-note=\"say &quot;hi&quot;\"><span title=\"Ready\" aria-busy>Go</span></div>"

;;;; Example: littoral.html:div littoral.html:span littoral.html:p
;;; The attribute list may be left out when the tag has none and its body does not start with a keyword list; () works too.
(h:with-canvas-to-string ()
  (h:div
    (h:p "No attributes.")
    (h:p () "Empty attributes.")
    (h:span (h:text 3))))
;; ⇒ "<div><p>No attributes.</p><p>Empty attributes.</p><span>3</span></div>"

;;;; Example: littoral.html:tag
;;; TAG writes an element whose name is computed, for elements without a macro of their own.
(defun stamp (element when label)
  (h:tag element (:datetime when) (h:text label)))
(h:with-canvas-to-string ()
  (stamp "time" "2026-10-15" "today"))
;; ⇒ "<time datetime=\"2026-10-15\">today</time>"

;;;; Example: littoral.html:main littoral.html:header littoral.html:nav littoral.html:section littoral.html:article littoral.html:aside littoral.html:footer littoral.html:div littoral.html:span
;;; The document-structure tags.
(h:with-canvas-to-string ()
  (h:header () (h:nav (:aria-label "Site") "Home"))
  (h:main ()
    (h:section (:id "news")
      (h:article () "First post")
      (h:aside () "Related")))
  (h:footer () (h:span () "2026")))
;; ⇒ "<header><nav aria-label=\"Site\">Home</nav></header><main><section id=\"news\"><article>First post</article><aside>Related</aside></section></main><footer><span>2026</span></footer>"

;;;; Example: littoral.html:h1 littoral.html:h2 littoral.html:h3 littoral.html:h4 littoral.html:h5 littoral.html:h6 littoral.html:p
;;; Headings and paragraphs.
(h:with-canvas-to-string ()
  (h:h1 () "Guide")
  (h:h2 () "Setup")
  (h:h3 () "Linux")
  (h:h4 () "Debian")
  (h:h5 () "Packages")
  (h:h6 () "Notes")
  (h:p () "Install SBCL first."))
;; ⇒ "<h1>Guide</h1><h2>Setup</h2><h3>Linux</h3><h4>Debian</h4><h5>Packages</h5><h6>Notes</h6><p>Install SBCL first.</p>"

;;;; Example: littoral.html:em littoral.html:strong littoral.html:b littoral.html:i littoral.html:u littoral.html:small littoral.html:mark littoral.html:sup littoral.html:sub
;;; Inline text tags for emphasis and position.
(h:with-canvas-to-string ()
  (h:p ()
    (h:em () "really") " " (h:strong () "must") " " (h:b () "bold") " " (h:i () "aside") " "
    (h:u () "misspelt") " " (h:small () "fine print") " " (h:mark () "found") " "
    "x" (h:sup () "2") " H" (h:sub () "2") "O"))
;; ⇒ "<p><em>really</em> <strong>must</strong> <b>bold</b> <i>aside</i> <u>misspelt</u> <small>fine print</small> <mark>found</mark> x<sup>2</sup> H<sub>2</sub>O</p>"

;;;; Example: littoral.html:code littoral.html:pre littoral.html:kbd littoral.html:samp littoral.html:var
;;; Tags for code and computer text.
(h:with-canvas-to-string ()
  (h:p () "Press " (h:kbd () "Ctrl-C") " to stop " (h:code () "(main)") "; it prints "
     (h:samp () "Bye") ". Let " (h:var () "n") " be the port.")
  (h:pre () "(+ 1 2) ⇒ 3"))
;; ⇒ "<p>Press <kbd>Ctrl-C</kbd> to stop <code>(main)</code>; it prints <samp>Bye</samp>. Let <var>n</var> be the port.</p><pre>(+ 1 2) ⇒ 3</pre>"

;;;; Example: littoral.html:time littoral.html:data littoral.html:search littoral.html:map littoral.html:area
;;; Every element has a tag under its own name, those named like CL's TIME, SEARCH and MAP too: written with the package's nickname, H:TIME is the tag and TIME is still CL's.
(h:with-canvas-to-string ()
  (h:search ()
    (h:p () "Updated " (h:time (:datetime "2026-10-20") "today") ", "
         (h:data (:value 42) "forty-two") " results."))
  (h:map (:name "plan")
    (h:area (:shape "rect" :coords "0,0,10,10" :href "/kitchen" :alt "Kitchen"))))
;; ⇒ "<search><p>Updated <time datetime=\"2026-10-20\">today</time>, <data value=\"42\">forty-two</data> results.</p></search><map name=\"plan\"><area shape=\"rect\" coords=\"0,0,10,10\" href=\"/kitchen\" alt=\"Kitchen\"></map>"

;;;; Example: littoral.html:picture littoral.html:source littoral.html:video littoral.html:track littoral.html:wbr
;;; Void elements, such as source, track and wbr, get no closing tag.
(h:with-canvas-to-string ()
  (h:picture ()
    (h:source (:srcset "/cat.avif" :type "image/avif"))
    (h:img (:src "/cat.jpg" :alt "A cat")))
  (h:video (:src "/talk.mp4" :controls t)
    (h:track (:kind "captions" :src "/talk.vtt" :srclang "en")))
  (h:p () "super" (h:wbr) "califragilistic"))
;; ⇒ "<picture><source srcset=\"/cat.avif\" type=\"image/avif\"><img src=\"/cat.jpg\" alt=\"A cat\"></picture><video src=\"/talk.mp4\" controls><track kind=\"captions\" src=\"/talk.vtt\" srclang=\"en\"></video><p>super<wbr>califragilistic</p>"

;;;; Example: littoral.html:blockquote littoral.html:cite littoral.html:abbr littoral.html:dfn
;;; Quotations, citations, abbreviations and definitions.
(h:with-canvas-to-string ()
  (h:blockquote (:cite "https://example.com/talk")
    (h:p () "Make it work, then make it fast."))
  (h:p () (h:cite () "The Talk") ": " (h:dfn () (h:abbr (:title "Server-sent events") "SSE"))
     " streams events to a page."))
;; ⇒ "<blockquote cite=\"https://example.com/talk\"><p>Make it work, then make it fast.</p></blockquote><p><cite>The Talk</cite>: <dfn><abbr title=\"Server-sent events\">SSE</abbr></dfn> streams events to a page.</p>"

;;;; Example: littoral.html:ul littoral.html:ol littoral.html:li littoral.html:dl littoral.html:dt littoral.html:dd
;;; Lists.  A body may contain any Lisp code, such as a loop writing one item per element.
(h:with-canvas-to-string ()
  (h:ul (:class "tags")
    (dolist (tag '("lisp" "web"))
      (h:li () (h:text tag))))
  (h:ol () (h:li () "Clone") (h:li () "Build"))
  (h:dl ()
    (h:dt () "SBCL") (h:dd () "A Common Lisp compiler")))
;; ⇒ "<ul class=\"tags\"><li>lisp</li><li>web</li></ul><ol><li>Clone</li><li>Build</li></ol><dl><dt>SBCL</dt><dd>A Common Lisp compiler</dd></dl>"

;;;; Example: littoral.html:table littoral.html:caption littoral.html:thead littoral.html:tbody littoral.html:tfoot littoral.html:tr littoral.html:th littoral.html:td
;;; Tables.
(let ((rows '(("Apples" 3) ("Pears" 5))))
  (h:with-canvas-to-string ()
    (h:table (:class "stock")
      (h:caption () "Stock")
      (h:thead () (h:tr () (h:th (:scope "col") "Fruit") (h:th (:scope "col") "Count")))
      (h:tbody ()
        (loop for (fruit count) in rows
              do (h:tr () (h:td () (h:text fruit)) (h:td () (h:text count)))))
      (h:tfoot () (h:tr () (h:th () "Total") (h:td () (h:text (reduce #'+ rows :key #'second))))))))
;; ⇒ "<table class=\"stock\"><caption>Stock</caption><thead><tr><th scope=\"col\">Fruit</th><th scope=\"col\">Count</th></tr></thead><tbody><tr><td>Apples</td><td>3</td></tr><tr><td>Pears</td><td>5</td></tr></tbody><tfoot><tr><th>Total</th><td>8</td></tr></tfoot></table>"

;;;; Example: littoral.html:fieldset littoral.html:legend littoral.html:label
;;; Grouping and labelling form controls.  The controls themselves are brushes, such as TEXT-INPUT.
(h:with-canvas-to-string ()
  (h:fieldset ()
    (h:legend () "Contact")
    (h:label (:for "email") "Email")
    (h:text-input (:id "email" :name "email"))))
;; ⇒ "<fieldset><legend>Contact</legend><label for=\"email\">Email</label><input type=\"text\" name=\"email\" id=\"email\"></fieldset>"

;;;; Example: littoral.html:figure littoral.html:figcaption littoral.html:img littoral.html:br littoral.html:hr
;;; Figures and images.  IMG, BR and HR are void elements: they take attributes but no body, and have no closing tag.
(h:with-canvas-to-string ()
  (h:figure ()
    (h:img (:src "/static/boat.png" :alt "A boat" :width 120))
    (h:figcaption () "Low tide" (h:br) "at noon"))
  (h:hr))
;; ⇒ "<figure><img src=\"/static/boat.png\" alt=\"A boat\" width=\"120\"><figcaption>Low tide<br>at noon</figcaption></figure><hr>"

;;;; Example: littoral.html:details littoral.html:summary
;;; A disclosure box the browser opens and closes by itself; :OPEN T starts it open.
(h:with-canvas-to-string ()
  (h:details (:open t)
    (h:summary () "More")
    (h:p () "Hidden until opened.")))
;; ⇒ "<details open><summary>More</summary><p>Hidden until opened.</p></details>"

;;;; Example: littoral.html:html littoral.html:head littoral.html:title littoral.html:meta littoral.html:base littoral.html:link littoral.html:style littoral.html:script littoral.html:body
;;; A whole document, for an endpoint or a mail rather than a component (an application's page head is HTML-ROOT's).  STYLE and SCRIPT bodies are written as they are, so give them text with H:RAW.
(h:with-canvas-to-string ()
  (h:raw "<!doctype html>")
  (h:html (:lang "en")
    (h:head ()
      (h:meta (:charset "utf-8"))
      (h:title () "Receipt")
      (h:base (:href "https://shop.example/"))
      (h:link (:rel "stylesheet" :href "receipt.css"))
      (h:style () (h:raw "p { margin: 0 }")))
    (h:body ()
      (h:p () "Thank you.")
      (h:script (:src "receipt.js")))))
;; ⇒ "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Receipt</title><base href=\"https://shop.example/\"><link rel=\"stylesheet\" href=\"receipt.css\"><style>p { margin: 0 }</style></head><body><p>Thank you.</p><script src=\"receipt.js\"></script></body></html>"

;;;; Example: littoral.html:noscript littoral.html:template littoral.html:slot
;;; NOSCRIPT is shown only without JavaScript; TEMPLATE holds markup for scripts to copy, with SLOTs for a web component's content.
(h:with-canvas-to-string ()
  (h:noscript () (h:p () "Turn on JavaScript to see the map."))
  (h:template (:id "card")
    (h:div (:class "card") (h:slot (:name "title") "Untitled"))))
;; ⇒ "<noscript><p>Turn on JavaScript to see the map.</p></noscript><template id=\"card\"><div class=\"card\"><slot name=\"title\">Untitled</slot></div></template>"

;;;; Example: littoral.html:hgroup littoral.html:address littoral.html:menu
;;; A heading with its subtitle, contact details, and a menu: a list of commands.
(h:with-canvas-to-string ()
  (h:hgroup () (h:h1 () "Littoral") (h:p () "Web applications in Lisp"))
  (h:address () "Write to " (h:a (:href "mailto:ada@example.com") "Ada"))
  (h:menu () (h:li () (h:button () "Copy")) (h:li () (h:button () "Paste"))))
;; ⇒ "<hgroup><h1>Littoral</h1><p>Web applications in Lisp</p></hgroup><address>Write to <a href=\"mailto:ada@example.com\">Ada</a></address><menu><li><button type=\"button\">Copy</button></li><li><button type=\"button\">Paste</button></li></menu>"

;;;; Example: littoral.html:a littoral.html:s littoral.html:q littoral.html:ins littoral.html:del
;;; H:A is a plain link, with no callback (H:ANCHOR has those).  S is no longer accurate, Q quotes inline, and INS and DEL mark what an edit added and took away.
(h:with-canvas-to-string ()
  (h:p () (h:a (:href "/sale") "Sale") ": " (h:s () "£30") " £20, "
     (h:q () "while stocks last") ". Ends " (h:del () "Friday") (h:ins () "Sunday") "."))
;; ⇒ "<p><a href=\"/sale\">Sale</a>: <s>£30</s> £20, <q>while stocks last</q>. Ends <del>Friday</del><ins>Sunday</ins>.</p>"

;;;; Example: littoral.html:ruby littoral.html:rt littoral.html:rp littoral.html:bdi littoral.html:bdo
;;; Ruby annotations (with RP's parentheses for browsers without them), and isolating or overriding the direction of text.
(h:with-canvas-to-string ()
  (h:p () (h:ruby () "漢" (h:rp () "(") (h:rt () "kan") (h:rp () ")")))
  (h:p () "Winner: " (h:bdi () "إيان") ", " (h:bdo (:dir "rtl") "backwards")))
;; ⇒ "<p><ruby>漢<rp>(</rp><rt>kan</rt><rp>)</rp></ruby></p><p>Winner: <bdi>إيان</bdi>, <bdo dir=\"rtl\">backwards</bdo></p>"

;;;; Example: littoral.html:iframe littoral.html:embed littoral.html:object littoral.html:audio littoral.html:canvas
;;; Embedded content.  EMBED is void; the others' bodies are the fallback.
(h:with-canvas-to-string ()
  (h:iframe (:src "/preview" :title "Preview" :sandbox ""))
  (h:embed (:src "/chart.svg" :type "image/svg+xml"))
  (h:object (:data "/report.pdf" :type "application/pdf") (h:a (:href "/report.pdf") "The report"))
  (h:audio (:src "/bell.ogg" :controls t) "No audio here.")
  (h:canvas (:width 200 :height 100) "A chart of sales."))
;; ⇒ "<iframe src=\"/preview\" title=\"Preview\" sandbox=\"\"></iframe><embed src=\"/chart.svg\" type=\"image/svg+xml\"><object data=\"/report.pdf\" type=\"application/pdf\"><a href=\"/report.pdf\">The report</a></object><audio src=\"/bell.ogg\" controls>No audio here.</audio><canvas width=\"200\" height=\"100\">A chart of sales.</canvas>"

;;;; Example: littoral.html:colgroup littoral.html:col
;;; Columns styled as a whole.  COL is void.
(h:with-canvas-to-string ()
  (h:table ()
    (h:colgroup () (h:col (:class "name")) (h:col (:span 2 :class "number")))
    (h:tr () (h:td () "Figs") (h:td () "3") (h:td () "£1.20"))))
;; ⇒ "<table><colgroup><col class=\"name\"><col span=\"2\" class=\"number\"></colgroup><tr><td>Figs</td><td>3</td><td>£1.20</td></tr></table>"

;;;; Example: littoral.html:input littoral.html:select littoral.html:optgroup littoral.html:option littoral.html:datalist littoral.html:textarea
;;; Form controls written plainly, with no callback, for a form that posts somewhere else.  The brushes (H:TEXT-INPUT, H:SELECT-LIST, …) are the ones whose values come back to Lisp.
(h:with-canvas-to-string ()
  (h:input (:name "q" :list "places" :placeholder "Town"))
  (h:datalist (:id "places") (h:option (:value "Leeds")) (h:option (:value "York")))
  (h:select (:name "fruit")
    (h:optgroup (:label "Stone fruit") (h:option (:value "plum" :selected t) "Plum")))
  (h:textarea (:name "note" :rows 2) "Hello"))
;; ⇒ "<input name=\"q\" list=\"places\" placeholder=\"Town\"><datalist id=\"places\"><option value=\"Leeds\"></option><option value=\"York\"></option></datalist><select name=\"fruit\"><optgroup label=\"Stone fruit\"><option value=\"plum\" selected>Plum</option></optgroup></select><textarea name=\"note\" rows=\"2\">Hello</textarea>"

;;;; Example: littoral.html:selectedcontent
;;; In a customizable select, SELECTEDCONTENT shows a copy of the chosen option inside the button.
(h:with-canvas-to-string ()
  (h:select (:name "pet")
    (h:button () (h:selectedcontent))
    (h:option (:value "cat") "🐈 Cat")
    (h:option (:value "dog") "🐕 Dog")))
;; ⇒ "<select name=\"pet\"><button type=\"button\"><selectedcontent></selectedcontent></button><option value=\"cat\">🐈 Cat</option><option value=\"dog\">🐕 Dog</option></select>"

;;;; Example: littoral.html:output littoral.html:progress littoral.html:meter
;;; A calculation's result, progress towards finishing, and a measurement within a range.
(h:with-canvas-to-string ()
  (h:p () "Total: " (h:output (:for "price quantity") "£6"))
  (h:progress (:value 3 :max 10) "3 of 10")
  (h:meter (:value 0.7 :low 0.2 :high 0.8) "70%"))
;; ⇒ "<p>Total: <output for=\"price quantity\">£6</output></p><progress value=\"3\" max=\"10\">3 of 10</progress><meter value=\"0.7\" low=\"0.2\" high=\"0.8\">70%</meter>"

;;;; Example: littoral.html:dialog
;;; A dialog box; :OPEN shows it, and a form with :METHOD "dialog" closes it without a request.  CALL-MODAL and SHOW-MODAL draw Littoral's own.
(h:with-canvas-to-string ()
  (h:dialog (:open t :aria-labelledby "saved")
    (h:h2 (:id "saved") "Saved")
    (h:p () "Your changes are saved.")
    (h:form (:method "dialog" :action "#")
      (h:input (:type "submit" :value "OK")))))
;; ⇒ "<dialog open aria-labelledby=\"saved\"><h2 id=\"saved\">Saved</h2><p>Your changes are saved.</p><form method=\"dialog\" action=\"#\" accept-charset=\"utf-8\"><input type=\"submit\" value=\"OK\"></form></dialog>"
