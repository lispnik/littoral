;;;; The examples for littoral.test: the fake browser and what it reads and does.

;;;; Example: littoral.test:browser littoral.test:visit littoral.test:browser-status littoral.test:browser-url
;;; A browser calls the application in-process, with no server.  VISIT follows redirects and returns the browser; the URL it ends on carries the session and page keys.
(defclass hello (component) ())
(defmethod render ((self hello))
  (h1 () "Hello"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/hello")))
    (list (browser-status b)
          (not (null (search "/hello?_s=" (browser-url b))))
          (browser-status (visit b "/nowhere")))))
;; ⇒ (200 T 404)

;;;; Example: littoral.test:browser-app
;;; By default a browser drives every registered application, through MAKE-LACK-APP.  :APP gives it any Lack application instead, such as one wrapped in middleware.
(let ((b (make-instance 'browser
                        :app (lambda (env)
                               (list 200 '(:content-type "text/plain")
                                     (list (format nil "You asked for ~A" (getf env :path-info))))))))
  (visit b "/ping")
  (browser-html b))
;; ⇒ "You asked for /ping"

;;;; Example: littoral.test:browser-html littoral.test:page-text littoral.test:has-text-p
;;; BROWSER-HTML is the page as served; PAGE-TEXT is all its text, the title in the head included; HAS-TEXT-P searches that text.
(defclass hello (component) ())
(defmethod render ((self hello))
  (h1 () "Hello & welcome"))
(with-fresh-applications (("/hello" 'hello :mode :deployment :title "Greeter"))
  (let ((b (visit (make-instance 'browser) "/hello")))
    (list (not (null (search "<h1>Hello &amp; welcome</h1>" (browser-html b))))
          (not (null (has-text-p b "Hello & welcome")))
          (not (null (search "<title>Greeter</title>" (browser-html b))))
          (not (null (has-text-p b "Greeter"))))))
;; ⇒ (T T T T)

;;;; Example: littoral.test:body-text
;;; The text of the body alone, as a reader sees it: a space where a block, list item, cell or form control starts or ends, none around inline elements such as strong and a, and each run of whitespace made one space.
(defclass planets (component) ())
(defmethod render ((self planets))
  (h1 () "Planets")
  (p () "The " (strong () "inner") " ones:")
  (ul () (li () "Mercury") (li () "Venus"))
  (table () (tr () (th () "Largest") (td () "Jupiter")))
  (anchor (:href "/more") "More…"))
(with-fresh-applications (("/planets" 'planets :mode :deployment :title "Space"))
  (body-text (visit (make-instance 'browser) "/planets")))
;; ⇒ "Planets The inner ones: Mercury Venus Largest Jupiter More…"

;;;; Example: littoral.test:browser-headers
;;; :HEADERS are sent with every request, here to ask for French; the application offers it with :LANGUAGES.
(defclass trash (component) ())
(defmethod render ((self trash))
  (submit-button () (translate "Remove")))
(with-fresh-applications (("/trash" 'trash :mode :deployment :languages '("fr")))
  (let ((b (make-instance 'browser :headers '(("accept-language" . "fr-CA,fr;q=0.9")))))
    (visit b "/trash")
    (body-text b)))
;; ⇒ "Supprimer"

;;;; Example: littoral.test:browser-cookies
;;; The cookies the browser keeps, an alist of name and value, sent with each request.  A cookie set with MAX-AGE 0 is dropped.
(defclass theme-picker (component) ())
(defmethod render ((self theme-picker))
  (anchor (:callback (lambda () (set-cookie "theme" "dark" :max-age 3600))) "Dark")
  (anchor (:callback (lambda () (set-cookie "theme" "" :max-age 0))) "Default"))
(with-fresh-applications (("/theme" 'theme-picker :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/theme")))
    (click b "Dark")
    (let ((chosen (assoc "theme" (browser-cookies b) :test #'string=)))
      (click b "Default")
      (list chosen (assoc "theme" (browser-cookies b) :test #'string=)))))
;; ⇒ (("theme" . "dark") NIL)

;;;; Example: littoral.test:browser-fields littoral.test:element-name
;;; A field's name is its callback's id, which changes from page to page, so tests find fields by DOM id.  BROWSER-FIELDS holds what the next PRESS submits: the page's own values, then what was typed.
(defclass profile (component)
  ((city :initform "Lyon" :accessor city-of)))
(defmethod render ((self profile))
  (form ()
    (text-input (:id "city" :value (city-of self) :callback (lambda (v) (setf (city-of self) v))))
    (submit-button () "Save")))
(with-fresh-applications (("/profile" 'profile :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/profile"))
         (name (element-name b "city")))
    (flet ((city () (rest (assoc name (browser-fields b) :test #'string=))))
      (let ((before (city)))
        (fill-in b "city" "Nantes")
        (list before (city))))))
;; ⇒ ("Lyon" "Nantes")

;;;; Example: littoral.test:browser-files
;;; Files chosen with ATTACH-FILE wait in BROWSER-FILES, as (FILENAME CONTENT-TYPE OCTETS) under the field's name, until the next PRESS sends them.
(defclass avatar (component) ())
(defmethod render ((self avatar))
  (form (:multipart t)
    (file-input (:id "picture" :callback (lambda (file) (declare (ignore file)))))
    (submit-button () "Upload")))
(with-fresh-applications (("/avatar" 'avatar :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/avatar")))
    (attach-file b "picture" "me.png" "image/png" #(137 80 78 71))
    (let ((waiting (rest (first (browser-files b)))))
      (press b "Upload")
      (list (subseq waiting 0 2) (length (third waiting)) (browser-files b)))))
;; ⇒ (("me.png" "image/png") 4 NIL)

;;;; Example: littoral.test:raw-request littoral.test:response-header
;;; One request with no redirects followed, returning the status, the header plist and the body.  Cookies are kept as VISIT keeps them.
(defclass hello (component) ())
(defmethod render ((self hello))
  (p () "Hi"))
(with-fresh-applications (("/hello" 'hello :mode :deployment))
  (let ((b (make-instance 'browser)))
    (multiple-value-bind (status headers body) (raw-request b :get "/hello")
      (list status
            (not (null (search "/hello?_s=" (response-header headers :location))))
            body
            (response-header headers :cache-control)))))
;; ⇒ (302 T "" "no-store")

;;;; Example: littoral.test:make-env
;;; The Lack environment a request would make, to call an application with directly.
(let ((env (make-env :post "/search?page=2" :body "q=lisp"
                     :extra-headers '(("Accept-Language" . "de")))))
  (list (getf env :request-method) (getf env :path-info) (getf env :query-string)
        (getf env :content-length) (gethash "accept-language" (getf env :headers))))
;; ⇒ (:POST "/search" "page=2" 6 "de")

;;;; Example: littoral.test:back-to
;;; Going back to an earlier page and acting on it, as the back button does.  The counter's STATES make its count backtrack, so the earlier page acts on the count it showed.
(defclass counter (component)
  ((count :initform 0 :accessor count-of)))
(defmethod states ((self counter))
  (list self))
(defmethod render ((self counter))
  (p () (text (count-of self)))
  (anchor (:callback (lambda () (incf (count-of self)))) "Add one"))
(with-fresh-applications (("/counter" 'counter :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/counter")))
    (click b "Add one")
    (let ((at-one (browser-url b)))
      (click b "Add one")
      (click b "Add one")
      (back-to b at-one)
      (click b "Add one")
      (body-text b))))
;; ⇒ "2 Add one"

;;;; Example: littoral.test:find-link littoral.test:find-links littoral.test:click-nth
;;; FIND-LINK gives the href of the first link whose text contains a string; FIND-LINKS those whose text is exactly it.  CLICK-NTH follows one of the latter, counting from 0.
(defclass shopping-list (component)
  ((items :initform (list "Bread" "Milk" "Eggs") :accessor items-of)))
(defmethod render ((self shopping-list))
  (ul ()
    (dolist (item (items-of self))
      (li () (text item) " "
        (anchor (:callback (lambda () (setf (items-of self) (remove item (items-of self) :test #'string=))))
          "Remove"))))
  (anchor (:href "/help") "Help with lists"))
(with-fresh-applications (("/list" 'shopping-list :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/list")))
    (let ((help (find-link b "Help"))
          (removes (length (find-links b "Remove"))))
      (click-nth b "Remove" 1)
      (list help removes (body-text b)))))
;; ⇒ ("/help" 3 "Bread Remove Eggs Remove Help with lists")

;;;; Example: littoral.test:attributes littoral.test:attr
;;; Reading the attributes of a start tag, the part after its name, as the fake browser's own regular expressions capture it: an alist of lower-cased names to unescaped values, with NIL for a bare attribute.
(let ((a (attributes " type=\"checkbox\" name=\"7\" title=\"Fish &amp; chips\" checked")))
  (list a (attr a "title")))
;; ⇒ ((("type" . "checkbox") ("name" . "7") ("title" . "Fish & chips") ("checked")) "Fish & chips")

;;;; Example: littoral.test:strip-tags littoral.test:unescape
;;; STRIP-TAGS removes markup, scripts and style sheets, then undoes the escapes Littoral writes, which is what UNESCAPE does alone.
(list (strip-tags "<p>Fish &amp; <b>chips</b></p><script>if (a < b) go();</script>")
      (unescape "&lt;a href=&quot;/&quot;&gt; &#39;home&#39;"))
;; ⇒ ("Fish & chips" "<a href=\"/\"> 'home'")

;;;; Example: littoral.test:sink littoral.test:open-stream littoral.test:sink-text littoral.test:wait-for
;;; Server push in a test: OPEN-STREAM opens the page's event stream in a thread writing into a SINK, and WAIT-FOR polls until what was pushed arrives.  CLOSE-EVENT-STREAMS ends the stream and its thread.
(defvar *scores* (make-channel "scores"))
(defvar *score* 0)
(defclass scoreboard (updatable component) ())
(defmethod subscriptions ((self scoreboard))
  (list *scores*))
(defmethod render ((self scoreboard))
  (p () "Score: " (text *score*)))
(with-fresh-applications (("/score" 'scoreboard :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/score"))
         (sink (make-instance 'sink))
         (thread (open-stream b sink)))
    (unwind-protect
         (list (wait-for (lambda () (search "retry:" (sink-text sink))) 2)
               (progn (setf *score* 3)
                      (publish *scores*)
                      (wait-for (lambda () (search "Score: 3" (sink-text sink))) 2))
               (not (null (search "event: update" (sink-text sink)))))
      (close-event-streams)
      (sb-thread:join-thread thread :default nil :timeout 2))))
;; ⇒ (T T T)

;;;; Example: littoral.test:with-fresh-applications
;;; Registers applications for the body only, each with REGISTER-APPLICATION's arguments, hiding any others.
(defclass hello (component) ())
(defmethod render ((self hello))
  (p () "Hi"))
(list (with-fresh-applications (("/one" 'hello :mode :deployment)
                                ("/two" 'hello :mode :deployment))
        (mapcar #'application-path (list-applications)))
      (find-application "/one"))
;; ⇒ (("/one" "/two") NIL)
