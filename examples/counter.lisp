;;;; counter.lisp — Seaside's first example

(in-package #:littoral-examples)

(defclass counter (component)
  ((count :initform 0 :accessor count-of)))

;; Without this the back button would show an old count but act on the
;; current one.
(defmethod states ((self counter))
  (list self))

(defmethod render ((self counter))
  (div (:class "counter")
    (h1 () (text (count-of self)))
    (anchor (:callback (lambda () (incf (count-of self)))) "++")
    " "
    (anchor (:callback (lambda () (decf (count-of self)))) "--")))

(defmethod style ((self counter))
  ".counter h1 { font-size: 3rem; margin: .2rem 0; }")
