;;;; The examples for times written as how long ago they were, and comment threads that update for everyone.

;;;; Example: littoral:time-ago-text
;;; How long ago a time was, in words, in the current language: under a minute is just now, then minutes, hours and days, and after a week the date.
(let ((now (encode-universal-time 0 0 12 19 10 2026)))
  (list (time-ago-text (- now 20) now)
        (time-ago-text (- now 600) now)
        (time-ago-text (- now (* 5 3600)) now)
        (time-ago-text (- now (* 3 86400)) now)
        (time-ago-text (- now (* 30 86400)) now)
        (let ((littoral::*language* "de")) (time-ago-text (- now 600) now))))
;; ⇒ ("just now" "10 minutes ago" "5 hours ago" "3 days ago" "September 19, 2026" "vor 10 Minuten")

;;;; Example: littoral:time-ago
;;; Writes a time element saying how long ago the time was, with the date and time as its title.  littoral.js keeps the words up to date while the page stays open, so "just now" becomes "5 minutes ago".
(let ((time (- (get-universal-time) 120)))
  (cl-ppcre:regex-replace-all " (datetime|title|data-lt-date)=\"[^\"]*\"" (h:with-canvas-to-string () (time-ago time)) ""))
;; ⇒ "<time class=\"lt-relative-time\" data-lt-relative data-lt-now=\"just now\">2 minutes ago</time>"

;;;; Example: littoral:live-comment-thread littoral:thread-comments littoral:thread-comment-author littoral:thread-comment-body
;;; The comments on something, with a box for adding one.  `:thread` names it.  A comment posted shows at once on every page showing the thread (by server push), and is announced to screen readers there; while someone has written a comment but not posted it, the others see that they're writing.  `:author` names who posts; by default it's their `presence-name`, or with `:ask-name t` a name they give.
(defclass order-page (component)
  ((comments :reader comments
             :initform (make-instance 'live-comment-thread :thread "order:7" :author (constantly "Ada")))))
(defmethod children ((self order-page)) (list (comments self)))
(defmethod render ((self order-page)) (render-component (comments self)))
(let ((*comment-store* (make-instance 'memory-comment-store)))
  (with-fresh-applications (("/order" 'order-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/order")
      (fill-in b (cl-ppcre:register-groups-bind (id) ("<textarea[^>]* id=\"([^\"]+)\"" (browser-html b)) id)
               "Shipped today.")
      (press b "Post")
      (list (body-text b)
            (mapcar (lambda (c) (list (thread-comment-author c) (thread-comment-body c)))
                    (thread-comments "order:7"))))))
;; ⇒ ("Comments 1 comment Ada just now Shipped today. Add a comment Post Posting as Ada" (("Ada" "Shipped today.")))

;;;; Example: littoral:add-thread-comment littoral:delete-thread-comment littoral:thread-comment-id littoral:thread-comment-time littoral:thread-comment-thread littoral:thread-comment-origin littoral:memory-comment-store
;;; Comments can be added and removed from code too, as from a job, and pages showing the thread hear of it.  A `memory-comment-store` keeps them in this process; `*comment-store*` is the one threads use unless given another.
(let ((store (make-instance 'memory-comment-store)))
  (let ((first (add-thread-comment "doc:1" "Ada" "One" :store store :origin "job")))
    (add-thread-comment "doc:1" "Grace" "Two" :store store)
    (delete-thread-comment "doc:1" (thread-comment-id first) :store store)
    (list (thread-comment-thread first) (thread-comment-origin first) (integerp (thread-comment-time first))
          (mapcar #'thread-comment-body (thread-comments "doc:1" :store store)))))
;; ⇒ ("doc:1" "job" T ("Two"))

;;;; Example: littoral:comment-thread-channel littoral:*comment-store*
;;; Each thread has a channel, published when its comments change; a component of your own can subscribe to it, to show a count, say.
(list (eq (comment-thread-channel "doc:1") (comment-thread-channel "doc:1"))
      (typep *comment-store* 'memory-comment-store))
;; ⇒ (T T)

;;;; Example: littoral:store-thread-comments littoral:store-add-comment littoral:store-delete-comment littoral:call-after-store-change littoral:thread-comment
;;; A store of your own implements these generics, returning `thread-comment` objects; `call-after-store-change` says when its change is final, such as after a database commit (littoral/comments has one for littoral.db).
(defclass list-store () ((comments :initform '() :accessor stored)))
(defmethod store-thread-comments ((store list-store) thread)
  (reverse (remove thread (stored store) :key #'thread-comment-thread :test-not #'equal)))
(defmethod store-add-comment ((store list-store) thread author body time origin)
  (let ((comment (make-instance 'thread-comment :id (length (stored store)) :thread thread :author author
                                                :body body :time time :origin origin)))
    (push comment (stored store))
    comment))
(defmethod store-delete-comment ((store list-store) thread id)
  (setf (stored store) (remove id (stored store) :key #'thread-comment-id)))
(let ((store (make-instance 'list-store)))
  (add-thread-comment "x" "Alan" "Hello" :store store)
  (mapcar #'thread-comment-body (thread-comments "x" :store store)))
;; ⇒ ("Hello")
