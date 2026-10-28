;;;; fuzz.lisp — random and mutated input for the code that reads what
;;;; browsers and databases send: passkey responses (CBOR, COSE, DER), the
;;;; decoders, sealed secrets, request handling, endpoints, escaping and the
;;;; SQL splitter.
;;;;
;;;; Each test draws its cases from a random state seeded with
;;;; $LITTORAL_FUZZ_SEED (fixed by default, so `make test` sees the same
;;;; cases every time; "random" picks one) and runs $LITTORAL_FUZZ_RUNS
;;;; times its usual number of cases.  `make fuzz` runs this suite alone,
;;;; with a random seed and many cases.  A failure names the seed, the run
;;;; and the input.

(in-package #:littoral/tests)

(def-suite fuzz :in littoral)
(in-suite fuzz)

;;; Drawing cases

(defvar *fuzz-seed* nil "The seed this process fuzzes with, once chosen.")

(defun fuzz-seed ()
  (or *fuzz-seed*
      (setf *fuzz-seed*
            (let ((setting (uiop:getenv "LITTORAL_FUZZ_SEED")))
              (cond ((and setting (string-equal setting "random"))
                     (let ((seed (random (expt 2 31) (make-random-state t))))
                       (format t "~&Fuzzing with LITTORAL_FUZZ_SEED=~D~%" seed)
                       seed))
                    ((and setting (ignore-errors (parse-integer setting))))
                    (t 20261028))))))

(defun fuzz-scale ()
  "How many times its usual number of cases each test runs."
  (let ((setting (uiop:getenv "LITTORAL_FUZZ_RUNS")))
    (max 1 (or (and setting (ignore-errors (parse-integer setting))) 1))))

(defvar *fuzz-state* (make-random-state t))

(defun rnd (n) (random n *fuzz-state*))
(defun chance (n) (zerop (rnd n)))
(defun pick (sequence) (elt sequence (rnd (length sequence))))

(defmacro fuzzing ((run cases) &body body)
  "BODY for RUN from 0 below CASES times FUZZ-SCALE, drawing from a random
state seeded for this test alone, so tests don't change each other's cases."
  `(let ((*fuzz-state* (sb-ext:seed-random-state (fuzz-seed))))
     (dotimes (,run (* ,cases (fuzz-scale)))
       ,@body)))

(defun fuzz-octets (vector) (coerce vector '(simple-array (unsigned-byte 8) (*))))

(defparameter *edge-bytes*
  #(0 1 2 #x17 #x18 #x19 #x1a #x1b #x1c #x1f #x20 #x30 #x3f #x40 #x41 #x5f #x60 #x7f #x80 #x81
    #x9f #xa0 #xa1 #xbf #xc0 #xd8 #xf4 #xf5 #xf6 #xf7 #xff)
  "Bytes that mean something to CBOR (lengths, types, indefinite and break), DER and UTF-8.")

(defun random-byte () (if (chance 2) (pick *edge-bytes*) (rnd 256)))

(defun random-octets (&optional (most 64))
  (fuzz-octets (loop repeat (rnd (1+ most)) collect (random-byte))))

(defun mutate-once (octets)
  (let ((n (length octets)))
    (if (zerop n)
        (random-octets 8)
        (let ((i (rnd n)))
          (ecase (rnd 7)
            (0 (let ((copy (copy-seq octets))) (setf (aref copy i) (logxor (aref copy i) (ash 1 (rnd 8)))) copy))
            (1 (let ((copy (copy-seq octets))) (setf (aref copy i) (random-byte)) copy))
            (2 (let ((at (rnd (1+ n))))       ; at the end too
                 (concatenate '(vector (unsigned-byte 8)) (subseq octets 0 at) (random-octets 8) (subseq octets at))))
            (3 (concatenate '(vector (unsigned-byte 8)) (subseq octets 0 i) (subseq octets (min n (+ i 1 (rnd 8))))))
            (4 (subseq octets 0 i))
            (5 (let ((slice (subseq octets i (min n (+ i 1 (rnd 16))))))
                 (concatenate '(vector (unsigned-byte 8)) (subseq octets 0 (rnd n)) slice (subseq octets (rnd n)))))
            ;; A length or count made huge.
            (6 (let ((copy (copy-seq octets))) (setf (aref copy i) (pick #(#x1b #x3b #x5b #x7b #x9b #xbb #xff))) copy)))))))

(defun mutate (octets)
  "OCTETS changed in one to four places: bits flipped, bytes set, inserted,
deleted, cut short, duplicated.  Never the same as OCTETS."
  (loop for changed = (fuzz-octets (let ((v octets)) (dotimes (i (1+ (rnd 4)) v) (setf v (mutate-once v)))))
        unless (equalp changed octets) return changed))

(defparameter *edge-chars*
  (concatenate 'string "<>&\"'%;=?#/\\$-*+_.:,()[]{}| " (string #\Newline) (string #\Tab) (string #\Return)
               (string (code-char 0)) (string (code-char #x7f)) (string (code-char #xe9))
               (string (code-char #x20ac)) (string (code-char #xfeff)) (string (code-char #x1f600))))

(defun random-string (&optional (most 24))
  (coerce (loop repeat (rnd (1+ most))
                collect (case (rnd 3)
                          (0 (pick *edge-chars*))
                          (1 (code-char (+ 32 (rnd 95))))
                          (t (pick "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))))
          'string))

(defun shown (thing)
  "THING for a failure message, cut short."
  (let ((text (typecase thing
                ((vector (unsigned-byte 8)) (ironclad:byte-array-to-hex-string thing))
                (t (prin1-to-string thing)))))
    (if (> (length text) 300) (concatenate 'string (subseq text 0 300) "…") text)))

(defun outcome (thunk &key (seconds 10))
  "What calling THUNK did: :RETURNED (and its value), :ERROR (and the
error), :TIMEOUT, or :SERIOUS (and the condition) for anything else that
stopped it, such as exhausting the stack, which handlers of ERROR miss."
  (handler-case (sb-ext:with-timeout seconds (values :returned (funcall thunk)))
    (sb-ext:timeout () :timeout)
    (error (e) (values :error e))
    (serious-condition (c) (values :serious c))))

(defmacro is-only-refused (form message &rest arguments)
  "Check FORM returns or signals an ERROR, and does nothing worse."
  (let ((what (gensym)) (detail (gensym)))
    `(multiple-value-bind (,what ,detail) (outcome (lambda () ,form))
       (is (member ,what '(:returned :error)) "~?: ~S ~A" ,message (list ,@arguments) ,what ,detail))))

;;; CBOR

(defun nested-cbor (depth)
  "DEPTH arrays or maps, one in another, around a zero."
  (fuzz-octets (append (loop repeat depth collect (pick #(#x81 #xa1 #xc6))) (list 0 0))))

(test fuzz-cbor-decoding
  (let ((valid (list (cbor `(("fmt" . "none") ("attStmt") ("authData" . ,(random-octets 40))))
                     (cbor '((1 . 2) (3 . -7) (-1 . 1)))
                     (cbor "text") (cbor 1000) (cbor -24))))
    (fuzzing (run 300)
      (let ((input (case (rnd 4)
                     (0 (random-octets))
                     (1 (nested-cbor (pick #(10 100 1000 100000))))
                     (t (mutate (pick valid))))))
        (multiple-value-bind (what detail) (outcome (lambda () (multiple-value-list (littoral.auth:cbor-decode input))))
          (is (member what '(:returned :error)) "seed ~D run ~D: ~S ~A on ~A" (fuzz-seed) run what detail (shown input))
          (when (eq what :returned)
            (is (<= (second detail) (length input)) "seed ~D run ~D: read past the end of ~A"
                (fuzz-seed) run (shown input))))))))

;;; ECDSA signatures in DER

(test fuzz-der-signatures
  (multiple-value-bind (private public) (ironclad:generate-key-pair :secp256r1)
    (let* ((point (getf (ironclad:destructure-public-key public) :y))
           (x (subseq point 1 33)) (y (subseq point 33))
           (message (ironclad:random-data 64)))
      (fuzzing (run 100)
        (let* ((raw (ironclad:sign-message private (ironclad:digest-sequence :sha256 message)))
               (good (der raw))
               (bad (if (chance 8) (random-octets 80) (mutate good))))
          (is (littoral.auth::es256-valid-p x y message good) "seed ~D run ~D: a good signature" (fuzz-seed) run)
          (multiple-value-bind (what detail) (outcome (lambda () (littoral.auth::es256-valid-p x y message bad)))
            (is (member what '(:returned :error)) "seed ~D run ~D: ~S ~A" (fuzz-seed) run what detail)
            ;; Only the one encoding of a signature is accepted.
            (is (not (and (eq what :returned) detail))
                "seed ~D run ~D: a changed signature verified: ~A" (fuzz-seed) run (shown bad))))))))

;;; Passkey responses

(defun fuzz-assertion (authenticator challenge count)
  "A navigator.credentials.get response's fields, as base 64 URL: id, client
data, authenticator data (user verified, COUNT as 4 bytes) and signature."
  (let* ((data (octets (rp-hash) #(5) (vector (ldb (byte 8 24) count) (ldb (byte 8 16) count)
                                              (ldb (byte 8 8) count) (ldb (byte 8 0) count))))
         (client (client-data "webauthn.get" challenge))
         (signature (ironclad:sign-message (getf authenticator :private)
                                           (ironclad:digest-sequence :sha256 (octets data (ironclad:digest-sequence :sha256 client))))))
    (list :id (getf authenticator :id) :client client :data data :signature (der signature))))

(defun assertion-table (fields)
  (let ((response (make-hash-table :test 'equal))
        (inner (make-hash-table :test 'equal)))
    (setf (gethash "id" response) (littoral.auth::b64url-encode (getf fields :id))
          (gethash "response" response) inner
          (gethash "clientDataJSON" inner) (littoral.auth::b64url-encode (getf fields :client))
          (gethash "authenticatorData" inner) (littoral.auth::b64url-encode (getf fields :data))
          (gethash "signature" inner) (littoral.auth::b64url-encode (getf fields :signature)))
    response))

(defun junk-json-value ()
  (case (rnd 6)
    (0 nil) (1 (rnd 1000000)) (2 (random-string)) (3 (vector 1 2)) (4 'null)
    (t (make-hash-table :test 'equal))))

(defun mangle-assertion (fields)
  "A parsed response made from FIELDS with one thing wrong: one field's bytes
changed, a field's value replaced by junk, or a field left out."
  (let* ((field (pick #(:id :client :data :signature))))
    (if (chance 4)
        (let* ((response (assertion-table fields))
               (inner (gethash "response" response))
               (key (pick #("id" "response" "clientDataJSON" "authenticatorData" "signature")))
               (table (if (member key '("id" "response") :test #'string=) response inner)))
          (if (chance 2) (remhash key table) (setf (gethash key table) (junk-json-value)))
          response)
        (let ((changed (copy-list fields)))
          (setf (getf changed field) (mutate (getf fields field)))
          (assertion-table changed)))))

(test fuzz-passkey-assertions
  (with-auth (b)
    (let ((*request* (lack/request:make-request (make-env :get "/m")))
          (bob (littoral.auth:find-user "bob"))
          (authenticator (make-authenticator))
          (count 0))
      (littoral.auth:add-passkey bob "reg" (registration-response authenticator "reg"))
      (fuzzing (run 40)
        (let* ((challenge (littoral.auth::new-challenge))
               (fields (fuzz-assertion authenticator challenge (incf count)))
               (response (mangle-assertion fields)))
          (multiple-value-bind (what detail)
              (outcome (lambda () (littoral.auth:verify-assertion challenge response (and (chance 2) bob))))
            (is (eq :error what) "seed ~D run ~D: a changed response gave ~S ~A" (fuzz-seed) run what detail)))
        ;; Now and then, a good one, to show the bad ones failed for being bad.
        (when (zerop (mod run 10))
          (let ((challenge (littoral.auth::new-challenge)))
            (is (equal "bob" (littoral.auth:user-name
                              (littoral.auth:verify-assertion
                               challenge (assertion-table (fuzz-assertion authenticator challenge (incf count))))))
                "seed ~D run ~D: a good response" (fuzz-seed) run)))))))

(test fuzz-passkey-registrations
  (with-auth (b)
    (let ((*request* (lack/request:make-request (make-env :get "/m")))
          (bob (littoral.auth:find-user "bob")))
      (fuzzing (run 60)
        (let* ((json (com.inuoe.jzon:parse (registration-response (make-authenticator) "reg")))
               (inner (gethash "response" json))
               (key (pick #("clientDataJSON" "attestationObject"))))
          (if (chance 4)
              (setf (gethash key inner) (junk-json-value))
              (setf (gethash key inner)
                    (littoral.auth::b64url-encode (mutate (littoral.auth::b64url-decode (gethash key inner))))))
          (let ((text (com.inuoe.jzon:stringify json)))
            (is-only-refused (littoral.auth:add-passkey bob "reg" text) "seed ~D run ~D: ~A" (fuzz-seed) run (shown text))))))))

;;; Decoders and sealed secrets

(test fuzz-decoders
  (fuzzing (run 300)
    (let ((octets (random-octets 48))
          (text (random-string 40)))
      (is (equalp octets (littoral.auth::b64url-decode (littoral.auth::b64url-encode octets)))
          "seed ~D run ~D: base 64 URL lost ~A" (fuzz-seed) run (shown octets))
      (is (equalp octets (littoral.auth:base32-decode (littoral.auth:base32-encode octets)))
          "seed ~D run ~D: base 32 lost ~A" (fuzz-seed) run (shown octets))
      (is-only-refused (littoral.auth::b64url-decode text) "seed ~D run ~D: ~S" (fuzz-seed) run text)
      (is-only-refused (littoral.auth:base32-decode text) "seed ~D run ~D: ~S" (fuzz-seed) run text)
      (multiple-value-bind (what key) (outcome (lambda () (littoral.auth::parse-factor-key text)))
        (is (or (eq what :error) (and (eq what :returned) (= 32 (length key))))
            "seed ~D run ~D: factor key ~S gave ~S" (fuzz-seed) run text what)))))

(test fuzz-sealed-secrets
  (let* ((key (ironclad:random-data 32))
         (secret (littoral.auth:new-totp-secret))
         (sealed (let ((littoral.auth:*factor-key* key)) (littoral.auth::seal-totp-secret secret "7"))))
    (fuzzing (run 200)
      (let ((changed (sb-ext:octets-to-string (mutate (sb-ext:string-to-octets sealed :external-format :latin-1))
                                              :external-format :latin-1)))
        (multiple-value-bind (what opened)
            (outcome (lambda () (let ((littoral.auth:*factor-key* key)) (littoral.auth::open-totp-secret changed "7"))))
          ;; Changed, it opens to nothing; unless it no longer looks sealed,
          ;; when it is taken as a secret kept as it is.
          (is (or (eq what :error)
                  (and (eq what :returned) (not (alexandria:starts-with-subseq "aes1:" changed)) (equal opened changed)))
              "seed ~D run ~D: ~S gave ~S ~S" (fuzz-seed) run changed what opened))))))

;;; Escaping, query strings and SQL

(defun html-unescape (text)
  (let ((text (cl-ppcre:regex-replace-all "&lt;" text "<")))
    (setf text (cl-ppcre:regex-replace-all "&gt;" text ">")
          text (cl-ppcre:regex-replace-all "&quot;" text "\"")
          text (cl-ppcre:regex-replace-all "&#39;" text "'"))
    (cl-ppcre:regex-replace-all "&amp;" text "&")))

(test fuzz-html-escaping
  (fuzzing (run 300)
    (let* ((text (random-string 40))
           (escaped (h:html-escape text)))
      (is (not (find-if (lambda (c) (find c "<>\"'")) escaped)) "seed ~D run ~D: ~S left markup" (fuzz-seed) run text)
      (is (cl-ppcre:scan "^(?:[^&]|&(?:lt|gt|quot|amp|#39);)*$" escaped)
          "seed ~D run ~D: a bare & in ~S" (fuzz-seed) run escaped)
      (is (string= text (html-unescape escaped)) "seed ~D run ~D: ~S didn't come back" (fuzz-seed) run text))))

(defun query-has-p-slowly (query name)
  (some (lambda (pair) (string= name (subseq pair 0 (or (position #\= pair) (length pair)))))
        (cl-ppcre:split "&" query :limit most-positive-fixnum)))

(test fuzz-query-parameters
  (fuzzing (run 300)
    (let* ((names #("_s" "_k" "_lt_ajax" "_lt_events" "_s_" "s" "" "_k=" "a"))
           (query (format nil "~{~A~^&~}"
                          (loop repeat (rnd 5)
                                collect (case (rnd 3)
                                          (0 (pick names))
                                          (1 (format nil "~A=~A" (pick names) (random-string 6)))
                                          (t (random-string 8))))))
           (name (pick #("_s" "_k" "_lt_ajax" "_lt_events"))))
      (is (eq (and (query-has-p-slowly query name) t) (and (littoral::query-has-p query name) t))
          "seed ~D run ~D: ~S in ~S" (fuzz-seed) run name query))))

(defun random-sql-statement ()
  "A statement with no semicolon outside its quotes and comments."
  (format nil "~{~A~^ ~} x"
          (cons (pick #("SELECT" "INSERT" "CREATE" "UPDATE"))
                (loop repeat (rnd 6)
                      collect (case (rnd 7)
                                (0 (format nil "'~A'" (remove #\' (random-string 8))))
                                (1 (format nil "\"~A\"" (remove #\" (random-string 8))))
                                (2 (format nil "$$~A$$" (cl-ppcre:regex-replace-all "\\$" (random-string 8) "")))
                                (3 (format nil "$fn$ x; y $fn$"))
                                (4 (format nil "/* ~A */" (cl-ppcre:regex-replace-all "\\*/" (random-string 8) "")))
                                (5 (format nil "-- ~A~%" (remove #\Newline (random-string 8))))
                                (t (pick #("x" "a1" "t" "(1, 2)" "=" "42" "b_c"))))))))

(test fuzz-sql-splitting
  (fuzzing (run 200)
    (let* ((statements (loop repeat (1+ (rnd 4)) collect (string-trim '(#\Space #\Tab #\Newline) (random-sql-statement))))
           (text (format nil (pick #("~{~A~^;~%~}" "~{~A~^;~}" "~{~A;~%~}")) statements)))
      (is (equal statements (littoral.db::split-sql-statements text))
          "seed ~D run ~D: ~S" (fuzz-seed) run text))))

;;; Requests

(defparameter *fuzz-parameter-names*
  #("_s" "_k" "_lt_ajax" "_lt_live" "_lt_value" "_lt_ws" "v" "1" "2" "3" "10" "_lt_upload" "x[]" "" "a%5B%5D"))

(defun random-url-text (&optional (most 12))
  "Text for a URL: mostly escaped, sometimes raw or with broken escapes."
  (let ((text (random-string most)))
    (case (rnd 4)
      (0 text)
      (1 (concatenate 'string text (pick #("%" "%z" "%zz" "%0" "%C3" "%ff%fe" "+"))))
      (t (quri:url-encode text)))))

(defun random-query (session-query)
  (format nil "~{~A~^&~}"
          (append (and session-query (not (chance 4)) (list session-query))
                  (loop repeat (rnd 6)
                        collect (if (chance 5)
                                    (random-url-text)
                                    (format nil "~A=~A" (pick *fuzz-parameter-names*) (random-url-text)))))))

(defun random-body ()
  (case (rnd 6)
    (0 (values (format nil "~{~A~^&~}" (loop repeat (rnd 5) collect (format nil "~A=~A" (pick *fuzz-parameter-names*) (random-url-text))))
               "application/x-www-form-urlencoded"))
    (1 (values (random-string 60) "application/json"))
    (2 (values (format nil "--b~%Content-Disposition: form-data; name=\"~A\"~%~%~A~%--b--" (random-string 6) (random-string 20))
               (pick #("multipart/form-data; boundary=b" "multipart/form-data" "multipart/form-data; boundary="))))
    (3 (values (random-octets 80) (pick #("application/octet-stream" "text/plain" "application/x-www-form-urlencoded"))))
    (4 (values (random-string 40) (random-string 20)))
    (t (values nil nil))))

(test fuzz-requests
  (with-fresh-applications (("/c" 'littoral-examples:counter :mode :deployment)
                            ("/examples/api" 'littoral-examples:api-demo :mode :deployment))
    (setf littoral-examples::*api-notes* '())
    (let* ((b (make-instance 'browser))
           (app (make-lack-app)))
      (visit b "/c")
      (let ((session-query (nth-value 1 (littoral.test::split-url (browser-url b)))))
        (fuzzing (run 300)
          (multiple-value-bind (body content-type) (random-body)
            (let* ((path (pick #("/c" "/c/" "/c/x" "/" "/littoral/files/littoral.js" "/littoral/files/../x"
                                 "/examples/api/notes" "/examples/api/notes/1" "/examples/api/notes/%25zz" "/c/%25zz")))
                   (url (format nil "~A?~A" path (random-query session-query)))
                   (cookies (append (browser-cookies b)
                                    (loop repeat (rnd 3) collect (cons (random-string 6) (random-string 10)))))
                   (headers (loop repeat (rnd 3)
                                  collect (cons (pick #("Accept-Language" "Host" "X-Forwarded-For" "Referer" "User-Agent"
                                                        "Range" "If-None-Match" "X-Requested-With" "Origin"))
                                                (random-string 30))))
                   (method (pick #(:get :post :put :delete :head :options))))
              (multiple-value-bind (what response)
                  ;; The server decodes the path before Littoral sees it, as MAKE-ENV does.
                  (let ((env (make-env method url :body body :cookies cookies :extra-headers headers
                                                  :content-type (or content-type "application/x-www-form-urlencoded"))))
                    (outcome (lambda () (funcall app env))))
                (is (eq :returned what) "seed ~D run ~D: ~S ~A gave ~S ~A" (fuzz-seed) run method url what response)
                (when (eq :returned what)
                  (let ((status (if (consp response) (first response) 200)))
                    (is (and (integerp status) (< status 500))
                        "seed ~D run ~D: ~S ~A, body ~S, answered ~S" (fuzz-seed) run method url (shown body) status)))))))
        ;; The session still works.
        (visit b "/c")
        (click b "++")
        (is (= 200 (browser-status b)))))))

(defun random-json (&optional (depth 0))
  (case (if (> depth 3) (rnd 4) (rnd 6))
    (0 (com.inuoe.jzon:stringify (random-string 10)))
    (1 (princ-to-string (- (rnd 2000) 1000)))
    (2 (pick #("true" "false" "null" "1e400" "-0" "0.5")))
    (3 (pick #("" "{" "[" "\"" "{\"text\":" "nul" "{\"text\" \"x\"}")))
    (4 (format nil "[~{~A~^,~}]" (loop repeat (rnd 4) collect (random-json (1+ depth)))))
    (t (format nil "{~{~A~^,~}}"
               (loop repeat (rnd 4)
                     collect (format nil "~A:~A" (com.inuoe.jzon:stringify (pick #("text" "id" "" "words" "text")))
                                     (random-json (1+ depth))))))))

(test fuzz-endpoint-bodies
  (with-fresh-applications (("/examples/api" 'littoral-examples:api-demo :mode :deployment))
    (setf littoral-examples::*api-notes* '())
    (let ((b (make-instance 'browser)))
      (fuzzing (run 200)
        (let ((body (if (chance 5) (random-string 40) (random-json))))
          (multiple-value-bind (what status)
              (outcome (lambda () (api b (pick #(:post :put :get)) "/examples/api/notes" body)))
            (is (and (eq :returned what) (integerp status) (< status 500))
                "seed ~D run ~D: ~S gave ~S ~S" (fuzz-seed) run body what status)))))))

;;; What fuzzing found, kept as plain tests

(define-condition fuzz-not-an-error () ()
  (:documentation "A condition that isn't an error, as fast-http's parsers signal with ERROR."))

(defclass condition-signaller (component) ())
(defmethod render ((self condition-signaller))
  (h:anchor (:callback (lambda () (error 'fuzz-not-an-error))) "odd")
  (h:anchor (:callback (lambda () (labels ((deeper (n) (1+ (deeper (1+ n))))) (deeper 0)))) "deep"))

(test unhandled-conditions-answer-500
  ;; Not errors, so no handler of ERROR sees them: without a guard they reach
  ;; the debugger, which ends a server running without one.
  (with-fresh-applications (("/odd" 'condition-signaller :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/odd")
      (click b "odd")
      (is (= 500 (browser-status b)))
      (is (has-text-p b "Reference:"))
      (visit b "/odd")
      (click b "deep")
      (is (= 500 (browser-status b)))
      (visit b "/odd")
      (is (= 200 (browser-status b))))))

(test broken-multipart-bodies-are-no-body
  (with-fresh-applications (("/c" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/c")
      (dolist (body (list (format nil "--b~%Content-Disposition: form-data; name=\"x\"~%~%hello~%--b--")
                          "--b" (format nil "--b~%Content-") ""))
        (is (member (raw-request b :post (browser-url b) :body body :content-type "multipart/form-data; boundary=b")
                    '(200 302))
            "~S" body)))))

(test deeply-nested-cbor-is-refused
  (signals error (littoral.auth:cbor-decode (nested-cbor 100000)))
  (signals error (littoral.auth:cbor-decode (fuzz-octets #(#x9b #xff #xff #xff #xff #xff #xff #xff #xff 0))))
  (is (equal '(1 2) (littoral.auth:cbor-decode (fuzz-octets #(#x82 1 2))))))

(test base64-refuses-other-characters
  (is (equalp #(1 2 3) (littoral.auth::b64url-decode "AQID")))
  (is (equalp #(251 255) (littoral.auth::b64url-decode "-_8")))
  (is (equalp #(251 255) (littoral.auth::b64url-decode "+/8=")))
  (dolist (bad '("AQ ID" "AQ?D" "AQID!" "A" "AQ=D" "=AQID"))
    (signals error (littoral.auth::b64url-decode bad) "~S" bad)))

(test passkey-keys-must-be-points
  ;; A COSE key whose x is an integer once had the encoder ask for a terabyte.
  (with-auth (b)
    (let ((*request* (lack/request:make-request (make-env :get "/m")))
          (bob (littoral.auth:find-user "bob")))
      (dolist (x (list 65535 "text" (ironclad:random-data 31)))
        (let* ((key (cbor `((1 . 2) (3 . -7) (-1 . 1) (-2 . ,x) (-3 . ,(ironclad:random-data 32)))))
               (id (ironclad:random-data 16))
               (data (octets (rp-hash) #(#x41) #(0 0 0 0) (make-array 16 :initial-element 0) (vector 0 16) id key))
               (json (format nil "{\"id\":~S,\"response\":{\"clientDataJSON\":~S,\"attestationObject\":~S}}"
                             (littoral.auth::b64url-encode id)
                             (littoral.auth::b64url-encode (client-data "webauthn.create" "reg"))
                             (littoral.auth::b64url-encode (cbor `(("fmt" . "none") ("attStmt") ("authData" . ,data)))))))
          (signals littoral.auth:passkey-error (littoral.auth:add-passkey bob "reg" json)))))))

(test only-der-signatures-verify
  (multiple-value-bind (private public) (ironclad:generate-key-pair :secp256r1)
    (let* ((point (getf (ironclad:destructure-public-key public) :y))
           (x (subseq point 1 33)) (y (subseq point 33))
           (message (ironclad:random-data 64))
           (good (der (ironclad:sign-message private (ironclad:digest-sequence :sha256 message)))))
      (is (littoral.auth::es256-valid-p x y message good))
      (flet ((refused (der) (signals littoral.auth:passkey-error (littoral.auth::es256-valid-p x y message der))))
        (refused (octets good #(0)))                                         ; something after
        (refused (octets (vector #x30 (+ 2 (aref good 1))) (subseq good 2) #(0 0)))
        (let ((r-length (aref good 3)))                                      ; a needless zero in R
          (refused (octets (vector #x30 (1+ (aref good 1)) 2 (1+ r-length) 0) (subseq good 4))))))))

(test plain-requests-for-a-websocket-are-refused
  (with-fresh-applications (("/c" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/c")
      (is (= 400 (raw-request b :get (format nil "~A&_lt_ws=1" (browser-url b))))))))

(test endpoints-refuse-odd-paths-and-bodies
  (with-fresh-applications (("/examples/api" 'littoral-examples:api-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (is (<= 400 (api b :get "/examples/api/notes/%25zz") 499))
      (is (= 400 (api b :post "/examples/api/notes" (fuzz-octets #(#xff #xfe #x7b))))))))
