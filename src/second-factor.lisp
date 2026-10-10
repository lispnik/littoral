;;;; second-factor.lisp — authenticator apps, recovery codes and passkeys
;;;;
;;;; A user may add, from SECURITY-SETTINGS:
;;;;   - an authenticator app (TOTP, RFC 6238): signing in with a password
;;;;     then asks for its six-digit code;
;;;;   - passkeys (WebAuthn): sign in with one alone, or use it as the second
;;;;     step after a password;
;;;;   - recovery codes, ten single-use codes for when the others are lost.
;;;; Second factors live in the auth_factors table, recovery codes (hashed)
;;;; in auth_tokens.  Passkeys are checked here: the browser's response is
;;;; parsed (CBOR), its challenge, origin and relying party matched, and its
;;;; ES256 signature verified.

(in-package #:littoral.auth)

(defclass auth-factor (persistent)
  ((user-id :initarg :user-id :initform nil :reader factor-user-id)
   (kind :initarg :kind :initform nil :reader factor-kind :documentation "\"totp\" or \"passkey\".")
   (name :initarg :name :initform nil :accessor factor-name)
   (data :initarg :data :initform nil :accessor factor-data
         :documentation "A TOTP secret (base 32), or a passkey's id and public key.")
   (counter :initarg :counter :initform 0 :accessor factor-counter
            :documentation "The last TOTP time step used, or the passkey's signature count.")
   (created :initarg :created :initform nil :reader factor-created))
  (:documentation "A second way for a user to prove who they are."))

(define-description auth-factor
  ((user-id) (kind) (name) (data :type :text) (counter :type :integer) (created :type :integer)))

(define-table auth-factor :name "auth_factors")

(defun user-factors (user &optional kind)
  "USER's second factors, oldest first, of KIND (\"totp\", \"passkey\") if given."
  (db-select 'auth-factor :where (if kind "user_id = ? AND kind = ?" "user_id = ?")
                          :params (if kind (list (princ-to-string (user-id user)) kind)
                                      (list (princ-to-string (user-id user))))))

(defun second-factor-p (user)
  "True when signing in as USER with a password needs a second step."
  (and (user-factors user) t))

;;; Base 32 (RFC 4648), for TOTP secrets

(defparameter +base32+ "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

(defun base32-encode (octets)
  (with-output-to-string (out)
    (let ((bits 0) (count 0))
      (loop for byte across octets
            do (setf bits (logior (ash bits 8) byte) count (+ count 8))
               (loop while (>= count 5)
                     do (decf count 5)
                        (write-char (char +base32+ (ldb (byte 5 count) bits)) out)
                        (setf bits (ldb (byte count 0) bits))))
      (when (plusp count)
        (write-char (char +base32+ (ash bits (- 5 count))) out)))))

(defun base32-decode (string)
  (let ((bits 0) (count 0) (out (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (loop for char across (remove-if (lambda (c) (member c '(#\Space #\- #\=))) (string-upcase string))
          for value = (position char +base32+)
          do (unless value (error "Not base 32: ~S" string))
             (setf bits (logior (ash bits 5) value) count (+ count 5))
             (when (>= count 8)
               (decf count 8)
               (vector-push-extend (ldb (byte 8 count) bits) out)
               (setf bits (ldb (byte count 0) bits))))
    (coerce out '(simple-array (unsigned-byte 8) (*)))))

;;; TOTP

(defparameter *totp-step* 30 "Seconds a TOTP code lasts.")

(defun hotp (key counter &key (digits 6))
  "The HOTP code (RFC 4226) of KEY (octets) for COUNTER, as a string of DIGITS."
  (let* ((message (let ((m (make-array 8 :element-type '(unsigned-byte 8))))
                    (loop for i from 7 downto 0 for c = counter then (ash c -8)
                          do (setf (aref m i) (ldb (byte 8 0) c)))
                    m))
         (mac (let ((h (ironclad:make-hmac key :sha1))) (ironclad:update-hmac h message) (ironclad:hmac-digest h)))
         (offset (logand (aref mac 19) #xF))
         (number (logand (logior (ash (aref mac offset) 24) (ash (aref mac (+ offset 1)) 16)
                                 (ash (aref mac (+ offset 2)) 8) (aref mac (+ offset 3)))
                         #x7FFFFFFF)))
    (format nil "~v,'0D" digits (mod number (expt 10 digits)))))

(defun unix-time (&optional (universal-time (get-universal-time)))
  (- universal-time (encode-universal-time 0 0 0 1 1 1970 0)))

(defun totp-step (&optional (universal-time (get-universal-time)))
  (floor (unix-time universal-time) *totp-step*))

(defun totp-code (secret &optional (universal-time (get-universal-time)))
  "The six-digit code SECRET (base 32) gives now."
  (hotp (base32-decode secret) (totp-step universal-time)))

(defun verify-totp (secret code &key (after -1) (universal-time (get-universal-time)))
  "The time step at which CODE is SECRET's, within one step either way and
later than AFTER (so a code works once), or NIL."
  (let ((code (remove #\Space code))
        (step (totp-step universal-time))
        (key (base32-decode secret)))
    (loop for s from (1- step) to (1+ step)
          when (and (> s after) (string= code (hotp key s)))
            return s)))

(defun new-totp-secret ()
  (base32-encode (ironclad:random-data 20)))

(defun totp-uri (secret account issuer)
  "The otpauth:// address an authenticator app reads, from a QR code or a link."
  (format nil "otpauth://totp/~A:~A?secret=~A&issuer=~A&algorithm=SHA1&digits=6&period=~D"
          (quri:url-encode issuer) (quri:url-encode account) secret (quri:url-encode issuer) *totp-step*))

(defun qr-svg (text &key (module 4) (label "QR code"))
  "TEXT as a QR code, inline SVG."
  (let* ((code (clqr:encode text :error-correction :m))
         (size (clqr:qr-size code))
         (margin 4)
         (total (+ size (* 2 margin))))
    (with-output-to-string (out)
      (format out "<svg class=\"lt-qr\" viewBox=\"0 0 ~D ~D\" width=\"~D\" height=\"~D\" role=\"img\" aria-label=\"~A\" shape-rendering=\"crispEdges\"><rect width=\"100%\" height=\"100%\" fill=\"#fff\"/><path fill=\"#000\" d=\""
              total total (* total module) (* total module) (littoral.html:html-escape label))
      (dotimes (i size)
        (dotimes (j size)
          (when (clqr:qr-module code i j)
            (format out "M~D ~Dh1v1h-1z" (+ j margin) (+ i margin)))))
      (format out "\"/></svg>"))))

;;; Recovery codes

(defun make-recovery-codes (user &key (count 10))
  "Ten new single-use recovery codes for USER, replacing any others; only
their hashes are kept, so show them once."
  (db-execute "DELETE FROM auth_tokens WHERE user_id = ? AND purpose = ?" (princ-to-string (user-id user)) "recovery")
  (loop repeat count
        collect (let ((code (string-downcase (format nil "~A-~A" (subseq (base32-encode (ironclad:random-data 5)) 0 5)
                                                     (subseq (base32-encode (ironclad:random-data 5)) 0 5)))))
                  (db-insert (make-instance 'auth-token :token-hash (token-hash code) :purpose "recovery"
                                                        :user-id (princ-to-string (user-id user))))
                  code)))

(defun recovery-codes-left (user)
  (length (db-query "SELECT id FROM auth_tokens WHERE user_id = ? AND purpose = ?"
                    (princ-to-string (user-id user)) "recovery")))

(defun use-recovery-code (user code)
  "True, using it up, when CODE is one of USER's recovery codes."
  (plusp (db-execute "DELETE FROM auth_tokens WHERE user_id = ? AND purpose = ? AND token_hash = ?"
                     (princ-to-string (user-id user)) "recovery"
                     (token-hash (string-downcase (string-trim " " code))))))

;;; CBOR, as much as WebAuthn needs

(defun cbor-decode (octets &optional (start 0))
  "The CBOR item at START in OCTETS, and where the next begins.  Maps become
alists, byte strings octet vectors."
  (let* ((initial (aref octets start))
         (major (ash initial -5))
         (info (logand initial 31))
         (position (1+ start)))
    (flet ((argument ()
             (cond ((< info 24) info)
                   ((<= info 27)
                    (let ((size (expt 2 (- info 24))) (value 0))
                      (dotimes (i size) (setf value (logior (ash value 8) (aref octets (+ position i)))))
                      (incf position size)
                      value))
                   (t (error "CBOR: indefinite lengths aren't supported")))))
      (let ((n (argument)))
        (ecase major
          (0 (values n position))
          (1 (values (- -1 n) position))
          (2 (values (subseq octets position (+ position n)) (+ position n)))
          (3 (values (sb-ext:octets-to-string octets :start position :end (+ position n) :external-format :utf-8)
                     (+ position n)))
          (4 (let ((items '()))
               (dotimes (i n) (multiple-value-bind (item next) (cbor-decode octets position)
                                (push item items) (setf position next)))
               (values (nreverse items) position)))
          (5 (let ((pairs '()))
               (dotimes (i n)
                 (multiple-value-bind (key next) (cbor-decode octets position)
                   (multiple-value-bind (value after) (cbor-decode octets next)
                     (push (cons key value) pairs) (setf position after))))
               (values (nreverse pairs) position)))
          (6 (cbor-decode octets position))
          (7 (values (case n (20 :false) (21 t) (22 :null) (t :undefined)) position)))))))

;;; Base 64 URL, as WebAuthn writes binary

(defun b64url-encode (octets)
  (string-right-trim "=" (substitute #\_ #\/ (substitute #\- #\+ (cl-base64:usb8-array-to-base64-string octets)))))

(defun b64url-decode (string)
  (let ((s (substitute #\/ #\_ (substitute #\+ #\- string))))
    (cl-base64:base64-string-to-usb8-array
     (concatenate 'string s (make-string (mod (- 4 (mod (length s) 4)) 4) :initial-element #\=)))))

;;; WebAuthn

(define-condition passkey-error (error)
  ((reason :initarg :reason :reader passkey-error-reason))
  (:report (lambda (c s) (format s "Passkey refused: ~A" (passkey-error-reason c)))))

(defun refuse (reason &rest arguments)
  (error 'passkey-error :reason (apply #'format nil reason arguments)))

(defun expected-origin ()
  "This site's origin, as browsers will report it: *PUBLIC-URL* when set,
else the request's own.  (The browser itself reports the true origin, so a
forged Host header can't make a passkey work elsewhere.)"
  (if *public-url*
      (let ((uri (quri:uri *public-url*)))
        (format nil "~A://~A~@[:~D~]" (quri:uri-scheme uri) (quri:uri-host uri)
                (let ((port (quri:uri-port uri)))
                  (and port (not (eql port (if (string= (quri:uri-scheme uri) "https") 443 80))) port))))
      (let ((headers (lack/request:request-headers *request*)))
        (format nil "~A://~A" (if (littoral::secure-request-p) "https" "http")
                (or (and *trust-forwarded-for* (gethash "x-forwarded-host" headers))
                    (gethash "host" headers) "localhost")))))

(defun rp-id ()
  "The relying party id: this site's host name, without port."
  (or (quri:uri-host (quri:uri (expected-origin))) "localhost"))

(defun new-challenge () (b64url-encode (ironclad:random-data 32)))

(defun json-escape (string) (littoral::json-string string))

(defun registration-options (user challenge)
  "The JSON options for navigator.credentials.create, binary fields in base 64 URL."
  (format nil "{\"challenge\":~A,\"rp\":{\"name\":~A,\"id\":~A},\"user\":{\"id\":~A,\"name\":~A,\"displayName\":~A},~
\"pubKeyCredParams\":[{\"type\":\"public-key\",\"alg\":-7}],\"timeout\":60000,\"attestation\":\"none\",~
\"authenticatorSelection\":{\"residentKey\":\"preferred\",\"userVerification\":\"preferred\"},\"excludeCredentials\":[~{~A~^,~}]}"
          (json-escape challenge)
          (json-escape (or (and *application* (application-title *application*)) (rp-id)))
          (json-escape (rp-id))
          (json-escape (b64url-encode (sb-ext:string-to-octets (princ-to-string (user-id user)) :external-format :utf-8)))
          (json-escape (user-name user)) (json-escape (user-name user))
          (mapcar (lambda (f) (format nil "{\"type\":\"public-key\",\"id\":~A}" (json-escape (passkey-id f))))
                  (user-factors user "passkey"))))

(defun assertion-options (challenge &optional user)
  "The JSON options for navigator.credentials.get: USER's passkeys, or any
passkey for this site when USER is NIL (signing in without a name)."
  (format nil "{\"challenge\":~A,\"rpId\":~A,\"timeout\":60000,\"userVerification\":\"preferred\",\"allowCredentials\":[~{~A~^,~}]}"
          (json-escape challenge) (json-escape (rp-id))
          (and user (mapcar (lambda (f) (format nil "{\"type\":\"public-key\",\"id\":~A}" (json-escape (passkey-id f))))
                            (user-factors user "passkey")))))

(defun check-client-data (client-data-json type challenge)
  (let ((client (com.inuoe.jzon:parse (sb-ext:octets-to-string client-data-json :external-format :utf-8))))
    (unless (equal (gethash "type" client) type) (refuse "it isn't a ~A response" type))
    (unless (equal (gethash "challenge" client) challenge) (refuse "the challenge doesn't match"))
    (unless (equal (gethash "origin" client) (expected-origin))
      (refuse "it comes from ~A, not ~A" (gethash "origin" client) (expected-origin)))))

(defun check-authenticator-data (data)
  "Check DATA's relying party and user presence; its flags and signature count."
  (unless (>= (length data) 37) (refuse "the authenticator data is short"))
  (unless (equalp (subseq data 0 32)
                  (ironclad:digest-sequence :sha256 (sb-ext:string-to-octets (rp-id) :external-format :utf-8)))
    (refuse "it is for another site"))
  (let ((flags (aref data 32)))
    (unless (logbitp 0 flags) (refuse "no user was present"))
    (values flags (logior (ash (aref data 33) 24) (ash (aref data 34) 16) (ash (aref data 35) 8) (aref data 36)))))

(defun cose-key (alist)
  "The (X . Y) of an ES256 COSE key."
  (unless (and (eql (cdr (assoc 3 alist)) -7) (eql (cdr (assoc 1 alist)) 2) (eql (cdr (assoc -1 alist)) 1))
    (refuse "only ES256 (P-256) keys are accepted"))
  (cons (cdr (assoc -2 alist)) (cdr (assoc -3 alist))))

(defun verify-registration (challenge client-data-b64 attestation-b64)
  "Check a navigator.credentials.create response: (VALUES CREDENTIAL-ID X Y COUNT)."
  (let ((client-data (b64url-decode client-data-b64))
        (attestation (cbor-decode (b64url-decode attestation-b64))))
    (check-client-data client-data "webauthn.create" challenge)
    (let ((data (cdr (assoc "authData" attestation :test #'equal))))
      (unless data (refuse "there is no authenticator data"))
      (multiple-value-bind (flags count) (check-authenticator-data data)
        (unless (logbitp 6 flags) (refuse "no credential was made"))
        (let* ((id-length (logior (ash (aref data 53) 8) (aref data 54)))
               (id (subseq data 55 (+ 55 id-length)))
               (key (cose-key (cbor-decode data (+ 55 id-length)))))
          (values (b64url-encode id) (car key) (cdr key) count))))))

(defun der-to-raw (der)
  "An ECDSA signature in DER as R and S, 32 bytes each."
  (flet ((integer-at (position)
           (unless (= (aref der position) 2) (refuse "the signature is malformed"))
           (let* ((length (aref der (1+ position)))
                  (bytes (subseq der (+ position 2) (+ position 2 length)))
                  (bytes (subseq bytes (max 0 (- (length bytes) 32)))))
             (values (concatenate '(vector (unsigned-byte 8)) (make-array (- 32 (length bytes)) :initial-element 0) bytes)
                     (+ position 2 length)))))
    (unless (= (aref der 0) #x30) (refuse "the signature is malformed"))
    (multiple-value-bind (r next) (integer-at 2)
      (concatenate '(simple-array (unsigned-byte 8) (*)) r (integer-at next)))))

(defun es256-valid-p (x y message der-signature)
  "True when DER-SIGNATURE is the P-256 key (X, Y)'s on MESSAGE."
  (let ((key (ironclad:make-public-key :secp256r1
                                       :y (concatenate '(simple-array (unsigned-byte 8) (*)) #(4) x y))))
    (ironclad:verify-signature key (ironclad:digest-sequence :sha256 message) (der-to-raw der-signature))))

(defun passkey-id (factor) (first (cl-ppcre:split " " (factor-data factor))))

(defun passkey-key (factor)
  (destructuring-bind (id x y) (cl-ppcre:split " " (factor-data factor))
    (declare (ignore id))
    (values (b64url-decode x) (b64url-decode y))))

(defun verify-assertion (challenge response &optional user)
  "Check a navigator.credentials.get RESPONSE (a parsed JSON hash table); the
user it signs in, its passkey's signature count advanced."
  (let* ((id (gethash "id" response))
         (inner (gethash "response" response))
         (factor (and (stringp id)
                      (find id (db-select 'auth-factor :where "kind = ?" :params (list "passkey"))
                            :key #'passkey-id :test #'string=)))
         (owner (and factor (find-user-by-id (factor-user-id factor)))))
    (unless (and factor owner (user-active-p owner)) (refuse "that passkey isn't known here"))
    (when (and user (not (equal (princ-to-string (user-id user)) (factor-user-id factor))))
      (refuse "that passkey is someone else's"))
    (let ((client-data (b64url-decode (gethash "clientDataJSON" inner)))
          (data (b64url-decode (gethash "authenticatorData" inner)))
          (signature (b64url-decode (gethash "signature" inner))))
      (check-client-data client-data "webauthn.get" challenge)
      (multiple-value-bind (flags count) (check-authenticator-data data)
        (declare (ignore flags))
        (multiple-value-bind (x y) (passkey-key factor)
          (unless (es256-valid-p x y (concatenate '(simple-array (unsigned-byte 8) (*)) data
                                                  (ironclad:digest-sequence :sha256 client-data))
                                 signature)
            (refuse "the signature doesn't verify")))
        ;; A count that doesn't go up means a cloned authenticator (0 means it doesn't count).
        (when (and (plusp count) (<= count (factor-counter factor)))
          (refuse "the authenticator's count went backwards"))
        (setf (factor-counter factor) count)
        (db-save factor)
        owner))))

(defun add-passkey (user challenge response-json &key (name "Passkey"))
  "Keep the passkey a navigator.credentials.create response (JSON) made for USER."
  (let* ((response (com.inuoe.jzon:parse response-json))
         (inner (gethash "response" response)))
    (multiple-value-bind (id x y count)
        (verify-registration challenge (gethash "clientDataJSON" inner) (gethash "attestationObject" inner))
      (db-insert (make-instance 'auth-factor :user-id (princ-to-string (user-id user)) :kind "passkey" :name name
                                             :data (format nil "~A ~A ~A" id (b64url-encode x) (b64url-encode y))
                                             :counter count :created (get-universal-time))))))

(defun passkey-callback (function)
  "A littoral.call spec running FUNCTION with the JSON the browser sends."
  (littoral::register :action (littoral::ajax-action (littoral::%make-ajax-spec :callback function :value t))))

(defun passkey-button (mode options callback-spec label &key status-id update)
  "Write a button that runs navigator.credentials (MODE :CREATE or :GET) with
OPTIONS (JSON), then sends the response to CALLBACK-SPEC."
  (littoral::emit-tag "button" (list :type "button" :class "lt-passkey-button"
                                     :data-lt-passkey (string-downcase mode)
                                     :data-lt-passkey-options options
                                     :data-lt-passkey-callback (format nil "~A;~@[~A~]" callback-spec
                                                                       (and update (littoral:component-id update)))
                                     :data-lt-passkey-status status-id)
                      (lambda () (littoral.html:text label))))
