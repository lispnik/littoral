;;;; widgets-layout.lisp — popovers, tooltips, drawers and split panes
;;;;
;;;;   (with-popover ("Details") (h:p () "More about it."))
;;;;   (with-tooltip ("Copies the link") (h:button () "Copy"))
;;;;   (make-instance 'drawer :label "Filters" :content filters :side :right)
;;;;   (make-instance 'split-pane :first list :second detail :position 35)

(in-package #:littoral)

(defun fresh-element-id (prefix)
  "An element id starting PREFIX, different on every call."
  (format nil "~A-~A" prefix (random-key 8)))

;;; Popovers: the browser's own popover attribute

(defun %with-popover (label body &key id class)
  "Write WITH-POPOVER's button and popover, BODY a thunk."
  (let ((id (or id (fresh-element-id "lt-popover"))))
    (emit-tag "button" (list :type "button" :class "lt-popover-button" :popovertarget id)
              (lambda () (h:text (translate-label label))))
    (emit-tag "div" (list :id id :popover "auto" :class (list "lt-popover" class)) body)))

(defmacro with-popover ((label &key id class) &body body)
  "Write a button, LABEL (translated), that opens a popover holding BODY,
written as a tag's body is.  It is the browser's own popover: it opens and
closes without a round trip, Escape or a click elsewhere closes it, and it
needs no script, though littoral.js places it beside its button.  ID names
the popover element and CLASS is added to its classes.  What BODY writes is
there from the start, so its links and fields work as any others."
  `(%with-popover ,label ,(or (body-thunk body) '(lambda ())) :id ,id :class ,class))

;;; Tooltips

(defun %with-tooltip (tip body &key id)
  "Write WITH-TOOLTIP's wrapper around the thunk BODY, and its tip."
  (let ((id (or id (fresh-element-id "lt-tip"))))
    (emit-tag "span" (list :class "lt-tooltip")
              (lambda ()
                (funcall body)
                (emit-tag "span" (list :id id :role "tooltip" :class "lt-tooltip-text")
                          (lambda () (h:text (translate-label tip))))))))

(defmacro with-tooltip ((tip &key id) &body body)
  "Write BODY, written as a tag's body is, with TIP (translated) shown above
it while the pointer is over it or it has the focus.  littoral.js makes the
tip describe the first thing in BODY that takes the focus (or BODY itself,
made focusable), and Escape hides it.  ID names the tip's element."
  `(%with-tooltip ,tip ,(or (body-thunk body) '(lambda ())) :id ,id))

;;; Drawers

(defclass drawer (component updatable)
  ((content :initarg :content :reader drawer-content
            :documentation "The component shown in the drawer.")
   (label :initarg :label :initform "Menu" :reader drawer-label
          :documentation "The text of the button that opens it, translated.")
   (title :initarg :title :initform nil :reader drawer-title
          :documentation "The drawer's heading, translated; by default its label.")
   (side :initarg :side :initform :left :reader drawer-side
         :documentation ":LEFT or :RIGHT.")
   (open :initarg :open :initform nil :accessor drawer-open-p))
  (:documentation "A panel that slides in over the page from its :SIDE
(:LEFT or :RIGHT) holding :CONTENT, a component.  A button, :LABEL,
opens it, and its close button, Escape or a click outside closes it.
Whether it is open is kept on the server, so the page comes back as it was
left; opening and closing go over AJAX, or are ordinary links without
JavaScript.  Focus moves into it as it opens and back to its button when
it closes."))

(defmethod states ((self drawer)) (list self))

(defmethod children ((self drawer))
  (when (drawer-open-p self) (list (drawer-content self))))

(defun toggle-drawer (drawer &optional (open (not (drawer-open-p drawer))))
  "Open DRAWER, or close it, or with OPEN true or false, open or close it."
  (setf (drawer-open-p drawer) (and open t)))

(defmethod render ((self drawer))
  (let ((panel-id (format nil "~A-panel" (component-id self)))
        (open (drawer-open-p self))
        (title (translate-label (or (drawer-title self) (drawer-label self)))))
    (flet ((toggle () (toggle-drawer self)))
      (h:anchor (:class "lt-drawer-toggle" :aria-expanded (if open "true" "false")
               :aria-controls (when open panel-id)
               :callback #'toggle :on-click (ajax :callback #'toggle :update self))
        (h:text (translate-label (drawer-label self))))
      (when open
        (h:div (:class "lt-drawer-backdrop"))
        (h:div (:id panel-id :role "dialog" :aria-label title
              :class (list "lt-drawer" (format nil "lt-drawer-~(~A~)" (drawer-side self))))
          (h:div (:class "lt-drawer-head")
            (h:h2 () (h:text title))
            (h:anchor (:class "lt-drawer-close" :label (translate "Close") :autofocus t
                     :callback #'toggle :on-click (ajax :callback #'toggle :update self))
              "×"))
          (render-component (drawer-content self)))))))

;;; Split panes

(defclass split-pane (component)
  ((first :initarg :first :reader split-first :documentation "The component on the left.")
   (second :initarg :second :reader split-second :documentation "The component on the right.")
   (position :initarg :position :initform 40 :accessor split-position
             :documentation "The left pane's share of the width, in percent.")
   (min :initarg :min :initform 15 :reader split-min)
   (max :initarg :max :initform 85 :reader split-max)
   (label :initarg :label :initform "Resize" :reader split-label
          :documentation "What the divider is called to assistive technology, translated."))
  (:documentation "Two components side by side, :FIRST and :SECOND, such as
a list and the detail of what is chosen in it, with a divider between them.
Dragging the divider, or focusing it and using the arrow keys (Home and End
for the limits), shares the width differently, between :MIN and :MAX
percent; :POSITION is the first pane's share.  The share is kept on the
server, so the page comes back as it was left.  On narrow screens the
panes are stacked."))

(defmethod states ((self split-pane)) (list self))
(defmethod children ((self split-pane)) (list (split-first self) (split-second self)))

(defun set-split-position (pane percent)
  "Give PANE's first pane PERCENT of the width, kept within its limits."
  (setf (split-position pane) (max (split-min pane) (min (split-max pane) (round percent)))))

(defmethod render ((self split-pane))
  (let ((first-id (format nil "~A-first" (component-id self)))
        (position (split-position self)))
    (h:div (:class "lt-split" :style (format nil "--lt-split: ~D%" position))
      (h:div (:id first-id :class "lt-split-pane")
        (render-component (split-first self)))
      (h:div (:class "lt-split-divider" :role "separator" :tabindex "0" :aria-orientation "vertical"
            :aria-controls first-id :aria-label (translate-label (split-label self))
            :aria-valuenow position :aria-valuetext (format nil "~D%" position)
            :aria-valuemin (split-min self) :aria-valuemax (split-max self)
            :split (ajax :callback (lambda (value)
                                     (let ((n (ignore-errors (parse-integer value))))
                                       (when n (set-split-position self n))))
                         :value "this.getAttribute('aria-valuenow')")))
      (h:div (:class "lt-split-pane")
        (render-component (split-second self))))))
