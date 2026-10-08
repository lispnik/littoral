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
  (span (:class "ws-count") (text (ws-count self)))
  (button (:id "ws-plus" :on-click (ajax :callback (lambda () (incf (ws-count self))) :update self)) "+"))

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
