;;;; package.lisp

(defpackage #:littoral.test
  (:use #:cl #:littoral #:littoral.html)
  (:documentation "Test Littoral applications in-process with a fake browser.")
  (:export
   ;; A browser and its state
   #:browser #:browser-app #:browser-url #:browser-status #:browser-html
   #:browser-cookies #:browser-fields #:browser-files
   ;; Requests
   #:visit #:back-to #:raw-request #:make-env #:response-header
   ;; Reading the page
   #:page-text #:has-text-p #:find-link #:find-links #:element-name #:form-action
   #:attributes #:attr #:unescape #:strip-tags
   ;; Acting on it
   #:click #:click-nth #:fill-in #:set-checkbox #:select-option #:attach-file #:press
   #:encode-fields
   ;; AJAX and server push
   #:ajax-request #:ajax-specs #:sink #:sink-text #:open-stream #:wait-for
   ;; Test fixtures
   #:with-fresh-applications))
