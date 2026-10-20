;;;; presence.lisp — who has a page open, and what they're doing there
;;;;
;;;; A PRESENCE is a channel that open pages are "in".  A page is in the
;;;; presences its visible components name with PRESENCES while its event
;;;; stream (or WebSocket) is open, and PRESENCE-ACTIVITY says what its
;;;; person is doing ("editing").  Who is where is worked out from the open
;;;; streams, which note their presences, activity and person's name when
;;;; they open and after each AJAX request, under their own session's lock:
;;;; never another session's, so pages rendering each other's presence
;;;; can't deadlock.  Each change publishes the presences it touches, which
;;;; re-renders the PRESENCE-LISTs on the pages in them.

(in-package #:littoral)

(defclass presence (channel) ()
  (:documentation "A place pages can be in, such as one wiki page; make or
find one with FIND-PRESENCE.  It is a channel: PRESENCE-LIST subscribes to
it, and it is published whenever someone arrives, leaves or changes what
they're doing."))

(defvar *presences* (make-hash-table :test 'equal :weakness :value :synchronized t)
  "Key → PRESENCE, kept while something refers to it.")

(defun find-presence (key)
  "The presence for KEY (compared with EQUAL), such as \"wiki:Home\", made
the first time it is asked for."
  (or (gethash key *presences*)
      (sb-ext:with-locked-hash-table (*presences*)
        (or (gethash key *presences*)
            (setf (gethash key *presences*) (make-instance 'presence :name key))))))

(defgeneric presences (component)
  (:documentation "The presences COMPONENT puts its page in while the page
is open and shows it; none by default.  A page showing any opens an event
stream, as one with SUBSCRIPTIONS does.")
  (:method ((component component)) '()))

(defgeneric presence-activity (component)
  (:documentation "What the person whose page shows COMPONENT is doing, a
short text such as \"editing\" that PRESENCE-LIST shows by their name; or
NIL, the default.  The first visible component with one decides.")
  (:method ((component component)) nil))

(defvar *presence-name-function* nil
  "A function of no arguments giving the name of the person making the
current request, or NIL for a guest; NIL itself makes everyone a guest
unless PRESENCE-NAME is set.  littoral/auth sets it to the signed-in user's
name.")

(defun presence-name (&optional (session *session*))
  "The name SESSION's person goes by in presence lists: what (SETF
PRESENCE-NAME) gave it, else *PRESENCE-NAME-FUNCTION*'s answer (in a
request of SESSION's), else NIL for a guest."
  (or (session-property 'presence-name session)
      (and *presence-name-function* (eq session *session*)
           (ignore-errors (funcall *presence-name-function*)))))

(defun (setf presence-name) (name &optional (session *session*))
  "Name SESSION's person NAME in presence lists (NIL to forget it).  Its
open pages' presences hear of it at once."
  (setf (session-property 'presence-name session) name)
  (dolist (stream (open-event-streams))
    (when (eq (stream-session stream) session)
      (let ((old (stream-viewer stream)))
        (setf (stream-viewer stream) name)
        (unless (equal old name)
          (mapc #'publish (stream-presences stream))))))
  name)

(defun page-presence-state (root)
  "The presences visible from ROOT, and the activity of the first visible
component with one."
  (let ((presences '()) (activity nil))
    (map-visible (lambda (c)
                   (dolist (p (presences c)) (pushnew p presences))
                   (unless activity (setf activity (presence-activity c))))
                 root)
    (values (nreverse presences) activity)))

(defun note-stream-presences (stream)
  "Record which presences STREAM's page is in, its activity and its
person's name, and publish the presences that changed when the stream is
already counted.  In a request of STREAM's session, holding its lock."
  (multiple-value-bind (presences activity) (page-presence-state (session-root (stream-session stream)))
    (let ((name (presence-name (stream-session stream)))
          (old-presences (stream-presences stream)))
      (unless (and (equal presences old-presences)
                   (equal activity (stream-activity stream))
                   (equal name (stream-viewer stream)))
        (setf (stream-presences stream) presences
              (stream-activity stream) activity
              (stream-viewer stream) name)
        (when (member stream (open-event-streams))
          (mapc #'publish (union presences old-presences)))))))

(defun note-session-presences (session)
  "After an AJAX request in SESSION, which may have changed what its pages
show: note its streams' presences again.  Holding SESSION's lock."
  (dolist (stream (open-event-streams))
    (when (eq (stream-session stream) session)
      (note-stream-presences stream))))

(defun presence-stream-changed (stream)
  "STREAM has opened or closed: tell its presences."
  (mapc #'publish (stream-presences stream)))

(defun presence-viewers (presence)
  "Who has a page in PRESENCE open now, one plist per session in the order
they came: :NAME (NIL for a guest), :ACTIVITY, and :YOU, true for the
current session.  The current session is included while it renders a page
in PRESENCE, even before that page's stream has opened."
  (let ((viewers '()))
    (dolist (stream (reverse (open-event-streams)))
      ;; Each stream noted its presences in a request of its own session.
      (when (and (member presence (stream-presences stream)) (stream-open-p stream))
        (let ((viewer (find (stream-session stream) viewers :key (lambda (v) (getf v :session)))))
          (if viewer
              ;; Another page of the same session: the first activity counts.
              (unless (getf viewer :activity)
                (setf (getf viewer :activity) (stream-activity stream)))
              (push (list :session (stream-session stream) :name (stream-viewer stream)
                          :activity (stream-activity stream))
                    viewers)))))
    (setf viewers (nreverse viewers))
    (when (and *session* (not (find *session* viewers :key (lambda (v) (getf v :session)))))
      (let ((root (session-root *session*)))
        (when (and root (member presence (page-presence-state root)))
          (setf viewers (append viewers (list (list :session *session* :name (presence-name)
                                                    :activity (nth-value 1 (page-presence-state root)))))))))
    (mapcar (lambda (v) (list :name (getf v :name) :activity (getf v :activity)
                              :you (eq (getf v :session) *session*)))
            viewers)))

;;; Showing who's here

(defclass presence-list (component updatable)
  ((presence :initarg :presence :reader presence-list-designator
             :documentation "A PRESENCE, or a function of no arguments returning one."))
  (:documentation "Who has a page in :PRESENCE open: how many, then each
person by name with what they're doing, the current one as \"You\", and the
guests counted (those doing something are listed).  :PRESENCE is a presence,
or a function returning one, called each time, for a list that follows what
the page shows.  Showing it puts the page in the presence, and it is
re-rendered by server push as people come and go."))

(defun presence-list-presence (list)
  "The presence LIST shows now."
  (let ((designator (presence-list-designator list)))
    (if (functionp designator) (funcall designator) designator)))

(defmethod presences ((self presence-list)) (list (presence-list-presence self)))
(defmethod subscriptions ((self presence-list)) (list (presence-list-presence self)))

(defmethod render ((self presence-list))
  (let* ((viewers (presence-viewers (presence-list-presence self)))
         (guests (count-if (lambda (v) (not (or (getf v :name) (getf v :you) (getf v :activity)))) viewers)))
    (h:div (:class "lt-presence")
      (h:p (:class "lt-presence-count")
        (h:text (translate-plural (length viewers) "~D person here" "~D people here")))
      (h:ul ()
        (dolist (viewer (stable-sort (copy-list viewers) (lambda (a b) (and (getf a :you) (not (getf b :you))))))
          (when (or (getf viewer :name) (getf viewer :you) (getf viewer :activity))
            (h:li (:class (when (getf viewer :you) "lt-presence-you"))
              (h:text (cond ((getf viewer :you) (translate "You"))
                          ((getf viewer :name))
                          (t (translate "A guest"))))
              (when (getf viewer :activity)
                (h:text " ")
                (h:span (:class "lt-presence-activity") (h:text (translate-label (getf viewer :activity))))))))
        (when (plusp guests)
          (h:li (:class "lt-presence-guests")
            (h:text (translate-plural guests "~D guest" "~D guests"))))))))
