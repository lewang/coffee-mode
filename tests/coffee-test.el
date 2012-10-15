(require 'ert)

(require 'coffee-mode)

;; for "every" function
(require 'cl)

(defmacro coffee-test-with-test-buffer (&rest body)
  (declare (indent 0) (debug t))
  `(let ((test-buffer-name "*AWESOME test*"))
     (save-excursion
       (when (get-buffer test-buffer-name)
         (kill-buffer test-buffer-name))
       (switch-to-buffer (get-buffer-create test-buffer-name))
       ,@body)))

(defmacro coffee-test-with-common-setup (&rest body)
  (declare (indent 0) (debug t))
  `(coffee-test-with-test-buffer
    (coffee-mode)
    ,@body))


(ert-deftest coffee-test-basic-indent ()
  "Basic indentation.

Press TAB rotates through valid indentation points."
  (coffee-test-with-common-setup
   (insert "blah = 1")
   (execute-kbd-macro (read-kbd-macro "TAB"))
   (should (string-equal (buffer-string) "  blah = 1"))
   (execute-kbd-macro (read-kbd-macro "TAB"))
   (should (string-equal (buffer-string) "blah = 1"))
   (execute-kbd-macro (read-kbd-macro "TAB"))
   (should (string-equal (buffer-string) "  blah = 1"))))
