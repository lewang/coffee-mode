;;; coffee-mode.el --- Major mode to edit CoffeeScript files in Emacs

;; Copyright (C) 2010 Chris Wanstrath

;; Version: 0.4.1
;; Keywords: CoffeeScript major mode
;; Author: Chris Wanstrath <chris@ozmm.org>
;; URL: http://github.com/defunkt/coffee-mode

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

;;; Commentary

;; Provides syntax highlighting, indentation support, imenu support,
;; a menu bar, and a few cute commands.

;; ## Indentation

;; ### TAB Theory

;; It goes like this: when you press `TAB`, we indent the line unless
;; doing so would make the current line more than two indentation levels
;; deepers than the previous line. If that's the case, remove all
;; indentation.

;; Consider this code, with point at the position indicated by the
;; caret:

;;     line1()
;;       line2()
;;       line3()
;;          ^

;; Pressing `TAB` will produce the following code:

;;     line1()
;;       line2()
;;         line3()
;;            ^

;; Pressing `TAB` again will produce this code:

;;     line1()
;;       line2()
;;     line3()
;;        ^

;; And so on. I think this is a pretty good way of getting decent
;; indentation with a whitespace-sensitive language.

;; ### Newline and Indent

;; We all love hitting `RET` and having the next line indented
;; properly. Given this code and cursor position:

;;     line1()
;;       line2()
;;       line3()
;;             ^

;; Pressing `RET` would insert a newline and place our cursor at the
;; following position:

;;     line1()
;;       line2()
;;       line3()

;;       ^

;; In other words, the level of indentation is maintained. This
;; applies to comments as well. Combined with the `TAB` you should be
;; able to get things where you want them pretty easily.

;; ### Indenters

;; `class`, `for`, `if`, and possibly other keywords cause the next line
;; to be indented a level deeper automatically.

;; For example, given this code and cursor position::

;;     class Animal
;;                 ^

;; Pressing enter would produce the following:

;;     class Animal

;;       ^

;; That is, indented a column deeper.

;; This also applies to lines ending in `->`, `=>`, `{`, `[`, and
;; possibly more characters.

;; So this code and cursor position:

;;     $('#demo').click ->
;;                        ^

;; On enter would produce this:

;;     $('#demo').click ->

;;       ^

;; Pretty slick.

;; Thanks to Jeremy Ashkenas for CoffeeScript, and to
;; http://xahlee.org/emacs/elisp_syntax_coloring.html, Jason
;; Blevins's markdown-mode.el and Steve Yegge's js2-mode for guidance.

;; TODO:
;; - Make prototype accessor assignments like `String::length: -> 10` pretty.
;; - mirror-mode - close brackets and parens automatically

;;; Code:

(require 'comint)
(require 'easymenu)
(require 'font-lock)

(eval-when-compile
  (require 'cl))

;;
;; Customizable Variables
;;

(defconst coffee-mode-version "0.4.1"
  "The version of `coffee-mode'.")

(defgroup coffee nil
  "A CoffeeScript major mode."
  :group 'languages)

(defcustom coffee-tab-width 2
  "The tab width to use when indenting."
  :type 'integer
  :group 'coffee)

(defcustom coffee-command "coffee"
  "The CoffeeScript command used for evaluating code."
  :type 'string
  :group 'coffee)

(defcustom js2coffee-command "js2coffee"
  "The js2coffee command used for evaluating code."
  :type 'string
  :group 'coffee)

(defcustom coffee-args-repl '("-i")
  "The arguments to pass to `coffee-command' to start a REPL."
  :type 'list
  :group 'coffee)

(defcustom coffee-args-compile '("-c")
  "The arguments to pass to `coffee-command' to compile a file."
  :type 'list
  :group 'coffee)

(defcustom coffee-compiled-buffer-name "*coffee-compiled*"
  "The name of the scratch buffer used for compiled CoffeeScript."
  :type 'string
  :group 'coffee)

(defcustom coffee-compile-jump-to-error t
  "Whether to jump to the first error if compilation fails.
Since the coffee compiler does not always include a line number in
its error messages, this is not always possible."
  :type 'boolean
  :group 'coffee)

(defcustom coffee-watch-buffer-name "*coffee-watch*"
  "The name of the scratch buffer used when using the --watch flag
with CoffeeScript."
  :type 'string
  :group 'coffee)

(defcustom coffee-mode-hook nil
  "Hook called by `coffee-mode'.  Examples:

      ;; If you don't want your compiled files to be wrapped
      (setq coffee-args-compile '(\"-c\" \"--bare\"))

      ;; Emacs key binding
      (define-key coffee-mode-map [(meta r)] 'coffee-compile-buffer)

      ;; Bleeding edge.
      (setq coffee-command \"~/dev/coffee\")

      ;; Compile '.coffee' files on every save
      (and (file-exists-p (buffer-file-name))
           (file-exists-p (coffee-compiled-file-name))
           (coffee-cos-mode t)))"
  :type 'hook
  :group 'coffee)

(defvar coffee-indent-happened nil)
(make-variable-buffer-local 'coffee-indent-happened)

(defvar coffee-mode-map
  (let ((map (make-sparse-keymap)))
    ;; key bindings
    (define-key map (kbd "A-r") 'coffee-compile-buffer)
    (define-key map (kbd "A-R") 'coffee-compile-region)
    (define-key map (kbd "A-M-r") 'coffee-repl)
    (define-key map [remap comment-dwim] 'coffee-comment-dwim)
    (define-key map [remap newline-and-indent] 'coffee-newline-and-indent)
    (define-key map (kbd "RET") 'coffee-newline-and-indent)
    (define-key map (kbd "C-c C-o C-s") 'coffee-cos-mode)
    (define-key map (kbd "DEL") 'coffee-backspace)
    (define-key map (kbd "SPC") 'coffee-space)
    map)
  "Keymap for CoffeeScript major mode.")

;;
;; Commands
;;

(defun coffee-repl ()
  "Launch a CoffeeScript REPL using `coffee-command' as an inferior mode."
  (interactive)

  (unless (comint-check-proc "*CoffeeREPL*")
    (set-buffer
     (apply 'make-comint "CoffeeREPL"
            "env"
            nil (append (list "NODE_NO_READLINE=1" coffee-command) coffee-args-repl))))

  (pop-to-buffer "*CoffeeREPL*"))

(defun coffee-compiled-file-name (&optional filename)
  "Returns the name of the JavaScript file compiled from a CoffeeScript file.
If FILENAME is omitted, the current buffer's file name is used."
  (concat (file-name-sans-extension (or filename (buffer-file-name))) ".js"))

(defun coffee-compile-file ()
  "Compiles and saves the current file to disk in a file of the same
base name, with extension `.js'.  Subsequent runs will overwrite the
file.

If there are compilation errors, point is moved to the first
(see `coffee-compile-jump-to-error')."
  (interactive)
  (let ((compiler-output (shell-command-to-string (coffee-command-compile (buffer-file-name)))))
    (if (string= compiler-output "")
        (message "Compiled and saved %s" (coffee-compiled-file-name))
      (let* ((msg (car (split-string compiler-output "[\n\r]+")))
             (line (and (string-match "on line \\([0-9]+\\)" msg)
                        (string-to-number (match-string 1 msg)))))
        (message msg)
        (when (and coffee-compile-jump-to-error line (> line 0))
          (goto-char (point-min))
          (forward-line (1- line)))))))

(defun coffee-compile-buffer ()
  "Compiles the current buffer and displays the JavaScript in a buffer
called `coffee-compiled-buffer-name'."
  (interactive)
  (save-excursion
    (coffee-compile-region (point-min) (point-max))))

(defun coffee-compile-region (start end)
  "Compiles a region and displays the JavaScript in a buffer called
`coffee-compiled-buffer-name'."
  (interactive "r")

  (let ((buffer (get-buffer coffee-compiled-buffer-name)))
    (when buffer
      (kill-buffer buffer)))

  (apply (apply-partially 'call-process-region start end coffee-command nil
                          (get-buffer-create coffee-compiled-buffer-name)
                          nil)
         (append coffee-args-compile (list "-s" "-p")))
  (switch-to-buffer (get-buffer coffee-compiled-buffer-name))
  (let ((buffer-file-name "tmp.js")) (set-auto-mode))
  (goto-char (point-min)))

(defun coffee-js2coffee-replace-region (start end)
  "Convert JavaScript in the region into CoffeeScript."
  (interactive "r")

  (let ((buffer (get-buffer coffee-compiled-buffer-name)))
    (when buffer
      (kill-buffer buffer)))

  (call-process-region start end
                       js2coffee-command nil
                       (current-buffer))
  (delete-region start end))

(defun coffee-version ()
  "Show the `coffee-mode' version in the echo area."
  (interactive)
  (message (concat "coffee-mode version " coffee-mode-version)))

(defun coffee-watch (dir-or-file)
  "Run `coffee-run-cmd' with the --watch flag on a directory or file."
  (interactive "fDirectory or File: ")
  (let ((coffee-compiled-buffer-name coffee-watch-buffer-name)
        (args (mapconcat 'identity (append coffee-args-compile (list "--watch" (expand-file-name dir-or-file))) " ")))
    (coffee-run-cmd args)))

;;
;; Menubar
;;

(easy-menu-define coffee-mode-menu coffee-mode-map
  "Menu for CoffeeScript mode"
  '("CoffeeScript"
    ["Compile File" coffee-compile-file]
    ["Compile Buffer" coffee-compile-buffer]
    ["Compile Region" coffee-compile-region]
    ["REPL" coffee-repl]
    "---"
    ["Version" coffee-version]
    ))

;;
;; Define Language Syntax
;;

;; String literals
(defvar coffee-string-regexp "\"\\([^\\]\\|\\\\.\\)*?\"\\|'\\([^\\]\\|\\\\.\\)*?'")

;; Instance variables (implicit this)
(defvar coffee-this-regexp "@\\(\\w\\|_\\)*\\|this")

;; Prototype::access
(defvar coffee-prototype-regexp "\\(\\(\\w\\|\\.\\|_\\| \\|$\\)+?\\)::\\(\\(\\w\\|\\.\\|_\\| \\|$\\)+?\\):")

;; Assignment
(defvar coffee-assign-regexp "\\(\\(\\w\\|\\.\\|_\\|$\\)+?\s*\\):")

;; Local Assignment
(defvar coffee-local-assign-regexp "\\(\\(_\\|\\w\\|\\$\\)+\\)\s+=")

;; Lambda
(defvar coffee-lambda-regexp "\\((.+)\\)?\\s *\\(->\\|=>\\)")

;; Namespaces
(defvar coffee-namespace-regexp "\\b\\(class\\s +\\(\\S +\\)\\)\\b")

;; Booleans
(defvar coffee-boolean-regexp "\\b\\(true\\|false\\|yes\\|no\\|on\\|off\\|null\\|undefined\\)\\b")

;; Regular Expressions
(defvar coffee-regexp-regexp "\\/\\(\\\\.\\|\\[\\(\\\\.\\|.\\)+?\\]\\|[^/
]\\)+?\\/")

;; JavaScript Keywords
(defvar coffee-js-keywords
      '("if" "else" "new" "return" "try" "catch"
        "finally" "throw" "break" "continue" "for" "in" "while"
        "delete" "instanceof" "typeof" "switch" "super" "extends"
        "class" "until" "loop"))

;; Reserved keywords either by JS or CS.
(defvar coffee-js-reserved
      '("case" "default" "do" "function" "var" "void" "with"
        "const" "let" "debugger" "enum" "export" "import" "native"
        "__extends" "__hasProp"))

;; CoffeeScript keywords.
(defvar coffee-cs-keywords
      '("then" "unless" "and" "or" "is" "own"
        "isnt" "not" "of" "by" "when"))

;; Iced CoffeeScript keywords
(defvar iced-coffee-cs-keywords
  '("await" "defer"))

;; Regular expression combining the above three lists.
(defvar coffee-keywords-regexp
  ;; keywords can be member names.
  (regexp-opt (append coffee-js-reserved
                      coffee-js-keywords
                      coffee-cs-keywords
                      iced-coffee-cs-keywords) 'symbols))


;; Create the list for font-lock. Each class of keyword is given a
;; particular face.
(defvar coffee-font-lock-keywords
  ;; *Note*: order below matters. `coffee-keywords-regexp' goes last
  ;; because otherwise the keyword "state" in the function
  ;; "state_entry" would be highlighted.
  `((,coffee-string-regexp . font-lock-string-face)
    (,coffee-this-regexp . font-lock-variable-name-face)
    (,coffee-prototype-regexp . font-lock-variable-name-face)
    (,coffee-assign-regexp . font-lock-type-face)
    (,coffee-local-assign-regexp 1 font-lock-variable-name-face)
    (,coffee-regexp-regexp . font-lock-constant-face)
    (,coffee-boolean-regexp . font-lock-constant-face)
    (,coffee-lambda-regexp . (2 font-lock-function-name-face))
    (,coffee-keywords-regexp 1 font-lock-keyword-face)))

;;
;; Helper Functions
;;

(defun coffee-comment-dwim (arg)
  "Comment or uncomment current line or region in a smart way.
For details, see `comment-dwim'."
  (interactive "*P")
  (require 'newcomment)
  (let ((deactivate-mark nil))
    (if (and (not (use-region-p))
             (coffee-line-is-blank))
        (let ((indent (save-excursion
                        (progn
                          (skip-chars-forward " \t\n")
                          (when (eobp)
                            (skip-chars-backward " \t\n")))
                        (current-indentation))))
          (delete-horizontal-space)
          (insert (make-string indent ? ) comment-start))
      (comment-dwim arg))))

(defun coffee-command-compile (file-name)
  "Run `coffee-command' to compile FILE."
  (let ((full-file-name (expand-file-name file-name)))
    (mapconcat 'identity (append (list coffee-command) coffee-args-compile (list full-file-name)) " ")))

(defun coffee-run-cmd (args)
  "Run `coffee-command' with the given arguments, and display the
output in a compilation buffer."
  (interactive "sArguments: ")
  (let ((compilation-buffer-name-function (lambda (this-mode)
                                            (generate-new-buffer-name coffee-compiled-buffer-name))))
    (compile (concat coffee-command " " args))))

;;
;; imenu support
;;

;; This is a pretty naive but workable way of doing it. First we look
;; for any lines that starting with `coffee-assign-regexp' that include
;; `coffee-lambda-regexp' then add those tokens to the list.
;;
;; Should cover cases like these:
;;
;; minus: (x, y) -> x - y
;; String::length: -> 10
;; block: ->
;;   print('potion')
;;
;; Next we look for any line that starts with `class' or
;; `coffee-assign-regexp' followed by `{` and drop into a
;; namespace. This means we search one indentation level deeper for
;; more assignments and add them to the alist prefixed with the
;; namespace name.
;;
;; Should cover cases like these:
;;
;; class Person
;;   print: ->
;;     print 'My name is ' + this.name + '.'
;;
;; class Policeman extends Person
;;   constructor: (rank) ->
;;     @rank: rank
;;   print: ->
;;     print 'My name is ' + this.name + " and I'm a " + this.rank + '.'
;;
;; TODO:
;; app = {
;;   window:  {width: 200, height: 200}
;;   para:    -> 'Welcome.'
;;   button:  -> 'OK'
;; }

(defun coffee-imenu-create-index ()
  "Create an imenu index of all methods in the buffer."
  (interactive)

  ;; This function is called within a `save-excursion' so we're safe.
  (goto-char (point-min))

  (let ((index-alist '()) assign pos indent ns-name ns-indent)
    ;; Go through every assignment that includes -> or => on the same
    ;; line or starts with `class'.
    (while (re-search-forward
            (concat "^\\(\\s *\\)"
                    "\\("
                      coffee-assign-regexp
                      ".+?"
                      coffee-lambda-regexp
                    "\\|"
                      coffee-namespace-regexp
                    "\\)")
            (point-max)
            t)

      ;; If this is the start of a new namespace, save the namespace's
      ;; indentation level and name.
      (when (match-string 8)
        ;; Set the name.
        (setq ns-name (match-string 8))

        ;; If this is a class declaration, add :: to the namespace.
        (setq ns-name (concat ns-name "::"))

        ;; Save the indentation level.
        (setq ns-indent (length (match-string 1))))

      ;; If this is an assignment, save the token being
      ;; assigned. `Please.print:` will be `Please.print`, `block:`
      ;; will be `block`, etc.
      (when (setq assign (match-string 3))
          ;; The position of the match in the buffer.
          (setq pos (match-beginning 3))

          ;; The indent level of this match
          (setq indent (length (match-string 1)))

          ;; If we're within the context of a namespace, add that to the
          ;; front of the assign, e.g.
          ;; constructor: => Policeman::constructor
          (when (and ns-name (> indent ns-indent))
            (setq assign (concat ns-name assign)))

          ;; Clear the namespace if we're no longer indented deeper
          ;; than it.
          (when (and ns-name (<= indent ns-indent))
            (setq ns-name nil)
            (setq ns-indent nil))

          ;; Add this to the alist. Done.
          (push (cons assign pos) index-alist)))

    ;; Return the alist.
    index-alist))

;;
;; Indentation
;;

(defun coffee-valid-indents ()
  "Return list of column numbers which are valid indents for current line.

List is in descending order."
  (let ((wants-indent (coffee-line-wants-indent))
        (previous-indent (coffee-previous-indent))
        sequence-start)
    (destructuring-bind (pre-list sequence-start)
        (if wants-indent
            (list
             (list (+ previous-indent coffee-tab-width))
             previous-indent)
          (list
           (list previous-indent
                 (+ previous-indent coffee-tab-width))
           (- previous-indent coffee-tab-width)))
      (nconc pre-list
             (number-sequence sequence-start 0 (- coffee-tab-width))))))

(defun coffee-line-indentable ()
  (save-excursion
    (back-to-indentation)
    (not (eq 'string (syntax-ppss-context (syntax-ppss))))))

(defun coffee-line-is-blank ()
  (save-excursion
    (forward-line 0)
    (skip-chars-forward " \t" (point-at-eol))
    (= (point) (point-at-eol))))

(defun coffee-point-in-indentation ()
  (save-excursion
    (skip-chars-forward " \t" (point-at-eol))
    (= (point) (progn (forward-line 0)
                      (skip-chars-forward " \t")
                      (point)))))

(defun coffee-space-should-indent (arg)
  (and (= 1 arg)
       (coffee-line-indentable)
       (coffee-point-in-indentation)
       (if (coffee-line-is-blank)
           (progn
             (delete-char (- (skip-chars-forward " \t" (point-at-eol))))
             t)
         (back-to-indentation)
         t)))

;;; The theory is explained in the README.

(defun coffee-indent-line ()
  "Indent current line as CoffeeScript."
  (interactive)
  (let* ((current-indent (current-indentation))
         (valid-indents (coffee-valid-indents))
         (next-indents (cdr (memq current-indent valid-indents))))
    (save-excursion
      ;; goals:
      ;; 1. first invocation moves to "correct" column
      ;; 2. move line to new valid column with every invocation
      (indent-line-to (if (and (or (not (eq this-command last-command))
                                   (zerop current-indent)
                                   (null next-indents))
                               (not (= current-indent (car valid-indents))))
                          (car valid-indents)
                        (car next-indents))))
    (when (< (current-column) (current-indentation))
      (back-to-indentation))
    (setq coffee-indent-happened t)))

(defun coffee-previous-indent ()
  "Return the indentation level of the previous non-blank line,
  rounding up to increments of `coffee-tab-width' "
  (save-excursion
    (goto-char (point-at-bol))
    (skip-chars-backward " \t\n")
    (let ((indent (if (bobp)
                      0
                    (current-indentation))))
      (* coffee-tab-width
         (ceiling
          (/ indent
             (float coffee-tab-width)))))))

(defun coffee-newline-and-indent ()
  "Insert a newline and indent it appropriately."
  (interactive)

  (let* ((prev-was-blank (coffee-line-is-blank))
         (prev-indent (if prev-was-blank
                               (current-column)
                             (current-indentation)))
         (point-in-indentation (and (not prev-was-blank)
                                    (<= (point) (+ (point-at-bol) prev-indent))))
         (new-indent (when (or prev-was-blank point-in-indentation)
                       prev-indent)))
    (delete-horizontal-space)
    (newline)
    (indent-to (or new-indent
                   (+ prev-indent
                      (if (coffee-line-wants-indent)
                          coffee-tab-width
                        0)))))

  ;; Last line was a comment so this one should probably be,
  ;; too. Makes it easy to write multi-line comments (like the one I'm
  ;; writing right now).
  (when (coffee-previous-line-is-comment)
    (insert "# ")))

(defun coffee-backspace (arg)
  "Unindent to increment of `coffee-tab-width' with ARG==1 when
called from first non-blank char of line.

Delete ARG spaces if ARG!=1."
  (interactive "*p")
  (if (and (coffee-space-should-indent arg)
           (not (bolp)))
      (let ((extra-space-count (% (current-column) coffee-tab-width)))
        (backward-delete-char-untabify
         (if (zerop extra-space-count)
             coffee-tab-width
           extra-space-count)))
    (backward-delete-char-untabify arg)))

(defun coffee-space (arg)
  "Indent to increment of `coffee-tab-width' with ARG==1 when
called from first non-blank char of line.

Insert ARG spaces if ARG!=1."
  (interactive "*p")
  (if (coffee-space-should-indent arg)
      (let* ((current-column (current-column))
             (missing-spaces-count
              (let ((jagged (% current-column coffee-tab-width)))
                (if (zerop jagged)
                    0
                  (- coffee-tab-width jagged)))))
        (indent-to-column
         (+ current-column
            (if (zerop missing-spaces-count)
                coffee-tab-width
              missing-spaces-count))))
    (funcall 'insert (make-string arg ? ))))

;; Indenters help determine whether the current line should be
;; indented further based on the content of the previous line. If a
;; line starts with `class', for instance, you're probably going to
;; want to indent the next line.

(defvar coffee-indenters-bol '("class" "for" "if" "try" "while" "else" "unless")
  "Keywords or syntax whose presence at the start of a line means the
next line should probably be indented.")

(defun coffee-indenters-bol-regexp ()
  "Builds a regexp out of `coffee-indenters-bol' words."
  (regexp-opt coffee-indenters-bol 'words))

(defvar coffee-indenters-eol '(?> ?{ ?\[)
  "Single characters at the end of a line that mean the next line
should probably be indented.")

(defun coffee-line-wants-indent ()
  "Return t if the current line should be indented relative to the
previous line."
  (interactive)

  (save-excursion
    (skip-chars-backward "\n\t ")
    (and (not (bobp))
         (or (memq (char-before (point-at-eol)) coffee-indenters-eol)
             (progn
               (back-to-indentation)
               (looking-at-p (coffee-indenters-bol-regexp)))))))

(defun coffee-previous-line-is-comment ()
  "Return t if the previous line is a CoffeeScript comment."
  (save-excursion
    (forward-line -1)
    (coffee-line-is-comment)))

(defun coffee-line-is-comment ()
  "Return t if the current line is a CoffeeScript comment."
  (save-excursion
    (backward-to-indentation 0)
    (= (char-after) (string-to-char "#"))))


;; (defun coffee-quote-syntax (n)
;;   "Put `syntax-table' property correctly on triple quote.
;; Used for syntactic keywords.  N is the match number (1, 2 or 3)."
;;   ;; From python-mode...
;;   ;;
;;   ;; Given a triple quote, we have to check the context to know
;;   ;; whether this is an opening or closing triple or whether it's
;;   ;; quoted anyhow, and should be ignored.  (For that we need to do
;;   ;; the same job as `syntax-ppss' to be correct and it seems to be OK
;;   ;; to use it here despite initial worries.)  We also have to sort
;;   ;; out a possible prefix -- well, we don't _have_ to, but I think it
;;   ;; should be treated as part of the string.

;;   ;; Test cases:
;;   ;;  ur"""ar""" x='"' # """
;;   ;; x = ''' """ ' a
;;   ;; '''
;;   ;; x '"""' x """ \"""" x
;;   (save-excursion
;;     (goto-char (match-beginning 0))
;;     (cond
;;      ;; Consider property for the last char if in a fenced string.
;;      ((= n 3)
;;       (let* ((font-lock-syntactic-keywords nil)
;; 	     (syntax (syntax-ppss)))
;; 	(when (eq t (nth 3 syntax))	; after unclosed fence
;; 	  (goto-char (nth 8 syntax))	; fence position
;; 	  ;; (skip-chars-forward "uUrR")	; skip any prefix
;; 	  ;; Is it a matching sequence?
;; 	  (if (eq (char-after) (char-after (match-beginning 2)))
;; 	      (eval-when-compile (string-to-syntax "|"))))))
;;      ;; Consider property for initial char, accounting for prefixes.
;;      ((or (and (= n 2)			; leading quote (not prefix)
;; 	       (not (match-end 1)))     ; prefix is null
;; 	  (and (= n 1)			; prefix
;; 	       (match-end 1)))          ; non-empty
;;       (let ((font-lock-syntactic-keywords nil))
;; 	(unless (eq 'string (syntax-ppss-context (syntax-ppss)))
;; 	  (eval-when-compile (string-to-syntax "|")))))
;;      ;; Otherwise (we're in a non-matching string) the property is
;;      ;; nil, which is OK.
;;      )))

(defun coffee-post-command-function ()
  (setq coffee-indent-happened nil))

;;
;; Define Major Mode
;;

(defvar coffee-syntax-table
  (let ((st (make-syntax-table)))
    ;; perl style comment: "# ..."
    (modify-syntax-entry ?# "< b" st)
    (modify-syntax-entry ?\n "> b" st)
    ;; single quote strings
    (modify-syntax-entry ?' "\"" st)
    st))


;;;###autoload
(define-derived-mode coffee-mode fundamental-mode
  "Coffee"
  "Major mode for editing CoffeeScript."

  ;; code for syntax highlighting
  (setq font-lock-defaults '((coffee-font-lock-keywords)))

  (make-local-variable 'comment-start)
  (setq comment-start "# ")


  ;; (setq font-lock-syntactic-keywords
  ;;       ;; Make outer chars of matching triple-quote sequences into generic
  ;;       ;; string delimiters.
  ;;       ;; First avoid a sequence preceded by an odd number of backslashes.
  ;;       `((,(concat "\\(?:^\\|[^\\]\\(?:\\\\.\\)*\\)" ;Prefix.
  ;;                   "\\(?:\\('\\)\\('\\)\\('\\)\\|\\(?1:\"\\)\\(?2:\"\\)\\(?3:\"\\)\\)")
  ;;          (1 (coffee-quote-syntax 1) nil lax)
  ;;          (2 (coffee-quote-syntax 2))
  ;;          (3 (coffee-quote-syntax 3)))))

  ;; indentation -- for those who want to use tabs to indent, set tab-width
  ;; appropriately.
  (make-local-variable 'indent-line-function)
  (setq indent-line-function 'coffee-indent-line)
  (set (make-local-variable 'tab-width) coffee-tab-width)

  ;; imenu
  (make-local-variable 'imenu-create-index-function)
  (setq imenu-create-index-function 'coffee-imenu-create-index)

  ;; no tabs
  (setq indent-tabs-mode nil)

  (add-hook 'post-command-hook #'coffee-post-command-function 'append t))


;;
;; Compile-on-Save minor mode
;;

(defvar coffee-cos-mode-line " CoS")
(make-variable-buffer-local 'coffee-cos-mode-line)

(define-minor-mode coffee-cos-mode
  "Toggle compile-on-save for coffee-mode.

Add `'(lambda () (coffee-cos-mode t))' to `coffee-mode-hook' to turn
it on by default."
  :group 'coffee-cos :lighter coffee-cos-mode-line
  (cond
   (coffee-cos-mode
    (add-hook 'after-save-hook 'coffee-compile-file nil t))
   (t
    (remove-hook 'after-save-hook 'coffee-compile-file t))))

(provide 'coffee-mode)

;;
;; On Load
;;

;; Run coffee-mode for files ending in .coffee.
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.coffee$" . coffee-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.iced$" . coffee-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("Cakefile" . coffee-mode))
;;; coffee-mode.el ends here
