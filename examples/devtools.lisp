;;;; devtools.lisp — a page to try the development tools on

(in-package #:littoral-examples)

(defclass devtools-demo (component)
  ((counters :initform (list (make-instance 'counter) (make-instance 'counter)) :reader demo-counters)
   (note :initform "" :accessor demo-note))
  (:documentation "Two counters and a note, to watch with the development tools."))

(defmethod children ((self devtools-demo)) (demo-counters self))
(defmethod states ((self devtools-demo)) (list self))

(defmethod render ((self devtools-demo))
  (h1 () "Development tools")
  (p () "Applications in development mode end every page with a toolbar. Try it on this page:")
  (ol ()
    (li () "Click the counters a few times, and type a note.")
    (li () (strong () "History") " lists every page this session has shown. Open the changes of each: "
      "which slot of which component the click changed, before and after. " (strong () "Open") " an old page to go back to it.")
    (li () (strong () "Components") " shows the component tree as it is now, with every slot.")
    (li () (strong () "Halos") " frames each component, with its inspector, HTML and source.")
    (li () "Make a callback fail (the link below divides by zero): the page becomes a debugger, with Retry."))
  (div (:class "devtools-counters")
    (dolist (counter (demo-counters self))
      (render-component counter)))
  (form ()
    (text-input (:id "note" :label "Note" :value (demo-note self) :callback (lambda (v) (setf (demo-note self) v))))
    (submit-button () "Save the note"))
  (p () (anchor (:callback (lambda () ;; Two counters: this divides by zero, but only when it runs.
                             (/ (length (demo-note self)) (- (length (demo-counters self)) 2))))
          "A callback that fails")))

(defmethod style ((self devtools-demo))
  ".devtools-counters { display: flex; flex-wrap: wrap; gap: 2rem; }")
