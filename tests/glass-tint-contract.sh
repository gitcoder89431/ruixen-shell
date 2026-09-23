#!/usr/bin/env bash
# Direct request, after remembering this had already been explored:
# "i think we had this effect before in the past but opted to go for
# the theme tint only. i remember it was pretty cool." Confirmed
# directly in this repo's own git history (d527a25, e864c76): Black
# (Qt.rgba(0, 0, 0, ...), zero theme influence) is genuinely this
# property's own ORIGINAL value, from before the accent tint was ever
# added -- this test locks in that it's an exact revival, not a fresh
# invention with different numbers.
#
# A separate control from Glass Effect (glass-profile) -- orthogonal
# axes: this is the launcher card's own TINT COLOR (a pure QML
# property in Launcher.qml), Glass Effect is Hyprland-level blur/
# opacity STRENGTH. No `hyprctl reload` involved here at all, unlike
# Glass Effect/Window Spacing/Animation Style -- Launcher.qml's own
# FileView picks up the state file change directly, live.
#
# Same reader/writer-agreement shape cava-state-contract.sh/
# glass-profile-contract.sh already cover for their own plugin pairs.
#
# Static QML checks only -- verifying the actual on-screen tint change
# needs a real running shell, not something a CI fixture can measure
# cheaply.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
launcher_qml="$repo_dir/ruixen.launcher/Launcher.qml"
settings_qml="$repo_dir/ruixen.launcher/SettingsContent.qml"

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

# --- reader/writer agree on the state file path and exact values ---------

check "Launcher.qml reads from ~/.local/state/ruixen/glass-tint-mode" \
  "$(grep -c '/.local/state/ruixen/glass-tint-mode' "$launcher_qml")" "1"
check "SettingsContent.qml writes to the same path" \
  "$(grep -c '/.local/state/ruixen/glass-tint-mode' "$settings_qml")" "1"
check "Launcher.qml defaults to themed, only flips on an exact black match" \
  "$(grep -c 'root.glassTintMode = (v === "black") ? v : "themed"' "$launcher_qml")" "1"
check "SettingsContent.qml validates against exactly themed/black" \
  "$(grep -c 'if (mode !== "themed" && mode !== "black") return' "$settings_qml")" "1"
check "SettingsContent.qml's own Glass Tint picker offers exactly those two ids" \
  "$(grep -c '{ id: "themed", label: "Themed" }\|{ id: "black", label: "Dark" }' "$settings_qml")" "2"

# --- the Black value is an exact revival of this property's real original,
# not a fresh guess (confirmed directly in git history: d527a25/e864c76) ---

check "Black resolves to pure #000000, zero theme influence -- this property's own original value before any accent tint existed" \
  "$(grep -A1 'readonly property color glassTint: root.glassTintMode === "black"' "$launcher_qml" | grep -c '? "#000000"')" "1"
check "Themed keeps the exact live accent-tint formula unchanged (0.25 ratio)" \
  "$(grep -c 'Qt.tint("#000000", Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25))' "$launcher_qml")" "1"

# --- no hyprctl reload here -- this is pure QML state, not Hyprland config --

check "setGlassTintMode does NOT shell out to hyprctl (unlike setGlassProfile)" \
  "$(grep -A4 'function setGlassTintMode' "$settings_qml" | grep -c 'hyprctl')" "0"

# --- glassBackground/every other glassTint consumer derives from the same
# property, so the toggle propagates everywhere for free ------------------

check "glassBackground still derives from glassTint (single source of truth)" \
  "$(grep -c 'readonly property color glassBackground: Qt.rgba(glassTint.r, glassTint.g, glassTint.b, 0.68)' "$launcher_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
