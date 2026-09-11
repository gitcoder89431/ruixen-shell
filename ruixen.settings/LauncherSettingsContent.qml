import QtQuick
import QtQuick.Layouts

// Issue #61: "Launcher" settings page -- configurable Search Files
// locations/exclusions for ruixen.launcher. Same split convention as
// every other section (PluginsContent.qml/AboutContent.qml/...):
// presentation only, all real state/persistence lives on Settings.qml's
// own root, reached through the single settingsRoot reference.
ColumnLayout {
  id: root

  property var settingsRoot: null

  spacing: 12

  Component.onCompleted: settingsRoot.refreshLauncherDiscoveredMounts()

  // Merges the live findmnt-discovered mounts with any remembered
  // disabled root that ISN'T currently mounted -- a drive disabled
  // while plugged in should stay visible (and re-enable-able) after
  // it's unplugged, per this issue's own "visible indication when a
  // currently mounted source has been disabled" requirement.
  readonly property var mountChecklist: {
    var cfg = settingsRoot.launcherSearchConfig
    var disabledSet = ({})
    for (var i = 0; i < cfg.disabledAutoRoots.length; i++) disabledSet[cfg.disabledAutoRoots[i]] = true
    var seen = ({})
    var out = []
    var live = settingsRoot.launcherDiscoveredMounts
    for (var j = 0; j < live.length; j++) {
      seen[live[j].path] = true
      out.push({ path: live[j].path, fstype: live[j].fstype, disabled: !!disabledSet[live[j].path], connected: true })
    }
    for (var k = 0; k < cfg.disabledAutoRoots.length; k++) {
      if (seen[cfg.disabledAutoRoots[k]]) continue
      out.push({ path: cfg.disabledAutoRoots[k], fstype: "", disabled: true, connected: false })
    }
    return out
  }

  // ---- Home / auto-mount toggles ---------------------------------------

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: togglesContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: togglesContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 8

      RowLayout {
        Layout.fillWidth: true
        Text {
          text: "Include Home"
          font.family: settingsRoot.fontFamily
          font.pixelSize: 12
          color: settingsRoot.textColor
          Layout.fillWidth: true
        }
        Rectangle {
          Layout.preferredWidth: 32
          Layout.preferredHeight: 16
          radius: 8
          color: settingsRoot.launcherSearchConfig.includeHome ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.15)
          Behavior on color { ColorAnimation { duration: 120 } }
          Rectangle {
            width: 12
            height: 12
            radius: 6
            color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
            x: settingsRoot.launcherSearchConfig.includeHome ? parent.width - width - 2 : 2
            Behavior on x { NumberAnimation { duration: 120 } }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsRoot.setLauncherIncludeHome(!settingsRoot.launcherSearchConfig.includeHome)
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Text {
          text: "Auto-include mounted drives"
          font.family: settingsRoot.fontFamily
          font.pixelSize: 12
          color: settingsRoot.textColor
          Layout.fillWidth: true
        }
        Rectangle {
          Layout.preferredWidth: 32
          Layout.preferredHeight: 16
          radius: 8
          color: settingsRoot.launcherSearchConfig.includeMountedRoots ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.15)
          Behavior on color { ColorAnimation { duration: 120 } }
          Rectangle {
            width: 12
            height: 12
            radius: 6
            color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
            x: settingsRoot.launcherSearchConfig.includeMountedRoots ? parent.width - width - 2 : 2
            Behavior on x { NumberAnimation { duration: 120 } }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsRoot.setLauncherIncludeMountedRoots(!settingsRoot.launcherSearchConfig.includeMountedRoots)
          }
        }
      }
    }
  }

  // ---- Auto-discovered mounts checklist ---------------------------------

  Text {
    text: "MOUNTED DRIVES"
    font.family: settingsRoot.fontFamily
    font.pixelSize: 10
    font.capitalization: Font.AllUppercase
    font.bold: true
    color: settingsRoot.muted
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: mountsContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: mountsContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 4

      Text {
        visible: root.mountChecklist.length === 0
        text: "No drives detected"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        color: settingsRoot.muted
      }

      Repeater {
        model: root.mountChecklist

        RowLayout {
          id: mountRow
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: 28

          ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Text {
              text: mountRow.modelData.path
              font.family: settingsRoot.fontFamily
              font.pixelSize: 12
              color: settingsRoot.textColor
              elide: Text.ElideMiddle
              Layout.fillWidth: true
            }
            Text {
              visible: !mountRow.modelData.connected
              text: "Not currently connected"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 9
              color: settingsRoot.muted
            }
          }

          Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 16
            radius: 8
            color: !mountRow.modelData.disabled ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.15)
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
              width: 12
              height: 12
              radius: 6
              color: "#ffffff"
              anchors.verticalCenter: parent.verticalCenter
              x: !mountRow.modelData.disabled ? parent.width - width - 2 : 2
              Behavior on x { NumberAnimation { duration: 120 } }
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.toggleLauncherAutoRootDisabled(mountRow.modelData.path)
            }
          }
        }
      }
    }
  }

  // ---- Custom roots / exclusions: shared add+list layout -----------------
  // Three near-identical cards below (custom roots, excluded paths,
  // excluded names) -- kept as three separate literal blocks rather
  // than one parameterized Component, since QML has no clean way to
  // pass "which settingsRoot function to call" as data into a reused
  // delegate without a pile of indirection that would be harder to
  // follow than the small, honest repetition here.

  Text {
    text: "CUSTOM SEARCH ROOTS"
    font.family: settingsRoot.fontFamily
    font.pixelSize: 10
    font.capitalization: Font.AllUppercase
    font.bold: true
    color: settingsRoot.muted
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: rootsContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: rootsContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 6

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 28
          radius: 6
          color: Qt.rgba(1, 1, 1, 0.06)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.12)

          TextInput {
            id: rootInput
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            color: settingsRoot.textColor
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            clip: true
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "~/Work or /mnt/Documents"
              color: settingsRoot.muted
              font.family: settingsRoot.fontFamily
              font.pixelSize: 12
              visible: rootInput.text.length === 0
            }
            Keys.onReturnPressed: { settingsRoot.addLauncherRoot(rootInput.text); rootInput.text = "" }
          }
        }

        Rectangle {
          Layout.preferredWidth: 50
          Layout.preferredHeight: 28
          radius: 6
          color: Qt.rgba(1, 1, 1, 0.08)
          Text {
            anchors.centerIn: parent
            text: "Add"
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            color: settingsRoot.textColor
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { settingsRoot.addLauncherRoot(rootInput.text); rootInput.text = "" }
          }
        }
      }

      Text {
        visible: settingsRoot.launcherSearchConfig.roots.length === 0
        text: "No custom roots added"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        color: settingsRoot.muted
      }

      Repeater {
        model: settingsRoot.launcherSearchConfig.roots

        RowLayout {
          id: rootRow
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: 24

          Text {
            text: rootRow.modelData
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            color: settingsRoot.textColor
            elide: Text.ElideMiddle
            Layout.fillWidth: true
          }
          Text {
            text: "✕"
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            color: settingsRoot.muted
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.removeLauncherRoot(rootRow.modelData)
            }
          }
        }
      }
    }
  }

  Text {
    text: "EXCLUDED PATHS"
    font.family: settingsRoot.fontFamily
    font.pixelSize: 10
    font.capitalization: Font.AllUppercase
    font.bold: true
    color: settingsRoot.muted
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: excludePathsContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: excludePathsContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 6

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 28
          radius: 6
          color: Qt.rgba(1, 1, 1, 0.06)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.12)

          TextInput {
            id: excludePathInput
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            color: settingsRoot.textColor
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            clip: true
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "~/VMs or ~/Downloads/ISOs"
              color: settingsRoot.muted
              font.family: settingsRoot.fontFamily
              font.pixelSize: 12
              visible: excludePathInput.text.length === 0
            }
            Keys.onReturnPressed: { settingsRoot.addLauncherExcludePath(excludePathInput.text); excludePathInput.text = "" }
          }
        }

        Rectangle {
          Layout.preferredWidth: 50
          Layout.preferredHeight: 28
          radius: 6
          color: Qt.rgba(1, 1, 1, 0.08)
          Text {
            anchors.centerIn: parent
            text: "Add"
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            color: settingsRoot.textColor
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { settingsRoot.addLauncherExcludePath(excludePathInput.text); excludePathInput.text = "" }
          }
        }
      }

      Text {
        visible: settingsRoot.launcherSearchConfig.excludePaths.length === 0
        text: "No excluded paths"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        color: settingsRoot.muted
      }

      Repeater {
        model: settingsRoot.launcherSearchConfig.excludePaths

        RowLayout {
          id: excludePathRow
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: 24

          Text {
            text: excludePathRow.modelData
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            color: settingsRoot.textColor
            elide: Text.ElideMiddle
            Layout.fillWidth: true
          }
          Text {
            text: "✕"
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            color: settingsRoot.muted
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.removeLauncherExcludePath(excludePathRow.modelData)
            }
          }
        }
      }
    }
  }

  Text {
    text: "EXCLUDED DIRECTORY NAMES"
    font.family: settingsRoot.fontFamily
    font.pixelSize: 10
    font.capitalization: Font.AllUppercase
    font.bold: true
    color: settingsRoot.muted
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: excludeNamesContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: excludeNamesContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 6

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 28
          radius: 6
          color: Qt.rgba(1, 1, 1, 0.06)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.12)

          TextInput {
            id: excludeNameInput
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            color: settingsRoot.textColor
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            clip: true
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "e.g. dist or .venv"
              color: settingsRoot.muted
              font.family: settingsRoot.fontFamily
              font.pixelSize: 12
              visible: excludeNameInput.text.length === 0
            }
            Keys.onReturnPressed: { settingsRoot.addLauncherExcludeName(excludeNameInput.text); excludeNameInput.text = "" }
          }
        }

        Rectangle {
          Layout.preferredWidth: 50
          Layout.preferredHeight: 28
          radius: 6
          color: Qt.rgba(1, 1, 1, 0.08)
          Text {
            anchors.centerIn: parent
            text: "Add"
            font.family: settingsRoot.fontFamily
            font.pixelSize: 12
            color: settingsRoot.textColor
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { settingsRoot.addLauncherExcludeName(excludeNameInput.text); excludeNameInput.text = "" }
          }
        }
      }

      Text {
        visible: settingsRoot.launcherSearchConfig.excludeNames.length === 0
        text: "No excluded names"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        color: settingsRoot.muted
      }

      // Wrapped, not a vertical list -- these are short single-word
      // names (node_modules, .git, ...), a dense wrapped chip layout
      // reads better than one full-width row apiece.
      Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          model: settingsRoot.launcherSearchConfig.excludeNames

          Rectangle {
            id: excludeNameChip
            required property var modelData
            width: chipRow.implicitWidth + 16
            height: 24
            radius: 6
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)

            RowLayout {
              id: chipRow
              anchors.centerIn: parent
              spacing: 6

              Text {
                text: excludeNameChip.modelData
                font.family: settingsRoot.fontFamily
                font.pixelSize: 11
                color: settingsRoot.textColor
              }
              Text {
                text: "✕"
                font.family: settingsRoot.fontFamily
                font.pixelSize: 11
                color: settingsRoot.muted
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -4
                  cursorShape: Qt.PointingHandCursor
                  onClicked: settingsRoot.removeLauncherExcludeName(excludeNameChip.modelData)
                }
              }
            }
          }
        }
      }
    }
  }
}
