;;;; parenscript-demo.lisp — browser behaviour written in Lisp

(defpackage #:littoral-parenscript-demo
  (:use #:cl #:littoral #:parenscript #:littoral.parenscript)
  (:local-nicknames (#:h #:littoral.html))
  ;; Parenscript also exports CALL; take littoral's.  Parenscript
  ;; method names in CHAIN work with any symbol of the right name.
  (:shadowing-import-from #:littoral #:call)
  (:documentation "Components whose browser behaviour is written in Parenscript.")
  (:export #:ps-demo #:register))

(in-package #:littoral-parenscript-demo)

(defclass ps-demo (component updatable)
  ((asked :initform 0 :accessor times-asked))
  (:documentation "A browser-only toggle, and a question the server answers."))

(defmethod render ((self ps-demo))
  (h:h1 () "Parenscript")
  (h:p () "These buttons' behaviour is Lisp, compiled to JavaScript.")
  ;; Runs only in the browser: no request.
  (h:p () (h:button (:id "toggle" :aria-pressed "false"
                 :on-click (in-browser (ps (let ((on (not (= (chain this (get-attribute "aria-pressed")) "true"))))
                                         (chain this (set-attribute "aria-pressed" (if on "true" "false")))
                                         (setf (@ this text-content) (if on "On" "Off"))))))
          "Off"))
  ;; Asks a Lisp function, and shows what it answers.
  (let ((shout (client-callback (lambda (text)
                                  (incf (times-asked self))
                                  (string-upcase text))
                                :update self)))
    (h:p ()
      (h:text-input (:id "words" :label "Words to shout" :value "hello from the browser"))
      (h:button (:id "shout"
               :on-click (in-browser (ps (chain littoral
                                            (call (lisp shout) (@ (chain document (get-element-by-id "words")) value))
                                            (then (lambda (answer)
                                                    (setf (@ (chain document (get-element-by-id "answer")) text-content)
                                                          answer)))))))
        "Shout")))
  (h:p () "The server answered: " (h:strong (:id "answer") ""))
  (h:p () (h:text (format nil "Asked ~D time~:P." (times-asked self)))))

(define-script ps-demo (self)
  (chain console (log (+ "ps-demo ready, component " (lisp (component-id self))))))

(defun register (&key (path "/examples/parenscript"))
  "Serve the demo at PATH."
  (register-application path 'ps-demo :title "Parenscript"))
