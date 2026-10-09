;;;; gallery.lisp — uploads kept in storage, with thumbnails
;;;;
;;;; (asdf:load-system :littoral/storage-demo) (littoral-gallery:register)
;;;; serves /examples/gallery: photos with captions and an optional
;;;; attachment, described once.  The description's :IMAGE and :FILE fields
;;;; give the editor its file choosers and the page its thumbnails and
;;;; links; files are kept on disk in the temp directory and served at
;;;; /examples/gallery-files/, the records in SQLite.

(defpackage #:littoral-gallery
  (:use #:cl #:littoral #:littoral.html)
  (:documentation "A photo gallery: uploads, thumbnails and downloads.")
  (:export #:register #:gallery))

(in-package #:littoral-gallery)

(defclass photo (littoral.db:persistent)
  ((caption :initarg :caption :initform nil :accessor photo-caption)
   (picture :initarg :picture :initform nil :accessor photo-picture)
   (attachment :initarg :attachment :initform nil :accessor photo-attachment))
  (:documentation "A photo with a caption, and perhaps a file to go with it."))

(define-description photo
  ((caption :required t :max-length 80)
   (picture :type :image :required t :max-size 8000000)
   (attachment :type :file :max-size 8000000 :help "Anything: a PDF, a ZIP… downloaded, never shown.")))

(littoral.db:define-table photo :name "photos")

(defun field (name) (littoral::find-field (find-description 'photo) name))

(defclass gallery (component) ()
  (:documentation "The photos, newest first, and a way to add more."))

(defun add-photo (self)
  (show self (make-editor (make-instance 'photo) :title "New photo" :save-label "Upload")
        :on-answer (lambda (photo)
                     (when photo
                       (littoral.db:db-save photo)
                       (toast "Uploaded." :kind :success)))))

(defun remove-photo (self photo)
  (show self (make-instance 'confirm-dialog :message (format nil "Remove “~A”?" (photo-caption photo)))
        :on-answer (lambda (yes)
                     (when yes
                       (littoral.storage:delete-stored-file (photo-picture photo))
                       (when (photo-attachment photo)
                         (littoral.storage:delete-stored-file (photo-attachment photo)))
                       (littoral.db:db-delete photo)
                       (toast "Removed.")))))

(defmethod render ((self gallery))
  (h1 () "Gallery")
  (p () "Upload a photo: it's kept on disk, with a thumbnail made from it. "
    "The file's type comes from its bytes, so only real images are shown in the page.")
  (p () (anchor (:callback (lambda () (add-photo self))) "Add a photo"))
  (let ((photos (littoral.db:db-select 'photo :order-by "id DESC")))
    (if (null photos)
        (p (:class "empty") "No photos yet.")
        (ul (:class "gallery")
          (dolist (photo photos)
            (let ((photo photo))
              (li ()
                (littoral::render-field-value (field 'picture) (photo-picture photo))
                (p (:class "caption") (text (photo-caption photo)))
                (when (photo-attachment photo)
                  (p () (littoral::render-field-value (field 'attachment) (photo-attachment photo))))
                (p () (anchor (:callback (lambda () (remove-photo self photo))) "Remove")))))))))

(defmethod style ((self gallery))
  ".gallery { list-style: none; padding: 0; display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem; }
.gallery li { border: 1px solid var(--lt-border); border-radius: 8px; padding: .6rem; }
.gallery img { max-width: 100%; height: auto; }
.gallery .caption { font-weight: 600; margin: .4rem 0 .2rem; }
.empty { color: var(--lt-muted); }")

(defun register (&key (path "/examples/gallery")
                   (directory (merge-pathnames "littoral-gallery/" (uiop:temporary-directory))))
  "Serve the gallery at PATH, keeping files and the database under DIRECTORY."
  (let* ((directory (uiop:ensure-directory-pathname directory))
         (database (littoral.db:using-database
                    :sqlite3 :database-name (namestring (merge-pathnames "gallery.sqlite3" directory)))))
    (ensure-directories-exist directory)
    (setf littoral.storage:*storage*
          (littoral.storage:make-disk-storage (merge-pathnames "files/" directory)
                                              :prefix (format nil "~A-files/" path)))
    (funcall database (lambda () (littoral.db:create-table 'photo)))
    (register-application path 'gallery :title "Gallery"
                          :around-request database
                          :around-actions (littoral.db:transactional))))
