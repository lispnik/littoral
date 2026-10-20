;;;; push.lisp — server-sent events

(in-package #:littoral/tests)

(def-suite push :in littoral)
(in-suite push)

(test chat-push
  (littoral-examples:clear-room)
  (with-fresh-applications (("/chat" 'littoral-examples:chat :mode :deployment))
    (let ((alice (make-instance 'browser)) (bob (make-instance 'browser)) (sink (make-instance 'sink)))
      (join-chat alice "alice")
      (join-chat bob "bob")
      (is (search "data-lt-events=" (browser-html bob)))
      (let ((thread (open-stream bob sink)))
        (is (wait-for (lambda () (search "retry:" (sink-text sink)))))
        (let ((spec (first (ajax-specs alice "on-submit"))))
          (ajax-request alice (first spec) (rest spec)
                        :fields (list (cons (element-name alice "draft") "pushed hello"))))
        (is (wait-for (lambda () (search "pushed hello" (sink-text sink)))))
        (is (search "event: update" (sink-text sink)))
        (close-event-streams)
        (is (wait-for (lambda () (not (sb-thread:thread-alive-p thread)))))))))

(test pages-without-subscribers-do-not-listen
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (is (not (search "data-lt-events" (browser-html b)))))))

(test stale-page-stream-is-refused
  (with-fresh-applications (("/chat" 'littoral-examples:chat :mode :deployment))
    (let ((b (make-instance 'browser)))
      (join-chat b "carol")
      (let ((url (cl-ppcre:register-groups-bind (u) ("data-lt-events=\"([^\"]*)\"" (browser-html b)) (unescape u))))
        (is (= 204 (first (funcall (browser-app b)
                                   (make-env :get (cl-ppcre:regex-replace "_k=[^&]*" url "_k=gone")
                                             :cookies (browser-cookies b))))))))))

(test notify-from-a-background-thread
  ;; The job runs in its own thread, which does not see LET bindings, so
  ;; the step time is set globally for the test's duration.
  (let ((saved littoral-examples::*job-step-seconds*))
    (setf littoral-examples::*job-step-seconds* 0.01)
    (unwind-protect
         (with-fresh-applications (("/progress" 'littoral-examples:progress-demo :mode :deployment))
           (let* ((b (make-instance 'browser))
                  (sink (make-instance 'sink))
                  (thread (progn (visit b "/progress") (open-stream b sink)))
                  (spec (first (ajax-specs b "on-click"))))
             (is (wait-for (lambda () (search "retry:" (sink-text sink)))))
             (ajax-request b (first spec) (rest spec))
             (is (wait-for (lambda () (search "Done." (sink-text sink)))))
             (is (search "width: 50%" (sink-text sink)))
             (close-event-streams)
             (is (wait-for (lambda () (not (sb-thread:thread-alive-p thread)))))))
      (setf littoral-examples::*job-step-seconds* saved))))

;;; Presence: who has a page open, and what they're doing

(defun presence-sessions-gone (presence)
  "True once no open stream is in PRESENCE (outside any request)."
  (let ((*session* nil)) (null (presence-viewers presence))))

(test chat-room-presence
  (littoral-examples:clear-room)
  (with-fresh-applications (("/chat" 'littoral-examples:chat :mode :deployment))
    (let ((alice (make-instance 'browser)) (bob (make-instance 'browser))
          (alice-sink (make-instance 'sink)) (bob-sink (make-instance 'sink))
          (room (find-presence "chat room")))
      (join-chat alice "alice")
      ;; Alice's own page counts her before its stream opens.
      (is (search "1 person here You" (body-text alice)))
      (join-chat bob "bob")
      (open-stream alice alice-sink)
      (open-stream bob bob-sink)
      ;; Bob arriving re-renders Alice's list, by push, with his name.
      (is (wait-for (lambda () (search "bob" (sink-text alice-sink)))))
      (is (search "2 people here" (sink-text alice-sink)))
      (visit alice (browser-url alice))
      (is (search "2 people here You bob" (body-text alice)))
      (close-event-streams)
      (is (wait-for (lambda () (presence-sessions-gone room)))))))

(test wiki-editing-presence
  (with-fresh-applications (("/wiki" 'littoral-examples:wiki :mode :deployment))
    (let ((reader (make-instance 'browser)) (editor (make-instance 'browser))
          (reader-sink (make-instance 'sink)) (editor-sink (make-instance 'sink)))
      (visit reader "/wiki")
      (visit editor "/wiki")
      (open-stream reader reader-sink)
      ;; The other one edits the page: still on it, and editing.
      (click editor "Edit")
      (is (has-text-p editor "Editing FrontPage"))
      (open-stream editor editor-sink)
      (is (wait-for (lambda () (search "editing" (sink-text reader-sink)))))
      (visit reader (browser-url reader))
      (is (search "2 people here You A guest editing" (body-text reader)))
      (close-event-streams)
      (is (wait-for (lambda () (presence-sessions-gone (find-presence "wiki:FrontPage"))))))))

(defvar *toggle-channel* (make-channel "presence toggle test"))
(defvar *toggle-presence* (find-presence "presence toggle test"))

(defclass presence-toggle (component updatable)
  ((shown :initform nil :accessor toggle-shown)
   (list :initform (make-instance 'presence-list :presence *toggle-presence*) :reader toggle-list))
  (:documentation "Shows a presence list or not, switched by AJAX; always listens."))

(defmethod subscriptions ((self presence-toggle)) (list *toggle-channel*))
(defmethod children ((self presence-toggle)) (when (toggle-shown self) (list (toggle-list self))))
(defmethod render ((self presence-toggle))
  (h:button (:on-click (ajax :callback (lambda () (setf (toggle-shown self) (not (toggle-shown self)))) :update self))
    "Toggle")
  (when (toggle-shown self) (render-component (toggle-list self))))

(test presence-follows-ajax-changes
  (with-fresh-applications (("/toggle" 'presence-toggle :mode :deployment))
    (let ((b (make-instance 'browser)) (sink (make-instance 'sink)))
      (visit b "/toggle")
      (open-stream b sink)
      (is (presence-sessions-gone *toggle-presence*))
      (let ((spec (first (ajax-specs b "on-click"))))
        (is (search "1 person here" (ajax-request b (first spec) (rest spec))))
        (is (not (presence-sessions-gone *toggle-presence*)) "Shown by AJAX: the page is in it")
        (ajax-request b (first spec) (rest spec))
        (is (presence-sessions-gone *toggle-presence*) "Hidden again: it isn't"))
      (close-event-streams))))

(test presence-names-come-from-sign-ins
  (is (functionp *presence-name-function*) "littoral/auth names signed-in users")
  (let ((*session* nil) (*presence-name-function* (lambda () "never asked")))
    (is (null (presence-name (make-instance 'littoral::session))) "Not in that session's request")))
