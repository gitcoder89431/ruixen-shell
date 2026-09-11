#!/usr/bin/env bash
# Covers the ruixen-shell issue #44/#38 fix: shell.appLibrary only
# populates for a plugin declaring manifest kind "menu" under Omarchy
# v4.0.3, which neither call site here does -- and per #44's own
# research, shell.appLibrary is independently broken by a caching bug
# even for a plugin that DOES declare that kind (omacom/omarchy#10871,
# #10876), so adding a fake "menu" kind was never a real fix either way.
#
# Quickshell.DesktopEntries is a real, core Quickshell type independent
# of Omarchy -- ruixen.notch/AppLibrary.qml, ruixen.pinnedapps/AppLibrary.qml,
# and ruixen.launcher/AppLibrary.qml (issue #52: added to this guard when
# ruixen.launcher's own copy was discovered NOT covered here, even though
# it's kept byte-identical to the other two by the same convention -- see
# ruixen.launcher/AppLibrary.qml's own header) are a from-scratch wrapper
# around it, with AppSearch.js (ranking algorithm only) ported verbatim
# from Omarchy's own real /usr/share/omarchy/shell/services/AppSearch.js
# (MIT).
#
# Static QML/JS checks only. Live end-to-end verification (real icons
# resolved for real installed apps in the pinned-apps row; search
# ranking correct for a real query; a real, confirmed-hidden desktop
# entry actually filtered out of results, via a temporary debug
# IpcHandler since removed) was done manually against the actual 4.0.2
# install this session -- not repeated here since it needs a real
# desktop-entry set to search, not something a CI fixture can
# synthesize cheaply. launch() itself was not live-fired (it would open
# a real window) -- verified instead by exact comparison against
# Omarchy's own real AppLibrary.qml launch() function, byte-for-byte
# the same Util.execDetached/shellQuote call.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
notch_lib="$repo_dir/ruixen.notch/AppLibrary.qml"
notch_search="$repo_dir/ruixen.notch/AppSearch.js"
pinned_lib="$repo_dir/ruixen.pinnedapps/AppLibrary.qml"
pinned_search="$repo_dir/ruixen.pinnedapps/AppSearch.js"
# "rlauncher_*", not "launcher_*" -- that name's already taken below by
# ruixen.notch/LauncherContent.qml, a completely different file.
rlauncher_lib="$repo_dir/ruixen.launcher/AppLibrary.qml"
rlauncher_search="$repo_dir/ruixen.launcher/AppSearch.js"
# Issue #61: same byte-identical-duplicate-across-a-plugin-boundary
# situation as AppLibrary.qml/AppSearch.js above, just a different pair
# of plugins (ruixen.launcher consumes it to build the real search root
# set; ruixen.settings reads/writes it via its own Launcher settings
# page) -- see LauncherSearchConfig.js's own header for the full "why".
launcher_search_config="$repo_dir/ruixen.launcher/LauncherSearchConfig.js"
settings_search_config="$repo_dir/ruixen.settings/LauncherSearchConfig.js"
# Same byte-identical-duplicate situation, different pair again --
# ruixen.peripherals' own battery-level coloring needs the theme's
# green/yellow/red (see ThemeColors.qml's own header for the full "why").
bar_theme_colors="$repo_dir/ruixen.bar/ThemeColors.qml"
peripherals_theme_colors="$repo_dir/ruixen.peripherals/ThemeColors.qml"
launcher_qml="$repo_dir/ruixen.notch/LauncherContent.qml"
overlay_qml="$repo_dir/ruixen.notch/Overlay.qml"
pinned_widget="$repo_dir/ruixen.pinnedapps/BarWidget.qml"
# Issue #64: static/provider-level coverage that configured exclusions
# actually reach fd/rg's own argv, alongside LauncherSearchConfig.test.js's
# own pure unit tests for the underlying normalization logic -- neither
# provider's own buildFdArgs/buildRgArgs is a plain JS module `require()`
# can load (both live inside a QML Item), so this is a grep-based static
# check on the real source instead, same convention this file's own
# "no leftover restricted API calls" section above already uses.
rfiles_search="$repo_dir/ruixen.launcher/FileSearchProvider.qml"
rcontent_search="$repo_dir/ruixen.launcher/FileContentSearchProvider.qml"

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

# --- no leftover restricted API calls -----------------------------------

# "2" -- both are this migration's own explanatory comments (the prop
# doc comment and the header note), not a real call site.
check "LauncherContent.qml has no leftover REAL shell.appLibrary read" \
  "$(grep -c 'shell\.appLibrary' "$launcher_qml" || true)" "2"
# "1" -- this migration's own explanatory comment.
check "BarWidget.qml (pinnedapps) has no leftover REAL bar.shell.appLibrary read" \
  "$(grep -c 'bar\.shell\.appLibrary' "$pinned_widget" || true)" "1"

# --- all three copies exist and stay byte-identical ----------------------

check "ruixen.notch/AppLibrary.qml exists" "$([[ -f "$notch_lib" ]] && echo yes)" "yes"
check "ruixen.pinnedapps/AppLibrary.qml exists" "$([[ -f "$pinned_lib" ]] && echo yes)" "yes"
check "ruixen.launcher/AppLibrary.qml exists" "$([[ -f "$rlauncher_lib" ]] && echo yes)" "yes"
check "the three AppLibrary.qml copies are byte-identical (plugin folders can't share a file)" \
  "$(diff -q "$notch_lib" "$pinned_lib" >/dev/null 2>&1 && diff -q "$notch_lib" "$rlauncher_lib" >/dev/null 2>&1 && echo same || echo different)" "same"
check "the three AppSearch.js copies are byte-identical" \
  "$(diff -q "$notch_search" "$pinned_search" >/dev/null 2>&1 && diff -q "$notch_search" "$rlauncher_search" >/dev/null 2>&1 && echo same || echo different)" "same"

check "ruixen.launcher/LauncherSearchConfig.js exists" "$([[ -f "$launcher_search_config" ]] && echo yes)" "yes"
check "ruixen.settings/LauncherSearchConfig.js exists" "$([[ -f "$settings_search_config" ]] && echo yes)" "yes"
check "the two LauncherSearchConfig.js copies are byte-identical (plugin folders can't share a file)" \
  "$(diff -q "$launcher_search_config" "$settings_search_config" >/dev/null 2>&1 && echo same || echo different)" "same"

check "ruixen.bar/ThemeColors.qml exists" "$([[ -f "$bar_theme_colors" ]] && echo yes)" "yes"
check "ruixen.peripherals/ThemeColors.qml exists" "$([[ -f "$peripherals_theme_colors" ]] && echo yes)" "yes"
check "the two ThemeColors.qml copies are byte-identical (plugin folders can't share a file)" \
  "$(diff -q "$bar_theme_colors" "$peripherals_theme_colors" >/dev/null 2>&1 && echo same || echo different)" "same"

# --- Issue #64: configured exclusions actually reach fd/rg argv ---------

# The old hardcoded lists must be GONE, not just supplemented -- a
# leftover excludeDirs property reading would mean buildFdArgs/buildRgArgs
# could still silently ignore the shared config for names.
check "FileSearchProvider.qml has no leftover hardcoded excludeDirs property" \
  "$(grep -c 'property var excludeDirs' "$rfiles_search" || true)" "0"
check "FileContentSearchProvider.qml has no leftover hardcoded excludeDirs property" \
  "$(grep -c 'property var excludeDirs' "$rcontent_search" || true)" "0"

check "FileSearchProvider.qml's buildFdArgs reads config.excludeNames, not a hardcoded list" \
  "$(grep -c 'searchConfig\.excludeNames' "$rfiles_search")" "1"
check "FileContentSearchProvider.qml's buildRgArgs reads config.excludeNames via its own bound property" \
  "$(grep -c 'root\.excludeNames' "$rcontent_search")" "1"

check "FileSearchProvider.qml's buildFdArgs applies excludeInfoForRoot for subtree excludePaths" \
  "$(grep -c 'LauncherSearchConfig\.excludeInfoForRoot' "$rfiles_search")" "1"
check "FileContentSearchProvider.qml's buildRgArgs applies excludeInfoForRoot for subtree excludePaths" \
  "$(grep -c 'LauncherSearchConfig\.excludeInfoForRoot' "$rcontent_search")" "1"

check "FileSearchProvider.qml's runSearch skips a root that exactly matches an exclusion" \
  "$(grep -c 'LauncherSearchConfig\.rootExactlyExcluded(' "$rfiles_search")" "1"
check "FileContentSearchProvider.qml's runSearch skips a root that exactly matches an exclusion" \
  "$(grep -c 'LauncherSearchConfig\.rootExactlyExcluded(' "$rcontent_search")" "1"

# Confirmed live (see LauncherSearchConfig.js's own excludeInfoForRoot
# comment): rg's own -g glob anchoring follows the PROCESS's cwd, not the
# search-root argument the way fd's --exclude does -- every one of the 4
# worker Process objects must force cwd to "/" for an absolute exclude
# glob to anchor correctly regardless of which root is being searched.
check "FileContentSearchProvider.qml forces workingDirectory \"/\" on all 4 worker Process objects" \
  "$(grep -c 'workingDirectory: "/"' "$rcontent_search")" "4"

# --- Issue #65: overlapping/nested roots compacted before scheduling ----

check "FileSearchProvider.qml's runSearch compacts its root list before scheduling" \
  "$(grep -c 'LauncherSearchConfig\.compactRoots(' "$rfiles_search")" "1"
check "FileContentSearchProvider.qml's runSearch compacts its root list before scheduling" \
  "$(grep -c 'LauncherSearchConfig\.compactRoots(' "$rcontent_search")" "1"

# --- AppLibrary.qml wraps the real, unaffected Quickshell type ----------

check "sortedEntries reads Quickshell's own DesktopEntries singleton" \
  "$(grep -c 'DesktopEntries\.applications\.values' "$notch_lib")" "1"
# "4" -- 3 real calls (empty icon, themed lookup, final fallback) plus
# one mention in this file's own header comment.
check "iconSource falls back through Quickshell.iconPath, not a first-party service" \
  "$(grep -c 'Quickshell\.iconPath' "$notch_lib")" "4"
check "launch uses the same uwsm-app/gtk-launch command Omarchy's own real AppLibrary.qml uses, confirmed by reading it directly" \
  "$(grep -cF 'Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))' "$notch_lib")" "1"
check "hidden-entry filtering reads the real launcher.hides file" \
  "$(grep -c '/default/omarchy/launcher\.hides' "$notch_lib")" "1"
check "hidden-entry filtering runs the real hidden-entries.sh script" \
  "$(grep -c '/shell/services/hidden-entries\.sh' "$notch_lib")" "1"

# --- AppSearch.js is the real ranking algorithm, not a placeholder ------

check "fuzzyScore implements prefix-match-highest ranking (name match at index 0 scores highest)" \
  "$(grep -c 'directName === 0' "$notch_search")" "1"
check "sortedEntries respects the real noDisplay field" \
  "$(grep -c 'entry\.noDisplay' "$notch_search")" "1"
check "sortedEntries applies the hidden callback" \
  "$(grep -c 'hiddenCallback(entry)' "$notch_search")" "1"

# --- wiring: one instance per plugin, threaded down correctly -----------

check "Overlay.qml instantiates one AppLibrary for the whole session" \
  "$(grep -c 'AppLibrary {' "$overlay_qml")" "1"
check "Overlay.qml threads it down to LauncherContent" \
  "$(grep -c 'appLibrary: appLibrary' "$overlay_qml")" "1"
check "LauncherContent.qml declares the appLibrary passthrough prop" \
  "$(grep -c 'property var appLibrary: null' "$launcher_qml")" "1"
check "ruixen.pinnedapps/BarWidget.qml owns its own local instance via an alias" \
  "$(grep -c 'readonly property alias appLibrary: appLibraryImpl' "$pinned_widget")" "1"
check "ruixen.pinnedapps/BarWidget.qml instantiates AppLibrary" \
  "$(grep -c 'AppLibrary { id: appLibraryImpl }' "$pinned_widget")" "1"

# --- no debug scaffolding left behind ------------------------------------

check "no leftover debug IpcHandler in Overlay.qml (a mention of the word in a comment is fine)" \
  "$(grep -c 'target: "debug\.applibrary"' "$overlay_qml" || true)" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
