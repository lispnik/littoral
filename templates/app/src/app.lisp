;;;; app.lisp — the pages

(in-package #:{{name}})

(defun owner-id ()
  (princ-to-string (littoral.auth:user-id (littoral.auth:current-user))))

(defun my-notes ()
  "The signed-in user's notes, newest first."
  (littoral.db:db-select 'note :where "owner = ?" :params (list (owner-id)) :order-by "id DESC"))

;;; Who is signed in

(defclass account-box (component) ()
  (:documentation "Who is signed in, with a link to sign in or out.  The
sign-in form shows in its place."))

(defmethod render ((self account-box))
  (let ((user (littoral.auth:current-user)))
    (p (:class "account")
      (if user
          (progn (text "Signed in as ") (strong () (text (littoral.auth:user-name user)))
                 (text " · ")
                 (littoral.auth:sign-out-link))
          (anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in))))
            "Sign in")))))

;;; The notes

(defclass notes-page (littoral.auth:restricted component)
  ((report :reader notes-report))
  (:documentation "The signed-in user's notes: a table, with editors to add,
change and remove them.  RESTRICTED: a sign-in prompt shows until someone
signs in."))

(defmethod initialize-instance :after ((self notes-page) &key)
  (setf (slot-value self 'report)
        (make-instance 'report
                       :rows (lambda () (my-notes))
                       :batch-size 20
                       :columns (append (description-columns 'note 'title)
                                        (list (column "" nil :sortable nil
                                                      :render (lambda (note value)
                                                                (declare (ignore value))
                                                                (anchor (:callback (lambda () (edit-note self note))) "edit")
                                                                (text " ")
                                                                (anchor (:callback (lambda () (remove-note self note))) "remove"))))))))

(defmethod children ((self notes-page))
  (list (notes-report self)))

(defun add-note (self)
  (show self (make-editor (make-instance 'note :owner (owner-id)) :title "New note" :save-label "Add")
        :on-answer (lambda (note)
                     (when note
                       (littoral.db:db-save note)
                       (toast "Note added." :kind :success)))))

(defun edit-note (self note)
  (show self (make-editor note :title "Edit note")
        :on-answer (lambda (edited)
                     (when edited
                       (handler-case (progn (littoral.db:db-save edited) (toast "Saved." :kind :success))
                         ;; Someone saved it in another tab meanwhile.
                         (littoral.db:stale-object ()
                           (toast "That note changed meanwhile; your edit wasn't saved." :kind :error)))))))

(defun remove-note (self note)
  (show self (make-instance 'confirm-dialog :message (format nil "Remove “~A”?" (note-title note)))
        :on-answer (lambda (yes)
                     (when yes
                       (littoral.db:db-delete note)
                       (toast "Note removed.")))))

(defmethod render ((self notes-page))
  (p () (anchor (:callback (lambda () (add-note self))) "Add a note"))
  (if (my-notes)
      (render-component (notes-report self))
      (p (:class "empty") "No notes yet.")))

;;; The page

(defclass app-root (littoral.auth:auth-root component)
  ((account :initform (make-instance 'account-box) :reader root-account)
   (notes :initform (make-instance 'notes-page) :reader root-notes))
  (:documentation "The root of {{title}}.  AUTH-ROOT: it answers password
reset links and brings back sign-ins kept from before a restart."))

(defmethod children ((self app-root))
  (list (root-account self) (root-notes self)))

(defmethod render ((self app-root))
  (header (:class "top")
    (h1 () "{{title}}")
    (render-component (root-account self)))
  (render-component (root-notes self)))

(defmethod style ((self app-root))
  ".top { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: baseline; gap: .5rem 1rem; }
.empty { color: var(--lt-muted); }")
