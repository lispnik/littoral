;;;; endpoints.lisp — JSON endpoints, and who they come from

(in-package #:littoral/tests)

(def-suite endpoints :in littoral)
(in-suite endpoints)

(defun api (b method path &optional body (content-type "application/json"))
  "Call the endpoint at PATH as B; status and body."
  (multiple-value-bind (status headers text)
      (raw-request b method path :body body :content-type (and body content-type))
    (declare (ignore headers))
    (values status text)))

(test endpoints-answer-json
  (with-fresh-applications (("/examples/api" 'littoral-examples:api-demo :mode :deployment))
    (setf littoral-examples::*api-notes* '())
    (let ((b (make-instance 'browser)))
      (multiple-value-bind (status text) (api b :get "/examples/api/notes")
        (is (= 200 status)) (is (string= "[]" text)))
      (multiple-value-bind (status text) (api b :post "/examples/api/notes" "{\"text\": \"first\"}")
        (is (= 201 status))
        (is (search "\"text\":\"first\"" text)))
      (let ((id (getf (first littoral-examples::*api-notes*) :id)))
        (multiple-value-bind (status text) (api b :get (format nil "/examples/api/notes/~D" id))
          (is (= 200 status)) (is (search "first" text)))
        (multiple-value-bind (status text) (api b :delete (format nil "/examples/api/notes/~D" id))
          (is (= 200 status)) (is (search "\"deleted\"" text))))
      (is (= 404 (api b :get "/examples/api/notes/999")))
      (is (= 422 (api b :post "/examples/api/notes" "{\"words\": 1}")))
      (is (= 400 (api b :post "/examples/api/notes" "not json")))
      (is (= 405 (api b :put "/examples/api/notes")))
      ;; The page is still there.
      (visit b "/examples/api")
      (is (has-text-p b "JSON endpoints")))))

(test endpoints-know-who-is-asking
  (with-members (b)
    (is (= 401 (api b :get "/examples/members/api/me")))
    ;; Signed in, the browser's cookie is enough to read…
    (members-sign-in b "ada" "correct horse battery")
    (multiple-value-bind (status text) (api b :get "/examples/members/api/me")
      (is (= 200 status))
      (is (search "\"name\":\"ada\"" text))
      (is (search "\"roles\":[\"admin\"]" text)))
    ;; …but not to write without saying it sends JSON, as a cross-site form couldn't.
    (register-endpoint "/examples/members" :post "/api/echo" (lambda () (list :ok t)))
    (is (= 415 (api b :post "/examples/members/api/echo" "x=1" "application/x-www-form-urlencoded")))
    (is (= 200 (api b :post "/examples/members/api/echo" "{}")))
    ;; A token works from anywhere, without the cookie.
    (click b "Create an API token")
    (let* ((token (cl-ppcre:register-groups-bind (tk) ("Bearer (lt_[A-Za-z0-9]+)" (browser-html b)) tk))
           (script (make-instance 'browser :headers `(("authorization" . ,(format nil "Bearer ~A" token))))))
      (is (not (null token)))
      (multiple-value-bind (status text) (api script :get "/examples/members/api/me")
        (is (= 200 status)) (is (search "\"name\":\"ada\"" text)))
      (let ((forger (make-instance 'browser :headers '(("authorization" . "Bearer lt_forged")))))
        (is (= 401 (api forger :get "/examples/members/api/me")))))))

(test endpoint-docstrings-and-options
  ;; A docstring or option is one only when forms follow it.
  (unwind-protect
       (progn
         (define-endpoint "/doc-test" :get "/word" () "a word")
         (define-endpoint "/doc-test" :get "/keyword" () :false)
         (define-endpoint "/doc-test" :get "/both" ()
           "Answer both.  This is said
in two lines."
           :tags ("t") :responses ((200 "Both")) :query (("q" "A word"))
           (list :both t))
         (with-fresh-applications (("/doc-test" 'component :mode :deployment))
           (let ((b (make-instance 'browser)))
             (is (equal "\"a word\"" (nth-value 1 (api b :get "/doc-test/word"))))
             (is (equal "false" (nth-value 1 (api b :get "/doc-test/keyword"))))
             (is (equal "{\"both\":true}" (nth-value 1 (api b :get "/doc-test/both"))))))
         (let ((both (gethash "get" (gethash "/both" (gethash "paths" (openapi-description "/doc-test"))))))
           (is (equal "Answer both." (gethash "summary" both)))
           (is (equal "Answer both. This is said in two lines." (gethash "description" both)))
           (is (equalp #("t") (gethash "tags" both)))
           (is (equal "q" (gethash "name" (aref (gethash "parameters" both) 0))))
           (is (equal "Both" (gethash "description" (gethash "200" (gethash "responses" both))))))
         (is (equal "GET /word" (gethash "summary" (gethash "get" (gethash "/word" (gethash "paths" (openapi-description "/doc-test"))))))))
    (remhash "/doc-test" littoral::*endpoints*)))

(test openapi-describes-the-endpoints
  (with-fresh-applications (("/examples/api" 'littoral-examples:api-demo :mode :deployment))
    (multiple-value-bind (status text) (let ((*endpoint-authenticator* nil)) ; littoral/auth sets one
                                         (api (make-instance 'browser) :get "/examples/api/openapi.json"))
      (is (= 200 status))
      (let* ((spec (com.inuoe.jzon:parse text))
             (paths (gethash "paths" spec))
             (note (gethash "/notes/{id}" paths))
             (post (gethash "post" (gethash "/notes" paths))))
        (is (equal "3.1.0" (gethash "openapi" spec)))
        (is (equal "Notes" (gethash "title" (gethash "info" spec))))
        (is (equal "/examples/api" (gethash "url" (aref (gethash "servers" spec) 0))))
        ;; Itself not among them.
        (is (equal '("/notes" "/notes/{id}") (sort (alexandria:hash-table-keys paths) #'string<)))
        (is (equal '("delete" "get") (sort (alexandria:hash-table-keys note) #'string<)))
        (is (equal "getNotesById" (gethash "operationId" (gethash "get" note))))
        (let ((id (aref (gethash "parameters" (gethash "get" note)) 0)))
          (is (equal "id" (gethash "name" id)))
          (is (equal "path" (gethash "in" id)))
          (is (eq t (gethash "required" id))))
        (is (equal "Add a note." (gethash "summary" post)))
        (is (gethash "requestBody" post))
        (is (equal '("201" "400" "422" "default") (sort (alexandria:hash-table-keys (gethash "responses" post)) #'string<)))
        (is (equal "#/components/schemas/Error"
                   (gethash "$ref" (gethash "schema" (gethash "application/json" (gethash "content" (gethash "422" (gethash "responses" post))))))))
        (is (null (gethash "security" spec)) "No authenticator, no security")))
    (let ((*endpoint-authenticator* (lambda () nil)))
      (let ((spec (openapi-description "/examples/api")))
        (is (gethash "bearer" (gethash "securitySchemes" (gethash "components" spec))))
        (is (= 2 (length (gethash "security" spec))) "A token is optional")))))

(test the-root-application-answers-its-endpoints
  (unwind-protect
       (progn
         (define-endpoint "/" :get "/api/ping" () (list :ok t))
         (with-fresh-applications (("/" 'component :mode :deployment))
           (let ((b (make-instance 'browser)))
             (is (equal "{\"ok\":true}" (nth-value 1 (api b :get "/api/ping"))))
             (is (= 405 (api b :post "/api/ping" "{}")))
             ;; Paths it has no endpoint for aren't its pages.
             (is (= 404 (api b :get "/favicon.ico"))))))
    (remhash "/" littoral::*endpoints*)))
