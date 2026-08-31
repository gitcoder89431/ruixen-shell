import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell

// General -- bar layout mode + avatar + about, first page in the
// sidebar. Per direct request ("i think we can just do General for
// now"). See the property/function block in Settings.qml (root.
// barMode, root.avatarCacheBust, root.shuffleAvatar() etc.) for the
// real mechanism and reasoning.
ColumnLayout {
  id: root

  property var settingsRoot: null

  spacing: 16

  // Bar Layout -- own card, same segmented-button treatment as
  // Display's own Display Scale card (DisplayContent.qml).
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: barModeCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: barModeCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Bar Layout"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: settingsRoot.muted
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          model: [
            { id: "floating", label: "Floating" },
            { id: "docked", label: "Docked" }
          ]

          Rectangle {
            id: modeBtn
            required property var modelData
            readonly property bool isCurrent: settingsRoot.barMode === modeBtn.modelData.id

            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 6
            color: modeBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            border.width: 1
            border.color: modeBtn.isCurrent ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.12)

            Text {
              anchors.centerIn: parent
              text: modeBtn.modelData.label
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              font.weight: modeBtn.isCurrent ? Font.DemiBold : Font.Normal
              color: modeBtn.isCurrent ? settingsRoot.textColor : settingsRoot.muted
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.setBarMode(modeBtn.modelData.id)
            }
          }
        }
      }
    }
  }

  // Avatar -- shown on ruixen.notch's own collapsed row. Live preview
  // uses the exact same dual-layer technique as ruixen.notch's own
  // UserAvatar component (gradient Rectangle underneath, theme-aware
  // via Qt.lighter/darker off settingsRoot.accent -- same Color.accent
  // source, just computed locally since plugins can't import across
  // each other), real ~/.face.icon image + circular mask on top, which
  // simply renders nothing when the file doesn't exist, letting the
  // gradient show through on its own -- no separate "gradient mode"
  // flag needed anywhere.
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: avatarCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: avatarCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Avatar"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: settingsRoot.muted
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 16

        Item {
          Layout.preferredWidth: 56
          Layout.preferredHeight: 56

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            gradient: Gradient {
              GradientStop { position: 0.0; color: Qt.lighter(settingsRoot.accent, 1.6) }
              GradientStop { position: 1.0; color: Qt.darker(settingsRoot.accent, 1.4) }
            }
          }

          // "#" cache-bust fragment, not a "?" query string -- Qt's
          // local file:// loader can try to resolve a "?"-suffixed
          // string as a literal filename instead of stripping it the
          // way an HTTP server would. A URL fragment is universally
          // stripped before path resolution, so it busts the Image's
          // source-string cache (needed since Shuffle/Reset overwrite
          // the exact same path) without that risk.
          Image {
            id: avatarPreviewImage
            anchors.fill: parent
            source: "file://" + Quickshell.env("HOME") + "/.face.icon#" + settingsRoot.avatarCacheBust
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: false
          }

          Rectangle {
            id: avatarPreviewMask
            anchors.fill: parent
            radius: width / 2
            color: "#ffffff"
            visible: false
            layer.enabled: true
          }

          MultiEffect {
            anchors.fill: parent
            source: avatarPreviewImage
            maskEnabled: true
            maskSource: avatarPreviewMask
            maskThresholdMin: 0.5
            maskThresholdMax: 1.0
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            Layout.fillWidth: true
            text: "Shown on the notch's collapsed row. Shuffle picks a random generated avatar; Reset goes back to the plain gradient."
            wrapMode: Text.WordWrap
            font.family: settingsRoot.fontFamily
            font.pixelSize: 10
            color: settingsRoot.muted
          }

          RowLayout {
            spacing: 8

            Rectangle {
              Layout.preferredWidth: 84
              Layout.preferredHeight: 28
              radius: 8
              color: shuffleMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.06)
              opacity: settingsRoot.avatarBusy ? 0.5 : 1

              Text {
                anchors.centerIn: parent
                text: settingsRoot.avatarBusy ? "..." : "Shuffle"
                font.family: settingsRoot.fontFamily
                font.pixelSize: 11
                color: settingsRoot.textColor
              }

              MouseArea {
                id: shuffleMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !settingsRoot.avatarBusy
                cursorShape: Qt.PointingHandCursor
                onClicked: settingsRoot.shuffleAvatar()
              }
            }

            Rectangle {
              Layout.preferredWidth: 72
              Layout.preferredHeight: 28
              radius: 8
              color: resetMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.06)
              opacity: settingsRoot.avatarBusy ? 0.5 : 1

              Text {
                anchors.centerIn: parent
                text: "Reset"
                font.family: settingsRoot.fontFamily
                font.pixelSize: 11
                color: settingsRoot.muted
              }

              MouseArea {
                id: resetMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !settingsRoot.avatarBusy
                cursorShape: Qt.PointingHandCursor
                onClicked: settingsRoot.resetAvatar()
              }
            }
          }
        }
      }
    }
  }

  // About -- small and static for now. No real version tracking exists
  // in this repo yet (confirmed: no VERSION file, no git tags), so this
  // mirrors the one number that does exist -- this plugin's own
  // manifest.json "version" field -- rather than inventing a fake one.
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: aboutCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: aboutCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 4

      Text {
        text: "Ruixen Shell"
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
    }
  }

  Item { Layout.fillHeight: true }
}
