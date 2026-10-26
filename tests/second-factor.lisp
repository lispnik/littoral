;;;; second-factor.lisp — authenticator apps, recovery codes and passkeys

(in-package #:littoral/tests)

(def-suite second-factor :in littoral)
(in-suite second-factor)

(defparameter *rfc-key* (sb-ext:string-to-octets "12345678901234567890"))

(test hotp-and-totp-match-the-rfcs
  ;; RFC 4226, appendix D.
  (is (equal '("755224" "287082" "359152" "969429" "338314")
             (loop for c below 5 collect (littoral.auth:hotp *rfc-key* c))))
  ;; RFC 6238, appendix B (SHA-1, eight digits, 30-second steps).
  (loop for (time code) in '((59 "94287082") (1111111109 "07081804") (1111111111 "14050471")
                             (1234567890 "89005924") (2000000000 "69279037"))
        do (is (string= code (littoral.auth:hotp *rfc-key* (floor time 30) :digits 8)))))

(test totp-codes-work-once
  (let* ((secret (littoral.auth:new-totp-secret))
         (now (get-universal-time))
         (code (littoral.auth:totp-code secret now))
         (step (littoral.auth:verify-totp secret code :universal-time now)))
    (is (= 32 (length secret)))
    (is (equalp (littoral.auth:base32-decode (littoral.auth:base32-encode #(1 2 3 250 251))) #(1 2 3 250 251)))
    (is (integerp step))
    ;; Used once, not again.
    (is (null (littoral.auth:verify-totp secret code :after step :universal-time now)))
    ;; A neighbouring step is still accepted; a far one isn't.
    (is (littoral.auth:verify-totp secret (littoral.auth:totp-code secret (- now 30)) :universal-time now))
    (is (null (littoral.auth:verify-totp secret (littoral.auth:totp-code secret (- now 300)) :universal-time now)))
    (is (search "otpauth://totp/Shop:ada?secret=" (littoral.auth:totp-uri secret "ada" "Shop")))
    (is (search "<svg class=\"lt-qr\"" (littoral.auth:qr-svg (littoral.auth:totp-uri secret "ada" "Shop"))))))

(defun give-totp (name &key key)
  "Give the user NAME an authenticator app, its secret sealed with KEY if
given; its secret."
  (let* ((user (littoral.auth:find-user name))
         (id (princ-to-string (littoral.auth:user-id user)))
         (secret (littoral.auth:new-totp-secret)))
    (littoral.db:db-insert (make-instance 'littoral.auth::auth-factor :user-id id
                                                                      :kind "totp" :name "App" :counter 0
                                                                      :data (if key
                                                                                (let ((littoral.auth:*factor-key* key))
                                                                                  (littoral.auth::seal-totp-secret secret id))
                                                                                secret)
                                                                      :created (get-universal-time)))
    secret))

(test signing-in-asks-for-the-second-factor
  (with-auth (b)
    (let ((secret (give-totp "bob")))
      (sign-in-as b "bob" "another passphrase")
      (is (has-text-p b "Check it's you"))
      (is (not (has-text-p b "Signed in as bob")))
      (fill-in b "sign-in-code" "000000")
      (press b "Verify")
      (is (has-text-p b "That code isn't right."))
      (let ((code (littoral.auth:totp-code secret)))
        (fill-in b "sign-in-code" code)
        (press b "Verify")
        (is (has-text-p b "Signed in as bob"))
        ;; The same code, again, elsewhere: refused.
        (let ((other (make-instance 'browser)))
          (visit other "/m")
          (sign-in-as other "bob" "another passphrase")
          (fill-in other "sign-in-code" code)
          (press other "Verify")
          (is (has-text-p other "That code isn't right.")))))))

(test authenticator-secrets-are-encrypted
  (let ((secret (littoral.auth:new-totp-secret))
        (key (ironclad:random-data 32)))
    (let ((littoral.auth:*factor-key* nil))
      (is (string= secret (littoral.auth::seal-totp-secret secret "7")) "Without a key, kept as it is"))
    (let* ((littoral.auth:*factor-key* key)
           (sealed (littoral.auth::seal-totp-secret secret "7")))
      (is (alexandria:starts-with-subseq "aes1:" sealed))
      (is (not (search secret sealed)))
      (is (string/= sealed (littoral.auth::seal-totp-secret secret "7")) "A fresh nonce each time")
      (is (string= secret (littoral.auth::open-totp-secret sealed "7")))
      (is (string= secret (littoral.auth::open-totp-secret secret "7")) "Secrets from before the key still read")
      (signals error (littoral.auth::open-totp-secret sealed "8") "Bound to its user")
      (let ((littoral.auth:*factor-key* (ironclad:random-data 32)))
        (signals error (littoral.auth::open-totp-secret sealed "7")))
      (let ((littoral.auth:*factor-key* nil))
        (signals error (littoral.auth::open-totp-secret sealed "7")))
      ;; Keys as text: hex or base 64; other lengths are refused.
      (let ((littoral.auth:*factor-key* (ironclad:byte-array-to-hex-string key)))
        (is (string= secret (littoral.auth::open-totp-secret sealed "7"))))
      (let ((littoral.auth:*factor-key* (cl-base64:usb8-array-to-base64-string key)))
        (is (string= secret (littoral.auth::open-totp-secret sealed "7"))))
      (let ((littoral.auth:*factor-key* "too short"))
        (signals error (littoral.auth::factor-key))))))

(test signing-in-with-an-encrypted-secret
  (with-auth (b)
    (let* ((secret (give-totp "bob"))        ; kept before there was a key
           (littoral.auth:*factor-key* (ironclad:random-data 32))
           (bob (littoral.auth:find-user "bob")))
      (flet ((stored () (littoral.auth::factor-data (first (littoral.auth:user-factors bob "totp")))))
        (is (string= secret (stored)))
        (sign-in-as b "bob" "another passphrase")
        (fill-in b "sign-in-code" (littoral.auth:totp-code secret))
        (press b "Verify")
        (is (has-text-p b "Signed in as bob"))
        ;; Signing in encrypted it; it still works.
        (is (alexandria:starts-with-subseq "aes1:" (stored)))
        (let ((other (make-instance 'browser)))
          (visit other "/m")
          (sign-in-as other "bob" "another passphrase")
          (fill-in other "sign-in-code" (littoral.auth:totp-code secret (+ (get-universal-time) 30)))
          (press other "Verify")
          (is (has-text-p other "Signed in as bob")))
        ;; ENCRYPT-FACTOR-SECRETS does the rest at once.
        (give-totp "ada")
        (is (= 1 (littoral.auth:encrypt-factor-secrets)))
        (is (= 0 (littoral.auth:encrypt-factor-secrets)))))))

(test changing-the-factor-key
  (let* ((secret (littoral.auth:new-totp-secret))
         (old (ironclad:random-data 32))
         (new (ironclad:random-data 32))
         (sealed (let ((littoral.auth:*factor-key* old)) (littoral.auth::seal-totp-secret secret "7"))))
    (is (search (format nil "aes1:~A:" (littoral.auth::factor-key-id old)) sealed) "Names its key")
    (let ((littoral.auth:*factor-key* new))
      (signals error (littoral.auth::open-totp-secret sealed "7") "The old key is needed")
      (let ((littoral.auth:*old-factor-keys* (list (ironclad:byte-array-to-hex-string old))))
        (is (string= secret (littoral.auth::open-totp-secret sealed "7")))))
    ;; Secrets sealed before keys had ids open with whichever key fits.
    (let ((idless (cl-ppcre:regex-replace "^aes1:[0-9a-f]+:" sealed "aes1:"))
          (littoral.auth:*factor-key* new)
          (littoral.auth:*old-factor-keys* (list old)))
      (is (string= secret (littoral.auth::open-totp-secret idless "7"))))
    (let ((littoral.auth:*factor-key* "too short")
          (littoral.auth:*old-factor-keys* nil))
      (signals error (littoral.auth::factor-key)))
    (let ((littoral.auth:*old-factor-keys* (list "too short")))
      (signals error (littoral.auth::old-factor-keys)))))

(test rotating-the-factor-key
  (with-auth (b)
    (let* ((old (ironclad:random-data 32))
           (new (ironclad:random-data 32))
           (secret (give-totp "bob" :key old))
           (bob (littoral.auth:find-user "bob")))
      (flet ((stored () (littoral.auth::factor-data (first (littoral.auth:user-factors bob "totp")))))
        (is (search (littoral.auth::factor-key-id old) (stored)))
        (let ((littoral.auth:*factor-key* new)
              (littoral.auth:*old-factor-keys* (list old)))
          ;; Signing in reads it with the old key and seals it with the new one.
          (sign-in-as b "bob" "another passphrase")
          (fill-in b "sign-in-code" (littoral.auth:totp-code secret))
          (press b "Verify")
          (is (has-text-p b "Signed in as bob"))
          (is (search (littoral.auth::factor-key-id new) (stored)))
          ;; ENCRYPT-FACTOR-SECRETS moves the rest at once.
          (give-totp "ada" :key old)
          (is (= 1 (littoral.auth:encrypt-factor-secrets)))
          (is (= 0 (littoral.auth:encrypt-factor-secrets))))
        ;; Without the old key nothing changes: every secret must open first.
        (littoral.auth:add-user "carol" "carol@example.org" "a long enough passphrase")
        (give-totp "carol" :key old)
        (let ((littoral.auth:*factor-key* new) (littoral.auth:*old-factor-keys* nil))
          (signals error (littoral.auth:encrypt-factor-secrets)))
        ;; And the new key alone still signs bob in.
        (let ((littoral.auth:*factor-key* new) (littoral.auth:*old-factor-keys* nil)
              (other (make-instance 'browser)))
          (visit other "/m")
          (sign-in-as other "bob" "another passphrase")
          (fill-in other "sign-in-code" (littoral.auth:totp-code secret (+ (get-universal-time) 30)))
          (press other "Verify")
          (is (has-text-p other "Signed in as bob")))))))

(test recovery-codes
  (with-auth (b)
    (give-totp "bob")
    (let ((codes (littoral.auth:make-recovery-codes (littoral.auth:find-user "bob"))))
      (is (= 10 (length codes)))
      (is (= 10 (littoral.auth:recovery-codes-left (littoral.auth:find-user "bob"))))
      (sign-in-as b "bob" "another passphrase")
      (click b "Use a recovery code instead")
      (fill-in b "sign-in-code" (string-upcase (first codes)))
      (press b "Verify")
      (is (has-text-p b "Signed in as bob"))
      (is (= 9 (littoral.auth:recovery-codes-left (littoral.auth:find-user "bob"))))
      (is (not (littoral.auth:use-recovery-code (littoral.auth:find-user "bob") (first codes)))))))

(test setting-up-an-authenticator-app
  (with-members (b)
    (members-sign-in b "bob" "another passphrase")
    (click b "Set up an authenticator app")
    (is (search "<svg class=\"lt-qr\"" (browser-html b)))
    (let ((secret (cl-ppcre:register-groups-bind (s) ("Key: <code>([A-Z2-7]+)</code>" (browser-html b)) s)))
      (is (not (null secret)))
      (fill-in b "totp-code" (littoral.auth:totp-code secret))
      (press b "Turn on")
      (is (has-text-p b "Your authenticator app is set up."))
      (is (has-text-p b "Your recovery codes."))
      (is (has-text-p b "On: signing in with your password also asks for its code.")))))

;;; Passkeys, with an authenticator made here

(defun cbor (value)
  "VALUE as CBOR, for the few kinds WebAuthn uses."
  (flet ((head (major n)
           (cond ((< n 24) (vector (logior (ash major 5) n)))
                 ((< n 256) (vector (logior (ash major 5) 24) n))
                 (t (vector (logior (ash major 5) 25) (ash n -8) (logand n 255))))))
    (coerce
     (etypecase value
       ((integer 0) (head 0 value))
       ((integer * -1) (head 1 (- -1 value)))
       (string (let ((o (sb-ext:string-to-octets value :external-format :utf-8))) (concatenate 'vector (head 3 (length o)) o)))
       ((vector (unsigned-byte 8)) (concatenate 'vector (head 2 (length value)) value))
       (list (apply #'concatenate 'vector (head 5 (length value))
                    (loop for (k . v) in value collect (concatenate 'vector (cbor k) (cbor v))))))
     '(vector (unsigned-byte 8)))))

(defun octets (&rest parts)
  (coerce (apply #'concatenate 'vector parts) '(simple-array (unsigned-byte 8) (*))))

(defun der (raw)
  "R‖S as a DER ECDSA signature."
  (flet ((int (bytes)
           (let* ((bytes (subseq bytes (or (position-if #'plusp bytes) 31)))
                  (bytes (if (>= (aref bytes 0) #x80) (octets #(0) bytes) bytes)))
             (octets (vector 2 (length bytes)) bytes))))
    (let ((body (octets (int (subseq raw 0 32)) (int (subseq raw 32)))))
      (octets (vector #x30 (length body)) body))))

(defun client-data (type challenge &optional (origin "http://localhost"))
  (sb-ext:string-to-octets (format nil "{\"type\":~S,\"challenge\":~S,\"origin\":~S}" type challenge origin)))

(defun rp-hash () (ironclad:digest-sequence :sha256 (sb-ext:string-to-octets "localhost")))

(defun make-authenticator ()
  (multiple-value-bind (private public) (ironclad:generate-key-pair :secp256r1)
    (let ((point (getf (ironclad:destructure-public-key public) :y)))
      (list :private private :x (subseq point 1 33) :y (subseq point 33) :id (ironclad:random-data 16)))))

(defun registration-response (authenticator challenge)
  (let* ((key (cbor `((1 . 2) (3 . -7) (-1 . 1) (-2 . ,(getf authenticator :x)) (-3 . ,(getf authenticator :y)))))
         (id (getf authenticator :id))
         (data (octets (rp-hash) #(#x41) #(0 0 0 0) (make-array 16 :initial-element 0)
                       (vector (ash (length id) -8) (logand (length id) 255)) id key)))
    (format nil "{\"id\":~S,\"response\":{\"clientDataJSON\":~S,\"attestationObject\":~S}}"
            (littoral.auth::b64url-encode id)
            (littoral.auth::b64url-encode (client-data "webauthn.create" challenge))
            (littoral.auth::b64url-encode (cbor `(("fmt" . "none") ("attStmt") ("authData" . ,data)))))))

(defun assertion-response (authenticator challenge count &key (origin "http://localhost") tamper (verified t))
  (let* ((data (octets (rp-hash) (vector (if verified 5 1)) (vector 0 0 0 count)))
         (client (client-data "webauthn.get" challenge origin))
         (signature (ironclad:sign-message (getf authenticator :private)
                                           (ironclad:digest-sequence :sha256 (octets data (ironclad:digest-sequence :sha256 client))))))
    (when tamper (setf (aref data 36) (logxor 1 (aref data 36))))
    (com.inuoe.jzon:parse
     (format nil "{\"id\":~S,\"response\":{\"clientDataJSON\":~S,\"authenticatorData\":~S,\"signature\":~S}}"
             (littoral.auth::b64url-encode (getf authenticator :id))
             (littoral.auth::b64url-encode client) (littoral.auth::b64url-encode data)
             (littoral.auth::b64url-encode (der signature))))))

(test passkeys-register-and-sign-in
  (with-auth (b)
    (let ((*request* (lack/request:make-request (make-env :get "/m")))
          (bob (littoral.auth:find-user "bob"))
          (authenticator (make-authenticator)))
      (littoral.auth:add-passkey bob "reg-challenge" (registration-response authenticator "reg-challenge"))
      (is (= 1 (length (littoral.auth:user-factors bob "passkey"))))
      (is (littoral.auth:second-factor-p bob))
      (is (string= (littoral.auth::b64url-encode (getf authenticator :id))
                   (littoral.auth::factor-credential-id (first (littoral.auth:user-factors bob "passkey")))))
      ;; Signing in: the right user, and the count moves on.
      (is (string= "bob" (littoral.auth:user-name
                          (littoral.auth:verify-assertion "c1" (assertion-response authenticator "c1" 1)))))
      ;; Replayed (the count didn't go up), the wrong challenge, origin, or data: refused.
      (signals littoral.auth:passkey-error (littoral.auth:verify-assertion "c2" (assertion-response authenticator "c2" 1)))
      (signals littoral.auth:passkey-error (littoral.auth:verify-assertion "c3" (assertion-response authenticator "other" 5)))
      (signals littoral.auth:passkey-error
        (littoral.auth:verify-assertion "c4" (assertion-response authenticator "c4" 6 :origin "https://evil.example")))
      (signals littoral.auth:passkey-error
        (littoral.auth:verify-assertion "c5" (assertion-response authenticator "c5" 7 :tamper t)))
      ;; Another user's passkey doesn't sign in as Ada.
      (signals littoral.auth:passkey-error
        (littoral.auth:verify-assertion "c6" (assertion-response authenticator "c6" 8) (littoral.auth:find-user "ada")))
      ;; Alone, a passkey must have verified the user; after Bob's password, his presence is enough.
      (signals littoral.auth:passkey-error
        (littoral.auth:verify-assertion "c8" (assertion-response authenticator "c8" 9 :verified nil)))
      (is (string= "bob" (littoral.auth:user-name
                          (littoral.auth:verify-assertion "c9" (assertion-response authenticator "c9" 10 :verified nil) bob))))
      (is (search "\"userVerification\":\"required\"" (littoral.auth::assertion-options "c")))
      (is (search "\"userVerification\":\"preferred\"" (littoral.auth::assertion-options "c" bob)))
      ;; An unknown key.
      (signals littoral.auth:passkey-error
        (littoral.auth:verify-assertion "c7" (assertion-response (make-authenticator) "c7" 1)))
      ;; A registration for the wrong challenge.
      (signals littoral.auth:passkey-error
        (littoral.auth:add-passkey bob "expected" (registration-response (make-authenticator) "something-else"))))))
