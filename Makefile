EMACS=emacs
EMACS23=emacs23
EMACS-OPTIONS=

.PHONY: test test-nw travis-ci show-version before-test

show-version:
	echo "*** Emacs version ***"
	echo "EMACS = `which ${EMACS}`"
	${EMACS} --version

install-ert:
	emacs --batch -L "${PWD}/lib/ert/lisp/emacs-lisp" --eval "(require 'ert)" || ( git clone git://github.com/ohler/ert.git lib/ert && cd lib/ert && git checkout 00aef6e43 )

clean:
	find . -name "*.elc" -exec /bin/rm {} \;

before-test: show-version install-ert clean

test: before-test
	${EMACS} -Q -L . -l tests/run-test.el

test-nw: before-test
	${EMACS} -Q -nw -L . -l tests/run-test.el

travis-ci: before-test
	echo ${EMACS-OPTIONS}
	${EMACS} -batch -Q -l tests/run-test.el
