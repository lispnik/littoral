;;;; topics.lisp — bookmarkable pages with update-url and initial-request

(in-package #:littoral-examples)

(defparameter *topics*
  '(("components" . "A component renders itself and embeds others with render-component.")
    ("callbacks" . "Links and fields carry closures instead of URLs you design.")
    ("call-answer" . "One component calls another and gets its answer back.")
    ("backtracking" . "The back button restores the state each page was rendered from.")
    ("tasks" . "A flow of calls written as straight-line code.")))

(defclass topics (component)
  ((current :initform nil :accessor current-topic)
   (zoom :initform nil :accessor zoomed-p))
  (:documentation "Topics whose URL names the one shown, so they can be bookmarked."))

(defmethod states ((self topics))
  (list self))

;; /examples/topics/tasks?big
(defmethod update-url ((self topics) url)
  (when (current-topic self)
    (add-to-path url (current-topic self)))
  (when (zoomed-p self)
    (add-parameter url "big")))

(defmethod initial-request ((self topics) request)
  (let ((name (first (request-extra-path))))
    (when (assoc name *topics* :test #'equal)
      (setf (current-topic self) name)))
  (setf (zoomed-p self) (request-parameter-p "big" request)))

(defmethod render ((self topics))
  (h1 () "Topics")
  (ul ()
    (loop for (name) in *topics*
          do (let ((name name))
               (li () (anchor (:callback (lambda () (setf (current-topic self) name)))
                        (text name))))))
  (let ((topic (assoc (current-topic self) *topics* :test #'equal)))
    (when topic
      (h2 () (text (first topic)))
      (p (:style (when (zoomed-p self) "font-size: 1.6rem")) (text (rest topic)))
      (anchor (:callback (lambda () (setf (zoomed-p self) (not (zoomed-p self)))))
        (text (if (zoomed-p self) "smaller" "bigger")))))
  (p (:class "hint") "The address bar names the topic: bookmark it and come back."))
