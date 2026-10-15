;;;; Examples for littoral.auth: hashing passwords and checking hashes made elsewhere.

;;;; Example: littoral.auth:hash-password littoral.auth:verify-password
;;; A new hash is salted, so hashing the same password twice gives different strings; each verifies.
(let ((littoral.auth:*pbkdf2-iterations* 1000))
  (let ((one (littoral.auth:hash-password "correct horse battery"))
        (two (littoral.auth:hash-password "correct horse battery")))
    (list (subseq one 0 19)
          (string= one two)
          (littoral.auth:verify-password "correct horse battery" one)
          (littoral.auth:verify-password "Correct horse battery" one))))
;; ⇒ ("PBKDF2$SHA256:1000$" NIL T NIL)

;;;; Example: littoral.auth:verify-password
;;; Hashes from other frameworks verify too: here Werkzeug's (Flask) and Django's PBKDF2.  Anything else is simply false.
(list (littoral.auth:verify-password
       "correct horse battery"
       "pbkdf2:sha256:1000$seasalt1234$7550ac791a251d65e7ddd282ac996a427107369b72fe00b683aa5462d0864ffe")
      (littoral.auth:verify-password
       "correct horse battery"
       "pbkdf2_sha256$1000$seasalt1234$dVCseRolHWXn3dKCrJlqQnEHNpty/gC2g6pUYtCGT/4=")
      (littoral.auth:verify-password "correct horse battery" "plain text")
      (littoral.auth:verify-password "correct horse battery" nil))
;; ⇒ (T T NIL NIL)

;;;; Example: littoral.auth:bcrypt-hash
;;; A bcrypt hash, as Rails, Laravel or PHP make them, for seeding a table an older application also reads.  COST 4 is the quickest bcrypt allows.
(let ((hash (littoral.auth:bcrypt-hash "made here" :cost 4)))
  (list (subseq hash 0 7)
        (length hash)
        (littoral.auth:verify-password "made here" hash)))
;; ⇒ ("$2b$04$" 60 T)

;;;; Example: littoral.auth:password-needs-rehash-p littoral.auth:*pbkdf2-iterations*
;;; False only for Littoral's own hashes with at least *PBKDF2-ITERATIONS*: a hash made with fewer, or in another format, is upgraded when its owner next signs in.
(let ((hash (let ((littoral.auth:*pbkdf2-iterations* 1000))
              (littoral.auth:hash-password "s3cret pass"))))
  (list (let ((littoral.auth:*pbkdf2-iterations* 1000))
          (littoral.auth:password-needs-rehash-p hash))
        (let ((littoral.auth:*pbkdf2-iterations* 5000))
          (littoral.auth:password-needs-rehash-p hash))
        (littoral.auth:password-needs-rehash-p (littoral.auth:bcrypt-hash "s3cret pass" :cost 4))))
;; ⇒ (NIL T T)

;;;; Example: littoral.auth:*rehash-on-sign-in*
;;; Signing in re-hashes a weaker hash, where the store can write; binding it to NIL leaves hashes as they are.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:"))
      (littoral.auth:*pbkdf2-iterations* 1000))
  (littoral.auth:create-auth-tables)
  (let ((ada (littoral.auth:add-user "ada" "ada@example.org" "correct horse battery")))
    (littoral.auth:store-set-password-hash littoral.auth:*user-store* ada
                                           (littoral.auth:bcrypt-hash "correct horse battery" :cost 4))
    (let ((littoral.auth:*rehash-on-sign-in* nil))
      (littoral.auth:authenticate "ada" "correct horse battery"))
    (let ((kept (subseq (littoral.auth:user-password-hash (littoral.auth:find-user "ada")) 0 4)))
      (littoral.auth:authenticate "ada" "correct horse battery")
      (list kept (subseq (littoral.auth:user-password-hash (littoral.auth:find-user "ada")) 0 7)))))
;; ⇒ ("$2b$" "PBKDF2$")
