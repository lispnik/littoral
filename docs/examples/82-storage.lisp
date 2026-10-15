;;;; The examples for littoral.storage: uploaded files on disk, thumbnails, and file fields.

;;;; Example: littoral.storage:make-disk-storage littoral.storage:disk-storage littoral.storage:store-octets littoral.storage:stored-file littoral.storage:stored-file-key littoral.storage:stored-file-name littoral.storage:stored-file-type littoral.storage:stored-file-size littoral.storage:stored-file-thumbnail
;;; Keeping a file gives a STORED-FILE: a new random key, the name it came with (without directories), its type as its bytes say, and its size.  The storage also serves files at its prefix, so the example unmounts it and deletes its directory afterwards.
(let* ((directory (merge-pathnames "littoral-example-files/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "letters/ada.txt"
                                                  :storage storage)))
         (list (typep storage 'littoral.storage:disk-storage)
               (typep file 'littoral.storage:stored-file)
               (littoral.storage:stored-file-name file)
               (littoral.storage:stored-file-type file)
               (littoral.storage:stored-file-size file)
               (littoral.storage:stored-file-thumbnail file)
               (length (littoral.storage:stored-file-key file))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T T "ada.txt" "application/octet-stream" 9 NIL 28)

;;;; Example: littoral.storage:stored-file-url
;;; Where the browser fetches a stored file.  Only PNG, JPEG, GIF and WebP are shown in the page; anything else, such as this text, is served as a download under the name it was uploaded with.
(defun fetch (url)
  "The status, Content-Type, Content-Disposition and text of URL, as the fake browser gets them."
  (multiple-value-bind (status headers body) (raw-request (make-instance 'browser) :get url)
    (list status (getf headers :content-type) (getf headers :content-disposition) body)))
(let* ((directory (merge-pathnames "littoral-example-files-2/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let* ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Dear Ada,") "ada.txt" :storage storage))
              (url (littoral.storage:stored-file-url file :storage storage)))
         (list (string= url (format nil "/files/~A?name=ada.txt" (littoral.storage:stored-file-key file)))
               (fetch url)
               (fetch "/files/nothing-here.txt")))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (T (200 "application/octet-stream" "attachment; filename=\"ada.txt\"" "Dear Ada,") (404 "text/plain" NIL "Not found."))

;;;; Example: littoral.storage:make-disk-storage littoral.storage:stored-file-url
;;; With :PRIVATE T a file is served only through a signed URL, until it expires (:EXPIRES seconds, an hour by default).
(defun status (url)
  (nth-value 0 (raw-request (make-instance 'browser) :get url)))
(let* ((directory (merge-pathnames "littoral-example-private/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/private/" :private t)))
  (unwind-protect
       (let ((file (littoral.storage:store-octets (sb-ext:string-to-octets "Payslip") "payslip.txt" :storage storage)))
         (list (status (littoral.storage:stored-file-url file :storage storage))
               (status (format nil "/private/~A" (littoral.storage:stored-file-key file)))
               (status (littoral.storage:stored-file-url file :storage storage :expires -1))))
    (unmount-handler "/private/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (200 404 404)

;;;; Example: littoral.storage:store-octets littoral.storage:stored-file-thumbnail littoral.storage:stored-file-thumbnail-url littoral.storage:*thumbnail-size*
;;; With :THUMBNAIL T an image also gets a JPEG thumbnail, at most *THUMBNAIL-SIZE* pixels on its longer side.
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(let* ((directory (merge-pathnames "littoral-example-photos/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/photos/")))
  (unwind-protect
       (let* ((littoral.storage:*thumbnail-size* 120)
              (photo (littoral.storage:store-octets (png 600 300) "beach.png" :storage storage :thumbnail t))
              (thumbnail (littoral.storage:stored-file-thumbnail photo)))
         (list (littoral.storage:stored-file-type photo)
               (string= (littoral.storage:stored-file-thumbnail-url photo :storage storage)
                        (format nil "/photos/~A" thumbnail))
               (multiple-value-bind (octets type) (littoral.storage:storage-get storage thumbnail)
                 (list type (array-dimensions (flexi-streams:with-input-from-sequence (in octets)
                                                (opticl:read-jpeg-stream in)))))))
    (unmount-handler "/photos/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ("image/png" T ("image/jpeg" (60 120 3)))

;;;; Example: littoral.storage:*max-image-pixels*
;;; An image with more pixels than this gets no thumbnail, as decoding it could take all the memory.
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(let* ((directory (merge-pathnames "littoral-example-big/" (uiop:temporary-directory)))
       (storage (littoral.storage:make-disk-storage directory :prefix "/big/")))
  (unwind-protect
       (let ((littoral.storage:*max-image-pixels* 10000))
         (list (littoral.storage:stored-file-thumbnail
                (littoral.storage:store-octets (png 200 100) "big.png" :storage storage :thumbnail t))
               (littoral.storage:stored-file-thumbnail-url
                (littoral.storage:store-octets (png 200 100) "big.png" :storage storage :thumbnail t)
                :storage storage)))
    (unmount-handler "/big/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (NIL NIL)

;;;; Example: littoral.storage:delete-stored-file
;;; Deleting a stored file deletes its thumbnail too; its URL then answers 404.
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(let* ((directory (merge-pathnames "littoral-example-delete/" (uiop:temporary-directory)))
       (littoral.storage:*storage* (littoral.storage:make-disk-storage directory :prefix "/files/")))
  (unwind-protect
       (let ((photo (littoral.storage:store-octets (png 40 30) "cat.png" :thumbnail t)))
         (littoral.storage:delete-stored-file photo)
         (list (littoral.storage:storage-get littoral.storage:*storage* (littoral.storage:stored-file-key photo))
               (littoral.storage:storage-get littoral.storage:*storage* (littoral.storage:stored-file-thumbnail photo))
               (nth-value 0 (raw-request (make-instance 'browser) :get (littoral.storage:stored-file-url photo)))))
    (unmount-handler "/files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ (NIL NIL 404)

;;;; Example: littoral.storage:sniff-type
;;; A file's type comes from its first bytes, whatever its name or the browser said.
(list (littoral.storage:sniff-type (sb-ext:string-to-octets "%PDF-1.7 …" :external-format :utf-8))
      (littoral.storage:sniff-type (coerce #(#xFF #xD8 #xFF #xE0 0 16) '(vector (unsigned-byte 8))))
      (littoral.storage:sniff-type (sb-ext:string-to-octets "<svg onload=\"alert(1)\">")))
;; ⇒ ("application/pdf" "image/jpeg" "application/octet-stream")

;;;; Example: littoral.storage:storage littoral.storage:storage-put littoral.storage:storage-get littoral.storage:storage-delete littoral.storage:storage-url
;;; A storage of one's own: a subclass of STORAGE with methods for the four generic functions.  This one keeps files in memory, and its URLs point at a CDN.
(defclass memory-storage (littoral.storage:storage)
  ((files :initform (make-hash-table :test 'equal) :reader storage-files)))
(defmethod littoral.storage:storage-put ((storage memory-storage) key octets content-type)
  (setf (gethash key (storage-files storage)) (cons octets content-type))
  key)
(defmethod littoral.storage:storage-get ((storage memory-storage) key)
  (let ((entry (gethash key (storage-files storage))))
    (and entry (values (car entry) (cdr entry)))))
(defmethod littoral.storage:storage-delete ((storage memory-storage) key)
  (remhash key (storage-files storage)))
(defmethod littoral.storage:storage-url ((storage memory-storage) key &key filename expires)
  (declare (ignore expires))
  (format nil "https://cdn.example.org/~A~@[?download=~A~]" key filename))
(let* ((storage (make-instance 'memory-storage))
       (file (littoral.storage:store-octets (sb-ext:string-to-octets "%PDF-1.7") "minutes.pdf" :storage storage)))
  (list (nth-value 1 (littoral.storage:storage-get storage (littoral.storage:stored-file-key file)))
        (string= (littoral.storage:stored-file-url file :storage storage)
                 (format nil "https://cdn.example.org/~A?download=minutes.pdf" (littoral.storage:stored-file-key file)))
        (progn (littoral.storage:delete-stored-file file storage)
               (hash-table-count (storage-files storage)))))
;; ⇒ ("application/pdf" T 0)

;;;; Example: littoral.storage:make-s3-storage littoral.storage:s3-storage
;;; Files in an S3 bucket (or MinIO, R2 and the like, given :ENDPOINT).  Private storage, the default, hands out presigned URLs that expire; a public bucket's URLs point straight at it.  Making the storage contacts no server.
(let ((public (littoral.storage:make-s3-storage :bucket "photos" :region "eu-west-1" :private nil))
      (private (littoral.storage:make-s3-storage :bucket "photos" :region "eu-west-1"
                                                 :access-key "AKIDEXAMPLE" :secret-key "secret")))
  (list (typep public 'littoral.storage:s3-storage)
        (littoral.storage:storage-url public "beach.png")
        (alexandria:starts-with-subseq
         "https://s3.eu-west-1.amazonaws.com/photos/beach.png?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIDEXAMPLE%2F"
         (littoral.storage:storage-url private "beach.png" :expires 600))))
;; ⇒ (T "https://s3.eu-west-1.amazonaws.com/photos/beach.png" T)

;;;; Example: littoral.storage:store-upload
;;; A file from a FILE-INPUT, kept in *STORAGE*.
(defclass inbox (component)
  ((received :initform '() :accessor received)))
(defmethod render ((self inbox))
  (form (:multipart t)
    (file-input (:id "document"
                 :callback (lambda (upload)
                             (push (littoral.storage:store-upload upload) (received self)))))
    (submit-button () "Send"))
  (ul ()
    (dolist (file (received self))
      (li () (text (format nil "~A, ~D bytes" (littoral.storage:stored-file-name file)
                           (littoral.storage:stored-file-size file)))))))
(let* ((directory (merge-pathnames "littoral-example-inbox/" (uiop:temporary-directory)))
       (littoral.storage:*storage* (littoral.storage:make-disk-storage directory :prefix "/inbox-files/")))
  (unwind-protect
       (with-fresh-applications (("/inbox" 'inbox :mode :deployment))
         (let ((b (make-instance 'browser)))
           (visit b "/inbox")
           (attach-file b "document" "notes.txt" "text/plain" "Remember the milk.")
           (press b "Send")
           (body-text b)))
    (unmount-handler "/inbox-files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ "Send notes.txt, 18 bytes"

;;;; Example: littoral.storage:file-field littoral.storage:image-field littoral.storage:*storage*
;;; In a description, :TYPE :FILE is an upload (with :MAX-SIZE in bytes) and :TYPE :IMAGE one that must be a PNG, JPEG, GIF or WebP image, kept with a thumbnail.  Editors get a file chooser; files go to *STORAGE* unless the field gives :STORAGE.
(defun png (width height)
  "A grey PNG of WIDTH by HEIGHT pixels."
  (flexi-streams:with-output-to-sequence (out)
    (opticl:write-png-stream out (opticl:make-8-bit-rgb-image height width :initial-element 200))))
(defclass applicant ()
  ((name :initarg :name :initform nil)
   (photo :initarg :photo :initform nil)
   (letter :initarg :letter :initform nil)))
(define-description applicant
  ((name :required t)
   (photo :type :image)
   (letter :type :file :max-size 1000)))
(defclass application-form (component)
  ((saved :initform nil :accessor saved)))
(defmethod render ((self application-form))
  (if (saved self)
      (p () (text (format nil "Saved: ~A" (littoral.storage:stored-file-name (slot-value (saved self) 'letter)))))
      (anchor (:callback (lambda ()
                           (show self (make-editor (make-instance 'applicant))
                                 :on-answer (lambda (applicant) (setf (saved self) applicant)))))
        "Apply")))
(let* ((directory (merge-pathnames "littoral-example-applicants/" (uiop:temporary-directory)))
       (littoral.storage:*storage* (littoral.storage:make-disk-storage directory :prefix "/applicant-files/")))
  (unwind-protect
       (with-fresh-applications (("/apply" 'application-form :mode :deployment))
         (let ((b (make-instance 'browser)) (messages '()))
           (visit b "/apply")
           (click b "Apply")
           (fill-in b "name" "Ada")
           (attach-file b "photo" "photo.txt" "image/png" "not a picture")
           (attach-file b "letter" "letter.txt" "text/plain" (make-string 2000 :initial-element #\a))
           (press b "Save")
           (push (not (null (has-text-p b "Photo must be a PNG, JPEG, GIF or WebP image."))) messages)
           (push (not (null (has-text-p b "Letter is too large: at most 1,000 bytes."))) messages)
           (setf (browser-files b) '())
           (attach-file b "photo" "ada.png" "image/png" (png 80 60))
           (attach-file b "letter" "letter.txt" "text/plain" "Dear committee,")
           (press b "Save")
           (list (reverse messages) (body-text b))))
    (unmount-handler "/applicant-files/")
    (uiop:delete-directory-tree directory :validate t)))
;; ⇒ ((T T) "Saved: letter.txt")
