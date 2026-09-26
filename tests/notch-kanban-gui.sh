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
overlay_qml="$repo_dir/bars/widgets/ruixen.notch/Overlay.qml"
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
  "$(grep -c 'onClicked: root.openAdd(columnRoot.columnId)' "$content_qml")" \
  "1"

check "column header + button uses green hover fill" \
  "$(grep -c 'color: addMouse.containsMouse ? root.successColor : Qt.rgba(1, 1, 1, 0.12)' "$content_qml")" \
  "1"

check "column header + glyph stays green when idle" \
  "$(grep -c 'color: addMouse.containsMouse ? "#000000" : root.successColor' "$content_qml")" \
  "2"

check "column header label and count share one compact pill" \
  "$(grep -F -c 'implicitWidth: headerLabelRow.implicitWidth + 18' "$content_qml")" \
  "1"

check "column header count is a nested rounded sub-pill" \
  "$(grep -F -c 'implicitWidth: Math.max(18, countText.implicitWidth + 10)' "$content_qml")" \
  "1"

check "column header count sub-pill uses a subtle accent tint" \
  "$(grep -F -c 'color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)' "$content_qml")" \
  "1"

check "column header count text uses accent color" \
  "$(grep -c 'color: root.accent' "$content_qml")" \
  "2"

check "column header add action is a wider pill" \
  "$(grep -F -c 'implicitWidth: addActionRow.implicitWidth + 16' "$content_qml")" \
  "1"

check "column header add action has an Add label" \
  "$(grep -c 'text: "Add"' "$content_qml")" \
  "1"

check "add editor commits through KanbanService.addCard with the column + priority" \
  "$(grep -m1 'var cardId = root.kanbanService.addCard(addInput.text, columnRoot.columnId, root.addPriority)' "$content_qml")" \
  '                var cardId = root.kanbanService.addCard(addInput.text, columnRoot.columnId, root.addPriority)'

check "add editor can set description on the newly-created card" \
  "$(grep -m1 'root.kanbanService.setDescription(cardId, addDescInput.text)' "$content_qml")" \
  '                  root.kanbanService.setDescription(cardId, addDescInput.text)'

check "priority chip cycles default medium to high, then low, then medium" \
  "$(grep -m1 'return priority === "medium" ? "high" : priority === "high" ? "low" : "medium"' "$content_qml")" \
  '    return priority === "medium" ? "high" : priority === "high" ? "low" : "medium"'

check "priority chip uses one reusable pill component" \
  "$(grep -c 'component KanbanPriorityPill : Rectangle' "$content_qml")" "1"

check "add and edit priority chips use the shared pill" \
  "$(grep -c 'KanbanPriorityPill {' "$content_qml")" "2"

check "add and edit priority chips bind to their local priority state" \
  "$(grep -E -c 'priority: root.addPriority|priority: root.editPriority' "$content_qml")" "2"

check "blank input can never create a card" \
  "$(grep -m1 'if (addInput.text.trim() === "" || !root.kanbanService) return' "$content_qml")" \
  '                if (addInput.text.trim() === "" || !root.kanbanService) return'

check "add editor has a description field matching edit mode" \
  "$(grep -c 'id: addDescInput' "$content_qml")" "1"

check "add description placeholder is action-oriented" \
  "$(grep -c 'text: "Add description..."' "$content_qml")" "1"

check "Kanban compact icon actions use one reusable button component" \
  "$(grep -c 'component KanbanActionButton : Rectangle' "$content_qml")" "1"

check "reusable action button inverts icon color on hover/armed" \
  "$(grep -c 'color: (actionButton.armed || actionButton.hovered) ? "#000000" : actionButton.accentColor' "$content_qml")" "1"

check "add editor confirm uses the reusable action button" \
  "$(grep -c 'id: addCommitButton' "$content_qml")" "1"

check "add editor confirm uses the theme blue confirm token" \
  "$(grep -c 'accentColor: root.confirmColor' "$content_qml")" "2"

check "add editor cancel uses the reusable red action button" \
  "$(grep -c 'id: addCancelButton' "$content_qml")" "1"

check "Kanban confirm token is supplied from the active theme blue swatch" \
  "$(grep -c 'confirmColor: root.cavaCoolColor' "$overlay_qml")" "1"

check "Kanban semantic colors are supplied from the active theme palette" \
  "$(grep -E -c 'successColor: root.kanbanSuccessColor|dangerColor: root.kanbanDangerColor|warningColor: root.kanbanWarningColor' "$overlay_qml")" "3"

check "Kanban card and editor surfaces are explicit theme-fed tokens" \
  "$(grep -E -c 'cardSurface: Qt.lighter\(root.notchColor, 1.18\)|editorSurface: Qt.darker\(root.notchColor, 1.08\)' "$overlay_qml")" "2"

check "Kanban task and editor rectangles use surface tokens, not raw black" \
  "$(grep -E -c 'color: root.cardSurface|color: root.editorSurface' "$content_qml")" "2"

# --- Edit path ----------------------------------------------------------
check "edit editor saves through KanbanService.renameCard" \
  "$(grep -m1 'root.kanbanService.renameCard(cardRoot.modelData.id, editTitleInput.text)' "$content_qml")" \
  '                    root.kanbanService.renameCard(cardRoot.modelData.id, editTitleInput.text)'

check "edit editor covers description" \
  "$(grep -m1 'root.kanbanService.setDescription(cardRoot.modelData.id, editDescInput.text)' "$content_qml")" \
  '                    root.kanbanService.setDescription(cardRoot.modelData.id, editDescInput.text)'

check "title and description inputs wrap instead of overflowing horizontally" \
  "$(grep -c 'wrapMode: TextInput.Wrap' "$content_qml")" "3"

check "edit editor covers priority" \
  "$(grep -m1 'root.kanbanService.setPriority(cardRoot.modelData.id, root.editPriority)' "$content_qml")" \
  '                    root.kanbanService.setPriority(cardRoot.modelData.id, root.editPriority)'

check "inline edit omits the due-date field so Todo/Done controls fit" \
  "$(grep -c 'id: editDueInput\\|yyyy-mm-dd' "$content_qml")" "0"

check "inline edit leaves existing due dates untouched" \
  "$(grep -c 'root.kanbanService.setDueDate(cardRoot.modelData.id' "$content_qml")" "0"

check "edit save check uses the reusable action button" \
  "$(grep -c 'id: saveEditButton' "$content_qml")" "1"

check "edit mode has no visible cancel x; Esc is the cancel path" \
  "$(grep -c 'onClicked: root.editingCardId = ""' "$content_qml")" "0"

# --- Delete path --------------------------------------------------------
check "delete is two-step: first click arms" \
  "$(grep -c 'root.deleteArmedId = cardRoot.modelData.id$' "$content_qml")" "1"

check "second click on the armed button removes" \
  "$(grep -c 'if (cardRoot.deleteArmed)' "$content_qml")" "1"

check "card title row reserves enough right-side space for hover actions" \
  "$(grep -c 'Item { Layout.preferredWidth: 48 }' "$content_qml")" "1"

check "compact action button size is defined once" \
  "$(grep -c 'width: 20' "$content_qml")" "1"

check "confirm and cancel glyphs keep the larger icon size by default" \
  "$(grep -c 'property int iconPixelSize: 13' "$content_qml")" "1"

check "all five compact action surfaces use the shared component" \
  "$(grep -c 'KanbanActionButton {' "$content_qml")" "5"

check "card hover border stays active while hovering edit/delete buttons" \
  "$(grep -c 'cardArea.containsMouse || editButton.hovered || deleteButton.hovered' "$content_qml")" "1"

check "hover edit button uses Font Awesome edit glyph" \
  "$(grep -F -c 'icon: "\uf044"' "$content_qml")" "1"

check "hover edit button uses green fill/glyph treatment" \
  "$(grep -c 'id: editButton' "$content_qml")" "1"

check "hover delete button uses red fill/glyph treatment" \
  "$(grep -c 'id: deleteButton' "$content_qml")" "1"

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

check "card title is single-line elided so long words cannot underlap actions" \
  "$(grep -c 'maximumLineCount: 1' "$content_qml")" "2"

# --- Done clear + progress footer --------------------------------------
check "Done header clear button calls the shared clearDone API" \
  "$(grep -c 'onClicked: if (root.kanbanService) root.kanbanService.clearDone()' "$content_qml")" \
  "1"

check "Done header clear button uses the same yellow broom treatment as notification clear" \
  "$(grep -F -c 'text: "\udb80\udce2"' "$content_qml")" \
  "1"

check "Done header clear button uses notification-clear yellow" \
  "$(grep -c 'color: clearDoneMouse.containsMouse ? "#e0a050" : Qt.rgba(1, 1, 1, 0.12)' "$content_qml")" \
  "1"

check "Done footer is scoped to the Done column" \
  "$(grep -c 'id: doneProgressCard' "$content_qml")" \
  "1"

check "Done footer centers the dial/text group instead of stretching it left" \
  "$(grep -c 'Layout.preferredWidth: 74' "$content_qml")" \
  "1"

check "Done footer is a separate layout-sized panel, not anchored inside the card panel" \
  "$(grep -c 'Layout.preferredHeight: 92' "$content_qml")" \
  "1"

check "Done footer shows completion percent" \
  "$(grep -F -c 'text: root.donePercent + "%"' "$content_qml")" \
  "1"

check "Done footer dial is driven by the done/total ratio" \
  "$(grep -c 'property real value: root.doneRatio' "$content_qml")" \
  "1"

check "Done footer dial does not wrap the remaining-track arc at 100%" \
  "$(grep -c 'if (trackStart < trackEnd)' "$content_qml")" \
  "1"

# --- Registration -------------------------------------------------------
check "tests/run-all.sh runs this suite" \
  "$(grep -m1 'notch-kanban-gui.sh' "$run_all")" \
  '  "$script_dir/notch-kanban-gui.sh"'

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
