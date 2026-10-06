;;;; callbacks.lisp — what a rendered page can call back into
;;;;
;;;; Every link, field and button carries the id of a closure registered
;;;; here while the page renders.  A request names those ids as parameter
;;;; keys; value callbacks (fields) run first, in the order they were
;;;; rendered, then the single action callback (a link or button).

(in-package #:littoral)

(defstruct (callback (:constructor make-callback (id kind function)))
  id
  (kind :action :type (member :action :value :cancel :default))
  function)

(defclass callback-registry ()
  ((table :initform (make-hash-table :test 'equal) :reader registry-table)
   (next-id :initform 0 :accessor registry-next-id))
  (:documentation "The callbacks one rendered page registered, by id."))

(defun register-callback (kind function &optional (registry (render-callbacks *render-context*)))
  "Register FUNCTION as a KIND callback and return its id."
  (let ((id (princ-to-string (incf (registry-next-id registry)))))
    (setf (gethash id (registry-table registry)) (make-callback id kind function))
    id))

(defun find-callback (id registry)
  "The callback registered under ID in REGISTRY, or NIL."
  (gethash id (registry-table registry)))

(defun clear-callbacks (registry)
  "Forget every callback in REGISTRY and restart its ids."
  (clrhash (registry-table registry))
  (setf (registry-next-id registry) 0))

(defun request-callbacks (parameters registry)
  "Pair each callback named in PARAMETERS with its value.  Returns the
value callbacks (in render order) and the action callbacks."
  (let ((value-pairs (list)) (action-pairs (list)) (seen (list)))
    (loop for (key . value) in parameters
          for callback = (find-callback key registry)
          when (and callback (not (member key seen :test #'string=)))
            do (push key seen)
               ;; A field may appear more than once (a checkbox follows its
               ;; hidden twin); the last occurrence is the field's value.
               (let ((final (rest (find key parameters :key #'car :test #'string= :from-end t))))
                 (if (eql (callback-kind callback) :value)
                     (push (cons callback final) value-pairs)
                     (push (cons callback final) action-pairs))))
    (flet ((order (list) (sort list #'< :key (lambda (pair) (parse-integer (callback-id (first pair)))))))
      (values (order value-pairs) (order action-pairs)))))

(defun process-callbacks (parameters registry)
  "Run the callbacks PARAMETERS name.  True when any callback ran.

A cancel button runs alone: what was typed into the form is ignored.
Otherwise field callbacks run first, then one action: the last button or
link named, or failing that the form's default action."
  (multiple-value-bind (value-pairs action-pairs) (request-callbacks parameters registry)
    (flet ((of-kind (kind)
             (remove kind action-pairs :key (lambda (pair) (callback-kind (first pair))) :test-not #'eq)))
      (let ((cancel (first (of-kind :cancel)))
            (actions (of-kind :action))
            (default (first (of-kind :default))))
        (cond (cancel
               (funcall (callback-function (first cancel))))
              (t
               (loop for (callback . value) in value-pairs
                     do (funcall (callback-function callback) (or value "")))
               (cond (actions (funcall (callback-function (first (first (last actions))))))
                     (default (funcall (callback-function (first default))))
                     (t nil))))))
    (or value-pairs action-pairs)))
