;;;; bench.lisp — how fast is the request cycle?  Run with make bench.
;;;;
;;;; In-process, through the same fake browser the tests use, so it measures
;;;; littoral (callbacks, snapshots, rendering) and not the network.

(in-package #:littoral/tests)

(defun seconds-since (start)
  (/ (- (get-internal-real-time) start) internal-time-units-per-second))

(defmacro timing ((label count &optional (unit "op")) &body body)
  `(let ((start (get-internal-real-time)))
     ,@body
     (let ((elapsed (seconds-since start)))
       (format t "~&~40A ~8D ~(~A~)s  ~9,1F µs/~(~A~)  ~9,0F ~(~A~)s/s~%"
               ,label ,count ,unit (/ (* elapsed 1000000) ,count) ,unit
               (/ ,count (max elapsed 1/1000000)) ,unit))))

(defun bench-clicks (path link count)
  (let ((b (make-instance 'browser)))
    (visit b path)
    (timing ((format nil "~A: click ~S" path link) count "click")
      (dotimes (i count) (click b link)))))

(defun bench-renders (path count)
  (let ((b (make-instance 'browser)))
    (visit b path)
    (let ((url (browser-url b)))
      (timing ((format nil "~A: render a page" path) count "page")
        (dotimes (i count) (visit b url))))))

(defun bench-snapshots (label root count)
  (let ((size (length (snapshot-entries (take-snapshot root)))))
    (timing ((format nil "snapshot ~A (~D objects)" label size) count "snapshot")
      (dotimes (i count) (take-snapshot root)))))

(defun bench-todo (items deep count)
  (let ((todo (make-instance 'littoral-examples:todo-list)))
    (setf (slot-value todo 'littoral-examples::items)
          (loop for i below items
                collect (make-instance 'littoral-examples::todo-item :title (format nil "Item ~D" i))))
    (if deep
        (let ((wrapped (make-instance 'deep-todo :todo todo)))
          (bench-snapshots (format nil "todo ~D items, deep" items) wrapped count))
        (bench-snapshots (format nil "todo ~D items" items) todo count))))

(defclass deep-todo (component)
  ((todo :initarg :todo :reader deep-todo)))

(defmethod states ((self deep-todo))
  (list (deep (deep-todo self))))

(defun run-benchmarks ()
  (format t "~&Littoral ~A on ~A ~A~%~%"
          (asdf:component-version (asdf:find-system :littoral))
          (lisp-implementation-type) (lisp-implementation-version))
  (with-fresh-applications (("/counter" 'littoral-examples:counter :mode :deployment)
                            ("/multi" 'littoral-examples:multi-counter :mode :deployment)
                            ("/store" 'littoral-examples:store :mode :deployment)
                            ("/wiki" 'littoral-examples:wiki :mode :deployment))
    (littoral-examples:reset-wiki)
    ;; Warm up.
    (bench-clicks "/counter" "++" 200)
    (format t "~%Request cycle (each click is an action request and a render request):~%")
    (bench-clicks "/counter" "++" 5000)
    (bench-clicks "/multi" "++" 2000)
    (bench-clicks "/store" "Add" 2000)
    (bench-renders "/store" 2000)
    (bench-renders "/wiki" 2000)
    (format t "~%Snapshots:~%")
    (bench-snapshots "counter" (make-instance 'littoral-examples:counter) 100000)
    (bench-snapshots "store" (make-instance 'littoral-examples:store) 20000)
    (bench-todo 100 nil 20000)
    (bench-todo 100 t 20000)
    (format t "~%Concurrency (16 threads, separate sessions):~%")
    (let ((start (get-internal-real-time))
          (applications littoral::*applications*))
      (mapc #'sb-thread:join-thread
            (loop repeat 16
                  collect (sb-thread:make-thread
                           (lambda ()
                             (let ((littoral::*applications* applications)
                                   (b (make-instance 'browser)))
                               (visit b "/counter")
                               (dotimes (i 500) (click b "++")))))))
      (let ((elapsed (seconds-since start)))
        (format t "~40A ~8D clicks  ~9,0F clicks/s~%" "/counter from 16 threads" 8000 (/ 8000 elapsed))))))
