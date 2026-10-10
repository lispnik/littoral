;;;; wizard.lisp — a description's fields in steps

(in-package #:littoral/tests)

(def-suite wizard :in littoral)
(in-suite wizard)

(test signing-up-in-steps
  (with-fresh-applications (("/wizard" 'littoral-examples:wizard-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/wizard")
      (click b "Sign up")
      (is (search "aria-current=\"step\"" (browser-html b)))
      ;; Step 1 checks its own fields.
      (press b "Next")
      (is (has-text-p b "Name is required."))
      (fill-in b "name" "Ada")
      (fill-in b "email" "ada@example.org")
      (press b "Next")
      (is (has-text-p b "Seats"))
      ;; Back keeps what was typed.
      (press b "Back")
      (is (search "value=\"ada@example.org\"" (browser-html b)))
      (press b "Next")
      (fill-in b "seats" "3")
      (press b "Next")
      (press b "Next")
      (is (has-text-p b "Review"))
      (is (has-text-p b "ada@example.org"))
      ;; The description's own check: a personal plan with three seats.
      (press b "Finish")
      (is (has-text-p b "Personal plans are for one person"))
      ;; Change the plan from the review, and finish.
      (is (has-text-p b "Personal"))                 ; the plan as it reads, not as posted
      (click-nth b "Change" 3)                       ; Name, Email, Plan, Seats
      (fill-in b "seats" "1")
      (press b "Next") (press b "Next")
      (press b "Finish")
      (is (has-text-p b "Welcome, Ada!")))))

(test cancelling-a-wizard
  (with-fresh-applications (("/wizard" 'littoral-examples:wizard-demo :mode :deployment))
    (let ((b (make-instance 'browser)))
      (visit b "/wizard")
      (click b "Sign up")
      (press b "Cancel")
      (is (has-text-p b "Sign up"))
      (is (not (has-text-p b "Welcome"))))))

(test wizards-without-writing
  (let* ((subscriber (make-instance 'littoral-examples:subscriber))
         (wizard (make-wizard subscriber :write nil :steps '(("All" littoral-examples::name)))))
    (is (= 1 (length (littoral::wizard-steps wizard))))
    (is (eq subscriber (littoral::wizard-object wizard)))))
