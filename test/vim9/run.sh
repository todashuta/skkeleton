#!/bin/sh
# Runs the Vim9 script implementation against the states the TypeScript
# implementation produced.
#
# The expected values are generated first:
#   DENO_DIR="$(pwd)/.deno" deno run -A --config deno.json tools/gen/gen_expected.ts
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"

if [ ! -f test/vim9/expected.json ]; then
  echo "test/vim9/expected.json is missing; run tools/gen/gen_expected.ts first" >&2
  exit 1
fi

if ! vim --clean -es -V1 -S test/vim9/test_impl.vim >test/vim9/impl.log 2>&1; then
  echo "FAIL: impl (vim exited with an error)"
  cat test/vim9/impl.log
  cat test/vim9/actual.txt 2>/dev/null || true
  exit 1
fi
if grep -qE 'E[0-9]+:' test/vim9/impl.log; then
  echo "FAIL: impl (vim error)"
  cat test/vim9/impl.log
  exit 1
fi

cat test/vim9/actual.txt
if grep -qv '^[0-9]* cases, 0 failures$' test/vim9/actual.txt; then
  echo "FAIL: impl"
  exit 1
fi
echo "ok: impl"
