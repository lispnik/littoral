;;;; The examples for AJAX: re-rendering parts of a page in place.

;;;; Example: littoral:ajax
;;; The button posts its callback in the background and gets back the new HTML of the components to :update, which must be UPDATABLE.  AJAX-REQUEST posts it as littoral.js does; the reply is JSON.
(defclass likes (component updatable)
  ((count :initform 0 :accessor like-count)))
(defmethod render ((self likes))
  (h:text (format nil "~D likes " (like-count self)))
  (h:button (:on-click (ajax :callback (lambda () (incf (like-count self))) :update self))
    "Like"))
(with-fresh-applications (("/likes" 'likes :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/likes")
    (destructuring-bind (callback . targets) (first (ajax-specs b "on-click"))
      (let ((reply (com.inuoe.jzon:parse (ajax-request b callback targets))))
        (mapcar #'strip-tags (alexandria:hash-table-values (gethash "fragments" reply)))))))
;; ⇒ ("1 likes Like")

;;;; Example: littoral:ajax
;;; :VALUE is JavaScript the browser evaluates; the callback gets its result as a string, and what the callback returns goes back to the :ON-COMPLETE snippet as value.  :CONFIRM asks the user first.  Here the request carries the value the browser would have sent.
(defclass size-probe (component) ())
(defmethod render ((self size-probe))
  (h:button (:on-click (ajax :value "window.innerWidth + 'x' + window.innerHeight"
                           :callback (lambda (size) (format nil "The server saw ~A." size))
                           :on-complete "document.title = value"
                           :confirm "Send your window size?"))
    "Measure"))
(with-fresh-applications (("/probe" 'size-probe :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/probe")
    (destructuring-bind (callback . targets) (first (ajax-specs b "on-click"))
      (gethash "value" (com.inuoe.jzon:parse
                        (ajax-request b callback targets :fields '(("_lt_value" . "1280x800"))))))))
;; ⇒ "The server saw 1280x800."

;;;; Example: littoral:ajax-update
;;; Re-render components without a callback of their own: here the field's own callback stores what was typed, and the preview is redrawn on every keystroke.
(defclass search-box (component)
  ((query :initform "" :accessor query)
   (preview :reader preview)))
(defclass search-preview (component updatable)
  ((box :initarg :box :reader box)))
(defmethod initialize-instance :after ((self search-box) &key)
  (setf (slot-value self 'preview) (make-instance 'search-preview :box self)))
(defmethod children ((self search-box)) (list (preview self)))
(defmethod render ((self search-preview))
  (h:p () (h:text (format nil "Searching for ~S" (query (box self))))))
(defmethod render ((self search-box))
  (h:text-input (:id "q" :label "Search" :value (query self)
               :callback (lambda (v) (setf (query self) v))
               :on-input (ajax-update (preview self))))
  (render-component (preview self)))
(with-fresh-applications (("/search" 'search-box :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/search")
    (destructuring-bind (callback . targets) (first (ajax-specs b "on-input"))
      (ajax-request b callback targets :fields (list (cons (element-name b "q") "otters"))))
    (visit b (browser-url b))
    (body-text b)))
;; ⇒ "Searching for \"otters\""

;;;; Example: littoral:periodical
;;; For a :PERIODICAL attribute: littoral.js runs the callback and redraws the components every few seconds.  The attribute holds the interval in milliseconds, then the callback and the components; here one tick is posted by hand.
(defclass ticker (component updatable)
  ((ticks :initform 0 :accessor ticks)))
(defmethod render ((self ticker))
  (h:span (:periodical (periodical 5 :callback (lambda () (incf (ticks self))) :update self))
    (h:text (format nil "Ticks: ~D" (ticks self)))))
(with-fresh-applications (("/ticker" 'ticker :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/ticker")
    (destructuring-bind (interval . rest) (first (ajax-specs b "periodical"))
      (let ((semicolon (position #\; rest)))
        (ajax-request b (subseq rest 0 semicolon) (subseq rest (1+ semicolon))))
      (visit b (browser-url b))
      (list interval (body-text b)))))
;; ⇒ ("5000" "Ticks: 1")

;;;; Example: littoral:execute-script
;;; From an AJAX callback, queue JavaScript for the browser to run once the updates are in.  Outside an AJAX request it does nothing.
(defclass retitler (component) ())
(defmethod render ((self retitler))
  (h:button (:on-click (ajax :callback (lambda () (execute-script "document.title = 'Saved'"))))
    "Save"))
(with-fresh-applications (("/retitle" 'retitler :mode :deployment))
  (let ((b (make-instance 'browser)))
    (visit b "/retitle")
    (destructuring-bind (callback . targets) (first (ajax-specs b "on-click"))
      (gethash "scripts" (com.inuoe.jzon:parse (ajax-request b callback targets))))))
;; ⇒ #("document.title = 'Saved'")
(execute-script "alert('not now')")
;; ⇒ NIL
