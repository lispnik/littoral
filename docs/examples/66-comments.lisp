;;;; Comment threads kept in the database (littoral/comments).

;;;; Example: littoral.comments:database-comment-store littoral.comments:create-comment-tables littoral.comments:drop-comment-tables
;;; Comments kept in the comments table, which `create-comment-tables` makes.  Give a thread `:store` this, or make it `*comment-store*`.  Pages showing a thread hear of a change once its transaction commits.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.comments:create-comment-tables)
  (unwind-protect
       (let ((store (make-instance 'littoral.comments:database-comment-store)))
         (add-thread-comment "invoice:42" "Ada" "Sent today." :store store)
         (add-thread-comment "invoice:42" "Grace" "Paid." :store store)
         (mapcar (lambda (c) (format nil "~A: ~A" (thread-comment-author c) (thread-comment-body c)))
                 (thread-comments "invoice:42" :store store)))
    (littoral.comments:drop-comment-tables)))
;; ⇒ ("Ada: Sent today." "Grace: Paid.")
