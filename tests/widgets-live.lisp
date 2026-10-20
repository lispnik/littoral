;;;; widgets-live.lisp — times ago, and comment threads that update for everyone

(in-package #:littoral/tests)

(def-suite widgets-live :in littoral)
(in-suite widgets-live)

;;; Times ago

(test times-ago-in-words
  (let ((now (encode-universal-time 0 30 9 19 10 2026)))
    (is (equal "just now" (time-ago-text (- now 59) now)))
    (is (equal "just now" (time-ago-text (+ now 5) now)) "A clock a little ahead isn't the future")
    (is (equal "1 minute ago" (time-ago-text (- now 60) now)))
    (is (equal "2 minutes ago" (time-ago-text (- now 150) now)))
    (is (equal "3 hours ago" (time-ago-text (- now (* 3 3600) 5) now)))
    (is (equal "1 day ago" (time-ago-text (- now 86400) now)))
    (is (equal "6 days ago" (time-ago-text (- now (* 6 86400)) now)))
    (is (equal "October 9, 2026" (time-ago-text (- now (* 10 86400)) now)))
    (let ((littoral::*language* "fr"))
      (is (equal "il y a 2 jours" (time-ago-text (- now (* 2 86400)) now))))))

(test time-ago-elements
  (let* ((time (encode-universal-time 0 30 9 19 10 2026 0))
         (html (with-canvas-to-string () (time-ago time :class "when"))))
    (is (search "<time datetime=\"2026-10-19T09:30:00Z\" class=\"lt-relative-time when\"" html))
    (is (search "data-lt-relative data-lt-now=\"just now\"" html))
    (multiple-value-bind (s m h day month year) (decode-universal-time time)
      (declare (ignore s))
      (is (search (format nil "title=\"~A, ~2,'0D:~2,'0D\"" (localized-date year month day) h m) html))
      (is (search (format nil "data-lt-date=\"~A\"" (localized-date year month day)) html)))
    (is (cl-ppcre:scan ">[^<]+</time>$" html))))

;;; Stores

(test comments-in-memory
  (let ((store (make-instance 'memory-comment-store)))
    (is (null (thread-comments "a" :store store)))
    (let ((one (add-thread-comment "a" "Ada" "First" :store store :origin "s1"))
          (two (add-thread-comment "a" "Grace" "Second" :store store)))
      (add-thread-comment "b" "Alan" "Elsewhere" :store store)
      (is (equal '("First" "Second") (mapcar #'thread-comment-body (thread-comments "a" :store store))))
      (is (equal "Ada" (thread-comment-author one)))
      (is (equal "a" (thread-comment-thread one)))
      (is (equal "s1" (thread-comment-origin one)))
      (is (< (thread-comment-id one) (thread-comment-id two)))
      (is (<= (abs (- (get-universal-time) (thread-comment-time two))) 2))
      (delete-thread-comment "a" (thread-comment-id one) :store store)
      (is (equal '("Second") (mapcar #'thread-comment-body (thread-comments "a" :store store))))
      (is (= 1 (length (thread-comments "b" :store store)))))))

;;; On the wiki: comments under each page

(defun composer-field (b suffix)
  "The id of the comment composer's field ending SUFFIX (\"text\", \"name\")."
  (cl-ppcre:register-groups-bind (id) ((format nil "id=\"([^\"]+-~A)\"" suffix) (browser-html b)) id))

(defun post-wiki-comment (b text)
  "Write TEXT in the comment box and post it, without JavaScript."
  (fill-in b (composer-field b "text") text)
  (press b "Post"))

(test wiki-pages-have-comments
  (littoral-examples:reset-wiki)
  (with-fresh-applications (("/wiki" 'littoral-examples:wiki :mode :deployment))
    (let ((ada (make-instance 'browser)) (bob (make-instance 'browser)))
      (visit ada "/wiki")
      (is (has-text-p ada "0 comments"))
      (is (has-text-p ada "No comments yet."))
      (is (search "<section class=\"lt-comments\" aria-label=\"Comments\"><h2 class=\"lt-comments-heading\">Comments</h2>"
                  (browser-html ada)))
      ;; A name to post under, which is her name in presence lists too.
      (fill-in ada (composer-field ada "name") "Ada")
      (post-wiki-comment ada (format nil "Looks *good*.~%~%Second paragraph."))
      (is (has-text-p ada "1 comment"))
      (is (search "<strong class=\"lt-comment-author\">Ada</strong>" (browser-html ada)))
      (is (search "<p>Looks <em>good</em>.</p>" (browser-html ada)) "Markdown")
      (is (search "class=\"lt-relative-time\"" (browser-html ada)))
      (is (equal "" (cl-ppcre:register-groups-bind (v) ("<textarea[^>]*-text\"[^>]*>([^<]*)</textarea>" (browser-html ada)) v))
          "The box is emptied")
      (is (search "value=\"Ada\"" (browser-html ada)))
      ;; Another reader sees it.
      (visit bob "/wiki")
      (is (has-text-p bob "Looks good."))
      ;; Blank comments are ignored; long ones refused.
      (post-wiki-comment bob "   ")
      (is (has-text-p bob "1 comment"))
      (post-wiki-comment bob (make-string 2001 :initial-element #\x))
      (is (has-text-p bob "A comment can be at most 2000 characters."))
      (is (search "aria-invalid=\"true\"" (browser-html bob)))
      (post-wiki-comment bob "Agreed.")
      (is (search "<strong class=\"lt-comment-author\">A guest</strong>" (browser-html bob)))
      (is (has-text-p bob "2 comments"))
      ;; Each page has its own thread.
      (click bob "Littoral")
      (is (has-text-p bob "No comments yet."))
      ;; RESET-WIKI forgets them.
      (littoral-examples:reset-wiki)
      (visit ada "/wiki")
      (is (has-text-p ada "No comments yet.")))))

(test comments-and-writers-arrive-by-push
  (littoral-examples:reset-wiki)
  (with-fresh-applications (("/wiki" 'littoral-examples:wiki :mode :deployment))
    (let ((reader (make-instance 'browser)) (writer (make-instance 'browser))
          (sink (make-instance 'sink)) (writer-sink (make-instance 'sink)))
      (visit reader "/wiki")
      (visit writer "/wiki")
      (fill-in writer (composer-field writer "name") "Grace")
      (press writer "Post")                ; nothing to post: the name is kept
      (is (search "data-lt-events=" (browser-html reader)))
      (open-stream reader sink)
      ;; Presence counts the pages whose streams are open.
      (open-stream writer writer-sink)
      ;; Typing, as littoral.js posts it: the reader sees who's writing.
      (let ((spec (cl-ppcre:register-groups-bind (spec) ("<textarea[^>]*data-lt-on-input=\"([^\"]*)\"" (browser-html writer))
                    (let* ((spec (unescape spec)) (semi (position #\; spec)))
                      (cons (subseq spec 0 semi) (subseq spec (1+ semi)))))))
        (ajax-request writer (car spec) (cdr spec)
                      :fields (list (cons (element-name writer (composer-field writer "text")) "Half a thou"))))
      (is (wait-for (lambda () (search "Grace is writing a comment…" (sink-text sink)))))
      ;; Posting, as littoral.js submits the form: the comment, and its announcement.
      (visit writer (browser-url writer))
      (let ((spec (first (ajax-specs writer "on-submit"))))
        (ajax-request writer (car spec) (cdr spec)
                      :fields (list (cons (element-name writer (composer-field writer "text")) "Half a thought, finished"))))
      (is (wait-for (lambda () (search "Half a thought, finished" (sink-text sink)))))
      (is (wait-for (lambda () (search "Grace commented: Half a thought, finished" (sink-text sink)))))
      ;; Not writing any more.
      (visit reader (browser-url reader))
      (is (not (has-text-p reader "is writing")))
      ;; Their own page doesn't announce their own comment.
      (visit writer (browser-url writer))
      (is (not (search "Grace commented" (browser-html writer))))
      (close-event-streams))))

;;; Deleting

(defvar *test-comments* nil)

(defclass deletable-comments (component)
  ((thread :reader page-thread
           :initform (make-instance 'live-comment-thread :thread "deletable" :store (lambda () *test-comments*)
                                                    :author (constantly "Tester") :heading "Notes" :heading-level 3
                                                    :can-delete (lambda (c) (equal (thread-comment-author c) "Tester")))))
  (:documentation "A comment thread whose own comments can be deleted."))

(defmethod children ((self deletable-comments)) (list (page-thread self)))
(defmethod render ((self deletable-comments)) (render-component (page-thread self)))

(test deleting-comments
  (let ((*test-comments* (make-instance 'memory-comment-store)))
    (add-thread-comment "deletable" "Someone else" "Not yours" :store *test-comments*)
    (with-fresh-applications (("/notes" 'deletable-comments :mode :deployment))
      (let ((b (make-instance 'browser)))
        (visit b "/notes")
        (is (search "<h3 class=\"lt-comments-heading\">Notes</h3>" (browser-html b)))
        (is (has-text-p b "Posting as Tester"))
        (post-wiki-comment b "Mine")
        (is (= 1 (count-matches "lt-comment-delete" (browser-html b))) "Only your own")
        (is (search "aria-label=\"Delete the comment by Tester\"" (browser-html b)))
        (is (search "data-lt-on-click-confirm=\"Delete this comment?\"" (browser-html b)))
        (click b "Delete")
        (is (not (has-text-p b "Mine")))
        (is (has-text-p b "Not yours"))))))
