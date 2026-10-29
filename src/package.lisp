;;;; package.lisp

;;; The HTML vocabulary lives in a package of its own, with every element
;;; under its own name: MAP, TIME and SEARCH shadow CL's, and names like
;;; MAIN, LABEL and DATA are too common to force on anyone.  Give it a
;;; local nickname rather than using it:
;;;
;;;   (defpackage #:my-app
;;;     (:use #:cl #:littoral)
;;;     (:local-nicknames (#:h #:littoral.html)))
;;;
;;; and write (h:div (:class "x") (h:p () "Hello")).
(defpackage #:littoral.html
  (:use #:cl)
  (:shadow #:map #:search #:time)
  (:export
   ;; Canvas
   #:*canvas* #:text #:raw #:with-canvas-to-string
   #:html-escape #:tag
   ;; The document
   #:html #:head #:title #:base #:link #:meta #:style #:script #:noscript #:template #:slot #:body
   ;; Sections
   #:article #:section #:nav #:aside #:h1 #:h2 #:h3 #:h4 #:h5 #:h6 #:hgroup
   #:header #:footer #:address #:main #:search
   ;; Grouping content
   #:p #:hr #:pre #:blockquote #:ol #:ul #:menu #:li #:dl #:dt #:dd
   #:figure #:figcaption #:div
   ;; Text
   #:a #:em #:strong #:small #:s #:cite #:q #:dfn #:abbr #:ruby #:rt #:rp #:data #:time
   #:code #:var #:samp #:kbd #:sub #:sup #:i #:b #:u #:mark #:bdi #:bdo #:span #:br #:wbr
   #:ins #:del
   ;; Embedded content
   #:picture #:source #:img #:iframe #:embed #:object #:video #:audio #:track #:map #:area
   #:canvas
   ;; Tables
   #:table #:caption #:colgroup #:col #:tbody #:thead #:tfoot #:tr #:td #:th
   ;; Forms, written plainly
   #:fieldset #:legend #:label #:input #:select #:datalist #:optgroup #:option #:selectedcontent
   #:textarea #:output #:progress #:meter
   ;; Interactive
   #:details #:summary #:dialog
   ;; Brushes with callbacks
   #:anchor #:form #:text-input #:password-input #:number-input #:hidden-input
   #:text-area #:checkbox #:select-list #:radio-group #:submit-button #:cancel-button #:button
   #:file-input #:uploaded-file #:file-name #:file-content-type #:file-contents)
  (:documentation "Tags and brushes for writing HTML in RENDER methods: every HTML element,
under its own name.  Give the package a local nickname, as in
(:local-nicknames (#:h #:littoral.html)), and write (h:p () \"Hello\")."))

;;; The class JOB (a background job) is not exported: the name is too
;;; common.  Its readers (JOB-ID, JOB-STATUS, …) are.
(defpackage #:littoral
  (:use #:cl)
  (:local-nicknames (#:h #:littoral.html))
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
   #:report #:column #:report-rows #:report-columns #:sort-by #:report-csv #:data-grid-csv
   #:send-download #:csv-text
   #:tab-panel #:navigation #:panel-tabs #:panel-selected #:selected-tab #:select-tab
   #:tree #:tree-expanded #:tree-selected #:toggle-item #:expand-all
   #:autocomplete #:autocomplete-value
   #:sortable-list #:sortable-items #:move-item
   ;; Descriptions
   #:define-description #:description #:find-description #:description-fields
   #:description-label #:description-plural #:english-plural
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
   #:state-changed-in-place #:state-changed-object #:state-changed-slot
   #:shared-state-slots #:*check-state-changed-in-place*
   ;; Tasks
   #:task #:define-flow #:flow
   ;; AJAX and push
   #:ajax #:ajax-update #:periodical #:execute-script
   #:channel #:make-channel #:subscriptions #:publish #:notify #:close-event-streams #:*keepalive-seconds* #:*push-render-threads*
   #:with-session #:*source-editor* #:*async-stream-opener*
   ;; Presence
   #:presence #:find-presence #:presences #:presence-activity #:presence-name #:*presence-name-function*
   #:presence-viewers #:presence-list #:presence-list-presence
   ;; Wizards
   #:wizard #:make-wizard #:wizard-step
   ;; More widgets
   #:data-grid #:bar-chart #:line-chart #:sparkline #:calendar #:calendar-year #:calendar-month
   #:kanban #:kanban-columns #:move-card #:markdown-html #:markdown-field
   #:breadcrumb-trail #:breadcrumb-trail-of #:breadcrumb-label
   #:disclosure #:disclosure-open-p #:accordion #:accordion-sections #:accordion-open
   #:dropdown-menu #:menu-bar #:menu-items
   #:in-place-editor #:make-in-place-editor #:edit-conflict #:edit-conflict-object
   ;; Lazy panels, differences, command palettes
   #:lazy-panel #:lazy-panel-loaded-p #:lazy-panel-content #:load-lazy-panel
   #:text-diff #:diff-view #:diff-view-old #:diff-view-new #:diff-view-layout
   #:command-palette #:palette-command #:palette-command-label #:palette-command-action
   #:palette-command-group #:palette-command-keywords #:palette-match-score #:palette-matches #:palette-query
   ;; More field kinds
   #:range-field #:stepper-field #:rating-field #:color-field #:normalize-color
   #:multiple-choice-field #:transfer-field #:new-password-field
   #:password-strength #:password-strength-label #:render-new-password-input #:*common-passwords*
   ;; Popovers, tooltips, drawers and split panes
   #:with-popover #:with-tooltip
   #:drawer #:drawer-content #:drawer-open-p #:toggle-drawer
   #:split-pane #:split-first #:split-second #:split-position #:set-split-position
   ;; Loading more, filter builders, more charts, a week calendar
   #:load-more-list #:load-more #:reset-load-more #:load-more-shown
   #:filter-builder #:filter-conditions #:filter-match #:filter-matches-p #:filter-operators
   #:add-filter-condition #:remove-filter-condition #:clear-filter-conditions #:data-grid-filter
   #:pie-chart #:stacked-bar-chart #:scatter-chart
   #:event-calendar #:event-calendar-view #:event-calendar-date
   ;; Times ago and comment threads
   #:time-ago #:time-ago-text
   #:live-comment-thread #:thread-comment #:thread-comment-id #:thread-comment-thread #:thread-comment-author
   #:thread-comment-body #:thread-comment-time #:thread-comment-origin
   #:thread-comments #:add-thread-comment #:delete-thread-comment #:comment-thread-channel
   #:*comment-store* #:memory-comment-store
   #:store-thread-comments #:store-add-comment #:store-delete-comment #:call-after-store-change
   ;; JSON endpoints
   #:define-endpoint #:register-endpoint #:endpoint-error #:endpoint-body #:*endpoint-authenticator*
   #:openapi-description #:serve-openapi
   ;; Health, metrics, request logs
   #:add-health-check #:remove-health-check #:serve-metrics #:metrics-text #:metrics-summary
   #:reset-metrics #:log-requests-to #:*request-log* #:*latency-buckets*
   #:*request-id* #:*request-log-user-function* #:log-requests-from-environment
   #:add-metrics-source #:remove-metrics-source #:metric-label
   #:define-metric #:count-metric #:observe-metric #:timing-metric
   ;; Background jobs
   #:submit-job #:job-progress #:cancel-job #:watch-job #:wait-for-job #:list-jobs
   #:job-view #:job-view-job #:job-cancelled #:*current-job* #:*job-workers* #:*jobs-channel*
   #:job-id #:job-name #:job-status #:job-progress-fraction #:job-message #:job-result
   #:job-error #:job-attempt #:job-attempts
   ;; Live reload
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
   #:*instance-id* #:*max-request-size* #:*new-sessions-per-minute* #:*trust-forwarded-for* #:*hsts-max-age*
   #:*max-event-streams* #:*max-event-streams-per-session*
   #:application-max-request-size #:application-local-only-p #:application-language
   #:application-around-actions #:application-around-request #:application-websockets-p
   #:application-content-security-policy
   #:*configuration-file* #:save-configuration #:load-configuration
   #:configure-application #:application-settings
   #:register-application #:unregister-application #:find-application
   #:list-applications
   #:make-lack-app #:start #:stop #:*debug-errors* #:url-for #:*base-path*
   #:drain #:cancel-drain #:draining-p #:add-drain-hook #:remove-drain-hook #:drain-on-signal
   #:configure-admin
   ;; Languages
   #:translate #:translate-plural #:define-translations #:add-translations #:load-translations
   #:define-language #:current-language #:set-language #:*language* #:*source-language*
   #:missing-translations #:translated-languages #:language-display-name
   #:translate-label #:localized-number #:localized-date #:application-languages #:language-chooser)
  (:documentation "Littoral: a Seaside-style component web framework for Common Lisp."))
