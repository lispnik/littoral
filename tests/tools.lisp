;;;; tools.lisp — toolbar, halos, inspector, config

(in-package #:littoral/tests)

(def-suite tools :in littoral)
(in-suite tools)

(test toolbar-only-in-development
  (with-fresh-applications (("/dev" 'littoral-examples:counter :mode :development)
                            ("/prod" 'littoral-examples:counter :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/dev")
      (is (search "lt-toolbar" (browser-html b)))
      (visit b "/prod")
      (is (not (search "lt-toolbar" (browser-html b)))))))

(test halos
  (with-fresh-applications (("/multi" 'littoral-examples:multi-counter :mode :development))
    (let ((b (make-instance 'browser)))
      (visit b "/multi")
      (is (not (search "lt-halo" (browser-html b))))
      (click b "Halos")
      (is (= 6 (length (cl-ppcre:all-matches-as-strings "class=\"lt-halo\"" (browser-html b)))))
      (is (has-text-p b "MULTI-COUNTER"))
      ;; Source view of the first counter.
      (click b "source")
      (is (search "&lt;h1&gt;" (browser-html b)))
      (click b "render")
      (click b "Halos off")
      (is (not (search "lt-halo" (browser-html b)))))))

(test inspector-edits-slots
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :development))
    (let ((b (make-instance 'browser)))
      (visit b "/counter")
      (click b "Halos")
      (click b "inspect")
      (is (has-text-p b "Inspector"))
      (is (has-text-p b "count"))
      ;; The count field is the second editable row (after id).
      (let ((names (let (r) (cl-ppcre:do-register-groups (n) ("<input type=\"text\" name=\"(\\d+)\"" (browser-html b))
                              (push n r))
                     (nreverse r))))
        (setf (browser-fields b) (list (cons (car (last names)) "41"))))
      (press b "Close")
      (click b "Halos off")
      (is (= 41 (count-shown b))))))

(test session-browser
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :development))
    (let ((a (make-instance 'browser)) (b (make-instance 'browser)))
      (visit a "/counter")
      (visit b "/counter")
      (click a "Sessions")
      (is (has-text-p a "(this one)"))
      (is (= 2 (length (littoral::list-sessions (find-application "/counter")))))
      (click a "expire")
      (is (= 1 (length (littoral::list-sessions (find-application "/counter")))))
      (click a "Close")
      (is (= 0 (count-shown a))))))

(test config-app
  (with-fresh-applications (("/config" 'littoral::config-root :mode :deployment)
                            ("/counter" 'littoral-examples:counter))
    (let ((b (make-instance 'browser)))
      (visit b "/config")
      (is (has-text-p b "Littoral Configuration"))
      (is (has-text-p b "/counter"))
      ;; Add an application.
      (fill-in b "new-path" "/todo")
      (fill-in b "new-class" "littoral-examples:todo-list")
      (fill-in b "new-title" "Todos")
      (press b "Add")
      (is (has-text-p b "Registered /todo."))
      (is (find-application "/todo"))
      ;; A bad class is refused.
      (fill-in b "new-path" "/bad")
      (fill-in b "new-class" "no-such-package::nothing")
      (press b "Add")
      (is (has-text-p b "does not name a component class"))
      (is (null (find-application "/bad")))
      ;; Configure /counter.
      (let ((href (cl-ppcre:register-groups-bind (h)
                      ("(?s)href=\"/counter\">/counter</a>.*?<a href=\"([^\"]*)\">configure</a>" (browser-html b))
                    (unescape h))))
        (visit b href))
      (is (has-text-p b "Configure /counter"))
      (fill-in b "title" "Counting")
      (select-option b "mode" "deployment")
      (fill-in b "timeout" "60")
      (set-checkbox b 0 t)
      (press b "Save")
      (let ((app (find-application "/counter")))
        (is (string= "Counting" (application-title app)))
        (is (eq :deployment (application-mode app)))
        (is (= 60 (application-session-timeout app)))
        (is (application-cookie-sessions-p app)))
      ;; Remove /todo, confirming.
      (let ((href (cl-ppcre:register-groups-bind (h)
                      ("(?s)href=\"/todo\">/todo</a>.*?<a href=\"([^\"]*)\">remove</a>" (browser-html b))
                    (unescape h))))
        (visit b href))
      (press b "Yes")
      (is (has-text-p b "Removed /todo."))
      (is (null (find-application "/todo"))))))

(test config-is-registered-by-default
  (is (find-application "/config")))
