# Littoral — notes for working on it

A Seaside-style web framework for SBCL. See README.md for the user-facing tour.

- Toolchain: SBCL only, ocicl for dependencies (`ocicl install <system>` updates `ocicl.csv`), FiveAM for tests. No Quicklisp. Use `sb-thread`/`sb-ext` directly.
- `make test` runs `(asdf:test-system :littoral)` and must stay green. `make e2e NODE=…` checks `littoral.js` in headless Chrome (`tests/e2e/browser.mjs`). In this shell `node` is an nvm stub, so pass `NODE=~/.nvm/versions/node/v24.3.0/bin/node`.
- SBCL servers ignore SIGTERM while Hunchentoot threads run, so stop a test server with `kill -9`.
- Threads do not inherit dynamic bindings: tests that spawn threads must rebind `littoral::*applications*` (see `run-threads` in `tests/robustness.lisp`).
- Tests drive the Lack app in-process through the fake browser in `tests/browser.lisp` (`visit`, `click`, `fill-in`, `press`, `back-to`, `ajax-request`); add tests in that style, not over sockets.
- Packages: `littoral.html` holds the HTML tags and brushes, and `littoral` uses it. Keep generic tag names out of `littoral`'s exports.
- Load order is serial (see `littoral.asd`): util → context → callbacks → html/{canvas,tags,brushes} → component → decoration → dialogs → backtracking → task → widgets → session → application → configuration → ajax → dispatcher → push → live → tools/{halos,config}.
- Invariants:
  - `decorations` lists are replaced, never mutated, because snapshots store them by value.
  - Rendering must not change state (`*rendering*` makes `show`/`answer`/`home` signal). Tasks are started by `prepare-tasks` after the callbacks run, never during render. Derived data, such as a report's rows, is computed on demand rather than stored at render time.
  - Every URL goes through `url-for` or `page-url`, so the mount prefix and `update-url` apply.
  - AJAX requests reuse the page's continuation and re-snapshot it; they do not create a new `_k`.
  - Static files are served at `static-url`, which carries a content fingerprint (`?v=`). Only a URL with the matching fingerprint is cached as immutable, so browsers never run stale JS.
  - Chrome restores even `no-store` pages from its back/forward cache, so `littoral.js` reloads on `pageshow` when the page was persisted. Browser tests of back-button behaviour must allow for that reload.
  - Woo (optional, `littoral/woo`): its worker threads start with standard I/O syntax (`*print-readably*` true), so every entry point binds `with-sane-printing`. libev is not thread-safe: push on Woo marshals to the stream's event loop with `ev_async_send`; never call a Woo writer from another thread.
- Shared, cross-session state (the wiki and the chat room) lives outside `states`, behind a mutex.
  - Server push: each open page's EventSource is a Clack streaming response (a function) running in its request thread. `publish` and `notify` only queue work and wake the stream; rendering happens in the stream thread under the session lock. Tests drive streams in-process (`tests/push.lisp`).
- `call` is a `defun/cc`, so it suspends only when called lexically inside `define-flow` (or another `/cc` function).
- `sed` on this machine is GNU sed.
- This machine's ASDF configuration includes `(:tree ~/Projects/common-lisp/)`, so `make test` may load dependencies from other projects' `ocicl/` directories. `make clean-check` (`tools/clean-check.sh`) builds a fresh clone of HEAD against only its own `ocicl.csv`; run it after changing dependencies, and commit first.
- `ocicl lint --fix` is unsafe here: its `needless-shiftf` fix rewrites `(shiftf place '())` to `(setf place nil)`, losing the returned old value, and its `bare-progn-in-if` fix flattens forms onto one line. It also leaves `.bak` files. Fix lint findings by hand. Six findings are deliberate (see the commit that cleaned lint).
- `docs/API.md` is generated (`make docs`); edit docstrings, not the file. `defun/cc` drops docstrings, so `/cc` functions get theirs with `(setf (documentation …))`.
