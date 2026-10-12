#!/bin/sh
# Build and test a fresh clone of HEAD in an SBCL that sees only the clone and
# its ocicl/ directory, ignoring any ASDF source registry in the environment.
# Fails if ocicl.csv is missing a dependency (the runtime would download it and
# change ocicl.csv) or the tests fail.
set -e
status=
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d /tmp/littoral-clean-XXXXXX)
trap 'rm -rf "$work"' EXIT
git clone -q "$here" "$work/littoral"
cd "$work/littoral"
ocicl install >/dev/null 2>&1
cp ocicl.csv "$work/ocicl.csv.before"
cat > "$work/check.lisp" <<LISP
(load #P"~/.local/share/ocicl/ocicl-runtime.lisp")
(asdf:clear-source-registry)
(asdf:initialize-source-registry
 '(:source-registry (:directory "$work/littoral/") :ignore-inherited-configuration))
(asdf:test-system :littoral)
LISP
sbcl --no-userinit --non-interactive --load "$work/check.lisp" > "$work/output.txt" 2>&1 || status=$?
grep -E "Did |Pass:|Fail:|Skip:|Unhandled|tests failed" "$work/output.txt" || true
if [ -n "$status" ]; then
  # FiveAM's failure details, without compiler notes.
  sed -n '/Failure Details:/,$p' "$work/output.txt" | grep -v '^;' | head -80 >&2
  echo "The tests failed in the clean build." >&2
  exit 1
fi
if ! cmp -s ocicl.csv "$work/ocicl.csv.before"; then
  echo "ocicl.csv is missing dependencies; the clean build added:" >&2
  diff "$work/ocicl.csv.before" ocicl.csv | grep '^>' | cut -d, -f1 >&2
  exit 1
fi
echo "Clean build OK."
