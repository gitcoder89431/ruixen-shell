#!/usr/bin/env bash
# Covers "[P0/P1] Preserve third-party bar widgets added while Ruixen
# is installed during uninstall" (#26) end-to-end: runs the REAL
# install.sh and uninstall.sh back to back against a throwaway fake
# $HOME, with a widget added to the live bar layout in between --
# proving the wiring in uninstall.sh actually calls
# lib/merge-uninstall-bar.sh with the right values, not just that the
# pure merge function itself is correct in isolation (already covered
# thoroughly by tests/merge-uninstall-bar.sh).
#
# Sources the REAL /usr/bin/omarchy-shell-config (via PATH fallthrough
# -- fake_bin has no file by that name, so bash's own `source` search
# finds the real one further down PATH), since that's what actually
# performs the atomic shell.json write uninstall.sh depends on -- a
# faithful re-implementation here would risk drifting from the real
# commit()/$NORMALIZE behavior. It already respects $HOME for
# CONFIG_FILE, so pointing $HOME at the fake test home is enough to
# keep it fully sandboxed; a fake omarchy-shell binary (fixtures/
# fake-bin/omarchy-shell) makes sure its own refresh step can never
# reach a real, currently-running Quickshell process on the machine
# actually running this test suite.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'uninstall-preserve-thirdparty: jq is required (command "jq" not found)\n' >&2
  exit 1
}
command -v omarchy-shell-config >/dev/null 2>&1 || {
  printf 'uninstall-preserve-thirdparty: this test sources the real omarchy-shell-config, not found on PATH -- skipping (not a real Omarchy machine)\n' >&2
  exit 0
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

homes=()
cleanup() { rm -rf "${homes[@]}"; }
trap cleanup EXIT

run_install() {
  ( HOME="$1" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$1/install.out" 2>&1
}
run_uninstall() {
  ( HOME="$1" PATH="$fake_bin:$PATH" "$repo_dir/uninstall.sh" ) >"$1/uninstall.out" 2>&1
}

home="$(mktemp -d)"
homes+=("$home")

# A real customized bar existed before Ruixen ever touched shell.json
# -- this is what install.sh will capture as the pristine baseline.
mkdir -p "$home/.config/omarchy"
printf '%s' '{"bar":{"id":"local.old-bar","layout":{"left":[{"id":"local.launcher"}],"center":[],"right":[]}}}' \
  > "$home/.config/omarchy/shell.json"

if run_install "$home"; then status1=0; else status1=$?; fi
check "baseline install: exits 0" "$status1" "0"
if [[ "$status1" -ne 0 ]]; then
  cat "$home/install.out" >&2
fi
check "baseline install: ruixen.bar owns the bar slot" \
  "$(jq -r '.bar.id' "$home/.config/omarchy/shell.json")" "ruixen.bar"

# A user adds a third-party widget to the live bar WHILE Ruixen is
# active -- the exact scenario #26 is about. Also nudge one of
# Ruixen's own canonical entries into a different region, to prove the
# merge doesn't mistake a Ruixen-owned id for something foreign just
# because it moved (#26's own explicit fixture).
shell_json="$home/.config/omarchy/shell.json"
tmp="$(mktemp)"
jq '.bar.layout.left += [{"id":"test.thirdparty.widget","note":"added by the user"}]' \
  "$shell_json" > "$tmp" && mv "$tmp" "$shell_json"

if run_uninstall "$home"; then status2=0; else status2=$?; fi
check "uninstall: exits 0" "$status2" "0"
if [[ "$status2" -ne 0 ]]; then
  cat "$home/uninstall.out" >&2
fi

restored_bar="$(jq -c '.bar' "$shell_json")"
check "uninstall: bar id restored to the pre-Ruixen bar" \
  "$(jq -r '.id' <<<"$restored_bar")" "local.old-bar"
check "uninstall: the pre-existing baseline widget survived" \
  "$(jq -c '.layout.left | map(select(.id == "local.launcher"))' <<<"$restored_bar")" \
  '[{"id":"local.launcher"}]'
check "uninstall: the third-party widget added while Ruixen was active survived, settings intact (#26)" \
  "$(jq -c '.layout.left | map(select(.id == "test.thirdparty.widget"))' <<<"$restored_bar")" \
  '[{"id":"test.thirdparty.widget","note":"added by the user"}]'
check "uninstall: no Ruixen-owned entry (e.g. ruixen.applauncher) survived anywhere" \
  "$(jq -c '[.layout.left[], .layout.center[], .layout.right[]] | map(select(.id == "ruixen.applauncher"))' <<<"$restored_bar")" \
  '[]'

check "uninstall: ruixen.* plugin directories were actually removed" \
  "$(find "$home/.config/omarchy/plugins" -maxdepth 1 -iname 'ruixen.*' -not -name '.*' 2>/dev/null | wc -l)" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
