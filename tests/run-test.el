;; Usage:
;;
;;   emacs -Q -l tests/run-test.el           # interactive mode
;;   emacs -batch -Q -l tests/run-test.el    # batch mode


;; Utils
(defun coffee-test-join-path (path &rest rest)
  "Join a list of PATHS with appropriate separator (such as /).

\(fn &rest paths)"
  (if rest
      (concat (file-name-as-directory path) (apply 'coffee-test-join-path rest))
    path))

(defvar coffee-test-dir (file-name-directory load-file-name))
(defvar coffee-root-dir (file-name-as-directory (expand-file-name ".." coffee-test-dir)))


;; Setup `load-path'
(mapc (lambda (p) (add-to-list 'load-path p))
      (list coffee-test-dir
            coffee-root-dir))


;; Use ERT from github when this Emacs does not have it
(unless (locate-library "ert")
  (add-to-list
   'load-path
   (coffee-test-join-path coffee-root-dir "lib" "ert" "lisp" "emacs-lisp"))
  (require 'ert-batch)
  (require 'ert-ui))


;; Load tests
(load "coffee-test")


;; Run tests
(if noninteractive
    (ert-run-tests-batch-and-exit)
  (ert t))
