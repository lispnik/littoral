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
;;;; A socket opens only for a page of a live session (its URL names the
;;;; session and page keys), from a page of this site (Origin must match the
;;;; host), within the stream limits.  Messages are limited to *MAX-MESSAGE-
;;;; SIZE*.  When the session's key changes (its user signs in or out), its
;;;; sockets close.
;;;;
;;;; Messages from the page:   {"id": N, "params": {name: value, ...}}
;;;; Messages to the page:     {"type": "reply", "id": N, "data": {...}}
;;;;                           {"type": "update" | "toast" | "reload", "data": ...}

(defpackage #:littoral.websocket
  (:use #:cl #:littoral)
  (:documentation "Carry Littoral's AJAX and server push over WebSockets.")
  (:export #:*max-message-size* #:*allowed-origins*))

(in-package #:littoral.websocket)

(defvar *max-message-size* (* 1024 1024)
  "The largest message, in bytes, a page may send over its socket.")

(defvar *allowed-origins* '()
  "Origins (such as \"https://app.example.org\") allowed to open sockets
besides the server's own host, for pages served from another name.")

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
  "The id (an integer) and parameters (an alist of strings) of MESSAGE, a
JSON string; NIL when it is not a well-formed request."
  (let* ((object (ignore-errors (com.inuoe.jzon:parse message :max-depth 4)))
         (id (and (hash-table-p object) (gethash "id" object)))
         (params (and (hash-table-p object) (gethash "params" object))))
    (when (and (integerp id) (hash-table-p params))
      (values id
              (loop for key being the hash-keys of params using (hash-value value)
                    when (or (stringp value) (realp value))
                      collect (cons key (if (stringp value) value (princ-to-string value))))))))

(defun handle-message (stream application message send)
  "Answer MESSAGE, an AJAX request, as a POST of the same parameters would be.
Messages for a stream that has been closed, or a session that has expired,
are ignored."
  (let ((session (littoral::stream-session stream)))
    (multiple-value-bind (id parameters) (message-parameters message)
      (when (and id (littoral::stream-open-p stream)
                 (not (littoral::session-expired-p session)))
        (let ((*session* session)
              (*application* application)
              (littoral::*base-path* (littoral::stream-base-path stream))
              (littoral::*current-stream* stream))
          (littoral::with-sane-printing ()
            (let ((json (handler-case
                            (littoral::call-around-request
                             application
                             (lambda ()
                               (sb-thread:with-recursive-lock ((littoral::session-lock session))
                                 (setf (littoral::session-last-access session) (littoral::now-seconds))
                                 (littoral::ajax-json session (littoral::stream-continuation stream)
                                                      parameters))))
                          (error (e)
                            ;; Only development pages hear what went wrong.
                            (format nil "{\"error\":~A}"
                                    (littoral::json-string
                                     (if (littoral::development-p application)
                                         (princ-to-string e)
                                         "The request failed.")))))))
              (funcall send (format nil "{\"type\":\"reply\",\"id\":~D,\"data\":~A}" id json)))))))))

(defun same-origin-p (request)
  "True when REQUEST's Origin, if it has one, is this server's host or one of
*ALLOWED-ORIGINS*.  Browsers always send Origin with WebSocket requests;
other clients still need the session and page keys."
  (let* ((headers (lack/request:request-headers request))
         (origin (gethash "origin" headers))
         (host (or (and littoral:*trust-forwarded-for* (gethash "x-forwarded-host" headers))
                   (gethash "host" headers))))
    (or (null origin)
        (member origin *allowed-origins* :test #'string-equal)
        ;; An origin is scheme://host[:port], the port only when not the
        ;; scheme's default, just as the Host header writes it.
        (let ((authority (cl-ppcre:register-groups-bind (a) ("^[a-z][a-z0-9+.-]*://([^/]+)$" origin) a)))
          (and authority host (string-equal authority host))))))

(defun handle-websocket (session continuation)
  "Answer a page's WebSocket request: carry its AJAX and its pushes.  403
from another site, 503 beyond the stream limits."
  (unless (same-origin-p *request*)
    (return-from handle-websocket
      (list 403 (list* :content-type "text/plain" littoral::*security-headers*)
            (list "Cross-origin WebSocket refused."))))
  (let ((refusal (littoral::too-many-streams-response session)))
    (when refusal (return-from handle-websocket refusal)))
  (let* ((socket (wsd:make-server (lack/request:request-env *request*)
                                  :max-length *max-message-size*))
         (lock (sb-thread:make-mutex :name "littoral websocket send"))
         (application *application*)
         (base-path littoral::*base-path*)
         (stream (make-instance 'littoral::event-stream :session session :continuation continuation
                                                        :base-path base-path)))
    (labels ((send (string)
               (sb-thread:with-recursive-lock (lock)
                 (when (eq (wsd:ready-state socket) :open)
                   (wsd:send socket string))))
             (writer () (event-writer #'send)))
      (setf (littoral::stream-waker stream) (lambda () (queue-push stream (writer)))
            ;; Closing writes a frame too, so it takes the send lock.
            (littoral::stream-closer stream) (lambda ()
                                               (sb-thread:with-recursive-lock (lock)
                                                 (wsd:close-connection socket))))
      (wsd:on :open socket (lambda () (littoral::register-event-stream stream)))
      (wsd:on :message socket
              (lambda (message)
                (handler-case
                    (progn
                      (handle-message stream application message #'send)
                      ;; Its session's key changed while answering: the reply
                      ;; has told the page to move; now close.
                      (unless (littoral::stream-open-p stream)
                        (funcall (littoral::stream-closer stream))))
                  (error () (ignore-errors (funcall (littoral::stream-closer stream)))))))
      (wsd:on :close socket
              (lambda (&key code reason)
                (declare (ignore code reason))
                (setf (littoral::stream-open-p stream) nil)
                (littoral::unregister-event-stream stream)))
      (lambda (responder)
        (declare (ignore responder))
        (wsd:start-connection socket)))))

(setf littoral::*websocket-handler* 'handle-websocket)
