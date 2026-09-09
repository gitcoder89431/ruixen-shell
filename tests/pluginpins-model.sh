#!/usr/bin/env bash
# Covers ruixen.pluginpins -- direct request: "instead of the AI icon,
# its a dropdown icon that shows the name of the available plugins you
# have... clicking or toggling them pins it onto the icons group". Lets
# any installed bar-widget plugin be pinned/unpinned from a dropdown
# instead of needing to live in the bar permanently.
#
# Can't drive a real Quickshell instance here (no compositor in CI), so
# this is a static invariant check against the actual QML source, same
# style as tests/lint-shell.sh's own pattern-based guards. Deploy-time
# behavior (the candidate list's real contents, an actual pin/unpin
# round trip) was verified live via a temporary debug IpcHandler, since
# removed -- see the commit message, not this file, for those results.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
widget_qml="$repo_dir/ruixen.pluginpins/BarWidget.qml"
manifest_json="$repo_dir/ruixen.pluginpins/manifest.json"

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

check "manifest declares kind bar-widget" \
  "$(grep -c '"bar-widget"' "$manifest_json")" "1"
check "manifest defaults to the right section (curatedRightIds places it explicitly either way)" \
  "$(grep -c '"defaultSection": "right"' "$manifest_json")" "1"

# Structural ruixen ids this widget must never offer to unpin -- doing so
# through this generic mechanism would silently break the bar's own
# curated layout (the app launcher, workspace switcher, tray, its own
# settings/quickactions group) rather than just hiding an optional widget.
required_exclusions=(
  "ruixen.applauncher" "ruixen.workspaces" "ruixen.pinnedapps" "ruixen.tray"
  "ruixen.quickactions" "ruixen.settingsbutton"
  "ruixen.weather" "ruixen.media" "ruixen.pluginpins" "omarchy.clock"
  "omarchy.system-update" "omarchy.power"
  "omarchy.keyboard-layout" "omarchy.indicators" "omarchy.network"
  "omarchy.active-window"
)
excluded_block="$(grep -A20 'readonly property var excludedIds:' "$widget_qml")"
missing=0
for id in "${required_exclusions[@]}"; do
  if ! grep -qF "\"$id\"" <<<"$excluded_block"; then
    printf 'FAIL - excludedIds is missing required id: %s\n' "$id"
    missing=$((missing + 1))
  fi
done
if [[ "$missing" -eq 0 ]]; then
  printf 'ok   - excludedIds covers every structural ruixen id, omarchy.clock (shares clockPill with weather), system-update/power (curatedPill'"'"'s exact fixed four), keyboard-layout (self-hides on a single layout), indicators (redundant + a real IPC collision), network (a real, ongoing IPC collision), and active-window (ruixen.notch'"'"'s own collapsed player pill already shows it)\n'
  pass=$((pass + 1))
else
  fail_count=$((fail_count + 1))
fi

# Deliberately NOT excluded: ruixen.stayawake and omarchy.agents both
# render in ruixen.pluginpins' OWN pill now (the toggle icon lives
# together with whatever it toggles -- "microphone network cofee ai
# [are] toggleable from the plugins pin so they stay pinnable or not in
# the plugin group"), so pinning/unpinning them through this dropdown is
# the intended interaction, not something to guard against. A future
# change accidentally excluding either here should fail loudly, not
# silently make them unpinnable again.
#
# ruixen.peripherals joins this list too now -- it briefly lived in
# curatedRightIds instead (excluded from here for that reason, see git
# history), then moved back out to reduce clutter (direct follow-up:
# "its not that important for me to always see it right now"). Pinnable
# through here once more, same as stayawake/agents.
must_not_exclude=("ruixen.stayawake" "omarchy.agents" "ruixen.peripherals")
wrongly_excluded=0
for id in "${must_not_exclude[@]}"; do
  if grep -qF "\"$id\"" <<<"$excluded_block"; then
    printf 'FAIL - excludedIds should NOT contain: %s (meant to stay toggle-able for discoverability)\n' "$id"
    wrongly_excluded=$((wrongly_excluded + 1))
  fi
done
if [[ "$wrongly_excluded" -eq 0 ]]; then
  printf 'ok   - stayawake/agents/peripherals are NOT excluded (they render in this widget'"'"'s own pill, toggling them through it is the intended interaction)\n'
  pass=$((pass + 1))
else
  fail_count=$((fail_count + 1))
fi

# Real, live bug found after issue #45/#38's own fix: bar.barWidgetRegistry
# (the fix's own replacement for the broken bar.shell.pluginRegistry)
# shrinks the moment a non-Omarchy-first-party widget (every ruixen.* one)
# is fully unpinned -- Omarchy's own isEnabled() treats it as "disabled"
# once it's found nowhere in bar.layout, unregistering its widget
# component entirely, with no row left in this dropdown to pin it back
# from (confirmed live, reproduced on ruixen.stayawake independently of
# ruixen.peripherals). Candidates are now sourced from the real `omarchy
# plugin list --json` catalog instead (scanned from disk, confirmed live
# it keeps listing a plugin with enabled:false rather than omitting it)
# -- bar.barWidgetRegistry is only consulted afterward, for a currently-
# registered widget's own shorter displayName.
check "candidates are sourced from the real omarchy plugin list --json catalog, not the shrinking widget registry" \
  "$(grep -c 'command: \["omarchy", "plugin", "list", "--json"\]' "$widget_qml")" "1"
check "candidates filters the catalog to kind bar-widget only" \
  "$(grep -c 'kinds\.indexOf("bar-widget")' "$widget_qml")" "1"
check "candidates excludes excludedIds" \
  "$(grep -c 'excludedIds\.indexOf(p\.id)' "$widget_qml")" "1"
check "candidates re-evaluates on registry changes (revision read for its binding dependency)" \
  "$(grep -c 'reg\.revision' "$widget_qml")" "1"

# Direct follow-up, found live right after the fix above: the label
# flickered between the registry's own short displayName ("Peripherals")
# and the catalog's plain name ("Ruixen Peripherals") every time a row
# got pinned/unpinned, since the old code read the registry fresh inside
# candidates on every recompute. A manifest's own barWidget.displayName
# never changes at runtime, so it's captured once per id into
# displayNameCache and trusted forever after instead of being re-derived
# each time -- mutating a property read by the SAME binding that reads
# it back (candidates itself) would be the exact read-your-own-write
# binding-loop anti-pattern this file's own registerClickTarget comment
# already warns about, so the cache is populated off the registry's own
# revision signal in a separate Connections block, not inside candidates.
check "a captured displayName is cached, not re-read from the registry fresh every time (fixes the pin/unpin name flicker)" \
  "$(grep -c 'property var displayNameCache' "$widget_qml")" "1"
check "the cache is populated by its own function, not inside candidates' own binding (avoids a binding loop)" \
  "$(grep -c 'function captureDisplayNames' "$widget_qml")" "1"
check "candidates itself only ever READS the cache, never writes it" \
  "$(grep -A20 'readonly property var candidates:' "$widget_qml" | grep -c 'root\.displayNameCache\[p\.id\]')" "1"
check "candidates never calls captureDisplayNames from inside its own binding" \
  "$(grep -A20 'readonly property var candidates:' "$widget_qml" | grep -c 'captureDisplayNames()' || true)" "0"
check "the cache refreshes off the widget registry's own real revision signal" \
  "$(grep -c 'function onRevisionChanged() { root\.captureDisplayNames() }' "$widget_qml")" "1"
check "the plugin catalog is fetched once on startup" \
  "$(grep -A3 'Component\.onCompleted: {' "$widget_qml" | grep -c 'refreshPluginCatalog()')" "1"
check "the displayName cache is also seeded once on startup" \
  "$(grep -A3 'Component\.onCompleted: {' "$widget_qml" | grep -c 'captureDisplayNames()')" "1"
check "the plugin catalog also refreshes every time the popup opens (picks up a newly-installed plugin)" \
  "$(grep -A3 'onOpenChanged: if (open)' "$widget_qml" | grep -c 'root\.refreshPluginCatalog()')" "1"
# Direct follow-up: dragging turned out to have no way to populate an
# initially-empty left-side group at all (ModuleList only registers a
# real drop-target slot for entries that already exist), so pin/unpin
# moved to left/right click here instead of drag-and-drop -- "can we
# do right click and left click to send it to the new group on the
# left or right depending on the click". currentSide now scans
# bar.barConfig.layout directly (the old registry-owned
# findBarLocation()/shellConfigProvider() pair doesn't exist on the new
# scoped shell object) -- the same {left,center,right} shape setPinSide
# below already reads/writes, so this is the same structure, not a new
# mechanism.
check "currentSide scans bar.barConfig.layout directly" \
  "$(grep -c 'bar && bar\.barConfig ? bar\.barConfig\.layout : null' "$widget_qml")" "1"
check "currentSide sweeps all three sections, matching setPinSide's own section list" \
  "$(grep -A10 'function currentSide' "$widget_qml" | grep -c '\["left", "center", "right"\]')" "1"

# Unpin has to search every section, not just the clicked one -- a
# plugin someone dragged elsewhere (the bar's own drag-to-reorder
# feature) must still be removable from here.
setpinside_block="$(grep -A20 'function setPinSide' "$widget_qml")"
check "setPinSide sweeps all three sections (left/center/right), not just the clicked side" \
  "$(grep -c '\["left", "center", "right"\]' <<<"$setpinside_block")" "1"
check "setPinSide uses mutateShellConfig, the same primitive the bar's own drag-reorder already uses" \
  "$(grep -c 'bar\.shell\.mutateShellConfig(function' "$widget_qml")" "1"

check "the row's own MouseArea accepts both left and right click" \
  "$(grep -c 'acceptedButtons: Qt\.LeftButton | Qt\.RightButton' "$widget_qml")" "1"
check "left-click pins right, right-click pins left (Qt.RightButton ternary)" \
  "$(grep -c 'button === Qt\.RightButton ? "left" : "right"' "$widget_qml")" "1"

# The trigger/checkmark/left-arrow glyphs must be QML \u escapes, not
# pasted Nerd Font characters -- direct precedent for why: a hidden/
# corrupted glyph byte has broken this exact thing twice already
# elsewhere in this repo (ruixen.pinnedapps' own fallback glyph,
# Bar.qml's sidebar label).
check "trigger glyph is a \\u escape, not a raw pasted character" \
  "$(grep -c 'text: "\\uf00a"' "$widget_qml")" "1"
check "right-pinned glyph (check, U+F00C) is a \\u escape, not a raw pasted character" \
  "$(grep -c '"\\uf00c"' "$widget_qml")" "1"
check "left-pinned glyph (long-arrow-left, U+F177) is a \\u escape, not a raw pasted character" \
  "$(grep -c '"\\uf177"' "$widget_qml")" "1"

check "no leftover bar.shell.pluginRegistry read, not even in a comment" \
  "$(grep -c 'bar\.shell\.pluginRegistry' "$widget_qml" || true)" "0"
check "widgetRegistry reads bar.barWidgetRegistry, unaffected by the bar.shell restriction" \
  "$(grep -c 'bar ? bar\.barWidgetRegistry : null' "$widget_qml")" "1"

# No debug scaffolding left behind from live verification.
check "no leftover console.log debug statements" \
  "$(grep -c 'console\.log' "$widget_qml")" "0"
check "no leftover debug IpcHandler declaration (a mention of the word in a comment is fine)" \
  "$(grep -c 'IpcHandler {' "$widget_qml")" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
