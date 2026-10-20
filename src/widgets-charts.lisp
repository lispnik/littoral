;;;; widgets-charts.lisp — pie and donut charts, stacked bars and scatter plots
;;;;
;;;;   (pie-chart '(("Email" . 41) ("Chat" . 23) ("Phone" . 9)) :title "Support" :donut t)
;;;;   (stacked-bar-chart '(("Open" 4 6 3) ("Closed" 9 7 12)) :x-labels '("Q1" "Q2" "Q3"))
;;;;   (scatter-chart '(("Trees" (2.1 . 12) (3.4 . 19))) :x-label "Age" :y-label "Height")
;;;;
;;;; Inline SVG like BAR-CHART's: a figure with a caption, a key, and the
;;;; data as a table for screen readers.

(in-package #:littoral)

(defun nice-range (low high &optional (ticks 4))
  "A round step and the multiples of it either side of LOW and HIGH: three
values, LOW and HIGH rounded outwards and the step."
  (let* ((low (if (= low high) (1- low) low))
         (high (if (= low high) (1+ high) high))
         (step (nice-step (- high low) ticks)))
    (values (* step (floor low step)) (* step (ceiling high step)) step)))

(defun percent-text (part whole)
  "PART of WHOLE as a whole percentage, such as \"42%\"."
  (format nil "~D%" (if (plusp whole) (round (* 100 part) whole) 0)))

;;; Pie and donut charts

(defun arc-point (cx cy r angle)
  "The point at ANGLE (radians, clockwise from twelve o'clock) on the circle
of radius R about CX, CY, as \"X Y\"."
  (format nil "~A ~A" (svg-number (+ cx (* r (sin angle)))) (svg-number (- cy (* r (cos angle))))))

(defun slice-path (cx cy r inner from to)
  "SVG path data for the slice of the circle of radius R about CX, CY from
angle FROM to TO, cut out to radius INNER (0 for a pie)."
  (let ((large (if (> (- to from) pi) 1 0)))
    (cond ((>= (- to from) (* 2 pi 0.9999))
           ;; A whole circle: two half arcs (and a hole, for a donut).
           (format nil "M~A A~A ~A 0 1 1 ~A A~A ~A 0 1 1 ~AZ~@[~A~]"
                   (arc-point cx cy r 0) (svg-number r) (svg-number r) (arc-point cx cy r pi)
                   (svg-number r) (svg-number r) (arc-point cx cy r 0)
                   (when (plusp inner)
                     (format nil " M~A A~A ~A 0 1 0 ~A A~A ~A 0 1 0 ~AZ"
                             (arc-point cx cy inner 0) (svg-number inner) (svg-number inner) (arc-point cx cy inner pi)
                             (svg-number inner) (svg-number inner) (arc-point cx cy inner 0)))))
          ((plusp inner)
           (format nil "M~A A~A ~A 0 ~D 1 ~A L~A A~A ~A 0 ~D 0 ~AZ"
                   (arc-point cx cy r from) (svg-number r) (svg-number r) large (arc-point cx cy r to)
                   (arc-point cx cy inner to) (svg-number inner) (svg-number inner) large (arc-point cx cy inner from)))
          (t
           (format nil "M~A ~A L~A A~A ~A 0 ~D 1 ~AZ"
                   (svg-number cx) (svg-number cy) (arc-point cx cy r from) (svg-number r) (svg-number r) large
                   (arc-point cx cy r to))))))

(defun pie-chart (data &key (title "") (size 220) donut (format-value #'princ-to-string))
  "Write a pie chart of DATA, a list of (LABEL . VALUE) with VALUE a
non-negative number, as accessible SVG like BAR-CHART's: a figure captioned
by TITLE, a key, each slice titled with its label, value and share, and the
data as a table.  DONUT T cuts out the middle and writes the total there.
FORMAT-VALUE, a function of a number, writes the values.  SIZE is the
diameter in SVG units; the chart scales to fit."
  (let* ((total (reduce #'+ data :key (lambda (d) (max 0 (cdr d))) :initial-value 0))
         (r (/ size 2)) (inner (if donut (* r 0.58) 0)))
    (chart-figure
     title
     (mapcar (lambda (d) (list (princ-to-string (car d)) (funcall format-value (cdr d))
                               (percent-text (max 0 (cdr d)) total)))
             data)
     (lambda (id)
       (with-output-to-string (out)
         (format out "<svg class=\"lt-chart-svg lt-chart-pie\" viewBox=\"0 0 ~D ~D\" role=\"img\" aria-labelledby=\"~A\">"
                 size size id)
         (if (zerop total)
             (format out "<circle class=\"lt-chart-grid\" cx=\"~A\" cy=\"~A\" r=\"~A\" fill=\"none\"/>"
                     (svg-number r) (svg-number r) (svg-number (1- r)))
             (let ((angle 0))
               (loop for (label . value) in data for n from 0
                     when (plusp value)
                       do (let ((to (+ angle (* 2 pi (/ value total)))))
                            (format out "<path class=\"lt-chart-slice ~A\" d=\"~A\"~:[~; fill-rule=\"evenodd\"~]><title>~A: ~A (~A)</title></path>"
                                    (series-class n) (slice-path r r (1- r) inner angle to)
                                    (and donut (= value total))
                                    (h:html-escape (princ-to-string label)) (h:html-escape (funcall format-value value))
                                    (percent-text value total))
                            (setf angle to)))))
         (when donut
           (format out "<text class=\"lt-chart-total\" x=\"~A\" y=\"~A\" text-anchor=\"middle\" dominant-baseline=\"middle\">~A</text>"
                   (svg-number r) (svg-number r) (h:html-escape (funcall format-value total))))
         (format out "</svg>")))
     (lambda () (chart-key (mapcar #'car data))))))

;;; Stacked bars

(defun stacked-bar-chart (series &key (title "") (width 480) (height 220) x-labels (format-value #'princ-to-string))
  "Write a bar chart with a bar for each point of SERIES, a list of (NAME .
VALUES) with the values all the same length and non-negative, each bar
the series' values stacked in order.  It is drawn like LINE-CHART: a
figure captioned by TITLE, a key, X-LABELS naming the bars, FORMAT-VALUE
writing the values and the axis, and the data as a table."
  (let* ((count (reduce #'max series :key (lambda (s) (length (rest s))) :initial-value 0))
         (sums (loop for i below count
                     collect (loop for s in series sum (max 0 (or (nth i (rest s)) 0)))))
         (top (max 1 (reduce #'max sums :initial-value 0)))
         (step (nice-step top 4))
         (top (* step (ceiling top step)))
         (left 44) (bottom 28) (right 8) (above 8)
         (plot-w (- width left right)) (plot-h (- height bottom above))
         (slot (/ plot-w (max 1 count)))
         (bar-labels (or (mapcar #'princ-to-string x-labels) (loop for i from 1 to count collect (princ-to-string i)))))
    (chart-figure
     title
     (cons (cons "" bar-labels)
           (mapcar (lambda (s) (cons (princ-to-string (first s)) (mapcar format-value (rest s)))) series))
     (lambda (id)
       (with-output-to-string (out)
         (format out "<svg class=\"lt-chart-svg\" viewBox=\"0 0 ~D ~D\" role=\"img\" aria-labelledby=\"~A\" preserveAspectRatio=\"xMidYMid meet\">" width height id)
         (loop for tick from 0 to top by step
               for y = (+ above (* plot-h (- 1 (/ tick top))))
               do (format out "<line class=\"lt-chart-grid\" x1=\"~A\" x2=\"~A\" y1=\"~A\" y2=\"~A\"/><text class=\"lt-chart-axis\" x=\"~A\" y=\"~A\" text-anchor=\"end\">~A</text>"
                          left (- width right) (svg-number y) (svg-number y) (- left 6) (svg-number (+ y 4))
                          (h:html-escape (funcall format-value tick))))
         (loop for i below count
               for label in bar-labels
               for x = (+ left (* i slot) (* slot 0.15))
               do (let ((base 0))
                    (loop for (name . values) in series for n from 0
                          for value = (max 0 (or (nth i values) 0))
                          when (plusp value)
                            do (let ((y0 (* plot-h (/ base top))) (h (* plot-h (/ value top))))
                                 (format out "<rect class=\"lt-chart-segment ~A\" x=\"~A\" y=\"~A\" width=\"~A\" height=\"~A\"><title>~A, ~A: ~A</title></rect>"
                                         (series-class n) (svg-number x) (svg-number (- (+ above plot-h) y0 h))
                                         (svg-number (* slot 0.7)) (svg-number h)
                                         (h:html-escape (princ-to-string name)) (h:html-escape label)
                                         (h:html-escape (funcall format-value value)))
                                 (incf base value))))
                  (format out "<text class=\"lt-chart-axis\" x=\"~A\" y=\"~A\" text-anchor=\"middle\">~A</text>"
                          (svg-number (+ x (* slot 0.35))) (- height 8) (h:html-escape label)))
         (format out "</svg>")))
     (lambda () (chart-key (mapcar #'first series))))))

;;; Scatter plots

(defun scatter-mark (out n x y title)
  "Write series N's mark at X, Y, titled TITLE: each series has a shape of
its own as well as a colour."
  (let ((x (svg-number x)) (y (svg-number y)) (class (series-class n)))
    (ecase (mod n 4)
      (0 (format out "<circle class=\"lt-chart-point ~A\" cx=\"~A\" cy=\"~A\" r=\"4\"><title>~A</title></circle>" class x y title))
      (1 (format out "<rect class=\"lt-chart-point ~A\" x=\"~A\" y=\"~A\" width=\"7\" height=\"7\" transform=\"translate(-3.5 -3.5)\"><title>~A</title></rect>"
                 class x y title))
      (2 (format out "<path class=\"lt-chart-point ~A\" d=\"M0 -5 L4.5 3.5 L-4.5 3.5Z\" transform=\"translate(~A ~A)\"><title>~A</title></path>"
                 class x y title))
      (3 (format out "<path class=\"lt-chart-point ~A\" d=\"M0 -5 L5 0 L0 5 L-5 0Z\" transform=\"translate(~A ~A)\"><title>~A</title></path>"
                 class x y title)))))

(defun scatter-chart (series &key (title "") (width 480) (height 260) (x-label "") (y-label "")
                               (format-x #'princ-to-string) (format-y #'princ-to-string))
  "Write a scatter plot of SERIES, a list of (NAME . POINTS) with each point
\(X . Y), both real numbers, as accessible SVG: a figure captioned by
TITLE, a key when there is more than one series, X-LABEL and Y-LABEL naming
the axes, and the points as a table.  Each series has its own colour and
shape.  FORMAT-X and FORMAT-Y write the coordinates and the axes."
  (let* ((points (mapcan (lambda (s) (copy-list (rest s))) series))
         (left 52) (bottom 40) (right 10) (above 10)
         (plot-w (- width left right)) (plot-h (- height bottom above)))
    (multiple-value-bind (x0 x1 x-step)
        (nice-range (reduce #'min points :key #'car :initial-value (if points (car (first points)) 0))
                    (reduce #'max points :key #'car :initial-value (if points (car (first points)) 1)))
      (multiple-value-bind (y0 y1 y-step)
          (nice-range (reduce #'min points :key #'cdr :initial-value (if points (cdr (first points)) 0))
                      (reduce #'max points :key #'cdr :initial-value (if points (cdr (first points)) 1)))
        (flet ((x (v) (+ left (* plot-w (/ (- v x0) (- x1 x0)))))
               (y (v) (+ above (* plot-h (- 1 (/ (- v y0) (- y1 y0)))))))
          (chart-figure
           title
           (cons (list "" (princ-to-string x-label) (princ-to-string y-label))
                 (loop for (name . points) in series
                       append (loop for (px . py) in points
                                    collect (list (princ-to-string name) (funcall format-x px) (funcall format-y py)))))
           (lambda (id)
             (with-output-to-string (out)
               (format out "<svg class=\"lt-chart-svg\" viewBox=\"0 0 ~D ~D\" role=\"img\" aria-labelledby=\"~A\" preserveAspectRatio=\"xMidYMid meet\">" width height id)
               (loop for tick from y0 to y1 by y-step
                     for yy = (y tick)
                     do (format out "<line class=\"lt-chart-grid\" x1=\"~A\" x2=\"~A\" y1=\"~A\" y2=\"~A\"/><text class=\"lt-chart-axis\" x=\"~A\" y=\"~A\" text-anchor=\"end\">~A</text>"
                                left (- width right) (svg-number yy) (svg-number yy) (- left 6) (svg-number (+ yy 4))
                                (h:html-escape (funcall format-y tick))))
               (loop for tick from x0 to x1 by x-step
                     for xx = (x tick)
                     do (format out "<line class=\"lt-chart-grid\" x1=\"~A\" x2=\"~A\" y1=\"~A\" y2=\"~A\"/><text class=\"lt-chart-axis\" x=\"~A\" y=\"~A\" text-anchor=\"middle\">~A</text>"
                                (svg-number xx) (svg-number xx) above (+ above plot-h) (svg-number xx) (+ above plot-h 14)
                                (h:html-escape (funcall format-x tick))))
               (format out "<text class=\"lt-chart-axis lt-chart-axis-title\" x=\"~A\" y=\"~A\" text-anchor=\"middle\">~A</text>"
                       (svg-number (+ left (/ plot-w 2))) (- height 4) (h:html-escape (princ-to-string x-label)))
               (format out "<text class=\"lt-chart-axis lt-chart-axis-title\" text-anchor=\"middle\" transform=\"translate(12 ~A) rotate(-90)\">~A</text>"
                       (svg-number (+ above (/ plot-h 2))) (h:html-escape (princ-to-string y-label)))
               (loop for (name . points) in series for n from 0
                     do (loop for (px . py) in points
                              do (scatter-mark out n (x px) (y py)
                                               (h:html-escape (format nil "~A: ~A, ~A" name (funcall format-x px) (funcall format-y py))))))
               (format out "</svg>")))
           (when (> (length series) 1)
             (lambda () (chart-key (mapcar #'first series))))))))))
