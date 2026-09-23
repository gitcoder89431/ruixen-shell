#!/usr/bin/env bash
# Direct request, after checking a reference theme's own window-look
# hook for how its blur read noticeably clearer: "im thinking of
# making that a setting in profile between frosted and transparent."
# Same pattern as Window Spacing (spacing-profile)/Animation Style
# (animation-profile): a plain-text state file the writer (Settings
# Profile page) and the readers (both looknfeel variants) have to
# independently agree on -- nothing at the language level keeps a
# value added to one in sync with the others, so this is exactly the
# kind of drift cava-state-contract.sh already guards against for a
# different plugin pair.
#
# Static Lua/QML checks only -- verifying the actual on-screen blur/
# opacity change needs a real Hyprland session, not something a CI
# fixture can measure cheaply.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
settings_qml="$repo_dir/ruixen.launcher/SettingsContent.qml"
ruixen_lua="$repo_dir/hyprland/looknfeel.ruixen.lua"
square_lua="$repo_dir/hyprland/looknfeel.square.lua"

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

# --- both Lua files parse cleanly (a real syntax check, not just grep) ---

if command -v luac >/dev/null 2>&1; then
  check "looknfeel.ruixen.lua parses without a syntax error" \
    "$(luac -p "$ruixen_lua" >/dev/null 2>&1 && echo ok || echo fail)" "ok"
  check "looknfeel.square.lua parses without a syntax error" \
    "$(luac -p "$square_lua" >/dev/null 2>&1 && echo ok || echo fail)" "ok"
else
  printf 'glass-profile-contract: luac not found, skipping Lua syntax checks\n' >&2
fi

# --- reader/writer agree on the state file path ---------------------------

check "SettingsContent.qml writes to ~/.local/state/ruixen/glass-profile" \
  "$(grep -c '/.local/state/ruixen/glass-profile' "$settings_qml")" "1"
check "looknfeel.ruixen.lua reads the same path" \
  "$(grep -c '/.local/state/ruixen/glass-profile' "$ruixen_lua")" "1"
check "looknfeel.square.lua reads the same path" \
  "$(grep -c '/.local/state/ruixen/glass-profile' "$square_lua")" "1"

# --- reader/writer agree on exactly frosted/transparent --------------------

check "SettingsContent.qml validates against exactly frosted/transparent" \
  "$(grep -c 'profile !== "frosted" && profile !== "transparent"' "$settings_qml")" "1"
check "SettingsContent.qml's own Glass picker offers exactly those two ids" \
  "$(grep -c '{ id: "frosted", label: "Frosted" }\|{ id: "transparent", label: "Transparent" }' "$settings_qml")" "2"
check "looknfeel.ruixen.lua defaults to frosted, only flips on an exact transparent match" \
  "$(grep -c 'if line == "transparent" then return line end' "$ruixen_lua")" "1"
check "looknfeel.square.lua has the identical reader (independent files, no shared base)" \
  "$(grep -c 'if line == "transparent" then return line end' "$square_lua")" "1"

# --- both Lua files agree on the exact numeric values per profile ---------

check "both Lua files use the same Transparent inactive_opacity (0.75)" \
  "$(grep -c 'and 0.75 or 0.94' "$ruixen_lua")$(grep -c 'and 0.75 or 0.94' "$square_lua")" "11"
check "both Lua files use the same Transparent blur size (4 vs. Frosted's 7)" \
  "$(grep -c 'and 4 or 7' "$ruixen_lua")$(grep -c 'and 4 or 7' "$square_lua")" "11"
check "both Lua files use the same Transparent blur passes (2 vs. Frosted's 3)" \
  "$(grep -c 'and 2 or 3' "$ruixen_lua")$(grep -c 'and 2 or 3' "$square_lua")" "11"

# --- no leftover Vibrant/Solid machinery (tried and reverted) --------------

check "no leftover vibrant/solid branching anywhere in either Lua file" \
  "$(grep -c 'ruixenGlassProfile == "vibrant"\|ruixenGlassProfile == "solid"\|ruixenGlassProfile ~= "solid"' "$ruixen_lua")$(grep -c 'ruixenGlassProfile == "vibrant"\|ruixenGlassProfile == "solid"\|ruixenGlassProfile ~= "solid"' "$square_lua")" "00"
check "no leftover vibrant/solid ids in SettingsContent.qml's own picker/validation" \
  "$(grep -c '"vibrant"\|"solid"' "$settings_qml")" "0"

# --- the actual decoration block reads the profile-driven variables, not a
# leftover hardcoded literal ------------------------------------------------

check "looknfeel.ruixen.lua's inactive_opacity is profile-driven, not hardcoded" \
  "$(grep -c 'inactive_opacity = ruixenInactiveOpacity' "$ruixen_lua")" "1"
check "looknfeel.ruixen.lua's blur size/passes are profile-driven, not hardcoded" \
  "$(grep -c 'size = ruixenBlurSize' "$ruixen_lua")$(grep -c 'passes = ruixenBlurPasses' "$ruixen_lua")" "11"
check "looknfeel.square.lua's inactive_opacity is profile-driven, not hardcoded" \
  "$(grep -c 'inactive_opacity = ruixenInactiveOpacity' "$square_lua")" "1"
check "looknfeel.square.lua's blur size/passes are profile-driven, not hardcoded" \
  "$(grep -c 'size = ruixenBlurSize' "$square_lua")$(grep -c 'passes = ruixenBlurPasses' "$square_lua")" "11"

# --- setGlassProfile writes AND triggers a live hyprctl reload -------------

check "setGlassProfile writes the file and reloads Hyprland live, same as spacing/animation profiles" \
  "$(grep -A4 'function setGlassProfile' "$settings_qml" | grep -c 'hyprctl reload')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
