#!/usr/bin/env bash
# Covers issue #31's uninstall half: uninstall.sh --dry-run. Caught a
# real bug before this ever shipped -- the foreign-widget filter used
# `$owned | index(.)` inside select(), where `.` resolves to $owned
# itself (the array being searched), not the array element under test,
# so it silently reported zero foreign widgets no matter what was
# actually in the bar. Same exact jq scoping mistake already hit once
# tonight in lib/build-shell-json.sh. Fixed with `. as $id | $owned |
# index($id)`; this test pins the fix with the same synthetic
# example.weather/example.vpn fixture the issue's own sample output
# uses, so it can never silently regress back to the broken version.
#
# Also covers the issue's own core safety requirement directly: hash
# every file dry-run could plausibly touch before and after, assert
# byte-for-byte identical.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'uninstall-dry-run: jq is required (command "jq" not found)\n' >&2
  exit 1
}

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

fake_home="$(mktemp -d)"
trap 'rm -rf "$fake_home"' EXIT

mkdir -p "$fake_home/.config/omarchy" "$fake_home/.local/state/ruixen" \
  "$fake_home/.config/omarchy/plugins/ruixen.notch" \
  "$fake_home/.config/omarchy/plugins/ruixen.settingsbutton"

cat >"$fake_home/.local/state/ruixen/shell.json.pre-ruixen" <<'EOF'
{
  "bar": { "id": "omarchy.bar", "layout": { "left": [], "center": [], "right": [] } }
}
EOF

cat >"$fake_home/.config/omarchy/shell.json" <<'EOF'
{
  "bar": {
    "id": "ruixen.bar",
    "layout": {
      "left": [{ "id": "ruixen.applauncher" }],
      "center": [{ "id": "example.weather" }],
      "right": [{ "id": "ruixen.tray" }, { "id": "example.vpn" }]
    }
  }
}
EOF

before_shell_json="$(sha256sum "$fake_home/.config/omarchy/shell.json" | awk '{print $1}')"
before_pristine="$(sha256sum "$fake_home/.local/state/ruixen/shell.json.pre-ruixen" | awk '{print $1}')"
before_plugin_count="$(find "$fake_home/.config/omarchy/plugins" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"

out="$(HOME="$fake_home" PATH="$fake_bin:$PATH" "$repo_dir/uninstall.sh" --dry-run)"
exit_code=$?

check "dry run exits 0" "$exit_code" "0"
check "dry run reports the restored bar id" "$(grep -c 'Restore bar: omarchy.bar' <<<"$out")" "1"
check "dry run lists example.weather as a preserved foreign widget" "$(grep -c '^  example\.weather$' <<<"$out")" "1"
check "dry run lists example.vpn as a preserved foreign widget" "$(grep -c '^  example\.vpn$' <<<"$out")" "1"
check "dry run does NOT list ruixen.applauncher/tray as foreign (they are Ruixen-owned)" \
  "$(grep -cE '^  ruixen\.(applauncher|tray)$' <<<"$out")" "0"
check "dry run lists the installed ruixen.* plugins that would be removed" \
  "$(grep -c '^  ruixen\.notch$' <<<"$out")" "1"
check "dry run says explicitly that nothing changed" "$(grep -c '^No files changed\.$' <<<"$out")" "1"

after_shell_json="$(sha256sum "$fake_home/.config/omarchy/shell.json" | awk '{print $1}')"
after_pristine="$(sha256sum "$fake_home/.local/state/ruixen/shell.json.pre-ruixen" | awk '{print $1}')"
after_plugin_count="$(find "$fake_home/.config/omarchy/plugins" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"

check "safety: shell.json is byte-for-byte unchanged" "$after_shell_json" "$before_shell_json"
check "safety: the pristine snapshot is byte-for-byte unchanged" "$after_pristine" "$before_pristine"
check "safety: no plugin directory was removed" "$after_plugin_count" "$before_plugin_count"
check "safety: no lock file was created (dry-run never takes the lifecycle lock)" \
  "$([[ -e "$fake_home/.local/state/ruixen/install.lock" ]] && echo yes || echo no)" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
