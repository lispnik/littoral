;;;; chrome.lisp — test a Littoral application in a real Chrome, from Lisp
;;;;
;;;;   (littoral.browser-test:with-chrome (page :base "http://127.0.0.1:8080")
;;;;     (visit page "/examples/counter")
;;;;     (click-text page "++")
;;;;     (is (search "1" (text page "h1"))))
;;;;
;;;; Chrome runs headless with a fresh profile, driven over the DevTools
;;;; protocol; pages run their JavaScript, so AJAX, server push, dialogs and
;;;; passkeys (with a virtual authenticator) can be tested as users meet them.
;;;; The fake browser (littoral/test) is faster and needs no Chrome; use this
;;;; for what only a browser does.

(defpackage #:littoral.browser-test
  (:use #:cl)
  (:documentation "Drive headless Chrome from Lisp tests.")
  (:export #:with-chrome #:chrome-path #:page #:visit #:evaluate #:click-text #:click-css #:type-into
           #:text #:page-url #:back #:wait-until #:screenshot #:add-virtual-authenticator #:browser-error))

(in-package #:littoral.browser-test)

(define-condition browser-error (error)
  ((message :initarg :message :reader browser-error-message))
  (:report (lambda (c s) (write-string (browser-error-message c) s)))
  (:documentation "Chrome couldn't do what a test asked: no such element, a timeout, a JavaScript error."))

(defun fail (control &rest arguments)
  (error 'browser-error :message (apply #'format nil control arguments)))

(defun chrome-path ()
  "Chrome or Chromium: $CHROME, $LITTORAL_TEST_CHROME, or the usual places."
  (or (uiop:getenv "CHROME") (uiop:getenv "LITTORAL_TEST_CHROME")
      (find-if #'probe-file '("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
                              "/Applications/Chromium.app/Contents/MacOS/Chromium"
                              "/usr/bin/google-chrome" "/usr/bin/chromium" "/usr/bin/chromium-browser"))
      (fail "No Chrome found: set CHROME to its path.")))

(defclass page ()
  ((socket :initarg :socket :reader page-socket)
   (base :initarg :base :reader page-base)
   (next-id :initform 0 :accessor page-next-id)
   (replies :initform (make-hash-table) :reader page-replies)
   (lock :initform (sb-thread:make-mutex :name "browser test") :reader page-lock)
   (ready :initform (sb-thread:make-waitqueue) :reader page-ready))
  (:documentation "A Chrome tab, driven over the DevTools protocol."))

(defun send (page method &optional (params (make-hash-table :test 'equal)) (timeout 30))
  "Call the DevTools METHOD with PARAMS (a hash table); its result."
  (let ((id (sb-thread:with-mutex ((page-lock page)) (incf (page-next-id page))))
        (message (make-hash-table :test 'equal)))
    (setf (gethash "id" message) id (gethash "method" message) method (gethash "params" message) params)
    (wsd:send (page-socket page) (com.inuoe.jzon:stringify message))
    (sb-thread:with-mutex ((page-lock page))
      (loop with deadline = (+ (get-internal-real-time) (* timeout internal-time-units-per-second))
            for reply = (gethash id (page-replies page))
            until reply
            do (when (> (get-internal-real-time) deadline) (fail "Chrome didn't answer ~A" method))
               (sb-thread:condition-wait (page-ready page) (page-lock page) :timeout 0.5)
               (unless (sb-thread:holding-mutex-p (page-lock page)) (sb-thread:grab-mutex (page-lock page)))
            finally (remhash id (page-replies page))
                    (let ((error (gethash "error" reply)))
                      (when error (fail "~A: ~A" method (gethash "message" error))))
                    (return (gethash "result" reply))))))

(defun params (&rest pairs)
  "A hash table of PAIRS, for SEND."
  (let ((table (make-hash-table :test 'equal)))
    (loop for (key value) on pairs by #'cddr do (setf (gethash key table) value))
    table))

(defun evaluate (page javascript)
  "The value of JAVASCRIPT in PAGE (promises awaited), as JSON-able Lisp data."
  (let* ((result (send page "Runtime.evaluate"
                       (params "expression" javascript "awaitPromise" t "returnByValue" t)))
         (exception (gethash "exceptionDetails" result)))
    (when exception
      (fail "JavaScript failed: ~A" (or (gethash "description" (gethash "exception" exception))
                                        (gethash "text" exception))))
    (gethash "value" (gethash "result" result))))

(defun wait-until (page javascript &key (timeout 10))
  "Wait until JAVASCRIPT is true in PAGE; signals BROWSER-ERROR after TIMEOUT seconds."
  (loop repeat (* timeout 10)
        when (ignore-errors (evaluate page javascript)) return t
        do (sleep 0.1)
        finally (fail "Timed out waiting for ~A" javascript)))

(defun settle (page)
  "Wait for the page (and any navigation a click started) to finish loading."
  (sleep 0.25)
  (wait-until page "document.readyState === 'complete'"))

(defun visit (page path)
  "Open PATH (relative to the page's base URL, or absolute)."
  (send page "Page.navigate" (params "url" (if (alexandria:starts-with-subseq "http" path)
                                               path
                                               (concatenate 'string (page-base page) path))))
  (settle page))

(defun page-url (page)
  "Where PAGE is."
  (evaluate page "location.href"))

(defun back (page)
  "The browser's back button."
  (evaluate page "history.back()")
  (settle page))

(defun js-string (string) (com.inuoe.jzon:stringify string))

(defun click-css (page selector)
  "Click the first element SELECTOR matches, as a user would."
  (unless (evaluate page (format nil "(() => { const e = document.querySelector(~A); if (!e) return false; e.click(); return true; })()"
                                 (js-string selector)))
    (fail "Nothing matches ~A" selector))
  (settle page))

(defun click-text (page text &key (among "a, button"))
  "Click the first link or button (or what AMONG selects) whose text is TEXT,
or failing that contains it."
  (unless (evaluate page (format nil "(() => { const all = [...document.querySelectorAll(~A)];
  const e = all.find(e => e.textContent.trim() === ~A) || all.find(e => e.textContent.includes(~:*~A));
  if (!e) return false; e.click(); return true; })()" (js-string among) (js-string text)))
    (fail "Nothing (~A) says ~S" among text))
  (settle page))

(defun type-into (page selector string)
  "Type STRING into the field SELECTOR matches, key by key."
  (click-css page selector)
  (evaluate page (format nil "(() => { const e = document.querySelector(~A); e.focus(); e.select && e.select(); })()"
                         (js-string selector)))
  (send page "Input.insertText" (params "text" string))
  (sleep 0.2))

(defun text (page &optional (selector "body"))
  "The visible text of what SELECTOR matches."
  (or (evaluate page (format nil "(document.querySelector(~A) || {}).innerText || ''" (js-string selector))) ""))

(defun screenshot (page pathname)
  "Save PAGE as a PNG at PATHNAME."
  (let ((data (gethash "data" (send page "Page.captureScreenshot" (params "format" "png")))))
    (with-open-file (out pathname :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
      (write-sequence (cl-base64:base64-string-to-usb8-array data) out))
    pathname))

(defun add-virtual-authenticator (page)
  "Give PAGE a platform authenticator that always says yes, for passkey tests."
  (send page "WebAuthn.enable")
  (send page "WebAuthn.addVirtualAuthenticator"
        (params "options" (params "protocol" "ctap2" "transport" "internal" "hasResidentKey" t
                                  "hasUserVerification" t "isUserVerified" t "automaticPresenceSimulation" t))))

(defun free-port ()
  (let ((socket (usocket:socket-listen "127.0.0.1" 0)))
    (prog1 (usocket:get-local-port socket) (usocket:socket-close socket))))

(defun call-with-chrome (function &key (base "http://127.0.0.1:8080") (width 1280) (height 800))
  (let* ((port (free-port))
         (profile (uiop:ensure-directory-pathname
                   (merge-pathnames (format nil "littoral-chrome-~36R/" (random (expt 36 8))) (uiop:temporary-directory))))
         (process (sb-ext:run-program (chrome-path)
                                      (list "--headless=new" (format nil "--remote-debugging-port=~D" port)
                                            (format nil "--user-data-dir=~A" (namestring profile))
                                            (format nil "--window-size=~D,~D" width height)
                                            "--no-first-run" "--no-default-browser-check" "about:blank")
                                      :wait nil :output nil :error nil)))
    (unwind-protect
         (let ((target nil))
           ;; Chrome takes a moment, more on a busy machine.
           (loop repeat 300 until target
                 do (setf target (ignore-errors
                                  (find "page" (com.inuoe.jzon:parse (dex:get (format nil "http://127.0.0.1:~D/json/list" port)))
                                        :key (lambda (h) (gethash "type" h)) :test #'equal)))
                    (unless target (sleep 0.2)))
           (unless target (fail "Chrome didn't start"))
           (let* ((socket (wsd:make-client (gethash "webSocketDebuggerUrl" target) :max-length (* 64 1024 1024)))
                  (page (make-instance 'page :socket socket :base base)))
             (wsd:on :message socket
                     (lambda (message)
                       (let ((data (com.inuoe.jzon:parse message)))
                         (when (gethash "id" data)
                           (sb-thread:with-mutex ((page-lock page))
                             (setf (gethash (gethash "id" data) (page-replies page)) data)
                             (sb-thread:condition-broadcast (page-ready page)))))))
             (wsd:start-connection socket)
             (send page "Page.enable")
             (send page "Runtime.enable")
             (unwind-protect (funcall function page)
               (ignore-errors (wsd:close-connection socket)))))
      (ignore-errors (sb-ext:process-kill process 9))
      (ignore-errors (sb-ext:process-wait process))
      (ignore-errors (uiop:delete-directory-tree profile :validate t :if-does-not-exist :ignore)))))

(defmacro with-chrome ((page &rest options &key base width height) &body body)
  "Run BODY with PAGE a headless Chrome tab, its paths relative to BASE."
  (declare (ignore base width height))
  `(call-with-chrome (lambda (,page) ,@body) ,@options))
