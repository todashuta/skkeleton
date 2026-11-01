#!/bin/sh
# Runs the dictionary subsystem tests.
#
# Expected values come from the TypeScript implementation; regenerate them
# with:
#   DENO_DIR="$(pwd)/.deno" deno run -A --config deno.json tools/gen/gen_dict_expect.ts
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
mkdir -p test/actual

if [ ! -f test/expected/dict_expected.json ]; then
  echo "missing test/expected/dict_expected.json; run tools/gen/gen_dict_expect.ts" >&2
  exit 1
fi

log=test/actual/dictionary.log
if ! vim --clean -es -V1 -S test/test_dictionary.vim >"$log" 2>&1; then
  echo "FAIL: vim exited with an error" >&2
  cat "$log" >&2
  exit 1
fi

if grep -qE 'E[0-9]+:' "$log"; then
  echo "FAIL: vim reported an error" >&2
  cat "$log" >&2
  exit 1
fi

if grep -q '^FAIL ' test/actual/dictionary.txt; then
  echo "FAIL: assertions failed" >&2
  cat test/actual/dictionary.txt >&2
  exit 1
fi

cat test/actual/dictionary.txt
