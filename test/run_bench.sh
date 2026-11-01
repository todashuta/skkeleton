#!/bin/sh
# Benchmarks the dictionary subsystem with a generated 100k reading SKK-JISYO.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
mkdir -p test/actual
log=test/actual/dictionary_bench.log
if ! vim --clean -es -V1 -S test/bench_dictionary.vim >"$log" 2>&1; then
  echo "FAIL: vim exited with an error" >&2
  cat "$log" >&2
  exit 1
fi
if grep -qE 'E[0-9]+:' "$log"; then
  echo "FAIL: vim reported an error" >&2
  cat "$log" >&2
  exit 1
fi
cat test/actual/dictionary_bench.txt
