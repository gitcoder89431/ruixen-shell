import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
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

      // Page title lives here now, not a separate floating headerPill
      // above this card -- direct follow-up ("the header like Settings
      // instead of floating it can go on the Avatar as the header for
      // that card... audio and wifi has a toggle button so it can stay
      // floating"). Settings.qml's own headerPill collapses to nothing
      // for this page specifically (selectedSection === 0) since System
      // has no inline control (mute/radio toggle) that needs a
      // consistently-positioned floating row -- see its own comment.
      // Same size/weight/color the floating pill's title used (15px
      // DemiBold, root.textColor equivalent), so it still reads as the
      // page header, just relocated. Distinct from the small muted
      // section labels below it (Bar Layout, and the same "Output"/
      // "Input" pattern elsewhere in this file) -- this is the page's
      // own title, not a card-local one.
      Text {
        text: "System"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 15
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

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
        // what let any imperfection show up as the gradient visibly
        // bleeding through. With this, nothing is left behind the
        // avatar for any edge case to ever reveal.
        Rectangle {
          anchors.fill: parent
          // Circular, unlike the real DiceBear avatars this sits
          // behind (deliberately plain square now, see settingsRoot.
          // selectAvatar's own comment) -- direct follow-up ("keep it
          // for the gradient though, the gradient default we load in
          // is square now... why not just make the gradient a
          // circle"). Never shown at the same time as a real avatar
          // (visible below is gated on the image NOT being ready), so
          // the two shapes never need to match.
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
        // No circular treatment -- direct follow-up chain: first "why
        // do we still hard cap a circle around it, doesnt dicebear
        // take care of it" (tried DiceBear's own radius=50 param,
        // which scales each style's content to fit a circle instead of
        // the old MultiEffect mask's blind crop), then, after actually
        // seeing it, "the circle is still there... the circle mask
        // comes back" -- radius=50 still produces a circle, just a
        // better-behaved one, which wasn't the actual ask. Dropped
        // radius=50 too (see settingsRoot.selectAvatar).
        //
        // Rounded-square clip, not a hard rectangle though -- direct
        // follow-up ("on the site it shows it has like a curved around
        // the edge, its not suppose to be rectangular with hard
        // edge"). That curve is DiceBear's own website preview-card
        // CSS, not part of the fetched image -- confirmed by reading
        // pixelbot's raw SVG directly, rx="0" regardless of style. So
        // a real mask is what gets that look here, same MultiEffect
        // technique this used before, just a small proportional radius
        // instead of width/2 -- a rounded square, not a circle (the
        // circle stays for the gradient placeholder only, per its own
        // comment above).
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
          radius: width * 0.2
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

  // No more trailing fillHeight spacer -- direct follow-up ("nothing
  // is sticky... everything in the page scroll"): this page's own
  // ColumnLayout is naturally sized inside Settings.qml's shared
  // Flickable now, not a fixed-height container to absorb leftover
  // space in, so this sink has nothing left to do.
}
