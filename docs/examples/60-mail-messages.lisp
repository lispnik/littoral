;;;; Mail messages: making them, writing them as MIME, reading them back, and templates.

;;;; Example: littoral.mail:make-mail littoral.mail:mail littoral.mail:mail-to littoral.mail:mail-bcc littoral.mail:mail-subject littoral.mail:mail-text littoral.mail:mail-recipients
;;; A mail with a plain-text body.  Its recipients are everyone it goes to, Bcc included, as bare addresses.
(let ((mail (littoral.mail:make-mail :from "Bookshop <shop@example.org>"
                                     :to "Ada Lovelace <ada@example.org>"
                                     :bcc "orders@example.org"
                                     :subject "Your order has shipped"
                                     :text "It should arrive on Friday.")))
  (list (littoral.mail:mail-to mail)
        (littoral.mail:mail-bcc mail)
        (littoral.mail:mail-subject mail)
        (littoral.mail:mail-text mail)
        (littoral.mail:mail-recipients mail)))
;; ⇒ (("Ada Lovelace <ada@example.org>") ("orders@example.org") "Your order has shipped" "It should arrive on Friday." ("ada@example.org" "orders@example.org"))

;;;; Example: littoral.mail:make-mail littoral.mail:mail-html littoral.mail:mail-text
;;; With only an HTML body, the plain one is made from it.
(let ((mail (littoral.mail:make-mail :to "ada@example.org" :subject "Hello"
                                     :html "<p>Your <b>order</b> is <a href=\"https://example.org/orders/42\">here</a>.</p>")))
  (list (littoral.mail:mail-html mail) (littoral.mail:mail-text mail)))
;; ⇒ ("<p>Your <b>order</b> is <a href=\"https://example.org/orders/42\">here</a>.</p>" "Your order is here (https://example.org/orders/42).")

;;;; Example: littoral.mail:make-mail
;;; A mail needs someone to send it to and a body, and its addresses and headers can't smuggle in line breaks: each is refused when the mail is made.
(flet ((refused-p (&rest arguments)
         (handler-case (progn (apply #'littoral.mail:make-mail arguments) nil)
           (error () t))))
  (list (refused-p :to "ada@example.org" :subject "No body")
        (refused-p :subject "Nobody" :text "Hello")
        (refused-p :to "not an address" :text "Hello")
        (refused-p :to "ada@example.org" :subject (format nil "Hi~%Bcc: everyone@example.org") :text "Hello")))
;; ⇒ (T T T T)

;;;; Example: littoral.mail:mail-cc littoral.mail:mail-reply-to littoral.mail:mail-headers littoral.mail:mail-attachments littoral.mail:mail-from
;;; Copies, a Reply-To address, extra headers and an attachment, read back from the message MAIL-STRING writes.
(let* ((mail (littoral.mail:make-mail :from "Accounts <accounts@example.org>"
                                      :to "ada@example.org" :cc "bob@example.org"
                                      :reply-to "help@example.org"
                                      :subject "Invoice 42" :text "Your invoice is attached."
                                      :headers '(("X-Invoice" . "42"))
                                      :attachments '(("invoice.txt" "text/plain" "Total: 12.50"))))
       (message (littoral.mail:mail-string mail)))
  (list (littoral.mail:mail-from mail)
        (littoral.mail:mail-cc mail)
        (littoral.mail:message-header message "Cc")
        (littoral.mail:message-header message "Reply-To")
        (littoral.mail:message-header message "X-Invoice")
        (mapcar #'first (littoral.mail:mail-attachments mail))))
;; ⇒ ("Accounts <accounts@example.org>" ("bob@example.org") "bob@example.org" "help@example.org" "42" ("invoice.txt"))

;;;; Example: littoral.mail:mail-string littoral.mail:message-header littoral.mail:message-text littoral.mail:message-html
;;; MAIL-STRING writes the MIME message a mailer sends; the message functions read one back, decoding what MIME encoded.
(let* ((mail (littoral.mail:make-mail :to "Zoë <zoe@example.org>" :bcc "orders@example.org"
                                      :subject "Ça va? Order №42"
                                      :text "Thank you, Zoë."
                                      :html "<p>Thank you, <b>Zoë</b>.</p>"))
       (message (littoral.mail:mail-string mail)))
  (list (littoral.mail:message-header message "Subject")
        (littoral.mail:message-header message "To")
        (string-right-trim '(#\Newline) (littoral.mail:message-text message))
        (string-right-trim '(#\Newline) (littoral.mail:message-html message))
        (every (lambda (c) (< (char-code c) 128)) message)
        (null (search "orders@example.org" message))))
;; ⇒ ("Ça va? Order №42" "Zoë <zoe@example.org>" "Thank you, Zoë." "<p>Thank you, <b>Zoë</b>.</p>" T T)

;;;; Example: littoral.mail:address-spec
(littoral.mail:address-spec "Ada Lovelace <ada@example.org>")
;; ⇒ "ada@example.org"

;;;; Example: littoral.mail:*mail-from*
;;; The From address of mail that doesn't give one.
(let ((littoral.mail:*mail-from* "Bookshop <hello@example.org>"))
  (littoral.mail:mail-from (littoral.mail:make-mail :to "ada@example.org" :text "Hello")))
;; ⇒ "Bookshop <hello@example.org>"

;;;; Example: littoral.mail:html-to-text
;;; Paragraphs and list items become lines; links are written out after their text.
(uiop:split-string
 (littoral.mail:html-to-text
  "<h1>Hello <b>Ada</b></h1><ul><li>One book</li><li>Two pens</li></ul><p><a href=\"https://example.org/orders/42\">Your order</a> &amp; its invoice.</p>")
 :separator '(#\Newline))
;; ⇒ ("Hello Ada" "" "- One book" "- Two pens" "" "Your order (https://example.org/orders/42) & its invoice.")

;;;; Example: littoral.mail:define-mail
;;; A template is a function making a mail.  Its HTML is written with the tags RENDER uses, so text is escaped; the plain-text body is made from it.
(littoral.mail:define-mail welcome-mail (name address)
  :to (format nil "~A <~A>" name address)
  :subject (format nil "Welcome, ~A" name)
  :html ((h:p () "Hello " (h:strong () (h:text name)) ",")
         (h:p () (h:anchor (:href "https://example.org/start") "Get started"))))
(let ((mail (welcome-mail "Ada" "ada@example.org")))
  (list (littoral.mail:mail-to mail)
        (littoral.mail:mail-subject mail)
        (uiop:split-string (littoral.mail:mail-text mail) :separator '(#\Newline))
        (not (null (search "<strong>Ada</strong>" (littoral.mail:mail-html mail))))))
;; ⇒ (("Ada <ada@example.org>") "Welcome, Ada" ("Hello Ada," "" "Get started (https://example.org/start)") T)

;;;; Example: littoral.mail:*mail-layout* littoral.mail:default-mail-layout
;;; A layout of its own adds a footer to every template's mail, inside the default layout.
(littoral.mail:define-mail shipped-mail (address)
  :to address
  :subject "Your order has shipped"
  :html ((h:p () "It should arrive on Friday.")))
(let ((littoral.mail:*mail-layout*
        (lambda (subject body)
          (littoral.mail:default-mail-layout
           subject
           (lambda ()
             (funcall body)
             (h:p (:class "footer") "Bookshop, 1 High Street"))))))
  (let ((mail (shipped-mail "ada@example.org")))
    (list (uiop:split-string (littoral.mail:mail-text mail) :separator '(#\Newline))
          (not (null (search "<title>Your order has shipped</title>" (littoral.mail:mail-html mail)))))))
;; ⇒ (("It should arrive on Friday." "" "Bookshop, 1 High Street") T)
