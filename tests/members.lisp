;;;; members.lisp — the members example: signing in, roles, reset, OAuth

(in-package #:littoral/tests)

(def-suite members :in littoral)
(in-suite members)

(defvar *members-test-file* nil "The database file of the members test running.")

(defun members-test-file () *members-test-file*)

(defmacro with-members ((b) &body body)
  "The members example over a fresh database, and a browser on it."
  (let ((file (gensym "FILE")))
    `(let* ((,file (merge-pathnames (format nil "littoral-members-test-~36R.sqlite3" (random (expt 36 8)))
                                    (uiop:temporary-directory)))
            (*members-test-file* ,file))
       (unwind-protect
            (with-fresh-applications ()
              (littoral-members-demo:register :file ,file)
              (littoral.mail:clear-mailer littoral-mail-demo:*mailbox*)
              (clrhash littoral.auth::*failures*)
              (let ((,b (make-instance 'browser)))
                (visit ,b "/examples/members")
                ,@body))
         (setf littoral.oauth::*providers* '())
         (littoral.mail:stop-mail-delivery)
         (uiop:delete-file-if-exists ,file)))))

(defun members-sign-in (b name password)
  (click b "Sign in")
  (fill-in b "sign-in-name" name)
  (fill-in b "sign-in-password" password)
  (press b "Sign in"))

(test members-roles
  (with-members (b)
    (is (has-text-p b "Anyone can see this part"))
    (is (has-text-p b "Not signed in"))
    (is (has-text-p b "Please sign in to see this."))
    (is (not (has-text-p b "Welcome back")))
    (members-sign-in b "bob" "another passphrase")
    (is (has-text-p b "Signed in as bob"))
    (is (has-text-p b "Welcome back"))
    (is (has-text-p b "You don't have permission to see this."))
    (let ((page (browser-url b)))
      (click b "Do something only admins may do")
      (is (= 403 (browser-status b)))
      (back-to b page))
    (click b "Sign out")
    (members-sign-in b "ada" "correct horse battery")
    (is (has-text-p b "Signed in as ada (admin)"))
    (is (has-text-p b "bob@example.org"))
    (click b "Do something only admins may do")
    (is (has-text-p b "and you are one"))
    ;; Ada switches bob off; he can no longer sign in.
    (click b "Deactivate")
    (is (has-text-p b "bob is now inactive"))
    (click b "Sign out")
    (members-sign-in b "bob" "another passphrase")
    (is (has-text-p b "Unknown user or wrong password."))))

(test members-password-reset-through-the-mailbox
  (with-members (b)
    (click b "Sign in")
    (click b "Forgot your password?")
    (fill-in b "reset-email" "bob@example.org")
    (press b "Send me a link")
    (is (has-text-p b "is on its way"))
    ;; Queued in the outbox; once sent, it's in the demo mailbox.
    (littoral-mail-demo:deliver-now)
    (visit b "/examples/members")
    (is (has-text-p b "To: bob@example.org"))
    (let ((link (find-link b "Open the reset link")))
      (is (search "/examples/members/reset?token=" link))
      (let ((other (make-instance 'browser)))
        (visit other link)
        (fill-in other "new-password" "a fresh passphrase")
        (fill-in other "new-password-again" "a fresh passphrase")
        (press other "Save and sign in")
        (is (has-text-p other "Signed in as bob"))))))

(defun press-demoid (b)
  "Press Sign in with DemoID; arrive at DemoID's page."
  (click b "Sign in")
  (press b "Sign in with DemoID")
  (is (search "/examples/demo-idp" (browser-url b)))
  (is (has-text-p b "Continue as")))

(test members-oauth-with-demoid
  (with-members (b)
    (press-demoid b)
    (press b "carol@example.org")
    (is (has-text-p b "Signed in as carol")))
  ;; Denying comes back without signing in.
  (with-members (b)
    (press-demoid b)
    (press b "Deny")
    (is (has-text-p b "didn't work"))))

(test demoid-checks-the-pkce-verifier
  (let ((code "test-code"))
    (setf (gethash code littoral-members-demo::*codes*)
          (list (littoral.oauth::code-challenge "the-right-verifier") "http://x/oauth/demoid"
                "carol@example.org" "carol" (+ (get-universal-time) 60)))
    (flet ((exchange (verifier)
             (littoral-members-demo::demo-token
              `(("code" . ,code) ("client_id" . "members-demo") ("client_secret" . "not-so-secret")
                ("redirect_uri" . "http://x/oauth/demoid") ("code_verifier" . ,verifier)))))
      (is (search "invalid_grant" (exchange "a-wrong-verifier")))
      ;; The code was used up by that attempt, even though it failed.
      (setf (gethash code littoral-members-demo::*codes*)
            (list (littoral.oauth::code-challenge "the-right-verifier") "http://x/oauth/demoid"
                  "carol@example.org" "carol" (+ (get-universal-time) 60)))
      (is (search "access_token" (exchange "the-right-verifier")))
      (is (search "invalid_grant" (exchange "the-right-verifier"))))))

(test the-index-lists-only-registered-examples
  (with-fresh-applications (("/examples" 'littoral-examples:example-index))
    (let ((b (make-instance 'browser)))
      (visit b "/examples")
      (is (null (find-link b "Members")))
      (littoral-members-demo:register
       :file (merge-pathnames "littoral-members-index-test.sqlite3" (uiop:temporary-directory)))
      (visit b "/examples")
      (is (find-link b "Members"))
      (setf littoral.oauth::*providers* '()))))

(test members-editors-and-permissions
  (with-members (b)
    (members-sign-in b "bob" "another passphrase")
    (let ((page (browser-url b)))
      (click b "Edit a post")
      (is (= 403 (browser-status b)))
      (back-to b page))
    (click b "Sign out")
    (members-sign-in b "ada" "correct horse battery")
    (click b "Edit a post")
    (is (has-text-p b "You may edit posts."))
    (click b "Make editor")
    (is (has-text-p b "bob is now an editor."))
    (click b "Sign out")
    (members-sign-in b "bob" "another passphrase")
    (click b "Edit a post")
    (is (has-text-p b "You may edit posts."))))

(test members-sessions-list
  (with-members (b)
    (members-sign-in b "bob" "another passphrase")
    (is (has-text-p b "(this browser)"))
    (let ((phone (make-instance 'browser)))
      (visit phone "/examples/members")
      (members-sign-in phone "bob" "another passphrase")
      ;; The phone sees the first browser's sign-in, and ends it.
      (is (search "End" (page-text phone)))
      (click phone "End")
      (is (has-text-p phone "That sign-in has ended."))
      (let ((littoral.auth:*auth-session-check-seconds* 0))
        (visit b (browser-url b))
        (is (has-text-p b "Not signed in")))
      ;; Sign out everywhere ends the phone's own too.
      (click phone "Sign out everywhere")
      (is (has-text-p phone "Not signed in")))))

(test accounts-from-an-existing-table
  (with-members (b)
    (visit b "/examples/accounts")
    (is (has-text-p b "Accounts (an existing table)"))
    (members-sign-in b "dora" "dora's password")
    (is (has-text-p b "Signed in as dora (admin)"))
    (is (has-text-p b "eve@example.org"))
    (click b "Sign out")
    (members-sign-in b "eve" "correct horse battery")
    (is (has-text-p b "Signed in as eve"))
    ;; Her Werkzeug hash is now Littoral's.
    (is (alexandria:starts-with-subseq
         "PBKDF2$"
         (funcall (littoral.db:using-database :sqlite3 :database-name
                                              (namestring (members-test-file)))
                  (lambda ()
                    (getf (first (littoral.db:db-query "SELECT pw_hash FROM accounts WHERE login = 'eve'"))
                          :|pw_hash|)))))))

(test mail-demo-outbox
  (with-members (b)
    (visit b "/examples/mail")
    (is (has-text-p b "Outbox"))
    (fill-in b "mail-to" "Ada <ada@example.org>")
    (fill-in b "mail-subject" "Über die Post")
    (press b "Queue it")
    (is (has-text-p b "Queued."))
    (littoral-mail-demo:deliver-now)
    (visit b "/examples/mail")
    (is (has-text-p b "Über die Post"))
    (is (has-text-p b "sent"))
    ;; The server goes down: the welcome mail waits, with the reason.
    (click b "Switch it off")
    (unwind-protect
         (progn
           (press b "Queue the welcome template")
           (littoral-mail-demo:deliver-now)
           (visit b "/examples/mail")
           (is (has-text-p b "Connection refused"))
           (is (has-text-p b "queued")))
      (setf littoral-mail-demo:*server-down* nil))
    ;; Back up, and retried by hand.
    (visit b "/examples/mail")
    (click b "Retry")
    (littoral-mail-demo:deliver-now)
    (visit b "/examples/mail")
    (is (has-text-p b "Welcome to the Littoral demo"))
    (is (search "<!DOCTYPE html>" (browser-html b)) "The HTML version is previewed")))
