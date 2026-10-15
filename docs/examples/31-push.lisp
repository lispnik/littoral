;;;; The examples for server push: redrawing components on open pages.

;;;; Example: littoral:publish littoral:make-channel littoral:subscriptions littoral:channel
;;; A component names the channels it listens to; a page showing one opens an event stream.  PUBLISH, from any thread, redraws the subscribers on every open page.  OPEN-STREAM reads the page's stream as its EventSource would.
(defvar *news* (make-channel "news"))
(defvar *headline* "Calm seas")
(defclass headline (component updatable) ())
(defmethod subscriptions ((self headline)) (list *news*))
(defmethod render ((self headline))
  (p () (text *headline*)))
(defclass front-page (component)
  ((headline :initform (make-instance 'headline) :reader headline)))
(defmethod children ((self front-page)) (list (headline self)))
(defmethod render ((self front-page))
  (h1 () "The Littoral Times")
  (render-component (headline self)))
(with-fresh-applications (("/news" 'front-page :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/news") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (setf *headline* "Storm warning")
    (publish *news*)
    (prog1 (wait-for (lambda () (search "Storm warning" (sink-text sink))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ T

;;;; Example: littoral:notify littoral:with-session
;;; NOTIFY redraws one component on one session's pages: for work another thread does for that session.  The thread changes the component inside WITH-SESSION, as a request would, holding the session's lock.  The page listens because the inbox subscribes to a channel.  A real application would capture *SESSION* in the callback that starts the work.
(defvar *mail* (make-channel "mail"))
(defclass inbox (component updatable)
  ((unread :initform 0 :accessor unread)))
(defmethod subscriptions ((self inbox)) (list *mail*))
(defmethod render ((self inbox))
  (p () (text (format nil "~D unread" (unread self)))))
(defclass mail-page (component)
  ((inbox :initform (make-instance 'inbox) :reader inbox)))
(defmethod children ((self mail-page)) (list (inbox self)))
(defmethod render ((self mail-page))
  (render-component (inbox self)))
(with-fresh-applications (("/mail" 'mail-page :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/mail") (open-stream b sink)))
         (session (first (list-sessions (find-application "/mail"))))
         (inbox (inbox (session-root session))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (sb-thread:join-thread
     (sb-thread:make-thread
      (lambda ()
        (with-session (session) (incf (unread inbox) 3))
        (notify inbox session))))
    (prog1 (wait-for (lambda () (search "3 unread" (sink-text sink))))
      (close-event-streams)
      (wait-for (lambda () (not (sb-thread:thread-alive-p stream)))))))
;; ⇒ T

;;;; Example: littoral:close-event-streams
;;; End every open stream, as when stopping the server; a browser whose page is still current reconnects.
(defvar *alerts* (make-channel "alerts"))
(defclass alert-bar (component updatable) ())
(defmethod subscriptions ((self alert-bar)) (list *alerts*))
(defmethod render ((self alert-bar)) (p () "No alerts"))
(with-fresh-applications (("/alerts" 'alert-bar :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/alerts") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (close-event-streams)
    (wait-for (lambda () (not (sb-thread:thread-alive-p stream))))))
;; ⇒ T
