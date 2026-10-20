;;;; widgets-schedule.lisp — a week or a day of timed events, moved by dragging
;;;;
;;;;   (make-instance 'event-calendar
;;;;     :events (lambda () (list '(:title "Standup" :start (2026 10 19 9 0) :minutes 15)))
;;;;     :on-move (lambda (event start) (reschedule event start)))

(in-package #:littoral)

;;; Days and minutes

(defun day-number (date)
  "The days from 1900-01-01 to DATE, (YEAR MONTH DAY)."
  (floor (encode-universal-time 0 0 0 (third date) (second date) (first date) 0) 86400))

(defun number-date (number)
  "The (YEAR MONTH DAY) DAY-NUMBER gives NUMBER."
  (multiple-value-bind (s m h day month year) (decode-universal-time (* number 86400) 0)
    (declare (ignore s m h))
    (list year month day)))

(defun add-days (date days)
  "The date DAYS after DATE (before, when DAYS is negative)."
  (number-date (+ (day-number date) days)))

(defun today ()
  "Today's date, (YEAR MONTH DAY)."
  (multiple-value-bind (s m h day month year) (decode-universal-time (get-universal-time))
    (declare (ignore s m h))
    (list year month day)))

(defun moment-minutes (moment)
  "MOMENT, (YEAR MONTH DAY HOUR MINUTE), as minutes from 1900."
  (destructuring-bind (year month day &optional (hour 0) (minute 0)) moment
    (+ (* 1440 (day-number (list year month day))) (* 60 hour) minute)))

(defun minutes-moment (minutes)
  "The (YEAR MONTH DAY HOUR MINUTE) MOMENT-MINUTES gives MINUTES."
  (multiple-value-bind (days rest) (floor minutes 1440)
    (append (number-date days) (multiple-value-list (floor rest 60)))))

(defun clock-text (minutes)
  "The time of day MINUTES after midnight, such as 09:30."
  (multiple-value-bind (hour minute) (floor (mod minutes 1440) 60)
    (format nil "~2,'0D:~2,'0D" hour minute)))

(defun iso-date (date)
  (format nil "~4,'0D-~2,'0D-~2,'0D" (first date) (second date) (third date)))

(defun parse-moment (text)
  "The (YEAR MONTH DAY HOUR MINUTE) in TEXT, written 2026-10-19 09:30, or NIL."
  (cl-ppcre:register-groups-bind ((#'parse-integer year month day hour minute))
      ("^(\\d{4})-(\\d{1,2})-(\\d{1,2})[ T](\\d{1,2}):(\\d{2})$" (string-trim " " text))
    (and (<= 1 month 12) (<= 1 day (days-in-month* year month)) (<= 0 hour 23) (<= 0 minute 59)
         (list year month day hour minute))))

;;; The schedule

(defclass event-calendar (component updatable)
  ((events :initarg :events :initform '() :reader schedule-events-designator
           :documentation "A list of events, or a function returning one on every render.")
   (view :initarg :view :initform :week :accessor event-calendar-view :documentation ":WEEK or :DAY.")
   (date :initarg :date :initform nil :accessor event-calendar-date
         :documentation "The day shown, or a day of the week shown, as (YEAR MONTH DAY).")
   (hours :initarg :hours :initform '(8 . 18) :reader schedule-hours
          :documentation "(FIRST . LAST): the day is shown from FIRST o'clock until LAST.")
   (step :initarg :step :initform 30 :reader schedule-step
         :documentation "The minutes of each row, and of each move.")
   (start-of :initarg :event-start :initform (lambda (event) (getf event :start)) :reader schedule-start-of)
   (minutes-of :initarg :event-minutes :initform (lambda (event) (getf event :minutes 60)) :reader schedule-minutes-of)
   (title-of :initarg :event-title :initform (lambda (event) (getf event :title)) :reader schedule-title-of)
   (event-key :initarg :event-key :initform #'identity :reader schedule-event-key
              :documentation "Function of an event giving what identifies it, compared with EQUAL.")
   (on-move :initarg :on-move :initform nil :reader schedule-on-move
            :documentation "Called with an event and its new start, (YEAR MONTH DAY HOUR MINUTE).")
   (selected :initform nil :accessor schedule-selected
             :documentation "The key of the event chosen for moving, or NIL.")
   (last-selected :initform nil :accessor schedule-last-selected))
  (:documentation "A week (Monday first) or a day of timed events, laid out
on a grid of hours, with links to the weeks or days before and after, to
today, and between the two views.  :EVENTS is a list, or a function
returning one, called on every render; by default each event is a plist
such as (:TITLE \"Standup\" :START (2026 10 19 9 0) :MINUTES 15), and
:EVENT-START, :EVENT-MINUTES and :EVENT-TITLE, functions of an event, read
other kinds.  :HOURS, (FIRST . LAST), is the part of the day shown (8 till
18); :STEP is the minutes in each row (30).  Events at the same time are
shown side by side.

With :ON-MOVE, a function of an event and its new start, events can be
dragged to another time or day, in steps of :STEP minutes.  Choosing an
event (a link) also shows buttons that move it a step earlier or later or
a day either way, which work from the keyboard and without JavaScript.
The schedule doesn't change events itself: :ON-MOVE does, and the events
are read again.  :EVENT-KEY, a function of an event (IDENTITY by default),
says which events are the same when they are read afresh.  :VIEW is :WEEK
or :DAY, and :DATE the day to show first, by default today."))

(defmethod initialize-instance :after ((self event-calendar) &key)
  (unless (event-calendar-date self) (setf (event-calendar-date self) (today))))

(defmethod states ((self event-calendar)) (list self))

(defun schedule-days (schedule)
  "The dates SCHEDULE shows."
  (let ((date (event-calendar-date schedule)))
    (if (eq (event-calendar-view schedule) :day)
        (list date)
        (let ((monday (add-days date (- (apply #'weekday date)))))
          (loop for i below 7 collect (add-days monday i))))))

(defun schedule-events (schedule)
  (let ((events (schedule-events-designator schedule)))
    (if (functionp events) (funcall events) events)))

(defun event-span (schedule event)
  "EVENT's start and end, in minutes from 1900."
  (let ((start (moment-minutes (funcall (schedule-start-of schedule) event))))
    (values start (+ start (max 1 (funcall (schedule-minutes-of schedule) event))))))

(defun shift-schedule (schedule direction)
  "Show the week or day after SCHEDULE's (before, with DIRECTION -1)."
  (setf (event-calendar-date schedule)
        (add-days (event-calendar-date schedule) (* direction (if (eq (event-calendar-view schedule) :day) 1 7)))))

(defun show-schedule-view (schedule view &optional date)
  "Show SCHEDULE's VIEW, :WEEK or :DAY, of DATE (by default the day it shows)."
  (setf (event-calendar-view schedule) view)
  (when date (setf (event-calendar-date schedule) date)))

(defun find-event (schedule key)
  (find key (schedule-events schedule) :key (schedule-event-key schedule) :test #'equal))

(defun select-event (schedule event)
  "Choose EVENT to move with the buttons, or with NIL, none."
  (let ((key (and event (funcall (schedule-event-key schedule) event))))
    (setf (schedule-selected schedule) key)
    (when key (setf (schedule-last-selected schedule) key))))

(defun move-event (schedule event start)
  "Call SCHEDULE's :ON-MOVE with EVENT and START, (YEAR MONTH DAY HOUR MINUTE).
The schedule then shows START's day if it wasn't showing it."
  (when (schedule-on-move schedule)
    (funcall (schedule-on-move schedule) event start)
    (let ((day (subseq start 0 3)))
      (unless (member day (schedule-days schedule) :test #'equal)
        (setf (event-calendar-date schedule) day)))))

(defun nudge-event (schedule minutes)
  "Move SCHEDULE's chosen event MINUTES later (earlier, when negative)."
  (let ((event (find-event schedule (schedule-selected schedule))))
    (when event
      (move-event schedule event (minutes-moment (+ (event-span schedule event) minutes))))))

(defun lay-out-day (spans)
  "Columns for SPANS, (START END EVENT) lists sorted by start, so that those
overlapping sit side by side: (EVENT START END COLUMN COLUMNS) lists."
  (let ((result '()) (cluster '()) (ends '()) (cluster-end nil))
    (flet ((close-cluster ()
             (let ((columns (length ends)))
               (dolist (entry cluster) (push (append entry (list columns)) result)))
             (setf cluster '() ends '())))
      (loop for (start end event) in spans
            do (when (and cluster-end (>= start cluster-end))
                 (close-cluster))
               (let ((column (position-if (lambda (e) (<= e start)) ends)))
                 (if column
                     (setf (nth column ends) end)
                     (setf column (length ends) ends (append ends (list end))))
                 (push (list event start end column) cluster)
                 (setf cluster-end (max (or cluster-end end) end))))
      (close-cluster))
    (nreverse result)))

(defun day-label (date)
  "DATE in full, for a heading or a sentence."
  (format nil "~A, ~A" (translate (nth (apply #'weekday date) *weekday-names*)) (apply #'localized-date date)))

(defun event-time-text (start end)
  (format nil "~A–~A" (clock-text start) (clock-text end)))

(defun schedule-title (days)
  (if (rest days)
      (format nil "~A – ~A" (apply #'localized-date (first days)) (apply #'localized-date (first (last days))))
      (day-label (first days))))

(defun render-schedule-head (schedule days)
  (let ((day (eq (event-calendar-view schedule) :day)))
    (flet ((link (label thunk &rest attributes)
             (%anchor (list* :callback thunk :on-click (ajax :callback thunk :update schedule) attributes)
                      (lambda () (h:text label)))))
      (h:div (:class "lt-schedule-head")
        (link "‹" (lambda () (shift-schedule schedule -1))
              :aria-label (translate (if day "Previous day" "Previous week")))
        (h:h3 () (h:text (schedule-title days)))
        (link "›" (lambda () (shift-schedule schedule 1))
              :aria-label (translate (if day "Next day" "Next week")))
        (link (translate "Today") (lambda () (setf (event-calendar-date schedule) (today))))
        (h:span (:class "lt-schedule-views" :role "group" :aria-label (translate "View"))
          (dolist (view '(:week :day))
            (let ((view view))
              (link (translate (if (eq view :week) "Week" "Day")) (lambda () (show-schedule-view schedule view))
                    :aria-current (when (eq view (event-calendar-view schedule)) "true")))))))))

(defun render-move-buttons (schedule event)
  (let* ((id (component-id schedule))
         (step (schedule-step schedule))
         (title (princ-to-string (funcall (schedule-title-of schedule) event))))
    (multiple-value-bind (start end) (event-span schedule event)
      (h:div (:class "lt-schedule-move" :role "group" :aria-label (translate "Move ~A" title))
        (h:p ()
          (h:strong () (h:text title))
          (h:text (format nil " ~A, ~A" (day-label (subseq (minutes-moment start) 0 3)) (event-time-text start end))))
        (h:div (:class "lt-buttons")
          (loop for (suffix label minutes) in `(("earlier" "Earlier" ,(- step)) ("later" "Later" ,step)
                                                ("before" "Day before" -1440) ("after" "Day after" 1440))
                for first = t then nil
                do (let ((minutes minutes))
                     (flet ((move () (nudge-event schedule minutes)))
                       (h:anchor (:id (format nil "~A-~A" id suffix) :class "lt-button" :autofocus first
                                :callback #'move :on-click (ajax :callback #'move :update schedule))
                         (h:text (translate label))))))
          (flet ((done () (select-event schedule nil)))
            (h:anchor (:id (format nil "~A-done" id) :class "lt-button"
                     :callback #'done :on-click (ajax :callback #'done :update schedule))
              (translate "Close"))))))))

(defun render-schedule-event (schedule event start end column columns first-minute slots)
  (let* ((step (schedule-step schedule))
         (title (princ-to-string (funcall (schedule-title-of schedule) event)))
         (key (funcall (schedule-event-key schedule) event))
         (from (/ (- (mod start 1440) first-minute) step))
         (to (/ (- (if (> (floor end 1440) (floor start 1440)) 1440 (mod end 1440)) first-minute) step))
         (top (max 0 (min from (1- slots))))
         (span (max 1 (- (min to slots) top)))
         (movable (schedule-on-move schedule)))
    (h:li (:class (list "lt-schedule-event" (when (equal key (schedule-selected schedule)) "lt-selected"))
         :style (format nil "--lt-from: ~A; --lt-span: ~A; --lt-col: ~D; --lt-cols: ~D"
                        (svg-number top) (svg-number span) column columns))
      (flet ((body ()
               (h:span (:class "lt-schedule-time") (h:text (event-time-text start end)))
               (h:text " ")
               (h:span (:class "lt-schedule-title") (h:text title))))
        (if movable
            (flet ((choose () (select-event schedule event)))
              (h:anchor (:class "lt-schedule-event-link"
                       :autofocus (and (null (schedule-selected schedule))
                                       (equal key (schedule-last-selected schedule)))
                       :aria-current (when (equal key (schedule-selected schedule)) "true")
                       :callback #'choose :on-click (ajax :callback #'choose :update schedule)
                       :move (ajax :callback (lambda (text)
                                               (let ((moment (parse-moment text)))
                                                 (when moment (move-event schedule event moment))))
                                   :update schedule :value "this.getAttribute('data-lt-to')"))
                (body)))
            (h:span (:class "lt-schedule-event-link") (body)))))))

(defmethod render ((self event-calendar))
  (let* ((days (schedule-days self))
         (first-hour (car (schedule-hours self)))
         (last-hour (cdr (schedule-hours self)))
         (step (schedule-step self))
         (first-minute (* 60 first-hour))
         (slots (ceiling (* 60 (- last-hour first-hour)) step))
         (today (today))
         (id (component-id self))
         (events (schedule-events self))
         (selected (and (schedule-selected self) (find-event self (schedule-selected self)))))
    (h:div (:class (list "lt-schedule" (format nil "lt-schedule-~(~A~)" (event-calendar-view self))))
      (render-schedule-head self days)
      (when (and selected (schedule-on-move self))
        (render-move-buttons self selected))
      (h:div (:class "lt-schedule-scroll" :tabindex "0" :role "region"
            :aria-label (schedule-title days))
        (h:div (:class "lt-schedule-grid"
              :style (format nil "--lt-days: ~D; --lt-slots: ~D; --lt-per-hour: ~A"
                             (length days) slots (svg-number (/ 60 step)))
              :data-lt-step step :data-lt-first first-minute :data-lt-slots slots)
          (h:div (:class "lt-schedule-times" :aria-hidden "true")
            (h:div (:class "lt-schedule-day-head"))
            (h:div (:class "lt-schedule-slots")
              (loop for hour from first-hour below last-hour
                    do (h:span (:class "lt-schedule-hour"
                              :style (format nil "--lt-from: ~A" (svg-number (/ (* 60 (- hour first-hour)) step))))
                         (h:text (clock-text (* 60 hour)))))))
          (loop for date in days for n from 0
                do (let* ((day (day-number date))
                          (heading (format nil "~A-day-~D" id n))
                          (spans (sort (loop for event in events
                                             append (multiple-value-bind (start end) (event-span self event)
                                                      (when (= (floor start 1440) day)
                                                        (list (list start end event)))))
                                       #'< :key #'first)))
                     (h:section (:class (list "lt-schedule-day" (when (equal date today) "lt-today"))
                               :aria-labelledby heading :data-lt-day (iso-date date))
                       (h:h4 (:id heading :class "lt-schedule-day-head")
                         (h:span (:aria-hidden "true")
                           (h:text (format nil "~A ~D" (translate (nth (apply #'weekday date) *weekday-names*)) (third date))))
                         (h:span (:class "lt-visually-hidden") (h:text (day-label date))))
                       (h:div (:class "lt-schedule-slots")
                         (when spans
                           (h:ol (:class "lt-schedule-events")
                             (loop for (event start end column columns) in (lay-out-day spans)
                                   do (render-schedule-event self event start end column columns
                                                             first-minute slots)))))))))))))
