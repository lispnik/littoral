;;;; The examples for the newer field kinds (sliders, steppers, ratings, colours, multiple choices, transfer lists, new passwords), popovers, tooltips, drawers and split panes.

;;;; Example: littoral:stepper-field littoral:range-field
;;; `:stepper` puts − and + buttons either side of a number box; `:range` is a slider with the number beside it.  Both go in steps of `:step` within `:min` and `:max`.  Without JavaScript the buttons submit the form, and the page comes back with the number changed, kept within its limits.
(defclass order ()
  ((copies :initarg :copies)
   (volume :initarg :volume :initform 6)))
(define-description order
  ((copies :type :stepper :min 1 :max 5)
   (volume :type :range :max 10 :step 2)))
(defclass order-page (component)
  ((editor :initform (make-editor (make-instance 'order :copies 4)) :reader editor)))
(defmethod children ((self order-page)) (list (editor self)))
(defmethod render ((self order-page)) (render-component (editor self)))
(with-fresh-applications (("/order" 'order-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/order")
    (press b "+")
    (press b "+")
    (fill-in b "volume" "7")
    (press b "Save")
    (list (cl-ppcre:register-groups-bind (n) ("id=\"copies\" value=\"(\\d+)\"" (browser-html b)) n)
          (cl-ppcre:register-groups-bind (n) ("<output[^>]*>(\\d+)</output>" (browser-html b)) n)
          (body-text b))))
;; ⇒ ("5" "7" "Copies − + Volume 7 Volume must go in steps of 2. Save Cancel")

;;;; Example: littoral:rating-field
;;; `:rating` is a number of stars, 1 to `:max` (5), chosen with radio buttons drawn as stars; a field that isn't required offers No rating too, for NIL.  Shown, it is stars with the count for screen readers.
(defclass review ()
  ((stars :initarg :stars)))
(define-description review
  ((stars :type :rating)))
(let ((field (find-field 'review 'stars)))
  (list (parse-field field "4")
        (parse-field field "0")
        (handler-case (parse-field field "6") (field-error (e) (princ-to-string e)))
        (h:with-canvas-to-string () (render-field-value field 3))))
;; ⇒ (4 NIL "Stars must be from 1 to 5." "<span class=\"lt-stars\" role=\"img\" aria-label=\"3 out of 5\">★★★<span class=\"lt-stars-empty\">☆☆</span></span>")

;;;; Example: littoral:color-field littoral:normalize-color
;;; `:color` holds a colour code, entered with the browser's picker and a box for the code beside it, which may be cleared.  `normalize-color` reads a code as the field does.
(defclass theme ()
  ((accent :initarg :accent)))
(define-description theme
  ((accent :type :color)))
(let ((field (find-field 'theme 'accent)))
  (list (normalize-color "#36C")
        (normalize-color "teal")
        (parse-field field "0E7490")
        (h:with-canvas-to-string () (render-field-value field "#0e7490"))))
;; ⇒ ("#3366cc" NIL "#0e7490" "<span class=\"lt-swatch\" style=\"background: #0e7490\" aria-hidden=\"true\"></span><code>#0e7490</code>")

;;;; Example: littoral:multiple-choice-field littoral.test:select-options
;;; `:multiple-choice` takes any number of the `:choices`, entered with a list box, and holds them as a list in the choices' order; `:min` and `:max` bound how many.  As text, they're written one to a line.  In tests, `select-options` chooses several, as Ctrl-clicking them would.
(defclass meeting ()
  ((days :initarg :days :initform '())))
(define-description meeting
  ((days :type :multiple-choice :choices '(:mon :tue :wed :thu :fri) :labels #'string-capitalize :min 1)))
(defclass meeting-page (component)
  ((meeting :initform (make-instance 'meeting :days '(:tue)) :reader meeting)
   (editor :reader editor)))
(defmethod initialize-instance :after ((self meeting-page) &key)
  (setf (slot-value self 'editor) (make-editor (meeting self))))
(defmethod children ((self meeting-page)) (list (editor self)))
(defmethod render ((self meeting-page))
  (render-component (editor self))
  (h:p () (h:text (format nil "Meets on ~S" (slot-value (meeting self) 'days)))))
(with-fresh-applications (("/meeting" 'meeting-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/meeting")
    (select-options b "days" '("Fri" "Mon"))
    (press b "Save")
    (body-text b)))
;; ⇒ "Days Mon Tue Wed Thu Fri Hold Ctrl or ⌘ to choose several. Save Cancel Meets on (:MON :FRI)"

;;;; Example: littoral:transfer-field
;;; `:transfer` is a multiple choice entered with two lists, what's left and what's chosen, and buttons moving the selected items across: littoral.js moves them in place, and without it the buttons submit the form.  `:available-label` and `:chosen-label` head the lists.
(defclass account ()
  ((roles :initarg :roles)))
(define-description account
  ((roles :type :transfer :choices '("reader" "writer" "editor" "admin") :chosen-label "Granted")))
(defclass account-page (component)
  ((editor :initform (make-editor (make-instance 'account :roles '("reader"))) :reader editor)))
(defmethod children ((self account-page)) (list (editor self)))
(defmethod render ((self account-page)) (render-component (editor self)))
(with-fresh-applications (("/account" 'account-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/account")
    (select-options b "roles" '("editor" "writer"))
    (press b "Add")
    (body-text b)))
;; ⇒ "Roles Available admin Add → ← Remove Granted reader writer editor Save Cancel"

;;;; Example: littoral:password-strength littoral:password-strength-label littoral:*common-passwords*
;;; A rough estimate of how hard a password would be to guess, 0 to 4, and hints for a better one.  Common passwords, repeats, runs like abc and the person's own name (`:words`) count for little; length counts for most.
(list (multiple-value-list (password-strength "Password1"))
      (password-strength "elephant")
      (password-strength "correct horse battery staple")
      (nth-value 1 (password-strength "grace-hopper-1906" :words '("Grace Hopper")))
      (password-strength-label 2)
      (and (member "letmein" *common-passwords* :test #'string=) t))
;; ⇒ ((0 ("This is one of the most common passwords.")) 1 4 ("Avoid words from your name or email address." "Add another word or two: longer is better.") "Fair" T)

;;;; Example: littoral:new-password-field littoral:render-new-password-input
;;; `:new-password` is a password field with a strength meter beneath it, kept up to date over AJAX as the password is typed; `:min-strength` refuses weaker ones.  `render-new-password-input` writes the input and meter anywhere, as littoral/auth's reset form does.
(defclass wifi ()
  ((password :initarg :password :initform nil)))
(define-description wifi
  ((password :type :new-password :min-strength 3)))
(defclass wifi-page (component)
  ((editor :initform (make-editor (make-instance 'wifi)) :reader editor)))
(defmethod children ((self wifi-page)) (list (editor self)))
(defmethod render ((self wifi-page)) (render-component (editor self)))
(with-fresh-applications (("/wifi" 'wifi-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/wifi")
    (let* ((typing (first (ajax-specs b "on-input")))
           (verdict (ajax-request b (car typing) (cdr typing) :fields '(("_lt_value" . "hunter22")))))
      (fill-in b "password" "elephant42")
      (press b "Save")
      (list verdict (body-text b)))))
;; ⇒ ("{\"fragments\":{},\"missing\":[],\"value\":{\"score\":0,\"length\":8,\"text\":\"Very weak. This is one of the most common passwords.\"},\"scripts\":[]}" "Password Password is too easy to guess. Add another word or two: longer is better. Save Cancel")

;;;; Example: littoral:with-popover
;;; A button that opens a popover: the browser's own, which opens and closes without a round trip and closes on Escape or a click elsewhere.  littoral.js places it beside its button.
(h:with-canvas-to-string ()
  (with-popover ("Shipping" :id "shipping")
    (h:p () "Free over €50.")))
;; ⇒ "<button type=\"button\" class=\"lt-popover-button\" popovertarget=\"shipping\">Shipping</button><div id=\"shipping\" popover=\"auto\" class=\"lt-popover\"><p>Free over €50.</p></div>"

;;;; Example: littoral:with-tooltip
;;; A tip shown above what it wraps while that has the pointer or the focus.  littoral.js makes the tip describe the first thing inside that takes the focus, and Escape hides it.
(h:with-canvas-to-string ()
  (with-tooltip ("Saves a copy" :id "tip")
    (h:button () "Duplicate")))
;; ⇒ "<span class=\"lt-tooltip\"><button type=\"button\">Duplicate</button><span id=\"tip\" role=\"tooltip\" class=\"lt-tooltip-text\">Saves a copy</span></span>"

;;;; Example: littoral:drawer littoral:drawer-content littoral:drawer-open-p littoral:toggle-drawer
;;; A panel that slides in from the side over the page.  Its button opens it and its × closes it, over AJAX or as plain links; whether it's open is kept on the server.  `toggle-drawer` opens or closes it from code.
(defclass filters (component) ())
(defmethod render ((self filters)) (h:p () "Only in stock"))
(defclass shop-page (component)
  ((drawer :initform (make-instance 'drawer :label "Filters" :side :right :content (make-instance 'filters))
           :reader drawer)))
(defmethod children ((self shop-page)) (list (drawer self)))
(defmethod render ((self shop-page)) (render-component (drawer self)))
(with-fresh-applications (("/shop" 'shop-page :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/shop")
    (let ((closed (body-text b)))
      (click b "Filters")
      (list closed (body-text b)))))
;; ⇒ ("Filters" "Filters Filters × Only in stock")
(let ((drawer (make-instance 'drawer :content (make-instance 'filters))))
  (list (drawer-open-p drawer)
        (progn (toggle-drawer drawer) (drawer-open-p drawer))
        (progn (toggle-drawer drawer nil) (drawer-open-p drawer))
        (typep (drawer-content drawer) 'filters)))
;; ⇒ (NIL T NIL T)

;;;; Example: littoral:split-pane littoral:split-first littoral:split-second littoral:split-position littoral:set-split-position
;;; Two components side by side with a divider that can be dragged, or moved with the arrow keys, to share the width; `:position` is the first's share in percent, kept between `:min` (15) and `:max` (85).  littoral.js posts each new share, which is kept on the server.
(defclass words (component) ((text :initarg :text :reader words-text)))
(defmethod render ((self words)) (h:p () (h:text (words-text self))))
(let ((pane (make-instance 'split-pane :first (make-instance 'words :text "Inbox")
                                       :second (make-instance 'words :text "Message")
                                       :position 30)))
  (list (words-text (split-first pane)) (words-text (split-second pane))
        (split-position pane)
        (set-split-position pane 95)
        (set-split-position pane 3)))
;; ⇒ ("Inbox" "Message" 30 85 15)
