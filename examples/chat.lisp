;;;; chat.lisp — many sessions, one room, updated by server push
;;;;
;;;; The room is shared state.  Every message list subscribes to the room's
;;;; channel, and posting PUBLISHes it, so each open page re-renders its
;;;; list as soon as anyone speaks.  Posting is an AJAX form submit, so the
;;;; page never reloads.  The nickname is asked for with an ordinary CALL.

(in-package #:littoral-examples)

(defstruct chat-message nick text time)

(defvar *room* '() "Messages, newest first.")
(defvar *room-lock* (sb-thread:make-mutex :name "chat room"))
(defparameter *room-size* 100)
(defvar *room-channel* (make-channel "chat room"))

(defun post-message (nick text)
  "Add TEXT from NICK to the room and tell every open page."
  (sb-thread:with-mutex (*room-lock*)
    (push (make-chat-message :nick nick :text text :time (get-universal-time)) *room*)
    (when (> (length *room*) *room-size*)
      (setf *room* (subseq *room* 0 *room-size*))))
  (publish *room-channel*))

(defun room-messages ()
  "The room's messages, oldest first."
  (sb-thread:with-mutex (*room-lock*) (reverse *room*)))

(defun clear-room ()
  "Empty the room."
  (sb-thread:with-mutex (*room-lock*) (setf *room* '()))
  (publish *room-channel*))

(defclass message-list (component updatable)
  ((chat :initarg :chat :reader list-chat))
  (:documentation "The room's messages, re-rendered whenever anyone posts."))

(defmethod updatable-wrapper ((self message-list))
  ;; New messages are announced to screen readers.
  (values "div" '(:aria-live "polite")))

(defmethod subscriptions ((self message-list))
  (list *room-channel*))

(defmethod render ((self message-list))
  (let ((messages (room-messages))
        (me (chat-nick (list-chat self))))
    (div (:class "chat-messages")
      (if (null messages)
          (p (:class "empty") "No messages yet. Say hello!")
          (dolist (m messages)
            (div (:class (list "chat-message" (when (equal (chat-message-nick m) me) "mine")))
              (span (:class "chat-time")
                (text (multiple-value-bind (s mi h) (decode-universal-time (chat-message-time m))
                        (declare (ignore s))
                        (format nil "~2,'0D:~2,'0D" h mi))))
              (strong (:class "chat-nick") (text (chat-message-nick m)))
              (span (:class "chat-text") (text (chat-message-text m)))))))))

(defclass composer (component updatable)
  ((chat :initarg :chat :reader composer-chat)
   (draft :initform "" :accessor composer-draft))
  (:documentation "The field for writing a message."))

(defun send-draft (composer)
  "Post COMPOSER's draft, if it says anything, and clear it."
  (let ((text (string-trim " " (composer-draft composer))))
    (unless (string= text "")
      (post-message (chat-nick (composer-chat composer)) text))
    (setf (composer-draft composer) "")))

(defmethod render ((self composer))
  (let ((chat (composer-chat self)))
    (form (:class "chat-composer"
           :on-submit (ajax :callback (lambda () (send-draft self))
                            :update (list self (chat-messages chat))))
      (text-input (:id "draft" :value (composer-draft self) :autofocus t :autocomplete "off"
                   :label "Message"
                   :placeholder (format nil "Message as ~A" (chat-nick chat))
                   :callback (lambda (v) (setf (composer-draft self) v))))
      (submit-button () "Send"))))

(defclass chat (component)
  ((nick :initform nil :accessor chat-nick)
   (messages :reader chat-messages)
   (composer :reader chat-composer))
  (:documentation "The chat page: ask for a nickname, then show the room."))

(defmethod initialize-instance :after ((self chat) &key)
  (setf (slot-value self 'messages) (make-instance 'message-list :chat self)
        (slot-value self 'composer) (make-instance 'composer :chat self)))

(defmethod children ((self chat))
  (list (chat-messages self) (chat-composer self)))

(defun ask-nick (chat)
  "Ask for a nickname, refusing blank ones."
  (show chat (validate-with (make-instance 'input-dialog :message "Pick a nickname")
                            (lambda (nick)
                              (when (string= (string-trim " " nick) "")
                                "A nickname needs at least one letter.")))
        :on-answer (lambda (nick) (setf (chat-nick chat) (string-trim " " nick)))))

(defmethod render ((self chat))
  (h1 () "Chat")
  (cond ((null (chat-nick self))
         (p () "Open this page in two browsers to talk to yourself. "
           (anchor (:callback (lambda () (ask-nick self))) "Join the room")))
        (t
         (render-component (chat-messages self))
         (render-component (chat-composer self))
         (p (:class "chat-who") "You are " (strong () (text (chat-nick self))) ". "
           (anchor (:callback (lambda () (ask-nick self))) "Change nickname")))))

(defmethod style ((self chat))
  ".chat-messages { height: 22rem; overflow-y: auto; border: 1px solid var(--lt-border);
                  border-radius: 6px; padding: .5rem; display: flex; flex-direction: column; gap: .3rem; }
.chat-message { display: flex; flex-wrap: wrap; gap: 0 .5rem; align-items: baseline; }
.chat-message.mine .chat-nick { color: var(--lt-accent); }
.chat-time { color: var(--lt-muted); font-size: .8rem; font-variant-numeric: tabular-nums; }
.chat-composer { display: flex; gap: .5rem; margin-top: .5rem; }
.chat-composer input { flex: 1; min-width: 0; }
.chat-who { font-size: .85rem; color: var(--lt-muted); }")

(defmethod script ((self chat))
  ;; Keep the newest message in view after each update.
  "document.addEventListener('littoral:updated', function () {
  var m = document.querySelector('.chat-messages'); if (m) m.scrollTop = m.scrollHeight; });
document.addEventListener('DOMContentLoaded', function () {
  var m = document.querySelector('.chat-messages'); if (m) m.scrollTop = m.scrollHeight; });")
