;;;; The examples for components.  See tools/doc-examples.lisp for the format.

;;;; Example: littoral:render littoral:component
;;; A component draws itself in its render method.  Visiting an application serves its root component.
(defclass greeting (component) ())
(defmethod render ((self greeting))
  (h1 () "Hello"))
(with-fresh-applications (("/greeting" 'greeting :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greeting")
    (body-text b)))
;; ⇒ "Hello"

;;;; Example: littoral.html:with-canvas-to-string
;;; The HTML that rendering code writes, as a string.
(with-canvas-to-string () (p (:class "note") "Fish & chips"))
;; ⇒ "<p class=\"note\">Fish &amp; chips</p>"

;;;; Example: littoral:render-component littoral:children
;;; A component that embeds others renders each with render-component and names them in children, so backtracking, AJAX and halos can find them.
(defclass counter (component)
  ((label :initarg :label :reader counter-label)
   (count :initform 0 :accessor counter-count)))
(defmethod states ((self counter)) (list self))
(defmethod render ((self counter))
  (p () (text (counter-label self)) ": " (text (princ-to-string (counter-count self))) " "
    (anchor (:callback (lambda () (incf (counter-count self))))
      "more " (text (counter-label self)))))
(defclass tally (component)
  ((counters :initform (list (make-instance 'counter :label "gulls")
                             (make-instance 'counter :label "terns"))
             :reader tally-counters)))
(defmethod children ((self tally)) (tally-counters self))
(defmethod render ((self tally))
  (h1 () "Birds seen")
  (dolist (counter (tally-counters self))
    (render-component counter)))
(with-fresh-applications (("/tally" 'tally :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tally")
    (click b "more terns")
    (click b "more terns")
    (body-text b)))
;; ⇒ "Birds seen gulls: 0 more gulls terns: 2 more terns"

;;;; Example: littoral:component-id
;;; Every component gets an id of its own when it is made; AJAX updates find their element by it.
(let ((a (make-instance 'component))
      (b (make-instance 'component)))
  (list (stringp (component-id a))
        (string= (component-id a) (component-id a))
        (string= (component-id a) (component-id b))))
;; ⇒ (T T NIL)

;;;; Example: littoral:states
;;; Naming the component itself in states makes all its slots backtrack: going back to an earlier page and acting there starts from the state that page showed.
(defclass score (component)
  ((points :initform 0 :accessor points)))
(defmethod states ((self score)) (list self))
(defmethod render ((self score))
  (p () "Points: " (text (princ-to-string (points self))))
  (anchor (:callback (lambda () (incf (points self)))) "Score"))
(with-fresh-applications (("/score" 'score :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/score")
    (click b "Score")
    (let ((one-point (browser-url b)))
      (click b "Score")
      (click b "Score")
      (back-to b one-point)
      (click b "Score")
      (body-text b))))
;; ⇒ "Points: 2 Score"

;;;; Example: littoral:update-root littoral:html-root littoral:root-title littoral:add-stylesheet littoral:add-script littoral:add-style littoral:add-head-meta littoral:add-head-link
;;; A component fills in the page's head from update-root.  Calling the next method keeps what style and script give.
(defclass tide-page (component) ())
(defmethod update-root ((self tide-page) root)
  (call-next-method)
  (setf (root-title root) "Tides")
  (add-head-meta root "description" "Why the sea comes and goes.")
  (add-head-meta root "og:title" "Tides")
  (add-head-link root "icon" "/favicon.svg" :type "image/svg+xml")
  (add-stylesheet root "/css/site.css")
  (add-style root "h1 { color: navy }")
  (add-script root "/js/charts.js"))
(defmethod render ((self tide-page))
  (h1 () "Tides"))
(with-fresh-applications (("/tides" 'tide-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (mapcar (lambda (html) (not (null (search html (browser-html b)))))
            '("<title>Tides</title>"
              "<meta name=\"description\" content=\"Why the sea comes and goes.\">"
              "<meta property=\"og:title\" content=\"Tides\">"
              "<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">"
              "<link rel=\"stylesheet\" href=\"/css/site.css\">"
              "h1 { color: navy }"
              "<script src=\"/js/charts.js\" defer"))))
;; ⇒ (T T T T T T T)

;;;; Example: littoral:style littoral:script
;;; CSS a component needs goes in the page head; its JavaScript goes at the end of the body, with the page's script nonce.
(defclass chart (component) ())
(defmethod style ((self chart)) ".chart { height: 10rem }")
(defmethod script ((self chart)) "console.log('chart drawn')")
(defmethod render ((self chart))
  (div (:class "chart")))
(with-fresh-applications (("/chart" 'chart :mode :deployment))
  (let* ((b (make-instance 'browser))
         (html (browser-html (visit b "/chart"))))
    (list (< (search ".chart { height: 10rem }" html) (search "</head>" html))
          (< (search "<body" html) (search "console.log('chart drawn')" html)))))
;; ⇒ (T T)

;;;; Example: littoral:update-url littoral:initial-request littoral:page-url littoral:add-to-path littoral:add-parameter littoral:request-extra-path
;;; A page that can be bookmarked: update-url puts the tide table shown in the URL, and initial-request reads it back when a session starts from that URL.
(defclass harbours (component)
  ((harbour :initform nil :accessor harbour)
   (metric :initform nil :accessor metric)))
(defmethod states ((self harbours)) (list self))
(defmethod update-url ((self harbours) url)
  (when (harbour self)
    (add-to-path url (harbour self)))
  (when (metric self)
    (add-parameter url "metric")))
(defmethod initial-request ((self harbours) request)
  (setf (harbour self) (first (request-extra-path))
        (metric self) (request-parameter-p "metric" request)))
(defmethod render ((self harbours))
  (p () "Tides for " (text (or (harbour self) "nowhere"))
    (text (if (metric self) " in metres. " " in feet. ")))
  (anchor (:callback (lambda () (setf (harbour self) "Dover"))) "Dover")
  (text " ")
  (anchor (:callback (lambda () (setf (metric self) t))) "Metric"))
(with-fresh-applications (("/tides" 'harbours :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/tides")
    (click b "Dover")
    (click b "Metric")
    (let* ((url (browser-url b))
           (bookmark (subseq url 0 (search "&_s=" url)))
           (later (make-instance 'browser)))
      (visit later bookmark)
      (list bookmark (body-text later)))))
;; ⇒ ("/tides/Dover?metric" "Tides for Dover in metres. Dover Metric")

;;;; Example: littoral:url-path littoral:url-parameters
;;; What update-url methods have added so far.  Values are printed with princ, and a parameter may have no value.
(let ((url (make-instance 'page-url)))
  (add-to-path url "harbours" 42)
  (add-parameter url "metric")
  (add-parameter url "sort" :name)
  (list (url-path url) (url-parameters url)))
;; ⇒ (("harbours" "42") (("metric") ("sort" . "NAME")))

;;;; Example: littoral:updatable littoral:updatable-wrapper
;;; An updatable component is written inside an element carrying its component-id (removed here, as it differs every run), so AJAX can replace it.  updatable-wrapper chooses that element.
(defclass shopping-item (component updatable)
  ((name :initarg :name :reader item-name)))
(defmethod updatable-wrapper ((self shopping-item))
  (values "li" '(:aria-live "polite")))
(defmethod render ((self shopping-item))
  (text (item-name self)))
(let ((html (with-canvas-to-string ()
              (render-component (make-instance 'shopping-item :name "Milk")))))
  (cl-ppcre:regex-replace " id=\"[^\"]*\"" html ""))
;; ⇒ "<li class=\"lt-updatable\" aria-live=\"polite\">Milk</li>"

;;;; Example: littoral:call littoral:answer
;;; Outside a flow, call shows the other component in place of the caller and returns at once; when that component answers, the caller comes back.
(defclass inbox (component) ())
(defmethod render ((self inbox))
  (p () "Inbox")
  (anchor (:callback (lambda ()
                       (call self (make-instance 'message-dialog :message "No new mail."))))
    "Check mail"))
(with-fresh-applications (("/inbox" 'inbox :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/inbox")
    (click b "Check mail")
    (let ((dialog (body-text b)))
      (press b "OK")                    ; the message dialog answers T
      (list dialog (body-text b)))))
;; ⇒ ("No new mail. OK" "Inbox Check mail")

;;;; Example: littoral:answer littoral:show
;;; A component answers a value; show hands it to ON-ANSWER, which is how a callback acts on an answer.
(defclass colour-picker (component) ())
(defmethod render ((self colour-picker))
  (ul ()
    (dolist (colour '(:red :green :blue))
      (let ((colour colour))
        (li () (anchor (:callback (lambda () (answer self colour)))
                 (text (string-downcase colour))))))))
(defclass boat (component)
  ((colour :initform :white :accessor boat-colour)))
(defmethod states ((self boat)) (list self))
(defmethod render ((self boat))
  (p () "The boat is " (text (string-downcase (boat-colour self))) ". ")
  (anchor (:callback (lambda ()
                       (show self (make-instance 'colour-picker)
                             :on-answer (lambda (colour) (setf (boat-colour self) colour)))))
    "Paint it"))
(with-fresh-applications (("/boat" 'boat :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/boat")
    (click b "Paint it")
    (let ((picker (body-text b)))
      (click b "green")
      (list picker (body-text b)))))
;; ⇒ ("red green blue" "The boat is green. Paint it")

;;;; Example: littoral:home littoral:active-component littoral:visible-children
;;; While a component has shown another, that one is active in its place and is what it shows; home dismisses it without an answer.
(let* ((page (make-instance 'component))
       (dialog (make-instance 'confirm-dialog :message "Sure?")))
  (show page dialog)
  (list (eq (active-component page) dialog)
        (equal (visible-children page) (list dialog))
        (progn (home page)
               (eq (active-component page) page))))
;; ⇒ (T T T)
