;;;; storage.lisp — files people upload, on disk or in S3, with thumbnails
;;;;
;;;;   (setf littoral.storage:*storage*
;;;;         (littoral.storage:make-disk-storage #p"/var/lib/app/files/"))   ; served at /files/
;;;;   ;; or (make-s3-storage :bucket "app-files" :region "eu-west-1"
;;;;   ;;                     :access-key … :secret-key …)
;;;;
;;;;   (define-description photo
;;;;     ((caption :required t)
;;;;      (picture :type :image :required t)        ; an upload, with a thumbnail
;;;;      (document :type :file :max-size 5000000)))
;;;;
;;;; Editors get a file chooser; viewers and reports a thumbnail or a link.
;;;; A stored file is a STORED-FILE: its key, the name it was uploaded with,
;;;; its type and size, and its thumbnail's key.  Types come from the bytes,
;;;; not from what the browser said.  Only PNG, JPEG, GIF and WebP are ever
;;;; shown in the page; anything else is served as an attachment, so an
;;;; uploaded HTML or SVG file can't run script on this site.  With
;;;; :PRIVATE T, files are served only through signed URLs that expire.

(defpackage #:littoral.storage
  (:use #:cl #:littoral #:littoral.html)
  (:documentation "Load with `(asdf:load-system :littoral/storage)`.  Stores uploaded files on
disk or in S3, with thumbnails, and gives descriptions the field types :file
and :image.")
  (:export #:storage #:*storage* #:disk-storage #:make-disk-storage #:s3-storage #:make-s3-storage
           #:storage-put #:storage-get #:storage-delete #:storage-url #:ensure-bucket
           #:store-upload #:store-octets #:delete-stored-file
           #:stored-file #:stored-file-key #:stored-file-name #:stored-file-type #:stored-file-size
           #:stored-file-thumbnail #:stored-file-url #:stored-file-thumbnail-url
           #:file-field #:image-field #:*thumbnail-size* #:*max-image-pixels* #:sniff-type #:*signing-key*))

(in-package #:littoral.storage)

;;; Where files go

(defclass storage ()
  ((private :initarg :private :initform nil :reader storage-private-p
            :documentation "When true, files are served only through signed URLs that expire."))
  (:documentation "Somewhere to keep files.  A subclass specialises STORAGE-PUT, STORAGE-GET,
STORAGE-DELETE and STORAGE-URL."))

(defgeneric storage-put (storage key octets content-type)
  (:documentation "Keep OCTETS under KEY, with CONTENT-TYPE.  Returns KEY."))

(defgeneric storage-get (storage key)
  (:documentation "The octets kept under KEY and their content type, or NIL."))

(defgeneric storage-delete (storage key)
  (:documentation "Forget what is kept under KEY."))

(defgeneric storage-url (storage key &key filename expires)
  (:documentation "A URL the browser can fetch KEY's file from.  FILENAME
names the download; EXPIRES (seconds) limits how long a private URL works."))

(defvar *storage* nil
  "Where description file fields keep their files, unless a field names its own.")

;;; What a file is

(defun sniff-type (octets)
  "The type OCTETS' first bytes say they are, whatever the browser said:
\"image/png\", \"image/jpeg\", \"image/gif\", \"image/webp\",
\"application/pdf\" or \"application/zip\", else
\"application/octet-stream\"."
  (flet ((starts (&rest bytes)
           (and (>= (length octets) (length bytes))
                (every (lambda (b i) (or (null b) (= b (aref octets i)))) bytes
                       (loop for i below (length bytes) collect i)))))
    (cond ((starts #x89 #x50 #x4E #x47 #x0D #x0A #x1A #x0A) "image/png")
          ((starts #xFF #xD8 #xFF) "image/jpeg")
          ((starts #x47 #x49 #x46 #x38) "image/gif")
          ((and (starts #x52 #x49 #x46 #x46) (>= (length octets) 12)
                (equalp (subseq octets 8 12) #(#x57 #x45 #x42 #x50)))
           "image/webp")
          ((starts #x25 #x50 #x44 #x46 #x2D) "application/pdf")
          ((starts #x50 #x4B #x03 #x04) "application/zip")
          (t "application/octet-stream"))))

(defparameter *inline-types* '("image/png" "image/jpeg" "image/gif" "image/webp")
  "Types shown in the page; anything else is downloaded, never rendered here.")

(defun extension-for (type)
  (or (cdr (assoc type '(("image/png" . "png") ("image/jpeg" . "jpg") ("image/gif" . "gif")
                         ("image/webp" . "webp") ("application/pdf" . "pdf") ("application/zip" . "zip"))
                  :test #'string=))
      "bin"))

(defstruct (stored-file (:constructor make-stored-file (key name type size thumbnail)))
  "A file kept in storage: KEY, the NAME it was uploaded with, its TYPE (as
sniffed), its SIZE in bytes, and its THUMBNAIL's key or NIL."
  key name type size thumbnail)

(setf (documentation 'stored-file-key 'function) "The key FILE, a STORED-FILE, is kept under in its storage."
      (documentation 'stored-file-name 'function) "The name FILE, a STORED-FILE, was uploaded with, without directories."
      (documentation 'stored-file-type 'function) "FILE's content type, as SNIFF-TYPE found it from its bytes."
      (documentation 'stored-file-size 'function) "FILE's size in bytes."
      (documentation 'stored-file-thumbnail 'function) "The key of FILE's thumbnail, or NIL when it has none.")

(defun clean-name (name)
  "NAME without directories or characters that would trouble a header."
  (let* ((base (subseq name (1+ (or (position-if (lambda (c) (member c '(#\/ #\\))) name :from-end t) -1))))
         (clean (remove-if (lambda (c) (or (char< c #\Space) (member c '(#\" #\Tab #\;)))) base)))
    (if (string= clean "") "file" (subseq clean 0 (min 200 (length clean))))))

(defun encode-stored-file (file)
  "FILE as one line of text, for a database column."
  (and file
       (format nil "~A	~A	~A	~D	~@[~A~]" (stored-file-key file) (stored-file-name file)
               (stored-file-type file) (stored-file-size file) (stored-file-thumbnail file))))

(defun decode-stored-file (text)
  (and text (stringp text) (plusp (length text))
       (char/= (char text 0) #\!)          ; an upload FILE-FIELD refused
       (destructuring-bind (key &optional (name "file") (type "application/octet-stream") (size "0") thumbnail)
           (cl-ppcre:split "\\t" text :limit 5)
         (make-stored-file key name type (or (parse-integer size :junk-allowed t) 0)
                           (and thumbnail (plusp (length thumbnail)) thumbnail)))))

;;; Images and thumbnails

(defvar *thumbnail-size* 240 "The longest side of a thumbnail, in pixels.")
(defvar *max-image-pixels* (* 50 1000 1000)
  "Images with more pixels than this get no thumbnail: decoding one could
take all the memory (a small file can claim enormous dimensions).")

(defun be16 (octets i) (logior (ash (aref octets i) 8) (aref octets (1+ i))))
(defun be32 (octets i) (logior (ash (be16 octets i) 16) (be16 octets (+ i 2))))

(defun image-dimensions (octets type)
  "WIDTH and HEIGHT from the image's header, without decoding it; NIL if unknown."
  (ignore-errors
   (cond ((string= type "image/png") (values (be32 octets 16) (be32 octets 20)))
         ((string= type "image/gif")
          (values (logior (aref octets 6) (ash (aref octets 7) 8))
                  (logior (aref octets 8) (ash (aref octets 9) 8))))
         ((string= type "image/jpeg")
          ;; Walk the markers to the frame header (SOF0–SOF15, not DHT/JPG/DAC).
          (loop with i = 2
                while (< (+ i 9) (length octets))
                do (unless (= (aref octets i) #xFF) (return nil))
                   (let ((marker (aref octets (1+ i))))
                     (cond ((and (<= #xC0 marker #xCF) (not (member marker '(#xC4 #xC8 #xCC))))
                            (return (values (be16 octets (+ i 7)) (be16 octets (+ i 5)))))
                           ((member marker '(#xD8 #x01)) (incf i 2))
                           ((<= #xD0 marker #xD7) (incf i 2))
                           (t (incf i (+ 2 (be16 octets (+ i 2)))))))))
         (t nil))))

(defun make-thumbnail (octets type)
  "A JPEG thumbnail of the image OCTETS, at most *THUMBNAIL-SIZE* on its
longer side, or NIL when it can't or shouldn't be made."
  (multiple-value-bind (width height) (image-dimensions octets type)
    (when (and width height (plusp width) (plusp height) (<= (* width height) *max-image-pixels*)
               (member type '("image/png" "image/jpeg" "image/gif") :test #'string=))
      (ignore-errors
       (let* ((image (flexi-streams:with-input-from-sequence (in octets)
                       (opticl:read-image-stream in (intern (string-upcase (extension-for type)) :keyword))))
              (rgb (opticl:coerce-image image 'opticl:8-bit-rgb-image))
              (scale (min 1 (/ *thumbnail-size* (max width height))))
              (small (opticl:resize-image rgb (max 1 (round (* height scale))) (max 1 (round (* width scale)))
                                          :interpolate :bilinear)))
         (flexi-streams:with-output-to-sequence (out)
           (opticl:write-jpeg-stream out small)))))))

;;; Storing

(defun new-key (type)
  (format nil "~A.~A" (littoral::random-key 24) (extension-for type)))

(defun store-octets (octets name &key (storage *storage*) thumbnail)
  "Keep OCTETS, uploaded as NAME, in STORAGE under a new random key; the
STORED-FILE.  Its name is NAME without directories, and its type is what
SNIFF-TYPE says.  With THUMBNAIL, a PNG, JPEG or GIF image gets a JPEG
thumbnail too (see *THUMBNAIL-SIZE* and *MAX-IMAGE-PIXELS*).  Signals an
error when STORAGE is NIL."
  (unless storage (error "No storage: set LITTORAL.STORAGE:*STORAGE*."))
  (let* ((type (sniff-type octets))
         (key (new-key type))
         (small (and thumbnail (make-thumbnail octets type)))
         (thumbnail-key (and small (format nil "~A-thumb.jpg" (subseq key 0 (position #\. key))))))
    (storage-put storage key octets type)
    (when small (storage-put storage thumbnail-key small "image/jpeg"))
    (make-stored-file key (clean-name name) type (length octets) thumbnail-key)))

(defun store-upload (upload &rest options &key storage thumbnail)
  "Keep UPLOAD, an UPLOADED-FILE from a FILE-INPUT, under the name it was
uploaded with; the STORED-FILE.  STORAGE and THUMBNAIL are as for
STORE-OCTETS."
  (declare (ignore storage thumbnail))
  (apply #'store-octets (file-contents upload) (file-name upload) options))

(defun delete-stored-file (file &optional (storage *storage*))
  "Delete FILE, a STORED-FILE, and its thumbnail from STORAGE."
  (storage-delete storage (stored-file-key file))
  (when (stored-file-thumbnail file) (storage-delete storage (stored-file-thumbnail file))))

(defun stored-file-url (file &key (storage *storage*) (expires 3600))
  "A URL the browser can fetch FILE from in STORAGE, downloading under the
name it was uploaded with.  A private storage's URL works for EXPIRES
seconds."
  (storage-url storage (stored-file-key file) :filename (stored-file-name file) :expires expires))

(defun stored-file-thumbnail-url (file &key (storage *storage*) (expires 3600))
  "A URL the browser can fetch FILE's thumbnail from in STORAGE, or NIL when
it has none.  A private storage's URL works for EXPIRES seconds."
  (and (stored-file-thumbnail file)
       (storage-url storage (stored-file-thumbnail file) :expires expires)))

;;; Signed URLs, for private files

(defvar *signing-key* (ironclad:random-data 32)
  "The key signing private file URLs.  Random per process unless set: set it,
from a secret, to share signed URLs between processes or across restarts.")

(defun signature (key expires)
  (subseq (ironclad:byte-array-to-hex-string
           (ironclad:hmac-digest
            (let ((mac (ironclad:make-hmac *signing-key* :sha256)))
              (ironclad:update-hmac mac (sb-ext:string-to-octets (format nil "~A|~D" key expires)
                                                                :external-format :utf-8))
              mac)))
          0 32))

(defun signature-valid-p (key expires signature)
  (and expires signature
       (let ((expires (parse-integer expires :junk-allowed t)))
         (and expires (> expires (get-universal-time))
              (= (length signature) 32)
              (ironclad:constant-time-equal (sb-ext:string-to-octets (signature key expires))
                                            (sb-ext:string-to-octets signature))))))

;;; On disk, served by Littoral

(defclass disk-storage (storage)
  ((directory :initarg :directory :reader storage-directory)
   (prefix :initarg :prefix :reader storage-prefix
           :documentation "The path files are served at, such as \"/files/\"."))
  (:documentation "Files in a directory, served by Littoral under PREFIX."))

(defun safe-key-p (key)
  (and (stringp key) (cl-ppcre:scan "^[A-Za-z0-9_-]+(-thumb)?\\.[a-z0-9]+$" key)))

(defun key-path (storage key)
  (unless (safe-key-p key) (error "Not a storage key: ~S" key))
  ;; Two levels of directories, so no directory grows too large.
  (merge-pathnames (format nil "~A/~A/~A" (subseq key 0 2) (subseq key 2 4) key)
                   (storage-directory storage)))

(defmethod storage-put ((storage disk-storage) key octets content-type)
  (declare (ignore content-type))       ; the key's extension says it
  (let ((path (key-path storage key)))
    (ensure-directories-exist path)
    (with-open-file (out path :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
      (write-sequence octets out))
    key))

(defmethod storage-get ((storage disk-storage) key)
  (let ((path (and (safe-key-p key) (key-path storage key))))
    (when (and path (probe-file path))
      (with-open-file (in path :element-type '(unsigned-byte 8))
        (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
          (read-sequence octets in)
          (values octets (sniff-type octets)))))))

(defmethod storage-delete ((storage disk-storage) key)
  (let ((path (and (safe-key-p key) (key-path storage key))))
    (when (and path (probe-file path)) (delete-file path))))

(defmethod storage-url ((storage disk-storage) key &key filename (expires 3600))
  (let ((base (url-for (format nil "~A~A" (storage-prefix storage) key))))
    (let ((query (append (when filename (list (cons "name" filename)))
                         (when (storage-private-p storage)
                           (let ((until (+ (get-universal-time) expires)))
                             (list (cons "e" (princ-to-string until)) (cons "s" (signature key until))))))))
      (if query
          (format nil "~A?~A" base (quri:url-encode-params query))
          base))))

(defun file-response (octets type &key filename)
  "Serve OCTETS: images in the page, anything else as a download, and never
as something that runs."
  (let ((inline (member type *inline-types* :test #'string=)))
    (list 200 (list :content-type (if inline type "application/octet-stream")
                    :content-length (length octets)
                    :content-disposition (format nil "~:[attachment~;inline~]~@[; filename=\"~A\"~]"
                                                 inline (and filename (clean-name filename)))
                    :cache-control "private, max-age=31536000, immutable"
                    :x-content-type-options "nosniff"
                    :content-security-policy "default-src 'none'; sandbox"
                    :referrer-policy "no-referrer")
          octets)))

(defun serve-stored-file (storage rest)
  (let* ((key rest)
         (request littoral:*request*)
         (expires (littoral:request-parameter "e" request))
         (sig (littoral:request-parameter "s" request)))
    (multiple-value-bind (octets type) (and (safe-key-p key)
                                            (or (not (storage-private-p storage))
                                                (signature-valid-p key expires sig))
                                            (storage-get storage key))
      (if octets
          (file-response octets type :filename (littoral:request-parameter "name" request))
          (list 404 (list :content-type "text/plain") (list "Not found."))))))

(defun make-disk-storage (directory &key (prefix "/files/") private)
  "A DISK-STORAGE keeping files under DIRECTORY (created if need be) and
serving them at PREFIX, through MOUNT-HANDLER (UNMOUNT-HANDLER stops it).
With PRIVATE, only signed URLs (STORAGE-URL) serve them, until they expire;
the signing key is random per process."
  (let ((storage (make-instance 'disk-storage :directory (uiop:ensure-directory-pathname directory)
                                              :prefix prefix :private private)))
    (ensure-directories-exist (storage-directory storage))
    (mount-handler prefix (lambda (rest) (serve-stored-file storage rest)))
    storage))

;;; In S3, or anything that speaks its API (MinIO, R2, Spaces…)

(defclass s3-storage (storage)
  ((bucket :initarg :bucket :reader s3-bucket)
   (region :initarg :region :reader s3-region)
   (endpoint :initarg :endpoint :reader s3-endpoint
             :documentation "https://s3.REGION.amazonaws.com, or another service's address.")
   (access-key :initarg :access-key :reader s3-access-key)
   (secret-key :initarg :secret-key :reader s3-secret-key)
   (key-prefix :initarg :key-prefix :reader s3-key-prefix)
   (path-style :initarg :path-style :reader s3-path-style-p
               :documentation "True to address the bucket in the path (MinIO and most
others); NIL when ENDPOINT already names the bucket (virtual-hosted)."))
  (:documentation "Files in an S3 bucket, addressed path-style, signed with AWS Signature V4.
Unless the bucket is public, browsers fetch them through presigned URLs."))

(defun make-s3-storage (&key bucket (region "us-east-1") endpoint access-key secret-key (key-prefix "")
                          (private t) (path-style t))
  "An S3-STORAGE keeping files in BUCKET, with ACCESS-KEY and SECRET-KEY.
ENDPOINT defaults to AWS's for REGION; give it for MinIO or another service,
with PATH-STYLE NIL when it names the bucket itself.  KEY-PREFIX goes before
every key.  With PRIVATE (the default), URLs are presigned and expire;
otherwise they point straight at the bucket.  Contacts no server."
  (make-instance 's3-storage :bucket bucket :region region :access-key access-key :secret-key secret-key
                             :endpoint (string-right-trim "/" (or endpoint (format nil "https://s3.~A.amazonaws.com" region)))
                             :key-prefix key-prefix :private private :path-style path-style))

(defun uri-encode (string &key (slash t))
  "STRING percent-encoded as Signature V4 wants: all but A-Za-z0-9-_.~ (and /, with SLASH)."
  (with-output-to-string (out)
    (loop for byte across (sb-ext:string-to-octets string :external-format :utf-8)
          for char = (code-char byte)
          do (if (or (alphanumericp char) (find char "-_.~") (and slash (char= char #\/)))
                 (if (< byte 128) (write-char char out) (format out "%~2,'0X" byte))
                 (format out "%~2,'0X" byte)))))

(defun sha256-hex (octets)
  (ironclad:byte-array-to-hex-string (ironclad:digest-sequence :sha256 octets)))

(defun hmac (key data)
  (let ((mac (ironclad:make-hmac (if (stringp key) (sb-ext:string-to-octets key :external-format :utf-8) key)
                                 :sha256)))
    (ironclad:update-hmac mac (sb-ext:string-to-octets data :external-format :utf-8))
    (ironclad:hmac-digest mac)))

(defun amz-time (&optional (time (get-universal-time)))
  "TIME as Signature V4 writes it: 20130524T000000Z, and the date part."
  (multiple-value-bind (s m h day month year) (decode-universal-time time 0)
    (let ((stamp (format nil "~4,'0D~2,'0D~2,'0DT~2,'0D~2,'0D~2,'0DZ" year month day h m s)))
      (values stamp (subseq stamp 0 8)))))

(defun signing-key (secret date region)
  (hmac (hmac (hmac (hmac (concatenate 'string "AWS4" secret) date) region) "s3") "aws4_request"))

(defun sigv4-signature (secret region date amz-date canonical-request)
  (let ((string-to-sign (format nil "AWS4-HMAC-SHA256~%~A~%~A/~A/s3/aws4_request~%~A"
                                amz-date date region
                                (sha256-hex (sb-ext:string-to-octets canonical-request :external-format :utf-8)))))
    (ironclad:byte-array-to-hex-string (hmac (signing-key secret date region) string-to-sign))))

(defun canonical-query (parameters)
  (format nil "~{~A~^&~}"
          (mapcar (lambda (p) (format nil "~A=~A" (uri-encode (car p) :slash nil) (uri-encode (cdr p) :slash nil)))
                  (sort (copy-list parameters) #'string< :key #'car))))

(defun object-path (storage key)
  (if (s3-path-style-p storage)
      (format nil "/~A/~A~A" (s3-bucket storage) (s3-key-prefix storage) key)
      (format nil "/~A~A" (s3-key-prefix storage) key)))

(defun endpoint-host (storage)
  (let ((uri (quri:uri (s3-endpoint storage))))
    (format nil "~A~@[:~D~]" (quri:uri-host uri)
            (let ((port (quri:uri-port uri)))
              (and port (not (eql port (if (string= (quri:uri-scheme uri) "https") 443 80))) port)))))

(defun presign (storage method key &key (expires 3600) (time (get-universal-time)) extra-query)
  "A presigned URL for METHOD on KEY, good for EXPIRES seconds from TIME."
  (multiple-value-bind (amz-date date) (amz-time time)
    (let* ((path (object-path storage key))
           (query (append (list (cons "X-Amz-Algorithm" "AWS4-HMAC-SHA256")
                                (cons "X-Amz-Credential" (format nil "~A/~A/~A/s3/aws4_request"
                                                                 (s3-access-key storage) date (s3-region storage)))
                                (cons "X-Amz-Date" amz-date)
                                (cons "X-Amz-Expires" (princ-to-string expires))
                                (cons "X-Amz-SignedHeaders" "host"))
                          extra-query))
           (canonical (format nil "~A~%~A~%~A~%host:~A~%~%host~%UNSIGNED-PAYLOAD"
                              method (uri-encode path) (canonical-query query) (endpoint-host storage))))
      (format nil "~A~A?~A&X-Amz-Signature=~A" (s3-endpoint storage) (uri-encode path) (canonical-query query)
              (sigv4-signature (s3-secret-key storage) (s3-region storage) date amz-date canonical)))))

(defun s3-request (storage method key &key (content #()) content-type)
  "Send METHOD for KEY with CONTENT, signed in its headers; the body and status."
  (multiple-value-bind (amz-date date) (amz-time)
    (let* ((path (object-path storage key))
           (payload-hash (sha256-hex (coerce content '(vector (unsigned-byte 8)))))
           (headers (sort (append (list (cons "host" (endpoint-host storage))
                                        (cons "x-amz-content-sha256" payload-hash)
                                        (cons "x-amz-date" amz-date))
                                  (when content-type (list (cons "content-type" content-type))))
                          #'string< :key #'car))
           (signed (format nil "~{~A~^;~}" (mapcar #'car headers)))
           (canonical (format nil "~A~%~A~%~%~{~A~%~}~%~A~%~A"
                              method (uri-encode path)
                              (mapcar (lambda (h) (format nil "~A:~A" (car h) (cdr h))) headers)
                              signed payload-hash))
           (authorization (format nil "AWS4-HMAC-SHA256 Credential=~A/~A/~A/s3/aws4_request, SignedHeaders=~A, Signature=~A"
                                  (s3-access-key storage) date (s3-region storage) signed
                                  (sigv4-signature (s3-secret-key storage) (s3-region storage) date amz-date canonical))))
      (flet ((send ()
               (dex:request (format nil "~A~A" (s3-endpoint storage) (uri-encode path))
                            :method method
                            :headers (append (list (cons "Authorization" authorization))
                                             (remove "host" headers :key #'car :test #'string=))
                            :content (if (eq method :put) content nil)
                            :force-binary t :keep-alive nil)))
        ;; Reading or deleting what isn't there is NIL; any other failure,
        ;; a PUT's above all, signals.
        (if (eq method :put)
            (send)
            (handler-case (send)
              (dex:http-request-not-found () (values nil 404))))))))

(defun ensure-bucket (storage)
  "Create STORAGE's bucket unless it exists (for tests and first runs)."
  (handler-case
      (multiple-value-bind (amz-date date) (amz-time)
        (let* ((path (if (s3-path-style-p storage) (format nil "/~A" (s3-bucket storage)) "/"))
               (payload-hash (sha256-hex (make-array 0 :element-type '(unsigned-byte 8))))
               (headers (list (cons "host" (endpoint-host storage))
                              (cons "x-amz-content-sha256" payload-hash)
                              (cons "x-amz-date" amz-date)))
               (canonical (format nil "PUT~%~A~%~%~{~A~%~}~%host;x-amz-content-sha256;x-amz-date~%~A"
                                  path (mapcar (lambda (h) (format nil "~A:~A" (car h) (cdr h))) headers)
                                  payload-hash)))
          (dex:request (format nil "~A~A" (s3-endpoint storage) path)
                       :method :put
                       :headers (list (cons "Authorization"
                                            (format nil "AWS4-HMAC-SHA256 Credential=~A/~A/~A/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=~A"
                                                    (s3-access-key storage) date (s3-region storage)
                                                    (sigv4-signature (s3-secret-key storage) (s3-region storage)
                                                                     date amz-date canonical)))
                                      (cons "x-amz-content-sha256" payload-hash)
                                      (cons "x-amz-date" amz-date))
                       :content "" :keep-alive nil)
          t))
    ;; 409: it exists already.
    (dex:http-request-failed (e)
      (if (eql (dex:response-status e) 409) t (error e)))))

(defmethod storage-put ((storage s3-storage) key octets content-type)
  (s3-request storage :put key :content octets :content-type content-type)
  key)

(defmethod storage-get ((storage s3-storage) key)
  (multiple-value-bind (body status) (s3-request storage :get key)
    (when (and body (eql status 200))
      (values body (sniff-type body)))))

(defmethod storage-delete ((storage s3-storage) key)
  (s3-request storage :delete key))

(defmethod storage-url ((storage s3-storage) key &key filename (expires 3600))
  (let ((disposition (and filename
                          (list (cons "response-content-disposition"
                                      (format nil "attachment; filename=\"~A\"" (clean-name filename)))))))
    (if (storage-private-p storage)
        (presign storage "GET" key :expires expires :extra-query disposition)
        (format nil "~A~A" (s3-endpoint storage) (uri-encode (object-path storage key))))))

;;; Description fields

(defclass file-field (littoral::field)
  ((storage :initarg :storage :initform nil :reader field-storage
            :documentation "The STORAGE to keep files in; NIL for *STORAGE*.")
   (max-size :initarg :max-size :initform nil :reader field-max-size
             :documentation "The largest file accepted, in bytes, or NIL."))
  (:documentation "An uploaded file, kept in storage; the value is a STORED-FILE.  A
description's :TYPE :FILE, with the options :STORAGE and :MAX-SIZE."))

(defclass image-field (file-field) ()
  (:documentation "An uploaded PNG, JPEG, GIF or WebP image, kept with a thumbnail.  A
description's :TYPE :IMAGE, with the options of FILE-FIELD."))

(defun field-store (field) (or (field-storage field) *storage*))

(defmethod field-multipart-p ((field file-field)) t)

(defmethod littoral::format-field ((field file-field) value)
  (or (encode-stored-file value) ""))

(defmethod littoral::parse-field ((field file-field) string)
  (if (and (plusp (length string)) (char= (char string 0) #\!))
      (error 'littoral::field-error :message (subseq string 1))
      (decode-stored-file string)))

(defgeneric upload-problem (field size type)
  (:documentation "NIL when a file of SIZE bytes and TYPE suits FIELD, or a
sentence saying why not.")
  (:method ((field file-field) size type)
    (declare (ignore type))
    (and (field-max-size field) (> size (field-max-size field))
         (translate "~A is too large: at most ~:D bytes." (translate (littoral::field-label field))
                    (field-max-size field))))
  (:method ((field image-field) size type)
    (or (call-next-method)
        (and (not (member type *inline-types* :test #'string=))
             (translate "~A must be a PNG, JPEG, GIF or WebP image." (translate (littoral::field-label field)))))))

(defmethod littoral::check-field ((field file-field) value)
  (or (call-next-method)
      (and value (upload-problem field (stored-file-size value) (stored-file-type value)))))

(defmethod littoral::render-field-input ((field file-field) id text callback)
  (let ((current (decode-stored-file text)))
    (when current
      (div (:class "lt-file-current")
        (render-stored-file current field)
        (label ()
          (checkbox (:callback (lambda (remove) (when remove (funcall callback "")))))
          (text " ") (translate "Remove"))))
    (div (:class "lt-drop")
    (file-input (:id id
                 :accept (when (typep field 'image-field) "image/png,image/jpeg,image/gif,image/webp")
                 :callback (lambda (upload)
                             (let ((octets (file-contents upload)))
                               (when (plusp (length octets))
                                 ;; Refused uploads are never stored: the
                                 ;; field's text carries the problem instead.
                                 (let ((problem (upload-problem field (length octets) (sniff-type octets))))
                                   (funcall callback
                                            (if problem
                                                (format nil "!~A" problem)
                                                (encode-stored-file
                                                 (store-upload upload :storage (field-store field)
                                                                      :thumbnail (typep field 'image-field)))))))))))
      (span (:class "lt-drop-hint") (translate "or drop a file here"))
      (span (:class "lt-drop-files" :aria-live "polite")))))

(defun render-stored-file (file field)
  (let* ((storage (field-store field))
         (thumbnail (and storage (stored-file-thumbnail-url file :storage storage))))
    (if (and thumbnail (typep field 'image-field))
        (anchor (:href (stored-file-url file :storage storage) :class "lt-thumbnail")
          (img (:src thumbnail :alt (stored-file-name file) :loading "lazy")))
        (anchor (:href (stored-file-url file :storage storage))
          (text (format nil "~A (~A)" (stored-file-name file) (human-size (stored-file-size file))))))))

(defun human-size (bytes)
  (cond ((< bytes 1024) (format nil "~D B" bytes))
        ((< bytes (* 1024 1024)) (format nil "~,1F KB" (/ bytes 1024)))
        (t (format nil "~,1F MB" (/ bytes 1024 1024)))))

(defmethod littoral::render-field-value ((field file-field) value)
  (if value (render-stored-file value field) (text "")))

(push '(:file . file-field) littoral::*field-kinds*)
(push '(:image . image-field) littoral::*field-kinds*)

;;; In the database, a stored file is a line of text

(defmethod littoral.db:to-sql ((field file-field) value)
  (encode-stored-file value))

(defmethod littoral.db:from-sql ((field file-field) value)
  (and value (not (eq value :null)) (decode-stored-file value)))
