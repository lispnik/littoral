;;;; browser.lisp — a fake browser driving the Lack app in-process

(in-package #:littoral/tests)

(defclass browser ()
  ((app :initarg :app :initform (make-lack-app) :reader browser-app)
   (url :initform nil :accessor browser-url)
   (status :initform nil :accessor browser-status)
   (html :initform "" :accessor browser-html)
   (cookies :initform '() :accessor browser-cookies)
   (fields :initform '() :accessor browser-fields
           :documentation "Alist of field name → value typed into the current page.")
   (files :initform '() :accessor browser-files
          :documentation "Alist of field name → (FILENAME CONTENT-TYPE OCTETS)."))
  (:documentation "A fake browser driving the Lack app in-process."))

(defun split-url (url)
  "URL's path and query string."
  (let ((q (position #\? url)))
    (if q (values (subseq url 0 q) (subseq url (1+ q))) (values url nil))))

(defun make-env (method url &key body cookies (content-type "application/x-www-form-urlencoded"))
  "A Lack environment for a METHOD request to URL."
  (multiple-value-bind (path query) (split-url url)
    (let ((headers (make-hash-table :test 'equal))
          (octets (if (stringp body)
                      (flexi-streams:string-to-octets body :external-format :utf-8)
                      body)))
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

(defun raw-request (browser method url &key body content-type)
  "One request, no redirects followed.  Returns status, headers, body string."
  (destructuring-bind (status headers body-parts)
      (funcall (browser-app browser)
               (apply #'make-env method url :body body :cookies (browser-cookies browser)
                      (when content-type (list :content-type content-type))))
    (let ((cookie (response-header headers :set-cookie)))
      (when cookie
        (let* ((pair (subseq cookie 0 (position #\; cookie)))
               (eq (position #\= pair)))
          (push (cons (subseq pair 0 eq) (subseq pair (1+ eq))) (browser-cookies browser)))))
    (values status headers (apply #'concatenate 'string body-parts))))

(defun visit (browser url &key (method :get) body content-type)
  "Request URL, following redirects, and make the result the current page."
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
  "The attributes in TAG, the inside of an HTML start tag, as an alist."
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
  "HTML with its tags removed and escapes undone."
  (unescape (cl-ppcre:regex-replace-all "<[^>]*>" html "")))

(defun page-text (browser)
  "The current page's text without markup."
  (strip-tags (browser-html browser)))

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
  "Follow the link whose text contains TEXT."
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
  "The name of the field with DOM id ID."
  (cl-ppcre:do-register-groups (tag) ("<(?:input|textarea|select)\\b([^>]*)>" (browser-html browser))
    (let ((a (attributes tag)))
      (when (equal (attr a "id") id)
        (return-from element-name (attr a "name")))))
  (error "No field with id ~S" id))

(defun fill-in (browser id value)
  "Type VALUE into the field with DOM id ID."
  (let ((name (element-name browser id)))
    (setf (browser-fields browser)
          (acons name value (remove name (browser-fields browser) :key #'car :test #'string=)))
    browser))

(defun set-checkbox (browser index checked)
  "Check or uncheck the INDEXth checkbox on the page."
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
  "Choose the option labelled LABEL in the select with DOM id ID."
  (cl-ppcre:do-register-groups (tag options) ("(?s)<select\\b([^>]*)>(.*?)</select>" (browser-html browser))
    (when (equal (attr (attributes tag) "id") id)
      (cl-ppcre:do-register-groups (otag text) ("<option\\b([^>]*)>(.*?)</option>" options)
        (when (string= (strip-tags text) label)
          (return-from select-option
            (fill-in browser id (attr (attributes otag) "value")))))))
  (error "No option ~S in ~S" label id))

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
  "Choose a file for the file input with DOM id ID.  CONTENTS is a string."
  (let ((name (element-name browser id)))
    (push (list name filename content-type
                (flexi-streams:string-to-octets contents :external-format :utf-8))
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
  "Submit the form with the button whose label contains TEXT."
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
  "Post an AJAX request the way littoral.js does; returns the JSON text."
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
  "The (CALLBACK . TARGETS) of each element with data-lt-ATTRIBUTE."
  (let ((result '()))
    (cl-ppcre:do-register-groups (spec) ((format nil "data-lt-~A=\"([^\"]*)\"" attribute) (browser-html browser))
      (let* ((spec (unescape spec)) (semi (position #\; spec)))
        (push (cons (subseq spec 0 semi) (subseq spec (1+ semi))) result)))
    (nreverse result)))

(defmacro with-fresh-applications ((&rest registrations) &body body)
  "Run BODY with only the given applications registered."
  `(let ((littoral::*applications* (make-hash-table :test 'equal)))
     ,@(mapcar (lambda (r) `(register-application ,@r)) registrations)
     ,@body))
