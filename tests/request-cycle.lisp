;;;; request-cycle.lisp — sessions, callbacks, redirects

(in-package #:littoral/tests)

(def-suite request-cycle :in littoral)
(in-suite request-cycle)

(defun count-shown (browser)
  "The counter value on the current page."
  (parse-integer (cl-ppcre:scan-to-strings "(?<=<h1>)-?\\d+(?=</h1>)" (browser-html browser))))

(test counter
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (is (= 200 (browser-status b)))
      (is (search "_s=" (browser-url b)))
      (is (zerop (count-shown b)))
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
        (is (zerop (count-shown b)))
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

(defclass broken (component) ()
  (:documentation "A component whose link signals an error."))
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
      (is (search "href=\"/apps/littoral/files/littoral.css?v=" (browser-html b)))
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

(test static-files-are-fingerprinted
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let* ((b (make-instance 'browser))
           (src (progn (visit b "/counter")
                       (cl-ppcre:register-groups-bind (s) ("<script src=\"([^\"]*)\"" (browser-html b)) s))))
      (is (cl-ppcre:scan "^/littoral/files/littoral\\.js\\?v=[0-9a-f]{10}$" src))
      (multiple-value-bind (status headers) (raw-request b :get src)
        (is (= 200 status))
        (is (search "immutable" (getf headers :cache-control))))
      ;; Without the current fingerprint, browsers must revalidate.
      (multiple-value-bind (status headers) (raw-request b :get "/littoral/files/littoral.js?v=stale")
        (is (= 200 status))
        (is (string= "no-cache" (getf headers :cache-control)))))))

;;; Hardening

(test security-headers
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (multiple-value-bind (status headers) (raw-request b :get "/counter")
        (is (= 302 status))
        (is (string= "same-origin" (getf headers :referrer-policy))))
      (visit b "/counter")
      (multiple-value-bind (status headers) (raw-request b :get (browser-url b))
        (is (= 200 status))
        (is (string= "same-origin" (getf headers :referrer-policy)))
        (is (string= "nosniff" (getf headers :x-content-type-options)))))))

(test secure-cookie-over-https
  (with-fresh-applications (("/c" 'littoral-examples:counter :cookie-sessions t))
    (let ((app (make-lack-app)))
      (flet ((cookie (env)
               (getf (second (funcall app env)) :set-cookie)))
        (is (not (search "Secure" (cookie (make-env :get "/c")))))
        (let ((env (make-env :get "/c")))
          (setf (gethash "x-forwarded-proto" (getf env :headers)) "https")
          (is (search "; Secure" (cookie env))))))))

(test max-sessions-evicts-least-recent
  (with-fresh-applications (("/counter" 'littoral-examples:counter :max-sessions 2))
    (let ((a (make-instance 'browser)) (b (make-instance 'browser)) (c (make-instance 'browser)))
      (visit a "/counter")
      (sleep 1.1)
      (visit b "/counter")
      (sleep 1.1)                       ; last access is kept in whole seconds
      (click a "++")                    ; a is now more recent than b
      (sleep 1.1)
      (visit c "/counter")
      (let ((live (littoral::list-sessions (find-application "/counter"))))
        (is (= 2 (length live))))
      ;; a survived; b was evicted and starts over.
      (click a "++")
      (is (= 2 (count-shown a))))))

(test reaper-thread
  (with-fresh-applications (("/counter" 'littoral-examples:counter :session-timeout 1))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (is (= 1 (length (littoral::list-sessions (find-application "/counter")))))
      (sleep 2.1)                       ; idle time is counted in whole seconds
      (reap-all-sessions)
      (is (zerop (length (littoral::list-sessions (find-application "/counter")))))))
  (start-reaper :interval 1)
  (is (sb-thread:thread-alive-p littoral::*reaper*))
  (stop-reaper)
  (is (null littoral::*reaper*)))

(defclass cancellable (component)
  ((name :initform "kept" :accessor cancellable-name)
   (log :initform '() :accessor cancellable-log))
  (:documentation "A form with save, cancel and default actions that logs which ran."))

(defmethod render ((self cancellable))
  (p () "Name: " (text (cancellable-name self))
    " Log: " (text (format nil "~{~A~^,~}" (reverse (cancellable-log self)))))
  (form (:default-action (lambda () (push :default (cancellable-log self))))
    (text-input (:id "name" :value (cancellable-name self)
                 :callback (lambda (v) (setf (cancellable-name self) v))))
    (submit-button (:callback (lambda () (push :save (cancellable-log self)))) "Save")
    (cancel-button (:callback (lambda () (push :cancel (cancellable-log self)))) "Cancel")))

(test cancel-and-default-action
  (with-fresh-applications (("/c" 'cancellable :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/c")
      (fill-in b "name" "changed")
      (press b "Cancel")
      (is (has-text-p b "Name: kept Log: CANCEL"))
      (fill-in b "name" "changed")
      (press b "Save")
      (is (has-text-p b "Name: changed Log: CANCEL,SAVE"))
      ;; Submitting with no button (Enter in a form without one) runs the default.
      (fill-in b "name" "entered")
      (visit b (form-action b) :method :post :body (encode-fields (browser-fields b)))
      (is (has-text-p b "Name: entered Log: CANCEL,SAVE,DEFAULT")))))

(defclass kaboom (component) ()
  (:documentation "A component whose link signals an error."))
(defmethod render ((self kaboom))
  (anchor (:callback (lambda () (error "Kaboom"))) "explode"))

(defclass sorry (component)
  ((condition :initarg :condition :reader sorry-condition))
  (:documentation "A custom error page."))
(defmethod render ((self sorry))
  (h1 () "Sorry") (p () (text (sorry-condition self))) (anchor (:href "/k") "Start again"))

(test custom-error-handler
  (with-fresh-applications (("/k" 'kaboom :mode :deployment
                                  :error-handler (lambda (c) (make-instance 'sorry :condition c))))
    (let ((b (make-instance 'browser)))
      (visit b "/k")
      (click b "explode")
      (is (= 500 (browser-status b)))
      (is (has-text-p b "Sorry"))
      (is (has-text-p b "Kaboom"))))
  ;; A handler that fails itself falls back to the standard page.
  (with-fresh-applications (("/k" 'kaboom :mode :deployment
                                  :error-handler (lambda (c) (declare (ignore c)) (error "worse"))))
    (let ((b (make-instance 'browser)))
      (visit b "/k")
      (click b "explode")
      (is (= 500 (browser-status b)))
      (is (has-text-p b "Internal Server Error")))))

(test expired-notice
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment
                                        :session-timeout 1 :expired-notice 'session-expired-notice))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (click b "++")
      (sleep 2.1)
      (visit b (browser-url b))
      (is (has-text-p b "Your session expired"))
      (press b "Continue")
      (is (zerop (count-shown b)))
      ;; A first visit, naming no session, sees no notice.
      (let ((fresh (make-instance 'browser)))
        (visit fresh "/counter")
        (is (not (has-text-p fresh "expired")))))))

(defclass leaver (component) ()
  (:documentation "Sends the browser elsewhere, or refuses."))

(defmethod render ((self leaver))
  (anchor (:callback (lambda () (redirect-to "https://example.org/elsewhere"))) "leave")
  (anchor (:callback (lambda () (error 'forbidden :message "Admins only."))) "forbidden")
  (button (:id "ajax-leave" :on-click (ajax :callback (lambda () (redirect-to "https://example.org/ajax")))) "go"))

(test redirect-to-and-forbidden
  (with-fresh-applications (("/l" 'leaver :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/l")
      (multiple-value-bind (status headers) (raw-request b :get (find-link b "leave"))
        (is (= 302 status))
        (is (string= "https://example.org/elsewhere" (getf headers :location))))
      (click b "forbidden")
      (is (= 403 (browser-status b)))
      (is (has-text-p b "Admins only."))
      (visit b "/l")
      (let* ((spec (element-spec b "ajax-leave" "on-click"))
             (json (ajax-request b (first spec) (rest spec))))
        (is (search "\"redirect\":\"https://example.org/ajax\"" json))))))
