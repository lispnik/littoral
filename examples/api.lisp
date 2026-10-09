;;;; api.lisp — JSON endpoints beside a page

(in-package #:littoral-examples)

(defvar *api-notes* '() "Notes kept for the API example: plists, newest first.")
(defvar *api-next-id* 0)
(defvar *api-lock* (sb-thread:make-mutex :name "api example"))

(defun api-note (id) (find id *api-notes* :key (lambda (n) (getf n :id))))

(define-endpoint "/examples/api" :get "/notes" ()
  (sb-thread:with-mutex (*api-lock*) (coerce *api-notes* 'vector)))

(define-endpoint "/examples/api" :get "/notes/:id" (id)
  (or (sb-thread:with-mutex (*api-lock*) (api-note (parse-integer id :junk-allowed t)))
      (endpoint-error 404 "No note ~A." id)))

(define-endpoint "/examples/api" :post "/notes" ()
  (let* ((body (endpoint-body))
         (text (and (hash-table-p body) (gethash "text" body))))
    (unless (and (stringp text) (plusp (length (string-trim " " text))))
      (endpoint-error 422 "Send {\"text\": \"…\"}."))
    (let ((note (sb-thread:with-mutex (*api-lock*)
                  (let ((note (list :id (incf *api-next-id*) :text (subseq text 0 (min 200 (length text)))
                                    :created (littoral::iso-time (get-universal-time)))))
                    (push note *api-notes*)
                    (setf *api-notes* (subseq *api-notes* 0 (min 50 (length *api-notes*))))
                    note))))
      (values note 201))))

(define-endpoint "/examples/api" :delete "/notes/:id" (id)
  (sb-thread:with-mutex (*api-lock*)
    (let ((note (api-note (parse-integer id :junk-allowed t))))
      (unless note (endpoint-error 404 "No note ~A." id))
      (setf *api-notes* (remove note *api-notes*))
      (list :deleted (getf note :id)))))

(defclass api-demo (component) ()
  (:documentation "A page about the JSON endpoints beside it, which calls them."))

(defmethod render ((self api-demo))
  (let ((base (url-for "/examples/api")))
    (h1 () "JSON endpoints")
    (p () "This application answers JSON at " (code () (text (format nil "~A/notes" base)))
      " as well as serving this page. The endpoints share the application's database and "
      "sign-in, but not its sessions: they suit mobile apps, scripts and webhooks.")
    (pre (:class "api-code" :tabindex "0")
      (text (format nil "(define-endpoint \"/examples/api\" :post \"/notes\" ()
  (let ((text (gethash \"text\" (endpoint-body))))
    (values (create-note text) 201)))

curl ~A/notes
curl -X POST -H 'Content-Type: application/json' -d '{\"text\":\"hi\"}' ~A/notes" base base)))
    (h2 () "Try it")
    (div (:class "api-form")
      (label (:for "api-text") "Note")
      (littoral::emit-tag "input" (list :id "api-text" :type "text" :value "Hello from the browser") nil)
      (littoral::emit-tag "button" (list :type "button" :id "api-post") (lambda () (text "POST /notes")))
      (littoral::emit-tag "button" (list :type "button" :id "api-get") (lambda () (text "GET /notes"))))
    (p (:role "status") (strong () "Response: ") (code (:id "api-status") "—"))
    (pre (:id "api-output" :class "api-code" :tabindex "0") "Press a button.")))

(defmethod script ((self api-demo))
  ;; Plain fetch calls: this script carries the page's nonce.
  (format nil "(() => {
  const base = ~S;
  const show = async (response) => {
    document.getElementById('api-status').textContent = response.status + ' ' + response.statusText;
    document.getElementById('api-output').textContent = JSON.stringify(await response.json(), null, 2);
  };
  document.getElementById('api-get').addEventListener('click', async () => show(await fetch(base + '/notes')));
  document.getElementById('api-post').addEventListener('click', async () => show(await fetch(base + '/notes', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: document.getElementById('api-text').value }) })));
})();" (url-for "/examples/api")))

(defmethod style ((self api-demo))
  ".api-code { background: var(--lt-panel); padding: .6rem .8rem; border-radius: 6px; overflow-x: auto; font-size: .85rem; }
.api-form { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }")
