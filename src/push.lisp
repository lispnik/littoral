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
;;;; connection.  On Hunchentoot the connection leaves its request thread
;;;; once the response has begun, and one hub thread serves them all (see
;;;; "The Hunchentoot hub" below); on Woo the event loops serve them
;;;; (littoral/woo).  Elsewhere, as in the tests, a thread waits on each.

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
  (:documentation "The channels whose PUBLISH re-renders COMPONENT on open pages;
none by default.  A page showing a component with subscriptions opens an
event stream.  Subscribers must be UPDATABLE.")
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
   (closer :initform nil :accessor stream-closer
           :documentation "A function closing the connection at once, or NIL when
marking the stream closed is enough (it ends at its next wake or keepalive).")
   (presences :initform '() :accessor stream-presences
              :documentation "The presences its page is in (see presence.lisp).")
   (activity :initform nil :accessor stream-activity :documentation "What its person is doing there, or NIL.")
   (viewer :initform nil :accessor stream-viewer :documentation "Its person's name, or NIL for a guest.")
   (opened :initform (get-internal-real-time) :reader stream-opened)
   (request-id :initform *request-id* :reader stream-request-id
               :documentation "The id of the request that opened it, for the request log.")
   (address :initform (and *request* (lack/request:request-remote-addr *request*)) :reader stream-address)
   (updates :initform 0 :accessor stream-updates :documentation "Events written to it, keepalives aside.")
   (lock :initform (sb-thread:make-mutex :name "littoral event stream") :reader stream-lock)
   (waitqueue :initform (sb-thread:make-waitqueue) :reader stream-waitqueue))
  (:documentation "One open page's server-sent event connection and the work queued for it."))

(defvar *event-streams* '())
(defvar *event-streams-lock* (sb-thread:make-mutex :name "littoral event streams"))

(defparameter *keepalive-seconds* 5
  "How often an idle stream sends a comment.  Writing is how a closed page
is noticed, so this bounds how long a gone page keeps its connection.")

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
  (sb-thread:with-mutex (*event-streams-lock*) (push stream *event-streams*))
  (presence-stream-changed stream))

(defvar *stream-closed-function* nil
  "A function called with each event stream as it closes: the request log's (observe.lisp).")

(defun unregister-event-stream (stream)
  (let ((found nil))
    (sb-thread:with-mutex (*event-streams-lock*)
      (setf found (member stream *event-streams*)
            *event-streams* (remove stream *event-streams*)))
    (when found
      (presence-stream-changed stream)
      (when *stream-closed-function*
        (ignore-errors (funcall *stream-closed-function* stream))))))

(defun take-pending-now (stream)
  "STREAM's queued work, without waiting."
  (sb-thread:with-mutex ((stream-lock stream))
    (shiftf (stream-pending stream) '())))

(defun wake-streams-for-toasts (session)
  "Have SESSION's open pages show its waiting toasts now."
  (dolist (stream (open-event-streams))
    (when (eq (stream-session stream) session)
      (wake stream :toasts))))

(defun write-pending (stream writer pending)
  "Write what PENDING asks of STREAM: a reload, toasts, or updated components."
  (when (member :toasts pending)
    (let ((toasts (let ((*session* (stream-session stream)))
                    (sb-thread:with-recursive-lock ((session-lock *session*))
                      (take-toasts)))))
      (when toasts
        (funcall writer (format nil "event: toast~%data: ~A~%~%" (toasts-json toasts)))
        (incf (stream-updates stream))))
    (setf pending (remove :toasts pending)))
  (cond ((member :reload pending)
         (funcall writer (format nil "event: reload~%data: ~%~%"))
         (incf (stream-updates stream)))
        (pending
         (let ((json (pushed-fragments stream pending)))
           (when json
             (funcall writer (format nil "event: update~%data: ~A~%~%" json))
             (incf (stream-updates stream)))))
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
Safe to call from any thread: it only queues the work, which each page's
stream does.  Returns the number of open pages woken, whether or not they
show a subscriber."
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

(defvar *current-stream* nil
  "The stream whose message is being answered, if any; it closes itself
after replying.")

(defun close-stream (stream)
  "End STREAM: mark it closed and wake or close whatever serves it."
  (sb-thread:with-mutex ((stream-lock stream))
    (setf (stream-open-p stream) nil)
    (sb-thread:condition-broadcast (stream-waitqueue stream)))
  (let ((closer (stream-closer stream))
        (waker (stream-waker stream)))
    (cond ((and closer (not (eq stream *current-stream*))) (ignore-errors (funcall closer)))
          (waker (funcall waker)))))

(defun close-event-streams ()
  "End every open stream; browsers reconnect when their page is current."
  (mapc #'close-stream (open-event-streams)))

(defun close-session-streams (session)
  "End SESSION's open streams and sockets."
  (dolist (stream (open-event-streams))
    (when (eq (stream-session stream) session)
      (close-stream stream))))

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

;;; The Hunchentoot hub
;;;
;;; Hunchentoot answers each connection in a thread of its own, and an
;;; event stream never finishes, so served the usual way every open page
;;; would keep a thread (and its stack) for as long as it stays open.
;;; Instead the stream's response head is written straight to the socket,
;;; the socket is detached from Hunchentoot (which then lets the thread
;;; go without closing it), and the hub's one thread writes every stream's
;;; updates and keepalives.  It runs while any stream is open.

(defstruct (hub-entry (:constructor make-hub-entry (stream socket out)))
  "A stream the hub serves: its EVENT-STREAM, usocket, and the octet stream
to write: the socket's own, or the TLS stream over it.  BUSY while a
render thread serves it, so only one ever writes to it."
  stream socket out (keepalive-due 0) (busy nil))

(defparameter *push-render-threads* 4
  "How many threads the push hub renders and writes pushed updates with:
pages are served in parallel, each by one thread at a time.  1 serves them
all on the hub's own thread, one page after another.")

(defvar *hub-work* '() "Entries waiting for a render thread, oldest last.  Under *HUB-LOCK*.")
(defvar *hub-work-waitqueue* (sb-thread:make-waitqueue :name "littoral push hub work"))
(defvar *hub-workers* 0 "How many render threads run.  Under *HUB-LOCK*.")

(defvar *hub-entries* '())
(defvar *hub-lock* (sb-thread:make-mutex :name "littoral push hub"))
(defvar *hub-waitqueue* (sb-thread:make-waitqueue :name "littoral push hub"))
(defvar *hub-woken* nil "True when the hub has work it hasn't looked at yet.")
(defvar *hub-thread* nil "The hub's thread while it runs.")

(defun wake-hub ()
  "Have the hub look at its streams now.  Safe from any thread."
  (sb-thread:with-mutex (*hub-lock*)
    (setf *hub-woken* t)
    (sb-thread:condition-broadcast *hub-waitqueue*)))

(defun hub-stream-count ()
  "How many streams the hub serves now."
  (sb-thread:with-mutex (*hub-lock*) (length *hub-entries*)))

(defun hub-socket ()
  "The socket of the request being answered, when Hunchentoot answers it
and the hub can take it over (its stream an fd-stream), and the stream to
write the response to: the socket's own, or with TLS the stream over it.
Else NIL."
  (and (boundp 'hunchentoot:*acceptor*)
       (typep hunchentoot:*acceptor* 'clack.handler.hunchentoot::clack-acceptor)
       (boundp 'clack.handler.hunchentoot::*client-socket*)
       (boundp 'hunchentoot::*hunchentoot-stream*)
       (let ((socket clack.handler.hunchentoot::*client-socket*)
             (connection hunchentoot::*hunchentoot-stream*))
         (and (typep socket 'usocket:stream-usocket)
              (typep (usocket:socket-stream socket) 'sb-sys:fd-stream)
              connection
              (values socket (if (typep connection 'chunga:chunked-stream)
                                 (chunga:chunked-stream-stream connection)
                                 connection))))))

(defun response-head-octets (status headers)
  "The octets of a response head for STATUS and HEADERS (a plist).  The
body ends when the connection closes, as HTTP/1.0 and 1.1 both allow, so
there is neither a length nor chunking."
  (let ((crlf (coerce '(#\Return #\Linefeed) 'string)))
    (sb-ext:string-to-octets
     (with-output-to-string (out)
       (format out "HTTP/1.1 ~D OK~A" status crlf)
       (loop for (name value) on headers by #'cddr
             do (format out "~A: ~A~A" (string-capitalize (symbol-name name)) value crlf))
       (format out "Connection: close~A~A" crlf crlf))
     :external-format :latin-1)))

(defun hub-writer (out socket)
  "A writer, as Clack's responders return, for the hub's stream OUT.  It
refuses to wait on a client that has stopped reading: when SOCKET can't
take more, the stream is dropped (the browser reconnects later)."
  (let ((fd (sb-sys:fd-stream-fd (usocket:socket-stream socket))))
    (lambda (body &key close)
      (when body
        (unless (sb-unix:unix-simple-poll fd :output 0)
          (error "The client isn't reading its event stream."))
        (write-sequence (if (stringp body) (sb-ext:string-to-octets body :external-format :utf-8) body) out)
        (force-output out))
      (when close
        (ignore-errors (finish-output out))))))

(defun close-hub-entry (entry)
  "Stop serving ENTRY and close its connection.  On the hub's thread."
  (sb-thread:with-mutex (*hub-lock*)
    (setf *hub-entries* (delete entry *hub-entries*)))
  (unregister-event-stream (hub-entry-stream entry))
  (ignore-errors (finish-output (hub-entry-out entry)))
  ;; A TLS stream says goodbye before the socket closes.
  (unless (eq (hub-entry-out entry) (usocket:socket-stream (hub-entry-socket entry)))
    (ignore-errors (close (hub-entry-out entry))))
  (ignore-errors (usocket:socket-close (hub-entry-socket entry))))

(defun serve-hub-entry (entry now)
  "Write ENTRY's queued work, or a keepalive when one is due at NOW, or
close it when its page has gone or writing fails."
  (let ((stream (hub-entry-stream entry))
        (writer (hub-writer (hub-entry-out entry) (hub-entry-socket entry))))
    (handler-case
        (cond ((not (stream-live-p stream)) (close-hub-entry entry))
              (t (let ((pending (take-pending-now stream)))
                   (cond (pending
                          (write-pending stream writer pending)
                          (setf (hub-entry-keepalive-due entry) (keepalive-time now)))
                         ((>= now (hub-entry-keepalive-due entry))
                          (keep-stream-alive stream writer)
                          (setf (hub-entry-keepalive-due entry) (keepalive-time now)))))))
      (error () (close-hub-entry entry)))))

(defun keepalive-time (now)
  "The internal real time a keepalive is due, *KEEPALIVE-SECONDS* after NOW."
  (+ now (round (* *keepalive-seconds* internal-time-units-per-second))))

(defun needs-serving-p (entry now)
  "True when ENTRY has work queued, a keepalive due at NOW, or has closed."
  (let ((stream (hub-entry-stream entry)))
    (or (stream-pending stream)
        (not (stream-open-p stream))
        (>= now (hub-entry-keepalive-due entry)))))

(defun run-hub-worker ()
  "Serve the entries the hub hands over, until the hub stops."
  (with-sane-printing ()
    (loop
      (let ((entry (sb-thread:with-mutex (*hub-lock*)
                     (loop while (and (null *hub-work*) *hub-thread*)
                           do (sb-thread:condition-wait *hub-work-waitqueue* *hub-lock*))
                     (if *hub-work*
                         ;; Taken off the queue under the same lock it was found under.
                         (prog1 (car (last *hub-work*))
                           (setf *hub-work* (butlast *hub-work*)))
                         (progn (decf *hub-workers*) (return))))))
        (unwind-protect (serve-hub-entry entry (get-internal-real-time))
          (sb-thread:with-mutex (*hub-lock*)
            (setf (hub-entry-busy entry) nil)
            ;; Work that came in meanwhile: have the hub look again.
            (when (stream-pending (hub-entry-stream entry))
              (setf *hub-woken* t)
              (sb-thread:condition-broadcast *hub-waitqueue*))))))))

(defun hand-over (entries now)
  "Serve those of ENTRIES that need it: on render threads, or here when
*PUSH-RENDER-THREADS* is 1."
  (if (<= *push-render-threads* 1)
      (dolist (entry entries)
        (serve-hub-entry entry now))
      (sb-thread:with-mutex (*hub-lock*)
        (dolist (entry entries)
          (when (and (not (hub-entry-busy entry)) (needs-serving-p entry now))
            (setf (hub-entry-busy entry) t)
            (push entry *hub-work*)))
        (loop while (< *hub-workers* (min *push-render-threads* (length *hub-work*) ))
              do (incf *hub-workers*)
                 (sb-thread:make-thread #'run-hub-worker :name "littoral push render"))
        (sb-thread:condition-broadcast *hub-work-waitqueue*))))

(defun run-hub ()
  "Serve the hub's streams until there are none."
  (with-sane-printing ()
    (loop
      (let ((entries
              (sb-thread:with-mutex (*hub-lock*)
                (when (null *hub-entries*)
                  (setf *hub-thread* nil)
                  ;; Render threads end once their work is done.
                  (sb-thread:condition-broadcast *hub-work-waitqueue*)
                  (return))
                (unless *hub-woken*
                  (let ((due (reduce #'min *hub-entries* :key #'hub-entry-keepalive-due)))
                    (sb-thread:condition-wait
                     *hub-waitqueue* *hub-lock*
                     :timeout (max 0.01 (/ (- due (get-internal-real-time)) internal-time-units-per-second)))))
                (setf *hub-woken* nil)
                (copy-list *hub-entries*))))
        (hand-over entries (get-internal-real-time))))))

(defun hub-take-over (stream socket out head)
  "Answer the current Hunchentoot request with STREAM, served by the hub
over SOCKET, writing to OUT: write HEAD's status and headers, detach the
socket, and return, letting the request's thread go."
  (progn
    (write-sequence (response-head-octets (first head) (second head)) out)
    (write-sequence (sb-ext:string-to-octets (format nil "retry: 3000~%~%") :external-format :utf-8) out)
    (force-output out)
    ;; Hunchentoot neither answers again nor closes the connection.
    (setf hunchentoot::*headers-sent* t)
    (hunchentoot:detach-socket hunchentoot:*acceptor*)
    (let ((entry (make-hub-entry stream socket out)))
      (setf (hub-entry-keepalive-due entry) (keepalive-time (get-internal-real-time))
            (stream-waker stream) #'wake-hub)
      (register-event-stream stream)
      (sb-thread:with-mutex (*hub-lock*)
        (push entry *hub-entries*)
        (setf *hub-woken* t)
        (if *hub-thread*
            (sb-thread:condition-broadcast *hub-waitqueue*)
            (setf *hub-thread* (sb-thread:make-thread #'run-hub :name "littoral push hub")))))))

(defun async-socket (request)
  "The request's socket when the server is event-driven, else NIL."
  (let ((socket (getf (lack/request:request-env request) :clack.io))
        (package (find-package :clack.socket)))
    (and socket package
         (funcall (find-symbol "SOCKET-ASYNC-P" package) socket)
         socket)))

(defun too-many-streams-response (session)
  "A 503 response when no more streams may open, for SESSION or at all; else NIL."
  (let ((open (open-event-streams)))
    (when (or (>= (length open) *max-event-streams*)
              (>= (count session open :key #'stream-session) *max-event-streams-per-session*))
      (list 503 (list* :content-type "text/plain" :retry-after "30" *security-headers*)
            (list "Too many open event streams.")))))

(defun handle-events (session continuation)
  "The response to a page's EventSource: a stream that runs until the page
is gone.  503 when too many are open."
  (let ((refusal (too-many-streams-response session)))
    (when refusal (return-from handle-events refusal)))
  (let ((stream (let ((stream (make-instance 'event-stream :session session :continuation continuation
                                                           :base-path *base-path*)))
                  (note-stream-presences stream)
                  stream))
        (socket (and *async-stream-opener* (async-socket *request*)))
        (head (list 200 (append (list :content-type "text/event-stream"
                                      :cache-control "no-store"
                                      ;; Tell nginx not to buffer the stream.
                                      :x-accel-buffering "no")
                                *security-headers*))))
    (lambda (responder)
      ;; The server calls this later, outside the request's bindings.
      (with-sane-printing ()
        (multiple-value-bind (hub-socket out) (and (not socket) (hub-socket))
          (if hub-socket
              ;; The hub serves it: this thread goes back to Hunchentoot.
              (hub-take-over stream hub-socket out head)
              (let ((writer (funcall responder head)))
                (if socket
                    ;; An event loop serves it: no thread waits on this stream.
                    (funcall *async-stream-opener* socket stream writer)
                    (run-event-stream stream writer)))))))))

(defun page-listens-p (session)
  "True when SESSION's page should open an event stream: something on it
subscribes."
  (page-subscribes-p (session-root session)))

(defun page-polls-p (session)
  "True when SESSION's page should poll for live reloads: it is in
development mode and has no event stream to hear them through."
  (and *live-reload*
       (development-p (session-application session))
       (not (page-listens-p session))))

(defun page-subscribes-p (root)
  "True when a component visible from ROOT has subscriptions or presences."
  (map-visible (lambda (c) (when (or (subscriptions c) (presences c)) (return-from page-subscribes-p t))) root)
  nil)
