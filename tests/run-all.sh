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
  "$script_dir/looknfeel-stable-path.sh"
  "$script_dir/uninstall-bar-restore.sh"
  "$script_dir/merge-uninstall-bar.sh"
  "$script_dir/uninstall-preserve-thirdparty.sh"
  "$script_dir/uninstall-pristine-reset.sh"
  "$script_dir/uninstall-failure-aggregation.sh"
  "$script_dir/install-lifecycle.sh"
  "$script_dir/install-rollback.sh"
  "$script_dir/lifecycle-lock.sh"
  "$script_dir/wallpaper-discovery-format.sh"
  "$script_dir/update-safety.sh"
  "$script_dir/gif-poster-fallback.sh"
  "$script_dir/no-hardcoded-omarchy-shell-path.sh"
  "$script_dir/bar-popup-clearance.sh"
  "$script_dir/bar-right-side-groups.sh"
  "$script_dir/bar-docked-left-inset.sh"
  "$script_dir/pluginpins-model.sh"
  "$script_dir/notch-bar-hidden-sync.sh"
  "$script_dir/workspaces-pill-strict.sh"
  "$script_dir/bar-drag-protected-slots.sh"
  "$script_dir/bar-left-pluginpins-pill.sh"
  "$script_dir/repair-drift-detection.sh"
  "$script_dir/uninstall-dry-run.sh"
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
