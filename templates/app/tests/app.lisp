;;;; app.lisp — signing in and keeping notes, through a fake browser
;;;;
;;;; Each test gets its own SQLite file.  VISIT a URL, CLICK a link by its
;;;; text, FILL-IN a field by its id and PRESS a button, then ask what the
;;;; page says with HAS-TEXT-P.

(in-package #:{{name}}/tests)

(in-suite {{name}})

(defmacro with-app ((b) &body body)
  "The application over a fresh database with users ada and bob, and a browser."
  (let ((file (gensym)))
    `(let* ((,file (merge-pathnames (format nil "{{name}}-test-~36R.sqlite3" (random (expt 36 8)))
                                    (uiop:temporary-directory)))
            (database (list :sqlite3 :database-name (namestring ,file))))
       (unwind-protect
            (with-fresh-applications ()
              (register-app :mode :deployment :database database)
              (create-user "ada" "ada@example.org" "ada's long passphrase" :admin t :database database)
              (create-user "bob" "bob@example.org" "bob's long passphrase" :database database)
              (let ((,b (make-instance 'browser)))
                (visit ,b "/")
                ,@body))
         (uiop:delete-file-if-exists ,file)))))

(defun sign-in (b name password)
  (click b "Sign in")
  (fill-in b "sign-in-name" name)
  (fill-in b "sign-in-password" password)
  (press b "Sign in"))

(defun add (b title)
  (click b "Add a note")
  (fill-in b "title" title)
  (press b "Add"))

(test notes-need-signing-in
  (with-app (b)
    (is (has-text-p b "Please sign in to see this."))
    (sign-in b "ada" "wrong")
    (is (has-text-p b "Unknown user or wrong password."))
    (fill-in b "sign-in-name" "ada")
    (fill-in b "sign-in-password" "ada's long passphrase")
    (press b "Sign in")
    (is (has-text-p b "Signed in as ada"))
    (is (has-text-p b "No notes yet."))))

(test adding-editing-and-removing
  (with-app (b)
    (sign-in b "ada" "ada's long passphrase")
    (click b "Add a note")
    (press b "Add")
    (is (has-text-p b "Title is required."))
    (fill-in b "title" "Buy milk")
    (press b "Add")
    (is (has-text-p b "Note added."))
    (is (has-text-p b "Buy milk"))
    (click b "edit")
    (fill-in b "title" "Buy oat milk")
    (press b "Save")
    (is (has-text-p b "Buy oat milk"))
    (click b "remove")
    (press b "Yes")
    (is (has-text-p b "No notes yet."))))

(test notes-are-private
  (with-app (b)
    (sign-in b "ada" "ada's long passphrase")
    (add b "Ada's secret")
    (let ((other (make-instance 'browser)))
      (visit other "/")
      (sign-in other "bob" "bob's long passphrase")
      (is (has-text-p other "No notes yet."))
      (is (not (has-text-p other "Ada's secret"))))))
