import QtQuick

// Issue #57: extracted from Launcher.qml's own `detailsPanel` Rectangle
// verbatim. Purely presentational -- every computed value it used to
// derive itself (isImagePreview/isVideoPreview/hasThumbnail/
// thumbnailSource/isTextPreview/the metadata field list) now lives on
// Launcher.qml's own root instead and is passed straight in, matching
// this issue's own guidance to keep Launcher.qml as the coordinator
// owning selected-result state and let presentation components stay
// thin. Anchors (top/right/bottom/width) are set at the instantiation
// site in Launcher.qml, same as ResultsList -- they reference sibling
// ids (searchHeader) this file has no lexical access to.
Rectangle {
  id: root

  // Whichever result row is currently selected (or null) -- only its
  // label/kind/action.path are read here, for the fallback glyph and
  // presence checks; every derived preview value below is computed
  // by the caller.
  property var result: null
  property bool hasThumbnail: false
  property string thumbnailSource: ""
  property bool isTextPreview: false
  property string textPreviewContent: ""
  // { label, value } rows, already fully assembled by the caller
  // (Name/Type/Dimensions/Duration/Size/Where/Match/Created/Modified/
  // Permissions, each included only when actually available).
  property var fields: []
  // Whether FileSearchProvider's own stat() has resolved yet -- gates
  // the whole detailsColumn (nothing to show before the first result
  // is even selected) and the "Metadata"/"Loading…" split.
  property bool detailsPresent: false

  property color textColor: "#ffffff"
  property color mutedColor: "#888888"
  property color accentColor: "#ffffff"
  property string fontFamily: ""

  // A real 1:3 split (0.75) turned out too extreme in practice -- this
  // panel started swallowing the whole card and the list got
  // uncomfortably thin. 0.6 still gives this panel the larger,
  // featured share without starving the list. parent.width - 24 is the
  // usable space once the card's own left/right margins (8 each) and
  // the gap between the two panes (8, resultsList's own rightMargin)
  // are subtracted.
  width: (parent.width - 24) * 0.6
  radius: 12
  // Ghost -- no surface of its own (direct request: "ghost it on the
  // spotlight"), just the card's own frosted background showing
  // straight through, same treatment already given to the search
  // input. A line separator (drawn by Launcher.qml itself, between
  // this panel and the results list) takes over marking the boundary,
  // instead of a filled panel doing that job.
  color: "transparent"
  clip: true

  // No scrolling -- reverted direct follow-up: a Flickable here gave
  // real mouse-wheel scrolling, but with no keyboard path to reach it
  // at all (this launcher's own key handling never touches this
  // panel), that read as a dead end rather than a real fix ("doesnt
  // seem worth it for durations and size"). Compacting the row height/
  // spacing instead (both below) so the list fits without needing to
  // scroll in the first place.
  Column {
    id: detailsColumn
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    // Top margin separated out from the rest (was 24 on all sides) --
    // direct report: "the panels are kinda unbalanced, the preview
    // fixed size is taking a bit too much space... make sure the
    // thumbnail height starts where the left panel text search files
    // is". 0 here, not a further inset on top of this panel's own
    // topMargin (set at the instantiation site) -- resultsList's own
    // header has no internal inset beyond ITS topMargin either, so
    // adding another one here (an earlier pass used 8, double-counting
    // against the panel's own offset) put the preview 8px lower than
    // actually aligned. Left/right padding stays 24 for the panel's
    // own internal breathing room.
    anchors.topMargin: 0
    anchors.leftMargin: 24
    anchors.rightMargin: 24
    // 18 -> 10 -> 14 -> 12 -- first compacted to fit 8 rows without
    // scrolling, eased back up ("a bit too tight now... we have alot
    // more space now") once that turned out to leave slack, but 14
    // (plus the restored Metadata header) overflowed again -- confirmed
    // live, an 8-row video's own Permissions row was genuinely clipped
    // off the bottom, not just a screenshot crop. This is the single
    // spacing value between EVERY child here (the preview, the
    // Metadata header, and every field row alike).
    spacing: 12
    visible: root.result !== null

    FilePreview {
      hasThumbnail: root.hasThumbnail
      thumbnailSource: root.thumbnailSource
      isTextPreview: root.isTextPreview
      textPreviewContent: root.textPreviewContent
      fallbackIcon: root.result ? root.result.icon : ""
      fallbackIsFolder: !!root.result && root.result.kind === "Folder"
      textColor: root.textColor
      accentColor: root.accentColor
      fontFamily: root.fontFamily
    }

    // Same muted/uppercase/bold section-header style as the results
    // list's own section headers. Removed once during compacting,
    // restored once that compaction turned out to leave real slack to
    // spare ("we have alot more space now").
    Text {
      visible: root.detailsPresent
      text: "Metadata"
      color: root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: 10
      font.capitalization: Font.AllUppercase
      font.bold: true
    }

    Repeater {
      model: root.fields

      // One row per field -- label left, value right, elided rather
      // than wrapped (a "Where" path can be long; a second wrapped
      // line would break the fixed row height). The value Text's width
      // comes from anchors between the two siblings here, not its own
      // implicitWidth, so this doesn't reintroduce the implicitWidth+
      // elide binding-loop gotcha documented on the results list's own
      // labelText.
      Item {
        id: field
        required property var modelData
        required property int index
        width: parent.width
        // 20 -> 18 -> 20 -> 19 -- see Column's own spacing comment
        // above for why 20 (the fully-eased-back value) overflowed
        // once the header came back too; split the difference rather
        // than dropping all the way back to 18.
        height: 19

        // Zebra striping -- direct request: "dark light dark light
        // kinda tint" so adjacent rows are easier to track. Outdents
        // past the row's own text bounds (a wider band than just the
        // label/value) and a little vertical padding.
        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: -10
          anchors.rightMargin: -10
          anchors.topMargin: -4
          anchors.bottomMargin: -4
          radius: 4
          color: field.index % 2 === 0 ? Qt.rgba(0, 0, 0, 0.18) : "transparent"
        }

        Text {
          id: fieldLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: field.modelData.label
          color: root.mutedColor
          font.family: root.fontFamily
          font.pixelSize: 11
          font.capitalization: Font.AllUppercase
        }
        Text {
          anchors.left: fieldLabel.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideMiddle
          text: field.modelData.value
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 13
        }
      }
    }

    Text {
      visible: !root.detailsPresent
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "Loading…"
      color: root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: 11
    }
  }
}
