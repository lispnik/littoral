;;;; security.lisp — limits, session fixation, local-only applications

(in-package #:littoral/tests)

(def-suite security :in littoral)
(in-suite security)

(test session-fixation-is-refused
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((owner (make-instance 'browser)))
      (visit owner "/counter")
      (click owner "++")
      (let ((shared (browser-url owner)))
        ;; Someone without the owner's cookie follows the link...
        (let ((stranger (make-instance 'browser)))
          (visit stranger shared)
          (is (= 0 (count-shown stranger)))
          (is (not (string= (subseq shared 0 (search "&_k" shared))
                            (subseq (browser-url stranger) 0 (search "&_k" (browser-url stranger))))))
          ;; ...and their clicks do not reach the owner's session.
          (click stranger "++") (click stranger "++"))
        ;; Nor does someone with a different session's cookie.
        (let ((other (make-instance 'browser)))
          (visit other "/counter")
          (visit other shared)
          (is (= 0 (count-shown other))))
        (click owner "++")
        (is (= 2 (count-shown owner)))))))

(test cookieless-browsers-still-work
  ;; A browser that never returns cookies keeps its session through the URL.
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (setf (browser-cookies b) '())
      (let ((app (browser-app b)))
        (flet ((get-page (url)
                 (loop repeat 5
                       do (destructuring-bind (status headers body) (funcall app (make-env :get url))
                            (if (= status 302)
                                (setf url (getf headers :location))
                                (return (values url (apply #'concatenate 'string body))))))))
          (multiple-value-bind (url html) (get-page "/counter")
            (declare (ignore url))
            (let ((href (cl-ppcre:register-groups-bind (h) ("<a href=\"([^\"]*)\">\\+\\+</a>" html)
                          (unescape h))))
              (multiple-value-bind (url2 html2) (get-page href)
                (declare (ignore url2))
                (is (search "<h1>1</h1>" html2))))))))))

(test oversized-requests-are-refused
  (with-fresh-applications (("/upload" 'littoral-examples:upload-demo :mode :deployment
                                       :max-request-size 1000))
    (let ((b (make-instance 'browser)))
      (visit b "/upload")
      (attach-file b "file" "big.txt" "text/plain" (make-string 2000 :initial-element #\x))
      (press b "Upload")
      (is (= 413 (browser-status b)))
      (is (has-text-p b "larger than the 1,000 bytes"))))
  (let ((*max-request-size* 10))
    (with-fresh-applications (("/todo" 'littoral-examples:todo-list :mode :deployment))
      (let ((b (make-instance 'browser)))
        (visit b "/todo")
        (fill-in b "new-title" "a title longer than ten bytes")
        (press b "Add")
        (is (= 413 (browser-status b)))))))

(test chunked-bodies-need-a-length
  (with-fresh-applications (("/todo" 'littoral-examples:todo-list))
    (let ((env (make-env :post "/todo")))
      (setf (gethash "transfer-encoding" (getf env :headers)) "chunked")
      (is (= 411 (first (funcall (make-lack-app) env)))))))

(test new-session-rate-limit
  (let ((*new-sessions-per-minute* 3)
        (littoral::*session-starts* (make-hash-table :test 'equal)))
    (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
      (let ((statuses (loop repeat 5
                            collect (first (funcall (make-lack-app) (make-env :get "/counter"))))))
        (is (equal '(302 302 302 429 429) statuses)))
      ;; Existing sessions are not affected.
      (let ((b (make-instance 'browser)))
        (setf littoral::*session-starts* (make-hash-table :test 'equal))
        (visit b "/counter")
        (let ((*new-sessions-per-minute* 0))
          (click b "++")
          (is (= 1 (count-shown b))))))))

(test config-is-local-only-by-default
  (with-fresh-applications ()
    (configure-admin)
    (let ((app (make-lack-app)))
      (is (= 302 (first (funcall app (make-env :get "/config")))))
      (let ((remote (make-env :get "/config")))
        (setf (getf remote :remote-addr) "203.0.113.9")
        (is (= 403 (first (funcall app remote)))))
      ;; A local proxy forwarding someone else is not local.
      (let ((proxied (make-env :get "/config")))
        (setf (gethash "x-forwarded-for" (getf proxied :headers)) "203.0.113.9")
        (is (= 403 (first (funcall app proxied)))))
      ;; With credentials it answers anyone who has them.
      (configure-admin :user "admin" :password "pw")
      (let ((remote (make-env :get "/config")))
        (setf (getf remote :remote-addr) "203.0.113.9")
        (is (= 401 (first (funcall app remote))))
        (setf (gethash "authorization" (getf remote :headers))
              (format nil "Basic ~A" (cl-base64:string-to-base64-string "admin:pw")))
        (is (= 302 (first (funcall app remote))))
        (setf (gethash "authorization" (getf remote :headers))
              (format nil "Basic ~A" (cl-base64:string-to-base64-string "admin:pX")))
        (is (= 401 (first (funcall app remote))))))))

(test event-stream-caps
  (let ((*max-event-streams-per-session* 0))
    (with-fresh-applications (("/chat" 'littoral-examples:chat :mode :deployment))
      (let ((b (make-instance 'browser)))
        (join-chat b "dave")
        (let ((url (cl-ppcre:register-groups-bind (u) ("data-lt-events=\"([^\"]*)\"" (browser-html b))
                     (unescape u))))
          (is (= 503 (first (funcall (browser-app b)
                                     (make-env :get url :cookies (browser-cookies b)))))))))))

(test session-keys-are-unbiased
  ;; Every character of the alphabet turns up about as often as the others.
  (let ((counts (make-hash-table)))
    (loop repeat 2000
          do (loop for c across (littoral::random-key 31) do (incf (gethash c counts 0))))
    (is (= 62 (hash-table-count counts)))
    (let ((low (loop for v being the hash-values of counts minimize v))
          (high (loop for v being the hash-values of counts maximize v)))
      (is (< (/ high low) 1.25) "spread ~A..~A" low high))))

(test two-tabs-in-one-browser
  ;; Opening an application again in another tab must not lock the first
  ;; tab out of its session: both are tied to the same browser.
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment))
    (let ((first-tab (make-instance 'browser)))
      (visit first-tab "/counter")
      (click first-tab "++")
      (let ((second-tab (make-instance 'browser :app (browser-app first-tab))))
        ;; The same cookie jar.
        (setf (browser-cookies second-tab) (browser-cookies first-tab))
        (visit second-tab "/counter")
        (click second-tab "++") (click second-tab "++")
        (setf (browser-cookies first-tab) (browser-cookies second-tab))
        (click first-tab "++")
        (is (= 2 (count-shown first-tab)))
        (is (= 2 (count-shown second-tab)))
        (is (not (string= (subseq (browser-url first-tab) 0 (search "&_k" (browser-url first-tab)))
                          (subseq (browser-url second-tab) 0 (search "&_k" (browser-url second-tab))))))))))
