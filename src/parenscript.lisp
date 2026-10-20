;;;; parenscript.lisp — browser behaviour written in Lisp, beside RENDER
;;;;
;;;;   (defpackage #:my-app
;;;;     (:use #:cl #:littoral #:parenscript #:littoral.parenscript)
;;;;     (:local-nicknames (#:h #:littoral.html))
;;;;     (:shadowing-import-from #:littoral #:call))
;;;;
;;;;   (h:button (:on-click (in-browser (ps (chain this class-list (toggle "on")))))
;;;;     "Toggle")                                   ; runs in the browser only
;;;;
;;;;   (h:button (:on-click (in-browser (ps (chain littoral
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
  (:use #:cl #:littoral)
  (:local-nicknames (#:h #:littoral.html))
  (:documentation "Load with `(asdf:load-system :littoral/parenscript)`.  Writes Littoral
components' browser behaviour in Parenscript.  A package using both this and
parenscript must shadow one CALL, as the parenscript demo does with
(:shadowing-import-from #:littoral #:call).")
  (:export #:in-browser #:client-callback #:define-script))

(in-package #:littoral.parenscript)

(defstruct (client-handler (:constructor in-browser (code)))
  "JavaScript to run in the browser when an event happens on an element."
  code)

(setf (documentation 'in-browser 'function)
      "CODE, a string of JavaScript (as PARENSCRIPT:PS makes it), as the value of
an :ON-CLICK, :ON-CHANGE, :ON-INPUT or :ON-SUBMIT attribute: the browser runs
it when that event happens, with THIS the element and EVENT the event, and
sends no request.  The page's own script defines the code and the attribute
only names it, so use it while rendering.")

(defmethod littoral::emit-attribute (key (value client-handler) stream)
  ;; data-lt-on-click-js="@ID": littoral.js runs the code the page defined
  ;; under ID, with THIS and EVENT.
  (format stream " data-lt-~(~A~)-js=\"~A\"" key
          (h:html-escape (littoral::client-code (client-handler-code value) '("event")))))

(defun client-callback (function &key update)
  "Register FUNCTION, of the string the browser sends (\"\" when it sends
none), for littoral.call(spec, value) in the browser; returns the spec, a
string.  Call it while rendering.  UPDATE, a component or a list of them,
is drawn again after FUNCTION runs; FUNCTION's result, sent as JSON, is the
value of littoral.call's promise."
  (let ((id (littoral::register :action
                                (littoral::ajax-action
                                 (littoral::%make-ajax-spec :callback function :value t)))))
    (format nil "~A;~{~A~^ ~}" id (mapcar #'component-id (alexandria:ensure-list update)))))

(defmacro define-script (class (self) &body body)
  "Give CLASS's pages the JavaScript BODY, written in Parenscript, with
SELF the component (use (LISP …) for its values): a SCRIPT method."
  `(defmethod script ((,self ,class))
     (parenscript:ps ,@body)))
