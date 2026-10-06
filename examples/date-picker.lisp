;;;; date-picker.lisp — a reusable component that answers a date
;;;;
;;;; Dates are (YEAR MONTH DAY) lists.  Call it like any dialog:
;;;;
;;;;   (call self (make-instance 'date-picker :prompt "Deliver when?"
;;;;                                          :earliest (add-days (today) 1)))

(in-package #:littoral-examples)

(defun today ()
  (multiple-value-bind (s m h day month year) (decode-universal-time (get-universal-time))
    (declare (ignore s m h))
    (list year month day)))

(defun date-universal-time (date)
  (destructuring-bind (year month day) date
    (encode-universal-time 0 0 12 day month year 0)))

(defun add-days (date days)
  (multiple-value-bind (s m h day month year)
      (decode-universal-time (+ (date-universal-time date) (* days 86400)) 0)
    (declare (ignore s m h))
    (list year month day)))

(defun date< (a b)
  (< (date-universal-time a) (date-universal-time b)))

(defun weekday (date)
  "0 for Monday through 6 for Sunday."
  (nth-value 6 (decode-universal-time (date-universal-time date) 0)))

(defun days-in-month (year month)
  (if (= month 2)
      (if (and (zerop (mod year 4)) (or (plusp (mod year 100)) (zerop (mod year 400)))) 29 28)
      (nth (1- month) '(31 28 31 30 31 30 31 31 30 31 30 31))))

(defparameter *month-names*
  #("January" "February" "March" "April" "May" "June" "July" "August"
    "September" "October" "November" "December"))

(defun format-date (date)
  (destructuring-bind (year month day) date
    (format nil "~A ~D, ~D" (aref *month-names* (1- month)) day year)))

(defclass date-picker (component)
  ((prompt :initarg :prompt :initform "Choose a date" :reader picker-prompt)
   (earliest :initarg :earliest :initform nil :reader picker-earliest
             :documentation "The first selectable date, or NIL for any.")
   (year :accessor picker-year)
   (month :accessor picker-month)))

(defmethod initialize-instance :after ((self date-picker) &key)
  (destructuring-bind (year month day) (or (picker-earliest self) (today))
    (declare (ignore day))
    (setf (picker-year self) year
          (picker-month self) month)))

;; The month on show backtracks with the back button.
(defmethod states ((self date-picker))
  (list self))

(defun shift-month (picker delta)
  (let ((index (+ (* 12 (picker-year picker)) (1- (picker-month picker)) delta)))
    (setf (picker-year picker) (floor index 12)
          (picker-month picker) (1+ (mod index 12)))))

(defun selectable-p (picker date)
  (let ((earliest (picker-earliest picker)))
    (or (null earliest) (not (date< date earliest)))))

(defmethod render ((self date-picker))
  (let* ((year (picker-year self))
         (month (picker-month self))
         (lead (weekday (list year month 1)))
         (days (days-in-month year month)))
    (div (:class "date-picker lt-dialog")
      (h3 () (text (picker-prompt self)))
      (div (:class "date-picker-nav")
        (anchor (:callback (lambda () (shift-month self -1)) :title "Previous month") "‹")
        (strong () (text (format nil "~A ~D" (aref *month-names* (1- month)) year)))
        (anchor (:callback (lambda () (shift-month self 1)) :title "Next month") "›"))
      (table (:class "date-picker-grid")
        (thead () (tr () (dolist (d '("Mo" "Tu" "We" "Th" "Fr" "Sa" "Su")) (th () (text d)))))
        (tbody ()
          (loop for week-start from (- lead) below days by 7
                do (tr ()
                     (loop for offset from 0 below 7
                           for day = (+ week-start offset 1)
                           do (td ()
                                (when (<= 1 day days)
                                  (let ((date (list year month day)))
                                    (if (selectable-p self date)
                                        (anchor (:callback (lambda () (answer self date))
                                                 :class (when (equal date (today)) "today"))
                                          (text day))
                                        (span (:class "unavailable") (text day)))))))))))
      (p () (anchor (:callback (lambda () (answer self nil))) "Cancel")))))

(defmethod style ((self date-picker))
  ".date-picker-nav { display: flex; gap: 1rem; align-items: center; margin-bottom: .4rem; }
.date-picker-nav a { text-decoration: none; font-size: 1.3rem; }
.date-picker-grid td, .date-picker-grid th { width: 2.2rem; text-align: center; padding: .2rem; }
.date-picker-grid a { display: block; text-decoration: none; border-radius: 4px; }
.date-picker-grid a:hover { background: var(--lt-accent); color: var(--lt-bg); }
.date-picker-grid a.today { outline: 1px solid var(--lt-accent); }
.date-picker-grid .unavailable { color: var(--lt-muted); opacity: .5; }")
