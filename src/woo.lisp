;;;; woo.lisp — server push without a thread per open page, on Woo
;;;;
;;;; Load littoral/woo and start with :server :woo.  On Hunchentoot every
;;;; open page with server push holds a thread; here each one is two libev
;;;; watchers on the event loop that accepted it:
;;;;
;;;;   - an async watcher, which PUBLISH and NOTIFY trigger from any thread
;;;;     with ev_async_send (the one libev call that is safe across threads),
;;;;     and whose callback renders and writes on the loop's own thread;
;;;;   - a repeating timer that writes keepalives and notices closed pages.
;;;;
;;;; Woo's writers and libev itself must only be used from the loop's
;;;; thread, so everything but ev_async_send happens in these callbacks.

(defpackage #:littoral.woo
  (:use #:cl)
  (:documentation "Serve Littoral's server push from Woo's event loops."))

(in-package #:littoral.woo)

(defstruct (entry (:constructor make-entry (stream writer socket loop async timer)))
  "One open stream and the watchers serving it."
  stream writer socket loop async timer)

(defvar *entries* (make-hash-table)
  "Watcher address → ENTRY, for the callbacks to find their stream.  Read and
changed only on loop threads, but several loops share it.")

(defvar *entries-lock* (sb-thread:make-mutex :name "littoral woo streams"))

(defun entry-for (watcher)
  (sb-thread:with-mutex (*entries-lock*)
    (gethash (cffi:pointer-address watcher) *entries*)))

(defun close-entry (entry)
  "Stop ENTRY's watchers and forget its stream.  On its loop's thread."
  (let ((loop (entry-loop entry)))
    (sb-thread:with-mutex (*entries-lock*)
      (remhash (cffi:pointer-address (entry-async entry)) *entries*)
      (remhash (cffi:pointer-address (entry-timer entry)) *entries*))
    (lev:ev-async-stop loop (entry-async entry))
    (lev:ev-timer-stop loop (entry-timer entry))
    (cffi:foreign-free (entry-async entry))
    (cffi:foreign-free (entry-timer entry))
    (littoral::unregister-event-stream (entry-stream entry))
    (when (woo.ev.socket:socket-open-p (entry-socket entry))
      (ignore-errors (funcall (entry-writer entry) nil :close t)))))

(defun live-p (entry)
  (and (woo.ev.socket:socket-open-p (entry-socket entry))
       (littoral::stream-live-p (entry-stream entry))))

(defmacro serving ((entry watcher) &body body)
  "Run BODY for the ENTRY of WATCHER, closing it when its page has gone or
writing fails."
  `(let ((,entry (entry-for ,watcher)))
     (when ,entry
       (littoral::with-sane-printing ()
         (handler-case
             (if (live-p ,entry)
                 (progn ,@body)
                 (close-entry ,entry))
           (error () (close-entry ,entry)))))))

(cffi:defcallback stream-woken :void ((loop :pointer) (watcher :pointer) (events :int))
  (declare (ignore loop events))
  (serving (entry watcher)
    (littoral::serve-stream (entry-stream entry) (entry-writer entry))))

(cffi:defcallback stream-tick :void ((loop :pointer) (watcher :pointer) (events :int))
  (declare (ignore loop events))
  (serving (entry watcher)
    (littoral::keep-stream-alive (entry-stream entry) (entry-writer entry))))

(defun utf-8-writer (writer)
  "WRITER, with strings encoded to UTF-8 before Woo sees them.  Woo's
streaming writer sends each character of a string as one byte (its
WRITE-SOCKET-STRING writes CHAR-CODE), while announcing the UTF-8 length,
so a non-ASCII character such as an ellipsis would derail the stream."
  (lambda (body &rest options)
    (apply writer
           (if (stringp body) (sb-ext:string-to-octets body :external-format :utf-8) body)
           options)))

(defun open-stream (socket stream writer)
  "Serve STREAM from the event loop running this call.  Woo calls the
response function on that loop's thread, so *EVLOOP* is the right loop."
  (let* ((writer (utf-8-writer writer))
         (loop woo.ev:*evloop*)
         (async (cffi:foreign-alloc '(:struct lev:ev-async)))
         (timer (cffi:foreign-alloc '(:struct lev:ev-timer)))
         (interval (coerce littoral::*keepalive-seconds* 'double-float))
         (entry (make-entry stream writer socket loop async timer)))
    (lev:ev-async-init async 'stream-woken)
    (lev:ev-timer-init timer 'stream-tick interval interval)
    (sb-thread:with-mutex (*entries-lock*)
      (setf (gethash (cffi:pointer-address async) *entries*) entry
            (gethash (cffi:pointer-address timer) *entries*) entry))
    (lev:ev-async-start loop async)
    (lev:ev-timer-start loop timer)
    (setf (littoral::stream-waker stream) (lambda () (lev:ev-async-send loop async)))
    (littoral::register-event-stream stream)
    (funcall writer (format nil "retry: 3000~%~%"))))

(setf littoral:*async-stream-opener* 'open-stream)
