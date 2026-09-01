#!/usr/bin/env bash
# Covers the acceptance criteria of "[P1] Preserve pre-existing
# Hyprland looknfeel.lua files and symlinks": exercises
# lib/apply-looknfeel.sh and lib/restore-looknfeel.sh directly against
# a throwaway directory tree, not a real $HOME. Run directly:
# ./tests/looknfeel-preserve.sh
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
apply="$script_dir/../lib/apply-looknfeel.sh"
restore="$script_dir/../lib/restore-looknfeel.sh"

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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/src"
printf 'ruixen look and feel\n' > "$work/src/looknfeel.ruixen.lua"
src="$work/src/looknfeel.ruixen.lua"

mkdir -p "$work/omarchy-default"
printf 'omarchy default\n' > "$work/omarchy-default/looknfeel.lua"
omarchy_default="$work/omarchy-default/looknfeel.lua"

# --- Case A: nothing existed before Ruixen --------------------------
a_target="$work/a/looknfeel.lua"
a_pristine="$work/a/pristine"
mkdir -p "$(dirname "$a_target")"
"$apply" "$a_target" "$src" "$a_pristine" "111"
check "absent: target becomes a symlink to ruixen's own file" \
  "$(readlink "$a_target")" "$src"
check "absent: pristine record says absent" \
  "$([[ -e "$a_pristine/absent" ]] && echo yes)" "yes"
check "absent: no timestamped backup created (nothing to back up)" \
  "$(compgen -G "${a_target}.bak.*" >/dev/null 2>&1 && echo found || echo none)" "none"

# Reinstall -- pristine record must not be touched a second time
"$apply" "$a_target" "$src" "$a_pristine" "222"
check "absent, reinstalled: pristine record still says absent (not re-recorded)" \
  "$([[ -e "$a_pristine/absent" ]] && echo yes)" "yes"
check "absent, reinstalled: still points at ruixen's own file" \
  "$(readlink "$a_target")" "$src"

restore_a="$("$restore" "$a_target" "$a_pristine" "$omarchy_default")"
check "absent: restore falls back to Omarchy's own default" "$restore_a" "omarchy-default"
check "absent: restored file is a real file, not a symlink" \
  "$([[ -L "$a_target" ]] && echo symlink || echo regular)" "regular"
check "absent: restored content matches Omarchy's default" \
  "$(cat "$a_target")" "omarchy default"

# --- Case B: a real pre-existing regular file ------------------------
b_target="$work/b/looknfeel.lua"
b_pristine="$work/b/pristine"
mkdir -p "$(dirname "$b_target")"
printf 'the users own looknfeel content\n' > "$b_target"
"$apply" "$b_target" "$src" "$b_pristine" "111"
check "regular file: target becomes a symlink to ruixen's own file" \
  "$(readlink "$b_target")" "$src"
check "regular file: pristine copy preserved the exact content" \
  "$(cat "$b_pristine/looknfeel.lua")" "the users own looknfeel content"
check "regular file: timestamped backup also preserved the content" \
  "$(cat "${b_target}.bak.111")" "the users own looknfeel content"

restore_b="$("$restore" "$b_target" "$b_pristine" "$omarchy_default")"
check "regular file: restore reports file" "$restore_b" "file"
check "regular file: restored as a real file, not a symlink" \
  "$([[ -L "$b_target" ]] && echo symlink || echo regular)" "regular"
check "regular file: restored content matches the original exactly" \
  "$(cat "$b_target")" "the users own looknfeel content"

# --- Case C: a pre-existing symlink (e.g. a dotfiles setup) ---------
c_target="$work/c/looknfeel.lua"
c_pristine="$work/c/pristine"
mkdir -p "$(dirname "$c_target")"
dotfiles_target="$work/dotfiles/looknfeel.lua"
ln -s "$dotfiles_target" "$c_target"
"$apply" "$c_target" "$src" "$c_pristine" "111"
check "symlink: target becomes a symlink to ruixen's own file" \
  "$(readlink "$c_target")" "$src"
check "symlink: pristine record captured the exact original target" \
  "$(cat "$c_pristine/target")" "$dotfiles_target"
check "symlink: no regular-file pristine copy was made" \
  "$([[ -e "$c_pristine/looknfeel.lua" ]] && echo found || echo none)" "none"
check "symlink: timestamped backup is ITSELF a symlink to the original target" \
  "$(readlink "${c_target}.bak.111")" "$dotfiles_target"

restore_c="$("$restore" "$c_target" "$c_pristine" "$omarchy_default")"
check "symlink: restore reports the exact original target" "$restore_c" "symlink:$dotfiles_target"
check "symlink: restored AS a symlink, not copied as a regular file" \
  "$([[ -L "$c_target" ]] && echo symlink || echo regular)" "symlink"
check "symlink: restored symlink points at the exact original target" \
  "$(readlink "$c_target")" "$dotfiles_target"

# --- Case D: no pristine record at all (pre-dates this mechanism) --
d_target="$work/d/looknfeel.lua"
d_pristine="$work/d/pristine"
mkdir -p "$(dirname "$d_target")"
ln -s "$src" "$d_target"
restore_d="$("$restore" "$d_target" "$d_pristine" "$omarchy_default")"
check "no pristine record: reports that plainly rather than guessing" \
  "$restore_d" "no-pristine-record"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
