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

(defun give-totp (name)
  "Give the user NAME an authenticator app; its secret."
  (let ((user (littoral.auth:find-user name))
        (secret (littoral.auth:new-totp-secret)))
    (littoral.db:db-insert (make-instance 'littoral.auth::auth-factor :user-id (princ-to-string (littoral.auth:user-id user))
                                                                      :kind "totp" :name "App" :data secret :counter 0
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

(defun assertion-response (authenticator challenge count &key (origin "http://localhost") tamper)
  (let* ((data (octets (rp-hash) #(1) (vector 0 0 0 count)))
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
      ;; An unknown key.
      (signals littoral.auth:passkey-error
        (littoral.auth:verify-assertion "c7" (assertion-response (make-authenticator) "c7" 1)))
      ;; A registration for the wrong challenge.
      (signals littoral.auth:passkey-error
        (littoral.auth:add-passkey bob "expected" (registration-response (make-authenticator) "something-else"))))))
