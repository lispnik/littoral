# Littoral — notes for working on it

A Seaside-style web framework for SBCL. See README.md for the user-facing tour.

- Toolchain: SBCL only, ocicl for dependencies (`ocicl install <system>` updates `ocicl.csv`), FiveAM for tests. No Quicklisp. Use `sb-thread`/`sb-ext` directly.
- `make test` runs `(asdf:test-system :littoral)` and must stay green. `make e2e NODE=…` checks `littoral.js` in headless Chrome (`tests/e2e/browser.mjs`). In this shell `node` is an nvm stub, so pass `NODE=~/.nvm/versions/node/v24.3.0/bin/node`.
- SBCL servers ignore SIGTERM while Hunchentoot threads run, so stop a test server with `kill -9`.
- Tests drive the Lack app in-process through the fake browser in `tests/browser.lisp` (`visit`, `click`, `fill-in`, `press`, `back-to`, `ajax-request`); add tests in that style, not over sockets.
- Packages: `littoral.html` holds the HTML tags and brushes, and `littoral` uses it. Keep generic tag names out of `littoral`'s exports.
- Load order is serial (see `littoral.asd`): util → context → callbacks → html/{canvas,tags,brushes} → component → decoration → dialogs → backtracking → task → widgets → session → application → ajax → dispatcher → tools/{halos,config}.
- Invariants:
  - `decorations` lists are replaced, never mutated, because snapshots store them by value.
  - Rendering must not change state (`*rendering*` makes `show`/`answer`/`home` signal). Tasks are started by `prepare-tasks` after the callbacks run, never during render. Derived data, such as a report's rows, is computed on demand rather than stored at render time.
  - Every URL goes through `url-for` or `page-url`, so the mount prefix and `update-url` apply.
  - AJAX requests reuse the page's continuation and re-snapshot it; they do not create a new `_k`.
- `call` is a `defun/cc`, so it suspends only when called lexically inside `define-flow` (or another `/cc` function).
- `sed` on this machine is GNU sed.
