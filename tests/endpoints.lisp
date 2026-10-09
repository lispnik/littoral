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
