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
  (every nil))

(defun ajax (&key callback update)
  "Run the thunk CALLBACK in the background, then re-render the component
or list of components UPDATE."
  (%make-ajax-spec :callback callback
                   :update (alexandria:ensure-list update)))

(defun ajax-update (&rest components)
  "Re-render COMPONENTS, running no callback first."
  (ajax :update components))

(defun periodical (seconds &key callback update)
  "For a :PERIODICAL attribute: every SECONDS, run CALLBACK and re-render UPDATE."
  (%make-ajax-spec :callback callback
                   :update (alexandria:ensure-list update)
                   :every seconds))

(defmethod emit-attribute (key (value ajax-spec) stream)
  ;; data-lt-on-click="CALLBACK-ID;ID ID…" — data-lt-periodical prefixes
  ;; the interval in milliseconds.
  (let ((id (if (ajax-spec-callback value) (register :action (ajax-spec-callback value)) ""))
        (targets (join-strings (mapcar #'component-id (ajax-spec-update value)))))
    (format stream " data-lt-~(~A~)=\"~@[~D;~]~A;~A\""
            key
            (and (ajax-spec-every value) (round (* 1000 (ajax-spec-every value))))
            id
            (html-escape targets))))

(defun json-string (string)
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for c across string
          do (case c
               (#\" (write-string "\\\"" out))
               (#\\ (write-string "\\\\" out))
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (#\Tab (write-string "\\t" out))
               (t (if (< (char-code c) 32)
                      (format out "\\u~4,'0X" (char-code c))
                      (write-char c out)))))
    (write-char #\" out)))

(defun render-fragments (ids root)
  "JSON object mapping each id to the HTML of that visible component, and
the ids no longer visible to a list under \"missing\"."
  (let ((found '()) (missing '()))
    (dolist (id ids)
      (let ((component (find-visible id root)))
        (if component
            (push (cons id (with-canvas-to-string () (render-component component))) found)
            (push id missing))))
    (with-output-to-string (out)
      (format out "{\"fragments\":{~{~A~^,~}},\"missing\":[~{~A~^,~}]}"
              (loop for (id . html) in (nreverse found)
                    collect (format nil "~A:~A" (json-string id) (json-string html)))
              (mapcar #'json-string (nreverse missing))))))
