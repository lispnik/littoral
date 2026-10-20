;;;; Examples for littoral.auth: password reset by mail, the site's address, and more paths and buttons for signing in.

;;;; Example: littoral.auth:password-reset-request littoral.auth:password-reset littoral.auth:*send-mail* littoral.auth:*public-url*
;;; "Forgot your password?" on the sign-in form mails a link built from *PUBLIC-URL*.  Following it, at the AUTH-ROOT application, shows the form for a new password, which then signs the user in.
(defclass reading-room (littoral.auth:auth-root component) ())
(defmethod render ((self reading-room))
  (let ((user (littoral.auth:current-user)))
    (if user
        (h:p () (h:text (format nil "Hello, ~A." (littoral.auth:user-name user))))
        (h:anchor (:callback (lambda () (show self (make-instance 'littoral.auth:sign-in)))) "Sign in"))))
(let* ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
       (littoral.auth:*pbkdf2-iterations* 1000)
       (littoral.auth:*public-url* "https://library.example")
       (mails '())
       (littoral.auth:*send-mail* (lambda (to subject body) (push (list to subject body) mails))))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/library" 'reading-room :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/library")
      (click b "Sign in")
      (click b "Forgot your password?")
      (fill-in b "reset-email" "bob@example.org")
      (press b "Send me a link")
      (destructuring-bind (to subject body) (first mails)
        (let ((link (cl-ppcre:scan-to-strings "https://library.example/library/reset\\?token=\\S+" body))
              (other (make-instance 'browser)))
          (visit other link)
          (fill-in other "new-password" "a brand new passphrase")
          (fill-in other "new-password-again" "a brand new passphrase")
          (press other "Save and sign in")
          (list to subject (body-text other)
                (littoral.auth:check-password (littoral.auth:find-user "bob") "a brand new passphrase")))))))
;; ⇒ ("bob@example.org" "Choose a new password" "Hello, bob." T)

;;;; Example: littoral.auth:password-reset-request littoral.auth:*last-mail*
;;; An address without an account gets the same answer, and no mail.  *LAST-MAIL* holds the last mail sent, for development.
(defclass reset-page (component)
  ((form :initform (make-instance 'littoral.auth:password-reset-request) :reader reset-form)))
(defmethod children ((self reset-page)) (list (reset-form self)))
(defmethod render ((self reset-page))
  (render-component (reset-form self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*send-mail* (lambda (to subject body) (declare (ignore to subject body))))
      (littoral.auth:*last-mail* nil))
  (littoral.auth:create-auth-tables)
  (with-fresh-applications (("/reset-page" 'reset-page :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/reset-page")
      (fill-in b "reset-email" "nobody@example.org")
      (press b "Send me a link")
      (list (body-text b) littoral.auth:*last-mail*))))
;; ⇒ ("Reset your password If that address belongs to an account, a link to choose a new password is on its way. Back" NIL)

;;;; Example: littoral.auth:*reset-link-seconds*
;;; How long a reset link works: an hour, unless bound.  Here the link is aged two hours before it is followed.
(defclass short-links (littoral.auth:auth-root component) ())
(defmethod render ((self short-links))
  (h:anchor (:callback (lambda () (show self (make-instance 'littoral.auth:password-reset-request)))) "Reset"))
(let* ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
       (littoral.auth:*pbkdf2-iterations* 1000)
       (littoral.auth:*public-url* "https://short.example")
       (littoral.auth:*reset-link-seconds* 3600)
       (littoral.auth:*send-mail* (lambda (to subject body) (declare (ignore to subject body)))))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (with-fresh-applications (("/short" 'short-links :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/short")
      (click b "Reset")
      (fill-in b "reset-email" "bob@example.org")
      (press b "Send me a link")
      (littoral.db:db-execute "UPDATE auth_tokens SET expires = expires - 7200")
      (visit b (cl-ppcre:scan-to-strings "https://\\S+" (third littoral.auth:*last-mail*)))
      (body-text b))))
;; ⇒ "That link has expired or been used. Ask for a new one. OK"

;;;; Example: littoral.auth:request-base-url
;;; The site's address for links in mail and OAuth redirects: *PUBLIC-URL*, without a trailing slash.
(let ((littoral.auth:*public-url* "https://example.org/"))
  (littoral.auth:request-base-url))
;; ⇒ "https://example.org"

;;;; Example: littoral.auth:define-auth-path
;;; Answer a path of an AUTH-ROOT application when a session starts there, as /reset does: here, /welcome/NAME.
(littoral.auth:define-auth-path "welcome" (root rest request)
  (show root (make-instance 'message-dialog :message (format nil "Welcome, ~A!" (first rest)))))
(defclass guest-house (littoral.auth:auth-root component) ())
(defmethod render ((self guest-house)) (h:p () "The front page"))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.auth:create-auth-tables)
  (with-fresh-applications (("/house" 'guest-house :mode :deployment))
    (let ((b (make-instance 'browser)))
      (list (progn (visit b "/house/welcome/ada") (body-text b))
            (progn (visit b "/house") (body-text b))))))
;; ⇒ ("Welcome, ada! OK" "The front page")

;;;; Example: littoral.auth:*sign-in-extras*
;;; Add to the sign-in form: each function is called with the form, while it renders.
(defclass desk-sign-in (component) ())
(defmethod render ((self desk-sign-in))
  (render-component (make-instance 'littoral.auth:sign-in)))
(let ((littoral.auth:*offer-passkeys* nil)
      (littoral.auth:*sign-in-extras*
        (cons (lambda (sign-in)
                (declare (ignore sign-in))
                (h:p () "No account? Ask at the front desk."))
              littoral.auth:*sign-in-extras*)))
  (with-fresh-applications (("/desk" 'desk-sign-in :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/desk")
      (body-text b))))
;; ⇒ "Sign in Name Password Keep me signed in Sign in Cancel Forgot your password? No account? Ask at the front desk."

;;;; Example: littoral.auth:*failures-per-address* littoral.auth:*failure-window-seconds*
;;; Limits per client address apply to public addresses only: a loopback or private one is usually a proxy every visitor shares.  Here one public address tries many names, and is stopped even for a name it hasn't tried.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000)
      (littoral.auth:*failures-per-address* 3)
      (littoral.auth:*failure-window-seconds* 900)
      (*request* (lack/request:make-request
                  (let ((env (make-env :get "/")))
                    (setf (getf env :remote-addr) "203.0.113.5")
                    env))))
  (littoral.auth:create-auth-tables)
  (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")
  (dolist (name '("carol" "dave" "erin"))
    (littoral.auth:authenticate name "password1"))
  (multiple-value-list (littoral.auth:authenticate "bob" "another passphrase")))
;; ⇒ (NIL "Too many failed attempts; try again in a minute.")
