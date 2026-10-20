;;;; ajax.lisp — updating parts of a page in place

(in-package #:littoral-examples)

(defclass ajax-counter (counter updatable) ()
  (:documentation "A counter whose buttons update it in place."))

(defmethod render ((self ajax-counter))
  (h:span (:class "ajax-count") (h:text (count-of self)))
  (h:text " ")
  (h:button (:on-click (ajax :callback (lambda () (incf (count-of self))) :update self)) "++")
  (h:button (:on-click (ajax :callback (lambda () (decf (count-of self))) :update self)) "--"))

(defclass clock (component updatable) ()
  (:documentation "The time, re-rendered every second."))

(defmethod render ((self clock))
  (multiple-value-bind (s m h) (get-decoded-time)
    (h:span (:periodical (periodical 1 :update self))
      (h:text (format nil "~2,'0D:~2,'0D:~2,'0D" h m s)))))

(defclass echo (component updatable)
  ((text :initform "" :accessor echo-text))
  (:documentation "Holds the text typed into the echo field."))

(defclass echo-preview (component updatable)
  ((echo :initarg :echo :reader preview-echo))
  (:documentation "Shows what has been typed so far, updated on every keystroke."))

(defmethod render ((self echo-preview))
  (h:p () "You typed: " (h:strong () (h:text (echo-text (preview-echo self))))))

(defclass ajax-demo (component)
  ((counter :initform (make-instance 'ajax-counter) :reader demo-counter)
   (clock :initform (make-instance 'clock) :reader demo-clock)
   (echo :initform (make-instance 'echo) :reader demo-echo)
   (preview :reader demo-preview))
  (:documentation "The AJAX example page."))

(defmethod initialize-instance :after ((self ajax-demo) &key)
  (setf (slot-value self 'preview) (make-instance 'echo-preview :echo (demo-echo self))))

(defmethod children ((self ajax-demo))
  (list (demo-counter self) (demo-clock self) (demo-preview self)))

(defun render-server-talk (self)
  "Buttons showing browser values, callback results, confirmation and server scripts."
  (h:h2 () "Talking to the server")
  (h:p ()
    ;; A value computed in the browser goes to the callback; what the
    ;; callback returns comes back to :on-complete as value.
    (h:button (:id "measure"
             :on-click (ajax :value "window.innerWidth + 'x' + window.innerHeight"
                             :callback (lambda (size) (format nil "The server heard ~A." size))
                             :on-complete "document.getElementById('reply').textContent = value"))
      "Tell the server my window size")
    (h:text " ")
    ;; Ask first, then act.
    (h:button (:id "reset"
             :on-click (ajax :confirm "Reset the counter to zero?"
                             :callback (lambda () (setf (count-of (demo-counter self)) 0))
                             :update (demo-counter self)))
      "Reset the counter")
    (h:text " ")
    ;; The server decides what the browser does next.
    (h:button (:id "retitle"
             :on-click (ajax :callback (lambda ()
                                         (execute-script
                                          (format nil "document.title = ~S"
                                                  (format nil "Counter at ~D" (count-of (demo-counter self))))))))
      "Put the count in the title"))
  (h:p (:id "reply" :class "reply") ""))

(defmethod render ((self ajax-demo))
  (h:h1 () "AJAX")
  (h:h2 () "Counter")
  (render-component (demo-counter self))
  (h:h2 () "Clock")
  (render-component (demo-clock self))
  (h:h2 () "Echo")
  (h:text-input (:label "Text to echo" :value (echo-text (demo-echo self))
               :callback (lambda (v) (setf (echo-text (demo-echo self)) v))
               :on-input (ajax-update (demo-preview self))))
  (render-component (demo-preview self))
  (render-server-talk self))
