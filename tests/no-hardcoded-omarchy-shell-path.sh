#!/usr/bin/env bash
# Covers "[P2] Replace hardcoded /usr/share/omarchy/shell IPC calls with
# omarchy-shell" (#24)'s own acceptance criterion ("Add a simple static
# QA check preventing new operational qs -p /usr/share/omarchy/shell
# calls if practical"): a plain grep across every .qml/.sh file in this
# repo for the raw invocation pattern this issue replaced, so a future
# call site added the old way gets caught in CI instead of silently
# reintroducing the exact problem this issue fixed (hardcodes Omarchy's
# install path, no IPC timeout).
#
# Deliberately narrow to the actual INVOCATION shapes (a bare
# `qs -p /usr/share/omarchy/shell` shell string, or the equivalent
# ["qs", "-p", "/usr/share/omarchy/shell"] Process.command array form),
# not every mention of the path -- several files legitimately reference
# it in a comment as a "verified by reading that file directly" source
# citation (e.g. ruixen.workspaces/Workspaces.qml), which this issue's
# own acceptance criteria explicitly says are fine to leave alone.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"

pass=0
fail_count=0
check() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   - %s\n' "$desc"
    pass=$((pass + 1))
  else
    printf 'FAIL - %s\n       got:  %s\n       want: %s\n' "$desc" "$got" "$want"
    fail_count=$((fail_count + 1))
  fi
}

violations=""
self="$script_dir/no-hardcoded-omarchy-shell-path.sh"
while IFS= read -r -d '' f; do
  [[ "$f" == "$self" ]] && continue # this file necessarily names the pattern it's searching for
  while IFS=: read -r lineno line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
      "//"* | "#"*) continue ;; # a comment citing the path, not invoking it
    esac
    violations+="$(basename "$f"):$lineno: $trimmed"$'\n'
  done < <(grep -nF -e 'qs -p /usr/share/omarchy/shell' -e '"-p", "/usr/share/omarchy/shell"' "$f" 2>/dev/null || true)
done < <(find "$repo_dir" \( -name '*.qml' -o -name '*.sh' \) -not -path '*/.git/*' -print0)

check "no operational qs -p /usr/share/omarchy/shell call sites remain (#24)" \
  "$violations" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
