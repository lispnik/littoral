;;;; examples.lisp — the larger example applications, end to end

(in-package #:littoral/tests)

(def-suite examples :in littoral)
(in-suite examples)

;;; Sushi store

(defun store-browser ()
  (let ((b (make-instance 'browser)))
    (visit b "/store")
    (click-nth b "Add" 0) (click-nth b "Add" 0) (click-nth b "Add" 1)
    b))

(defun fill-address (b &key (name "Ada") (street "1 Main St") (city "Springfield") (postcode "12345"))
  (fill-in b "name" name) (fill-in b "street" street)
  (fill-in b "city" city) (fill-in b "postcode" postcode)
  (press b "Continue"))

(test store-checkout
  (with-fresh-applications (("/store" 'littoral-examples:store :mode :deployment))
    (let ((b (store-browser)))
      (is (has-text-p b "3 items in your cart"))
      (is (has-text-p b "Total $13.00"))
      (let ((before-checkout (browser-url b)))
        (click b "Checkout »")
        (is (has-text-p b "Your order"))
        (press b "Continue to delivery")
        (is (has-text-p b "Where should we deliver?"))
        ;; Validation refuses an incomplete address, then a bad postcode.
        (fill-address b :street "")
        (is (has-text-p b "Please fill in every field."))
        (fill-address b :postcode "12a")
        (is (has-text-p b "digits only"))
        (fill-address b)
        (is (has-text-p b "When should we deliver?"))
        ;; Today is not selectable; next month's 15th is.
        (click b "›")
        (click-nth b "15" 0)
        (is (has-text-p b "How will you pay?"))
        (press b "OK")                    ; the first choice, cash on delivery
        (is (has-text-p b "Place an order for 3 items, $13.00"))
        (is (has-text-p b "paid by cash on delivery"))
        (let ((confirm-page (browser-url b)))
          (press b "Yes")
          (is (has-text-p b "Thank you! Order #"))
          (is (has-text-p b "15,"))
          (press b "Back to the menu")
          (is (has-text-p b "is on its way"))
          (is (has-text-p b "0 items in your cart"))
          (is (has-text-p b "Your orders"))
          ;; Isolation: the confirmation page is gone, so going back to it
          ;; shows the store as it is, and nothing can be ordered twice.
          (back-to b confirm-page)
          (is (not (has-text-p b "Place an order")))
          (is (has-text-p b "Your orders"))
          (is (= 1 (length (cl-ppcre:all-matches-as-strings "<li>#\\d+" (browser-html b))))))
        ;; Pages from before the checkout still backtrack, cart and all.
        (back-to b before-checkout)
        (is (has-text-p b "3 items in your cart"))))))

(test store-checkout-cancel-and-edit
  (with-fresh-applications (("/store" 'littoral-examples:store :mode :deployment))
    (let ((b (store-browser)))
      (click b "Checkout »")
      ;; Change a quantity in the review, then go back to the menu.
      (let ((qty (cl-ppcre:register-groups-bind (n) ("<input type=\"number\" name=\"(\\d+)\"" (browser-html b)) n)))
        (setf (browser-fields b) (cons (cons qty "5") (remove qty (browser-fields b) :key #'car :test #'string=))))
      (press b "Update")
      (is (has-text-p b "Total: $26.50"))
      (press b "Back to the menu")
      (is (has-text-p b "6 items in your cart"))
      ;; Cancelling the address form ends the checkout too.
      (click b "Checkout »")
      (press b "Continue to delivery")
      (press b "Cancel")
      (is (has-text-p b "Sushi Store"))
      (is (has-text-p b "6 items in your cart"))
      (is (not (has-text-p b "Your orders"))))))

(test store-catalog-pages
  (with-fresh-applications (("/store" 'littoral-examples:store :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/store")
      (is (has-text-p b "Maguro nigiri"))
      (is (not (has-text-p b "Green tea")))
      (click b "Next »")
      (is (has-text-p b "Green tea"))
      (click b "Price")
      (is (search "Green tea" (page-text b))))))

;;; Wiki

(test wiki
  (littoral-examples:reset-wiki)
  (with-fresh-applications (("/wiki" 'littoral-examples:wiki :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/wiki")
      (is (alexandria:starts-with-subseq "/wiki/FrontPage?" (browser-url b)))
      (is (has-text-p b "Welcome"))
      ;; A link to a page nobody has written yet.
      (click b "Some Name")
      (is (alexandria:starts-with-subseq "/wiki/Some%20Name?" (browser-url b)))
      (is (has-text-p b "does not exist yet"))
      (click b "Write it")
      (fill-in b "text" (format nil "Hello *world*, see [[FrontPage]].~%~%- one~%- two"))
      (fill-in b "summary" "first")
      (press b "Preview")
      (is (search "<strong>world</strong>" (browser-html b)))
      (press b "Save")
      (is (search "Hello <strong>world</strong>" (browser-html b)))
      (is (search "<li>two</li>" (browser-html b)))
      ;; A second revision, then revert to the first.
      (click b "Edit")
      (fill-in b "text" "Rewritten <entirely>")
      (press b "Save")
      (is (search "Rewritten &lt;entirely&gt;" (browser-html b)))
      (click b "History")
      (is (has-text-p b "first"))
      (click b "revert")
      (is (has-text-p b "Hello world"))
      (click b "History")
      (is (has-text-p b "Reverted to #1"))
      (click b "Back to the page")
      ;; Another session, opening a bookmark, sees the shared page.
      (let ((other (make-instance 'browser)))
        (visit other "/wiki/Some%20Name")
        (is (has-text-p other "Hello world")))
      ;; Search covers titles and text.
      (fill-in b "query" "hello")
      (press b "Search")
      (is (has-text-p b "1 page match"))
      (is (find-link b "Some Name")))))

(test wiki-back-button-keeps-the-wiki
  (littoral-examples:reset-wiki)
  (with-fresh-applications (("/wiki" 'littoral-examples:wiki :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/wiki/Sandbox")
      (let ((before (browser-url b)))
        (click b "Write it")
        (fill-in b "text" "Sand")
        (press b "Save")
        ;; Going back restores the view, not the wiki's contents.
        (back-to b before)
        (is (has-text-p b "Sand"))
        (is (not (has-text-p b "does not exist yet")))))))

;;; Chat

(defun join-chat (b nick)
  (visit b "/chat")
  (click b "Join the room")
  (answer-input b nick))

(defun periodical-target (b)
  (let ((spec (cl-ppcre:register-groups-bind (s) ("data-lt-periodical=\"([^\"]*)\"" (browser-html b)) s)))
    (subseq spec (1+ (position #\; spec :from-end t)))))

(test chat
  (littoral-examples:clear-room)
  (with-fresh-applications (("/chat" 'littoral-examples:chat :mode :deployment))
    (let ((alice (make-instance 'browser)) (bob (make-instance 'browser)))
      (visit alice "/chat")
      (click alice "Join the room")
      (answer-input alice "  ")
      (is (has-text-p alice "at least one letter"))
      (answer-input alice "alice")
      (is (has-text-p alice "You are alice"))
      (join-chat bob "bob")
      ;; Alice posts through the AJAX form submit.
      (let* ((spec (first (ajax-specs alice "on-submit")))
             (json (ajax-request alice (car spec) (cdr spec)
                                 :fields (list (cons (element-name alice "draft") "hi <bob>")))))
        (is (search "hi &lt;bob&gt;" json))
        ;; The composer comes back empty.
        (is (search "value=\\\"\\\" id=\\\"draft\\\"" json)))
      ;; Bob's periodical update shows it, marked as someone else's.
      (let ((json (ajax-request bob "" (periodical-target bob))))
        (is (search "hi &lt;bob&gt;" json))
        (is (search "alice" json))
        (is (not (search "mine" json))))
      ;; A reload shows the room too.
      (visit bob (browser-url bob))
      (is (has-text-p bob "hi <bob>")))))

;;; Index

(test example-index-links-every-example
  (with-fresh-applications ()
    (littoral-examples:register-examples)
    (let ((b (make-instance 'browser)))
      (visit b "/examples")
      (is (has-text-p b "Littoral examples"))
      (dolist (app (list-applications))
        (let ((path (application-path app)))
          (when (alexandria:starts-with-subseq "/examples/" path)
            (is (search (format nil "href=\"~A\"" path) (browser-html b)) "~A is not in the index" path)
            ;; And every example starts without error.
            (let ((visitor (make-instance 'browser)))
              (visit visitor path)
              (is (= 200 (browser-status visitor)) "~A did not start" path))))))))
