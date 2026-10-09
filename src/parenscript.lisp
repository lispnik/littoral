;;;; parenscript.lisp — browser behaviour written in Lisp, beside RENDER
;;;;
;;;;   (defpackage #:my-app (:use #:cl #:littoral #:littoral.html
;;;;                              #:parenscript #:littoral.parenscript))
;;;;
;;;;   (button (:on-click (in-browser (ps (chain this class-list (toggle "on")))))
;;;;     "Toggle")                                   ; runs in the browser only
;;;;
;;;;   (button (:on-click (in-browser (ps (chain littoral
;;;;                                         (call (lisp (client-callback (lambda (v) (string-upcase v))))
;;;;                                               "hello")
;;;;                                         (then (lambda (answer) (alert answer)))))))
;;;;     "Ask the server")
;;;;
;;;; IN-BROWSER wraps JavaScript for an :ON-CLICK, :ON-CHANGE, :ON-INPUT or
;;;; :ON-SUBMIT attribute; THIS is the element and EVENT the event.
;;;; CLIENT-CALLBACK registers a Lisp function the browser can call with
;;;; littoral.call(spec, value), which returns a promise of the function's
;;;; answer (sent as JSON) after updating any components given as :UPDATE.
;;;; DEFINE-SCRIPT gives a component page-level JavaScript.

(defpackage #:littoral.parenscript
  (:use #:cl #:littoral #:littoral.html)
  (:documentation "Write Littoral components' browser behaviour in Parenscript.")
  (:export #:in-browser #:client-callback #:define-script))

(in-package #:littoral.parenscript)

(defstruct (client-handler (:constructor in-browser (code)))
  "JavaScript to run in the browser when an event happens on an element."
  code)

(defmethod littoral::emit-attribute (key (value client-handler) stream)
  ;; data-lt-on-click-js="@ID": littoral.js runs the code the page defined
  ;; under ID, with THIS and EVENT.
  (format stream " data-lt-~(~A~)-js=\"~A\"" key
          (html-escape (littoral::client-code (client-handler-code value) '("event")))))

(defun client-callback (function &key update)
  "Register FUNCTION, of the string the browser sends, for littoral.call;
returns the spec to pass it.  The components in UPDATE are re-rendered
after it runs; its result becomes the promise's value."
  (let ((id (littoral::register :action
                                (littoral::ajax-action
                                 (littoral::%make-ajax-spec :callback function :value t)))))
    (format nil "~A;~{~A~^ ~}" id (mapcar #'component-id (alexandria:ensure-list update)))))

(defmacro define-script (class (self) &body body)
  "Give CLASS's pages the JavaScript BODY, written in Parenscript, with
SELF the component (use (LISP …) for its values)."
  `(defmethod script ((,self ,class))
     (parenscript:ps ,@body)))
