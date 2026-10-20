;;;; comments.lisp — comment threads kept in the database (littoral/comments)

(in-package #:littoral/tests)

(def-suite comments :in littoral)
(in-suite comments)

(defmacro with-comment-table (() &body body)
  "BODY with a fresh comments table in the test database."
  `(progn
     (connect-test-database)
     (littoral.comments:drop-comment-tables)
     (littoral.comments:create-comment-tables)
     (unwind-protect (progn ,@body)
       (littoral.comments:drop-comment-tables))))

(test comments-in-the-database
  (with-comment-table ()
    (let ((store (make-instance 'littoral.comments:database-comment-store)))
      (let ((one (add-thread-comment "invoice:42" "Ada" "Sent." :store store :origin "s1"))
            (alan (progn (add-thread-comment "invoice:42" "Grace" "Paid." :store store)
                         (add-thread-comment "invoice:43" "Alan" "Elsewhere." :store store))))
        (let ((comments (thread-comments "invoice:42" :store store)))
          (is (equal '("Sent." "Paid.") (mapcar #'thread-comment-body comments)))
          (is (equal '("Ada" "Grace") (mapcar #'thread-comment-author comments)))
          (is (equal "s1" (thread-comment-origin (first comments))))
          (is (eql (thread-comment-id one) (thread-comment-id (first comments))))
          (is (<= (abs (- (get-universal-time) (thread-comment-time (first comments)))) 2)))
        (delete-thread-comment "invoice:42" (thread-comment-id one) :store store)
        (is (equal '("Paid.") (mapcar #'thread-comment-body (thread-comments "invoice:42" :store store))))
        ;; Only within its thread.
        (delete-thread-comment "invoice:42" (thread-comment-id alan) :store store)
        (is (= 1 (length (thread-comments "invoice:43" :store store)))))
      ;; Pages hear of a change once it commits, and not when it's rolled back.
      (let ((heard '()))
        (littoral.db:with-transaction ()
          (call-after-store-change store (lambda () (push :committed heard)))
          (is (null heard)))
        (is (equal '(:committed) heard))
        (ignore-errors
         (littoral.db:with-transaction ()
           (add-thread-comment "invoice:42" "Mallory" "Gone." :store store)
           (call-after-store-change store (lambda () (push :rolled-back heard)))
           (error "No.")))
        (is (equal '(:committed) heard))
        (is (notany (lambda (c) (equal (thread-comment-author c) "Mallory"))
                    (thread-comments "invoice:42" :store store)))))))

(defclass db-comments-page (component)
  ((thread :reader page-thread
           :initform (make-instance 'live-comment-thread
                                    :thread "page" :store (make-instance 'littoral.comments:database-comment-store)
                                    :author (constantly "Tester"))))
  (:documentation "A comment thread kept in the database."))

(defmethod children ((self db-comments-page)) (list (page-thread self)))
(defmethod render ((self db-comments-page)) (render-component (page-thread self)))

(test a-thread-kept-in-the-database
  (with-comment-table ()
    (with-fresh-applications (("/c" 'db-comments-page :mode :deployment))
      (let ((b (make-instance 'browser)))
        (visit b "/c")
        (post-wiki-comment b "Kept.")
        (is (has-text-p b "1 comment"))
        (is (equal '("Kept.") (mapcar #'thread-comment-body
                                      (thread-comments "page" :store (make-instance 'littoral.comments:database-comment-store)))))))))
