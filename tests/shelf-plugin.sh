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
  "$(grep -c 'function add(path: string)\|function addMany(pathsJson: string, source: string)\|function remove(idOrPath: string)\|function clear(): void\|function list(): string' "$shelf")" "5"
check "IPC: add tags agent-sourced items" "$(grep -c 'addPaths(\[path\], "agent")' "$shelf")" "1"
check "IPC: addMany takes the source explicitly" "$(grep -c 'service.addPaths(paths, source)' "$shelf")" "1"
check "Host lifecycle: open(payloadJson)/close()/toggle(payloadJson)" \
  "$(grep -c '^  function open(payloadJson)\|^  function close()\|^  function toggle(payloadJson)' "$shelf")" "3"
check "A user-initiated close also tells the host (shell.hide)" "$(grep -c 'root.shell.hide(' "$shelf")" "1"

# --- the window: the whole point of leaving the notch -----------------
check "Window: top-anchored only (no fullscreen surface)" \
  "$(grep -c 'anchors { top: true }' "$shelf")" "1"
check "Window: never anchored left/right/bottom" \
  "$(grep -cE 'anchors \{[^}]*(left|right|bottom): true' "$shelf")" "0"
check "Window: sized to the shelf itself" \
  "$(grep -c 'implicitWidth: root.shelfWidth' "$shelf")$(grep -c 'implicitHeight: root.shelfHeight' "$shelf")" "11"
check "Window: no input mask / click-away catcher" \
  "$(grep -cE '^\s*mask:|Region \{' "$shelf")" "0"
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

# --- content ----------------------------------------------------------
check "Content: drops via DropArea" "$(grep -c 'DropArea {' "$content")" "1"
check "Content: drags out with Drag.Automatic" "$(grep -c 'Drag.dragType: Drag.Automatic' "$content")" "1"
check "Content: offers uri-list and plain text on drag out" \
  "$(grep -c '"text/uri-list"' "$content")$(grep -c '"text/plain"' "$content")" "11"
check "Content: drag MouseArea stops the ListView stealing the gesture" \
  "$(grep -c 'preventStealing: true' "$content")" "1"
check "Content: thumbnails use the tested URI encoder, not string concat" \
  "$(grep -c 'ShelfModel.uriFor(row.entry.path)' "$content")$(grep -c '"file://" + ' "$content")" "10"
check "Content: ignores drags that started from its own rows" "$(grep -c 'if (drop.source) return' "$content")" "1"
check "Content: only local files from a drop" "$(grep -c 'ShelfModel.fileUrlToPath' "$content")" "1"
check "Content: drag out copies; nothing removes an item automatically" \
  "$(grep -c 'onDragFinished' "$content")$(grep -c 'removeItem' "$content")" "11"
check "Shelf holds references only: no cp/mv/rm in the QML" \
  "$(grep -E '"(cp|mv|rm)"' "$service" "$content" | wc -l | tr -d ' ')" "0"

# --- the notch: only the quick-drop relay, no Shelf UI ----------------
check "Notch: no Shelf service/content/tab left behind" \
  "$(grep -cE 'ShelfService|ShelfContent|dashboardTab === 4|% 5|toggleShelf|shelfAdd|shelfList' "$notch")" "0"
check "Notch: still four dashboard tabs" "$(grep -c 'dashboardTab + 1) % 4' "$notch")" "1"
check "Notch: quick-drop DropArea on the collapsed footprint" \
  "$(grep -c 'id: shelfQuickDrop' "$notch")" "1"
check "Notch: quick-drop is inert while expanded" \
  "$(grep -A8 'id: shelfQuickDrop' "$notch" | grep -c 'enabled: !panel.expanded')" "1"
check "Notch: quick-drop only accepts local file URLs" "$(grep -c 'indexOf("file://") === 0' "$notch")" "1"
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
