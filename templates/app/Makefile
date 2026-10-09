# {{title}}: make test, make run, make build.

# Where Littoral is checked out, with its dependencies in ocicl/.
LITTORAL ?= {{littoral}}
PORT ?= {{port}}

SBCL = sbcl --noinform --eval '(asdf:initialize-source-registry (quote (:source-registry (:directory "$(CURDIR)/") (:directory "$(LITTORAL)") (:tree "$(LITTORAL)ocicl/") :inherit-configuration)))'

.PHONY: test run build user clean

test:
	$(SBCL) --non-interactive --eval '(asdf:test-system :{{name}})'

# The development server, with halos and the toolbar.
run:
	$(SBCL) --eval '(asdf:load-system :{{name}})' --eval '({{name}}:serve :port $(PORT))'

# A user who can sign in: make user NAME=ada EMAIL=ada@example.org PASSWORD='…' [ADMIN=1]
user:
	@test -n "$(NAME)" -a -n "$(EMAIL)" -a -n "$(PASSWORD)" || { echo "Usage: make user NAME=… EMAIL=… PASSWORD=… [ADMIN=1]"; exit 2; }
	$(SBCL) --non-interactive --eval '(asdf:load-system :{{name}})' \
	  --eval '({{name}}:create-user "$(NAME)" "$(EMAIL)" "$(PASSWORD)" :admin $(if $(ADMIN),t,nil))'

# A standalone executable, serving in deployment mode: PORT=8080 bin/{{name}}
build:
	mkdir -p bin
	$(SBCL) --non-interactive --eval '(asdf:load-system :{{name}})' \
	  --eval '(sb-ext:save-lisp-and-die "bin/{{name}}" :executable t :toplevel (function {{name}}:toplevel))'

clean:
	rm -rf bin
