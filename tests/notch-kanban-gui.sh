#!/usr/bin/env bash
# Guards the notch Kanban's in-panel GUI (add / edit / delete /
# progress) -- direct request: "right now its not GUI friendly,
# meaning i can't manage tasks from there. i wanna be able to add,
# edit, delete check progress on the notch". This REVERSED the board's
# original "CLI-only for any text entry" rule (see KanbanContent.qml's
# own header), so every non-negotiable property of the new GUI is
# pinned here:
#   - the panel calls the SAME KanbanService functions the
#     kanban* IPC functions wrap (one API, two surfaces, never a
#     second implementation of a mutation);
#   - Esc inside an editor is consumed LOCALLY (an unhandled Escape
#     bubbles to notchOuter and closes the whole panel mid-edit);
#   - a blank title can never create a card;
#   - delete needs TWO clicks (armed state + 3s disarm timer) -- the
#     armed red button IS the confirmation, there is no dialog;
#   - the whole-row click still cannot fire while a card's editor is
#     open (a stray click on editor padding must not advance it).
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
content_qml="$repo_dir/bars/widgets/ruixen.notch/KanbanContent.qml"
run_all="$repo_dir/tests/run-all.sh"

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

# --- Add path ----------------------------------------------------------
check "column header + button opens the add editor for its own column" \
  "$(grep -m1 'onClicked: root.openAdd(columnRoot.columnId)' "$content_qml")" \
  '          onClicked: root.openAdd(columnRoot.columnId)'

check "add editor commits through KanbanService.addCard with the column + priority" \
  "$(grep -m1 'root.kanbanService.addCard(addInput.text, columnRoot.columnId, root.addPriority)' "$content_qml")" \
  '                root.kanbanService.addCard(addInput.text, columnRoot.columnId, root.addPriority)'

check "blank input can never create a card" \
  "$(grep -m1 'if (addInput.text.trim() === "" || !root.kanbanService) return' "$content_qml")" \
  '                if (addInput.text.trim() === "" || !root.kanbanService) return'

# --- Edit path ----------------------------------------------------------
check "edit editor saves through KanbanService.renameCard" \
  "$(grep -m1 'root.kanbanService.renameCard(cardRoot.modelData.id, editTitleInput.text)' "$content_qml")" \
  '                    root.kanbanService.renameCard(cardRoot.modelData.id, editTitleInput.text)'

check "edit editor covers description" \
  "$(grep -m1 'root.kanbanService.setDescription(cardRoot.modelData.id, editDescInput.text)' "$content_qml")" \
  '                    root.kanbanService.setDescription(cardRoot.modelData.id, editDescInput.text)'

check "edit editor covers priority" \
  "$(grep -m1 'root.kanbanService.setPriority(cardRoot.modelData.id, root.editPriority)' "$content_qml")" \
  '                    root.kanbanService.setPriority(cardRoot.modelData.id, root.editPriority)'

check "edit editor covers due date via the shared parse guard" \
  "$(grep -m1 'var dueMs = root.parsedDueMs(editDueInput.text)' "$content_qml")" \
  '                    var dueMs = root.parsedDueMs(editDueInput.text)'

check "unparseable due date no-ops instead of wiping the deadline" \
  "$(grep -m1 'if (!isNaN(dueMs)) root.kanbanService.setDueDate(cardRoot.modelData.id, dueMs)' "$content_qml")" \
  '                    if (!isNaN(dueMs)) root.kanbanService.setDueDate(cardRoot.modelData.id, dueMs)'

# --- Delete path --------------------------------------------------------
check "delete is two-step: first click arms" \
  "$(grep -m1 'root.deleteArmedId = cardRoot.modelData.id$' "$content_qml")" \
  '                          root.deleteArmedId = cardRoot.modelData.id'

check "second click on the armed button removes" \
  "$(grep -c '^                          root.kanbanService.removeCard(cardRoot.modelData.id)$' "$content_qml")" "1"

check "armed delete auto-disarms on a timer" \
  "$(grep -m1 'interval: 3000' "$content_qml")" \
  '    interval: 3000'

# --- Editor hygiene -----------------------------------------------------
check "Esc is consumed locally in every editor (never closes the panel)" \
  "$(grep -c 'event.accepted = true' "$content_qml")" "4"

check "whole-row click is inert while the card's editor is open" \
  "$(grep -m1 'if (cardRoot.isEditing) return' "$content_qml")" \
  '                    if (cardRoot.isEditing) return'

check "card text renders as PlainText (title, description, label)" \
  "$(grep -c 'textFormat: Text.PlainText' "$content_qml")" "3"

# --- Progress row -------------------------------------------------------
check "progress row shows done/total" \
  "$(grep -m1 'text: root.doneCards + "/" + root.totalCards' "$content_qml")" \
  '        text: root.doneCards + "/" + root.totalCards'

check "progress fill is driven by the done/total counts" \
  "$(grep -m1 'Math.min(root.doneCards / root.totalCards, 1)' "$content_qml")" \
  '          width: parent.width * (root.totalCards > 0 ? Math.min(root.doneCards / root.totalCards, 1) : 0)'

# --- Registration -------------------------------------------------------
check "tests/run-all.sh runs this suite" \
  "$(grep -m1 'notch-kanban-gui.sh' "$run_all")" \
  '  "$script_dir/notch-kanban-gui.sh"'

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
