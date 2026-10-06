;;;; report.lisp — a sortable, paged table

(in-package #:littoral-examples)

(defparameter *elements*
  '((1 "H" "Hydrogen" 1.008) (2 "He" "Helium" 4.0026) (3 "Li" "Lithium" 6.94)
    (4 "Be" "Beryllium" 9.0122) (5 "B" "Boron" 10.81) (6 "C" "Carbon" 12.011)
    (7 "N" "Nitrogen" 14.007) (8 "O" "Oxygen" 15.999) (9 "F" "Fluorine" 18.998)
    (10 "Ne" "Neon" 20.180) (11 "Na" "Sodium" 22.990) (12 "Mg" "Magnesium" 24.305)
    (13 "Al" "Aluminium" 26.982) (14 "Si" "Silicon" 28.085) (15 "P" "Phosphorus" 30.974)
    (16 "S" "Sulfur" 32.06) (17 "Cl" "Chlorine" 35.45) (18 "Ar" "Argon" 39.95)
    (19 "K" "Potassium" 39.098) (20 "Ca" "Calcium" 40.078) (21 "Sc" "Scandium" 44.956)
    (22 "Ti" "Titanium" 47.867) (23 "V" "Vanadium" 50.942) (24 "Cr" "Chromium" 51.996)
    (25 "Mn" "Manganese" 54.938) (26 "Fe" "Iron" 55.845) (27 "Co" "Cobalt" 58.933)
    (28 "Ni" "Nickel" 58.693) (29 "Cu" "Copper" 63.546) (30 "Zn" "Zinc" 65.38))
  "Number, symbol, name and standard atomic weight.")

(defclass element-table (component)
  ((report :reader element-report)
   (selected :initform nil :accessor selected-element)))

(defmethod initialize-instance :after ((self element-table) &key)
  (setf (slot-value self 'report)
        (make-instance
         'report
         :rows *elements*
         :batch-size 10
         :row-class (lambda (row) (when (eq row (selected-element self)) "selected"))
         :columns (list (column "No." #'first :class "number")
                        (column "Symbol" #'second)
                        (column "Name" #'third)
                        (column "Weight" #'fourth :class "number"
                                :render (lambda (row value)
                                          (declare (ignore row))
                                          (text (format nil "~,3F" value))))
                        (column "" nil :sortable nil
                                :render (lambda (row value)
                                          (declare (ignore value))
                                          (anchor (:callback (lambda () (setf (selected-element self) row)))
                                            "select")))))))

(defmethod states ((self element-table))
  (list self))

(defmethod children ((self element-table))
  (list (element-report self)))

(defmethod render ((self element-table))
  (h1 () "Elements")
  (p () "Click a heading to sort; click it again to reverse.")
  (render-component (element-report self))
  (when (selected-element self)
    (p () "Selected: " (strong () (text (third (selected-element self)))))))

(defmethod style ((self element-table))
  ".lt-report tr.selected td { background: var(--lt-panel); font-weight: 600; }")
