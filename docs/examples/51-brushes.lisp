;;;; The examples for brushes: links, forms, fields and buttons that call back into the session.

;;;; Example: littoral.html:anchor littoral.test:click
;;; A link whose :CALLBACK, a function of no arguments, runs when it is followed; the page is then rendered again.
(defclass counter (component)
  ((count :initform 0 :accessor count-of)))
(defmethod render ((self counter))
  (p () (text (count-of self)))
  (anchor (:callback (lambda () (incf (count-of self)))) "Add one"))
(with-fresh-applications (("/counter" 'counter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/counter")
    (click b "Add one")
    (click b "Add one")
    (body-text b)))
;; ⇒ "2 Add one"

;;;; Example: littoral.html:anchor
;;; Without a callback, :HREF makes a plain link, and other attributes are written as given.  :LABEL becomes aria-label.
(with-canvas-to-string ()
  (anchor (:href "https://sbcl.org/" :rel "external" :label "SBCL's site") "SBCL"))
;; ⇒ "<a href=\"https://sbcl.org/\" rel=\"external\" aria-label=\"SBCL&#39;s site\">SBCL</a>"

;;;; Example: littoral.html:form littoral.html:text-input littoral.html:submit-button littoral.test:fill-in littoral.test:press
;;; A form posts back to the session.  Each field's :CALLBACK receives what was typed; then the :CALLBACK of the button pressed runs.  Fields are found in tests by their :ID.
(defclass greeter (component)
  ((name :initform "" :accessor name-of)
   (greeting :initform nil :accessor greeting-of)))
(defmethod render ((self greeter))
  (form ()
    (label (:for "name") "Name")
    (text-input (:id "name" :value (name-of self)
                 :callback (lambda (value) (setf (name-of self) value))))
    (submit-button (:callback (lambda () (setf (greeting-of self) (format nil "Hello, ~A!" (name-of self)))))
      "Greet"))
  (when (greeting-of self)
    (p () (text (greeting-of self)))))
(with-fresh-applications (("/greet" 'greeter :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/greet")
    (fill-in b "name" "Ada")
    (press b "Greet")
    (body-text b)))
;; ⇒ "Name Greet Hello, Ada!"

;;;; Example: littoral.html:password-input littoral.html:cancel-button
;;; A password field never shows a :VALUE unless you give it one.  A cancel button runs its callback and nothing else: what was typed is not applied.
(defclass sign-in (component)
  ((password :initform nil :accessor password-of)
   (outcome :initform "" :accessor outcome-of)))
(defmethod render ((self sign-in))
  (form ()
    (password-input (:id "password" :autocomplete "current-password"
                     :callback (lambda (value) (setf (password-of self) value))))
    (submit-button (:callback (lambda () (setf (outcome-of self) (format nil "Got ~D characters." (length (password-of self))))))
      "Sign in")
    (cancel-button (:callback (lambda () (setf (outcome-of self) (format nil "Cancelled; password ~S." (password-of self)))))
      "Cancel"))
  (p () (text (outcome-of self))))
(with-fresh-applications (("/sign-in" 'sign-in :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/sign-in")
    (fill-in b "password" "hunter2")
    (press b "Cancel")
    (let ((cancelled (body-text b)))
      (fill-in b "password" "hunter2")
      (press b "Sign in")
      (list cancelled (body-text b)))))
;; ⇒ ("Sign in Cancel Cancelled; password NIL." "Sign in Cancel Got 7 characters.")

;;;; Example: littoral.html:number-input
;;; The callback receives an integer, or NIL when what was submitted is not one.
(defclass quantity (component)
  ((amount :initform 1 :accessor amount-of)))
(defmethod render ((self quantity))
  (form ()
    (number-input (:id "amount" :min 1 :value (or (amount-of self) "")
                   :callback (lambda (n) (setf (amount-of self) n))))
    (submit-button () "Update"))
  (p () (text (if (amount-of self) (format nil "~D in the basket" (amount-of self)) "Not a number"))))
(with-fresh-applications (("/quantity" 'quantity :mode :deployment))
  (let ((b (make-instance 'browser)) (seen '()))
    (visit b "/quantity")
    (dolist (typed '("3" "three"))
      (fill-in b "amount" typed)
      (press b "Update")
      (push (body-text b) seen))
    (reverse seen)))
;; ⇒ ("Update 3 in the basket" "Update Not a number")

;;;; Example: littoral.html:hidden-input
;;; A hidden field sends back its :VALUE, here the version of the record the form was rendered from.
(defclass versioned-note (component)
  ((version :initform 7 :accessor version-of)
   (submitted :initform nil :accessor submitted-of)))
(defmethod render ((self versioned-note))
  (form ()
    (hidden-input (:value (version-of self)
                   :callback (lambda (value) (setf (submitted-of self) value))))
    (submit-button () "Save"))
  (p () "Submitted version: " (text (submitted-of self))))
(with-fresh-applications (("/note" 'versioned-note :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/note")
    (press b "Save")
    (body-text b)))
;; ⇒ "Save Submitted version: 7"

;;;; Example: littoral.html:text-area
;;; A multi-line field showing :VALUE, escaped, and passing the submitted text to :CALLBACK.
(defclass notes (component)
  ((body :initform "Bring <cake>" :accessor body-of)))
(defmethod render ((self notes))
  (form ()
    (text-area (:id "body" :rows 4 :value (body-of self)
                :callback (lambda (value) (setf (body-of self) value))))
    (submit-button () "Save"))
  (p () (text (length (body-of self))) " characters"))
(with-fresh-applications (("/notes" 'notes :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/notes")
    (let ((field (not (null (search "&lt;cake&gt;</textarea>" (browser-html b))))))
      (fill-in b "body" (format nil "Bring cake~%and tea"))
      (press b "Save")
      (list field (body-text b)))))
;; ⇒ (T "Bring cake and tea Save 18 characters")

;;;; Example: littoral.html:checkbox littoral.test:set-checkbox
;;; :VALUE is whether the box is checked; :CALLBACK receives T or NIL.  An unchecked box still reports NIL, as the brush writes a hidden twin.  In tests, SET-CHECKBOX picks boxes by their position on the page.
(defclass preferences (component)
  ((newsletter :initform nil :accessor newsletter-p)
   (digest :initform t :accessor digest-p)))
(defmethod render ((self preferences))
  (form ()
    (label () (checkbox (:value (newsletter-p self) :callback (lambda (on) (setf (newsletter-p self) on))))
      "Newsletter")
    (label () (checkbox (:value (digest-p self) :callback (lambda (on) (setf (digest-p self) on))))
      "Weekly digest")
    (submit-button () "Save"))
  (p () (text (list (newsletter-p self) (digest-p self)))))
(with-fresh-applications (("/prefs" 'preferences :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/prefs")
    (set-checkbox b 0 t)
    (set-checkbox b 1 nil)
    (press b "Save")
    (body-text b)))
;; ⇒ "Newsletter Weekly digest Save (T NIL)"

;;;; Example: littoral.html:select-list littoral.test:select-option
;;; A drop-down of :ITEMS, which may be any objects: :LABELS turns one into its text, :SELECTED is the one shown chosen (compared with :TEST, default EQL), and :CALLBACK receives the item chosen.
(defclass shipping (component)
  ((carrier :initform :post :accessor carrier-of)))
(defmethod render ((self shipping))
  (form ()
    (select-list (:id "method" :items '(:post :courier :collect)
                  :labels (lambda (item) (string-capitalize item))
                  :selected (carrier-of self)
                  :callback (lambda (item) (setf (carrier-of self) item))))
    (submit-button () "Choose"))
  (p () "Shipping by " (text (string-downcase (carrier-of self)))))
(with-fresh-applications (("/ship" 'shipping :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/ship")
    (select-option b "method" "Courier")
    (press b "Choose")
    (body-text b)))
;; ⇒ "Post Courier Collect Choose Shipping by courier"

;;;; Example: littoral.html:radio-group
;;; One radio button per item, inside a span of class lt-radio-group; it takes the same keywords as SELECT-LIST.  Outside a request, as here, callback names are numbered from 1.
(with-canvas-to-string ()
  (radio-group (:items '(1 2 3) :selected 2 :labels (lambda (n) (format nil "~D star~:P" n))
                :callback (lambda (n) (print n)))))
;; ⇒ "<span class=\"lt-radio-group\"><label><input type=\"radio\" name=\"1\" value=\"0\">1 star</label><label><input type=\"radio\" name=\"1\" value=\"1\" checked>2 stars</label><label><input type=\"radio\" name=\"1\" value=\"2\">3 stars</label></span>"

;;;; Example: littoral.html:radio-group littoral.test:choose-radio
;;; The submitted choice reaches :CALLBACK as the item itself.  The fake browser's choose-radio clicks a button by its label.
(defclass size-picker (component)
  ((size :initform :small :accessor size-of)))
(defmethod render ((self size-picker))
  (form ()
    (radio-group (:id "size" :items '(:small :medium :large) :selected (size-of self)
                  :labels #'string-downcase
                  :callback (lambda (size) (setf (size-of self) size))))
    (submit-button () "Pick"))
  (p () "Size: " (text (size-of self))))
(with-fresh-applications (("/size" 'size-picker :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/size")))
    (choose-radio b "large")
    (press b "Pick")
    (body-text b)))
;; ⇒ "small medium large Pick Size: LARGE"

;;;; Example: littoral.html:form littoral.test:form-action littoral.test:encode-fields
;;; :DEFAULT-ACTION runs when the form is submitted without a button, as when Enter is pressed in a field of a form whose buttons all have callbacks.  The fake browser's PRESS always names a button, so the test posts the fields itself.
(defclass search-box (component)
  ((query :initform "" :accessor query-of)
   (results :initform nil :accessor results-of)))
(defmethod render ((self search-box))
  (form (:role "search" :default-action (lambda () (setf (results-of self) (format nil "Results for ~A" (query-of self)))))
    (text-input (:id "q" :callback (lambda (value) (setf (query-of self) value))))
    (submit-button (:callback (lambda () (setf (results-of self) "Feeling lucky"))) "Lucky"))
  (p () (text (results-of self))))
(with-fresh-applications (("/search" 'search-box :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/search")))
    (fill-in b "q" "lisp")
    (visit b (form-action b) :method :post :body (encode-fields (browser-fields b)))
    (body-text b)))
;; ⇒ "Lucky Results for lisp"

;;;; Example: littoral.html:file-input littoral.html:uploaded-file littoral.html:file-name littoral.html:file-content-type littoral.html:file-contents littoral.test:attach-file
;;; A file chooser needs a form with :MULTIPART T.  Its :CALLBACK receives an UPLOADED-FILE, whose bytes are an octet vector, and is not called when no file was chosen.
(defclass uploader (component)
  ((report :initform "Nothing yet" :accessor report-of)))
(defmethod render ((self uploader))
  (form (:multipart t)
    (file-input (:id "file" :accept "text/*"
                 :callback (lambda (file)
                             (setf (report-of self)
                                   (format nil "~A (~A): ~D bytes, starting ~S"
                                           (file-name file) (file-content-type file)
                                           (length (file-contents file))
                                           (code-char (aref (file-contents file) 0)))))))
    (submit-button () "Upload"))
  (p () (text (report-of self))))
(with-fresh-applications (("/upload" 'uploader :mode :deployment))
  (let ((b (visit (make-instance 'browser) "/upload")))
    (attach-file b "file" "notes.txt" "text/plain" "Hello, world")
    (press b "Upload")
    (body-text b)))
;; ⇒ "Upload notes.txt (text/plain): 12 bytes, starting #\\H"

;;;; Example: littoral.html:button littoral.test:ajax-specs littoral.test:ajax-request
;;; A button that submits nothing; it is for an AJAX :ON-CLICK, which runs its callback in the background and re-renders the components to :UPDATE.  Those components must be UPDATABLE.
(defclass likes (updatable component)
  ((count :initform 0 :accessor count-of)))
(defmethod render ((self likes))
  (span () (text (count-of self)) " likes")
  (button (:class "like" :on-click (ajax :callback (lambda () (incf (count-of self))) :update self))
    "Like"))
(with-fresh-applications (("/likes" 'likes :mode :deployment))
  (let* ((b (visit (make-instance 'browser) "/likes"))
         (spec (first (ajax-specs b "on-click"))))
    (ajax-request b (first spec) (rest spec))
    (ajax-request b (first spec) (rest spec))
    (visit b (browser-url b))             ; reload: the change stayed
    (body-text b)))
;; ⇒ "2 likes Like"
