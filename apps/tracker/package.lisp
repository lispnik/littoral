;;;; package.lisp

(defpackage #:littoral-tracker
  (:use #:cl #:littoral #:littoral.html)
  (:documentation "Tracker: an issue tracker built with Littoral.")
  (:export #:tracker #:start-tracker #:register-tracker #:*tracker-file* #:reset-tracker
           #:find-user #:add-user #:all-issues #:create-issue))
