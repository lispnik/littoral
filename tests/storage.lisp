;;;; storage.lisp — files on disk and in S3, thumbnails, description fields

(in-package #:littoral/tests)

(def-suite storage :in littoral)
(in-suite storage)

(defun png-octets (width height)
  "A PNG of WIDTH × HEIGHT, made with opticl."
  (let ((image (opticl:make-8-bit-rgb-image height width :initial-element 200)))
    (flexi-streams:with-output-to-sequence (out) (opticl:write-png-stream out image))))

(defun scratch-storage (&rest options)
  (apply #'littoral.storage:make-disk-storage
         (merge-pathnames (format nil "littoral-storage-~36R/" (random (expt 36 8))) (uiop:temporary-directory))
         options))

(defun mounted-get (b url)
  "Fetch URL from the Lack app as the browser B would: status, headers, body."
  (destructuring-bind (status headers body)
      (funcall (browser-app b) (make-env :get url))
    (values status headers body)))

(test types-come-from-the-bytes
  (is (string= "image/png" (littoral.storage:sniff-type (png-octets 4 3))))
  (is (string= "image/jpeg" (littoral.storage:sniff-type (coerce #(#xFF #xD8 #xFF #xE0 0 0) '(vector (unsigned-byte 8))))))
  (is (string= "application/octet-stream"
               (littoral.storage:sniff-type (sb-ext:string-to-octets "<svg onload=alert(1)>"))))
  (multiple-value-bind (w h) (littoral.storage::image-dimensions (png-octets 37 21) "image/png")
    (is (= 37 w)) (is (= 21 h))))

(test thumbnails-and-bombs
  (let ((thumb (littoral.storage::make-thumbnail (png-octets 960 480) "image/png")))
    (is (string= "image/jpeg" (littoral.storage:sniff-type thumb)))
    (multiple-value-bind (w h) (littoral.storage::image-dimensions thumb "image/jpeg")
      (is (= 240 w)) (is (= 120 h))))
  ;; A small file claiming huge dimensions gets no thumbnail (and isn't decoded).
  (let ((bomb (png-octets 10 10)))
    (setf (subseq bomb 16 24) #(0 0 #x75 #x30 0 0 #x75 #x30))   ; 30000 × 30000
    (is (null (littoral.storage::make-thumbnail bomb "image/png")))))

(test files-on-disk-are-served-safely
  (let* ((storage (scratch-storage :prefix "/stored/"))
         (b (make-instance 'browser))
         (picture (littoral.storage:store-octets (png-octets 400 300) "holiday.png" :storage storage :thumbnail t))
         (page (littoral.storage:store-octets (sb-ext:string-to-octets "<html><script>alert(1)</script>")
                                              "evil.html" :storage storage)))
    (unwind-protect
         (let ((*base-path* ""))
           (is (string= "image/png" (littoral.storage:stored-file-type picture)))
           (is (littoral.storage:stored-file-thumbnail picture))
           (multiple-value-bind (status headers body) (mounted-get b (littoral.storage:stored-file-url picture :storage storage))
             (is (= 200 status))
             (is (string= "image/png" (getf headers :content-type)))
             (is (search "inline" (getf headers :content-disposition)))
             (is (search "sandbox" (getf headers :content-security-policy)))
             (is (= (littoral.storage:stored-file-size picture) (length body))))
           ;; HTML is never served as HTML.
           (multiple-value-bind (status headers) (mounted-get b (littoral.storage:stored-file-url page :storage storage))
             (is (= 200 status))
             (is (string= "application/octet-stream" (getf headers :content-type)))
             (is (search "attachment; filename=\"evil.html\"" (getf headers :content-disposition))))
           (is (= 404 (mounted-get b "/stored/../../etc/passwd")))
           (is (= 404 (mounted-get b "/stored/nonexistent.png")))
           (littoral.storage:delete-stored-file picture storage)
           (is (= 404 (mounted-get b (littoral.storage:stored-file-url picture :storage storage)))))
      (unmount-handler "/stored/")
      (uiop:delete-directory-tree (littoral.storage::storage-directory storage) :validate t :if-does-not-exist :ignore))))

(test private-files-need-a-signed-url
  (let* ((storage (scratch-storage :prefix "/private/" :private t))
         (b (make-instance 'browser))
         (file (littoral.storage:store-octets (png-octets 8 8) "secret.png" :storage storage)))
    (unwind-protect
         (let ((*base-path* ""))
           (let ((url (littoral.storage:stored-file-url file :storage storage)))
             (is (search "&s=" url))
             (is (= 200 (mounted-get b url))))
           (is (= 404 (mounted-get b (format nil "/private/~A" (littoral.storage:stored-file-key file)))))
           ;; A forged or expired signature doesn't do.
           (is (= 404 (mounted-get b (format nil "/private/~A?e=99999999999&s=~A" (littoral.storage:stored-file-key file)
                                             (make-string 32 :initial-element #\a)))))
           (let ((url (littoral.storage:stored-file-url file :storage storage :expires -10)))
             (is (= 404 (mounted-get b url)))))
      (unmount-handler "/private/")
      (uiop:delete-directory-tree (littoral.storage::storage-directory storage) :validate t :if-does-not-exist :ignore))))

;;; Through a description and its editor

(defclass album-photo ()
  ((caption :initarg :caption :initform nil)
   (picture :initarg :picture :initform nil)))

(define-description album-photo
  ((caption :required t)
   (picture :type :image :required t)))

(defclass album (component)
  ((photos :initform '() :accessor album-photos)))

(defmethod render ((self album))
  (anchor (:callback (lambda ()
                       (show self (make-editor (make-instance 'album-photo) :save-label "Upload")
                             :on-answer (lambda (photo) (when photo (push photo (album-photos self)))))))
    "Add a photo")
  (dolist (photo (album-photos self))
    (div (:class "photo")
      (p () (text (slot-value photo 'caption)))
      (littoral::render-field-value (littoral::find-field (find-description 'album-photo) 'picture)
                                    (slot-value photo 'picture)))))

(test uploading-through-an-image-field
  (let ((littoral.storage:*storage* (scratch-storage :prefix "/album-files/")))
    (unwind-protect
         (with-fresh-applications (("/album" 'album :mode :deployment))
           (let ((b (make-instance 'browser)))
             (visit b "/album")
             (click b "Add a photo")
             (is (search "multipart/form-data" (browser-html b)))
             ;; Not an image: refused.
             (fill-in b "caption" "Notes")
             (attach-file b "picture" "notes.txt" "text/plain" (sb-ext:string-to-octets "just text"))
             (press b "Upload")
             (is (has-text-p b "Picture must be a PNG, JPEG, GIF or WebP image."))
             ;; An image: kept, with a thumbnail shown.
             (attach-file b "picture" "beach.png" "image/png" (png-octets 600 400))
             (press b "Upload")
             (is (has-text-p b "Notes"))
             (is (search "-thumb.jpg" (browser-html b)))
             (is (search "/album-files/" (browser-html b)))))
      (unmount-handler "/album-files/")
      (uiop:delete-directory-tree (littoral.storage::storage-directory littoral.storage:*storage*)
                                  :validate t :if-does-not-exist :ignore))))

;;; S3

(test s3-presigned-urls-match-aws
  ;; The example in AWS's "Authenticating Requests: Using Query Parameters".
  (let ((storage (littoral.storage:make-s3-storage
                  :bucket "examplebucket" :region "us-east-1"
                  :endpoint "https://examplebucket.s3.amazonaws.com"
                  :access-key "AKIAIOSFODNN7EXAMPLE"
                  :secret-key "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                  :path-style nil)))           ; the bucket is in the host name
    (let ((url (littoral.storage::presign storage "GET" "test.txt" :expires 86400
                                                                  :time (encode-universal-time 0 0 0 24 5 2013 0))))
      (is (search "X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404" url) url))))

(test s3-storage-against-a-server
  ;; Runs when LITTORAL_TEST_S3 names an S3-compatible server (CI runs MinIO).
  (let ((endpoint (uiop:getenv "LITTORAL_TEST_S3")))
    (if (null endpoint)
        (skip "LITTORAL_TEST_S3 is not set")
        (let* ((storage (littoral.storage:make-s3-storage
                         :bucket (or (uiop:getenv "LITTORAL_TEST_S3_BUCKET") "littoral-test")
                         :endpoint endpoint
                         :access-key (or (uiop:getenv "LITTORAL_TEST_S3_KEY") "minioadmin")
                         :secret-key (or (uiop:getenv "LITTORAL_TEST_S3_SECRET") "minioadmin")))
               (file (littoral.storage:store-octets (png-octets 300 200) "s3.png" :storage storage :thumbnail t)))
          (multiple-value-bind (octets type) (littoral.storage:storage-get storage (littoral.storage:stored-file-key file))
            (is (string= "image/png" type))
            (is (= (littoral.storage:stored-file-size file) (length octets))))
          ;; The presigned URL works from outside.
          (multiple-value-bind (body status) (dex:get (littoral.storage:stored-file-url file :storage storage)
                                                      :force-binary t)
            (is (= 200 status))
            (is (= (littoral.storage:stored-file-size file) (length body))))
          (littoral.storage:delete-stored-file file storage)
          (is (null (littoral.storage:storage-get storage (littoral.storage:stored-file-key file))))))))

(test the-gallery-example
  (let ((dir (merge-pathnames (format nil "littoral-gallery-test-~36R/" (random (expt 36 8))) (uiop:temporary-directory)))
        (previous littoral.storage:*storage*))
    (unwind-protect
         (with-fresh-applications ()
           (littoral-gallery:register :directory dir)
           (let ((b (make-instance 'browser)))
             (visit b "/examples/gallery")
             (is (has-text-p b "No photos yet."))
             (click b "Add a photo")
             (fill-in b "caption" "Sunset")
             (attach-file b "picture" "sunset.png" "image/png" (png-octets 800 500))
             (attach-file b "attachment" "notes.html" "text/html" "<script>alert(1)</script>")
             (press b "Upload")
             (is (has-text-p b "Uploaded."))
             (is (has-text-p b "Sunset"))
             (is (has-text-p b "notes.html"))
             (let ((thumb (cl-ppcre:register-groups-bind (u) ("<img src=\"([^\"]*-thumb\\.jpg)\"" (browser-html b)) u)))
               (is (not (null thumb)))
               (is (= 200 (mounted-get b (unescape thumb)))))
             (click b "Remove")
             (press b "Yes")
             (is (has-text-p b "No photos yet."))))
      (unmount-handler "/examples/gallery-files/")
      (setf littoral.storage:*storage* previous)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))
