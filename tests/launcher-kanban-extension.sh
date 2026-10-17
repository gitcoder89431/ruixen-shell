#!/usr/bin/env bash
# Static contract for the Kanban Board launcher extension -- this
# extension never had a dedicated test file of its own (unlike
# Clipboard/Cliamp/Theme Browser, each pinned in their own
# launcher-*-extension.sh), so this covers both its core wiring and the
# Column/Priority filter chips added as a direct follow-up ("wanna add
# the chips in so we can filter by To do Done etc... Bjaeneo Themes" --
# same cycling-pill shape ThemeBrowserContent.qml's own Collection/Style
# chips already established, deliberately with no separate sort chip,
# since cardsInColumn()'s own order/priority/age ordering already is
# the sort -- a second manual one would just compete with it).
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
launcher_qml="$repo_dir/ruixen.launcher/Launcher.qml"
content_qml="$repo_dir/ruixen.launcher/extensions/kanban/KanbanBoardContent.qml"
panel_qml="$repo_dir/ruixen.launcher/extensions/kanban/KanbanBoardDetailsPanel.qml"

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

# --- core actions-menu wiring, same trio every other 2-panel extension uses ---

check "KanbanBoardContent reuses the same focusRightPanel/blurToLeftPanel/rightFocused shape Clipboard/Cliamp/Theme Browser already use" \
  "$(( $(grep -c 'function focusRightPanel' "$content_qml") + $(grep -c 'function blurToLeftPanel' "$content_qml") + $(grep -c 'readonly property bool rightFocused: root.actionsMenuOpen' "$content_qml") + $(grep -c 'ResultActionsMenu {' "$content_qml") ))" "4"
check "Launcher passes glass props to Kanban's own actions menu" \
  "$(grep -A30 'KanbanBoardContent {' "$launcher_qml" | grep -cE 'glassTint: root.glassTint|glassBorder: root.glassBorder')" "2"

# --- rename: the stale-text + dead-Tab bug fixed after live use -------------

check "Rename field re-seeds its own text imperatively on every renaming:true transition, not just a declarative binding that breaks after the first edit" \
  "$(grep -c 'onRenamingChanged: if (root.renaming) renameInput.text = root.renameText' "$panel_qml")" "1"
check "commitRename and cancelRename both hand real Qt focus back out, or Tab dies after every rename" \
  "$(( $(grep -c 'signal returnFocusRequested()' "$content_qml") + $(grep -A3 'function commitRename' "$content_qml" | grep -c 'root.returnFocusRequested()') + $(grep -A2 'function cancelRename' "$content_qml" | grep -c 'root.returnFocusRequested()') ))" "3"
check "Launcher wires Kanban's returnFocusRequested the same way Settings' own uninstallConfirmField already does" \
  "$(grep -A40 'KanbanBoardContent {' "$launcher_qml" | grep -c 'onReturnFocusRequested: searchHeader.focusInput()')" "1"

# --- Column/Priority filter chips -------------------------------------------

check "Column filter cycles through All + every real column id, resettable by right-click" \
  "$(( $(grep -c 'property string columnFilter: ""' "$content_qml") + $(grep -c 'function cycleColumnFilter' "$content_qml") + $(grep -c 'function resetColumnFilter() { root.columnFilter = "" }' "$content_qml") + $(grep -c 'var ids = \[""\].concat(KanbanModel.COLUMN_IDS)' "$content_qml") ))" "4"
check "Priority filter cycles through All + every real priority, resettable by right-click" \
  "$(( $(grep -c 'property string priorityFilter: ""' "$content_qml") + $(grep -c 'function cyclePriorityFilter' "$content_qml") + $(grep -c 'function resetPriorityFilter() { root.priorityFilter = "" }' "$content_qml") + $(grep -c 'var ids = \[""\].concat(KanbanModel.PRIORITIES)' "$content_qml") ))" "4"
check "Both chips right-click to reset, left-click to cycle, same dual-button MouseArea shape Theme Browser's own chips use" \
  "$(grep -c 'if (mouse.button === Qt.RightButton) root.reset' "$content_qml")" "2"

check "allRows skips any column the Column filter has narrowed out, and filters each column's own cards by Priority" \
  "$(( $(grep -c 'if (root.columnFilter !== "" && columnId !== root.columnFilter) continue' "$content_qml") + $(grep -c 'if (root.priorityFilter !== "") cards = cards.filter' "$content_qml") ))" "2"

check "filterChipsRow actually has height now (chips filled in, not the old height:0 placeholder)" \
  "$(grep -A4 'id: filterChipsRow' "$content_qml" | grep -c 'height: 32')" "1"
check "Column and Priority chips are both really in the row (one Rectangle each, same 24px pill ThemeBrowserContent.qml's own chips use)" \
  "$(( $(grep -c 'id: columnChip$' "$content_qml") + $(grep -c 'id: priorityChip$' "$content_qml") ))" "2"

# --- row icon: priority dot, swapped for a checkmark on Done ---------------

check "List rows show a solid dot tinted by priority, same red/yellow/muted the notch's own priority dot uses" \
  "$(( $(grep -c '"medium": "#e8c34a"' "$content_qml") + $(grep -c 'icon: columnId === "done" ? "" : ""' "$content_qml") ))" "2"
check "Done-column rows swap the priority dot for a checkmark in the accent color, mirroring the notch panel's own dot-becomes-check behavior" \
  "$(grep -c 'iconColor: columnId === "done" ? root.accent : root.priorityColor\[card.priority\]' "$content_qml")" "1"

# --- same dot also sits in front of the title in the right-hand panel ------

check "The right-hand panel's own title row shows the same priority dot/checkmark, not just the left list -- direct follow-up ('the red dot for priority so its easy to see quickly')" \
  "$(( $(grep -c 'id: titleDot' "$panel_qml") + $(grep -c 'text: root.card && root.card.column === "done" ? "' "$panel_qml") + $(grep -c 'color: !root.card ? "transparent" : (root.card.column === "done" ? root.accent : root.dotColor\[root.card.priority\])' "$panel_qml") ))" "3"
check "Panel's own title-dot color map is separate from priorityColor (that one's scoped to the Priority metadata row's plain text, deliberately not yellow for medium)" \
  "$(grep -c '"medium": "#e8c34a"' "$panel_qml")" "1"

# --- Description: expanded block under the title, editable via Tab --------

check "Description is no longer in the generic metadata zebra list -- it gets its own expanded block" \
  "$(grep -c '{ label: "Description"' "$panel_qml")" "0"
check "The description block is word-wrapped, not elided to one line like the notch's own compact card" \
  "$(grep -c 'wrapMode: Text.WordWrap' "$panel_qml")" "1"
check "Description sits in its own dark card, same eqCard treatment Cliamp Radio's own panel uses for its Equalizer group" \
  "$(( $(grep -c 'height: descriptionColumn.height + 24' "$panel_qml") + $(grep -c 'color: Qt.rgba(0, 0, 0, 0.22)' "$panel_qml") ))" "2"
check "Description edit field is capped at KanbanModel's own real DESCRIPTION_LIMIT, not a separate arbitrary UI number -- enforced by hand in onTextChanged since TextInput.maxLength doesn't resolve in this Quickshell QML runtime (confirmed live: assigning it broke the whole component's load)" \
  "$(grep -c 'if (text.length > KanbanModel.DESCRIPTION_LIMIT)' "$panel_qml")" "1"
check "Description field re-seeds its own text imperatively too, same fix renameInput already needed" \
  "$(grep -c 'onEditingDescriptionChanged: if (editingDescription) descriptionInput.text = descriptionText' "$panel_qml")" "1"
check "Add/Edit Description is in the Tab menu, labeled by whether a description already exists" \
  "$(grep -c 'id: "description", label: root.selectedCard.description !== "" ? "Edit Description" : "Add Description"' "$content_qml")" "1"
check 'commitDescription calls through even on an empty string -- unlike commitRename, "" is the documented way to clear a description, not a cancel' \
  "$(( $(grep -A5 'function commitDescription' "$content_qml" | grep -c 'if (!root.selectedCard) return') + $(grep -A5 'function commitDescription' "$content_qml" | grep -c 'if (!root.selectedCard || .* === "") return') ))" "1"
check "editingDescription joins actionsMenuOpen/renaming in rightFocused, so Escape/Tab both still work while it's open" \
  "$(grep -c 'root.actionsMenuOpen || root.renaming || root.editingDescription' "$content_qml")" "1"
check "blurToLeftPanel cancels an open description edit on Escape, same as renaming" \
  "$(grep -A4 'function blurToLeftPanel' "$content_qml" | grep -c 'root.cancelDescription()')" "1"
check "Selecting a different card resets editingDescription, same safety net renaming already has" \
  "$(grep -A6 'onSelectedIndexChanged:' "$content_qml" | grep -c 'root.editingDescription = false')" "1"

# --- mouse-click QA fix: hover must not fight the open actions menu --------

check "Row hover does not reselect (and so can't close the actions menu out from under a click) while rightFocused -- the actual bug: moving the mouse from wherever it was toward the menu crosses other rows first" \
  "$(grep -c 'onRowHovered: (idx) => { if (root.hoverArmed && !root.rightFocused) root.selectedIndex = idx }' "$content_qml")" "1"
check "Actions menu Y-clamp accounts for filterChipsRow's real height, same shape ClipboardContent.qml's own positioning already uses for its own chip row" \
  "$(grep -c 'root.actionsMenuY = Math.max(filterChipsRow.height + 8,' "$content_qml")" "1"

# --- search-box add: !h/!m/!l priority + "--" description aliases ---------
# Direct follow-up once plain add-via-Enter shipped ("whats a way to set
# priority or description" without a second input row -- "i dont like
# adding rows cause it makes it jumpy").

check "parseCardInput splits off everything after \"--\" as the description" \
  "$(grep -c 'description = text.slice(dashIndex + 2).trim()' "$content_qml")" "1"
check "parseCardInput reads priority from the trailing !h/!m/!l word only, defaulting medium" \
  "$(grep -c 'var tagWords = { "!h": "high", "!m": "medium", "!l": "low" }' "$content_qml")" "1"
check "createCardFromSearch routes the typed text through parseCardInput instead of using the raw string" \
  "$(grep -A4 'function createCardFromSearch' "$content_qml" | grep -c 'root.parseCardInput(root.searchText)')" "1"
check "createCardFromSearch passes the parsed priority through to kanbanAddCard, not a hardcoded \"medium\"" \
  "$(grep -c 'kanbanAddCard", parsed.title, "todo", parsed.priority' "$content_qml")" "1"
check "a parsed description is stashed for addProc's own follow-up call, not dropped" \
  "$(grep -c 'property string pendingDescription: ""' "$content_qml")" "1"
check "addProc captures the new card id from its own stdout and chains kanbanSetDescription when a description was parsed" \
  "$(grep -A7 'id: addProc$' "$content_qml" | grep -c 'kanbanSetDescription", cardId, root.pendingDescription')" "1"
check "the add hint previews the parsed title/priority/description instead of a bare echo of the typed text" \
  "$(grep -c 'root.parsedSearchInput.title !== ""' "$content_qml")" "1"
check "the empty-board hint documents the alias syntax instead of leaving it undiscoverable" \
  "$(grep -c 'end with !h/!m/!l for priority, -- for a description' "$content_qml")" "1"
check "no leftover \"No match\" framing -- the add hint reads as an action, not an error" \
  "$(grep -c 'No match' "$content_qml")" "0"

# --- deliberately no separate sort chip -------------------------------------

check "No separate sort chip/sortKey -- cardsInColumn()'s own order/priority/age ordering already is the sort" \
  "$(( $(grep -c 'sortKey' "$content_qml") + $(grep -c 'sortDirection' "$content_qml") ))" "0"

check "run-all includes the Kanban Board extension contract" \
  "$(grep -c 'launcher-kanban-extension\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
