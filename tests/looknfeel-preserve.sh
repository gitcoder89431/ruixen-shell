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

# --- Case E: target is ALREADY a Ruixen-managed symlink the very
# first time apply-looknfeel.sh ever runs (an earlier, unofficial
# setup, or a prior uninstall/reinstall cycle outside these scripts on
# the same machine). A real bug found live: recording this as
# "pristine" would capture Ruixen's own look as if it were the user's
# real original -- restore-looknfeel.sh would then "restore" it right
# back on uninstall instead of actually reverting anything.
e_target="$work/e/looknfeel.lua"
e_pristine="$work/e/pristine"
mkdir -p "$(dirname "$e_target")"
e_stale_ruixen_target="$work/somewhere/ruixen-shell/hyprland/looknfeel.ruixen.lua"
mkdir -p "$(dirname "$e_stale_ruixen_target")"
printf 'a stale ruixen look\n' > "$e_stale_ruixen_target"
ln -s "$e_stale_ruixen_target" "$e_target"
"$apply" "$e_target" "$src" "$e_pristine" "111"
check "self-referential capture: pristine record says absent, not the stale ruixen target" \
  "$([[ -e "$e_pristine/absent" ]] && echo yes)" "yes"
check "self-referential capture: no target file was written at all" \
  "$([[ -e "$e_pristine/target" ]] && echo found || echo none)" "none"
check "self-referential capture: target still becomes ruixen's own symlink" \
  "$(readlink "$e_target")" "$src"

restore_e="$("$restore" "$e_target" "$e_pristine" "$omarchy_default")"
check "self-referential capture: restore falls back to Omarchy's own default" \
  "$restore_e" "omarchy-default"
check "self-referential capture: restored content matches Omarchy's default" \
  "$(cat "$e_target")" "omarchy default"

# --- Case F: the STORED pristine record itself is self-referential
# (defense in depth on the restore side -- covers a record written by
# an older, buggy version of apply-looknfeel.sh before this fix
# existed, not just a fresh capture).
f_target="$work/f/looknfeel.lua"
f_pristine="$work/f/pristine"
mkdir -p "$f_pristine"
f_bad_record_target="$HOME/.local/share/ruixen-shell/hyprland/looknfeel.ruixen.lua"
printf '%s\n' "$f_bad_record_target" > "$f_pristine/target"
ln -s "$src" "$f_target"
restore_f="$("$restore" "$f_target" "$f_pristine" "$omarchy_default")"
check "self-referential stored record: reports self-referential-record, not the bad symlink" \
  "$restore_f" "self-referential-record"
check "self-referential stored record: restored as a real file, not a symlink" \
  "$([[ -L "$f_target" ]] && echo symlink || echo regular)" "regular"
check "self-referential stored record: falls back to Omarchy's own default content" \
  "$(cat "$f_target")" "omarchy default"

# --- Case G: self-referential stored record but no Omarchy default
# template available either -- must say so plainly, not fail silently.
g_target="$work/g/looknfeel.lua"
g_pristine="$work/g/pristine"
mkdir -p "$g_pristine"
printf '%s\n' "$f_bad_record_target" > "$g_pristine/target"
ln -s "$src" "$g_target"
restore_g="$("$restore" "$g_target" "$g_pristine" "$work/no-such-omarchy-default.lua")"
check "self-referential stored record, no default available: reports that plainly" \
  "$restore_g" "no-default-available"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
