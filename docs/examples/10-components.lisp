;;;; The examples for components.  See tools/doc-examples.lisp for the format.

;;;; Example: littoral:render
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
