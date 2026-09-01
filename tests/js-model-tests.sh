#!/usr/bin/env bash
# Runs the plain-JS model tests (tests/js/*.test.js) via node -- covers
# the acceptance criteria of "[P1] Add automated QA/CI... JavaScript
# model tests" (BarModel.js, Model.js). Thin shell wrapper so this
# fits the same `tests/*.sh` entry-point convention as every other
# test file here. Run directly: ./tests/js-model-tests.sh
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

command -v node >/dev/null 2>&1 || {
  printf 'js-model-tests: node is required (command "node" not found)\n' >&2
  exit 1
}

status=0
for test_file in "$script_dir"/js/*.test.js; do
  printf '=== %s ===\n' "$(basename "$test_file")"
  node "$test_file" || status=1
  printf '\n'
done

exit "$status"
