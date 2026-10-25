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

;;;; Example: littoral.auth:new-password-problem littoral.auth:*min-password-length*
;;; Why a new password won't do, or NIL: too short, one of the most common passwords (digits and symbols added don't help), or too easy to guess, counting the user's own name and address for little.  The reset form uses it.
(let ((littoral.db:*database* '(:sqlite3 :database-name ":memory:")))
  (littoral.auth:create-auth-tables)
  (let ((bob (littoral.auth:add-user "bob" "bob@example.org" "another passphrase")))
    (list (littoral.auth:new-password-problem "short")
          (littoral.auth:new-password-problem "Sunshine2024!")
          (littoral.auth:new-password-problem "bob-example-org" :user bob)
          (littoral.auth:new-password-problem "copper kettle at noon" :user bob)
          (let ((littoral.auth:*min-password-length* 12))
            (littoral.auth:new-password-problem "tq8#Lm2v")))))
;; ⇒ ("Passwords need at least 8 characters." "This is one of the most common passwords." "That password is too easy to guess. Avoid words from your name or email address." NIL "Passwords need at least 12 characters.")

;;;; Example: littoral.auth:breached-password-p littoral.auth:*check-breached-passwords* littoral.auth:*pwned-range-function*
;;; With *CHECK-BREACHED-PASSWORDS*, passwords Have I Been Pwned has seen in breaches are refused too.  Only the first five hex digits of the password's SHA-1 are sent; the answer lists the rest of every breached hash that starts with them.  Here a stand-in answers as the service would, for one password.
(let* ((hash (string-upcase (ironclad:byte-array-to-hex-string
                             (ironclad:digest-sequence :sha1 (sb-ext:string-to-octets "copper kettle at noon")))))
       (littoral.auth:*pwned-range-function*
         (lambda (prefix)
           (if (string= prefix (subseq hash 0 5))
               (format nil "~A:41~C~C" (subseq hash 5) #\Return #\Newline)
               "")))
       (littoral.auth:*check-breached-passwords* t))
  (list (littoral.auth:breached-password-p "copper kettle at noon")
        (littoral.auth:breached-password-p "a kettle of copper fish")
        (littoral.auth:new-password-problem "copper kettle at noon")))
;; ⇒ (T NIL "That password has appeared in a data breach; please choose another.")
