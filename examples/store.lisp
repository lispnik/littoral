;;;; store.lisp — Seaside's sushi store, the classic demo
;;;;
;;;; A catalog report and a cart share the page.  Checkout is a task whose
;;;; flow reads like the process it describes: review the cart, give an
;;;; address (validated), pick a delivery date (the reusable DATE-PICKER),
;;;; choose how to pay, confirm.  Any step can be cancelled, the back
;;;; button works throughout, and once the order is placed the checkout
;;;; pages are isolated so going back cannot order twice.

(in-package #:littoral-examples)

;;; Model

(defstruct dish name price description)  ; PRICE in cents

(defparameter *menu*
  (list (make-dish :name "Maguro nigiri" :price 450 :description "Tuna on rice")
        (make-dish :name "Sake nigiri" :price 400 :description "Salmon on rice")
        (make-dish :name "Hamachi nigiri" :price 500 :description "Yellowtail on rice")
        (make-dish :name "Unagi nigiri" :price 550 :description "Grilled eel, sweet glaze")
        (make-dish :name "Ebi nigiri" :price 380 :description "Cooked prawn on rice")
        (make-dish :name "Tamago nigiri" :price 300 :description "Sweet omelette")
        (make-dish :name "California roll" :price 750 :description "Crab, avocado, cucumber")
        (make-dish :name "Spicy tuna roll" :price 800 :description "Tuna, chilli mayonnaise")
        (make-dish :name "Kappa maki" :price 450 :description "Cucumber")
        (make-dish :name "Dragon roll" :price 1250 :description "Eel and avocado")
        (make-dish :name "Salmon sashimi" :price 1100 :description "Six slices")
        (make-dish :name "Miso soup" :price 300 :description "With tofu and wakame")
        (make-dish :name "Edamame" :price 400 :description "Salted soy beans")
        (make-dish :name "Green tea" :price 250 :description "Pot for one")))

(defun money (cents)
  "CENTS as dollars, such as $4.50."
  (format nil "$~D.~2,'0D" (floor cents 100) (mod cents 100)))

(defclass cart ()
  ((lines :initform '() :accessor cart-lines
          :documentation "Alist of DISH → quantity, in the order added."))
  (:documentation "The dishes chosen so far and how many of each."))

(defun cart-quantity (cart)
  "How many items are in CART."
  (reduce #'+ (cart-lines cart) :key #'cdr))

(defun cart-total (cart)
  "What CART costs, in cents."
  (reduce #'+ (cart-lines cart) :key (lambda (line) (* (dish-price (first line)) (rest line)))))

(defun add-to-cart (cart dish &optional (quantity 1))
  "Put QUANTITY more of DISH in CART."
  ;; Fresh conses throughout: snapshots share structure with the live cart.
  (setf (cart-lines cart)
        (if (assoc dish (cart-lines cart))
            (mapcar (lambda (line)
                      (if (eq (first line) dish) (cons dish (+ (rest line) quantity)) line))
                    (cart-lines cart))
            (append (cart-lines cart) (list (cons dish quantity))))))

(defun set-quantity (cart dish quantity)
  "Make CART hold QUANTITY of DISH, removing it at zero or NIL."
  (setf (cart-lines cart)
        (loop for line in (cart-lines cart)
              if (not (eq (first line) dish)) collect line
              else if (and quantity (plusp quantity)) collect (cons dish quantity))))

(defstruct address name street city postcode)

(define-description address
  ((name :required t :accessor address-name)
   (street :required t :accessor address-street)
   (city :required t :accessor address-city)
   (postcode :required t :accessor address-postcode
             :pattern "[0-9]+" :pattern-message "The postcode should be digits only.")))

(defvar *order-counter* (list 1000))

(defclass order ()
  ((number :initform (sb-ext:atomic-incf (car *order-counter*)) :reader order-number)
   (lines :initarg :lines :reader order-lines)
   (total :initarg :total :reader order-total)
   (address :initarg :address :reader order-address)
   (date :initarg :date :reader order-date)
   (payment :initarg :payment :reader order-payment))
  (:documentation "A placed order."))

;;; Small components used by the checkout

(defun render-lines (lines)
  "A table of cart LINES with their prices."
  (table (:class "lt-table cart-lines")
    (dolist (line lines)
      (tr () (td () (text (rest line)) " × ")
        (td () (text (dish-name (first line))))
        (td (:class "number") (text (money (* (rest line) (dish-price (first line))))))))))

(defclass cart-review (component)
  ((cart :initarg :cart :reader review-cart))
  (:documentation "Lets the shopper check and change the cart before checking out."))

(defmethod render ((self cart-review))
  (let ((cart (review-cart self)))
    (h2 () "Your order")
    (form ()
      (table (:class "lt-table cart-lines")
        (dolist (line (cart-lines cart))
          (let ((dish (first line)))
            (tr ()
              (td () (number-input (:value (rest line) :min 0 :class "qty"
                                    :label (format nil "How many ~A" (dish-name dish))
                                    :callback (lambda (n) (set-quantity cart dish n)))))
              (td () (text (dish-name dish)))
              (td (:class "number") (text (money (* (rest line) (dish-price dish)))))))))
      (p () "Total: " (strong () (text (money (cart-total cart)))))
      (div (:class "lt-buttons")
        (submit-button () "Update")
        (submit-button (:callback (lambda ()
                                    (unless (null (cart-lines cart)) (answer self t))))
          "Continue to delivery")
        (submit-button (:callback (lambda () (answer self nil))) "Back to the menu")))))

(defclass receipt (component)
  ((order :initarg :order :reader receipt-order))
  (:documentation "Thanks the shopper and shows what was ordered."))

(defmethod render ((self receipt))
  (let* ((order (receipt-order self))
         (a (order-address order)))
    (div (:class "lt-dialog receipt")
      (h2 () "Thank you! Order #" (text (order-number order)))
      (render-lines (order-lines order))
      (p () "Total " (strong () (text (money (order-total order)))) ", "
        (text (string-downcase (order-payment order))) ".")
      (p () "Delivering on " (strong () (text (format-date (order-date order)))) " to "
        (text (format nil "~A, ~A, ~A ~A" (address-name a) (address-street a)
                      (address-city a) (address-postcode a))) ".")
      (form () (submit-button (:callback (lambda () (answer self t))) "Back to the menu")))))

;;; The checkout task

(defclass checkout (task)
  ((cart :initarg :cart :reader checkout-cart))
  (:documentation "The checkout task: cart, address, date, payment, confirmation, receipt."))

(defun order-summary (cart address date payment)
  "The question asked before an order is placed."
  (format nil "Place an order for ~D item~:P, ~A, delivered ~A to ~A, paid by ~(~A~)?"
          (cart-quantity cart) (money (cart-total cart)) (format-date date)
          (address-name address) payment))

(define-flow checkout (self)
  (let ((cart (checkout-cart self))
        (isolation (begin-isolation)))
    (when (call self (make-instance 'cart-review :cart cart))
      (let ((address (call self (make-editor (make-address) :title "Where should we deliver?"
                                                            :save-label "Continue"))))
        (when address
          (let ((date (call self (make-instance 'date-picker
                                                :prompt "When should we deliver?"
                                                :earliest (add-days (today) 1)))))
            (when date
              (let ((payment (choose-from self '("Cash on delivery" "Invoice")
                                          "How will you pay?")))
                (when (and payment (confirm self (order-summary cart address date payment)))
                  (let ((order (make-instance 'order
                                              :lines (copy-alist (cart-lines cart))
                                              :total (cart-total cart)
                                              :address address :date date
                                              :payment payment)))
                    ;; From here the checkout pages are gone: the back
                    ;; button cannot return to "Place the order?".
                    (end-isolation isolation)
                    (call self (make-instance 'receipt :order order))
                    order))))))))))

;;; The shop window

(defclass cart-view (component)
  ((cart :initarg :cart :reader view-cart)
   (store :initarg :store :reader view-store))
  (:documentation "The cart beside the menu."))

(defmethod render ((self cart-view))
  (let ((cart (view-cart self)))
    (aside (:class "cart")
      (h2 () "Cart")
      (cond ((null (cart-lines cart))
             (p (:class "empty") "Nothing yet."))
            (t
             (ul ()
               (dolist (line (cart-lines cart))
                 (let ((dish (first line)))
                   (li () (text (rest line)) " × " (text (dish-name dish)) " "
                     (anchor (:callback (lambda () (set-quantity cart dish 0)) :title "Remove") "✕")))))
             (p () "Total " (strong () (text (money (cart-total cart)))))
             (anchor (:class "checkout" :callback (lambda () (start-checkout (view-store self))))
               "Checkout »"))))))

(defclass store (component)
  ((cart :initform (make-instance 'cart) :reader store-cart)
   (catalog :reader store-catalog)
   (cart-view :reader store-cart-view)
   (orders :initform '() :accessor store-orders)
   (notice :initform nil :accessor store-notice))
  (:documentation "The sushi store: menu, cart and past orders."))

(defmethod initialize-instance :after ((self store) &key)
  (setf (slot-value self 'cart-view)
        (make-instance 'cart-view :cart (store-cart self) :store self))
  (setf (slot-value self 'catalog)
        (make-instance
         'report
         :rows *menu*
         :batch-size 8
         :columns (list (column "Dish" #'dish-name)
                        (column "" #'dish-description :sortable nil)
                        (column "Price" #'dish-price :class "number"
                                :render (lambda (row price)
                                          (declare (ignore row))
                                          (text (money price))))
                        (column "" nil :sortable nil
                                :render (lambda (dish value)
                                          (declare (ignore value))
                                          (anchor (:class "add"
                                                   :callback (lambda ()
                                                               (add-to-cart (store-cart self) dish)
                                                               (setf (store-notice self) nil)))
                                            "Add")))))))

(defmethod states ((self store))
  (list self (store-cart self)))

(defmethod children ((self store))
  (list (store-catalog self) (store-cart-view self)))

(defun start-checkout (store)
  "Run a checkout for STORE's cart, recording the order it answers."
  (show store (make-instance 'checkout :cart (store-cart store))
        :on-answer (lambda (order)
                     (when order
                       (push order (store-orders store))
                       (setf (cart-lines (store-cart store)) '()
                             (store-notice store)
                             (format nil "Order #~D is on its way." (order-number order)))))))

(defmethod render ((self store))
  (header (:class "store-header")
    (h1 () "Sushi Store")
    (span (:class "cart-count")
      (text (format nil "~D item~:P in your cart" (cart-quantity (store-cart self))))))
  (when (store-notice self)
    (p (:class "lt-message notice") (text (store-notice self))))
  (div (:class "store-body")
    (section (:class "menu")
      (render-component (store-catalog self)))
    (render-component (store-cart-view self)))
  (when (store-orders self)
    (section (:class "orders")
      (h2 () "Your orders")
      (ul ()
        (dolist (order (store-orders self))
          (li () "#" (text (order-number order)) " — "
            (text (money (order-total order))) ", "
            (text (format-date (order-date order)))))))))

(defmethod style ((self store))
  ".store-header { display: flex; flex-wrap: wrap; gap: .4rem 1rem; justify-content: space-between; align-items: baseline; }
.store-body { display: grid; grid-template-columns: minmax(0, 1fr) 16rem; gap: 1.5rem; align-items: start; }
@media (max-width: 40rem) { .store-body { grid-template-columns: minmax(0, 1fr); } }
.cart { border: 1px solid var(--lt-border); border-radius: 6px; padding: .2rem 1rem 1rem;
        background: var(--lt-panel); }
.cart ul { padding-left: 1rem; } .cart a { text-decoration: none; }
.cart .checkout { display: inline-block; margin-top: .3rem; font-weight: 600; }
.notice { color: var(--lt-accent); }
input.qty { width: 4rem; }")
