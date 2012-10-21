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

(defun test-press-key (key-string)
  (let* ((key (read-kbd-macro key-string)))
    (execute-kbd-macro key)))

(ert-deftest coffee-test-indent-basic ()
  "Basic indentation.

Press TAB rotates through valid indentation points."
  (coffee-test-with-common-setup
   (insert "
blah = ->
func()")
   (test-press-key "TAB")
   (should (string-equal "
blah = ->
  func()"
                         (buffer-string)))))

(ert-deftest coffee-test-indent-2-level ()
  "Rotate through valid indents."
  (coffee-test-with-common-setup
    (insert "
blah = ->
  if 1 == 1
  func()")
    (test-press-key "TAB")
    (should (string-equal "
blah = ->
  if 1 == 1
    func()"
                         (buffer-string))))
  (coffee-test-with-common-setup
    (insert "
blah = ->
  if 1 == 1
  func()")
    (test-press-key "TAB TAB")
    (should (string-equal "
blah = ->
  if 1 == 1
  func()"
                          (buffer-string))))
  (coffee-test-with-common-setup
    (insert "
blah = ->
  if 1 == 1
  func()")
    (test-press-key "TAB TAB TAB")
    (should (string-equal "
blah = ->
  if 1 == 1
func()"
                          (buffer-string)))))

(ert-deftest coffee-newline-and-indent ()
  " `coffee-newline-and-indent' works as expected."
  (coffee-test-with-common-setup
   (insert "
blah = ->")
   (test-press-key "C-j")
   (should (string-equal "
blah = ->
  "
                         (buffer-string)))))

(ert-deftest coffee-dedent-basic ()
  " `coffee-dedent-line-backspace' works as expected."
  (coffee-test-with-common-setup
   (insert "
blah = ->
  ")
   (test-press-key "DEL")
   (should (string-equal "
blah = ->
"
                         (buffer-string)))))

(ert-deftest coffee-dedent-from-bol ()
  " `coffee-dedent-line-backspace' from BOL deletes backwards one char."
  (coffee-test-with-common-setup
   (insert "
blah = ->
")
   (test-press-key "DEL")
   (should (string-equal "
blah = ->"
                         (buffer-string)))))

(ert-deftest coffee-dedent-from-jagged ()
  " `coffee-dedent-line-backspace' respects increments of `coffee-basic-indent' ."
  (coffee-test-with-common-setup
   (insert "
blah = ->
   ")
   (test-press-key "DEL")
   (should (string-equal "
blah = ->
  "
                         (buffer-string)))))

(ert-deftest coffee-dedent-in-string ()
  "dedent works as BACKSPACE in string."
  (coffee-test-with-common-setup
    (insert "\"
blah = ->
    \"")
    (backward-char)
    (test-press-key "DEL")
    (should (string-equal "\"
blah = ->
   \""
                          (buffer-string)))))