;;;; The examples for JSON endpoints served beside an application's pages.

;;;; Example: littoral:define-endpoint littoral:endpoint-error
;;; An endpoint's value is its JSON response: a keyword plist is an object, a list of them an array.  :ID in the pattern becomes the argument ID, a string.  ENDPOINT-ERROR answers with a status and {"error": message}.
(defvar *notes* (list (list :id 1 :text "Buy milk") (list :id 2 :text "Call Ada")))
(define-endpoint "/notes" :get "/api/notes" ()
  *notes*)
(define-endpoint "/notes" :get "/api/notes/:id" (id)
  (or (find (parse-integer id :junk-allowed t) *notes* :key (lambda (note) (getf note :id)))
      (endpoint-error 404 "No note ~A." id)))
(with-fresh-applications (("/notes" 'component :mode :deployment))
  (let ((b (make-instance 'browser)))
    (flet ((get-json (path)
             (multiple-value-bind (status headers body) (raw-request b :get path)
               (declare (ignore headers))
               (list status body))))
      (list (get-json "/notes/api/notes/2")
            (get-json "/notes/api/notes/9")))))
;; ⇒ ((200 "{\"id\":2,\"text\":\"Call Ada\"}") (404 "{\"error\":\"No note 9.\"}"))

;;;; Example: littoral:endpoint-body littoral:define-endpoint
;;; ENDPOINT-BODY is the JSON the request sent, parsed: objects become hash tables.  A second value is the status, a third extra headers.
(defvar *next-id* 3)
(define-endpoint "/notes" :post "/api/notes" ()
  (let* ((body (endpoint-body))
         (text (and body (gethash "text" body))))
    (unless (stringp text)
      (endpoint-error 422 "A note needs text."))
    (let ((id (incf *next-id*)))
      (values (list :id id :text text)
              201
              (list :location (format nil "/notes/api/notes/~D" id))))))
(with-fresh-applications (("/notes" 'component :mode :deployment))
  (let ((b (make-instance 'browser)))
    (flet ((post-json (json)
             (multiple-value-bind (status headers body)
                 (raw-request b :post "/notes/api/notes" :body json :content-type "application/json")
               (list status (getf headers :location) body))))
      (list (post-json "{\"text\": \"Feed the cat\"}")
            (post-json "{\"words\": 3}")
            (first (post-json "not JSON"))))))
;; ⇒ ((201 "/notes/api/notes/4" "{\"id\":4,\"text\":\"Feed the cat\"}") (422 NIL "{\"error\":\"A note needs text.\"}") 400)

;;;; Example: littoral:register-endpoint
;;; The function behind DEFINE-ENDPOINT: serve a function you already have.  It returns the method and pattern.
(defun zone-time (zone)
  (list :zone zone :hour 12))
(register-endpoint "/clock" :get "/api/time/:zone" #'zone-time)
;; ⇒ (:GET "/api/time/:zone")
(with-fresh-applications (("/clock" 'component :mode :deployment))
  (nth-value 2 (raw-request (make-instance 'browser) :get "/clock/api/time/UTC")))
;; ⇒ "{\"zone\":\"UTC\",\"hour\":12}"

;;;; Example: littoral:*endpoint-authenticator*
;;; littoral/auth sets it to say who a request comes from, and how.  A write signed in only by cookie must send JSON, which a cross-site form can't; here a stand-in says every request is Ada's, by cookie.
(define-endpoint "/inbox" :post "/api/read-all" ()
  (list :ok t))
(with-fresh-applications (("/inbox" 'component :mode :deployment))
  (let ((*endpoint-authenticator* (lambda () (values "ada" :cookie)))
        (b (make-instance 'browser)))
    (list (raw-request b :post "/inbox/api/read-all" :body "all=1"
                                                     :content-type "application/x-www-form-urlencoded")
          (raw-request b :post "/inbox/api/read-all" :body "{}" :content-type "application/json"))))
;; ⇒ (415 200)

;;;; Example: littoral:serve-openapi littoral:define-endpoint
;;; SERVE-OPENAPI answers GET /openapi.json with a description of the application's endpoints, for Swagger UI and client generators.  An endpoint's docstring gives its summary (the first sentence) and description; options before the body, unevaluated, give its tags, responses, request body and query parameters.
(define-endpoint "/shelf" :get "/api/books/:isbn" (isbn)
  "A book, by its ISBN."
  :tags ("books") :responses ((200 "The book") (404 "No such book"))
  (list :isbn isbn :title "Dune"))
(serve-openapi "/shelf" :title "Shelf" :version "2" :license "MIT")
;; ⇒ (:GET "/openapi.json")
(with-fresh-applications (("/shelf" 'component :mode :deployment))
  (let* ((json (nth-value 2 (raw-request (make-instance 'browser) :get "/shelf/openapi.json")))
         (spec (com.inuoe.jzon:parse json))
         (book (gethash "get" (gethash "/api/books/{isbn}" (gethash "paths" spec)))))
    (list (gethash "title" (gethash "info" spec))
          (gethash "summary" book)
          (gethash "operationId" book)
          (sort (alexandria:hash-table-keys (gethash "responses" book)) #'string<))))
;; ⇒ ("Shelf" "A book, by its ISBN." "getApiBooksByIsbn" ("200" "404" "default"))

;;;; Example: littoral:openapi-description
;;; The description itself, as a hash table: here a query parameter, documented with :QUERY.  Endpoints without a docstring are summarised by their method and path.
(define-endpoint "/shelf" :get "/api/search" ()
  "Find books."
  :query (("q" "Words in the title"))
  (list))
(define-endpoint "/shelf" :delete "/api/books/:isbn" (isbn)
  (list :deleted isbn))
(let* ((paths (gethash "paths" (openapi-description "/shelf")))
       (finder (gethash "get" (gethash "/api/search" paths)))
       (q (aref (gethash "parameters" finder) 0)))
  (list (gethash "name" q) (gethash "in" q)
        (gethash "summary" (gethash "delete" (gethash "/api/books/{isbn}" paths)))))
;; ⇒ ("q" "query" "DELETE /api/books/{isbn}")
