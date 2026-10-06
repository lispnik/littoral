;;;; ajax.lisp — re-rendering parts of a page in place
;;;;
;;;; An :ON-CLICK, :ON-CHANGE or :ON-INPUT attribute whose value is an AJAX
;;;; spec makes the element post its callback (and its field, or its form
;;;; for a submit button) in the background; the components to :UPDATE are
;;;; rendered again and swapped into the page.  Those components must be
;;;; UPDATABLE so the page has an element with their id.
;;;;
;;;;   (button (:on-click (ajax :callback (lambda () (incf (count-of self)))
;;;;                            :update self))
;;;;     "++")
;;;;
;;;; A :PERIODICAL attribute re-renders on a timer instead.
;;;;
;;;; AJAX requests act on the page's own continuation: they run callbacks
;;;; and replace its snapshot, but do not make a new page for the back
;;;; button, as in Seaside.

(in-package #:littoral)

(defstruct (ajax-spec (:constructor %make-ajax-spec))
  callback
  (update '())
  (every nil)
  (value nil)
  (confirm nil)
  (on-complete nil))

(defvar *ajax-result* nil
  "What the AJAX callback returned, sent back to :ON-COMPLETE as VALUE.")

(defvar *ajax-scripts* :none
  "JavaScript queued by EXECUTE-SCRIPT during an AJAX request, newest
first; :NONE outside one.")

(defun ajax (&key callback update value confirm on-complete)
  "Run CALLBACK in the background, then re-render the component or list of
components UPDATE.

VALUE is a JavaScript expression evaluated in the browser, with this bound
to the element; when given, CALLBACK receives its result as a string.
CALLBACK's return value goes back to the browser, where ON-COMPLETE, a
JavaScript snippet, can use it as value.  CONFIRM asks the user before
anything is sent."
  (%make-ajax-spec :callback callback
                   :update (alexandria:ensure-list update)
                   :value value :confirm confirm :on-complete on-complete))

(defun execute-script (javascript)
  "Run JAVASCRIPT in the browser once the current AJAX request's updates are
in place.  Outside an AJAX request it does nothing and returns NIL."
  (unless (eql *ajax-scripts* :none)
    (push javascript *ajax-scripts*)
    t))

(defun ajax-update (&rest components)
  "Re-render COMPONENTS, running no callback first."
  (ajax :update components))

(defun periodical (seconds &key callback update)
  "For a :PERIODICAL attribute: every SECONDS, run CALLBACK and re-render UPDATE."
  (%make-ajax-spec :callback callback
                   :update (alexandria:ensure-list update)
                   :every seconds))

(defun ajax-action (spec)
  "The action callback for SPEC: it passes the browser's value when SPEC
asks for one and keeps the result for the response."
  (let ((callback (ajax-spec-callback spec))
        (wants-value (ajax-spec-value spec)))
    (lambda ()
      (setf *ajax-result*
            (if wants-value
                (funcall callback (or (request-parameter "_lt_value") ""))
                (funcall callback))))))

(defmethod emit-attribute (key (value ajax-spec) stream)
  ;; data-lt-on-click="CALLBACK-ID;ID ID…" — data-lt-periodical prefixes
  ;; the interval in milliseconds.  Options ride in data-lt-on-click-value,
  ;; -confirm and -complete.
  (let ((id (if (ajax-spec-callback value) (register :action (ajax-action value)) ""))
        (targets (join-strings (mapcar #'component-id (ajax-spec-update value)))))
    (format stream " data-lt-~(~A~)=\"~@[~D;~]~A;~A\""
            key
            (and (ajax-spec-every value) (round (* 1000 (ajax-spec-every value))))
            id
            (html-escape targets))
    (loop for (suffix option) in `(("value" ,(ajax-spec-value value))
                                   ("confirm" ,(ajax-spec-confirm value))
                                   ("complete" ,(ajax-spec-on-complete value)))
          when option
            do (format stream " data-lt-~(~A~)-~A=\"~A\"" key suffix (html-escape option)))))

(defun json-value (value)
  "VALUE as JSON: strings, numbers, T/NIL as true/null, :FALSE, hash tables
and keyword plists as objects, other lists as arrays."
  (flet ((plistp (list)
           (and (evenp (length list))
                (loop for (k) on list by #'cddr always (keywordp k)))))
    (cond ((null value) "null")
          ((eq value t) "true")
          ((eql value :false) "false")
          ((stringp value) (json-string value))
          ((integerp value) (princ-to-string value))
          ((realp value) (let ((*read-default-float-format* 'double-float))
                           (format nil "~F" (coerce value 'double-float))))
          ((hash-table-p value)
           (format nil "{~{~A~^,~}}"
                   (loop for k being the hash-keys of value using (hash-value v)
                         collect (format nil "~A:~A" (json-string (if (symbolp k)
                                                                         (string-downcase k)
                                                                         (princ-to-string k)))
                                         (json-value v)))))
          ((and (consp value) (plistp value))
           (format nil "{~{~A~^,~}}"
                   (loop for (k v) on value by #'cddr
                         collect (format nil "~A:~A" (json-string (string-downcase k)) (json-value v)))))
          ((listp value) (format nil "[~{~A~^,~}]" (mapcar #'json-value value)))
          ((symbolp value) (json-string (string-downcase value)))
          (t (json-string (princ-to-string value))))))

(defun json-string (string)
  "STRING as a JSON string literal."
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for c across string
          do (case c
               (#\" (write-string "\\\"" out))
               (#\\ (write-string "\\\\" out))
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (#\Tab (write-string "\\t" out))
               (otherwise (if (< (char-code c) 32)
                      (format out "\\u~4,'0X" (char-code c))
                      (write-char c out)))))
    (write-char #\" out)))

(defun render-fragments (ids root &key value scripts)
  "JSON object mapping each id to the HTML of that visible component, the
ids no longer visible under \"missing\", the callback's VALUE and the
SCRIPTS to run."
  (let ((found '()) (missing '()))
    (dolist (id ids)
      (let ((component (find-visible id root)))
        (if component
            (push (cons id (with-canvas-to-string () (render-component component))) found)
            (push id missing))))
    (with-output-to-string (out)
      (format out "{\"fragments\":{~{~A~^,~}},\"missing\":[~{~A~^,~}],\"value\":~A,\"scripts\":[~{~A~^,~}]}"
              (loop for (id . html) in (nreverse found)
                    collect (format nil "~A:~A" (json-string id) (json-string html)))
              (mapcar #'json-string (nreverse missing))
              (json-value value)
              (mapcar #'json-string scripts)))))
