#!/usr/bin/env bash
# Pure function, no side effects: reads whatever shell.json already
# exists on stdin (or "{}" if there was none), writes the merged result
# to stdout. Kept separate from install.sh so the merge logic itself has
# a real, isolated test -- see tests/shell-json-merge.sh -- and so
# install.sh stays focused on the filesystem/backup steps around it.
#
# What each key does on merge -- see install.sh's own [2/4] comment for
# the full "why", this is just the mechanism:
#   - bar: Ruixen's own canonical object, but ONLY the first time
#     ruixen.bar takes over the bar slot (no bar yet, or a different
#     one active). Once ruixen.bar already owns it, the whole object is
#     left exactly as it was -- bar.docked (ruixen-bar-mode.sh /
#     Settings.qml's own toggle) and bar.layout (widget order/hidden
#     state, movable via `omarchy bar move` and Settings) are both real
#     runtime-mutable state living inside this same object, not static
#     config, so replacing it wholesale on every reinstall would
#     silently revert both back to the hardcoded default every time.
#   - plugins: every existing entry (ruixen-owned or not) is left
#     completely untouched; only a Ruixen id that isn't present AT ALL
#     gets a fresh bare {id} entry appended. Idempotent (never
#     duplicates) without needing to strip and re-add ruixen's own
#     entries, which would have the same live-state-wipe risk the bar
#     fix above addresses if one ever grows extra fields the way
#     bar.layout entries already have.
#   - idle: left alone entirely if the caller's existing JSON already
#     has one -- only Ruixen's own default applies when the key is
#     missing.
#   - any other top-level key: passed through verbatim.
#
# ruixen.workspaces appears in "left" only, not also in "center" the way
# an earlier version of this canonical layout had it -- direct review
# finding ("Resolve ruixen.workspaces allowMultiple mismatch with the
# default bar layout").
#
# Traced the actual mechanism in ruixen.bar/Bar.qml rather than assuming:
# it's NOT a registry dedup keyed by plugin id (Loader.sourceComponent
# happily creates one independent instance per Loader from a shared
# Component -- confirmed via a temporary debug IpcHandler exposing
# debugBarGeometry() on this real live machine, restarted, queried over
# IPC, then removed). The real reason the old "center" duplicate never
# rendered a second widget is simpler: the horizontal bar's center pill
# (clockPill) only ever reads two hardcoded ids out of "center" --
# "ruixen.weather" and "omarchy.clock" -- so a "ruixen.workspaces" entry
# placed in "center" was just never read by anything in horizontal mode,
# not deduplicated.
#
# That's NOT true for the vertical bar layout, though --
# CenterModules/LeftModules (used when root.vertical) render an
# UNFILTERED ModuleList over the raw region array, so the old duplicate
# WOULD have created two real rendered instances there. So this was a
# real latent bug for anyone running the bar docked to a side, not just
# a harmless contradiction -- removing it is a correctness fix, not just
# a cleanup.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Lives in its own file, not an inline heredoc, as of "Preserve third-
# party bar widgets added while Ruixen is installed during uninstall"
# (#26): lib/merge-uninstall-bar.sh needs the exact same "what does
# Ruixen own" canonical layout this script does, to tell a foreign bar
# widget a user added while Ruixen was installed apart from one Ruixen
# itself injected -- reading the same file is what keeps those two
# scripts' idea of "Ruixen-owned" from ever drifting apart. No comments
# inside the file itself: it's parsed as strict JSON via jq --argjson,
# which does not accept // comments -- an earlier attempt at
# documenting this inline broke every install/update test until the
# explanation was moved up here instead.
ruixen_bar_json="$(cat "$script_dir/ruixen-bar-canonical.json")"
# Every ruixen.* id that has no OTHER way to get enabled -- a
# bar-widget-kind plugin (applauncher, tray, ...) is enabled by simply
# appearing anywhere in ruixenBar's own layout above, so it doesn't
# need to be listed here too. These are the ones with no bar-widget
# presence in the canonical layout, so this top-level plugins array is
# their only home. ruixen.wallpaper was missing from this list
# entirely until a direct review caught it ("Explicitly enable
# ruixen.wallpaper on a clean install") -- it only ever worked on this
# dev machine because it had been enabled by hand while it was being
# built, never actually reachable on a real clean install.
#
# ruixen.media is a dual bar-widget/service plugin, deliberately kept
# OUT of ruixenBar's layout (its own oversized play/pause badge -- see
# its commit history) but still needed here so its service half (the
# notch's own music control) is enabled. Enabling a bar-widget-kind
# plugin this way, instead of through the layout, does not place it on
# the bar -- placement is layout-driven only -- confirmed live on this
# dev machine's own shell.json.
ruixen_plugin_ids='["ruixen.frame-widget", "ruixen.notch", "ruixen.settings", "ruixen.wallpaper", "ruixen.media"]'
default_idle_json='{"lock": 300, "screensaver": 150}'

existing_json="$(cat)"

jq -n \
  --argjson existing "$existing_json" \
  --argjson ruixenBar "$ruixen_bar_json" \
  --argjson ruixenPluginIds "$ruixen_plugin_ids" \
  --argjson defaultIdle "$default_idle_json" \
  '
  # bar: only installed fresh the first time ruixen.bar takes over the
  # bar slot (no bar yet, or some other bar active). Once ruixen.bar
  # already owns it, the WHOLE object is left exactly as-is on a
  # reinstall/update -- confirmed live that bar.docked
  # (ruixen-bar-mode.sh / Settings.qml own toggle) and bar.layout
  # (widget order/hidden state, movable via omarchy bar move and
  # Settings) are both real runtime-mutable state living inside this
  # same object, not static config -- replacing it wholesale on every
  # reinstall would silently revert both back to the hardcoded default
  # every time, which is exactly the kind of data loss this issue
  # exists to prevent, just one level deeper than a first pass assumed.
  (if ($existing.bar.id // "") == "ruixen.bar" then $existing.bar else $ruixenBar end) as $ownedBar

  # ruixen.media is deliberately never a real bar-widget entry (its own
  # oversized play/pause badge -- see ruixen-bar-canonical.json own
  # comment) and is now locked in ruixen.settings plugin list with no
  # toggle at all, so there is no user-facing way left to remove it if
  # it is already sitting in an EXISTING install own bar.layout from
  # before that fix -- an existing owner bar is otherwise left
  # completely untouched above (see that comment), which would
  # otherwise let this one stale, now-unremovable entry survive every
  # future update forever. This is an unconditional strip of that one
  # specific id, not a general layout migration -- omarchy.menu and
  # anything else a user actually chose to keep is left alone.
  | (if ($ownedBar.layout | type) == "object" then
       $ownedBar | .layout |= with_entries(
         .value |= (if type == "array" then map(select(.id != "ruixen.media")) else . end)
       )
     else $ownedBar end) as $mergedBar

  # plugins: existing entries (ruixen-owned or not) are left completely
  # untouched -- only ids from ruixenPluginIds that are not present AT
  # ALL get a fresh bare {id} entry appended. Strip-then-re-add would
  # have the same "wipe live per-plugin state on reinstall" problem the
  # bar fix above addresses, if a ruixen plugin entry ever grows extra
  # fields the way bar.layout entries already have.
  | ($existing.plugins // []) as $existingPlugins
  | ($existingPlugins | map(.id)) as $existingIds
  # `. as $id` matters here, not just style -- `index(.)` inside a
  # nested pipe re-evaluates `.` against the input of that pipe itself
  # (already $existingIds by that point), not the outer map item, so it
  # silently degenerates into "is $existingIds a subsequence of
  # itself" (always true at index 0) instead of a real membership
  # check. Binding the map item to $id first sidesteps that entirely.
  | ($ruixenPluginIds | map(. as $id | select(($existingIds | index($id)) == null) | {id: $id})) as $newRuixenEntries
  | ($existingPlugins + $newRuixenEntries) as $mergedPlugins

  | $existing
  + {version: ($existing.version // 1)}
  + {bar: $mergedBar}
  + {plugins: $mergedPlugins}
  + {idle: ($existing.idle // $defaultIdle)}
  '
