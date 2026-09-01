#!/usr/bin/env bash
# Covers "[P1/P2] Decouple deployed Hyprland looknfeel from the git
# checkout path" (#15): runs the REAL install.sh from a THROWAWAY COPY
# of this repo (not repo_dir itself) against a fake $HOME, so the
# checkout can actually be deleted afterward the same way a real user
# might delete their clone -- proving looknfeel.lua's active symlink
# target survives that, which is the whole point of the issue.
#
# lib/apply-looknfeel.sh / lib/restore-looknfeel.sh themselves are
# already covered in isolation by tests/looknfeel-preserve.sh and are
# untouched by this fix (it only changes what $src value install.sh
# passes them) -- this file is scoped to the stable-deploy behavior.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

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

cleanup_paths=()
cleanup() { rm -rf "${cleanup_paths[@]}"; }
trap cleanup EXIT

# A disposable checkout -- a plain copy of this repo -- so it can
# actually be deleted below without touching the real repo this test
# lives in.
checkout="$(mktemp -d)"
cleanup_paths+=("$checkout")
cp -r "$repo_dir"/. "$checkout"/

fake_home="$(mktemp -d)"
cleanup_paths+=("$fake_home")

run_install() {
  ( HOME="$fake_home" PATH="$fake_bin:$PATH" "$checkout/install.sh" ) >"$fake_home/install.out" 2>&1
}

if run_install; then status1=0; else status1=$?; cat "$fake_home/install.out" >&2; fi
check "install from disposable checkout: exits 0" "$status1" "0"

deployed="$fake_home/.local/share/ruixen-shell/hyprland/looknfeel.ruixen.lua"
target="$fake_home/.config/hypr/looknfeel.lua"

check "looknfeel.lua symlinks to the stable deployed path, not the checkout" \
  "$(readlink "$target")" "$deployed"
check "deployed asset matches the checkout's content at install time" \
  "$(diff -q "$deployed" "$checkout/hyprland/looknfeel.ruixen.lua" >/dev/null 2>&1 && echo same)" "same"

# --- Reinstall/update atomically replaces the deployed asset --------
printf '\n-- extra marker appended to simulate an upstream change --\n' >> "$checkout/hyprland/looknfeel.ruixen.lua"
if run_install; then status2=0; else status2=$?; cat "$fake_home/install.out" >&2; fi
check "reinstall after a checkout change: exits 0" "$status2" "0"
check "reinstall: deployed asset was refreshed to match the changed checkout" \
  "$(diff -q "$deployed" "$checkout/hyprland/looknfeel.ruixen.lua" >/dev/null 2>&1 && echo same)" "same"
check "reinstall: symlink still points at the same stable path (no churn)" \
  "$(readlink "$target")" "$deployed"

content_before_delete="$(cat "$deployed")"

# --- The actual point of #15: delete the checkout entirely ----------
rm -rf "$checkout"
cleanup_paths=("$fake_home") # checkout is already gone, don't try again in cleanup

check "after deleting the checkout: deployed asset file still exists" \
  "$([[ -f "$deployed" ]] && echo yes)" "yes"
check "after deleting the checkout: looknfeel.lua symlink still resolves to a real file" \
  "$([[ -f "$(readlink -f "$target")" ]] && echo yes)" "yes"
check "after deleting the checkout: content is unchanged (not just an empty/broken file)" \
  "$(cat "$deployed")" "$content_before_delete"

default_deployed="$fake_home/.local/share/ruixen-shell/hyprland/looknfeel.default.lua"
check "after deleting the checkout: the 'off' variant was deployed too, also survives" \
  "$([[ -f "$default_deployed" ]] && echo yes)" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
