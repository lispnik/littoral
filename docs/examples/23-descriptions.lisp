;;;; The examples for descriptions: fields, validation, editors, viewers and report columns.

;;;; Example: littoral:define-description littoral:validate
;;; Describe a class's fields once.  `validate` checks an object against its class's description and lists what is wrong, field by field.
(defclass guest ()
  ((name :initarg :name :initform nil)
   (email :initarg :email :initform nil)
   (age :initarg :age :initform nil)))
(define-description guest
  ((name :required t :max-length 40)
   (email :type :email :required t)
   (age :type :integer :min 0 :max 150)))
(validate (make-instance 'guest :email "ada@" :age 200))
;; ⇒ ((NAME . "Name is required.") (EMAIL . "Email must be an email address.") (AGE . "Age must be at most 150."))

;;;; Example: littoral:define-description littoral:validate
;;; `:validate` on the description checks the values together, as a plist keyed by keywords; it runs only once every field passes, and its problem comes back under `nil`.
(defclass booking ()
  ((plan :initarg :plan :initform :personal)
   (seats :initarg :seats :initform 1)))
(define-description booking
  ((plan :type :choice :choices '(:personal :team))
   (seats :type :integer :min 1))
  :validate (lambda (values)
              (when (and (eq (getf values :plan) :personal) (> (getf values :seats) 1))
                "A personal plan has one seat.")))
(list (validate (make-instance 'booking :seats 3))
      (validate (make-instance 'booking :plan :team :seats 3)))
;; ⇒ (((NIL . "A personal plan has one seat.")) NIL)

;;;; Example: littoral:define-description littoral:field-value
;;; A field reads and writes the slot of its name, unless given `:accessor` (a SETF-able function) or `:reader` and `:writer`.  `:label` names it on the page; the default comes from the property's name.
(defclass author ()
  ((names :initform (list "Mary" "Shelley") :accessor names)))
(defun full-name (author) (format nil "~{~A~^ ~}" (names author)))
(defun (setf full-name) (name author) (setf (names author) (uiop:split-string name)))
(define-description author
  ((full-name :accessor full-name :label "Name")))
(let ((author (make-instance 'author))
      (field (find-field 'author 'full-name)))
  (setf (field-value field author) "Mary Wollstonecraft Shelley")
  (list (field-value field author) (names author)))
;; ⇒ ("Mary Wollstonecraft Shelley" ("Mary" "Wollstonecraft" "Shelley"))

;;;; Example: littoral:find-description littoral:description littoral:description-fields littoral:find-field littoral:field littoral:field-name littoral:field-label
;;; A description is found by name, or from an object of its class.  Its fields are in the order given.
(defclass recipe ()
  ((title :initform "Scones")
   (serves :initform 8)))
(define-description recipe
  ((title :required t)
   (serves :type :integer :label "Serves")))
(let ((description (find-description (make-instance 'recipe))))
  (list (typep description 'description)
        (mapcar #'field-name (description-fields description))
        (mapcar #'field-label (description-fields description))
        (type-of (find-field 'recipe 'serves))))
;; ⇒ (T (TITLE SERVES) ("Title" "Serves") INTEGER-FIELD)

;;;; Example: littoral:parse-field littoral:format-field littoral:check-field
;;; Each field kind turns typed text into a value (`parse-field`), a value back into text (`format-field`), and says what is wrong with a value (`check-field`).  Blank input is `nil`.
(defclass reading ()
  ((taken :initform nil)
   (level :initform nil)))
(define-description reading
  ((taken :type :date :required t)
   (level :type :integer :min 0 :max 10)))
(let ((taken (find-field 'reading 'taken))
      (level (find-field 'reading 'level)))
  (list (parse-field taken " 2026-10-06 ")
        (format-field taken '(2026 10 6))
        (parse-field level "  ")
        (check-field level 11)
        (check-field taken nil)))
;; ⇒ ((2026 10 6) "2026-10-06" NIL "Level must be at most 10." "Taken is required.")

;;;; Example: littoral:field-error littoral:parse-field
;;; Text that is not a value of the field's kind signals `field-error`, whose message is what an editor shows.
(defclass delivery ()
  ((due :initform nil)))
(define-description delivery
  ((due :type :date)))
(handler-case (parse-field (find-field 'delivery 'due) "2026-02-30")
  (field-error (e) (princ-to-string e)))
;; ⇒ "Due must be a date, like 2026-10-06."

;;;; Example: littoral:string-field littoral:email-field littoral:url-field
;;; Text fields take `:max-length` and `:pattern` (a regular expression for the whole value, with `:pattern-message` to explain it).  Email and URL fields are text fields with a pattern of their own.
(defclass shop ()
  ((code :initform nil)
   (contact :initform nil)
   (site :initform nil)))
(define-description shop
  ((code :pattern "[A-Z]{3}" :pattern-message "A code is three capital letters.")
   (contact :type :email)
   (site :type :url)))
(flet ((check (name value) (check-field (find-field 'shop name) value)))
  (list (check 'code "AB1")
        (check 'code "ABC")
        (check 'contact "shop.example.org")
        (check 'site "javascript:alert(1)")))
;; ⇒ ("A code is three capital letters." NIL "Contact must be an email address." "Site must be a web address starting http:// or https://.")

;;;; Example: littoral:text-field littoral:render-field-value
;;; A text field holds several lines; it is shown with a line break after each.
(defclass memo ()
  ((body :initform nil)))
(define-description memo
  ((body :type :text)))
(let ((field (find-field 'memo 'body)))
  (with-canvas-to-string ()
    (render-field-value field (parse-field field (format nil "Buy milk.~%Call Ada.~%~%")))))
;; ⇒ "Buy milk.<br>Call Ada.<br>"

;;;; Example: littoral:integer-field
;;; Whole numbers, between `:min` and `:max` when given.
(defclass parcel ()
  ((weight :initform nil)))
(define-description parcel
  ((weight :type :integer :min 1 :max 30 :label "Weight (kg)")))
(let ((field (find-field 'parcel 'weight)))
  (list (parse-field field " 12 ")
        (check-field field 0)
        (handler-case (parse-field field "twelve")
          (field-error (e) (princ-to-string e)))))
;; ⇒ (12 "Weight (kg) must be at least 1." "Weight (kg) must be a whole number.")

;;;; Example: littoral:boolean-field
;;; Yes or no, entered as a checkbox: "on" is true, anything else false.
(defclass alert ()
  ((urgent :initform nil)))
(define-description alert
  ((urgent :type :boolean)))
(let ((field (find-field 'alert 'urgent)))
  (list (parse-field field "on") (parse-field field "off") (format-field field t) (check-field field nil)))
;; ⇒ (T NIL "Yes" NIL)

;;;; Example: littoral:choice-field littoral:field-choices
;;; One of `:choices`, shown through `:labels`.  The input posts the chosen item's position; its label means it too.
(defclass ticket ()
  ((priority :initform :normal)))
(define-description ticket
  ((priority :type :choice :choices '(:low :normal :high) :labels #'string-capitalize)))
(let ((field (find-field 'ticket 'priority)))
  (list (field-choices field)
        (parse-field field "2")
        (parse-field field "Low")
        (format-field field :normal)))
;; ⇒ ((:LOW :NORMAL :HIGH) :HIGH :LOW "Normal")

;;;; Example: littoral:choice-field littoral:field-choices
;;; `:choices` may be a function, called whenever the choices are needed, so they can change while a form is open.
(defclass assignment ()
  ((assignee :initform nil)))
(defvar *team* (list "Ada" "Grace"))
(define-description assignment
  ((assignee :type :choice :choices (lambda () *team*))))
(let ((field (find-field 'assignment 'assignee)))
  (let ((*team* (list "Ada" "Grace" "Alan")))
    (field-choices field)))
;; ⇒ ("Ada" "Grace" "Alan")

;;;; Example: littoral:date-field
;;; A calendar date, held as (`year` `month` `day`) and written like 2026-07-01.
(defclass trip ()
  ((leaves :initform '(2026 7 1))))
(define-description trip
  ((leaves :type :date)))
(let ((field (find-field 'trip 'leaves)))
  (list (format-field field (field-value field (make-instance 'trip)))
        (parse-field field "2028-2-29")))
;; ⇒ ("2026-07-01" (2028 2 29))

;;;; Example: littoral:password-field littoral:field-hidden-p littoral:make-viewer littoral:description-viewer
;;; A viewer shows an object's described values in a table, with a Close link that answers.  Password fields and `:hidden` fields are left out (and so are they from reports); hidden fields are left out of editors too.
(defclass account ()
  ((login :initform "ada")
   (secret :initform "correct horse")
   (token :initform "x7f3")))
(define-description account
  ((login :required t)
   (secret :type :password)
   (token :hidden t)))
(defclass account-page (component) ())
(defmethod render ((self account-page))
  (render-component (make-viewer (make-instance 'account))))
(with-fresh-applications (("/account" 'account-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/account")
    (list (body-text b) (field-hidden-p (find-field 'account 'token)))))
;; ⇒ ("Login ada Close" T)

;;;; Example: littoral:make-editor littoral:description-editor
;;; An editor is a form made from the description.  Save checks every field and shows the problems beside them; once they pass it writes the values to the object and answers it.  Cancel answers `nil` and leaves the object alone.
(defclass guest ()
  ((name :initarg :name :initform nil)
   (email :initarg :email :initform nil)))
(define-description guest
  ((name :required t)
   (email :type :email :required t)))
(defclass guest-page (component)
  ((guest :initform (make-instance 'guest :name "Ada" :email "ada@example.org") :reader guest)))
(defmethod render ((self guest-page))
  (p () (text (slot-value (guest self) 'name)))
  (anchor (:callback (lambda () (show self (make-editor (guest self) :title "Edit guest")))) "Edit"))
(with-fresh-applications (("/guest" 'guest-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/guest")
    (click b "Edit")
    (fill-in b "name" "Ada Lovelace")
    (fill-in b "email" "nowhere")
    (press b "Save")
    (let ((problem (not (null (has-text-p b "Email must be an email address.")))))
      (fill-in b "email" "ada@lovelace.org")
      (press b "Save")
      (list problem (body-text b)))))
;; ⇒ (T "Ada Lovelace Edit")

;;;; Example: littoral:make-editor
;;; With `:write` `nil` the editor leaves the object alone and answers the values as a plist, for the application to store as it sees fit.
(defclass topic ()
  ((title :initform "Lunch")
   (notes :initform nil)))
(define-description topic
  ((title :required t)
   (notes :type :text)))
(defclass topic-page (component)
  ((topic :initform (make-instance 'topic) :reader topic)
   (answer :initform nil :accessor editor-answer)))
(defmethod render ((self topic-page))
  (p () (text (prin1-to-string (editor-answer self))))
  (anchor (:callback (lambda ()
                       (show self (make-editor (topic self) :write nil :save-label "Propose")
                             :on-answer (lambda (values) (setf (editor-answer self) values)))))
    "Change"))
(with-fresh-applications (("/topic" 'topic-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/topic")
    (click b "Change")
    (fill-in b "title" "Dinner")
    (press b "Propose")
    (list (body-text b) (slot-value (topic (make-instance 'topic-page)) 'title))))
;; ⇒ ("(:TITLE \"Dinner\" :NOTES NIL) Change" "Lunch")

;;;; Example: littoral:description-columns
;;; Report columns made from a description: each shows its field the way a viewer does and sorts by its value.  Name fields to choose them; without names, every field not marked `:in-report` `nil`.
(defclass book ()
  ((title :initarg :title)
   (year :initarg :year)
   (blurb :initarg :blurb :initform "")))
(define-description book
  ((title :required t)
   (year :type :integer)
   (blurb :type :text :in-report nil)))
(defclass shelf (report) ()
  (:default-initargs
   :rows (list (make-instance 'book :title "Emma" :year 1815)
               (make-instance 'book :title "Persuasion" :year 1817)
               (make-instance 'book :title "Ivanhoe" :year 1819))
   :columns (description-columns 'book)))
(with-fresh-applications (("/shelf" 'shelf :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/shelf")
    (click b "Title")
    (body-text b)))
;; ⇒ "Title ▲ Year Emma 1815 Ivanhoe 1819 Persuasion 1817"

;;;; Example: littoral:*field-kinds* littoral:field-problem littoral:parse-field littoral:format-field
;;; A field kind of your own: a class with methods for what differs, under a keyword in `*field-kinds*`.  `field-problem` signals the `field-error` that rejects input.  (Push onto `*field-kinds*` in your own code; the `let` keeps this example tidy.)
(defclass postcode-field (string-field) ())
(defmethod parse-field ((field postcode-field) string)
  (let ((code (string-upcase (remove #\Space string))))
    (cond ((string= code "") nil)
          ((<= 5 (length code) 7)
           (format nil "~A ~A" (subseq code 0 (- (length code) 3)) (subseq code (- (length code) 3))))
          (t (field-problem "~A is not a postcode." (translate (field-label field)))))))
(defclass address ()
  ((postcode :initform nil)))
(let ((*field-kinds* (acons :postcode 'postcode-field *field-kinds*)))
  (define-description address
    ((postcode :type :postcode :required t))))
(let ((field (find-field 'address 'postcode)))
  (list (parse-field field "sw1a2aa")
        (handler-case (parse-field field "12")
          (field-error (e) (princ-to-string e)))))
;; ⇒ ("SW1A 2AA" "Postcode is not a postcode.")

;;;; Example: littoral:render-field-input littoral:render-field-value littoral:check-field
;;; `render-field-input` writes the input an editor shows: give the input the `id`, start it from `text`, and pass `callback` what is submitted.  `render-field-value` writes a value for reading.  A `check-field` method adds a check, keeping the general ones with `call-next-method`.
(defclass pence-field (integer-field) ())
(defmethod render-field-input ((field pence-field) id text callback)
  (text-input (:id id :value text :callback callback :inputmode "numeric" :placeholder "pence")))
(defmethod render-field-value ((field pence-field) value)
  (when value (text (format nil "£~D.~2,'0D" (floor value 100) (mod value 100)))))
(defmethod check-field ((field pence-field) value)
  (or (call-next-method)
      (when (and value (not (zerop (mod value 5))))
        "Prices end in 0 or 5.")))
(defclass item ()
  ((price :initform 1250)))
(let ((*field-kinds* (acons :pence 'pence-field *field-kinds*)))
  (define-description item
    ((price :type :pence :required t))))
(defclass price-page (component)
  ((item :initform (make-instance 'item) :reader item)))
(defmethod render ((self price-page))
  (render-component (make-viewer (item self)))
  (anchor (:callback (lambda () (show self (make-editor (item self))))) "Edit"))
(with-fresh-applications (("/price" 'price-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/price")
    (let ((before (body-text b)))
      (click b "Edit")
      (let ((input (not (null (search "inputmode=\"numeric\"" (browser-html b))))))
        (fill-in b "price" "1999")
        (press b "Save")
        (list before input (not (null (has-text-p b "Prices end in 0 or 5."))))))))
;; ⇒ ("Price £12.50 Close Edit" T T)

;;;; Example: littoral:description-label littoral:description-plural littoral:english-plural
;;; A description names its objects for pages such as the admin's: by default from the class name, with the English plural of the last word.  `:label` and `:plural` say otherwise.
(defclass reading-shelf () ((title :initarg :title :initform nil)))
(defclass cactus () ((kind :initarg :kind :initform nil)))
(list (let ((shelves (define-description reading-shelf ((title)))))
        (list (description-label shelves) (description-plural shelves)))
      (description-plural (define-description cactus ((kind)) :plural "Cacti"))
      (english-plural "Person"))
;; ⇒ (("Reading Shelf" "Reading Shelves") "Cacti" "People")
