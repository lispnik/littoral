;;;; decoration.lisp — call/answer and the standard decorations

(in-package #:littoral)

(defun add-decoration (component decoration)
  "Add DECORATION to COMPONENT, outermost among those of its kind.
Globals come first, then any delegation, then locals."
  (let* ((order '(:global :delegation :local))
         (rank (position (decoration-kind decoration) order))
         (chain (decorations component))
         (at (or (position-if (lambda (d) (>= (position (decoration-kind d) order) rank)) chain)
                 (length chain))))
    (setf (decorations component)
          (append (subseq chain 0 at) (list decoration) (subseq chain at)))
    decoration))

(defun remove-decoration (component decoration)
  "Take DECORATION off COMPONENT."
  (setf (decorations component) (remove decoration (decorations component)))
  decoration)

(defun find-decoration (component type)
  "COMPONENT's first decoration of TYPE, or NIL."
  (find-if (lambda (d) (typep d type)) (decorations component)))

;;; Delegation: CALL and SHOW

(defclass delegation (decoration)
  ((delegate :initarg :delegate :reader delegation-delegate))
  (:documentation "Shows the delegate in place of the decorated component."))

(defmethod decoration-kind ((decoration delegation)) :delegation)

(defmethod render-decoration ((decoration delegation) component)
  (declare (ignore component))
  (render-component (delegation-delegate decoration)))

(defclass answer-handler (decoration)
  ((function :initarg :function :reader handler-function)
   (caller :initarg :caller :reader handler-caller)
   (delegation :initarg :delegation :reader handler-delegation))
  (:documentation "Remembers who called a component and what to do with
its answer."))

(defmethod decoration-kind ((decoration answer-handler)) :global)

(defun show (self other &key on-answer)
  "Show OTHER in place of SELF until OTHER answers, then call ON-ANSWER
with the answer.  Returns OTHER at once: the non-blocking form of CALL."
  (signal-if-rendering 'show)
  (let ((delegation (make-instance 'delegation :delegate other)))
    (add-decoration self delegation)
    (add-decoration other (make-instance 'answer-handler
                                         :function on-answer
                                         :caller self
                                         :delegation delegation))
    other))

(declaim (ftype function call))   ; DEFUN/CC defines it only at load time

(defun/cc call (self other)
  "Show OTHER in place of SELF and return what it answers.

Inside a flow (see DEFINE-FLOW) this reads as a blocking call: the rest of
the flow is captured with cl-cont and resumed by ANSWER.  Elsewhere, such
as a callback, it shows OTHER and returns at once, discarding the answer;
use SHOW with :ON-ANSWER there to act on it."
  (let/cc k (show self other :on-answer k)))

;; DEFUN/CC makes a funcallable instance, which drops the docstring.
(setf (documentation 'call 'function)
      "Show OTHER in place of SELF and return what it answers.

Inside a flow (see DEFINE-FLOW) this reads as a blocking call: the rest of
the flow is captured with cl-cont and resumed by ANSWER.  Elsewhere, such
as a callback, it shows OTHER and returns at once, discarding the answer;
use SHOW with :ON-ANSWER there to act on it.")

(defgeneric validate-answer (decoration value)
  (:documentation "NIL when VALUE may be answered, else an error message.")
  (:method ((decoration decoration) value)
    (declare (ignore value))
    nil))

(defun answer (self &optional value)
  "Return control, with VALUE, to the component that called SELF.
Validation decorations on SELF may refuse the answer."
  (signal-if-rendering 'answer)
  (dolist (d (decorations self))
    (when (validate-answer d value)
      (return-from answer nil)))
  (let ((handler (find-decoration self 'answer-handler)))
    (when handler
      (remove-decoration self handler)
      (remove-decoration (handler-caller handler) (handler-delegation handler))
      (when (handler-function handler)
        (funcall (handler-function handler) value))
      t)))

(defun home (self)
  "Dismiss whatever SELF has called, without answering."
  (signal-if-rendering 'home)
  (setf (decorations self)
        (remove-if (lambda (d) (typep d 'delegation)) (decorations self))))

;;; Modal dialogs

(defmethod decoration-children ((decoration decoration)) '())

(defclass modal-decoration (decoration)
  ((dialog :initarg :dialog :reader modal-dialog)
   (closable :initarg :closable :initform t :reader modal-closable-p)
   (title :initarg :title :initform nil :reader modal-title))
  (:documentation "Shows a component over the page, which stays visible
behind it but cannot be used until the dialog answers."))

(defmethod decoration-kind ((decoration modal-decoration)) :global)

(defmethod decoration-children ((decoration modal-decoration))
  (list (modal-dialog decoration)))

(defmethod render-decoration ((decoration modal-decoration) component)
  (declare (ignore component))
  ;; The page behind, inert: no clicks, no focus, hidden from screen readers.
  (emit-tag "div" (list :class "lt-behind-modal" :inert t :aria-hidden "true")
            (lambda () (render-inner)))
  (emit-tag "dialog" (list :class "lt-modal" :open t :aria-modal "true"
                           :aria-label (modal-title decoration)
                           :data-lt-modal (if (modal-closable-p decoration) "closable" "fixed"))
            (lambda ()
              (when (modal-closable-p decoration)
                (anchor (:class "lt-modal-close" :aria-label "Close"
                         :callback (lambda () (answer (modal-dialog decoration) nil)))
                  "×"))
              (render-component (modal-dialog decoration)))))

(defun show-modal (other &key on-answer (closable t) title)
  "Show OTHER in a dialog over the whole page until it answers, then call
ON-ANSWER with the answer.  CLOSABLE adds a close button (and Esc), which
answers NIL; TITLE names the dialog for screen readers."
  (let* ((root (session-root *session*))
         (modal (make-instance 'modal-decoration :dialog other :closable closable :title title)))
    (signal-if-rendering 'show-modal)
    (add-decoration root modal)
    (add-decoration other (make-instance 'answer-handler :function on-answer
                                                         :caller root :delegation modal))
    other))

(declaim (ftype function call-modal))

(defun/cc call-modal (other &optional title)
  "Show OTHER in a dialog over the page and return what it answers; a
blocking call inside a flow, like CALL."
  (let/cc k (show-modal other :on-answer k :title title)))

;;; Toasts

(defun toast (message &key (kind :info) (session *session*))
  "Show MESSAGE briefly at the corner of SESSION's page: on its next page or
AJAX response, or at once on pages with a push stream.  KIND is :INFO,
:SUCCESS or :ERROR."
  (push (cons kind message) (session-property :toasts session))
  (wake-streams-for-toasts session))

(defun take-toasts (&optional (session *session*))
  "SESSION's waiting toasts, oldest first, now taken."
  (prog1 (reverse (session-property :toasts session))
    (setf (session-property :toasts session) '())))

(defun render-toasts (toasts)
  "Write TOASTS where littoral.js shows them."
  (emit-tag "div" (list :class "lt-toasts" :aria-live "polite" :role "status")
            (lambda ()
              (dolist (toast toasts)
                (emit-tag "div" (list :class (list "lt-toast" (format nil "lt-toast-~(~A~)" (car toast))))
                          (lambda () (text (cdr toast))))))))

(defun toasts-json (toasts)
  (format nil "[~{~A~^,~}]"
          (mapcar (lambda (toast)
                    (format nil "{\"kind\":~A,\"text\":~A}"
                            (json-string (string-downcase (car toast))) (json-string (cdr toast))))
                  toasts)))

;;; Message, form and validation decorations

(defclass message-decoration (decoration)
  ((message :initarg :message :accessor decoration-message))
  (:documentation "A heading above the component."))

(defmethod render-decoration ((decoration message-decoration) component)
  (declare (ignore component))
  (h3 (:class "lt-message") (text (decoration-message decoration)))
  (render-inner))

(defclass form-decoration (decoration)
  ((buttons :initarg :buttons :initform '(("OK" . :ok)) :reader decoration-buttons
            :documentation "Alist of (LABEL . ACTION).  An ACTION that is a
function is called with the component; any other value is answered."))
  (:documentation "Puts the component in a form with a row of buttons, the
way Seaside's WAFormDecoration does."))

(defmethod render-decoration ((decoration form-decoration) component)
  (form (:class "lt-form-decoration")
    (render-inner)
    (div (:class "lt-buttons")
      (loop for (label . action) in (decoration-buttons decoration)
            do (let ((action action))
                 (submit-button (:callback (lambda ()
                                             (if (functionp action)
                                                 (funcall action component)
                                                 (answer component action))))
                   (text label)))))))

(defclass validation-decoration (decoration)
  ((validator :initarg :validator :reader validator)
   (error-message :initform nil :accessor validation-error-message))
  (:documentation "Refuses answers the validator rejects and shows why."))

(defmethod validate-answer ((decoration validation-decoration) value)
  (setf (validation-error-message decoration) (funcall (validator decoration) value)))

(defmethod render-decoration ((decoration validation-decoration) component)
  (declare (ignore component))
  (let ((message (validation-error-message decoration)))
    (when message
      (div (:class "lt-validation-error") (text message))))
  (render-inner))

(defun validate-with (component validator)
  "Answers from COMPONENT must first pass VALIDATOR, a function of the
answer returning NIL to accept or an error message to refuse."
  (add-decoration component (make-instance 'validation-decoration :validator validator))
  component)
