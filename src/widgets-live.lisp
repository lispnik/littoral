;;;; widgets-live.lisp — times that keep themselves up to date, and comment threads
;;;;
;;;;   (time-ago (thread-comment-time comment))        ; "3 minutes ago", kept so
;;;;   (make-instance 'live-comment-thread :thread "wiki:Home")
;;;;
;;;; A comment thread's comments appear on every page showing the thread as
;;;; they're posted (server push), and those writing one are shown as
;;;; writing it (presence).

(in-package #:littoral)

;;; Relative times

(defun time-ago-text (time &optional (now (get-universal-time)))
  "How long before NOW TIME was, both universal times, for people: \"just
now\", \"3 minutes ago\", \"2 hours ago\", \"4 days ago\", and after a week
the date."
  (let ((seconds (max 0 (- now time))))
    (cond ((< seconds 60) (translate "just now"))
          ((< seconds 3600) (translate-plural (floor seconds 60) "~D minute ago" "~D minutes ago"))
          ((< seconds 86400) (translate-plural (floor seconds 3600) "~D hour ago" "~D hours ago"))
          ((< seconds (* 7 86400)) (translate-plural (floor seconds 86400) "~D day ago" "~D days ago"))
          (t (multiple-value-bind (s m h day month year) (decode-universal-time time)
               (declare (ignore s m h))
               (localized-date year month day))))))

(defun utc-timestamp (time)
  "TIME, a universal time, as an ISO 8601 timestamp in UTC."
  (multiple-value-bind (s m h day month year) (decode-universal-time time 0)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ" year month day h m s)))

(defun time-ago (time &key class)
  "Write TIME, a universal time, as a time element saying how long ago it
was (see TIME-AGO-TEXT), with the date and time as its title.
littoral.js keeps the words up to date while the page is open, in the
page's language.  CLASS is added to its classes."
  (multiple-value-bind (s m h day month year) (decode-universal-time time)
    (declare (ignore s))
    (emit-tag "time" (list :datetime (utc-timestamp time) :class (list "lt-relative-time" class)
                           :title (format nil "~A, ~2,'0D:~2,'0D" (localized-date year month day) h m)
                           :data-lt-relative t :data-lt-now (translate "just now")
                           :data-lt-date (localized-date year month day))
              (lambda () (h:text (time-ago-text time))))))

;;; Comments and where they're kept

(defclass thread-comment ()
  ((id :initarg :id :reader thread-comment-id :documentation "Its store's id for it.")
   (thread :initarg :thread :reader thread-comment-thread :documentation "The thread it is in.")
   (author :initarg :author :reader thread-comment-author :documentation "Who wrote it, named for people.")
   (body :initarg :body :reader thread-comment-body :documentation "What it says.")
   (time :initarg :time :reader thread-comment-time :documentation "When it was posted, a universal time.")
   (origin :initarg :origin :initform nil :reader thread-comment-origin
           :documentation "The session key of whoever posted it, or NIL."))
  (:documentation "A comment in a thread."))

(defmethod print-object ((comment thread-comment) stream)
  (print-unreadable-object (comment stream :type t)
    (format stream "~A by ~A" (thread-comment-id comment) (thread-comment-author comment))))

(defgeneric store-thread-comments (store thread)
  (:documentation "The comments in THREAD (a string) that STORE keeps, oldest first."))

(defgeneric store-add-comment (store thread author body time origin)
  (:documentation "Keep a new comment in THREAD in STORE and return it as a THREAD-COMMENT."))

(defgeneric store-delete-comment (store thread id)
  (:documentation "Forget the comment in THREAD with ID, if STORE has it."))

(defgeneric call-after-store-change (store function)
  (:documentation "Call FUNCTION once STORE's change is final: at once, or for
a database, once its transaction commits.")
  (:method (store function)
    (declare (ignore store))
    (funcall function)))

(defclass memory-comment-store ()
  ((threads :initform (make-hash-table :test 'equal) :reader store-threads
            :documentation "Thread → its comments, newest first.")
   (next-id :initform 0 :accessor store-next-id)
   (lock :initform (sb-thread:make-mutex :name "littoral comments") :reader store-lock))
  (:documentation "Comments kept in this process, until it ends.  The
littoral/comments system keeps them in a database instead."))

(defmethod store-thread-comments ((store memory-comment-store) thread)
  (sb-thread:with-mutex ((store-lock store))
    (reverse (gethash thread (store-threads store)))))

(defmethod store-add-comment ((store memory-comment-store) thread author body time origin)
  (sb-thread:with-mutex ((store-lock store))
    (let ((comment (make-instance 'thread-comment :id (incf (store-next-id store)) :thread thread
                                                  :author author :body body :time time :origin origin)))
      (push comment (gethash thread (store-threads store)))
      comment)))

(defmethod store-delete-comment ((store memory-comment-store) thread id)
  (sb-thread:with-mutex ((store-lock store))
    (setf (gethash thread (store-threads store))
          (remove id (gethash thread (store-threads store)) :key #'thread-comment-id :test #'eql))))

(defvar *comment-store* (make-instance 'memory-comment-store)
  "Where comments are kept unless a thread names another store: a
MEMORY-COMMENT-STORE, or littoral/comments' DATABASE-COMMENT-STORE.")

(defvar *comment-channels* (make-hash-table :test 'equal :weakness :value :synchronized t)
  "Thread → channel, kept while something refers to it.")

(defun comment-thread-channel (thread)
  "The channel published when THREAD's comments change in this process."
  (or (gethash thread *comment-channels*)
      (sb-ext:with-locked-hash-table (*comment-channels*)
        (or (gethash thread *comment-channels*)
            (setf (gethash thread *comment-channels*) (make-channel (format nil "comments ~A" thread)))))))

(defun thread-comments (thread &key (store *comment-store*))
  "THREAD's comments, oldest first."
  (store-thread-comments store thread))

(defun comments-changed (store thread)
  "Tell the pages showing THREAD, once STORE's change is final."
  (call-after-store-change store (lambda () (publish (comment-thread-channel thread)))))

(defun add-thread-comment (thread author body &key (store *comment-store*) origin)
  "Add a comment saying BODY by AUTHOR (a name) to THREAD, in STORE, and
return it.  Every page showing the thread shows it at once.  ORIGIN is the
session key of whoever posted it, so their own pages don't announce it to
them; by default the current session's."
  (let ((comment (store-add-comment store thread author body (get-universal-time)
                                    (or origin (and *session* (session-key *session*))))))
    (comments-changed store thread)
    comment))

(defun delete-thread-comment (thread id &key (store *comment-store*))
  "Remove the comment with ID from THREAD, in STORE."
  (store-delete-comment store thread id)
  (comments-changed store thread)
  (values))

;;; The thread on a page

(defclass live-comment-thread (component)
  ((thread :initarg :thread :reader comment-thread-designator
           :documentation "The thread's key, a string such as \"wiki:Home\", or a function returning one.")
   (store :initarg :store :initform nil :reader comment-thread-store-designator
          :documentation "Where its comments are kept, or a function returning that; NIL for *COMMENT-STORE*.")
   (ask-name :initarg :ask-name :initform nil :reader comment-thread-ask-name-p
             :documentation "True to ask those posting for a name, which becomes their PRESENCE-NAME.")
   (author :initarg :author :initform nil :reader comment-thread-author-function
           :documentation "A function of no arguments naming who is posting, or NIL for PRESENCE-NAME.")
   (markdown :initarg :markdown :initform nil :reader comment-thread-markdown-p
             :documentation "True to write comments as Markdown.")
   (can-delete :initarg :can-delete :initform nil :reader comment-thread-can-delete
               :documentation "A function of a comment, true when the current person may delete it.")
   (max-length :initarg :max-length :initform 2000 :reader comment-thread-max-length)
   (heading :initarg :heading :initform "Comments" :reader comment-thread-heading
            :documentation "The heading over it, translated; NIL for none.")
   (heading-level :initarg :heading-level :initform 2 :reader comment-thread-heading-level
                  :documentation "The heading's level, 1 to 6.")
   (list :reader comment-thread-list)
   (writing :reader comment-thread-writing)
   (composer :reader comment-thread-composer)
   (announcer :reader comment-thread-announcer))
  (:documentation "The comments on something, such as a wiki page or an
order, and a box for adding one.  :THREAD names it with a string (or a
function returning one).  A comment posted appears at once on every page
showing the thread, and is announced to screen readers there; while someone
has written something not yet posted, the others see that they're writing.
Comments are kept in :STORE (*COMMENT-STORE*, in memory, unless given; see
littoral/comments for a database), or a function returning one.  They are
posted under the name :AUTHOR (a function) gives, by default PRESENCE-NAME,
or as a guest; :ASK-NAME T asks for a name, which becomes the poster's
PRESENCE-NAME.
:MARKDOWN T writes them as Markdown.  :CAN-DELETE, a function of a
comment, says who may delete which.  Posting goes over AJAX, or is an
ordinary form without JavaScript."))

(defclass comment-part (component updatable)
  ((thread :initarg :thread :reader part-thread))
  (:documentation "A part of a LIVE-COMMENT-THREAD drawn again on its own."))

(defclass comment-list (comment-part) ()
  (:documentation "A LIVE-COMMENT-THREAD's comments, drawn again as they change."))

(defclass comment-writing (comment-part) ()
  (:documentation "Who else is writing a comment on a LIVE-COMMENT-THREAD."))

(defclass comment-announcer (comment-part) ()
  (:documentation "The newest comment by someone else, for screen readers to announce."))

(defclass comment-composer (comment-part)
  ((draft :initform "" :accessor composer-text)
   (problem :initform nil :accessor composer-problem))
  (:documentation "A LIVE-COMMENT-THREAD's box for writing a comment."))

(defmethod initialize-instance :after ((self live-comment-thread) &key)
  (setf (slot-value self 'list) (make-instance 'comment-list :thread self)
        (slot-value self 'writing) (make-instance 'comment-writing :thread self)
        (slot-value self 'composer) (make-instance 'comment-composer :thread self)
        (slot-value self 'announcer) (make-instance 'comment-announcer :thread self)))

(defmethod children ((self live-comment-thread))
  (list (comment-thread-list self) (comment-thread-writing self)
        (comment-thread-composer self) (comment-thread-announcer self)))

(defmethod states ((self comment-composer)) (list self))

(defun comment-thread-key (thread)
  "The key of the thread THREAD, a LIVE-COMMENT-THREAD, shows now."
  (let ((designator (comment-thread-designator thread)))
    (if (functionp designator) (funcall designator) designator)))

(defun comment-thread-store (thread)
  "Where THREAD, a LIVE-COMMENT-THREAD, keeps its comments."
  (let ((store (comment-thread-store-designator thread)))
    (if (functionp store) (funcall store) (or store *comment-store*))))

(defun comment-thread-presence (thread)
  "The presence of the pages showing THREAD, a LIVE-COMMENT-THREAD."
  (find-presence (format nil "comments:~A" (comment-thread-key thread))))

(defun comment-thread-comments (thread)
  "The comments THREAD, a LIVE-COMMENT-THREAD, shows, oldest first."
  (thread-comments (comment-thread-key thread) :store (comment-thread-store thread)))

(defparameter *writing-activity* "writing a comment"
  "What a comment thread's presence says of those with a comment unposted.")

(defmethod presences ((self live-comment-thread)) (list (comment-thread-presence self)))

(defmethod presence-activity ((self comment-composer))
  (and (string/= (string-trim '(#\Space #\Tab #\Newline #\Return) (composer-text self)) "")
       *writing-activity*))

(defmethod subscriptions ((self comment-list))
  (list (comment-thread-channel (comment-thread-key (part-thread self)))))

(defmethod subscriptions ((self comment-announcer))
  (list (comment-thread-channel (comment-thread-key (part-thread self)))))

(defmethod subscriptions ((self comment-writing))
  (list (comment-thread-presence (part-thread self))))

(defmethod updatable-wrapper ((self comment-list)) (values "div" '(:class "lt-comment-list")))
(defmethod updatable-wrapper ((self comment-writing)) (values "p" '(:class "lt-comment-writing")))
(defmethod updatable-wrapper ((self comment-announcer))
  (values "p" '(:class "lt-visually-hidden" :role "status" :aria-live "polite")))

(defun comment-poster (thread)
  "The name THREAD's comments from the current person go under."
  (or (and (comment-thread-author-function thread) (funcall (comment-thread-author-function thread)))
      (presence-name)
      (translate "A guest")))

(defun send-comment (composer)
  "Post COMPOSER's draft, if it says anything and isn't too long, and clear it."
  (let* ((thread (part-thread composer))
         (body (string-trim '(#\Space #\Tab #\Newline #\Return) (composer-text composer))))
    (cond ((string= body "") (setf (composer-problem composer) nil))
          ((> (length body) (comment-thread-max-length thread))
           (setf (composer-problem composer)
                 (translate "A comment can be at most ~D characters." (comment-thread-max-length thread))))
          (t (add-thread-comment (comment-thread-key thread) (comment-poster thread) body
                           :store (comment-thread-store thread))
             (setf (composer-text composer) "" (composer-problem composer) nil)))))

(defun render-comment-body (thread comment)
  "Write COMMENT's body as THREAD writes them: Markdown, or paragraphs of text."
  (if (comment-thread-markdown-p thread)
      (h:raw (markdown-html (thread-comment-body comment)))
      (dolist (paragraph (cl-ppcre:split "\\n\\s*\\n" (thread-comment-body comment)))
        (h:p () (loop for (line . more) on (cl-ppcre:split "\\r?\\n" paragraph)
                    do (h:text line) (when more (h:br)))))))

(defmethod render ((self live-comment-thread))
  (h:section (:class "lt-comments" :aria-label (translate-label (or (comment-thread-heading self) "Comments")))
    (when (comment-thread-heading self)
      (emit-tag (format nil "h~D" (comment-thread-heading-level self)) '(:class "lt-comments-heading")
                (lambda () (h:text (translate-label (comment-thread-heading self))))))
    (render-component (comment-thread-list self))
    (render-component (comment-thread-writing self))
    (render-component (comment-thread-composer self))
    (render-component (comment-thread-announcer self))))

(defmethod render ((self comment-list))
  (let* ((thread (part-thread self))
         (comments (comment-thread-comments thread))
         (can-delete (comment-thread-can-delete thread)))
    (h:p (:class "lt-comment-count") (h:text (translate-plural (length comments) "~D comment" "~D comments")))
    (if (null comments)
        (h:p (:class "lt-comment-none") (translate "No comments yet."))
        (h:ol (:class "lt-comment-items")
          (dolist (comment comments)
            (let ((comment comment))
              (h:li (:class "lt-comment")
                (h:div (:class "lt-comment-head")
                  (h:strong (:class "lt-comment-author") (h:text (thread-comment-author comment)))
                  (h:text " ")
                  (time-ago (thread-comment-time comment))
                  (when (and can-delete (funcall can-delete comment))
                    (flet ((delete-it ()
                             (delete-thread-comment (comment-thread-key thread) (thread-comment-id comment)
                                             :store (comment-thread-store thread))))
                      (h:text " ")
                      (h:anchor (:class "lt-comment-delete"
                               :aria-label (translate "Delete the comment by ~A" (thread-comment-author comment))
                               :callback #'delete-it
                               :on-click (ajax :callback #'delete-it :update self
                                               :confirm (translate "Delete this comment?")))
                        (translate "Delete")))))
                (h:div (:class "lt-comment-body") (render-comment-body thread comment)))))))))

(defmethod render ((self comment-writing))
  (let* ((writers (remove-if-not (lambda (v) (and (equal (getf v :activity) *writing-activity*) (not (getf v :you))))
                                 (presence-viewers (comment-thread-presence (part-thread self)))))
         (count (length writers)))
    (cond ((= count 1)
           (h:text (translate "~A is writing a comment…" (or (getf (first writers) :name) (translate "Someone")))))
          ((> count 1)
           (h:text (translate-plural count "~D people are writing comments…" "~D people are writing comments…")))
          (t nil))))

(defmethod render ((self comment-announcer))
  ;; The newest comment by someone else: its arrival is announced, but not
  ;; what's there when the page loads.
  (let* ((key (and *session* (session-key *session*)))
         (newest (find-if-not (lambda (c) (equal (thread-comment-origin c) key))
                          (reverse (comment-thread-comments (part-thread self))))))
    (when newest
      (h:text (translate "~A commented: ~A" (thread-comment-author newest)
                       (let ((body (thread-comment-body newest)))
                         (if (> (length body) 140) (format nil "~A…" (subseq body 0 140)) body)))))))

(defmethod render ((self comment-composer))
  (let* ((thread (part-thread self))
         (id (format nil "~A-text" (component-id self)))
         (problem (composer-problem self))
         (targets (list self (comment-thread-list thread))))
    (flet ((send () (send-comment self)))
      (h:form (:class "lt-comment-composer" :on-submit (ajax :callback #'send :update targets))
        (h:label (:for id) (translate "Add a comment"))
        (h:text-area (:id id :value (composer-text self) :rows "3"
                    :aria-invalid (when problem "true")
                    :aria-describedby (when problem (format nil "~A-problem" id))
                    :callback (lambda (v) (setf (composer-text self) v))
                    ;; What's typed reaches the server, which says who's writing.
                    :on-input (ajax :update '())))
        (when problem
          (h:div (:id (format nil "~A-problem" id) :class "lt-validation-error") (h:text problem)))
        (when (and (comment-thread-ask-name-p thread) (null (comment-thread-author-function thread)))
          (let ((name-id (format nil "~A-name" (component-id self))))
            (h:div (:class "lt-comment-name")
              (h:label (:for name-id) (translate "Your name"))
              (h:text " ")
              (h:text-input (:id name-id :value (or (presence-name) "") :autocomplete "name"
                           :callback (lambda (v)
                                       (let ((name (string-trim " " v)))
                                         (setf (presence-name) (if (string= name "") nil name)))))))))
        (h:div (:class "lt-buttons")
          (h:submit-button (:callback #'send) (translate "Post"))
          (unless (comment-thread-ask-name-p thread)
            (h:span (:class "lt-help") (h:text (translate "Posting as ~A" (comment-poster thread))))))))))
