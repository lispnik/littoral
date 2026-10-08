;;;; websocket.lisp — AJAX and server push over one WebSocket per page
;;;;
;;;;   (asdf:load-system :littoral/websocket)
;;;;   (register-application "/chat" 'chat :websockets t)
;;;;
;;;; Pages of such an application that have server push open one WebSocket
;;;; instead of an event stream, and send their AJAX requests over it too:
;;;; one connection, no request per click.  littoral.js falls back to fetch
;;;; and server-sent events when the socket cannot be opened.  On event-loop
;;;; servers (Woo), pages keep server-sent events, which already cost little
;;;; there.
;;;;
;;;; Messages from the page:   {"id": N, "params": {name: value, ...}}
;;;; Messages to the page:     {"type": "reply", "id": N, "data": {...}}
;;;;                           {"type": "update" | "toast" | "reload", "data": ...}

(defpackage #:littoral.websocket
  (:use #:cl #:littoral)
  (:documentation "Carry Littoral's AJAX and server push over WebSockets."))

(in-package #:littoral.websocket)

;;; Rendering pushes off the publisher's thread
;;;
;;; PUBLISH may be called by a request holding its own session's lock;
;;; rendering another session's page there could deadlock with a request
;;; doing the reverse.  So pushes are queued for a couple of worker threads
;;; that hold no locks of their own.

(defvar *push-queue* '())
(defvar *push-lock* (sb-thread:make-mutex :name "littoral websocket pushes"))
(defvar *push-ready* (sb-thread:make-waitqueue))
(defvar *push-workers* '())

(defun push-worker ()
  (loop
    (let ((job (sb-thread:with-mutex (*push-lock*)
                 (loop while (null *push-queue*)
                       do (sb-thread:condition-wait *push-ready* *push-lock*))
                 (pop *push-queue*))))
      (destructuring-bind (stream . writer) job
        (littoral::with-sane-printing ()
          (handler-case (littoral::serve-stream stream writer)
            (error () (setf (littoral::stream-open-p stream) nil))))))))

(defun queue-push (stream writer)
  "Have a worker serve STREAM's queued work through WRITER."
  (sb-thread:with-mutex (*push-lock*)
    (unless (find stream *push-queue* :key #'car)
      (setf *push-queue* (append *push-queue* (list (cons stream writer)))))
    (when (< (length *push-workers*) 2)
      (push (sb-thread:make-thread #'push-worker :name "littoral websocket push") *push-workers*))
    (sb-thread:condition-notify *push-ready*)))

;;; From the server-sent event text the push code writes, to messages

(defun event-writer (send)
  "A writer for SERVE-STREAM that turns each \"event: NAME / data: DATA\"
block into a {\"type\": NAME, \"data\": DATA} message for SEND."
  (lambda (text &rest options)
    (declare (ignore options))
    (when (stringp text)
      (let ((event (cl-ppcre:register-groups-bind (name) ("(?m)^event: (\\S+)$" text) name))
            (data (cl-ppcre:register-groups-bind (d) ("(?m)^data: (.*)$" text) d)))
        (when event
          (funcall send (format nil "{\"type\":~A,\"data\":~A}"
                                (littoral::json-string event)
                                (if (or (null data) (string= data "")) "null" data))))))))

;;; Messages from the page

(defun message-parameters (message)
  "The id and parameters (an alist of strings) of MESSAGE, a JSON string."
  (let ((object (com.inuoe.jzon:parse message)))
    (values (gethash "id" object)
            (let ((params (gethash "params" object)))
              (loop for key being the hash-keys of params using (hash-value value)
                    collect (cons key (if (stringp value) value (princ-to-string value))))))))

(defun handle-message (session continuation application base-path message send)
  "Answer MESSAGE, an AJAX request, as a POST of the same parameters would be."
  (multiple-value-bind (id parameters) (message-parameters message)
    (let ((*session* session)
          (*application* application)
          (littoral::*base-path* base-path))
      (littoral::with-sane-printing ()
        (let ((json (handler-case
                        (littoral::call-around-request
                         application
                         (lambda ()
                           (sb-thread:with-recursive-lock ((littoral::session-lock session))
                             (setf (littoral::session-last-access session) (littoral::now-seconds))
                             (littoral::ajax-json session continuation parameters))))
                      (error (e)
                        (format nil "{\"error\":~A}" (littoral::json-string (princ-to-string e)))))))
          (funcall send (format nil "{\"type\":\"reply\",\"id\":~A,\"data\":~A}" id json)))))))

(defun handle-websocket (session continuation)
  "Answer a page's WebSocket request: carry its AJAX and its pushes."
  (let* ((socket (wsd:make-server (lack/request:request-env *request*)))
         (lock (sb-thread:make-mutex :name "littoral websocket send"))
         (application *application*)
         (base-path littoral::*base-path*)
         (stream (make-instance 'littoral::event-stream :session session :continuation continuation
                                                        :base-path base-path)))
    (labels ((send (string)
               (sb-thread:with-mutex (lock)
                 (when (eq (wsd:ready-state socket) :open)
                   (wsd:send socket string))))
             (writer () (event-writer #'send)))
      (setf (littoral::stream-waker stream) (lambda () (queue-push stream (writer))))
      (wsd:on :open socket (lambda () (littoral::register-event-stream stream)))
      (wsd:on :message socket
              (lambda (message)
                (handle-message session continuation application base-path message #'send)))
      (wsd:on :close socket
              (lambda (&key code reason)
                (declare (ignore code reason))
                (setf (littoral::stream-open-p stream) nil)
                (littoral::unregister-event-stream stream)))
      (lambda (responder)
        (declare (ignore responder))
        (wsd:start-connection socket)))))

(setf littoral::*websocket-handler* 'handle-websocket)
