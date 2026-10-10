SBCL ?= sbcl
PORT ?= 8080

.PHONY: new tour build docker test test-chrome test-postgres e2e a11y bench load docs clean-check run tracker lint clean

test:
	$(SBCL) --non-interactive --eval '(asdf:test-system :littoral)'

# The examples in a real headless Chrome, driven from Lisp (set CHROME if it isn't found):
test-chrome:
	$(SBCL) --non-interactive --eval '(asdf:load-system :littoral/chrome-tests)' \
	  --eval '(uiop:quit (if (littoral/chrome-tests:run-chrome-tests) 0 1))'

# The database suites against PostgreSQL:
#   make test-postgres [LITTORAL_TEST_DATABASE=postgres://user:password@host:5432/db]
LITTORAL_TEST_DATABASE ?= postgres://postgres:postgres@127.0.0.1:5432/littoral_test
test-postgres:
	LITTORAL_TEST_DATABASE=$(LITTORAL_TEST_DATABASE) $(SBCL) --non-interactive \
	  --eval '(asdf:load-system :littoral/tests)' --eval '(littoral/tests::run-database-suites)'

# The narrated video tour, recorded from a fresh server into tour/littoral-tour.mp4.
# Needs Chrome, Node 22+ and ffmpeg; narration needs macOS `say` (captions only otherwise).
TOUR_DIR ?= $(CURDIR)/tour
TOUR_PORT ?= 8097
tour:
	@if curl -s -o /dev/null http://127.0.0.1:$(TOUR_PORT)/; then echo "Port $(TOUR_PORT) is in use: set TOUR_PORT"; exit 1; fi
	@rm -rf $(TOUR_DIR) && mkdir -p $(TOUR_DIR)/data $(TOUR_DIR)/inbox
	@TOUR_DIR=$(TOUR_DIR) TOUR_PORT=$(TOUR_PORT) $(SBCL) --load tools/tour/server.lisp > $(TOUR_DIR)/server.log 2>&1 & pid=$$!; \
	  until curl -s -o /dev/null http://127.0.0.1:$(TOUR_PORT)/; do sleep 1; kill -0 $$pid 2>/dev/null || exit 1; done; \
	  TOUR_DIR=$(TOUR_DIR) INBOX=$(TOUR_DIR)/inbox BASE=http://127.0.0.1:$(TOUR_PORT) $(NODE) tools/tour/tour.mjs; status=$$?; \
	  kill -9 $$pid; \
	  [ $$status = 0 ] && TOUR_DIR=$(TOUR_DIR) OUT=$(TOUR_DIR)/littoral-tour.mp4 $(NODE) tools/tour/build.mjs

# A new application: make new NAME=bookshop [DIR=~/src/bookshop] [TEMPLATE=app]
# (basic: a component and tests; app: also a database, signing in, an admin, deploy files)
new:
	@test -n "$(NAME)" || { echo "Usage: make new NAME=my-app [DIR=path]"; exit 2; }
	@$(SBCL) --noinform --non-interactive --eval '(asdf:load-system :littoral/generator)' \
	  --eval '(littoral.generator:make-project "$(NAME)" $(if $(DIR),:directory "$(abspath $(DIR))/") $(if $(TEMPLATE),:template "$(TEMPLATE)"))' 2>&1 | grep -v '^;\|^WARNING'

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
	  --eval '(asdf:load-system :littoral/members-demo)' --eval '(littoral-members-demo:register :file (format nil "/tmp/members-~D.sqlite3" (random 1000000 (make-random-state t))))' \
	  --eval '(asdf:load-system :littoral/storage-demo)' --eval '(littoral-gallery:register)' \
	  --eval '(asdf:load-system :littoral/search-demo)' --eval '(littoral-search-demo:register)' \
	  --eval '(asdf:load-system :littoral/parenscript-demo)' --eval '(littoral-parenscript-demo:register)' \
	  --eval '(asdf:load-system :littoral/websocket)' \
	  --eval '(when (eq :$(SERVER) :woo) (asdf:load-system :littoral/woo))' \
	  --eval '(setf littoral:*new-sessions-per-minute* nil)' --eval '(littoral:start :port $(E2E_PORT) :server :$(SERVER))' --eval '(sleep 600)' >/dev/null 2>&1 & pid=$$!; \
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
	  --eval '(asdf:load-system :littoral/members-demo)' --eval '(littoral-members-demo:register :file (format nil "/tmp/members-~D.sqlite3" (random 1000000 (make-random-state t))))' \
	  --eval '(asdf:load-system :littoral/storage-demo)' --eval '(littoral-gallery:register)' \
	  --eval '(asdf:load-system :littoral/search-demo)' --eval '(littoral-search-demo:register)' \
	  --eval '(asdf:load-system :littoral/parenscript-demo)' --eval '(littoral-parenscript-demo:register)' \
	  --eval '(asdf:load-system :littoral/websocket)' \
	  --eval '(setf littoral:*new-sessions-per-minute* nil)' --eval '(littoral:start :port $(E2E_PORT))' --eval '(sleep 600)' >/dev/null 2>&1 & pid=$$!; \
	for i in $$(seq 1 60); do curl -s -o /dev/null http://127.0.0.1:$(E2E_PORT)/ && break; sleep 1; done; \
	BASE=http://127.0.0.1:$(E2E_PORT) $(NODE) tests/e2e/accessibility.mjs; status=$$?; \
	kill -9 $$pid; exit $$status

# The examples on http://127.0.0.1:$(PORT)/ with a REPL in the terminal.
# Every example and demo in one executable, bin/littoral-demo: PORT=8080 bin/littoral-demo
build:
	$(SBCL) --non-interactive --load tools/demo-server.lisp --eval '(littoral-demo:build "bin/littoral-demo")'

# The same in a container image: docker run --rm -p 127.0.0.1:8080:8080 littoral-demo
docker:
	@test -d ocicl || ocicl install
	docker build -t littoral-demo .

run:
	$(SBCL) --eval '(asdf:load-system :littoral/examples)' \
	  --eval '(asdf:load-system :littoral/admin-demo)' --eval '(littoral-admin-demo:register)' \
	  --eval '(asdf:load-system :littoral/members-demo)' --eval '(littoral-members-demo:register)' \
	  --eval '(asdf:load-system :littoral/storage-demo)' --eval '(littoral-gallery:register)' \
	  --eval '(asdf:load-system :littoral/search-demo)' --eval '(littoral-search-demo:register)' \
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
