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

  Item { Layout.fillHeight: true }
}
