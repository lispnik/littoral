;;;; csp.lisp — the content security policy, stopping injected script

(in-package #:littoral-examples)

(defparameter *sample-attack*
  "<img src=\"x\" alt=\"\" onerror=\"document.title = 'hacked'\">
<button data-lt-on-click-js=\"document.title = 'hacked'\">An injected button</button>
<script>document.title = 'hacked'</script>")

(defclass csp-demo (component)
  ((markup :initform *sample-attack* :accessor demo-markup))
  (:documentation "Shows typed HTML unescaped, as a vulnerable page would, and
the policy stopping the script in it."))

(defmethod render ((self csp-demo))
  (h:h1 () "Content security policy")
  (h:p () "Every page carries a " (h:code () "Content-Security-Policy") " header that lets scripts run only if "
    "they carry the page's nonce, a random value new for each page. Littoral's own browser code is "
    "defined by the page's script and named by id in attributes, so even markup injected into a page "
    "can't bring code with it.")
  (h:p () "Below, whatever you type is written into the page " (h:strong () "unescaped") ", with "
    (h:code () "raw") ": the classic mistake behind cross-site scripting. Each attack tries to change "
    "this tab's title to \"hacked\".")
  (h:form ()
    (h:text-area (:id "markup" :label "HTML written into the page" :rows 5 :value (demo-markup self)
                :callback (lambda (v) (setf (demo-markup self) v))))
    (h:submit-button () "Write it into the page"))
  (h:div (:class "csp-sandbox")
    (h:raw (demo-markup self)))
  (h:p (:id "csp-report" :role "status") "Nothing blocked yet.")
  (h:p () "Applications choose with " (h:code () ":content-security-policy") ": "
    (h:code () ":strict") " (the default), their own policy string, or " (h:code () "nil") "."))

(defmethod script ((self csp-demo))
  ;; This script carries the nonce, so it runs; it reports what the policy stops.
  "(() => {
  let blocked = 0;
  document.addEventListener('securitypolicyviolation', (e) => {
    blocked++;
    document.getElementById('csp-report').textContent =
      'Blocked ' + blocked + ' attempt' + (blocked === 1 ? '' : 's') + ' to run script (' + e.violatedDirective + '). ' +
      'The title is still: ' + document.title;
  });
})();")

(defmethod style ((self csp-demo))
  ".csp-sandbox { border: 1px dashed var(--lt-error); border-radius: 6px; padding: .6rem; margin: .8rem 0; min-height: 2rem; }
.csp-sandbox img { max-width: 2rem; }")
