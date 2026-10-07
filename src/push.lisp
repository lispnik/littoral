;;;; push.lisp — the server re-renders components on open pages
;;;;
;;;; Seaside's Comet, done with server-sent events.  A component names the
;;;; CHANNELs it listens to with SUBSCRIPTIONS; any thread may PUBLISH a
;;;; channel, and every open page showing a subscriber gets that component
;;;; re-rendered and swapped in.  NOTIFY does the same for one component of
;;;; one session, for a background job reporting progress, say.
;;;;
;;;;   (defvar *news* (make-channel "news"))
;;;;   (defmethod subscriptions ((self headlines)) (list *news*))
;;;;   … (publish *news*) …
;;;;
;;;; Subscribers must be UPDATABLE.  Each open page holds one HTTP
;;;; connection, and with Hunchentoot one thread.

(in-package #:littoral)

(defclass channel ()
  ((name :initarg :name :initform nil :reader channel-name))
  (:documentation "Something components can subscribe to and threads PUBLISH."))

(defmethod print-object ((channel channel) stream)
  (print-unreadable-object (channel stream :type t :identity t)
    (format stream "~@[~A~]" (channel-name channel))))

(defun make-channel (&optional name)
  "A new channel, named NAME for printing."
  (make-instance 'channel :name name))

(defgeneric subscriptions (component)
  (:documentation "The channels whose PUBLISH re-renders COMPONENT on open pages.")
  (:method ((component component)) '()))

(defclass event-stream ()
  ((session :initarg :session :reader stream-session)
   (continuation :initarg :continuation :reader stream-continuation)
   (base-path :initarg :base-path :reader stream-base-path)
   (pending :initform '() :accessor stream-pending
            :documentation "Channels and component ids to re-render.")
   (open-p :initform t :accessor stream-open-p)
   (waker :initform nil :accessor stream-waker
          :documentation "On an event-loop server, a function (safe from any thread)
that has the loop serve the stream; NIL when a thread waits on it instead.")
   (lock :initform (sb-thread:make-mutex :name "littoral event stream") :reader stream-lock)
   (waitqueue :initform (sb-thread:make-waitqueue) :reader stream-waitqueue))
  (:documentation "One open page's server-sent event connection and the work queued for it."))

(defvar *event-streams* '())
(defvar *event-streams-lock* (sb-thread:make-mutex :name "littoral event streams"))

(defparameter *keepalive-seconds* 5
  "How often an idle stream sends a comment.  Writing is how a closed page
is noticed, so this bounds how long a gone page keeps its server thread.")

(defun open-event-streams ()
  "The event streams open now."
  (sb-thread:with-mutex (*event-streams-lock*) (copy-list *event-streams*)))

(defun wake (stream item)
  "Queue ITEM, a channel or component id, for STREAM and wake it."
  (sb-thread:with-mutex ((stream-lock stream))
    (push item (stream-pending stream))
    (sb-thread:condition-broadcast (stream-waitqueue stream)))
  (let ((waker (stream-waker stream)))
    (when waker (funcall waker))))

(defun register-event-stream (stream)
  "Count STREAM among the open ones."
  (sb-thread:with-mutex (*event-streams-lock*) (push stream *event-streams*)))

(defun unregister-event-stream (stream)
  (sb-thread:with-mutex (*event-streams-lock*)
    (setf *event-streams* (remove stream *event-streams*))))

(defun take-pending-now (stream)
  "STREAM's queued work, without waiting."
  (sb-thread:with-mutex ((stream-lock stream))
    (shiftf (stream-pending stream) '())))

(defun write-pending (stream writer pending)
  "Write what PENDING asks of STREAM: a reload, or updated components."
  (cond ((member :reload pending)
         (funcall writer (format nil "event: reload~%data: ~%~%")))
        (pending
         (let ((json (pushed-fragments stream pending)))
           (when json
             (funcall writer (format nil "event: update~%data: ~A~%~%" json)))))
        (t nil)))

(defun serve-stream (stream writer)
  "Write an update for STREAM's queued work, if any is visible.  For an
event loop to call when woken; signals if the connection has gone."
  (write-pending stream writer (take-pending-now stream)))

(defun keep-stream-alive (stream writer)
  "Write a keepalive comment to STREAM's connection."
  (declare (ignore stream))
  (funcall writer (format nil ": keepalive~%~%")))

(defun publish (channel)
  "Re-render, on every open page, the visible components subscribed to CHANNEL.
Safe to call from any thread.  Returns the number of pages told."
  (let ((count 0))
    (dolist (stream (open-event-streams) count)
      (wake stream channel)
      (incf count))))

(defmacro with-session ((session) &body body)
  "Run BODY as SESSION's requests do: holding its lock, with *SESSION* bound.
For other threads that change a session's components."
  (let ((s (gensym "SESSION")))
    `(let* ((,s ,session)
            (*session* ,s))
       (sb-thread:with-recursive-lock ((session-lock ,s))
         ,@body))))

(defun notify (component &optional (session *session*))
  "Re-render COMPONENT on SESSION's open pages.  Safe to call from any
thread, given the session (capture *SESSION* in the callback that starts
the work)."
  (dolist (stream (open-event-streams))
    (when (eq (stream-session stream) session)
      (wake stream (component-id component)))))

(defun close-event-streams ()
  "End every open stream; browsers reconnect when their page is current."
  (dolist (stream (open-event-streams))
    (sb-thread:with-mutex ((stream-lock stream))
      (setf (stream-open-p stream) nil)
      (sb-thread:condition-broadcast (stream-waitqueue stream)))
    (let ((waker (stream-waker stream)))
      (when waker (funcall waker)))))

(defun take-pending (stream timeout)
  "Wait up to TIMEOUT seconds for work; return it, or NIL."
  (sb-thread:with-mutex ((stream-lock stream))
    (when (and (null (stream-pending stream)) (stream-open-p stream))
      (sb-thread:condition-wait (stream-waitqueue stream) (stream-lock stream) :timeout timeout))
    (shiftf (stream-pending stream) '())))

(defun pushed-fragments (stream pending)
  "JSON for the visible components PENDING names, or NIL when none are."
  (let* ((session (stream-session stream))
         (continuation (stream-continuation stream))
         (*session* session)
         (*application* (session-application session))
         (*base-path* (stream-base-path stream)))
    (call-around-request
     *application*
     (lambda ()
    (sb-thread:with-recursive-lock ((session-lock session))
      (let* ((root (session-root session))
             (ids '()))
        (map-visible (lambda (c)
                       (when (or (member (component-id c) pending :test #'equal)
                                 (intersection (subscriptions c) pending))
                         (push (component-id c) ids)))
                     root)
        (when ids
          (let ((*render-context* (make-instance 'render-context
                                                 :callbacks (continuation-callbacks continuation)
                                                 :action-url (page-url session continuation)
                                                 :halos-p (and (development-p) (session-halos-p session))
                                                 :ajax-p t))
                (*rendering* t))
            (render-fragments (nreverse ids) root)))))))))

(defun stream-live-p (stream)
  "True while STREAM's session and page still exist and it has not been closed."
  (let ((session (stream-session stream)))
    (and (stream-open-p stream)
         (not (session-expired-p session))
         (find-continuation session (continuation-key (stream-continuation stream))))))

(defun run-event-stream (stream writer)
  "Serve STREAM through WRITER until its page is gone or the browser leaves."
  (register-event-stream stream)
  (unwind-protect
       (handler-case
           (progn
             (funcall writer (format nil "retry: 3000~%~%"))
             (loop while (stream-live-p stream)
                   do (let ((pending (take-pending stream *keepalive-seconds*)))
                        (when (stream-live-p stream)
                          (if pending
                              (write-pending stream writer pending)
                              (funcall writer (format nil ": keepalive~%~%")))))))
         ;; The browser went away: writing to its socket fails.
         (error () nil))
    (unregister-event-stream stream)
    (ignore-errors (funcall writer nil :close t))))

(defun async-socket (request)
  "The request's socket when the server is event-driven, else NIL."
  (let ((socket (getf (lack/request:request-env request) :clack.io))
        (package (find-package :clack.socket)))
    (and socket package
         (funcall (find-symbol "SOCKET-ASYNC-P" package) socket)
         socket)))

(defun handle-events (session continuation)
  "The response to a page's EventSource: a stream that runs until the page
is gone.  503 when too many are open."
  (let ((open (open-event-streams)))
    (when (or (>= (length open) *max-event-streams*)
              (>= (count session open :key #'stream-session) *max-event-streams-per-session*))
      (return-from handle-events
        (list 503 (list* :content-type "text/plain" :retry-after "30" *security-headers*)
              (list "Too many open event streams.")))))
  (let ((stream (make-instance 'event-stream :session session :continuation continuation
                                             :base-path *base-path*))
        (socket (and *async-stream-opener* (async-socket *request*)))
        (head (list 200 (append (list :content-type "text/event-stream"
                                      :cache-control "no-store"
                                      ;; Tell nginx not to buffer the stream.
                                      :x-accel-buffering "no")
                                *security-headers*))))
    (lambda (responder)
      ;; The server calls this later, outside the request's bindings.
      (with-sane-printing ()
       (let ((writer (funcall responder head)))
        (if socket
            ;; An event loop serves it: no thread waits on this stream.
            (funcall *async-stream-opener* socket stream writer)
            (run-event-stream stream writer)))))))

(defun page-listens-p (session)
  "True when SESSION's page should open an event stream: something on it
subscribes, or live reloading wants it."
  (or (page-subscribes-p (session-root session))
      (and *live-reload* (development-p (session-application session)))))

(defun page-subscribes-p (root)
  "True when a component visible from ROOT has subscriptions."
  (map-visible (lambda (c) (when (subscriptions c) (return-from page-subscribes-p t))) root)
  nil)
