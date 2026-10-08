;;;; passwords.lisp — hash formats, checked against hashes made elsewhere
;;;;
;;;; The bcrypt hashes come from Apache's htpasswd -B; the PBKDF2 ones from
;;;; Python's hashlib in Django's and Werkzeug's formats.

(in-package #:littoral/tests)

(def-suite passwords :in littoral)
(in-suite passwords)

(defparameter *password-vectors*
  `(("" "$2y$05$jyKugthfqw9X1Yu52diqGuW4jT1JZkF/lfbyx8wjyOhSXCmxF1K1.")
    ("a" "$2y$05$qIyIv16iytAnmHr.VRhJ..06yPeFJ59pjxwPvzJlSxSYBcxSVfveK")
    ("correct horse battery" "$2y$05$T7OPatK04IMwx3P0pJn6ZeUJ1qekAZjnVICWktxhQXD8hahCETPG.")
    ("Ünïcödé pässwörd" "$2y$05$2XzMhnCkFOVCk75Fz2tm6.g7YsQDOsV8LG2/mTyjlridRcMaMPyBW")
    (,(make-string 71 :initial-element #\x) "$2y$05$FHu31k2DMY/z2v01mSMpZunvU08eEIqgaTJtqrLK93TS60XO2arAG")
    (,(make-string 72 :initial-element #\y) "$2y$05$kzq9ErEiItAWGzq3Zpfp6uw6BckC0/GRrIPJwDHiWYkdHPiwAiV6m")
    (,(make-string 80 :initial-element #\z) "$2y$05$HhUlaIzrjY4cnBTOASybYeTbEZs8SRjZ.Qkf9wY.tQa/qyCUbVpPi")
    ("correct horse battery" "pbkdf2_sha256$1000$seasalt1234$dVCseRolHWXn3dKCrJlqQnEHNpty/gC2g6pUYtCGT/4=")
    ("correct horse battery" "pbkdf2:sha256:1000$seasalt1234$7550ac791a251d65e7ddd282ac996a427107369b72fe00b683aa5462d0864ffe")
    ("Ünïcödé" "pbkdf2_sha256$2000$s4lt$p8GzQyGNnf0jK8SrSaDNFStSyncl6+QKqcBkWdE/+V8=")
    ("Ünïcödé" "pbkdf2:sha256:2000$s4lt$a7c1b343218d9dfd232bc4ab49a0cd152b52ca7725ebe40aa9c06459d13ff95f")))

(test hashes-made-elsewhere-verify
  (loop for (password hash) in *password-vectors*
        do (is (littoral.auth:verify-password password hash) "~S should match ~A" password hash)
           ;; (Past 72 bytes bcrypt ignores the rest, so "!" changes nothing there.)
           (when (< (length password) 72)
             (is (not (littoral.auth:verify-password (concatenate 'string password "!") hash))))))

(test bcrypt-cuts-at-72-bytes
  ;; As every bcrypt does: an 80-character password matches its first 72.
  (is (littoral.auth:verify-password (make-string 72 :initial-element #\z)
                                     "$2y$05$HhUlaIzrjY4cnBTOASybYeTbEZs8SRjZ.Qkf9wY.tQa/qyCUbVpPi"))
  (is (not (littoral.auth:verify-password (make-string 71 :initial-element #\z)
                                          "$2y$05$HhUlaIzrjY4cnBTOASybYeTbEZs8SRjZ.Qkf9wY.tQa/qyCUbVpPi"))))

(test littorals-own-hashes
  (let ((hash (littoral.auth:hash-password "s3cret pass")))
    (is (alexandria:starts-with-subseq "PBKDF2$SHA256:1000$" hash))
    (is (littoral.auth:verify-password "s3cret pass" hash))
    (is (not (littoral.auth:verify-password "s3cret Pass" hash)))
    (is (not (littoral.auth:password-needs-rehash-p hash)))
    (let ((littoral.auth:*pbkdf2-iterations* 5000))
      (is (littoral.auth:password-needs-rehash-p hash))))
  (let ((bcrypt (littoral.auth:bcrypt-hash "made here" :cost 4)))
    (is (cl-ppcre:scan "^\\$2b\\$04\\$[./A-Za-z0-9]{53}$" bcrypt))
    (is (littoral.auth:verify-password "made here" bcrypt))
    (is (littoral.auth:password-needs-rehash-p bcrypt))))

(test garbage-never-matches-or-signals
  (dolist (hash '("" "plain text" "$2y$05$short" "$2y$99$jyKugthfqw9X1Yu52diqGuW4jT1JZkF/lfbyx8wjyOhSXCmxF1K1."
                  "pbkdf2_sha256$x$salt$hash" "pbkdf2:md5:1000$salt$00" "PBKDF2$nonsense" nil 42))
    (is (not (littoral.auth:verify-password "" hash)))
    (is (not (littoral.auth:verify-password "password" hash)))))
