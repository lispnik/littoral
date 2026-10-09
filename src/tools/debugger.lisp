;;;; debugger.lisp — an error in development mode, shown in the page
;;;;
;;;; When a callback or a render signals in a development-mode application,
;;;; the page shows the condition, the frames that led to it (the
;;;; application's first, with their arguments, local variables and source),
;;;; the restarts that were on offer, and the request.  Retry sends the same
;;;; request again: fix the code, recompile it, and retry.  AJAX and
;;;; WebSocket requests that fail show the same page.  Deployment mode shows
;;;; a plain error page; *DEBUG-ERRORS* hands errors to the Lisp debugger.

(in-package #:littoral)

(defparameter *debugger-frames* 60 "Most frames the debugger page shows.")

(defparameter *library-packages*
  '("SB-" "LITTORAL" "HUNCHENTOOT" "CLACK" "LACK" "CL-CONT" "WOO" "WEBSOCKET-DRIVER" "DBI" "DBD"
    "USOCKET" "BORDEAUX-THREADS" "BT2" "FIVEAM" "IT.BESE" "COMMON-LISP" "UIOP" "ASDF")
  "Package name prefixes whose frames the debugger folds away as the
framework's rather than the application's.")

(defun printed (value &optional (limit 300))
  "VALUE printed briefly and safely."
  (let ((text (handler-case (let ((*print-length* 8) (*print-level* 3) (*print-circle* t)
                                  (*print-readably* nil) (*print-pretty* nil))
                              (prin1-to-string value))
                (error () "#<error printing>"))))
    (if (> (length text) limit) (concatenate 'string (subseq text 0 limit) "…") text)))

(defun frame-name-package (name)
  "The package of the symbol naming a frame's function, or NIL."
  (let ((symbol (cond ((symbolp name) name)
                      ((and (consp name) (symbolp (second name))
                            (member (first name) '(setf sb-pcl::fast-method sb-pcl::slow-method
                                                   lambda flet labels sb-impl::%defun :method)))
                       (second name))
                      ((and (consp name) (consp (second name))) (frame-name-symbol (second name))))))
    (and symbol (symbolp symbol) (symbol-package symbol))))

(defun frame-name-symbol (name)
  (cond ((symbolp name) name)
        ((consp name) (some #'frame-name-symbol (rest name)))
        (t nil)))

(defun library-frame-p (name)
  (let ((package (frame-name-package name)))
    (or (null package)
        (let ((package-name (package-name package)))
          (some (lambda (prefix) (alexandria:starts-with-subseq prefix package-name)) *library-packages*)))))

(defun frame-source (debug-fun)
  "\"file:line\" where DEBUG-FUN's function is defined, or NIL."
  (ignore-errors
   (let* ((function (sb-di::debug-fun-fun debug-fun))
          (source (and function (sb-introspect:find-definition-source function)))
          (pathname (and source (sb-introspect:definition-source-pathname source)))
          (offset (and source (sb-introspect:definition-source-character-offset source))))
     (when (and pathname (probe-file pathname))
       (format nil "~A~@[:~D~]" (namestring pathname)
               (and offset
                    (with-open-file (in pathname :external-format :utf-8)
                      (1+ (loop repeat offset
                                for char = (read-char in nil nil)
                                while char count (char= char #\Newline))))))))))

(defun frame-locals (frame debug-fun)
  "FRAME's valid local variables, as (NAME . PRINTED-VALUE)."
  (ignore-errors
   (let ((location (sb-di::frame-code-location frame)))
     (loop for var in (sb-di::ambiguous-debug-vars debug-fun "")
           when (eq (sb-di::debug-var-validity var location) :valid)
             collect (cons (string-downcase (princ-to-string (sb-di::debug-var-symbol var)))
                           (printed (sb-di::debug-var-value var frame)))))))

(defun frame-call (frame)
  "FRAME's function and arguments, as printed text."
  (or (ignore-errors
       (let ((*print-length* 6) (*print-level* 3) (*print-readably* nil) (*print-pretty* nil))
         (string-trim '(#\Space #\Newline)
                      (with-output-to-string (out)
                        (sb-debug::print-frame-call frame out)))))
      "?"))

(defparameter *signalling-functions*
  '(error cerror signal warn sb-kernel::internal-error sb-kernel:with-simple-condition-restarts
    sb-int:bug sb-kernel::%signal sb-impl::call-with-sane-io-syntax)
  "Functions between the error and the code that caused it.")

(defun collect-frames ()
  "The frames from where the error was signalled outwards, as plists of
:CALL :LOCALS :SOURCE :LIBRARY."
  (let ((frames '()))
    ;; MAP-BACKTRACE is exported only by newer SBCLs; it exists in older ones.
    (funcall (find-symbol "MAP-BACKTRACE" "SB-DEBUG")
     (lambda (frame)
       (let* ((debug-fun (sb-di::frame-debug-fun frame))
              (name (ignore-errors (sb-di::debug-fun-name debug-fun))))
         (push (list :name name :call (frame-call frame)
                     :locals (frame-locals frame debug-fun)
                     :source (frame-source debug-fun)
                     :library (library-frame-p name))
               frames)))
     :count (+ *debugger-frames* 40))
    (setf frames (nreverse frames))
    ;; Skip the handler and the signalling machinery: start after the last
    ;; signalling function near the top.
    (let ((start (position-if (lambda (frame) (member (getf frame :name) *signalling-functions*))
                              frames :end (min 30 (length frames)) :from-end t)))
      (subseq frames (if start (1+ start) 0)
              (min (length frames) (+ (if start (1+ start) 0) *debugger-frames*))))))

(defun request-summary ()
  "The failing request's method, URL and parameters.  A WebSocket message
has no request of its own: only its parameters."
  (list :method (if *request* (string (lack/request:request-method *request*)) "WEBSOCKET")
        :uri (if *request* (lack/request:request-uri *request*) "")
        :parameters (ignore-errors
                     (remove-if (lambda (pair) (typep (cdr pair) 'uploaded-file)) (current-parameters)))))

(defun retry-form (request)
  "A form sending REQUEST again, as an ordinary request even if it was AJAX."
  (when (string= (getf request :uri) "")
    (return-from retry-form ""))
  (let* ((uri (getf request :uri))
         (parameters (remove-if (lambda (pair) (member (car pair) '("_lt_ajax" "_lt_update" "_lt_value")
                                                       :test #'string=))
                                (getf request :parameters)))
         (get-p (string-equal (getf request :method) "GET")))
    (if get-p
        (format nil "<a class=\"lt-debugger-button\" href=\"~A\">Retry</a>" (html-escape uri))
        (with-output-to-string (out)
          (format out "<form method=\"post\" action=\"~A\" class=\"lt-debugger-retry\">" (html-escape uri))
          (loop for (name . value) in parameters
                do (format out "<input type=\"hidden\" name=\"~A\" value=\"~A\">"
                           (html-escape name) (html-escape (princ-to-string value))))
          (format out "<button type=\"submit\" class=\"lt-debugger-button\" autofocus>Retry</button></form>")))))

(defun page-link ()
  "The page the request came from, without its callbacks, or NIL."
  (let ((session (ignore-errors (request-parameter "_s")))
        (page (ignore-errors (request-parameter "_k"))))
    (when page
      (format nil "~A?~@[_s=~A&~]_k=~A" (url-for (application-path *application*))
              (and session (quri:url-encode session)) (quri:url-encode page)))))

(defun render-frame (frame open)
  (with-output-to-string (out)
    (format out "<details class=\"lt-frame~:[~; lt-library~]\"~:[~; open~]><summary><code>~A</code>~@[ <span class=\"lt-frame-source\">~A</span>~]</summary>"
            (getf frame :library) open (html-escape (getf frame :call))
            (and (getf frame :source) (html-escape (getf frame :source))))
    (if (getf frame :locals)
        (progn
          (format out "<table class=\"lt-table lt-locals\">")
          (loop for (name . value) in (getf frame :locals)
                do (format out "<tr><th>~A</th><td><code>~A</code></td></tr>" (html-escape name) (html-escape value)))
          (format out "</table>"))
        (format out "<p class=\"lt-help\">No local variables recorded (compile with (debug 2) or more for them).</p>"))
    (format out "</details>")))

(defun debugger-html (condition)
  "The debugger page for CONDITION, made while its stack is still there."
  (let* ((frames (collect-frames))
         (restarts (mapcar (lambda (r) (printed r 160)) (compute-restarts condition)))
         (request (request-summary))
         (shown-open 0)
         (back (page-link)))
    (with-output-to-string (out)
      (format out "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">~
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>~A</title>~
<link rel=\"stylesheet\" href=\"~A\"><style>
.lt-debugger h1 { font-size: 1.3rem; margin-bottom: .2rem; }
.lt-debugger .lt-condition { font-size: 1.15rem; white-space: pre-wrap; color: var(--lt-error); font-weight: 600; margin: .4rem 0 1rem; }
.lt-debugger-actions { display: flex; flex-wrap: wrap; gap: .6rem; align-items: center; margin: 1rem 0; }
.lt-debugger-retry { margin: 0; }
.lt-debugger-button { display: inline-block; padding: .35rem .9rem; border: 1px solid var(--lt-border); border-radius: 6px;
  background: var(--lt-panel); color: var(--lt-fg); text-decoration: none; font: inherit; cursor: pointer; }
.lt-frame { border: 1px solid var(--lt-border); border-radius: 6px; margin: .3rem 0; padding: .2rem .6rem; overflow-x: auto; }
.lt-frame summary { cursor: pointer; }
.lt-frame code { font-size: .85rem; }
.lt-frame-source { color: var(--lt-muted); font-size: .8rem; }
.lt-library summary code { color: var(--lt-muted); }
.lt-locals th { width: 12rem; font-weight: 500; }
.lt-debugger section { margin-top: 1.5rem; }
</style></head><body class=\"lt-debugger\">"
              (html-escape (printed (type-of condition) 120)) (static-url "littoral.css"))
      (format out "<h1>~A</h1><p class=\"lt-condition\">~A</p>"
              (html-escape (string-downcase (printed (type-of condition) 120)))
              (html-escape (handler-case (princ-to-string condition) (error () (printed condition)))))
      (format out "<div class=\"lt-debugger-actions\">~A~@[<a class=\"lt-debugger-button\" href=\"~A\">Back to the page</a>~]~
<a class=\"lt-debugger-button\" href=\"~A\">New session</a>~
<span class=\"lt-help\">Fix the code, recompile it, then retry: the request runs again.</span></div>"
              (retry-form request) (and back (html-escape back))
              (html-escape (url-for (application-path *application*))))
      (format out "<section><h2>Backtrace</h2>")
      (dolist (frame frames)
        (let ((open (and (not (getf frame :library)) (< shown-open 3))))
          (when open (incf shown-open))
          (write-string (render-frame frame open) out)))
      (format out "<p class=\"lt-help\">Grey frames are the framework's and the system's.</p></section>")
      (when restarts
        (format out "<section><h2>Restarts on offer</h2><ul>~{<li><code>~A</code></li>~}</ul>~
<p class=\"lt-help\">They lapse with the request; set <code>littoral:*debug-errors*</code> to use them in the Lisp debugger.</p></section>"
                (mapcar #'html-escape restarts)))
      (format out "<section><h2>Request</h2><p><code>~A ~A</code></p>"
              (html-escape (getf request :method)) (html-escape (getf request :uri)))
      (when (getf request :parameters)
        (format out "<table class=\"lt-table\">")
        (loop for (name . value) in (getf request :parameters)
              do (format out "<tr><th>~A</th><td><code>~A</code></td></tr>"
                         (html-escape name) (html-escape (printed value 200))))
        (format out "</table>"))
      (format out "</section></body></html>"))))

(defun debugger-response (condition)
  "A 500 response showing the debugger page for CONDITION.  AJAX requests
get it marked, for littoral.js to show in place of the page."
  (let ((html (ignore-errors (debugger-html condition))))
    (if html
        (list 500 (list* :content-type "text/html; charset=utf-8" :cache-control "no-store"
                         :x-littoral-debugger "1" *security-headers*)
              (list html))
        (simple-page 500 "Internal Server Error"
                     (format nil "<p class=\"lt-error\">~A</p><pre>~A</pre>"
                             (html-escape (printed condition)) (html-escape (backtrace-string)))))))
