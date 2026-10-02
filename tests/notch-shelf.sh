#!/usr/bin/env bash
# Static contract for the notch's Shelf tab (5th dashboard tab): a drop
# pocket of file references that agents can read/write over IPC. Behavior
# of the pure logic is covered by tests/js/ShelfModel.test.js; this pins
# the wiring (neither it nor omarchy plugin validate compiles QML, so a
# live `omarchy restart shell` + journal check is still required -- see
# AGENTS.md section 8).
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
notch="$repo_dir/bars/widgets/ruixen.notch"
overlay="$notch/Overlay.qml"
service="$notch/ShelfService.qml"
content="$notch/ShelfContent.qml"
model="$notch/ShelfModel.js"

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

check "Overlay instantiates the ShelfService" "$(grep -c 'ShelfService {' "$overlay")" "1"
check "Overlay instantiates ShelfContent on dashboard tab 4" \
  "$(grep -A3 'ShelfContent {' "$overlay" | grep -c 'visible: panel.dashboardTab === 4')" "1"
check "Overlay has a fifth tab button" "$(grep -c 'panel.dashboardTab = 4; panel.pinnedOpen = true' "$overlay")" "1"
check "Tab key cycles all five tabs" "$(grep -c 'dashboardTab + 1) % 5' "$overlay")" "1"
check "openDashboardTab knows the shelf tab" "$(grep -c '"kanban", "shelf"' "$overlay")" "1"
check "Overlay exposes toggleShelf" "$(grep -A2 'function toggleShelf' "$overlay" | grep -c 'panel.dashboardTab = 4')" "1"
check "Overlay exposes shelfAdd/shelfRemove/shelfClear/shelfList IPC" \
  "$(grep -c 'function shelfAdd(path: string)\|function shelfRemove(idOrPath: string)\|function shelfClear()\|function shelfList()' "$overlay")" "4"
check "shelfAdd tags IPC additions as agent-sourced" "$(grep -c 'addPaths(\[path\], "agent")' "$overlay")" "1"
check "The tab bar's spacing still fits the notch height" \
  "$(grep -B7 '^              spacing: 6$' "$overlay" | grep -c 'Layout.maximumWidth: 78')" "1"

check "ShelfService persists to shelf.json under ~/.local/state/ruixen" \
  "$(grep -c '/.local/state/ruixen/shelf.json' "$service")" "1"
check "ShelfService writes atomically" "$(grep -c 'atomicWrites: true' "$service")" "1"
check "ShelfService stat runs async, one worker, merged by path" \
  "$(grep -c 'statDirty' "$service")$(grep -c 'onRunningChanged' "$service")" "41"
check "ShelfService never blocks the UI thread on stat (Process, not sync)" \
  "$(grep -c 'statProc.exec' "$service")" "1"

check "ShelfContent drops via DropArea" "$(grep -c 'DropArea {' "$content")" "1"
check "ShelfContent drags out with Drag.Automatic" "$(grep -c 'Drag.dragType: Drag.Automatic' "$content")" "1"
check "ShelfContent offers uri-list and plain text on drag out" \
  "$(grep -c '"text/uri-list"' "$content")$(grep -c '"text/plain"' "$content")" "11"
check "ShelfContent ignores drags that started from its own rows" "$(grep -c 'if (drop.source) return' "$content")" "1"
check "ShelfContent only accepts local files from a drop" "$(grep -c 'ShelfModel.fileUrlToPath' "$content")" "1"
check "ShelfContent shows an agent badge" "$(grep -c 'row.entry.source === "agent"' "$content")" "1"

check "Shelf holds references only: no cp/mv/rm in the QML" \
  "$(grep -E '"(cp|mv|rm)"' "$service" "$content" | wc -l | tr -d ' ')" "0"
check "Shelf model has no Qt/Quickshell globals" \
  "$(grep -cE '\b(Quickshell|Qt\.|Process)\b' "$model")" "0"

check "run-all includes the shelf contract" "$(grep -c 'notch-shelf\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
