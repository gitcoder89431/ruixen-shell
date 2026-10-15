import QtQuick

// Issue #102 phase 10 (final page): extracted from SettingsContent.qml's
// own About section (252 lines of pure visual markup -- version card,
// Health card, and the danger-zone full uninstall). Same pattern as
// every prior page -- see PluginsPage.qml's own header for the full
// reasoning (live property bindings via settingsRoot, never a
// one-time copy; a Column wrapper with its own matching spacing/
// visible so an inactive section collapses to zero space in the outer
// Column exactly like individually-hidden siblings did). No sibling
// component types used here (TextInput is a plain QtQuick type), so
// unlike most other pages this one needs no `import ".."`.
//
// The uninstall button's own activate logic (confirmFullUninstall())
// is a thin wrapper delegating to services/PluginService.qml, same as
// every other plugin-management action -- this extraction only ever
// moves the CONFIRMATION UI (the typed-phrase gate, the button's own
// enabled/disabled state), never the real destructive logic itself,
// which was already fully isolated before this phase and stays that
// way.
//
// restartShellButton/openGithubButton/uninstallConfirmRow/
// uninstallButtonRow are exposed because SettingsContent.qml's own
// shared, cross-section focusedItemVisual() keyboard-navigation
// coordinator needs to reach them regardless of which page owns them.
// uninstallConfirmField is ALSO exposed, for the same reason, by
// SettingsContent.qml's own aboutItems keyboard-nav data model (same
// role as pluginItems/audioItems/profileItems/launcherItems/wifiItems
// before it) -- its own text-entry row needs to hand real Qt focus to
// the actual input field, not just report which one is focused.
//
// Restart Shell + Open on GitHub (restartShellItem/openGithubItem, one
// Row, side by side) -- direct asks: "above the uninstall component,
// is it safe or possible to add an omarchy restart shell button?" (yes
// -- restartOmarchyShell's own comment in SettingsContent.qml has the
// reasoning: this exact command already fires from a live button
// elsewhere in this same plugin) and "on the same row or above it...
// one Open on Github". Both sit above the danger zone, plain action
// buttons rather than cards -- same bare-button weight and side-by-
// side pairing shape Plugins' own Check/Update row already uses, not
// the red destructive styling Uninstall below them has, since neither
// is destructive. Indices 0/1 in aboutItems now, ahead of the
// uninstall confirm field/button which shifted to 2/3.
Column {
  id: root
  required property Item settingsRoot

  width: parent.width
  spacing: 16
  visible: settingsRoot.aboutOpen

  readonly property alias restartShellButton: restartShellItem
  readonly property alias openGithubButton: openGithubItem
  readonly property alias uninstallConfirmRow: uninstallConfirmRow
  readonly property alias uninstallButtonRow: uninstallButtonRow
  readonly property alias uninstallConfirmField: uninstallConfirmField

  // About's own two items -- the version card (small and static, same
  // reasoning as ruixen.settings' own: no real version tracking exists
  // in this repo yet, so this mirrors the one number that does --
  // ruixen.launcher's own manifest.json "version" field, "Ruixen
  // Launcher" not "Ruixen Shell" since that's this plugin's own name)
  // and the danger-zone full uninstall, ported from
  // ruixen.settings/AboutContent.qml. Gated behind typing an exact
  // phrase, not just a click-through confirm.
  Rectangle {
    id: aboutVersionItem
    width: parent.width
    height: aboutVersionContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.aboutOpen

    Column {
      id: aboutVersionContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 4

      Text {
        // Real manifest.json "name" for this plugin -- matches the
        // Plugins page's own checklist row for it, not a separate name
        // invented just for this page.
        text: "Ruixen Launcher"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      Text {
        text: "v0.1.0 -- github.com/gitcoder89431/ruixen-shell"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 10
        color: settingsRoot.muted
      }

      Text {
        // Confirmed directly against this machine's own Omarchy
        // install (contributing.md, os-release BUG_REPORT_URL, several
        // systemd unit Documentation= lines all agree) -- basecamp/
        // omarchy, not omacom/omarchy.
        visible: settingsRoot.omarchyVersion !== ""
        text: "Omarchy " + settingsRoot.omarchyVersion + " -- github.com/basecamp/omarchy"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 10
        color: settingsRoot.muted
      }
    }
  }

  // Health card -- see healthChecks' own comment above for what this
  // checks and why. Purely informational (no MouseArea/focus ring, same
  // as aboutVersionItem above it), so it has no entry in aboutItems --
  // there's nothing here to activate or type into.
  Rectangle {
    id: healthItem
    width: parent.width
    height: healthContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.aboutOpen

    Column {
      id: healthContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 8

      Text {
        text: "Health"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      Text {
        visible: settingsRoot.healthChecks.length === 0
        text: "Checking…"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 10
        color: settingsRoot.muted
      }

      // Fixed-ish pass/fail dot, not the live theme accent -- direct
      // report: "my accent is red so the dot status shows red, can you
      // make it green or red token to show service status?" A status dot
      // needs to read as pass/fail on its own, independent of whatever
      // color the active theme happens to assign accent (confirmed live:
      // the Matcha theme's own accent is #f1735a, a coral/red that was
      // visually indistinguishable from the "#e05252" failure color used
      // right next to it). "#3ecf5b" is already this codebase's own
      // established default accent/connected-dot green (SettingsWifiRow's
      // own fallback), reused here as a real token instead of a new one;
      // "#e05252" is the same failure red every other error state in this
      // file already uses -- unchanged, it just no longer shares a hue
      // with a theme's own accent by coincidence.
      Repeater {
        model: settingsRoot.healthChecks

        delegate: Item {
          width: healthContent.width
          height: 16

          Rectangle {
            id: healthDot
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: modelData.ok ? "#3ecf5b" : "#e05252"
          }

          Text {
            anchors.left: healthDot.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label + " -- " + modelData.detail
            font.family: settingsRoot.fontFamily
            font.pixelSize: 10
            color: modelData.ok ? settingsRoot.muted : "#e05252"
          }
        }
      }
    }
  }

  Row {
    width: parent.width
    spacing: 8

    Rectangle {
      id: restartShellItem
      width: (parent.width - 8) / 2
      height: 36
      radius: 10
      color: restartShellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
      visible: settingsRoot.aboutOpen
      border.width: settingsRoot.aboutOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 0 ? 1 : 0
      border.color: settingsRoot.accent

      Row {
        anchors.centerIn: parent
        spacing: 8

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          font.family: settingsRoot.fontFamily
          font.pixelSize: 13
          color: settingsRoot.textColor
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Restart Shell"
          font.family: settingsRoot.fontFamily
          font.pixelSize: 12
          color: settingsRoot.textColor
        }
      }

      MouseArea {
        id: restartShellMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: settingsRoot.restartOmarchyShell()
      }
    }

    Rectangle {
      id: openGithubItem
      width: (parent.width - 8) / 2
      height: 36
      radius: 10
      color: openGithubMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
      visible: settingsRoot.aboutOpen
      border.width: settingsRoot.aboutOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 1 ? 1 : 0
      border.color: settingsRoot.accent

      Row {
        anchors.centerIn: parent
        spacing: 8

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          font.family: settingsRoot.fontFamily
          font.pixelSize: 13
          color: settingsRoot.textColor
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Open on GitHub"
          font.family: settingsRoot.fontFamily
          font.pixelSize: 12
          color: settingsRoot.textColor
        }
      }

      MouseArea {
        id: openGithubMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: settingsRoot.openRepoInBrowser()
      }
    }
  }

  Rectangle {
    id: dangerZoneItem
    width: parent.width
    height: dangerZoneContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0.878, 0.322, 0.322, 0.08)
    border.width: 1
    border.color: Qt.rgba(0.878, 0.322, 0.322, 0.35)
    visible: settingsRoot.aboutOpen

    Column {
      id: dangerZoneContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 8

      Text {
        visible: settingsRoot.ruixenRepoPath === ""
        width: parent.width
        text: "Uninstall needs a repo checkout path -- run install.sh or update.sh once from your ruixen-shell clone to enable it here."
        wrapMode: Text.WordWrap
        font.family: settingsRoot.fontFamily
        font.pixelSize: 10
        color: settingsRoot.muted
      }

      Item {
        id: uninstallConfirmRow
        width: parent.width
        height: 32

        Rectangle {
          visible: settingsRoot.aboutOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 2
          anchors.fill: parent
          anchors.margins: -4
          radius: 10
          color: "transparent"
          border.width: 1
          border.color: settingsRoot.accent
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: uninstallButtonRow.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          height: 32
          radius: 10
          color: Qt.rgba(1, 1, 1, 0.06)

          TextInput {
            id: uninstallConfirmField
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: settingsRoot.textColor
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            clip: true
            text: settingsRoot.uninstallConfirmInput
            onTextChanged: settingsRoot.uninstallConfirmInput = text

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: settingsRoot.uninstallConfirmPhrase
              color: settingsRoot.muted
              font.family: settingsRoot.fontFamily
              font.pixelSize: 12
              visible: uninstallConfirmField.text.length === 0
            }

            Keys.onEscapePressed: settingsRoot.returnFocusRequested()
          }
        }

        Rectangle {
          id: uninstallButtonRow
          readonly property bool ready: settingsRoot.ruixenRepoPath !== "" && settingsRoot.uninstallConfirmInput === settingsRoot.uninstallConfirmPhrase

          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 96
          height: 32
          radius: 10
          color: !uninstallButtonRow.ready ? Qt.rgba(1, 1, 1, 0.06)
            : (uninstallMouse.containsMouse ? Qt.rgba(0.878, 0.322, 0.322, 0.55) : Qt.rgba(0.878, 0.322, 0.322, 0.4))
          opacity: uninstallButtonRow.ready ? 1 : 0.5

          Rectangle {
            visible: settingsRoot.aboutOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 3
            anchors.fill: parent
            anchors.margins: -4
            radius: 12
            color: "transparent"
            border.width: 1
            border.color: settingsRoot.accent
          }

          Text {
            anchors.centerIn: parent
            text: "Uninstall"
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: settingsRoot.textColor
          }

          MouseArea {
            id: uninstallMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: uninstallButtonRow.ready
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsRoot.confirmFullUninstall()
          }
        }
      }
    }
  }
}
