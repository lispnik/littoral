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
    (div (:class "lt-history")
      (h2 () "History")
      (p (:class "lt-help")
        "Every page this session has shown keeps a snapshot of its state. Open one to go back to it: "
        "its state comes back, as with the back button. Each page also shows what the action that made it changed.")
      (table (:class "lt-table")
        (tr () (th () "Page") (th () "Objects") (th () "Changed") (th ()))
        (loop for (page older) on pages
              for number downfrom (length pages)
              do (let* ((page page)
                        (changes (and older (snapshot-changes (continuation-snapshot older)
                                                              (continuation-snapshot page))))
                        (key (continuation-key page))
                        (open (member key (history-open self) :test #'string=)))
                   (tr ()
                     (td () (text (format nil "#~D" number)) (when (eq page (first pages)) (em () " newest")))
                     (td () (text (length (snapshot-entries (continuation-snapshot page)))))
                     (td () (if older
                                (if changes
                                    (anchor (:callback (lambda ()
                                                         (setf (history-open self)
                                                               (if open (remove key (history-open self) :test #'string=)
                                                                   (cons key (history-open self))))))
                                      (text (format nil "~D slot~:P ~:[▸~;▾~]" (length changes) open)))
                                    (text "nothing"))
                                (text "—")))
                     (td () (anchor (:href (page-url session page)) "Open")))
                   (when (and open changes)
                     (tr (:class "lt-history-changes")
                       (td (:colspan "4")
                         (table (:class "lt-table")
                           (tr () (th () "Object") (th () "Slot") (th () "Before") (th () "After"))
                           (loop for (object slot before after) in (subseq changes 0 (min 30 (length changes)))
                                 do (tr ()
                                      (td () (code () (text (object-title object))))
                                      (td () (code () (text (string-downcase (princ-to-string slot)))))
                                      (td () (code () (text (printed before 120))))
                                      (td () (code () (text (printed after 120)))))))))))))
      (p () (anchor (:callback (lambda () (answer self))) "Close")))))

;;; The component tree

(defclass component-tree (tool) ()
  (:documentation "The live component tree, with every component's slots."))

(defun render-component-node (component depth)
  (let* ((active (active-component component))
         ;; The tools themselves stand in for the page while they're open.
         (showing (if (typep active 'tool) component active))
         (kids (children showing)))
    (li ()
      (details (:open (and (< depth 2) t))
        (summary ()
          (code () (text (object-title component)))
          (unless (eq showing component)
            (text " → calling ") (code () (text (object-title showing))))
          (when kids (span (:class "lt-help") (text (format nil " ~D child~:[ren~;~]" (length kids) (= 1 (length kids)))))))
        (table (:class "lt-table lt-locals")
          (dolist (slot (object-slots showing))
            (unless (member slot '(decorations id))
              (tr () (th () (text (string-downcase (princ-to-string slot))))
                (td () (code () (text (if (slot-boundp showing slot) (printed (slot-value showing slot) 160) "unbound"))))))))
        (p () (anchor (:callback (lambda () (show (session-root *session*) (make-instance 'inspector :object showing))))
                "inspect"))
        (when kids
          (ul (:class "lt-tree-list")
            (dolist (kid kids)
              (render-component-node kid (1+ depth)))))))))

(defmethod render ((self component-tree))
  (div (:class "lt-component-tree")
    (h2 () "Components")
    (p (:class "lt-help") "The page's components as they are now, from the root down through "
      (code () "children") ". Open one to see its slots.")
    (ul (:class "lt-tree-list")
      (render-component-node (session-root *session*) 0))
    (p () (anchor (:callback (lambda () (answer self))) "Close"))))
