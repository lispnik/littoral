;;;; passwords.lisp — hashing passwords, and checking hashes in other formats
;;;;
;;;; New hashes are Littoral's own: PBKDF2-SHA256 with *PBKDF2-ITERATIONS*,
;;;; written as ironclad's "PBKDF2$SHA256:210000$salt$hash".  VERIFY-PASSWORD
;;;; also checks hashes made elsewhere, so an existing users table keeps
;;;; working:
;;;;
;;;;   $2a$ $2b$ $2y$ …                  bcrypt (Rails, Laravel, Node, PHP)
;;;;   pbkdf2_sha256$iterations$salt$b64  Django (pbkdf2_sha1 too)
;;;;   pbkdf2:sha256:iterations$salt$hex  Werkzeug and Flask (sha1, sha512 too)
;;;;
;;;; PASSWORD-NEEDS-REHASH-P is true for any of those, and for Littoral hashes
;;;; with fewer iterations than now: signing in re-hashes them where the
;;;; store can write.

(in-package #:littoral.auth)

(defvar *pbkdf2-iterations* 210000
  "PBKDF2-SHA256 iterations for new password hashes (OWASP's 2023 advice).
Hashes with fewer are upgraded when their owner next signs in.")

(defun octets (string)
  (sb-ext:string-to-octets string :external-format :utf-8))

(defun hash-password (password)
  "A new hash of PASSWORD: salted PBKDF2-SHA256, as one string."
  (ironclad:pbkdf2-hash-password-to-combined-string
   (octets password) :digest :sha256 :iterations *pbkdf2-iterations*))

(defun constant-time-equal (a b)
  (and (= (length a) (length b)) (ironclad:constant-time-equal a b)))

;;; bcrypt

(defparameter +bcrypt-alphabet+
  "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  "bcrypt's own base-64 alphabet, without padding.")

(defun bcrypt-decode (string count)
  "The first COUNT bytes STRING encodes in bcrypt's base 64."
  (let ((bits 0) (nbits 0) (out (make-array count :element-type '(unsigned-byte 8) :fill-pointer 0)))
    (loop for char across string
          for value = (position char +bcrypt-alphabet+)
          do (unless value (return-from bcrypt-decode nil))
             (setf bits (logior (ash bits 6) value) nbits (+ nbits 6))
             (when (>= nbits 8)
               (decf nbits 8)
               (vector-push (ldb (byte 8 nbits) bits) out)
               (setf bits (ldb (byte nbits 0) bits))
               (when (= (fill-pointer out) count) (loop-finish))))
    (and (= (fill-pointer out) count)
         (coerce out '(simple-array (unsigned-byte 8) (*))))))

(defun bcrypt-encode (octets)
  "OCTETS in bcrypt's base 64, without padding."
  (with-output-to-string (out)
    (let ((bits 0) (nbits 0))
      (loop for byte across octets
            do (setf bits (logior (ash bits 8) byte) nbits (+ nbits 8))
               (loop while (>= nbits 6)
                     do (decf nbits 6)
                        (write-char (char +bcrypt-alphabet+ (ldb (byte 6 nbits) bits)) out)
                        (setf bits (ldb (byte nbits 0) bits))))
      (when (plusp nbits)
        (write-char (char +bcrypt-alphabet+ (ash bits (- 6 nbits))) out)))))

(defun bcrypt-raw (password salt cost)
  "The 23 bytes of the bcrypt hash of PASSWORD (a string) with SALT (16
bytes) and COST.  The key is the password's UTF-8 bytes and a NUL, cut to
72 bytes, as every bcrypt does.  Built from ironclad's Blowfish and EksBlowfish
setup; ironclad's own bcrypt KDF can't take a 72-byte key without the NUL."
  (let* ((bytes (octets password))
         (key (coerce (subseq (concatenate 'vector bytes #(0)) 0 (min 72 (1+ (length bytes))))
                      '(simple-array (unsigned-byte 8) (*))))
         (p-array (copy-seq crypto::+p-array+))
         (s-boxes (concatenate '(simple-array (unsigned-byte 32) (1024))
                               crypto::+s-box-0+ crypto::+s-box-1+ crypto::+s-box-2+ crypto::+s-box-3+))
         (hash (coerce (map 'vector #'char-code "OrpheanBeholderScryDoubt")
                       '(simple-array (unsigned-byte 8) (24)))))
    (crypto::bcrypt-expand-key key salt p-array s-boxes)
    (dotimes (i (expt 2 cost))
      (crypto::initialize-blowfish-vectors key p-array s-boxes)
      (crypto::initialize-blowfish-vectors salt p-array s-boxes))
    (dotimes (i 64)
      (crypto::blowfish-encrypt-block* p-array s-boxes hash 0 hash 0)
      (crypto::blowfish-encrypt-block* p-array s-boxes hash 8 hash 8)
      (crypto::blowfish-encrypt-block* p-array s-boxes hash 16 hash 16))
    (subseq hash 0 23)))

(defun bcrypt-hash (password &key (cost 12) (salt (ironclad:random-data 16)))
  "A $2b$ bcrypt hash of PASSWORD, for seeding a table that expects them."
  (format nil "$2b$~2,'0D$~A~A" cost (subseq (bcrypt-encode salt) 0 22)
          (subseq (bcrypt-encode (bcrypt-raw password salt cost)) 0 31)))

(defun verify-bcrypt (password hash)
  (cl-ppcre:register-groups-bind ((#'parse-integer cost) salt digest)
      ("^\\$2[aby]\\$(\\d\\d)\\$([./A-Za-z0-9]{22})([./A-Za-z0-9]{31})$" hash)
    (let ((salt-octets (bcrypt-decode salt 16))
          (expected (bcrypt-decode digest 23)))
      (and salt-octets expected (<= 4 cost 31)
           (constant-time-equal (bcrypt-raw password salt-octets cost) expected)))))

;;; PBKDF2 as Django and Werkzeug write it

(defun digest-keyword (name)
  (cdr (assoc name '(("sha1" . :sha1) ("sha256" . :sha256) ("sha512" . :sha512)) :test #'string=)))

(defun pbkdf2-matches-p (password digest salt iterations expected)
  (and digest (plusp iterations) (< iterations 10000000)
       (constant-time-equal (ironclad:pbkdf2-hash-password (octets password) :salt (octets salt)
                                                          :digest digest :iterations iterations)
                            expected)))

(defun verify-django (password hash)
  (cl-ppcre:register-groups-bind (algorithm (#'parse-integer iterations) salt digest)
      ("^pbkdf2_(sha1|sha256)\\$(\\d+)\\$([^$]+)\\$([A-Za-z0-9+/=]+)$" hash)
    (let ((expected (ignore-errors (cl-base64:base64-string-to-usb8-array digest))))
      (and expected (pbkdf2-matches-p password (digest-keyword algorithm) salt iterations expected)))))

(defun verify-werkzeug (password hash)
  (cl-ppcre:register-groups-bind (algorithm (#'parse-integer iterations) salt digest)
      ("^pbkdf2:(sha1|sha256|sha512):(\\d+)\\$([^$]+)\\$([0-9a-f]+)$" hash)
    (let ((expected (ignore-errors (ironclad:hex-string-to-byte-array digest))))
      (and expected (pbkdf2-matches-p password (digest-keyword algorithm) salt iterations expected)))))

;;; Any of them

(defun verify-password (password hash)
  "True when PASSWORD matches HASH, in Littoral's own format, bcrypt, or
Django's or Werkzeug's PBKDF2.  False for anything else, never an error."
  (and (stringp password) (stringp hash)
       (ignore-errors
        (cond ((alexandria:starts-with-subseq "PBKDF2$" hash)
               (ironclad:pbkdf2-check-password (octets password) hash))
              ((alexandria:starts-with-subseq "$2" hash) (verify-bcrypt password hash))
              ((alexandria:starts-with-subseq "pbkdf2_" hash) (verify-django password hash))
              ((alexandria:starts-with-subseq "pbkdf2:" hash) (verify-werkzeug password hash))))))

(defun password-needs-rehash-p (hash)
  "True unless HASH is Littoral's PBKDF2-SHA256 with at least *PBKDF2-ITERATIONS*."
  (not (cl-ppcre:register-groups-bind ((#'parse-integer iterations))
           ("^PBKDF2\\$SHA256:(\\d+)\\$" (string-upcase hash))
         (>= iterations *pbkdf2-iterations*))))
