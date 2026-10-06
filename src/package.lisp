;;;; package.lisp

;;; The HTML vocabulary lives in a package of its own: names like MAIN,
;;; HEADER, LABEL and TABLE are too common to force on every package that
;;; uses LITTORAL; use LITTORAL.HTML alongside it when that suits.
(defpackage #:littoral.html
  (:use #:cl)
  (:export
   ;; Canvas
   #:*canvas* #:text #:raw #:with-canvas-to-string
   #:html-escape
   ;; Plain tags
   #:div #:span #:p #:h1 #:h2 #:h3 #:h4 #:h5 #:h6 #:ul #:ol #:li #:dl #:dt #:dd
   #:table #:thead #:tbody #:tfoot #:tr #:td #:th #:caption
   #:em #:strong #:b #:i #:u #:small #:code #:pre #:blockquote #:sup #:sub
   #:section #:article #:aside #:nav #:header #:footer #:main #:figure #:figcaption
   #:fieldset #:legend #:label #:abbr #:cite #:mark #:dfn #:kbd #:samp #:var-tag
   #:img #:br #:hr #:tag
   ;; Brushes with callbacks
   #:anchor #:form #:text-input #:password-input #:number-input #:hidden-input
   #:text-area #:checkbox #:select-list #:radio-group #:submit-button #:cancel-button #:button
   #:file-input #:uploaded-file #:file-name #:file-content-type #:file-contents))

(defpackage #:littoral
  (:use #:cl #:littoral.html)
  (:import-from #:cl-cont #:defun/cc #:let/cc #:with-call/cc)
  (:export
   ;; Context
   #:*request* #:*session* #:*application* #:*render-context*
   #:request-parameter #:request-parameter-p #:request-path
   #:render-phase-error
   ;; Components
   #:component #:component-id #:render #:render-component #:children #:states
   #:update-root #:style #:script #:initial-request
   #:update-url #:page-url #:add-to-path #:add-parameter #:url-path #:url-parameters
   #:request-extra-path
   #:call #:answer #:show #:home #:visible-children #:active-component
   #:html-root #:root-title #:add-stylesheet #:add-script #:add-style
   ;; Decorations
   #:decoration #:add-decoration #:remove-decoration #:decorations
   #:delegation #:answer-handler #:message-decoration #:form-decoration
   #:validation-decoration #:validate-with
   #:render-inner #:render-decoration #:decoration-kind #:updatable
   ;; Dialogs
   #:message-dialog #:confirm-dialog #:input-dialog #:choice-dialog #:login-dialog
   #:inform #:confirm #:request-input #:choose-from
   ;; Widgets
   #:batched-list #:batch #:batch-items #:batch-size #:batch-page #:go-to-page
   #:report #:column #:report-rows #:report-columns #:sort-by
   ;; Backtracking
   #:snapshot #:take-snapshot #:restore-snapshot #:begin-isolation #:end-isolation
   ;; Tasks
   #:task #:define-flow #:flow
   ;; AJAX
   #:ajax #:ajax-update #:periodical
   ;; Sessions & applications
   #:session #:session-key #:session-root #:session-properties #:session-property
   #:expire-session #:list-sessions
   #:application #:application-path #:application-root-class #:application-title
   #:application-mode #:application-session-timeout #:application-max-continuations
   #:application-cookie-sessions-p #:application-sessions
   #:application-max-sessions #:application-error-handler #:application-expired-notice
   #:application-stylesheets #:application-scripts #:application-credentials
   #:reap-all-sessions #:start-reaper #:stop-reaper #:session-expired-notice
   #:register-application #:unregister-application #:find-application
   #:list-applications
   #:make-lack-app #:start #:stop #:*debug-errors* #:url-for #:*base-path*
   #:configure-admin))
