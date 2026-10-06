;;;; request-cycle.lisp — sessions, callbacks, redirects

(in-package #:littoral/tests)

(def-suite request-cycle :in littoral)
(in-suite request-cycle)

(defun count-shown (browser)
  (parse-integer (cl-ppcre:scan-to-strings "(?<=<h1>)-?\\d+(?=</h1>)" (browser-html browser))))

(test counter
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (is (= 200 (browser-status b)))
      (is (search "_s=" (browser-url b)))
      (is (= 0 (count-shown b)))
      (click b "++") (click b "++") (click b "++")
      (is (= 3 (count-shown b)))
      (click b "--")
      (is (= 2 (count-shown b))))))

(test reload-does-not-repeat-action
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (click b "++")
      (let ((url (browser-url b)))
        (visit b url)
        (visit b url)
        (is (= 1 (count-shown b)))))))

(test separate-sessions
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((a (make-instance 'browser)) (b (make-instance 'browser)))
      (visit a "/counter") (visit b "/counter")
      (click a "++") (click a "++")
      (click b "--")
      (is (= 2 (count-shown a)))
      (is (= -1 (count-shown b))))))

(test multi-counter
  (with-fresh-applications (("/multi" 'littoral-examples:multi-counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/multi")
      ;; Click the third counter's ++.
      (let ((links (let (r) (cl-ppcre:do-register-groups (href) ("<a href=\"([^\"]*)\">\\+\\+</a>" (browser-html b))
                              (push (unescape href) r))
                     (nreverse r))))
        (is (= 5 (length links)))
        (visit b (third links)))
      (is (equal '(0 0 1 0 0)
                 (mapcar #'parse-integer
                         (cl-ppcre:all-matches-as-strings "(?<=<h1>)-?\\d+(?=</h1>)" (browser-html b))))))))

(test expired-session-restarts
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment :session-timeout 1))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (click b "++")
      (let ((old-url (browser-url b)))
        (sleep 2.1)
        (visit b old-url)
        (is (= 0 (count-shown b)))
        (is (not (string= old-url (browser-url b))))))))

(test unknown-continuation-shows-current-state
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (click b "++")
      (visit b (cl-ppcre:regex-replace "_k=[^&]*" (browser-url b) "_k=nonsense"))
      (is (= 200 (browser-status b)))
      (is (= 1 (count-shown b))))))

(test forms-and-checkboxes
  (with-fresh-applications (("/todo" 'littoral-examples:todo-list :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/todo")
      (fill-in b "new-title" "Buy milk")
      (press b "Add")
      (fill-in b "new-title" "Write <tests>")
      (press b "Add")
      (is (has-text-p b "Buy milk"))
      (is (search "Write &lt;tests&gt;" (browser-html b)))
      (set-checkbox b 0 t)
      (press b "Save")
      (is (search "class=\"done\">Buy milk" (browser-html b)))
      (set-checkbox b 0 nil)
      (press b "Save")
      (is (not (search "class=\"done\"" (browser-html b)))))))

(test cookie-sessions
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment :cookie-sessions t))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (is (not (search "_s=" (browser-url b))))
      (is (browser-cookies b))
      (click b "++")
      (is (= 1 (count-shown b))))))

(test static-and-not-found
  (with-fresh-applications ()
    (let ((b (make-instance 'browser)))
      (visit b "/littoral/files/littoral.js")
      (is (= 200 (browser-status b)))
      (is (search "data-lt-action" (browser-html b)))
      (visit b "/littoral/files/../littoral.asd")
      (is (= 404 (browser-status b)))
      (visit b "/nowhere")
      (is (= 404 (browser-status b))))))

(defclass broken (component) ())
(defmethod render ((self broken))
  (anchor (:callback (lambda () (error "Kaboom"))) "explode"))

(test errors-render-a-page
  (with-fresh-applications (("/broken" 'broken :mode :development))
    (let ((b (make-instance 'browser)))
      (visit b "/broken")
      (click b "explode")
      (is (= 500 (browser-status b)))
      (is (has-text-p b "Kaboom")))))

(test basic-auth
  (with-fresh-applications (("/secret" 'littoral-examples:counter :credentials '("u" . "p")))
    (let ((b (make-instance 'browser)))
      (is (= 401 (raw-request b :get "/secret"))))))

(test mounted-under-a-prefix
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :development))
    (let* ((app (lack:builder
                 (:mount "/apps" (make-lack-app :prefix "/apps"))
                 (lambda (env) (declare (ignore env)) '(404 () ("outside")))))
           (b (make-instance 'browser :app app)))
      (visit b "/apps/counter")
      (is (= 200 (browser-status b)))
      (is (alexandria:starts-with-subseq "/apps/counter?" (browser-url b)))
      (is (search "href=\"/apps/littoral/files/littoral.css\"" (browser-html b)))
      (is (search "data-lt-action=\"/apps/counter?" (browser-html b)))
      (is (search "href=\"/apps/counter\">New Session" (browser-html b)))
      (click b "++")
      (is (= 1 (count-shown b)))
      (visit b "/apps/littoral/files/littoral.js")
      (is (= 200 (browser-status b))))))

(test script-name-is-honoured
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((app (make-lack-app)))
      (destructuring-bind (status headers body)
          (funcall app (append (list :script-name "/proxy") (make-env :get "/counter")))
        (declare (ignore body))
        (is (= 302 status))
        (is (alexandria:starts-with-subseq "/proxy/counter?" (getf headers :location)))))))

(test file-upload
  (with-fresh-applications (("/upload" 'littoral-examples:upload-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/upload")
      (is (search "enctype=\"multipart/form-data\"" (browser-html b)))
      (attach-file b "file" "notes.txt" "text/plain" "héllo <world>")
      (press b "Upload")
      (is (has-text-p b "notes.txt"))
      (is (has-text-p b "text/plain"))
      (is (has-text-p b "14 bytes"))
      (is (search "héllo &lt;world&gt;" (browser-html b)))
      ;; Browsers send an empty filename when no file is chosen; that
      ;; leaves the last upload alone.
      (attach-file b "file" "" "application/octet-stream" "")
      (press b "Upload")
      (is (has-text-p b "notes.txt")))))

(test multipart-text-fields
  ;; Ordinary fields still reach their callbacks in a multipart form.
  (with-fresh-applications (("/todo" 'littoral-examples:todo-list :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/todo")
      (fill-in b "new-title" "From multipart")
      (setf (browser-files b) (list (list "unused" "x.bin" "application/octet-stream" #())))
      (press b "Add")
      (is (has-text-p b "From multipart")))))

(test bookmarkable-urls
  (with-fresh-applications (("/topics" 'littoral-examples:topics :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/topics")
      (click b "tasks")
      (is (alexandria:starts-with-subseq "/topics/tasks?_s=" (browser-url b)))
      (click b "bigger")
      (is (alexandria:starts-with-subseq "/topics/tasks?big&_s=" (browser-url b)))
      (is (search "data-lt-action=\"/topics/tasks?big&amp;_s=" (browser-html b)))
      ;; A bookmark, opened in a new session, comes back to the same page.
      (let ((bookmark (subseq (browser-url b) 0 (search "&_s=" (browser-url b))))
            (fresh (make-instance 'browser)))
        (is (string= "/topics/tasks?big" bookmark))
        (visit fresh bookmark)
        (is (has-text-p fresh "A flow of calls"))
        (is (has-text-p fresh "smaller"))
        (is (alexandria:starts-with-subseq "/topics/tasks?big&_s=" (browser-url fresh))))
      ;; Unknown topics are ignored.
      (let ((fresh (make-instance 'browser)))
        (visit fresh "/topics/nonsense")
        (is (= 200 (browser-status fresh)))
        (is (alexandria:starts-with-subseq "/topics?_s=" (browser-url fresh)))))))

(test extra-path-segments
  (with-fresh-applications (("/a" 'littoral-examples:counter))
    (let ((*request* (lack/request:make-request (make-env :get "/a/b%20c/d/")))
          (littoral:*application* (find-application "/a")))
      (is (equal '("b c" "d") (request-extra-path))))))

(test reserved-parameters
  (signals error (add-parameter (make-instance 'page-url) "_k" "x")))
