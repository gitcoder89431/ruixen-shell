#!/usr/bin/env bash
# Runs every test in this directory and reports one final pass/fail
# summary -- what CI runs (.github/workflows/ci.yml) and what local
# development should run before pushing. See README.md's own
# "Running tests" section for what each individual script covers.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

suites=(
  "$script_dir/lint-shell.sh"
  "$script_dir/validate-manifests.sh"
  "$script_dir/js-model-tests.sh"
  "$script_dir/shell-json-merge.sh"
  "$script_dir/looknfeel-preserve.sh"
  "$script_dir/uninstall-bar-restore.sh"
  "$script_dir/uninstall-pristine-reset.sh"
  "$script_dir/install-lifecycle.sh"
  "$script_dir/install-rollback.sh"
  "$script_dir/wallpaper-discovery-format.sh"
  "$script_dir/update-safety.sh"
  "$script_dir/gif-poster-fallback.sh"
)

overall_status=0
for suite in "${suites[@]}"; do
  printf '\n##### %s #####\n' "$(basename "$suite")"
  if ! "$suite"; then
    overall_status=1
  fi
done

printf '\n'
if [[ "$overall_status" -eq 0 ]]; then
  printf 'All test suites passed.\n'
else
  printf 'One or more test suites FAILED -- see above.\n' >&2
fi
exit "$overall_status"
