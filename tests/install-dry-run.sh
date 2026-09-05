#!/usr/bin/env bash
# Covers issue #31's install half: install.sh --dry-run. Same fake
# $HOME + fake-bin sandbox tests/install-lifecycle.sh already
# established (see that file's own header for why these stubs are
# deliberately minimal).
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'install-dry-run: jq is required (command "jq" not found)\n' >&2
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

run_dry_run() {
  ( HOME="$1" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" --dry-run )
}

# --- Case 1: a genuinely fresh machine, no shell.json at all ----------
home1="$(mktemp -d)"
out1="$(run_dry_run "$home1")"
exit1=$?
check "fresh machine: dry run exits 0" "$exit1" "0"
check "fresh machine: every plugin reported as a fresh install, none as replace" \
  "$(grep -c 'replace existing' <<<"$out1")" "0"
check "fresh machine: reports shell.json would be created fresh" \
  "$(grep -c 'would be created fresh from this checkout' <<<"$out1")" "1"
check "fresh machine: reports the pristine bar snapshot would be recorded" \
  "$(grep -c 'would be recorded (first time Ruixen takes the bar slot)' <<<"$out1")" "1"
check "fresh machine: says explicitly nothing changed" "$(grep -c '^No files changed\.$' <<<"$out1")" "1"
check "fresh machine: no shell.json was actually created" \
  "$([[ -e "$home1/.config/omarchy/shell.json" ]] && echo yes || echo no)" "no"
check "fresh machine: no lifecycle lock was created" \
  "$([[ -e "$home1/.local/state/ruixen/install.lock" ]] && echo yes || echo no)" "no"
rm -rf "$home1"

# --- Case 2: an existing customized shell.json, already ruixen.bar ----
home2="$(mktemp -d)"
mkdir -p "$home2/.config/omarchy" "$home2/.config/omarchy/plugins/ruixen.notch"
cat >"$home2/.config/omarchy/shell.json" <<'EOF'
{
  "version": 1,
  "some_user_key": "left alone",
  "bar": { "id": "ruixen.bar", "docked": true, "layout": { "left": [], "center": [], "right": [] } },
  "plugins": [{ "id": "ruixen.notch" }]
}
EOF
before_hash2="$(sha256sum "$home2/.config/omarchy/shell.json" | awk '{print $1}')"

out2="$(run_dry_run "$home2")"
check "already-owned bar: reports it already owns the bar slot, not a host switch" \
  "$(grep -c 'already owns the bar slot' <<<"$out2")" "1"
check "already-owned bar: reports which missing ruixen plugins[] entries would be added" \
  "$(grep -c 'ruixen.media$' <<<"$out2")" "1"
after_hash2="$(sha256sum "$home2/.config/omarchy/shell.json" | awk '{print $1}')"
check "already-owned bar: shell.json is byte-for-byte unchanged" "$after_hash2" "$before_hash2"
rm -rf "$home2"

# --- Case 3: a plugin that fails validation aborts the dry run loudly,
# same as it would abort a real install, before anything is touched ---
home3="$(mktemp -d)"
out3="$(FAKE_OMARCHY_FAIL_VALIDATE_FOR="ruixen.weather" run_dry_run "$home3" 2>&1)" && exit3=0 || exit3=$?
check "failing validation: dry run exits non-zero" "$exit3" "1"
check "failing validation: names the specific plugin that fails" \
  "$(grep -c 'ruixen.weather.*FAILS VALIDATION' <<<"$out3")" "1"
check "failing validation: still says no files changed" "$(grep -c '^No files changed\.$' <<<"$out3")" "1"
rm -rf "$home3"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
