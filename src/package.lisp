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
   #:fieldset #:legend #:label #:abbr #:cite #:mark #:dfn #:kbd #:samp #:var-tag #:details #:summary
   #:img #:br #:hr #:tag
   ;; Brushes with callbacks
   #:anchor #:form #:text-input #:password-input #:number-input #:hidden-input
   #:text-area #:checkbox #:select-list #:radio-group #:submit-button #:cancel-button #:button
   #:file-input #:uploaded-file #:file-name #:file-content-type #:file-contents)
  (:documentation "Tags and brushes for writing HTML in RENDER methods."))

(defpackage #:littoral
  (:use #:cl #:littoral.html)
  (:import-from #:cl-cont #:defun/cc #:let/cc #:with-call/cc)
  (:export
   ;; Context
   #:*request* #:*session* #:*application* #:*render-context*
   #:request-parameter #:request-parameter-p #:request-path
   #:redirect-to #:forbidden #:forbidden-message
   #:render-phase-error
   ;; Components
   #:component #:component-id #:render #:render-component #:children #:states
   #:update-root #:style #:script #:initial-request #:updatable-wrapper
   #:update-url #:page-url #:add-to-path #:add-parameter #:url-path #:url-parameters
   #:request-extra-path
   #:call #:answer #:show #:home #:visible-children #:active-component
   #:html-root #:root-title #:add-stylesheet #:add-script #:add-style
   #:add-head-meta #:add-head-link
   ;; Decorations
   #:decoration #:add-decoration #:remove-decoration #:decorations
   #:delegation #:answer-handler #:message-decoration #:form-decoration
   #:validation-decoration #:validate-with
   #:render-inner #:render-decoration #:decoration-kind #:decoration-children #:updatable
   #:show-modal #:call-modal #:modal-decoration #:toast
   ;; Dialogs
   #:message-dialog #:confirm-dialog #:input-dialog #:choice-dialog #:login-dialog
   #:inform #:confirm #:request-input #:choose-from
   ;; Widgets
   #:batched-list #:batch #:batch-items #:batch-size #:batch-page #:go-to-page
   #:report #:column #:report-rows #:report-columns #:sort-by
   #:tab-panel #:navigation #:panel-tabs #:panel-selected #:selected-tab #:select-tab
   #:tree #:tree-expanded #:tree-selected #:toggle-item #:expand-all
   #:autocomplete #:autocomplete-value
   #:sortable-list #:sortable-items #:move-item
   ;; Descriptions
   #:define-description #:description #:find-description #:description-fields
   #:field #:field-name #:field-label #:field-value #:find-field #:*field-kinds*
   #:string-field #:text-field #:password-field #:email-field #:url-field
   #:integer-field #:boolean-field #:choice-field #:date-field #:field-choices #:field-hidden-p
   #:parse-field #:format-field #:check-field #:render-field-input #:render-field-value
   #:field-error #:field-problem
   #:validate #:make-editor #:make-viewer #:description-editor #:description-viewer
   #:description-columns
   ;; Backtracking
   #:snapshot #:take-snapshot #:restore-snapshot #:begin-isolation #:end-isolation
   #:deep #:deep-copy #:snapshot-entries
   ;; Tasks
   #:task #:define-flow #:flow
   ;; AJAX and push
   #:ajax #:ajax-update #:periodical #:execute-script
   #:channel #:make-channel #:subscriptions #:publish #:notify #:close-event-streams
   #:with-session #:*source-editor* #:*async-stream-opener*
   ;; Wizards
   #:wizard #:make-wizard #:wizard-step
   ;; More widgets
   #:data-grid #:bar-chart #:line-chart #:sparkline #:calendar #:calendar-year #:calendar-month
   #:kanban #:kanban-columns #:move-card #:markdown-html #:markdown-field
   ;; JSON endpoints
   #:define-endpoint #:register-endpoint #:endpoint-error #:endpoint-body #:*endpoint-authenticator*
   ;; Health, metrics, request logs
   #:add-health-check #:remove-health-check #:serve-metrics #:metrics-text #:metrics-summary
   #:reset-metrics #:log-requests-to #:*request-log* #:*latency-buckets*
   ;; Background jobs (the class JOB is not exported: the name is too common)
   #:submit-job #:job-progress #:cancel-job #:watch-job #:wait-for-job #:list-jobs
   #:job-view #:job-view-job #:job-cancelled #:*current-job* #:*job-workers* #:*jobs-channel*
   #:job-id #:job-name #:job-status #:job-progress-fraction #:job-message #:job-result
   #:job-error #:job-attempt #:job-attempts
   #:*live-reload* #:reload-pages #:start-live-watcher #:stop-live-watcher
   ;; Sessions & applications
   #:session #:session-key #:session-root #:session-properties #:session-property
   #:expire-session #:list-sessions #:rotate-session-key #:set-cookie #:request-cookie
   #:mount-handler #:unmount-handler #:field-multipart-p
   #:application #:application-path #:application-root-class #:application-title
   #:application-mode #:application-session-timeout #:application-max-continuations
   #:application-cookie-sessions-p #:application-sessions
   #:application-max-sessions #:application-error-handler #:application-expired-notice
   #:application-stylesheets #:application-scripts #:application-credentials
   #:reap-all-sessions #:start-reaper #:stop-reaper #:session-expired-notice
   #:*instance-id* #:*max-request-size* #:*new-sessions-per-minute* #:*trust-forwarded-for*
   #:*max-event-streams* #:*max-event-streams-per-session*
   #:application-max-request-size #:application-local-only-p #:application-language
   #:application-around-actions #:application-around-request #:application-websockets-p
   #:application-content-security-policy
   #:*configuration-file* #:save-configuration #:load-configuration
   #:configure-application #:application-settings
   #:register-application #:unregister-application #:find-application
   #:list-applications
   #:make-lack-app #:start #:stop #:*debug-errors* #:url-for #:*base-path*
   #:configure-admin
   ;; Languages
   #:translate #:translate-plural #:define-translations #:add-translations #:load-translations
   #:define-language #:current-language #:set-language #:*language* #:*source-language*
   #:missing-translations #:translated-languages #:language-display-name
   #:translate-label #:localized-number #:localized-date #:application-languages #:language-chooser)
  (:documentation "Littoral: a Seaside-style component web framework for Common Lisp."))
