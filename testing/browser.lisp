;;;; browser.lisp — a fake browser that drives a Littoral application
;;;;
;;;; It calls the Lack application directly: no sockets, no real browser,
;;;; and fast enough for hundreds of tests.  It keeps cookies, follows
;;;; redirects, reads links, fields and buttons out of the HTML, and posts
;;;; forms (multipart too), AJAX requests and event streams the way a
;;;; browser with littoral.js would.

(in-package #:littoral.test)

(defclass browser ()
  ((app :initarg :app :initform (make-lack-app) :reader browser-app
        :documentation "The Lack application requests go to; by default MAKE-LACK-APP's,
which serves every registered application.")
   (url :initform nil :accessor browser-url
        :documentation "The current page's URL, after redirects, or NIL before the first visit.")
   (status :initform nil :accessor browser-status
           :documentation "The current page's HTTP status, or NIL before the first visit.")
   (html :initform "" :accessor browser-html
         :documentation "The current page's body, as served.")
   (cookies :initform '() :accessor browser-cookies
            :documentation "Alist of cookie name → value, sent with every request.")
   (headers :initarg :headers :initform '() :accessor browser-headers
            :documentation "Alist of header name → value sent with every request,
such as (\"accept-language\" . \"fr\").")
   (fields :initform '() :accessor browser-fields
           :documentation "Alist of field name → value that PRESS submits: the current
page's fields as served, changed by FILL-IN, SET-CHECKBOX and SELECT-OPTION.")
   (files :initform '() :accessor browser-files
          :documentation "Alist of field name → (FILENAME CONTENT-TYPE OCTETS)."))
  (:documentation "A fake browser driving a Lack application in-process.  :APP
is the application (by default every registered one); :HEADERS are sent with
every request."))

(defun split-url (url)
  "URL's path and query string."
  (let ((q (position #\? url)))
    (if q (values (subseq url 0 q) (subseq url (1+ q))) (values url nil))))

(defun make-env (method url &key body cookies extra-headers (content-type "application/x-www-form-urlencoded"))
  "A Lack environment for a METHOD request to URL.  BODY, a string or
octets, is sent as CONTENT-TYPE (form-encoded by default); COOKIES is an
alist of name → value, and EXTRA-HEADERS an alist of header name → value."
  (multiple-value-bind (path query) (split-url url)
    (let ((headers (make-hash-table :test 'equal))
          (octets (if (stringp body)
                      (flexi-streams:string-to-octets body :external-format :utf-8)
                      body)))
      (loop for (name . value) in extra-headers
            do (setf (gethash (string-downcase name) headers) value))
      (when cookies
        (setf (gethash "cookie" headers)
              (format nil "~{~A~^; ~}" (mapcar (lambda (c) (format nil "~A=~A" (first c) (rest c))) cookies))))
      (append (list :request-method method
                    :script-name ""
                    :path-info (quri:url-decode path)
                    :request-uri url
                    :query-string query
                    :server-name "localhost" :server-port 80 :server-protocol :http/1.1
                    :url-scheme "http" :remote-addr "127.0.0.1" :remote-port 1234
                    :headers headers)
              (when octets
                (setf (gethash "content-type" headers) content-type
                      (gethash "content-length" headers) (princ-to-string (length octets)))
                (list :content-type content-type
                      :content-length (length octets)
                      :raw-body (flexi-streams:make-in-memory-input-stream octets)))))))

(defun response-header (headers name)
  "The header NAME from a Lack response's HEADERS plist."
  (getf headers name))

(defun store-cookies (browser headers)
  "Keep every cookie the response HEADERS set, replacing those of the same
name; Max-Age=0 deletes one."
  (loop for (key value) on headers by #'cddr
        when (eq key :set-cookie)
          do (let* ((pair (subseq value 0 (position #\; value)))
                    (eq (position #\= pair))
                    (name (subseq pair 0 eq)))
               (setf (browser-cookies browser)
                     (remove name (browser-cookies browser) :key #'car :test #'string=))
               (unless (cl-ppcre:scan "(?i);\\s*Max-Age=0(?:;|$)" value)
                 (push (cons name (subseq pair (1+ eq))) (browser-cookies browser))))))

(defun local-url (url)
  "URL without its scheme and host, when it has them: the fake browser has
only the one server, so http://localhost/a?b is /a?b."
  (let ((match (nth-value 1 (cl-ppcre:scan-to-strings "^https?://[^/]+(/.*)?$" url))))
    (if match (or (aref match 0) "/") url)))

(defun body-string (body)
  "A Lack response BODY as a string: a list of strings joined, octets (such
as a stored file) decoded as UTF-8, or as Latin-1, byte for byte, when they
aren't UTF-8, and a file read the same way."
  (flet ((decode (octets)
           (handler-case (sb-ext:octets-to-string octets :external-format :utf-8)
             (error () (sb-ext:octets-to-string octets :external-format :latin-1)))))
    (etypecase body
      (list (apply #'concatenate 'string body))
      ((vector (unsigned-byte 8)) (decode (coerce body '(simple-array (unsigned-byte 8) (*)))))
      (pathname (decode (alexandria:read-file-into-byte-vector body))))))

(defun raw-request (browser method url &key body content-type)
  "One METHOD request to URL, sending BODY as CONTENT-TYPE, with no redirect
followed.  Keeps the cookies it sets.  Returns the status, the header plist
and the body as a string."
  (setf url (local-url url))
  (destructuring-bind (status headers body-parts)
      (funcall (browser-app browser)
               (apply #'make-env method url :body body :cookies (browser-cookies browser) :extra-headers (browser-headers browser)
                      (when content-type (list :content-type content-type))))
    (store-cookies browser headers)
    (values status headers (body-string body-parts))))

(defun visit (browser url &key (method :get) body content-type)
  "Request URL (by METHOD, sending BODY as CONTENT-TYPE), following redirects
with GETs, and make the result the current page.  Returns BROWSER; signals
an error after ten redirects."
  (loop repeat 10
        do (multiple-value-bind (status headers html)
               (raw-request browser method url :body body :content-type content-type)
             (cond ((= status 302)
                    (setf url (response-header headers :location)
                          method :get body nil content-type nil))
                   (t
                    (setf (browser-url browser) url
                          (browser-status browser) status
                          (browser-html browser) html
                          (browser-fields browser) (initial-fields html))
                    (return browser))))
        finally (error "Too many redirects")))

;;; Reading the page

(defun attributes (tag)
  "The attributes in TAG, the part of an HTML start tag after its name, as an
alist of lower-cased name → unescaped value, NIL for a bare attribute."
  (let ((result '()))
    (cl-ppcre:do-register-groups (name value) ("([a-zA-Z_:-]+)(?:=\"([^\"]*)\")?" tag)
      (push (cons (string-downcase name) (and value (unescape value))) result))
    (nreverse result)))

(defun attr (attributes name)
  "The value of attribute NAME in ATTRIBUTES."
  (rest (assoc name attributes :test #'string=)))

(defun unescape (string)
  "STRING with the HTML escapes littoral writes undone."
  (cl-ppcre:regex-replace-all
   "&(lt|gt|amp|quot|#39);" string
   (lambda (match register)
     (declare (ignore match))
     (cond ((string= register "lt") "<") ((string= register "gt") ">")
           ((string= register "amp") "&") ((string= register "quot") "\"") (t "'")))
   :simple-calls t))

(defun strip-tags (html)
  "HTML with its tags removed and escapes undone.  Scripts and style sheets
go whole, as they aren't text (and a < in them isn't a tag)."
  (unescape (cl-ppcre:regex-replace-all
             "<[^>]*>"
             (cl-ppcre:regex-replace-all "(?is)<(script|style)\\b[^>]*>.*?</\\1>" html "")
             "")))

(defun page-text (browser)
  "The current page's text without markup."
  (strip-tags (browser-html browser)))

(defparameter *separate-tags*
  '("address" "article" "aside" "blockquote" "br" "button" "caption" "dd" "details" "div" "dl" "dt"
    "fieldset" "figcaption" "figure" "footer" "form" "h1" "h2" "h3" "h4" "h5" "h6" "header" "hr"
    "input" "label" "legend" "li" "main" "nav" "ol" "option" "p" "pre" "section" "select" "summary"
    "table" "tbody" "td" "textarea" "tfoot" "th" "thead" "tr" "ul")
  "Tags a browser shows apart from the text around them: BODY-TEXT puts a
space where one opens or closes.")

(defun body-text (browser)
  "The text of the current page's body without markup, as a reader sees
it: a space where a block, cell or form control begins or ends, and each
run of whitespace made one space."
  (let* ((html (browser-html browser))
         (start (cl-ppcre:scan "<body[\\s>]" html))
         (body (if start (subseq html start) html))
         (spaced (cl-ppcre:regex-replace-all
                  (format nil "(?i)</?(?:~{~A~^|~})(?=[\\s/>])[^>]*>" *separate-tags*)
                  ;; Scripts and styles go first, whole, as STRIP-TAGS does.
                  (cl-ppcre:regex-replace-all "(?is)<(script|style)\\b[^>]*>.*?</\\1>" body "")
                  " \\& ")))
    (string-trim " " (cl-ppcre:regex-replace-all "\\s+" (strip-tags spaced) " "))))

(defun has-text-p (browser text)
  "True when the current page's text contains TEXT."
  (search text (page-text browser)))

(defun initial-fields (html)
  "The values the page's inputs, textareas and selects would submit."
  (let ((fields '()))
    (cl-ppcre:do-register-groups (tag) ("<input\\b([^>]*)>" html)
      (let* ((a (attributes tag)) (name (attr a "name")) (type (attr a "type")))
        (when (and name (not (member type '("submit" "button") :test #'equal)))
          (cond ((equal type "checkbox")
                 (when (assoc "checked" a :test #'string=)
                   (push (cons name (attr a "value")) fields)))
                ((equal type "radio")
                 (when (assoc "checked" a :test #'string=)
                   (push (cons name (attr a "value")) fields)))
                (t (push (cons name (or (attr a "value") "")) fields))))))
    (cl-ppcre:do-register-groups (tag content) ("<textarea\\b([^>]*)>(.*?)</textarea>" html)
      (let ((name (attr (attributes tag) "name")))
        (when name (push (cons name (unescape content)) fields))))
    (cl-ppcre:do-register-groups (tag options) ("(?s)<select\\b([^>]*)>(.*?)</select>" html)
      (let ((name (attr (attributes tag) "name"))
            (selected nil) (first nil))
        (cl-ppcre:do-register-groups (otag) ("<option\\b([^>]*)>" options)
          (let ((a (attributes otag)))
            (unless first (setf first (attr a "value")))
            (when (assoc "selected" a :test #'string=) (setf selected (attr a "value")))))
        (when name (push (cons name (or selected first "")) fields))))
    (nreverse fields)))

(defun find-link (browser text)
  "The href of the first link whose text contains TEXT."
  (cl-ppcre:do-register-groups (tag content) ("(?s)<a\\b([^>]*)>(.*?)</a>" (browser-html browser))
    (when (search text (strip-tags content))
      (return-from find-link (attr (attributes tag) "href"))))
  nil)

(defun click (browser text)
  "Follow the first link whose text contains TEXT; an error when there is none."
  (let ((href (find-link browser text)))
    (unless href (error "No link ~S on the page:~%~A" text (page-text browser)))
    (visit browser href)))

(defun find-links (browser text)
  "The hrefs of every link whose text is exactly TEXT, in page order."
  (let (hrefs)
    (cl-ppcre:do-register-groups (tag content) ("(?s)<a\\b([^>]*)>(.*?)</a>" (browser-html browser))
      (when (string= text (string-trim " " (strip-tags content)))
        (push (attr (attributes tag) "href") hrefs)))
    (nreverse hrefs)))

(defun click-nth (browser text n)
  "Follow the Nth (from 0) link whose text is exactly TEXT."
  (let ((href (nth n (find-links browser text))))
    (unless href (error "No link ~S number ~D on the page:~%~A" text n (page-text browser)))
    (visit browser href)))

(defun element-name (browser id)
  "The name of the field with DOM id ID or, failing that, the field whose
aria-label is ID (a brush's :LABEL); an error when there is none."
  (let ((labelled nil))
    (cl-ppcre:do-register-groups (tag) ("<(?:input|textarea|select)\\b([^>]*)>" (browser-html browser))
      (let ((a (attributes tag)))
        (when (equal (attr a "id") id)
          (return-from element-name (attr a "name")))
        (when (and (null labelled) (equal (unescape (or (attr a "aria-label") "")) id))
          (setf labelled (attr a "name")))))
    (or labelled (error "No field with id or label ~S" id))))

(defun fill-in (browser id value)
  "Type VALUE into the field with DOM id ID, or else with label ID (see
ELEMENT-NAME); an error when there is none.
Returns BROWSER."
  (let ((name (element-name browser id)))
    (setf (browser-fields browser)
          (acons name value (remove name (browser-fields browser) :key #'car :test #'string=)))
    browser))

(defun set-checkbox (browser index checked)
  "Check (CHECKED true) or uncheck the INDEXth checkbox on the page,
counting from 0."
  (let ((names '()))
    (cl-ppcre:do-register-groups (tag) ("<input\\b([^>]*)>" (browser-html browser))
      (let ((a (attributes tag)))
        (when (equal (attr a "type") "checkbox") (push (attr a "name") names))))
    (let ((name (nth index (nreverse names))))
      ;; Its hidden twin is posted as "off" already; append the box last.
      (setf (browser-fields browser)
            (append (remove-if (lambda (f) (and (string= (first f) name) (string= (rest f) "on")))
                               (browser-fields browser))
                    (when checked (list (cons name "on")))))
      browser)))

(defun select-option (browser id label)
  "Choose the option labelled exactly LABEL in the select with DOM id ID,
or else with label ID (see ELEMENT-NAME); an error when there is none.
Returns BROWSER."
  (let ((labelled nil))
    (cl-ppcre:do-register-groups (tag options) ("(?s)<select\\b([^>]*)>(.*?)</select>" (browser-html browser))
      (let ((a (attributes tag)))
        (cond ((equal (attr a "id") id) (setf labelled (cons a options)) (return))
              ((and (null labelled) (equal (unescape (or (attr a "aria-label") "")) id))
               (setf labelled (cons a options))))))
    (when labelled
      (destructuring-bind (a . options) labelled
        (cl-ppcre:do-register-groups (otag text) ("<option\\b([^>]*)>(.*?)</option>" options)
          (when (string= (strip-tags text) label)
            (let ((name (attr a "name")))
              (setf (browser-fields browser)
                    (acons name (attr (attributes otag) "value")
                           (remove name (browser-fields browser) :key #'car :test #'string=)))
              (return-from select-option browser)))))))
  (error "No option ~S in ~S" label id))

(defun choose-radio (browser label)
  "Choose the radio button labelled exactly LABEL (the text of its
<label>), as clicking it would.  An error when there is none.  Returns
BROWSER."
  (cl-ppcre:do-register-groups (tag text)
      ("(?s)<label\\b[^>]*>\\s*<input\\b([^>]*\\btype=\"radio\"[^>]*)>(.*?)</label>" (browser-html browser))
    (when (string= (string-trim " " (strip-tags text)) label)
      (let* ((a (attributes tag)) (name (attr a "name")))
        (setf (browser-fields browser)
              (acons name (attr a "value") (remove name (browser-fields browser) :key #'car :test #'string=)))
        (return-from choose-radio browser))))
  (error "No radio button labelled ~S" label))

(defun form-action (browser)
  "The action URL of the first form on the page."
  (cl-ppcre:do-register-groups (tag) ("<form\\b([^>]*)>" (browser-html browser))
    (return-from form-action (attr (attributes tag) "action")))
  (error "No form on the page"))

(defun encode-fields (fields)
  "FIELDS, an alist, as a URL-encoded form body."
  (format nil "~{~A~^&~}"
          (mapcar (lambda (f) (format nil "~A=~A" (quri:url-encode (first f)) (quri:url-encode (or (rest f) ""))))
                  fields)))

(defun attach-file (browser id filename content-type contents)
  "Choose a file for the file input with DOM id ID.  CONTENTS is a string
or a vector of octets."
  (let ((name (element-name browser id)))
    (push (list name filename content-type
                (if (stringp contents)
                    (flexi-streams:string-to-octets contents :external-format :utf-8)
                    (coerce contents '(vector (unsigned-byte 8)))))
          (browser-files browser))
    browser))

(defun multipart-body (fields files boundary)
  "FIELDS and FILES encoded as multipart/form-data, as octets."
  (let ((out (flexi-streams:make-in-memory-output-stream)))
    (flet ((emit (string)
             (write-sequence (flexi-streams:string-to-octets string :external-format :utf-8) out)))
      (loop for (name . value) in fields
            do (emit (format nil "--~A~C~CContent-Disposition: form-data; name=\"~A\"~C~C~C~C~A~C~C"
                             boundary #\Return #\Newline name #\Return #\Newline #\Return #\Newline
                             (or value "") #\Return #\Newline)))
      (loop for (name filename type octets) in files
            do (emit (format nil "--~A~C~CContent-Disposition: form-data; name=\"~A\"; ~
filename=\"~A\"~C~CContent-Type: ~A~C~C~C~C"
                             boundary #\Return #\Newline name filename #\Return #\Newline
                             type #\Return #\Newline #\Return #\Newline))
               (write-sequence octets out)
               (emit (format nil "~C~C" #\Return #\Newline)))
      (emit (format nil "--~A--~C~C" boundary #\Return #\Newline)))
    (flexi-streams:get-output-stream-sequence out)))

(defun press (browser text)
  "Submit the form with the first button whose label contains TEXT, sending
BROWSER-FIELDS, and BROWSER-FILES as multipart when there are any; an error
when there is no such button."
  (let ((name nil))
    (cl-ppcre:do-register-groups (tag content) ("(?s)<button\\b([^>]*)>(.*?)</button>" (browser-html browser))
      (when (and (null name) (search text (strip-tags content)))
        (setf name (or (attr (attributes tag) "name") ""))))
    (unless name (error "No button ~S on the page:~%~A" text (page-text browser)))
    (let ((fields (append (browser-fields browser)
                          (unless (string= name "") (list (cons name "1")))))
          (files (shiftf (browser-files browser) '())))
      (if files
          (visit browser (form-action browser)
                 :method :post
                 :body (multipart-body fields files "littoral-test-boundary")
                 :content-type "multipart/form-data; boundary=littoral-test-boundary")
          (visit browser (form-action browser) :method :post :body (encode-fields fields))))))

(defun back-to (browser url)
  "Return to an earlier page, as the back button (with no cache) would."
  (visit browser url))

(defun ajax-request (browser callback targets &key fields)
  "Post an AJAX request the way littoral.js does, running the callback with
id CALLBACK (none when NIL or \"\") and re-rendering TARGETS, a string of
component ids, as AJAX-SPECS gives them.  FIELDS, an alist, is posted too.
Returns the JSON text and the status."
  (let ((action (cl-ppcre:register-groups-bind (url) ("data-lt-action=\"([^\"]*)\"" (browser-html browser))
                  (unescape url))))
    (multiple-value-bind (status headers body)
        (raw-request browser :post action
                     :body (encode-fields (append fields
                                                  (list (cons "_lt_ajax" "1")
                                                        (cons "_lt_update" targets))
                                                  (when (and callback (string/= callback ""))
                                                    (list (cons callback "1"))))))
      (declare (ignore headers))
      (values body status))))

(defun ajax-specs (browser attribute)
  "The (CALLBACK . TARGETS) of each element with data-lt-ATTRIBUTE, in page
order, for AJAX-REQUEST.  ATTRIBUTE is the event, such as \"on-click\"."
  (let ((result '()))
    (cl-ppcre:do-register-groups (spec) ((format nil "data-lt-~A=\"([^\"]*)\"" attribute) (browser-html browser))
      (let* ((spec (unescape spec)) (semi (position #\; spec)))
        (push (cons (subseq spec 0 semi) (subseq spec (1+ semi))) result)))
    (nreverse result)))

(defmacro with-fresh-applications ((&rest registrations) &body body)
  "Run BODY with only the applications REGISTRATIONS names registered, each
registration a list of REGISTER-APPLICATION's arguments."
  `(let ((littoral::*applications* (make-hash-table :test 'equal)))
     ,@(mapcar (lambda (r) `(register-application ,@r)) registrations)
     ,@body))

;;; Server push

(defclass sink ()
  ((chunks :initform '() :accessor sink-chunks)
   (lock :initform (sb-thread:make-mutex) :reader sink-lock))
  (:documentation "Collects what an event stream writes."))

(defun sink-text (sink)
  "Everything written to SINK so far."
  (sb-thread:with-mutex ((sink-lock sink))
    (format nil "~{~A~}" (reverse (sink-chunks sink)))))

(defun open-stream (browser sink)
  "Open the current page's event stream in a thread, writing into SINK, and
wait (up to 10 seconds) until it is open: its first line, retry:, written.
From then on it is among the open streams, so PUBLISH reaches it and
CLOSE-EVENT-STREAMS closes it.  Returns the thread; an error when the page
has no stream."
  (let* ((url (cl-ppcre:register-groups-bind (u) ("data-lt-events=\"([^\"]*)\"" (browser-html browser))
                (unescape u)))
         (response (funcall (browser-app browser)
                            (make-env :get url :cookies (browser-cookies browser) :extra-headers (browser-headers browser)))))
    (unless (functionp response)
      (error "~A did not open an event stream (status ~A)." url (first response)))
    (let ((thread (sb-thread:make-thread
                   (lambda ()
                     (funcall response
                              (lambda (head)
                                (declare (ignore head))
                                (lambda (chunk &key close)
                                  (declare (ignore close))
                                  (when chunk
                                    (sb-thread:with-mutex ((sink-lock sink))
                                      (push chunk (sink-chunks sink))))))))
                   :name "littoral.test event stream")))
      (wait-for (lambda () (search "retry:" (sink-text sink))))
      thread)))

(defun wait-for (predicate &optional (seconds 10))
  "Poll PREDICATE for up to SECONDS; true when it came true."
  (loop repeat (* seconds 20)
        when (funcall predicate) return t
        do (sleep 0.05)))
