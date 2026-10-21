;;;; websocket.lisp — AJAX and push over a real WebSocket, on a real server

(in-package #:littoral/tests)

(def-suite websocket :in littoral)
(in-suite websocket)

(defvar *ws-channel* (make-channel "websocket test"))

(defclass ws-counter (component updatable)
  ((count :initform 0 :accessor ws-count))
  (:documentation "Subscribes to a channel, and counts AJAX clicks."))

(defmethod subscriptions ((self ws-counter)) (list *ws-channel*))

(defmethod render ((self ws-counter))
  (h:span (:class "ws-count") (h:text (ws-count self)))
  (h:button (:id "ws-plus" :on-click (ajax :callback (lambda () (incf (ws-count self))) :update self)) "+"))

(defun close-client (client)
  "Close a test client.  websocket-driver's client destroys its reader
thread on close, which fails when the server's close frame has already
ended that thread; that race is the client library's, not the server's."
  (ignore-errors (wsd:close-connection client)))

(defun free-port ()
  (let ((socket (usocket:socket-listen "127.0.0.1" 0)))
    (prog1 (usocket:get-local-port socket) (usocket:socket-close socket))))

(defun fetch-page (url jar)
  (dex:get url :cookie-jar jar :max-redirects 5))

(defun cookie-header (jar)
  (format nil "~{~A~^; ~}"
          (mapcar (lambda (c) (format nil "~A=~A" (cl-cookie:cookie-name c) (cl-cookie:cookie-value c)))
                  (cl-cookie:cookie-jar-cookies jar))))

(test ajax-and-push-over-a-websocket
  (let ((port (free-port)) (jar (cl-cookie:make-cookie-jar)) (messages '()) (lock (sb-thread:make-mutex)))
    (register-application "/ws-test" 'ws-counter :mode :deployment :websockets t)
    (start :port port)
    (wait-for (lambda () (ignore-errors (usocket:socket-close (usocket:socket-connect "127.0.0.1" port)) t)))
    (unwind-protect
         (let* ((html (fetch-page (format nil "http://127.0.0.1:~D/ws-test" port) jar))
                (ws-url (cl-ppcre:register-groups-bind (u) ("data-lt-ws=\"([^\"]*)\"" html) (unescape u)))
                (spec (cl-ppcre:register-groups-bind (s) ("data-lt-on-click=\"([^\"]*)\"" html) (unescape s))))
           (is (not (null ws-url)))
           ;; The events URL stays, as the fallback.
           (is (search "data-lt-events=" html))
           (let ((client (wsd:make-client (format nil "ws://127.0.0.1:~D~A" port ws-url)
                                          :additional-headers `(("Cookie" . ,(cookie-header jar))))))
             (wsd:on :message client (lambda (m) (sb-thread:with-mutex (lock) (push m messages))))
             (wsd:start-connection client)
             (flet ((received (text)
                      (sb-thread:with-mutex (lock) (some (lambda (m) (search text m)) messages))))
               (is (wait-for (lambda () (eq (wsd:ready-state client) :open))))
               ;; An AJAX request over the socket.
               (destructuring-bind (callback targets) (cl-ppcre:split ";" spec)
                 (wsd:send client (format nil "{\"id\": 7, \"params\": {\"_lt_ajax\": \"1\", \"_lt_update\": \"~A\", \"~A\": \"1\"}}"
                                          targets callback)))
               (is (wait-for (lambda () (received "\"type\":\"reply\",\"id\":7"))))
               (is (received "ws-count\\\">1<"))
               ;; A push, on the same socket.
               (publish *ws-channel*)
               (is (wait-for (lambda () (received "\"type\":\"update\""))))
               (close-client client))))
      (stop)
      (unregister-application "/ws-test"))))

(test websockets-are-per-application
  (with-fresh-applications (("/plain" 'ws-counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/plain")
      (is (search "data-lt-events=" (browser-html b)))
      (is (not (search "data-lt-ws=" (browser-html b)))))))

;;; Security review

(defun ws-page (port jar)
  "Fetch the test page; its WebSocket URL and its click spec."
  (let ((html (fetch-page (format nil "http://127.0.0.1:~D/ws-test" port) jar)))
    (values (cl-ppcre:register-groups-bind (u) ("data-lt-ws=\"([^\"]*)\"" html) (unescape u))
            (cl-ppcre:register-groups-bind (s) ("data-lt-on-click=\"([^\"]*)\"" html) (unescape s)))))

(defmacro with-ws-server ((port) &body body)
  `(let ((,port (free-port)))
     (register-application "/ws-test" 'ws-counter :mode :deployment :websockets t)
     (start :port ,port)
     (wait-for (lambda () (ignore-errors (usocket:socket-close (usocket:socket-connect "127.0.0.1" ,port)) t)))
     (unwind-protect (progn ,@body)
       (stop)
       (unregister-application "/ws-test"))))

(defun ws-connect (port url jar &optional origin)
  (let ((client (wsd:make-client (format nil "ws://127.0.0.1:~D~A" port url)
                                 :additional-headers `(("Cookie" . ,(cookie-header jar))
                                                       ,@(when origin `(("Origin" . ,origin)))))))
    (ignore-errors (wsd:start-connection client))
    client))

(test sockets-from-other-sites-are-refused
  (with-ws-server (port)
    (let ((jar (cl-cookie:make-cookie-jar)))
      (let ((url (ws-page port jar)))
        (let ((evil (ws-connect port url jar "http://evil.example")))
          (sleep 0.3)
          (is (not (eq (wsd:ready-state evil) :open))))
        (let ((own (ws-connect port url jar (format nil "http://127.0.0.1:~D" port))))
          (is (wait-for (lambda () (eq (wsd:ready-state own) :open))))
          (close-client own))))))

(test a-new-session-key-closes-the-socket
  (with-ws-server (port)
    (let* ((jar (cl-cookie:make-cookie-jar))
           (url (ws-page port jar))
           (client (ws-connect port url jar))
           (messages '()))
      (wsd:on :message client (lambda (m) (push m messages)))
      (is (wait-for (lambda () (eq (wsd:ready-state client) :open))))
      ;; Garbage is ignored; the socket stays open.
      (wsd:send client "not json")
      (wsd:send client "{\"id\": \"x\", \"params\": []}")
      (sleep 0.3)
      (is (eq (wsd:ready-state client) :open))
      (is (null messages))
      ;; Signing in (or out) elsewhere gives the session a new key.
      (rotate-session-key (first (list-sessions (find-application "/ws-test"))))
      (is (wait-for (lambda () (member (wsd:ready-state client) '(:closing :closed))) 5)))))

(test sockets-count-against-the-stream-limit
  (with-ws-server (port)
    (let* ((jar (cl-cookie:make-cookie-jar))
           (url (ws-page port jar))
           (limit *max-event-streams-per-session*)
           (first-socket (ws-connect port url jar)))
      ;; Server threads see the global value, not a binding here.
      (setf *max-event-streams-per-session* 1)
      (unwind-protect
           (progn
             (is (wait-for (lambda () (eq (wsd:ready-state first-socket) :open))))
             (let ((second-socket (ws-connect port url jar)))
               (sleep 0.3)
               (is (not (eq (wsd:ready-state second-socket) :open))))
             (close-client first-socket))
        (setf *max-event-streams-per-session* limit)))))

;;; Event streams on Hunchentoot: the hub serves them, not a thread each

(defun open-raw-event-stream (port url jar)
  "Request URL's event stream over a socket of our own; the usocket."
  (let* ((socket (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8)))
         (out (usocket:socket-stream socket)))
    (write-sequence (sb-ext:string-to-octets
                     (format nil "GET ~A HTTP/1.1~C~CHost: 127.0.0.1:~D~C~CAccept: text/event-stream~C~CCookie: ~A~C~C~C~C"
                             url #\Return #\Linefeed port #\Return #\Linefeed #\Return #\Linefeed
                             (cookie-header jar) #\Return #\Linefeed #\Return #\Linefeed)
                     :external-format :latin-1)
                    out)
    (force-output out)
    socket))

(defun read-raw-until (socket text &optional (seconds 15))
  "What SOCKET sends until TEXT has come, as a string; NIL if it doesn't
come within SECONDS (generous, for busy CI machines), with what did come
as a second value."
  (let ((seen (make-array 0 :element-type 'character :adjustable t :fill-pointer 0))
        (deadline (+ (get-internal-real-time) (* seconds internal-time-units-per-second))))
    (loop
      (when (search text seen) (return seen))
      (let ((left (/ (- deadline (get-internal-real-time)) internal-time-units-per-second)))
        (unless (and (plusp left) (usocket:wait-for-input socket :timeout left :ready-only t))
          (return (values nil seen)))
        (let ((byte (read-byte (usocket:socket-stream socket) nil)))
          (unless byte (return (values nil seen)))
          (vector-push-extend (code-char byte) seen))))))

(defun hunchentoot-workers (sockets)
  "How many Hunchentoot threads serve the connections of SOCKETS, ours:
each is named for the client's address and port."
  (count-if (lambda (thread)
              (let ((name (sb-thread:thread-name thread)))
                (and (alexandria:starts-with-subseq "hunchentoot-worker" name)
                     (some (lambda (socket)
                             (alexandria:ends-with-subseq (format nil ":~D" (usocket:get-local-port socket)) name))
                           sockets))))
            (sb-thread:list-all-threads)))

(test event-streams-hold-no-hunchentoot-thread
  (let ((port (free-port)) (sockets '()) (keepalive littoral:*keepalive-seconds*))
    (register-application "/push-hub" 'ws-counter :mode :deployment)
    (start :port port)
    ;; Keepalives come often, so the test sees them and notices a closed page soon.
    (setf littoral:*keepalive-seconds* 0.2)
    (unwind-protect
         (let ((jars (loop repeat 3 collect (cl-cookie:make-cookie-jar))))
           (dolist (jar jars)
             (let* ((html (dex:get (format nil "http://127.0.0.1:~D/push-hub" port) :cookie-jar jar :keep-alive nil))
                    (url (cl-ppcre:register-groups-bind (u) ("data-lt-events=\"([^\"]*)\"" html) (unescape u)))
                    (socket (open-raw-event-stream port url jar)))
               (push socket sockets)
               (let ((head (read-raw-until socket "retry: 3000")))
                 (is (search "HTTP/1.1 200" head))
                 (is (search "Content-Type: text/event-stream" head))
                 (is (search "X-Content-Type-Options: nosniff" head)))))
           ;; Three pages listen, and no Hunchentoot thread waits on them.
           (is (= 3 (littoral::hub-stream-count)))
           (is (wait-for (lambda () (zerop (hunchentoot-workers sockets)))))
           ;; A push reaches each page.
           (publish *ws-channel*)
           (dolist (socket sockets)
             (is (search "event: update" (read-raw-until socket "ws-count"))))
           ;; Idle streams get keepalives, and a page that goes is noticed.
           (is (read-raw-until (first sockets) ": keepalive"))
           (usocket:socket-close (pop sockets))
           (is (wait-for (lambda () (= 2 (littoral::hub-stream-count)))))
           ;; Stopping the server ends the rest.
           (stop)
           (is (wait-for (lambda () (zerop (littoral::hub-stream-count)))))
           (dolist (socket sockets)
             (is (null (read-raw-until socket "never sent" 2)))))
      (setf littoral:*keepalive-seconds* keepalive)
      (mapc (lambda (socket) (ignore-errors (usocket:socket-close socket))) sockets)
      (stop)
      (unregister-application "/push-hub"))))

;;; HTTPS: start with a certificate; the hub serves event streams over TLS too

(defun make-test-certificate (directory)
  "A self-signed certificate and key for 127.0.0.1 in DIRECTORY, made with
openssl: their paths, or NIL without openssl."
  (let ((cert (merge-pathnames "cert.pem" directory))
        (key (merge-pathnames "key.pem" directory)))
    (and (ignore-errors
          (uiop:run-program (list "openssl" "req" "-x509" "-newkey" "rsa:2048" "-nodes" "-days" "1"
                                  "-subj" "/CN=127.0.0.1"
                                  "-keyout" (namestring key) "-out" (namestring cert))
                            :error-output nil :output nil)
          t)
         (probe-file cert)
         (list cert key))))

(test https-pages-and-event-streams
  (let* ((directory (uiop:ensure-directory-pathname
                     (merge-pathnames (format nil "littoral-tls-~36R" (random (expt 36 8))) (uiop:temporary-directory))))
         (files (progn (ensure-directories-exist directory) (make-test-certificate directory)))
         (port (free-port)) (jar (cl-cookie:make-cookie-jar))
         (received (make-array 0 :element-type 'character :adjustable t :fill-pointer 0))
         (lock (sb-thread:make-mutex)) (socket nil))
    (if (null files)
        (skip "openssl is not installed")
        (unwind-protect
             (progn
               (register-application "/tls-test" 'ws-counter :mode :deployment)
               (start :port port :ssl-certificate-file (first files) :ssl-key-file (second files))
               (let* ((html (dex:get (format nil "https://127.0.0.1:~D/tls-test" port)
                                     :cookie-jar jar :insecure t :keep-alive nil))
                      (url (cl-ppcre:register-groups-bind (u) ("data-lt-events=\"([^\"]*)\"" html) (unescape u))))
                 (is (search "ws-count" html) "The page, over HTTPS")
                 ;; The page's event stream, over TLS.
                 (setf socket (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8)))
                 (let ((tls (cl+ssl:make-ssl-client-stream (usocket:socket-stream socket) :verify nil)))
                   (write-sequence (sb-ext:string-to-octets
                                    (format nil "GET ~A HTTP/1.1~C~CHost: 127.0.0.1~C~CCookie: ~A~C~C~C~C"
                                            url #\Return #\Linefeed #\Return #\Linefeed (cookie-header jar)
                                            #\Return #\Linefeed #\Return #\Linefeed)
                                    :external-format :latin-1)
                                   tls)
                   (force-output tls)
                   (sb-thread:make-thread
                    (lambda ()
                      (ignore-errors
                       (loop for byte = (read-byte tls nil) while byte
                             do (sb-thread:with-mutex (lock) (vector-push-extend (code-char byte) received)))))
                    :name "TLS test reader")
                   (flet ((seen (text) (sb-thread:with-mutex (lock) (search text received))))
                     (is (wait-for (lambda () (seen "retry: 3000"))))
                     (is (seen "HTTP/1.1 200"))
                     (is (= 1 (littoral::hub-stream-count)) "The hub serves it")
                     (is (wait-for (lambda () (zerop (hunchentoot-workers (list socket))))) "No thread waits on it")
                     (publish *ws-channel*)
                     (is (wait-for (lambda () (seen "event: update"))) "A push arrives over TLS")))))
          (when socket (ignore-errors (usocket:socket-close socket)))
          (stop)
          (unregister-application "/tls-test")
          (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore)))))

(test start-takes-both-tls-files
  (signals error (start :port (free-port) :ssl-certificate-file "/tmp/cert.pem")))

;;; The hub renders pushes on several threads

(defvar *slow-channel* (make-channel "slow render test"))
(defvar *slow-renders* '() "The threads slow-panel rendered on, by push.")
(defvar *slow-renders-lock* (sb-thread:make-mutex))

(defclass slow-panel (component updatable) ())
(defmethod subscriptions ((self slow-panel)) (list *slow-channel*))
(defmethod render ((self slow-panel))
  (when (string= (sb-thread:thread-name sb-thread:*current-thread*) "littoral push render")
    (sleep 0.3)
    (sb-thread:with-mutex (*slow-renders-lock*) (push sb-thread:*current-thread* *slow-renders*)))
  (h:span () "slow panel"))

(test pushes-render-on-several-threads
  (let ((port (free-port)) (sockets '()))
    (register-application "/slow" 'slow-panel :mode :deployment)
    (start :port port)
    (setf *slow-renders* '())
    (unwind-protect
         (progn
           (dotimes (i 4)
             (let* ((jar (cl-cookie:make-cookie-jar))
                    (html (dex:get (format nil "http://127.0.0.1:~D/slow" port) :cookie-jar jar :keep-alive nil))
                    (url (cl-ppcre:register-groups-bind (u) ("data-lt-events=\"([^\"]*)\"" html) (unescape u)))
                    (socket (open-raw-event-stream port url jar)))
               (push socket sockets)
               (multiple-value-bind (head seen) (read-raw-until socket "retry: 3000")
                 (is-true head "Stream ~D didn't open: got ~S, with ~D streams in the hub"
                          (1+ i) seen (littoral::hub-stream-count)))))
           (let ((start (get-internal-real-time)))
             (publish *slow-channel*)
             (dolist (socket sockets)
               (is (search "slow panel" (read-raw-until socket "slow panel" 5))))
             ;; Four 0.3 s renders, side by side rather than one after another.
             (is (< (/ (- (get-internal-real-time) start) internal-time-units-per-second) 1.1))
             (is (< 1 (length (remove-duplicates *slow-renders*))) "More than one render thread")))
      (mapc (lambda (socket) (ignore-errors (usocket:socket-close socket))) sockets)
      (stop)
      (unregister-application "/slow"))))

(test serving-https-makes-every-request-secure
  ;; Woo calls every request http, even over TLS: START's word counts.
  (let ((request (lack/request:make-request (make-env :get "/page"))))
    (is (not (littoral::secure-request-p request)))
    (let ((littoral::*serving-https* t))
      (is (littoral::secure-request-p request)))))
