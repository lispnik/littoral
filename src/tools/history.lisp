;;;; history.lisp — development tools: the pages a session has shown, and its components
;;;;
;;;; History lists the session's pages, newest first, each with a link back to
;;;; it (opening an old page puts its state back: Littoral's back button, on
;;;; demand) and what the action that made it changed: which object, which
;;;; slot, the value before and after.  Components shows the live component
;;;; tree with every component's slots.

(in-package #:littoral)

(defun object-title (object)
  "A short name for OBJECT in the tools: its class, and its id if a component."
  (format nil "~(~A~)~@[ ~A~]" (class-name (class-of object))
          (and (typep object 'component) (component-id object))))

(defun same-value-p (a b)
  (or (eq a b) (equal a b)
      (and (numberp a) (numberp b) (= a b))
      (and (stringp a) (stringp b) (string= a b))))

(defun saved-slots (saved)
  "A snapshot entry's state as (SLOT . VALUE) pairs: entries for a component's
decorations alone have none to compare, and deep entries are unwrapped."
  (case (first saved)
    (:decorations '())
    (:deep (second saved))
    (otherwise saved)))

(defun snapshot-changes (older newer)
  "What changed between the snapshots OLDER and NEWER: (OBJECT SLOT BEFORE AFTER)."
  (let ((before (make-hash-table :test 'eq)))
    (dolist (entry (snapshot-entries older))
      (setf (gethash (car entry) before) (saved-slots (cdr entry))))
    (loop for (object . entry) in (snapshot-entries newer)
          for saved = (saved-slots entry)
          for old = (gethash object before)
          when (and old (listp saved) (listp old))
            append (loop for (slot . value) in saved
                         for previous = (assoc slot old :test #'equal)
                         when (and previous (not (same-value-p (cdr previous) value))
                                   ;; The tools' own coming and going isn't the application's.
                                   (not (and (eq slot 'decorations) (typep object 'component))))
                           collect (list object slot (cdr previous) value)))))

(defclass history-browser (tool)
  ((open :initform nil :accessor history-open :documentation "Keys of pages whose changes are shown."))
  (:documentation "The session's pages, each with a link back and what it changed."))

(defun session-pages (session)
  "SESSION's continuations, newest first."
  (loop for key in (session-continuation-order session)
        for continuation = (gethash key (session-continuations session))
        when continuation collect continuation))

(defmethod render ((self history-browser))
  (let* ((session *session*)
         (pages (session-pages session)))
    (h:div (:class "lt-history")
      (h:h2 () "History")
      (h:p (:class "lt-help")
        "Every page this session has shown keeps a snapshot of its state. Open one to go back to it: "
        "its state comes back, as with the back button. Each page also shows what the action that made it changed.")
      (h:table (:class "lt-table")
        (h:tr () (h:th () "Page") (h:th () "Objects") (h:th () "Changed") (h:th ()))
        (loop for (page older) on pages
              for number downfrom (length pages)
              do (let* ((page page)
                        (changes (and older (snapshot-changes (continuation-snapshot older)
                                                              (continuation-snapshot page))))
                        (key (continuation-key page))
                        (open (member key (history-open self) :test #'string=)))
                   (h:tr ()
                     (h:td () (h:text (format nil "#~D" number)) (when (eq page (first pages)) (h:em () " newest")))
                     (h:td () (h:text (length (snapshot-entries (continuation-snapshot page)))))
                     (h:td () (if older
                                (if changes
                                    (h:anchor (:callback (lambda ()
                                                         (setf (history-open self)
                                                               (if open (remove key (history-open self) :test #'string=)
                                                                   (cons key (history-open self))))))
                                      (h:text (format nil "~D slot~:P ~:[▸~;▾~]" (length changes) open)))
                                    (h:text "nothing"))
                                (h:text "—")))
                     (h:td () (h:anchor (:href (page-url session page)) "Open")))
                   (when (and open changes)
                     (h:tr (:class "lt-history-changes")
                       (h:td (:colspan "4")
                         (h:table (:class "lt-table")
                           (h:tr () (h:th () "Object") (h:th () "Slot") (h:th () "Before") (h:th () "After"))
                           (loop for (object slot before after) in (subseq changes 0 (min 30 (length changes)))
                                 do (h:tr ()
                                      (h:td () (h:code () (h:text (object-title object))))
                                      (h:td () (h:code () (h:text (string-downcase (princ-to-string slot)))))
                                      (h:td () (h:code () (h:text (printed before 120))))
                                      (h:td () (h:code () (h:text (printed after 120)))))))))))))
      (h:p () (h:anchor (:callback (lambda () (answer self))) "Close")))))

;;; The component tree

(defclass component-tree (tool) ()
  (:documentation "The live component tree, with every component's slots."))

(defun render-component-node (component depth)
  (let* ((active (active-component component))
         ;; The tools themselves stand in for the page while they're open.
         (showing (if (typep active 'tool) component active))
         (kids (children showing)))
    (h:li ()
      (h:details (:open (and (< depth 2) t))
        (h:summary ()
          (h:code () (h:text (object-title component)))
          (unless (eq showing component)
            (h:text " → calling ") (h:code () (h:text (object-title showing))))
          (when kids (h:span (:class "lt-help") (h:text (format nil " ~D child~:[ren~;~]" (length kids) (= 1 (length kids)))))))
        (h:table (:class "lt-table lt-locals")
          (dolist (slot (object-slots showing))
            (unless (member slot '(decorations id))
              (h:tr () (h:th () (h:text (string-downcase (princ-to-string slot))))
                (h:td () (h:code () (h:text (if (slot-boundp showing slot) (printed (slot-value showing slot) 160) "unbound"))))))))
        (h:p () (h:anchor (:callback (lambda () (show (session-root *session*) (make-instance 'inspector :object showing))))
                "inspect"))
        (when kids
          (h:ul (:class "lt-tree-list")
            (dolist (kid kids)
              (render-component-node kid (1+ depth)))))))))

(defmethod render ((self component-tree))
  (h:div (:class "lt-component-tree")
    (h:h2 () "Components")
    (h:p (:class "lt-help") "The page's components as they are now, from the root down through "
      (h:code () "children") ". Open one to see its slots.")
    (h:ul (:class "lt-tree-list")
      (render-component-node (session-root *session*) 0))
    (h:p () (h:anchor (:callback (lambda () (answer self))) "Close"))))
