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
set -Eeuo pipefail

ruixen_bar_json=$(cat <<'BARJSON'
{
    "id": "ruixen.bar",
    "position": "top",
    "transparent": true,
    "centerAnchor": "omarchy.clock",
    "layout": {
        "left": [
            { "id": "ruixen.applauncher" },
            { "id": "ruixen.workspaces" }
        ],
        "center": [
            { "id": "ruixen.workspaces" },
            { "id": "omarchy.menu" },
            { "id": "ruixen.media" },
            { "id": "ruixen.weather" },
            {
                "id": "omarchy.clock",
                "format": "HH:mm",
                "formatAlt": "d MMMM 'W'ww yyyy",
                "verticalFormat": "HH\n—\nmm"
            }
        ],
        "right": [
            { "id": "omarchy.keyboard-layout" },
            { "id": "omarchy.system-update" },
            { "id": "ruixen.tray", "hidden": [] },
            { "id": "ruixen.stayawake" },
            { "id": "ruixen.quickactions" },
            { "id": "omarchy.agents" },
            { "id": "omarchy.power" },
            { "id": "ruixen.settingsbutton" }
        ]
    }
}
BARJSON
)
# Every ruixen.* id that has no OTHER way to get enabled -- a
# bar-widget-kind plugin (applauncher, media, tray, ...) is enabled by
# simply appearing anywhere in ruixenBar's own layout above, so it
# doesn't need to be listed here too. These four are the ones with no
# bar-widget presence at all (overlay or pure-service kind), so this
# top-level plugins array is their only home. ruixen.wallpaper was
# missing from this list entirely until a direct review caught it
# ("Explicitly enable ruixen.wallpaper on a clean install") -- it only
# ever worked on this dev machine because it had been enabled by hand
# while it was being built, never actually reachable on a real clean
# install.
ruixen_plugin_ids='["ruixen.frame-widget", "ruixen.notch", "ruixen.settings", "ruixen.wallpaper"]'
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
  (if ($existing.bar.id // "") == "ruixen.bar" then $existing.bar else $ruixenBar end) as $mergedBar

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
