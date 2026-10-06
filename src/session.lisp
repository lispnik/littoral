;;;; session.lisp — one user's component tree and the pages it has shown

(in-package #:littoral)

(defclass continuation ()
  ((key :initarg :key :reader continuation-key)
   (snapshot :initarg :snapshot :accessor continuation-snapshot)
   (callbacks :initform (make-instance 'callback-registry) :reader continuation-callbacks))
  (:documentation "A page the user may act on: the state it was rendered
from and the callbacks its links and fields name."))

(defclass session ()
  ((key :initform (random-key 20) :reader session-key)
   (application :initarg :application :reader session-application)
   (root :initarg :root :accessor session-root)
   (lock :initform (sb-thread:make-mutex :name "littoral session") :reader session-lock)
   (continuations :initform (make-hash-table :test 'equal) :reader session-continuations)
   (continuation-order :initform '() :accessor session-continuation-order
                       :documentation "Keys, newest first.")
   (created :initform (now-seconds) :reader session-created)
   (last-access :initform (now-seconds) :accessor session-last-access)
   (halos-p :initform nil :accessor session-halos-p)
   (source-views :initform '() :accessor session-source-views
                 :documentation "Ids of components whose halo shows source.")
   (properties :initform (make-hash-table :test 'equal) :reader session-properties)))

(defun session-property (key &optional (session *session*))
  (gethash key (session-properties session)))

(defun (setf session-property) (value key &optional (session *session*))
  (setf (gethash key (session-properties session)) value))

(defun session-expired-p (session &optional (now (now-seconds)))
  (> (- now (session-last-access session))
     (application-session-timeout (session-application session))))

(defun new-continuation (session)
  "Snapshot SESSION's tree into a new continuation, forgetting the oldest
when there are more than the application allows."
  (let* ((key (random-key 12))
         (continuation (make-instance 'continuation
                                      :key key
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

(defun find-continuation (session key)
  (and key (gethash key (session-continuations session))))

(defun session-continuation-count (session)
  (hash-table-count (session-continuations session)))
