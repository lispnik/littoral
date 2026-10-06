;;;; session.lisp — one user's component tree and the pages it has shown

(in-package #:littoral)

(defclass continuation ()
  ((key :initarg :key :reader continuation-key)
   (serial :initarg :serial :reader continuation-serial
           :documentation "Increasing within a session; END-ISOLATION compares them.")
   (snapshot :initarg :snapshot :accessor continuation-snapshot)
   (callbacks :initform (make-instance 'callback-registry) :reader continuation-callbacks))
  (:documentation "A page the user may act on: the state it was rendered
from and the callbacks its links and fields name."))

(defvar *instance-id* nil
  "A short name for this process, put at the front of every session key
(\"a1.xxxx\") so a load balancer can send each session back to the process
that holds it.  NIL for none.")

(defun new-session-key ()
  "A fresh session key, prefixed with *INSTANCE-ID* when there is one."
  (if *instance-id*
      (format nil "~A.~A" *instance-id* (random-key 20))
      (random-key 20)))

(defclass session ()
  ((key :initform (new-session-key) :reader session-key)
   (application :initarg :application :reader session-application)
   (root :initarg :root :accessor session-root)
   (lock :initform (sb-thread:make-mutex :name "littoral session") :reader session-lock)
   (continuations :initform (make-hash-table :test 'equal) :reader session-continuations)
   (continuation-order :initform '() :accessor session-continuation-order
                       :documentation "Keys, newest first.")
   (continuation-serial :initform 0 :accessor session-continuation-serial)
   (browser-key :initform (random-key 20) :accessor session-browser-key
                :documentation "The browser's identity, kept in a cookie; a URL session key
only works with it.  Every session one browser starts shares it.")
   (browser-bound-p :initform nil :accessor session-browser-bound-p
                    :documentation "True once a request has come back with the cookie.")
   (created :initform (now-seconds) :reader session-created)
   (last-access :initform (now-seconds) :accessor session-last-access)
   (halos-p :initform nil :accessor session-halos-p)
   (source-views :initform '() :accessor session-source-views
                 :documentation "Alist of component id → halo view (:HTML or :CODE).")
   (profiling-p :initform nil :accessor session-profiling-p)
   (last-action :initform nil :accessor session-last-action
                :documentation "Plist of the last action's :ACTIONS and :SNAPSHOT seconds and :OBJECTS.")
   (properties :initform (make-hash-table :test 'equal) :reader session-properties))
  (:documentation "One user's component tree, the pages it has shown, and its lock."))

(defun session-property (key &optional (session *session*))
  "The value stored under KEY in SESSION, for application use."
  (gethash key (session-properties session)))

(defun (setf session-property) (value key &optional (session *session*))
  (setf (gethash key (session-properties session)) value))

(defun session-expired-p (session &optional (now (now-seconds)))
  "True when SESSION has been idle longer than its application allows."
  (> (- now (session-last-access session))
     (application-session-timeout (session-application session))))

(defun new-continuation (session)
  "Snapshot SESSION's tree into a new continuation, forgetting the oldest
when there are more than the application allows."
  (let* ((key (random-key 12))
         (continuation (make-instance 'continuation
                                      :key key
                                      :serial (incf (session-continuation-serial session))
                                      :snapshot (take-snapshot (session-root session))))
         (limit (application-max-continuations (session-application session))))
    (setf (gethash key (session-continuations session)) continuation)
    (push key (session-continuation-order session))
    (let ((excess (nthcdr limit (session-continuation-order session))))
      (when excess
        (dolist (old excess)
          (remhash old (session-continuations session)))
        (setf (session-continuation-order session)
              (ldiff (session-continuation-order session) excess))))
    continuation))

;;; Isolation: Seaside's isolate:

(defun begin-isolation (&optional (session *session*))
  "Start a stretch of pages that END-ISOLATION will make unreachable.
Returns a token for END-ISOLATION; it is a plain value, so a flow can hold
it across CALLs."
  (session-continuation-serial session))

(defun end-isolation (token &optional (session *session*))
  "Forget every page made since BEGIN-ISOLATION returned TOKEN, so the back
button cannot return into them (to place an order twice, say).  Going back
to one of them shows the session as it is now."
  (let ((doomed (loop for key in (session-continuation-order session)
                      for continuation = (gethash key (session-continuations session))
                      when (and continuation (> (continuation-serial continuation) token))
                        collect key)))
    (dolist (key doomed)
      (remhash key (session-continuations session)))
    (setf (session-continuation-order session)
          (remove-if (lambda (key) (member key doomed :test #'string=))
                     (session-continuation-order session)))
    (length doomed)))

(defun find-continuation (session key)
  "SESSION's page with KEY, or NIL."
  (and key (gethash key (session-continuations session))))

(defun session-snapshot-sizes (session)
  "Entries in the newest page's snapshot, and in all of SESSION's pages."
  (let ((newest (find-continuation session (first (session-continuation-order session))))
        (held 0))
    (loop for continuation being the hash-values of (session-continuations session)
          do (incf held (length (snapshot-entries (continuation-snapshot continuation)))))
    (values (if newest (length (snapshot-entries (continuation-snapshot newest))) 0)
            held)))

(defun session-continuation-count (session)
  "How many pages SESSION keeps."
  (hash-table-count (session-continuations session)))
