;;;; robustness.lisp — deep backtracking, concurrency, instance ids

(in-package #:littoral/tests)

(def-suite robustness :in littoral)
(in-suite robustness)

(defclass notebook (component)
  ((notes :initform (list "first") :accessor notes)
   (tags :initform (make-hash-table :test 'equal) :accessor tags)
   (deep-p :initarg :deep :initform nil :reader deep-p))
  (:documentation "Notes and tags, snapshotted shallowly or deeply."))

(defmethod states ((self notebook))
  (list (if (deep-p self) (deep self) self)))

(test shallow-snapshots-share-structure
  (let* ((nb (make-instance 'notebook))
         (snap (take-snapshot nb)))
    ;; Changing the list in place reaches the snapshot.
    (nconc (notes nb) (list "second"))
    (restore-snapshot snap)
    (is (equal '("first" "second") (notes nb)))))

(test deep-snapshots-copy
  (let* ((nb (make-instance 'notebook :deep t))
         (snap (progn (setf (gethash "lisp" (tags nb)) (list 1)) (take-snapshot nb))))
    (nconc (notes nb) (list "second"))
    (push 2 (gethash "lisp" (tags nb)))
    (setf (gethash "new" (tags nb)) t)
    (restore-snapshot snap)
    (is (equal '("first") (notes nb)))
    (is (equal '(1) (gethash "lisp" (tags nb))))
    (is (null (gethash "new" (tags nb))))
    ;; Restoring twice works: the restore copied, it did not hand over the snapshot.
    (nconc (notes nb) (list "again"))
    (restore-snapshot snap)
    (is (equal '("first") (notes nb)))))

(test deep-copy-keeps-sharing-and-cycles
  (let* ((shared (list 1 2))
         (value (list shared shared))
         (copy (deep-copy value)))
    (is (not (eq (first copy) shared)))
    (is (eq (first copy) (second copy))))
  (let ((cycle (list 1 2)))
    (setf (cddr cycle) cycle)
    (let ((copy (deep-copy cycle)))
      (is (eq copy (cddr copy)))))
  (let ((object (make-instance 'component)))
    (is (eq object (first (deep-copy (list object)))))))

(defun run-threads (n function)
  "Run FUNCTION (of an index) in N threads; return the errors raised."
  (let* ((errors '())
         (lock (sb-thread:make-mutex))
         ;; Threads do not inherit dynamic bindings, such as the registry
         ;; WITH-FRESH-APPLICATIONS makes; carry it over.
         (applications littoral::*applications*)
         (threads (loop for i below n
                        collect (let ((i i))
                                  (sb-thread:make-thread
                                   (lambda ()
                                     (let ((littoral::*applications* applications))
                                      (handler-case (funcall function i)
                                       (error (e)
                                         (sb-thread:with-mutex (lock) (push e errors)))))))))))
    (mapc #'sb-thread:join-thread threads)
    errors))

(test many-sessions-at-once
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let* ((counts (make-array 16 :initial-element nil))
           (errors (run-threads 16 (lambda (i)
                                     (let ((b (make-instance 'browser)))
                                       (visit b "/counter")
                                       (dotimes (k 25) (click b "++"))
                                       (setf (aref counts i) (count-shown b)))))))
      (is (null errors) "~A" errors)
      (is (every (lambda (n) (eql n 25)) counts))
      (is (= 16 (length (littoral::list-sessions (find-application "/counter"))))))))

(test one-page-hammered
  ;; Many requests acting on the same page of one session: each restores
  ;; the page and acts on it, so the result is the page's count plus one,
  ;; and nothing breaks.
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (click b "++")
      (let* ((href (find-link b "++"))
             (errors (run-threads 16 (lambda (i)
                                       (declare (ignore i))
                                       (let ((c (make-instance 'browser :app (browser-app b))))
                                         (dotimes (k 10) (visit c href))
                                         (assert (= 2 (count-shown c))))))))
        (is (null errors) "~A" errors)))))

(test concurrent-ajax-and-actions
  (with-fresh-applications (("/ajax" 'littoral-examples:ajax-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/ajax")
      (let* ((plus (first (ajax-specs b "on-click")))
             (errors (run-threads 8 (lambda (i)
                                      (declare (ignore i))
                                      (dotimes (k 20)
                                        (ajax-request b (first plus) (rest plus)))))))
        (is (null errors) "~A" errors)
        ;; AJAX acts on the live state, serialised by the session lock.
        (visit b (browser-url b))
        (is (search ">160</span>" (browser-html b)))))))

(test instance-id-prefixes-session-keys
  (let ((*instance-id* "a1"))
    (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
      (let ((b (make-instance 'browser)))
        (visit b "/counter")
        (is (search "_s=a1." (browser-url b)))
        (click b "++")
        (is (= 1 (count-shown b)))))))
