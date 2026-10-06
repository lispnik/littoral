;;;; util.lisp — escaping, keys, small helpers

(in-package #:littoral)

(defun html-escape (thing)
  "Return the printed representation of THING with HTML metacharacters escaped."
  (let ((string (if (stringp thing) thing (princ-to-string thing))))
    (if (not (find-if (lambda (c) (find c "<>&\"'")) string))
        string
        (with-output-to-string (out)
          (loop for c across string
                do (case c
                     (#\< (write-string "&lt;" out))
                     (#\> (write-string "&gt;" out))
                     (#\& (write-string "&amp;" out))
                     (#\" (write-string "&quot;" out))
                     (#\' (write-string "&#39;" out))
                     (otherwise (write-char c out))))))))

(defvar *key-alphabet* "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

(defun random-key (&optional (length 16))
  "A URL-safe key drawn from a cryptographic random source."
  (let ((bytes (ironclad:random-data length))
        (n (length *key-alphabet*)))
    (map 'string (lambda (b) (char *key-alphabet* (mod b n))) bytes)))

(defun now-seconds ()
  "The current universal time."
  (get-universal-time))

(defun url-with-params (path params)
  "PATH with the alist PARAMS appended as a query string.  A NIL value
emits the bare key, the way Seaside writes action callback ids."
  (if (null params)
      path
      (with-output-to-string (out)
        (write-string path out)
        (loop for (key . value) in params
              for first = t then nil
              do (write-char (if first #\? #\&) out)
                 (write-string (quri:url-encode key) out)
                 (when value
                   (write-char #\= out)
                   (write-string (quri:url-encode (princ-to-string value)) out))))))

(defun class-name-string (object)
  "The lower-case name of OBJECT's class."
  (string-downcase (symbol-name (class-name (class-of object)))))

(defun join-strings (strings &optional (separator " "))
  "STRINGS joined with SEPARATOR."
  (format nil (concatenate 'string "~{~A~^" separator "~}") strings))
