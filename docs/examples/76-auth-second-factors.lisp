;;;; Examples for littoral.auth: authenticator apps, recovery codes and passkeys.

;;;; Example: littoral.auth:security-settings littoral.auth:second-factor-p littoral.auth:user-factors
;;; A signed-in user sets up an authenticator app from the security settings: the page shows a QR code and the key, and the app's code turns it on.  From then on, signing in with a password asks for a code too.
(defclass account (littoral.auth:auth-root component)
  ((security :initform (make-instance 'littoral.auth:security-settings) :reader account-security)))
(defmethod children ((self account)) (list (account-security self)))
(defmethod render ((self account))
  (let ((user (littoral.auth:current-user)))
    (h:p () (h:text (if user (format nil "Hello, ~A." (littoral.auth:user-name user)) "Hello, stranger."))))
  (render-component (account-security self)))
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((bob (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")))
    (with-fresh-applications (("/account" 'account :mode :deployment))
      (flet ((sign-in (b)
               (visit b "/account")
               (click b "Sign in")
               (fill-in b "sign-in-name" "bob")
               (fill-in b "sign-in-password" "another passphrase")
               (press b "Sign in")))
        (let ((b (make-instance 'browser)))
          (sign-in b)
          (click b "Set up an authenticator app")
          (let ((secret (cl-ppcre:register-groups-bind (key) ("Key: <code>([A-Z2-7]+)</code>" (browser-html b)) key)))
            (fill-in b "totp-code" (littoral.auth:totp-code secret))
            (press b "Turn on")
            (let ((other (make-instance 'browser)))
              (sign-in other)
              (let ((asked (body-text other)))
                (fill-in other "sign-in-code" (littoral.auth:totp-code secret (+ (get-universal-time) 30)))
                (press other "Verify")
                (list asked (littoral.auth:second-factor-p bob)
                      (littoral.auth::factor-kind (first (littoral.auth:user-factors bob)))
                      (body-text other))))))))))
;; ⇒ ("Hello, stranger. Check it's you The code from your authenticator app Verify Cancel Use a recovery code instead" T "totp" "Hello, bob. Authenticator app On: signing in with your password also asks for its code. Turn off Passkeys None yet. A passkey signs you in with your fingerprint, face or device PIN, without a password. Add a passkey Recovery codes 10 codes left Make new codes")

;;;; Example: littoral.auth:hotp
;;; RFC 4226's own test values: a key and a counter give a code.
(let ((key (sb-ext:string-to-octets "12345678901234567890")))
  (list (littoral.auth:hotp key 0)
        (littoral.auth:hotp key 1)
        (littoral.auth:hotp key 1 :digits 8)))
;; ⇒ ("755224" "287082" "94287082")

;;;; Example: littoral.auth:totp-code littoral.auth:verify-totp
;;; A code lasts 30 seconds.  VERIFY-TOTP accepts one step either way, and returns the step it matched: pass it back as :AFTER so the same code doesn't work twice.
(let* ((secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
       (time (encode-universal-time 0 0 12 1 1 2026 0))
       (code (littoral.auth:totp-code secret time))
       (step (littoral.auth:verify-totp secret code :universal-time time)))
  (list code
        step
        (littoral.auth:verify-totp secret code :universal-time (+ time 30))
        (littoral.auth:verify-totp secret code :universal-time (+ time 300))
        (littoral.auth:verify-totp secret code :after step :universal-time time)))
;; ⇒ ("082995" 58908960 58908960 NIL NIL)

;;;; Example: littoral.auth:new-totp-secret littoral.auth:totp-uri
;;; A new secret, and the address an authenticator app reads from a QR code.
(let ((secret (littoral.auth:new-totp-secret)))
  (list (length secret)
        (littoral.auth:totp-uri "JBSWY3DPEHPK3PXP" "ada@example.org" "The Shop")))
;; ⇒ (32 "otpauth://totp/The%20Shop:ada%40example.org?secret=JBSWY3DPEHPK3PXP&issuer=The%20Shop&algorithm=SHA1&digits=6&period=30")

;;;; Example: littoral.auth:base32-encode littoral.auth:base32-decode
(list (littoral.auth:base32-encode (sb-ext:string-to-octets "Hello!"))
      (sb-ext:octets-to-string (littoral.auth:base32-decode "jbsw y3dp ee")))
;; ⇒ ("JBSWY3DPEE" "Hello!")

;;;; Example: littoral.auth:qr-svg
;;; Text as a QR code, as inline SVG for RAW to write into a page.
(let ((svg (littoral.auth:qr-svg "otpauth://totp/Shop:ada?secret=JBSWY3DPEHPK3PXP" :label "Scan me")))
  (list (subseq svg 0 18)
        (not (null (search "aria-label=\"Scan me\"" svg)))))
;; ⇒ ("<svg class=\"lt-qr\"" T)

;;;; Example: littoral.auth:make-recovery-codes littoral.auth:use-recovery-code littoral.auth:recovery-codes-left
;;; Ten single-use codes, for when the other ways in are lost.  Only their hashes are kept, so show them once.  Case and spaces around them don't matter.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let* ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery"))
         (codes (littoral.auth:make-recovery-codes ada)))
    (list (length codes)
          (every (lambda (code) (cl-ppcre:scan "^[a-z2-7]{5}-[a-z2-7]{5}$" code)) codes)
          (littoral.auth:use-recovery-code ada (string-upcase (first codes)))
          (littoral.auth:use-recovery-code ada (first codes))
          (littoral.auth:recovery-codes-left ada))))
;; ⇒ (10 T T NIL 9)

;;;; Example: littoral.auth:cbor-decode
;;; As much CBOR as WebAuthn uses: maps become alists, byte strings octet vectors.  The second value is where the next item starts.
(multiple-value-list
 (littoral.auth:cbor-decode
  (coerce #(#xA2 #x63 #x66 #x6D #x74 #x64 #x6E #x6F #x6E #x65 #x01 #x42 #x01 #x02) '(vector (unsigned-byte 8)))))
;; ⇒ ((("fmt" . "none") (1 . #(1 2))) 14)

;;;; Example: littoral.auth:passkey-error littoral.auth:verify-assertion
;;; Every check a passkey fails signals PASSKEY-ERROR, with the reason.  The security settings and the sign-in form handle it; here, a response from a passkey this site doesn't know.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.auth:create-auth-tables)
  (handler-case
      (littoral.auth:verify-assertion "the-challenge"
                                      (com.inuoe.jzon:parse "{\"id\": \"unknown\", \"response\": {}}"))
    (littoral.auth:passkey-error (e) (princ-to-string e))))
;; ⇒ "Passkey refused: that passkey isn't known here"

;;;; Example: littoral.auth:verify-registration littoral.auth:add-passkey
;;; ADD-PASSKEY checks the browser's navigator.credentials.create response with VERIFY-REGISTRATION, then keeps the passkey.  A response for another challenge than the one the page sent is refused.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*public-url* "https://example.org")
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let* ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery"))
         (client-data (cl-base64:string-to-base64-string
                       "{\"type\":\"webauthn.create\",\"challenge\":\"old\",\"origin\":\"https://example.org\"}"
                       :uri t))
         (response (format nil "{\"response\": {\"clientDataJSON\": ~S, \"attestationObject\": \"oA\"}}"
                           (string-right-trim "." client-data))))
    (handler-case (littoral.auth:add-passkey ada "new" response)
      (littoral.auth:passkey-error (e) (princ-to-string e)))))
;; ⇒ "Passkey refused: the challenge doesn't match"
