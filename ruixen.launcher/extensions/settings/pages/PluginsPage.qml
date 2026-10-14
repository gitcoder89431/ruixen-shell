import QtQuick

// Issue #102 phase 1: extracted from SettingsContent.qml's own Plugins
// section (355 lines of pure visual markup -- PluginService.qml already
// owns every bit of actual Plugins business logic/state, this is just
// where that state used to be RENDERED). No behavior or visual
// change: every settingsRoot.* read below is a live property binding
// (never a one-time copy -- see ExtensionTwoPanel.qml's own header for
// why that distinction matters here specifically, a real bug this plugin
// already hit once), same as every other already-split file in this
// plugin reads its own outer root directly.
//
// A Column, not a plain Item -- SettingsContent.qml's own rightContentColumn
// (a Column) used to hold these two Rectangles as direct, individually
// visible-gated siblings; this wraps them as ONE child instead, with its
// own matching spacing so the gap BETWEEN them reads identically, and its
// own top-level visible so an inactive section still collapses to zero
// height/spacing in the outer Column exactly like two individually-hidden
// siblings did (Qt Column: a hidden child contributes no space at all).
//
// checkButton/updateButton/repeater are exposed because
// SettingsContent.qml's own shared, cross-section focusedItemVisual()/
// scrollToFocusedItem() keyboard-navigation coordinator (used by every
// section, not just this one -- stays centralized there on purpose, see
// AGENTS.md on keeping true cross-category state/coordination in one
// place) needs to reach the actual focused visual Item regardless of
// which section owns it.
Column {
  id: root
  required property Item settingsRoot

  width: parent.width
  spacing: 16
  visible: settingsRoot.pluginsOpen

  readonly property alias checkButton: pluginCheckButton
  readonly property alias updateButton: pluginUpdateButton
  readonly property alias repeater: pluginRepeater

  // Plugins' own two items -- Check for Updates and Update actions,
  // then the checklist. Ported from ruixen.settings/PluginsContent.qml
  // + Settings.qml's own header-row Check/Update icons -- this plugin
  // has no shared header-icon chrome to put those in, so they're their
  // own action rows in a small card instead, same "adapt the chrome,
  // not the backend" approach Wi-Fi's own dropped QR/speed-test buttons
  // took the other way (dropped entirely there; kept here since these
  // two are core to the page, not optional extras).
  Rectangle {
    id: pluginActionsItem
    width: parent.width
    height: pluginActionsContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.pluginsOpen

    Column {
      id: pluginActionsContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 10

      Text {
        visible: settingsRoot.ruixenRepoPath === ""
        width: parent.width
        text: "Update needs a repo checkout path -- run install.sh or update.sh once from your ruixen-shell clone to enable it here."
        wrapMode: Text.WordWrap
        font.family: settingsRoot.fontFamily
        font.pixelSize: 10
        color: settingsRoot.muted
      }

      // Always exactly these two rows, never a third jumping in/out --
      // direct follow-up: "on the button press like Up to Date the
      // status, can we not make it jump to a new one row status, like
      // keep the commit version and last updated time and just show a
      // check or replace one of the line. keep it consistent 2 rows so
      // its not jumpy please". Commit Version never changes; the
      // second row swaps its own text/color between "Last Updated:
      // <date>" (nothing in flight yet) and the live Checking/
      // Updating/result message -- same information, just no longer a
      // separate line that appears and disappears.
      Column {
        visible: settingsRoot.pluginLastCommitSha !== ""
        width: parent.width
        spacing: 2

        Row {
          spacing: 4
          Text {
            text: "Commit Version:"
            font.family: settingsRoot.fontFamily
            font.pixelSize: 11
            color: settingsRoot.muted
          }
          Text {
            text: settingsRoot.pluginLastCommitSha
            font.family: settingsRoot.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: settingsRoot.textColor
          }
        }

        Text {
          text: settingsRoot.pluginStatusLine !== "" ? settingsRoot.pluginStatusLine : ("Last Updated: " + settingsRoot.pluginLastCommitDate)
          font.family: settingsRoot.fontFamily
          font.pixelSize: 11
          color: settingsRoot.pluginStatusLine !== "" ? settingsRoot.pluginStatusLineColor : settingsRoot.muted
        }
      }

      Text {
        visible: (settingsRoot.pluginUpdateStatus === "error" || settingsRoot.pluginUpdateStatus === "interrupted") && settingsRoot.pluginUpdateError !== ""
        width: parent.width
        text: settingsRoot.pluginUpdateError
        wrapMode: Text.WordWrap
        font.family: settingsRoot.fontFamily
        font.pixelSize: 10
        color: settingsRoot.pluginUpdateStatus === "interrupted" ? "#e8c34a" : "#e05252"
      }

      Text {
        visible: settingsRoot.pluginCheckStatus === "error" && settingsRoot.pluginCheckError !== ""
        width: parent.width
        text: settingsRoot.pluginCheckError
        wrapMode: Text.WordWrap
        font.family: settingsRoot.fontFamily
        font.pixelSize: 10
        color: "#e05252"
      }

      // Two real buttons side by side, not a plain 1-column/2-row list
      // -- direct follow-up: "the update thing on top the 1 column 2
      // row doesnt look nice. can they be buttons or something else".
      // Rest-state light tint (Qt.rgba(1,1,1,0.06)/0.12 hover) is safe
      // here -- unlike Wi-Fi/Bluetooth's own buttons, these sit
      // directly on this card's plain dark background, never a
      // lightened row, so there's no low-contrast risk to design
      // around (see SettingsWifiRow.qml's own header comment for that
      // specific bug).
      Row {
        width: parent.width
        spacing: 8

        Rectangle {
          id: pluginCheckButton
          readonly property bool actionEnabled: settingsRoot.ruixenRepoPath !== "" && settingsRoot.pluginCheckStatus !== "checking"

          width: (parent.width - 8) / 2
          height: 36
          radius: 8
          color: checkMouse.containsMouse && actionEnabled ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
          border.width: settingsRoot.pluginsOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 0 ? 1 : 0
          border.color: settingsRoot.accent

          Row {
            anchors.centerIn: parent
            spacing: 8

            Text {
              id: checkGlyph
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf058"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 13
              color: pluginCheckButton.actionEnabled ? settingsRoot.textColor : Qt.rgba(1, 1, 1, 0.25)
              rotation: settingsRoot.pluginCheckStatus === "checking" ? checkSpinAngle : 0
              property real checkSpinAngle: 0

              NumberAnimation on checkSpinAngle {
                running: settingsRoot.pluginCheckStatus === "checking"
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Check Updates"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 12
              color: pluginCheckButton.actionEnabled ? settingsRoot.textColor : settingsRoot.muted
            }
          }

          MouseArea {
            id: checkMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: pluginCheckButton.actionEnabled
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsRoot.checkForUpdates()
          }
        }

        Rectangle {
          id: pluginUpdateButton
          readonly property bool actionEnabled: settingsRoot.ruixenRepoPath !== "" && settingsRoot.pluginUpdateStatus !== "updating"

          width: (parent.width - 8) / 2
          height: 36
          radius: 8
          color: updateMouse.containsMouse && actionEnabled ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
          border.width: settingsRoot.pluginsOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 1 ? 1 : 0
          border.color: settingsRoot.accent

          Row {
            anchors.centerIn: parent
            spacing: 8

            Text {
              id: updateGlyph
              anchors.verticalCenter: parent.verticalCenter
              text: settingsRoot.pluginUpdateStatus === "updating" ? "\uf1ce" : "\uf021"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 13
              color: pluginUpdateButton.actionEnabled ? settingsRoot.textColor : Qt.rgba(1, 1, 1, 0.25)
              rotation: settingsRoot.pluginUpdateStatus === "updating" ? updateSpinAngle : 0
              property real updateSpinAngle: 0

              NumberAnimation on updateSpinAngle {
                running: settingsRoot.pluginUpdateStatus === "updating"
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Update"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 12
              color: pluginUpdateButton.actionEnabled ? settingsRoot.textColor : settingsRoot.muted
            }
          }

          MouseArea {
            id: updateMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: pluginUpdateButton.actionEnabled
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsRoot.updateRuixenShell()
          }
        }
      }
    }
  }

  Rectangle {
    id: pluginListItem
    width: parent.width
    height: pluginListContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.pluginsOpen

    Column {
      id: pluginListContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 4

      Text {
        visible: settingsRoot.pluginRows.length === 0
        text: "No plugins found"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        color: settingsRoot.muted
      }

      Repeater {
        id: pluginRepeater
        model: settingsRoot.pluginRows

        Item {
          id: pluginRow
          required property var modelData
          required property int index
          readonly property bool isProtected: settingsRoot.pluginIsProtected(modelData)
          readonly property bool busy: settingsRoot.pluginBusyId === modelData.id
          readonly property int focusIndex: {
            for (var i = 0; i < settingsRoot.togglablePluginRows.length; i++)
              if (settingsRoot.togglablePluginRows[i].id === modelData.id) return i
            return -1
          }

          width: parent.width
          height: 28

          Rectangle {
            visible: !pluginRow.isProtected && settingsRoot.pluginsOpen && settingsRoot.rightFocused
              && settingsRoot.focusedItemIndex === (2 + pluginRow.focusIndex)
            anchors.fill: parent
            anchors.margins: -4
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: settingsRoot.accent
          }

          // Reserved width for whatever sits at the row's far right
          // (lock glyph for protected rows, the toggle otherwise) plus
          // its own margin -- the name's own width budget below is
          // capped against this, not against the status dot, now that
          // the dot follows the name instead of living out at the
          // far-right edge.
          readonly property real trailingWidth: (pluginRow.isProtected ? pluginLock.implicitWidth : pluginToggle.width) + 8

          Text {
            id: pluginNameText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: pluginRow.modelData.name
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            color: pluginRow.isProtected ? settingsRoot.muted : settingsRoot.textColor
            elide: Text.ElideRight
            // Sized to its own content (capped by the leftover space
            // before the lock/toggle, reserving a bit more when the
            // status dot is actually showing) instead of stretching
            // to fill that whole space -- so pluginStatusDot below,
            // anchored off this Text's own right edge, sits right
            // behind the plugin's name instead of pinned out next to
            // the toggle. Direct report: "instead of alligning it
            // with the toggle, can we make it right behind the name
            // of the plugin instead."
            width: Math.min(implicitWidth, pluginRow.width - pluginRow.trailingWidth - (pluginStatusDot.visible ? 12 : 0))
          }

          // Update-status dot -- pending (yellow) if this plugin has
          // files in the checked batch, up to date (accent) otherwise.
          // Only shown once a real check has actually run.
          Rectangle {
            id: pluginStatusDot
            visible: settingsRoot.pluginCheckStatus === "checked"
            readonly property bool pending: settingsRoot.pluginChangedIds.indexOf(pluginRow.modelData.id) >= 0
            anchors.left: pluginNameText.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: pending ? "#e8c34a" : "#3ecf5b"
          }

          Text {
            id: pluginLock
            visible: pluginRow.isProtected
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            font.family: settingsRoot.fontFamily
            font.pixelSize: 11
            color: settingsRoot.muted
          }

          Rectangle {
            id: pluginToggle
            visible: !pluginRow.isProtected
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 16
            radius: 8
            color: pluginRow.modelData.enabled ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.15)
            opacity: pluginRow.busy ? 0.5 : 1
            Behavior on color { ColorAnimation { duration: 120 } }

            Rectangle {
              width: 12
              height: 12
              radius: 6
              color: "#ffffff"
              anchors.verticalCenter: parent.verticalCenter
              x: pluginRow.modelData.enabled ? parent.width - width - 2 : 2
              Behavior on x { NumberAnimation { duration: 120 } }
            }

            MouseArea {
              anchors.fill: parent
              enabled: !pluginRow.busy
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.togglePluginEnabled(pluginRow.modelData)
            }
          }
        }
      }
    }
  }
}
