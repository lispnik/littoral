;;;; callbacks.lisp — what a rendered page can call back into
;;;;
;;;; Every link, field and button carries the id of a closure registered
;;;; here while the page renders.  A request names those ids as parameter
;;;; keys; value callbacks (fields) run first, in the order they were
;;;; rendered, then the single action callback (a link or button).

(in-package #:littoral)

(defstruct (callback (:constructor make-callback (id kind function)))
  id
  (kind :action :type (member :action :value))
  function)

(defclass callback-registry ()
  ((table :initform (make-hash-table :test 'equal) :reader registry-table)
   (next-id :initform 0 :accessor registry-next-id)))

(defun register-callback (kind function &optional (registry (render-callbacks *render-context*)))
  "Register FUNCTION as a KIND callback and return its id."
  (let ((id (princ-to-string (incf (registry-next-id registry)))))
    (setf (gethash id (registry-table registry)) (make-callback id kind function))
    id))

(defun find-callback (id registry)
  (gethash id (registry-table registry)))

(defun clear-callbacks (registry)
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
               (let ((final (cdr (find key parameters :key #'car :test #'string= :from-end t))))
                 (if (eq (callback-kind callback) :value)
                     (push (cons callback final) value-pairs)
                     (push (cons callback final) action-pairs))))
    (flet ((order (list) (sort list #'< :key (lambda (pair) (parse-integer (callback-id (car pair)))))))
      (values (order value-pairs) (order action-pairs)))))

(defun process-callbacks (parameters registry)
  "Run the callbacks PARAMETERS name.  True when any callback ran."
  (multiple-value-bind (value-pairs action-pairs) (request-callbacks parameters registry)
    (loop for (callback . value) in value-pairs
          do (funcall (callback-function callback) (or value "")))
    ;; Only one action per request, as in Seaside: the last button or
    ;; link named wins.
    (when action-pairs
      (funcall (callback-function (car (first (last action-pairs))))))
    (or value-pairs action-pairs)))
