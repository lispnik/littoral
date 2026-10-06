SBCL ?= sbcl
PORT ?= 8080

.PHONY: test e2e bench run lint clean

test:
	$(SBCL) --non-interactive --eval '(asdf:test-system :littoral)'

bench:
	$(SBCL) --non-interactive --eval '(asdf:load-system :littoral/bench)' \
	  --eval '(littoral/tests::run-benchmarks)' 2>&1 | grep -v '^;' | cat -s

# littoral.js in headless Chrome against a fresh server on $(E2E_PORT).
NODE ?= node
E2E_PORT ?= 8765
e2e:
	@if curl -s -o /dev/null http://127.0.0.1:$(E2E_PORT)/; then \
	  echo "Port $(E2E_PORT) is busy; set E2E_PORT." >&2; exit 1; fi; \
	$(SBCL) --non-interactive --eval '(asdf:load-system :littoral/examples)' \
	  --eval '(littoral:start :port $(E2E_PORT))' --eval '(sleep 600)' >/dev/null 2>&1 & pid=$$!; \
	for i in $$(seq 1 60); do curl -s -o /dev/null http://127.0.0.1:$(E2E_PORT)/ && break; sleep 1; done; \
	BASE=http://127.0.0.1:$(E2E_PORT) $(NODE) tests/e2e/browser.mjs; status=$$?; \
	kill -9 $$pid; exit $$status

# The examples on http://127.0.0.1:$(PORT)/ with a REPL in the terminal.
run:
	$(SBCL) --eval '(asdf:load-system :littoral/examples)' --eval '(littoral:start :port $(PORT))'

lint:
	ocicl lint src examples tests

clean:
	rm -rf ~/.cache/common-lisp/*/$(CURDIR)
