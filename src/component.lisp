;;;; component.lisp — the unit of a page
;;;;
;;;; A component renders itself with RENDER, names the components it
;;;; embeds with CHILDREN, the objects whose state the back button should
;;;; restore with STATES, and contributes to the document head with
;;;; UPDATE-ROOT, STYLE and SCRIPT.  CALL puts another component in its
;;;; place until that one ANSWERs.

(in-package #:littoral)

(defvar *component-counter* (list 0)
  "A cell whose CAR numbers components; it is never reset, so ids stay
unique for the life of the image.")

(defun next-component-id ()
  "A fresh component id, unique in this image."
  ;; ATOMIC-INCF takes CAR as a place, not FIRST.
  (format nil "c~(~36R~)" (sb-ext:atomic-incf (car *component-counter*))))

(defclass component ()
  ((id :initform (next-component-id) :reader component-id
       :documentation "Unique and stable: the DOM id AJAX updates target.")
   (decorations :initform '() :accessor decorations
                :documentation "Outermost first.  Replaced, never mutated, so
backtracking can snapshot it as a value."))
  (:documentation "A stateful piece of user interface.  Subclass it and
specialise RENDER."))

(defgeneric render (component)
  (:documentation "Write COMPONENT's HTML to *CANVAS*.  Embedded components
are written with RENDER-COMPONENT, never by calling RENDER on them.")
  (:method ((component component))
    (text (format nil "~A" (class-name (class-of component))))))

(defgeneric children (component)
  (:documentation "The components COMPONENT renders.  Halos, update-root,
backtracking and AJAX lookups find components through this.")
  (:method ((component component)) '()))

(defgeneric states (component)
  (:documentation "Objects whose slots are snapshotted after every action
and restored when the user goes back to an earlier page.  Return COMPONENT
itself to make all its slots backtrack.")
  (:method ((component component)) '()))

(defgeneric style (component)
  (:documentation "CSS text this component adds to the page head, or NIL.")
  (:method ((component component)) nil))

(defgeneric script (component)
  (:documentation "JavaScript text this component adds to the page, or NIL.")
  (:method ((component component)) nil))

(defgeneric initial-request (component request)
  (:documentation "Called on the root component when its session starts,
with the request that started it.  A bookmarked URL is read back here with
REQUEST-EXTRA-PATH and REQUEST-PARAMETER.")
  (:method ((component component) request)
    (declare (ignore request))
    nil))

;;; The document head

(defclass html-root ()
  ((title :initform nil :accessor root-title)
   (stylesheets :initform '() :accessor root-stylesheets)
   (scripts :initform '() :accessor root-scripts)
   (styles :initform '() :accessor root-styles)
   (inline-scripts :initform '() :accessor root-inline-scripts))
  (:documentation "The document head a page collects from UPDATE-ROOT: title, stylesheets and scripts."))

(defun add-stylesheet (root url)
  "Link the stylesheet at URL from the page."
  (pushnew url (root-stylesheets root) :test #'string=))

(defun add-script (root url)
  "Load the script at URL in the page."
  (pushnew url (root-scripts root) :test #'string=))

(defun add-style (root css)
  "Add the CSS text CSS to the page head."
  (pushnew css (root-styles root) :test #'string=))

(defun add-inline-script (root js)
  "Add the JavaScript text JS at the end of the page."
  (pushnew js (root-inline-scripts root) :test #'string=))

(defgeneric update-root (component root)
  (:documentation "Contribute COMPONENT's title, stylesheets and scripts to
the HTML-ROOT of the page.  Call CALL-NEXT-METHOD to keep STYLE and SCRIPT.")
  (:method ((component component) root)
    (let ((css (style component)) (js (script component)))
      (when css (add-style root css))
      (when js (add-inline-script root js)))))

;;; Bookmarkable URLs

(defclass page-url ()
  ((path :initform '() :accessor url-path
         :documentation "Segments after the application's path, in order.")
   (parameters :initform '() :accessor url-parameters
               :documentation "Alist of query parameters, in order."))
  (:documentation "What UPDATE-URL methods add to the URL of a page."))

(defun add-to-path (url &rest segments)
  "Append SEGMENTS (strings, or anything PRINC prints) to URL's path."
  (setf (url-path url) (append (url-path url) (mapcar #'princ-to-string segments)))
  url)

(defun add-parameter (url key &optional value)
  "Add the query parameter KEY (with VALUE, unless NIL) to URL."
  (when (member key '("_s" "_k") :test #'string=)
    (error "~S is reserved for littoral's own parameters." key))
  (setf (url-parameters url)
        (append (url-parameters url) (list (cons key (and value (princ-to-string value))))))
  url)

(defgeneric update-url (component url)
  (:documentation "Add to URL, a PAGE-URL, whatever would let a bookmark of
this page come back to it.  Called on every visible component, parents
first; read it back in INITIAL-REQUEST with REQUEST-EXTRA-PATH and
REQUEST-PARAMETER.")
  (:method ((component component) url)
    (declare (ignore url))
    nil))

;;; Rendering through decorations

(defclass decoration ()
  ()
  (:documentation "Wraps a component's rendering or intercepts its answers.
Specialise RENDER-DECORATION and call RENDER-INNER for what it wraps."))

(defgeneric decoration-kind (decoration)
  (:documentation ":GLOBAL decorations sit outside a delegation and so stay
visible while another component is shown in their owner's place; :LOCAL
ones sit inside it.")
  (:method ((decoration decoration)) :local))

(defgeneric render-decoration (decoration component)
  (:documentation "Render DECORATION around COMPONENT; RENDER-INNER renders
the rest of the chain.")
  (:method ((decoration decoration) component)
    (declare (ignore component))
    (render-inner)))

(defvar *render-inner* nil)

(defun render-inner ()
  "Render whatever the current decoration wraps."
  (funcall *render-inner*))

(defun render-chain (component chain)
  "Render COMPONENT through the decorations in CHAIN, outermost first."
  (if (null chain)
      (render component)
      (let ((*render-inner* (lambda () (render-chain component (rest chain)))))
        (render-decoration (first chain) component))))

(defun render-decorated (component)
  "Render COMPONENT through all its decorations."
  (render-chain component (decorations component)))

(defclass updatable ()
  ()
  (:documentation "Mixin for components AJAX can re-render: each is written
inside an element carrying its COMPONENT-ID."))

(defgeneric render-component (component)
  (:documentation "Render COMPONENT where it is embedded: through its
decorations, inside a halo when halos are on.")
  (:method ((component component))
    (render-decorated component))
  (:method :around ((component updatable))
    (emit-tag "div" (list :id (component-id component) :class "lt-updatable")
              (lambda () (call-next-method)))))

;;; Visiting the tree

(defun visible-children (component)
  "The components COMPONENT shows now: its delegate when it has called
another, otherwise its CHILDREN."
  (let ((delegation (find-if (lambda (d) (typep d 'delegation)) (decorations component))))
    (if delegation
        (list (delegation-delegate delegation))
        (children component))))

(defun map-visible (function component)
  "Call FUNCTION on COMPONENT and everything visible below it, parents first."
  (let ((seen (make-hash-table :test 'eq)))
    (labels ((walk (c)
               (unless (gethash c seen)
                 (setf (gethash c seen) t)
                 (funcall function c)
                 (mapc #'walk (visible-children c)))))
      (walk component))))

(defun find-visible (id root)
  "The component with ID visible from ROOT, or NIL."
  (map-visible (lambda (c) (when (string= (component-id c) id)
                             (return-from find-visible c)))
               root)
  nil)

(defun active-component (component)
  "The component actually showing in COMPONENT's place."
  (let ((delegation (find-if (lambda (d) (typep d 'delegation)) (decorations component))))
    (if delegation
        (active-component (delegation-delegate delegation))
        component)))
