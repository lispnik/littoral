;;;; multi-counter.lisp — components embedding components

(in-package #:littoral-examples)

(defclass multi-counter (component)
  ((counters :initform (loop repeat 5 collect (make-instance 'counter))
             :reader counters))
  (:documentation "Five counters on one page."))

(defmethod children ((self multi-counter))
  (counters self))

(defmethod render ((self multi-counter))
  (dolist (counter (counters self))
    (render-component counter)
    (hr ())))
