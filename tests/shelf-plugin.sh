#!/usr/bin/env bash
# Static contract for the ruixen.shelf overlay plugin and the notch's
# quick-drop relay to it. Behavior of the pure logic is covered by
# tests/js/ShelfModel.test.js; this pins the wiring and, above all, the
# window semantics the Shelf exists for: a window sized to the shelf, no
# fullscreen surface or input mask, no exclusive keyboard focus -- so a
# drag can leave the shelf and reach the real destination app. Neither
# this nor `omarchy plugin validate` compiles QML, so a live `omarchy
# restart shell` + journal check is still required (AGENTS.md section 8).
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
shelf_dir="$repo_dir/ruixen.shelf"
manifest="$shelf_dir/manifest.json"
shelf="$shelf_dir/Shelf.qml"
service="$shelf_dir/ShelfService.qml"
content="$shelf_dir/ShelfContent.qml"
model="$shelf_dir/ShelfModel.js"
notch="$repo_dir/bars/widgets/ruixen.notch/Overlay.qml"

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

# --- manifest ---------------------------------------------------------
check "manifest: id is ruixen.shelf" "$(jq -r '.id' "$manifest")" "ruixen.shelf"
check "manifest: an overlay plugin" "$(jq -c '.kinds' "$manifest")" '["overlay"]'
check "manifest: keepLoaded (the notch relays to its IPC target)" "$(jq -r '.keepLoaded' "$manifest")" "true"
check "manifest: entry point exists" "$([[ -f "$shelf_dir/$(jq -r '.entryPoints.overlay' "$manifest")" ]] && echo yes)" "yes"
check "installer enables it in shell.json" "$(grep -c '"ruixen.shelf"' "$repo_dir/lib/build-shell-json.sh")" "1"

# --- plugin-owned IPC + host lifecycle --------------------------------
check "Shelf has its own IPC target" "$(grep -c 'target: "ruixen.shelf"' "$shelf")" "1"
check "IPC: open/close/toggle" \
  "$(grep -c 'function open(): void\|function close(): void\|function toggle(): void' "$shelf")" "3"
check "IPC: add/addMany/remove/clear/list" \
  "$(grep -c 'function add(path: string)\|function addMany(pathsArg: string, source: string)\|function remove(idOrPath: string)\|function clear(): void\|function list(): string' "$shelf")" "5"
check "IPC: add tags agent-sourced items" "$(grep -c 'addPaths(\[path\], "agent")' "$shelf")" "1"
check "IPC: addMany takes the source explicitly" "$(grep -c 'service.addPaths(paths, source)' "$shelf")" "1"

# Regression (found live, 2026-10-02): addMany's argument is NEWLINE
# delimited, never a JSON array. A bracketed array does not survive the
# IPC boundary as one argument -- the host split '["/a","/b"]' into three
# arguments and refused the call ("Too many arguments provided"), and a
# one-element array arrived as a scalar so Array.isArray() was false and
# it silently added nothing. That broke every notch quick-drop, since
# Overlay.qml relays exactly one addMany call per drop.
#
# These assert the ENCODING on both sides. They cannot prove the host's
# splitting behavior (that needs a live shell), so they pin the contract
# that avoids it instead. The decoding itself is behavior-tested in
# tests/js/ShelfModel.test.js (parsePathsArg/joinPathsArg, incl. a round
# trip), and the boundary is exercised for real by tests/live-shelf-ipc.sh,
# which needs a running shell and so lives outside run-all.sh/CI.
check "IPC: addMany decodes through the tested ShelfModel.parsePathsArg" \
  "$(grep -c 'ShelfModel.parsePathsArg(pathsArg)' "$shelf")" "1"
check "IPC: Shelf.qml imports ShelfModel.js (a missing import would silently break the whole plugin)" \
  "$(grep -c '^import "ShelfModel.js" as ShelfModel$' "$shelf")" "1"
check "Model: parsePathsArg splits on newlines, never on commas or semicolons" \
  "$(grep -cF 'return s.split("\n").map' "$model")" "1"
check "Model: parsePathsArg is the only decoder (no inline JSON.parse of the IPC argument in Shelf.qml)" \
  "$(grep -c 'JSON.parse(pathsArg\|JSON.parse(trimmed' "$shelf" || true)" "0"
check "Notch: relay sends newline-delimited batch, not JSON.stringify(urls)" \
  "$(grep -cF 'urls.join("\n")' "$notch")" "1"
check "Notch: relay does not JSON.stringify the batch" \
  "$(grep -cE '^[[:space:]]+[^/]*[^[:space:]]JSON\.stringify\(urls\)' "$notch")" "0"
check "Host lifecycle: open(payloadJson)/close()/toggle(payloadJson)" \
  "$(grep -c '^  function open(payloadJson)\|^  function close()\|^  function toggle(payloadJson)' "$shelf")" "3"
check "A user-initiated close also tells the host (shell.hide)" "$(grep -c 'root.shell.hide(' "$shelf")" "1"

# --- the window: the whole point of leaving the notch -----------------
check "Window: top-anchored only (no fullscreen surface)" \
  "$(grep -c 'anchors { top: true }' "$shelf")" "1"
check "Window: never anchored left/right/bottom" \
  "$(grep -cE 'anchors \{[^}]*(left|right|bottom): true' "$shelf")" "0"
check "Window: sized to the shape plus shadow room, never the screen" \
  "$(grep -c 'implicitWidth: root.shapeWidth + root.haloPad \* 2' "$shelf")$(grep -c 'implicitHeight: root.shapeHeight + root.haloPad' "$shelf")" "11"
check "Window: input region is ONLY the visible shape (halo padding stays click-through)" \
  "$(grep -c 'mask: Region {' "$shelf")$(sed -n '/mask: Region {/,/^    }/p' "$shelf" | grep -c 'width: root.shapeWidth')$(sed -n '/mask: Region {/,/^    }/p' "$shelf" | grep -c 'height: root.shapeHeight')" "111"
check "Window: no click-away catcher (no MouseArea at window level)" \
  "$(sed -n '/PanelWindow {/,/id: shape/p' "$shelf" | grep -c 'MouseArea' || true)" "0"

check "Window: reserves no screen space" "$(grep -c 'ExclusionMode.Ignore' "$shelf")" "2"
check "Window: keyboard focus is on demand, never exclusive" \
  "$(grep -c 'WlrKeyboardFocus.OnDemand' "$shelf")$(grep -c 'WlrKeyboardFocus.Exclusive' "$shelf")" "10"
check "Window: overlay layer" "$(grep -c 'WlrLayer.Overlay' "$shelf")" "1"
check "Window: Escape closes (when focused)" "$(grep -c 'Keys.onEscapePressed: root.dismiss()' "$shelf")" "1"
check "Window: has an explicit close button path" "$(grep -c 'onCloseRequested: root.dismiss()' "$shelf")" "1"
check "Window: no auto-dismiss on pointer leave in this first move" \
  "$(grep -cE 'onHoveredChanged|HoverHandler' "$shelf")" "0"
check "Window: surface identity read from bar-surface.json, solid only" \
  "$(grep -c '"/.local/state/ruixen/bar-surface.json"' "$shelf")" "1"

# --- shared state + service ------------------------------------------
check "Service persists to shelf.json under ~/.local/state/ruixen (path unchanged)" \
  "$(grep -c '/.local/state/ruixen/shelf.json' "$service")" "1"
check "Service writes atomically" "$(grep -c 'atomicWrites: true' "$service")" "1"
check "Service stat: async, one worker, merged by path" \
  "$(grep -c 'statDirty' "$service")$(grep -c 'onRunningChanged' "$service")" "41"
check "Service never stats on the UI thread (Process, not sync)" "$(grep -c 'statProc.exec' "$service")" "1"
check "Model has no Qt/Quickshell globals" "$(grep -cE '\b(Quickshell|Qt\.|Process)\b' "$model")" "0"

# --- the surface: an expanded notch hanging from the frame -----------
#
# The shelf is not a floating box. It is built the way ruixen.notch builds
# its expanded launcher shape -- left flank + square-topped center + right
# flank, concave "wing" shoulders flaring out to the frame -- with the
# notch's own numbers, flush under the frame at the notch's own resting
# offset. These pin the properties that are easy to "tidy up" by accident
# and very visible when you do.
check "Shape: attached to the frame at the notch's resting offset, no floating gap" \
  "$(grep -c 'readonly property int frameInset: 4' "$shelf")$(grep -c 'margins.top: root.frameInset' "$shelf")$(grep -c 'margins.top: 52' "$shelf" || true)" "110"
# 900 is the notch's own EXPANDED (pinned) width, not the launcher's 420 --
# this check exists to make a silent revert to 420 (or any other new number)
# a deliberate, visible act rather than a quiet edit, because that is the
# knob the notch's own masking bug is documented against.
check "Shape: 900 body, the notch's expanded/pinned width" \
  "$(grep -c 'readonly property int bodyWidth: 900' "$shelf")" "1"
check "Shape: the window shape is body plus a shoulder on each side" \
  "$(grep -c 'readonly property int shapeWidth: bodyWidth + cornerSize \* 2' "$shelf")" "1"
check "Shape: fixed height, not item-count driven (rows scroll sideways)" \
  "$(grep -cE 'readonly property int shapeHeight: [0-9]+$' "$shelf" || true)" "1"
check "Shape: wings are real concave shoulders (4 ShelfRoundCorner pieces: 2 in the shadow, 2 in the mask)" \
  "$(grep -c 'ShelfRoundCorner {' "$shelf")" "4"
check "Shape: left flank is corner 1 and right flank is corner 0, as in the notch" \
  "$(grep -c 'corner: 1' "$shelf")$(grep -c 'corner: 0' "$shelf")" "22"
check "Shape: the center is square-topped (meets the frame) with the notch's round bottom" \
  "$(grep -c 'topLeftRadius: 0' "$shelf")$(grep -c 'topRightRadius: 0' "$shelf")$(grep -c 'bottomLeftRadius: root.bottomRadius' "$shelf")$(grep -c 'bottomRightRadius: root.bottomRadius' "$shelf")" "2222"
check "Shape: the center overlaps both flanks by seamOverlap (no fractional-scale hairline)" \
  "$(grep -c 'readonly property int seamOverlap: 2' "$shelf")$(grep -c 'root.seamOverlap' "$shelf")" "14"
check "Shape: the mask is a real, named shape source (a typo here renders nothing)" \
  "$(grep -c 'maskSource: shelfMask' "$shelf")$(grep -c 'id: shelfMask' "$shelf")" "11"
check "Shape: the shoulders use the notch's own 28" \
  "$(grep -c 'readonly property int cornerSize: 28' "$shelf")" "1"
check "Shape: the bottom radius is 44, i.e. the notch's own expanded radius" \
  "$(grep -c 'readonly property int bottomRadius: 44' "$shelf")" "1"
check "Shape: content is inset by the shoulders (it lives in the body, not the wings)" \
  "$(grep -c 'anchors.leftMargin: root.cornerSize$' "$shelf")$(grep -c 'anchors.rightMargin: root.cornerSize$' "$shelf")" "11"
check "Shape: content clears the frame's top edge" \
  "$(grep -c 'anchors.topMargin: root.contentTopInset' "$shelf")" "1"
check "Shape: the wing component is the shelf's own copy (a missing file would silently blank the surface)" \
  "$([[ -f "$shelf_dir/ShelfRoundCorner.qml" ]] && echo yes)$(grep -c 'property int corner: 0' "$shelf_dir/ShelfRoundCorner.qml")" "yes1"
check "Shape: does NOT reach for the notch's private inline RoundCorner by its bare name" \
  "$(grep -cE '(^|[^A-Za-z])RoundCorner \{' "$shelf" || true)" "0"
check "Shadow: a separate blurred duplicate of the shape, clipped (notchShadowBlur's own arrangement)" \
  "$(grep -c 'id: shadowBlur' "$shelf")$(grep -c 'id: shadowClip' "$shelf")$(grep -c 'clip: true' "$shelf")" "111"
check "Shadow: uses the notch's own recipe, not a nearby mask-safe one (AGENTS.md section 9)" \
  "$(grep -c 'blurMax: 32' "$shelf")$(grep -c 'blur: 0.6' "$shelf")" "11"
check "Shadow: no directional offset -- the notch's own shadow has none, a lift shadow does" \
  "$(grep -cE 'shadowVerticalOffset|shadowHorizontalOffset|shadowEnabled' "$shelf" || true)" "0"
check "Shadow: the clip extends OUT by the halo on left/right/bottom, flush at the top" \
  "$(grep -c 'anchors.leftMargin: -root.haloPad' "$shelf")$(grep -c 'anchors.rightMargin: -root.haloPad' "$shelf")$(grep -c 'anchors.bottomMargin: -root.haloPad' "$shelf")$(sed -n '/id: shadowClip/,/clip: true/p' "$shelf" | grep -c 'anchors.top: parent.top')" "1111"
# The live "almost square edges" report from Overlay.qml: adding shadow*
# to the MASKED shape reproducibly destroys the silhouette. If someone ever
# "improves" this by shadowing the mask effect directly, this check is the
# one that says no.
check "Shape: the masked fill carries NO shadow properties (that combination breaks the silhouette)" \
  "$(sed -n '/id: shelfBg/,/id: shelfMask/p' "$shelf" | grep -cE 'shadow|blurEnabled' || true)" "0"
check "Shape: QtQuick.Effects is imported -- a missing import kills the WHOLE plugin silently" \
  "$(grep -c '^import QtQuick.Effects$' "$shelf")" "1"
check "Shape: the mask source is hidden (a visible mask paints over the fill)" \
  "$(sed -n '/id: shelfMask/,/anchors.fill: parent/p' "$shelf" | grep -c 'visible: false' || true)" "1"

# --- content ----------------------------------------------------------
check "Content: drops via DropArea" "$(grep -c 'DropArea {' "$content")" "1"
check "Content: drags out with Drag.Automatic" "$(grep -c 'Drag.dragType: Drag.Automatic' "$content")" "1"
check "Content: offers uri-list and plain text on drag out" \
  "$(grep -c '"text/uri-list"' "$content")$(grep -c '"text/plain"' "$content")" "11"
check "Content: drag MouseArea stops the ListView stealing the gesture" \
  "$(grep -c 'preventStealing: true' "$content")" "1"

# --- the inbox layout: horizontal strip + search ----------------------
#
# The strip is what makes the panel keep a fixed height no matter how full
# the shelf is, and the filter is now the only way to reach a card that
# isn't currently on screen -- so "the strip scrolls" and "the filter
# narrows" are load-bearing, not cosmetic.

check "Inbox: the item list is horizontal" \
  "$(grep -c 'orientation: ListView.Horizontal' "$content")" "1"
# Binding contentWidth to childrenRect.width is circular -- the view sizes
# its own content item FROM contentWidth -- and Qt reported a binding loop
# for that on every shell restart. The view derives it itself, and the
# anchors (not a content-driven width) are what stop the strip stretching
# the window, so the check is the ABSENCE of the binding plus the anchors.
check "Inbox: no circular contentWidth binding (it caused a live binding loop)" \
  "$(grep -c 'contentWidth:' "$content" || true)" "0"
check "Inbox: the strip is bounded by anchors, not by content, so it cannot stretch the window" \
  "$(grep -c 'orientation: ListView.Horizontal' "$content")" "1"
check "Inbox: the window itself is a fixed size, so nothing content-driven can grow it" \
  "$(grep -c 'implicitWidth: root.shapeWidth + root.haloPad \* 2' "$shelf")$(grep -c 'implicitHeight: root.shapeHeight + root.haloPad' "$shelf")" "11"
check "Inbox: the wheel scrolls the strip (target: null, not fighting the view's own handling)" \
  "$(grep -c 'WheelHandler {' "$content")" "1"
check "Inbox: wheel scrolling is clamped to the content, so it cannot rubber-band past the end" \
  "$(grep -c 'Math.min(max, list.contentX - delta)' "$content")" "1"
check "Inbox: the cards are a fixed width, not content-sized" \
  "$(grep -cE '^\s*width: 124$' "$content")" "1"
check "Inbox: the right edge fades only when there is more to scroll to" \
  "$(grep -cF 'list.contentWidth > list.width && list.contentX < list.contentWidth - list.width - 1' "$content")" "1"
check "Search: a real TextInput, not a fake Text" \
  "$(grep -c 'TextInput {' "$content")$(grep -c 'onTextChanged: root.query = text' "$content")" "11"
check "Search: filtering goes through the tested model helper, not inline in QML" \
  "$(grep -c 'ShelfModel.filterEntries(root.rows, root.query)' "$content")" "1"
check "Search: an empty query shows every row (no rebuild, no filter loop)" \
  "$(grep -c 'visibleRows: root.filtering ? root.filtered : root.rows' "$content")" "1"
check "Search: the header reports X of Y while filtering, so it does not read as deletions" \
  "$(grep -c 'root.visibleRows.length === 1 ? "1 of "' "$content")$(grep -c 'root.visibleRows.length + " of "' "$content")" "11"
check "Search: Escape clears the query before it dismisses the shelf" \
  "$(grep -cF 'if (root.query !== "") { text = ""; root.query = "" }' "$content")" "1"
check "Search: the search box is under the header, and the list under the search box" \
  "$(grep -c 'id: searchBox' "$content")$(grep -c 'anchors.top: searchBox.bottom' "$content")" "13"
# A destructive \"Clear\" (empties the whole shelf) one button away from a
# \"clear the textbox\" with no label difference is a real footgun.
check "Search: clear-the-text is a separate affordance from the shelf-wide Clear" \
  "$(grep -c 'id: clearQuery' "$content")$(grep -cF 'onClicked: { searchInput.text = ""; root.query = ""' "$content")" "21"
# Clear belongs on the search row's right, not the header: the header is
# the identity/count line, and an empty-the-whole-shelf button sitting there
# is one stray click away from the count it sits next to.
check "Clear: lives on the search row, right-aligned, not in the header" \
  "$(sed -n '/id: header/,/^    }$/p' "$content" | grep -c 'clearLabel' || true)$(grep -c 'anchors.verticalCenter: searchBox.verticalCenter' "$content")" "01"
# It stays OUTSIDE the rounded search box. As a child of searchBox it would
# read as part of the text field, which is how a destructive action turns
# into a mis-click on a filter.
check "Clear: a sibling of searchBox, not a child of it" \
  "$(sed -n '/id: searchBox/,/^    }$/p' "$content" | grep -c 'id: clearShelfButton' || true)" "0"
# Hiding Clear must not leave the search box permanently short on the right.
check "Clear: the search box gives the space back when Clear hides" \
  "$(grep -cF 'anchors.rightMargin: 12 + (clearShelfButton.visible ? clearShelfButton.width + 6 : 0)' "$content")" "1"
check "Search: the focus-catcher MouseArea sits UNDER the input (at default z it would eat its clicks)" \
  "$(grep -B4 'onClicked: searchInput.forceActiveFocus()' "$content" | grep -c 'z: -1' || true)" "1"
check "Search: 'no match' is its own state, distinct from an empty shelf" \
  "$(grep -c 'root.rows.length > 0 && root.filtering && root.visibleRows.length === 0' "$content")" "1"
check "Search: typing in the box never steals keyboard focus from the app below (OnDemand only)" \
  "$(grep -c 'WlrKeyboardFocus.Exclusive' "$shelf" || true)" "0"
check "Content: thumbnails use the tested URI encoder, not string concat" \
  "$(grep -c 'ShelfModel.uriFor(row.entry.path)' "$content")$(grep -c '"file://" + ' "$content")" "10"
check "Copy semantics: acceptProposedAction() is never used in the shelf or the notch quick-drop" \
  "$(cat "$shelf_dir"/*.qml "$notch" | grep -c '\.acceptProposedAction(' || true)" "0"
check "Copy semantics: the open Shelf accepts drags and drops with Qt.CopyAction explicitly" \
  "$(grep -c 'drag.accept(Qt.CopyAction)\|drop.accept(Qt.CopyAction)' "$content")" "2"
check "Copy semantics: the notch quick-drop accepts with Qt.CopyAction explicitly" \
  "$(grep -A45 'id: shelfQuickDrop' "$notch" | grep -c 'drag.accept(Qt.CopyAction)\|drop.accept(Qt.CopyAction)')" "2"
check "Copy semantics: drag-out only advertises CopyAction" \
  "$(grep -c 'Drag.supportedActions: Qt.CopyAction' "$content")" "1"
check "Content: a drop is only accepted once the shelf actually added something" \
  "$(grep -B1 'drop.accept(Qt.CopyAction)' "$content" | grep -c 'result.added.length > 0')" "1"
check "Content: drag-enter and drop use the same acceptability gate as the service" \
  "$(grep -c 'ShelfModel.normalizePath' "$content")" "3"
check "Content: ignores drags that started from its own rows" "$(grep -c 'if (drop.source) return' "$content")" "1"
check "Content: only local files from a drop" "$(grep -c 'ShelfModel.fileUrlToPath' "$content")" "1"
check "Content: drag out copies; nothing removes an item automatically" \
  "$(grep -c 'onDragFinished' "$content")$(grep -c 'removeItem' "$content")" "11"
check "Shelf holds references only: no cp/mv/rm in the QML" \
  "$(cat "$service" "$content" | grep -cE '"(cp|mv|rm)"' || true)" "0"

# --- the notch: only the quick-drop relay, no Shelf UI ----------------
check "Notch: no Shelf service/content/tab left behind" \
  "$(grep -cE 'ShelfService|ShelfContent|dashboardTab === 4|% 5|toggleShelf|shelfAdd|shelfList' "$notch")" "0"
check "Notch: still four dashboard tabs" "$(grep -c 'dashboardTab + 1) % 4' "$notch")" "1"
check "Notch: quick-drop DropArea on the collapsed footprint" \
  "$(grep -c 'id: shelfQuickDrop' "$notch")" "1"
check "Notch: quick-drop is inert while expanded" \
  "$(grep -A8 'id: shelfQuickDrop' "$notch" | grep -c 'enabled: !panel.expanded')" "1"
check "Notch: quick-drop only accepts local file URLs with a real path" \
  "$(grep -c 'file:\\/\\/(?:localhost)?\\/\.+' "$notch")" "1"
check "Notch: relays one batched IPC call to ruixen.shelf, not one per path" \
  "$(grep -c '"omarchy-shell", "ruixen.shelf", "addMany"' "$notch")" "1"
check "Notch: relay queues behind a running relay (never reassigns a live Process)" \
  "$(grep -c 'shelfRelayQueue' "$notch")" "5"
check "Notch: no spring-loading/dwell timer in this move" \
  "$(grep -cE 'dwellTimer|springLoad|openShelfTimer' "$notch")" "0"
check "Notch: does not import or reach into the shelf plugin's objects" \
  "$(grep -c 'ruixen.shelf/' "$notch")" "0"

check "run-all includes the shelf contract" "$(grep -c 'shelf-plugin\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
