SBCL ?= sbcl
PORT ?= 8080

.PHONY: new test e2e a11y bench load docs clean-check run tracker lint clean

test:
	$(SBCL) --non-interactive --eval '(asdf:test-system :littoral)'

# A new application: make new NAME=bookshop [DIR=~/src/bookshop]
new:
	@test -n "$(NAME)" || { echo "Usage: make new NAME=my-app [DIR=path]"; exit 2; }
	@$(SBCL) --noinform --non-interactive --eval '(asdf:load-system :littoral/generator)' \
	  --eval '(littoral.generator:make-project "$(NAME)" $(if $(DIR),:directory "$(abspath $(DIR))/"))' 2>&1 | grep -v '^;\|^WARNING'

# A fresh clone, built against nothing but its own ocicl.csv.
clean-check:
	tools/clean-check.sh

# Real-HTTP load test: clicks, memory per session, push streams.
LOAD_PORT ?= 8095
load:
	@$(SBCL) --non-interactive --load bench/load-server.lisp \
	  --eval '(littoral-load:start-load-server :port $(LOAD_PORT) :max-threads 1000)' \
	  --eval '(sleep 1200)' >/dev/null 2>&1 & pid=$$!; \
	for i in $$(seq 1 90); do curl -s -o /dev/null http://127.0.0.1:$(LOAD_PORT)/_stats && break; sleep 1; done; \
	SERVER_PID=$$(pgrep -f start-load-server | head -1) STREAMS=100,300 BASE=http://127.0.0.1:$(LOAD_PORT) \
	  $(NODE) bench/load.mjs; status=$$?; kill -9 $$pid; exit $$status

docs:
	@# The site's front page is the README, its links made relative to docs/.
	@{ printf -- '---\ntitle: Littoral\n---\n\n'; \
	  sed -e 's#](docs/#](#g' -e 's#](LICENSE)#](https://github.com/lispnik/littoral/blob/master/LICENSE)#g' \
	      -e 's#](\(examples\|apps\|src\|tests\|bench\)/#](https://github.com/lispnik/littoral/tree/master/\1/#g' README.md; } > docs/index.md
	$(SBCL) --non-interactive --eval '(asdf:load-system :littoral/docs)' \
	  --eval '(let ((missing (littoral-api-docs:write-api-docs))) (when missing (format t "~&Undocumented: ~{~(~A~)~^, ~}~%" missing)))' \
	  2>&1 | grep -v '^;' | grep -v '^$$'

bench:
	$(SBCL) --non-interactive --eval '(asdf:load-system :littoral/bench)' \
	  --eval '(littoral/tests::run-benchmarks)' 2>&1 | grep -v '^;' | cat -s

# littoral.js in headless Chrome against a fresh server on $(E2E_PORT).
NODE ?= node
E2E_PORT ?= 8765
# make e2e SERVER=woo runs the same checks on Woo (needs libev).
SERVER ?= hunchentoot
e2e:
	@if curl -s -o /dev/null http://127.0.0.1:$(E2E_PORT)/; then \
	  echo "Port $(E2E_PORT) is busy; set E2E_PORT." >&2; exit 1; fi; \
	$(SBCL) --non-interactive --eval '(asdf:load-system :littoral/examples)' \
	  --eval '(asdf:load-system :littoral/tracker)' --eval '(littoral-tracker:register-tracker)' \
	  --eval '(asdf:load-system :littoral/tutorial)' --eval '(reading-list:register)' \
	  --eval '(asdf:load-system :littoral/admin-demo)' --eval '(littoral-admin-demo:register)' \
	  --eval '(asdf:load-system :littoral/members-demo)' --eval '(littoral-members-demo:register)' \
	  --eval '(asdf:load-system :littoral/parenscript-demo)' --eval '(littoral-parenscript-demo:register)' \
	  --eval '(asdf:load-system :littoral/websocket)' \
	  --eval '(when (eq :$(SERVER) :woo) (asdf:load-system :littoral/woo))' \
	  --eval '(littoral:start :port $(E2E_PORT) :server :$(SERVER))' --eval '(sleep 600)' >/dev/null 2>&1 & pid=$$!; \
	for i in $$(seq 1 60); do curl -s -o /dev/null http://127.0.0.1:$(E2E_PORT)/ && break; sleep 1; done; \
	LITTORAL_SERVER=$(SERVER) BASE=http://127.0.0.1:$(E2E_PORT) $(NODE) tests/e2e/browser.mjs; status=$$?; \
	kill -9 $$pid; exit $$status

# WCAG 2 A/AA checks (axe-core) over every example page, in headless Chrome.
a11y:
	@if curl -s -o /dev/null http://127.0.0.1:$(E2E_PORT)/; then \
	  echo "Port $(E2E_PORT) is busy; set E2E_PORT." >&2; exit 1; fi; \
	$(SBCL) --non-interactive --eval '(asdf:load-system :littoral/examples)' \
	  --eval '(asdf:load-system :littoral/tracker)' --eval '(littoral-tracker:register-tracker)' \
	  --eval '(asdf:load-system :littoral/tutorial)' --eval '(reading-list:register)' \
	  --eval '(asdf:load-system :littoral/admin-demo)' --eval '(littoral-admin-demo:register)' \
	  --eval '(asdf:load-system :littoral/members-demo)' --eval '(littoral-members-demo:register)' \
	  --eval '(asdf:load-system :littoral/parenscript-demo)' --eval '(littoral-parenscript-demo:register)' \
	  --eval '(asdf:load-system :littoral/websocket)' \
	  --eval '(littoral:start :port $(E2E_PORT))' --eval '(sleep 600)' >/dev/null 2>&1 & pid=$$!; \
	for i in $$(seq 1 60); do curl -s -o /dev/null http://127.0.0.1:$(E2E_PORT)/ && break; sleep 1; done; \
	BASE=http://127.0.0.1:$(E2E_PORT) $(NODE) tests/e2e/accessibility.mjs; status=$$?; \
	kill -9 $$pid; exit $$status

# The examples on http://127.0.0.1:$(PORT)/ with a REPL in the terminal.
run:
	$(SBCL) --eval '(asdf:load-system :littoral/examples)' \
	  --eval '(asdf:load-system :littoral/admin-demo)' --eval '(littoral-admin-demo:register)' \
	  --eval '(asdf:load-system :littoral/members-demo)' --eval '(littoral-members-demo:register)' \
	  --eval '(asdf:load-system :littoral/parenscript-demo)' --eval '(littoral-parenscript-demo:register)' \
	  --eval '(asdf:load-system :littoral/websocket)' \
	  --eval '(littoral:start :port $(PORT))'

# Tracker on http://127.0.0.1:$(PORT)/tracker, its data in tracker-data.lisp.
tracker:
	$(SBCL) --eval '(asdf:load-system :littoral/tracker)' \
	  --eval '(littoral-tracker:start-tracker :port $(PORT) :file "tracker-data.lisp")'

lint:
	ocicl lint src examples tests

clean:
	rm -rf ~/.cache/common-lisp/*/$(CURDIR)
