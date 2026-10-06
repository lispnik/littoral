SBCL ?= sbcl
PORT ?= 8080

.PHONY: test run lint clean

test:
	$(SBCL) --non-interactive --eval '(asdf:test-system :littoral)'

# The examples on http://127.0.0.1:$(PORT)/ with a REPL in the terminal.
run:
	$(SBCL) --eval '(asdf:load-system :littoral/examples)' --eval '(littoral:start :port $(PORT))'

lint:
	ocicl lint src examples tests

clean:
	rm -rf ~/.cache/common-lisp/*/$(CURDIR)
