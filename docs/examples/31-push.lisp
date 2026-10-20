;;;; The examples for server push: redrawing components on open pages.

;;;; Example: littoral:publish littoral:make-channel littoral:subscriptions littoral:channel
;;; A component names the channels it listens to; a page showing one opens an event stream.  PUBLISH, from any thread, redraws the subscribers on every open page.  OPEN-STREAM reads the page's stream as its EventSource would.
(defvar *news* (make-channel "news"))
(defvar *headline* "Calm seas")
(defclass headline (component updatable) ())
(defmethod subscriptions ((self headline)) (list *news*))
(defmethod render ((self headline))
  (h:p () (h:text *headline*)))
(defclass front-page (component)
  ((headline :initform (make-instance 'headline) :reader headline)))
(defmethod children ((self front-page)) (list (headline self)))
(defmethod render ((self front-page))
  (h:h1 () "The Littoral Times")
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
  (h:p () (h:text (format nil "~D unread" (unread self)))))
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
(defmethod render ((self alert-bar)) (h:p () "No alerts"))
(with-fresh-applications (("/alerts" 'alert-bar :mode :deployment))
  (let* ((b (make-instance 'browser))
         (sink (make-instance 'sink))
         (stream (progn (visit b "/alerts") (open-stream b sink))))
    (wait-for (lambda () (search "retry:" (sink-text sink))))
    (close-event-streams)
    (wait-for (lambda () (not (sb-thread:thread-alive-p stream))))))
;; ⇒ T

;;;; Example: littoral:find-presence littoral:presence littoral:presence-list littoral:presence-viewers
;;; A page showing a PRESENCE-LIST is in its presence while the page's event stream is open, and the list shows who else is: by name, or counted as guests.  The page being rendered counts itself even before its stream opens.  PRESENCE-VIEWERS gives the same as data.
(defclass lobby (component)
  ((here :initform (make-instance 'presence-list :presence (find-presence "lobby")) :reader here)))
(defmethod children ((self lobby)) (list (here self)))
(defmethod render ((self lobby)) (render-component (here self)))
(with-fresh-applications (("/lobby" 'lobby :mode :deployment))
  (let ((ada (make-instance 'browser)) (bob (make-instance 'browser)) (sink (make-instance 'sink)))
    (visit bob "/lobby")
    (open-stream bob sink)
    (visit ada "/lobby")
    (prog1 (list (body-text ada)
                 (let ((*session* nil)) (presence-viewers (find-presence "lobby"))))
      (close-event-streams))))
;; ⇒ ("2 people here You 1 guest" ((:NAME NIL :ACTIVITY NIL :YOU NIL)))

;;;; Example: littoral:presences littoral:presence-activity littoral:presence-name littoral:*presence-name-function*
;;; Any component can put its page in presences, and say what its person is doing there.  Names come from (SETF PRESENCE-NAME), or *PRESENCE-NAME-FUNCTION*, which littoral/auth sets to the signed-in user's name.
(defvar *doc* (find-presence "doc:7"))
(defclass doc-editor (component) ())
(defmethod presences ((self doc-editor)) (list *doc*))
(defmethod presence-activity ((self doc-editor)) "editing")
(defmethod render ((self doc-editor))
  (h:anchor (:callback (lambda () (setf (presence-name) "Ada"))) "I'm Ada"))
(defclass doc-page (component)
  ((here :initform (make-instance 'presence-list :presence *doc*) :reader here)))
(defmethod children ((self doc-page)) (list (here self)))
(defmethod render ((self doc-page)) (render-component (here self)))
(with-fresh-applications (("/edit" 'doc-editor :mode :deployment) ("/doc" 'doc-page :mode :deployment))
  (let ((editor (make-instance 'browser)) (reader (make-instance 'browser)) (sink (make-instance 'sink)))
    (visit editor "/edit")
    (click editor "I'm Ada")
    (open-stream editor sink)
    (visit reader "/doc")
    (prog1 (body-text reader)
      (close-event-streams))))
;; ⇒ "2 people here You Ada editing"

;;;; Example: littoral:presence-list-presence
;;; :PRESENCE may be a function, called each time, for a list that follows what the page shows, such as the wiki page open now.
(defvar *page-name* "Home")
(let ((list (make-instance 'presence-list :presence (lambda () (find-presence (format nil "wiki:~A" *page-name*))))))
  (list (eq (presence-list-presence list) (find-presence "wiki:Home"))
        (let ((*page-name* "Help")) (eq (presence-list-presence list) (find-presence "wiki:Help")))))
;; ⇒ (T T)

;;;; Example: littoral:*push-render-threads*
;;; On Hunchentoot, the push hub renders and writes pushed updates on this many threads, each page by one thread at a time; 1 renders on the hub's own thread, one page after another.
*push-render-threads*
;; ⇒ 4
