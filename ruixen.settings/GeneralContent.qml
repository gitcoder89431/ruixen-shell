import QtQuick
import QtQuick.Layouts
import Quickshell

// General -- bar layout mode + avatar + about, first page in the
// sidebar. Per direct request ("i think we can just do General for
// now"). See the property/function block in Settings.qml (root.
// barMode, root.avatarCacheBust, root.selectAvatar() etc.) for the
// real mechanism and reasoning.
ColumnLayout {
  id: root

  property var settingsRoot: null

  spacing: 16

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

      // Centered preview + username@machine underneath, not a plain
      // "Avatar" header -- direct follow-up ("this card looks better
      // if the avatar is centered, and then instead of Avatar text in
      // the card header, we can put username and machine under the
      // avatar center then?"). No Shuffle/Reset buttons beside it
      // either (see the collection picker Flow below) -- every action
      // lives there instead.
      Item {
        Layout.preferredWidth: 64
        Layout.preferredHeight: 64
        Layout.alignment: Qt.AlignHCenter

        // Explicitly hidden once a real image is loaded, not just
        // painted over by an assumed-opaque one -- direct follow-up
        // ("why do we need to keep showing the fallback gradient...
        // why do we need both to appear and overlap"): the two
        // layers overlapping regardless of load state is exactly
        // what let any imperfection in the mask/image (a DiceBear
        // character not filling its own square, or the mask's own
        // antialiased edge) show up as the gradient visibly bleeding
        // through. With this, nothing is left behind the circle for
        // any mask edge case to ever reveal.
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          visible: avatarPreviewImage.status !== Image.Ready
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
        // source-string cache (needed since selecting a new avatar
        // overwrites the exact same path) without that risk.
        //
        // No client-side circular mask -- direct follow-up ("why do we
        // still hard cap a circle around it, doesnt dicebear take care
        // of it"): it does, better than the MultiEffect mask this used
        // to have did. That mask blindly cropped at the circle
        // boundary, which lost real content on full-bleed styles like
        // identicon (its checkered pattern touches every edge, unlike
        // bottts/adventurer/thumbs which already have breathing room).
        // DiceBear's own radius=50 param (see settingsRoot.
        // selectAvatar) scales each style's content to fit inside the
        // circle instead, and leaves corner pixels genuinely
        // transparent (confirmed via a raw pixel read) -- so a plain
        // Image composites correctly with nothing extra needed here.
        // One known gap: radius is silently ignored for SVG output, so
        // the one SVG-format collection (Sprouts) renders as a plain
        // square, not circular.
        Image {
          id: avatarPreviewImage
          anchors.fill: parent
          source: "file://" + Quickshell.env("HOME") + "/.face.icon#" + settingsRoot.avatarCacheBust
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          visible: status === Image.Ready
        }
      }

      Text {
        Layout.alignment: Qt.AlignHCenter
        // Raw Quickshell.env("USER"), not settingsRoot.username --
        // matches the header's own "user@machine" string exactly (that
        // one intentionally stays lowercase/unstyled, terminal-prompt
        // convention) rather than settingsRoot.username's capitalized
        // display form, which would read "Dev@NucBoxG5" here vs.
        // "dev@NucBoxG5" up top.
        text: Quickshell.env("USER") + "@" + settingsRoot.hardwareName
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        color: settingsRoot.muted
      }

      // Collection picker -- direct follow-up chain: first "this uses
      // only 1 dicebear collections right, can we do buttons with the
      // collection name and clicking on them just shuffle from within
      // that collection?", then "we dont need the shuffle and reset
      // button, just put the collection there and then instead of
      // reset just call it the gradient collection". "Gradient" is now
      // just the first entry in settingsRoot.avatarCollections rather
      // than a separate Reset button/concept -- every click here (this
      // one included) goes through the same settingsRoot.selectAvatar()
      // entry point. Selecting one both picks it (highlighted border,
      // same selected-state treatment as Bar Layout's own segmented
      // buttons below) AND immediately applies it, not a separate
      // "pick then press an action button" step. Flow instead of a
      // RowLayout since 6 labels don't reliably fit one row at this
      // card's width; wraps to a second line instead of squeezing/
      // eliding.
      Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          model: settingsRoot.avatarCollections

          Rectangle {
            id: collectionBtn
            required property var modelData
            readonly property bool isCurrent: settingsRoot.avatarCollection === collectionBtn.modelData.id

            width: collectionLabel.implicitWidth + 16
            height: 24
            radius: 6
            color: collectionBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            border.width: 1
            border.color: collectionBtn.isCurrent ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.12)
            opacity: settingsRoot.avatarBusy ? 0.5 : 1

            Text {
              id: collectionLabel
              anchors.centerIn: parent
              text: collectionBtn.modelData.label
              font.family: settingsRoot.fontFamily
              font.pixelSize: 10
              font.weight: collectionBtn.isCurrent ? Font.DemiBold : Font.Normal
              color: collectionBtn.isCurrent ? settingsRoot.textColor : settingsRoot.muted
            }

            MouseArea {
              anchors.fill: parent
              enabled: !settingsRoot.avatarBusy
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.selectAvatar(collectionBtn.modelData.id)
            }
          }
        }
      }
    }
  }
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
