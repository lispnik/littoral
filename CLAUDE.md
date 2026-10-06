# Littoral — notes for working on it

A Seaside-style web framework for SBCL. See README.md for the user-facing tour.

- Toolchain: SBCL only, ocicl for dependencies (`ocicl install <system>` updates `ocicl.csv`), FiveAM for tests. No Quicklisp. Use `sb-thread`/`sb-ext` directly.
- `make test` runs `(asdf:test-system :littoral)` and must stay green. Tests drive the Lack app in-process through the fake browser in `tests/browser.lisp` (`visit`, `click`, `fill-in`, `press`, `back-to`, `ajax-request`); add tests in that style, not over sockets.
- Packages: `littoral.html` holds the HTML tags and brushes, and `littoral` uses it. Keep generic tag names out of `littoral`'s exports.
- Load order is serial (see `littoral.asd`): util → context → callbacks → html/{canvas,tags,brushes} → component → decoration → dialogs → backtracking → task → session → application → ajax → dispatcher → tools/{halos,config}.
- Invariants:
  - `decorations` lists are replaced, never mutated, because snapshots store them by value.
  - Rendering must not change state. Tasks are started by `prepare-tasks` after the callbacks run, never during render.
  - AJAX requests reuse the page's continuation and re-snapshot it; they do not create a new `_k`.
- `call` is a `defun/cc`, so it suspends only when called lexically inside `define-flow` (or another `/cc` function).
- `sed` on this machine is GNU sed.
