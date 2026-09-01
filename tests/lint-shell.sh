#!/usr/bin/env bash
# Covers the shell-script-checking half of "[P1] Add automated QA/CI
# for manifests, shell scripts, models, and installer lifecycle":
# `bash -n` (syntax) on every script here, plus ShellCheck when it's
# installed. CI always has ShellCheck (installed explicitly, see
# .github/workflows/ci.yml) so it's never skipped there; a dev machine
# without it just gets a note instead of a hard failure, so this
# script stays runnable locally without a new dependency.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"

targets=(
  "$repo_dir/install.sh"
  "$repo_dir/update.sh"
  "$repo_dir/uninstall.sh"
  "$repo_dir/ruixen-bar-mode.sh"
  "$repo_dir/hyprland/ruixen-lookfeel.sh"
  "$repo_dir/ruixen.notch/list-wallpapers.sh"
)
targets+=("$repo_dir"/lib/*.sh)
targets+=("$repo_dir"/tests/*.sh)

pass=0
fail_count=0

for f in "${targets[@]}"; do
  [[ -f "$f" ]] || continue
  name="${f#"$repo_dir"/}"
  errfile="$(mktemp)"
  if bash -n "$f" 2>"$errfile"; then
    printf 'ok   - %s: bash -n\n' "$name"
    pass=$((pass + 1))
  else
    printf 'FAIL - %s: bash -n\n' "$name"
    cat "$errfile" >&2
    fail_count=$((fail_count + 1))
  fi
  rm -f "$errfile"
done

if command -v shellcheck >/dev/null 2>&1; then
  for f in "${targets[@]}"; do
    [[ -f "$f" ]] || continue
    name="${f#"$repo_dir"/}"
    if shellcheck "$f"; then
      printf 'ok   - %s: shellcheck\n' "$name"
      pass=$((pass + 1))
    else
      printf 'FAIL - %s: shellcheck\n' "$name"
      fail_count=$((fail_count + 1))
    fi
  done
else
  printf 'note - shellcheck not installed locally, skipped (CI always runs it)\n' >&2
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
