import QtQuick
import QtQuick.Layouts

// About -- its own page now, last in the sidebar. Was a card at the
// bottom of the General page, direct follow-up ("the last about card
// is kinda off panel cause theres no scroll, i guess after the
// plugins setting we can do About and then we can list the last card
// there"): General's own trailing Item spacer (not a Flickable, per
// the layout invariant every section page needs one or the other)
// meant this card had nowhere to go once the page's other content
// pushed it past the panel's fixed height. Its own page has the same
// spacer, but nothing else competing for room above it.
ColumnLayout {
  id: root

  property var settingsRoot: null

  spacing: 16

  // Small and static for now. No real version tracking exists in this
  // repo yet (confirmed: no VERSION file, no git tags), so this
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

  // Needs a real repo checkout path the same way Plugins' own Update
  // button does (confirmFullUninstall runs uninstall.sh from it) --
  // that page keeps its own copy of this warning for Update; this one
  // is About's own since the danger zone moved here and needs the same
  // explanation for why Uninstall might be disabled.
  Text {
    visible: settingsRoot.ruixenRepoPath === ""
    Layout.fillWidth: true
    text: "Uninstall needs a repo checkout path -- run install.sh or update.sh once from your ruixen-shell clone to enable it here."
    wrapMode: Text.WordWrap
    font.family: settingsRoot.fontFamily
    font.pixelSize: 10
    color: settingsRoot.muted
  }

  // Danger zone -- full uninstall, direct request following a real
  // Discord report ("its currently hard to uninstall cleanly even
  // with cli"). Visually distinct from the About card above (red-
  // tinted border, not plain black) so it doesn't read as just another
  // settings group. Gated behind typing an exact phrase, not just a
  // click-through confirm -- direct suggestion ("let the user type
  // confirm uninstall in order to press the uninstall"). Moved here
  // from the Plugins page per direct follow-up ("should we put the
  // uninstall on the about then? seems like we have more room there,
  // the plugs in list is kinda big").
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: dangerZoneContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0.878, 0.322, 0.322, 0.08)
    border.width: 1
    border.color: Qt.rgba(0.878, 0.322, 0.322, 0.35)

    ColumnLayout {
      id: dangerZoneContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 8

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 32
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
          }
        }

        Rectangle {
          readonly property bool ready: settingsRoot.ruixenRepoPath !== "" && settingsRoot.uninstallConfirmInput === settingsRoot.uninstallConfirmPhrase

          Layout.preferredWidth: 96
          Layout.preferredHeight: 32
          radius: 10
          color: !ready ? Qt.rgba(1, 1, 1, 0.06)
            : (uninstallMouse.containsMouse ? Qt.rgba(0.878, 0.322, 0.322, 0.55) : Qt.rgba(0.878, 0.322, 0.322, 0.4))
          opacity: ready ? 1 : 0.5

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
            enabled: parent.ready
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsRoot.confirmFullUninstall()
          }
        }
      }
    }
  }

  Item { Layout.fillHeight: true }
}
