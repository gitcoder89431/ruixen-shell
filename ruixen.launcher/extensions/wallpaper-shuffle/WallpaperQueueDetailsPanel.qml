import QtQuick
import QtQuick.Effects
import Quickshell
import "../../search/LauncherHelpers.js" as LauncherHelpers

// Right-pane preview for the selected queue entry -- a large preview
// image on top, then zebra-striped metadata rows below it, same shape
// FileDetailsPanel.qml originated and ThemeBrowserContent.qml/
// CliampStationPanel.qml's own right panes already reuse (that file's
// own header comment: "a featured box on top, then a 'Metadata' header
// and zebra-striped label/value rows below it"). Direct correction:
// "we dont need a set as wallpaper now, maybe put that in the tab
// dropdown too... just make the stuff under preview use metadata info
// with the zebra stripe pattern" -- applying now moved to the Tab
// actions menu (WallpaperShuffleContent.qml's own shuffleActions),
// this panel is purely informational now.
Rectangle {
  id: root

  property var row: null
  readonly property var entry: row ? row.entry : null
  property string currentBackground: ""
  readonly property bool isCurrent: !!root.entry && root.entry.identity === root.currentBackground
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  readonly property string homeDir: Quickshell.env("HOME")

  // Skips anything with no value, same reasoning CliampStationPanel.qml's
  // own metadataFields comment gives: never leave the zebra tint (by
  // array position) with a gap over an empty row.
  //
  // No "Current" row -- direct ask: "we dont need the current Yes in
  // the metadata zebra group". The CURRENT badge already sits right on
  // the preview image itself, so a Current/Yes row below it only ever
  // repeated what's already shown, never carried new information the
  // way Ignored (not visible elsewhere on this panel) does.
  readonly property var metadataFields: {
    if (!root.row) return []
    var out = [
      { label: "Name", value: root.row.label },
      { label: "Kind", value: root.row.kind },
      { label: "Position", value: root.row.breadcrumb + " in queue" }
    ]
    if (root.row.ignored) out.push({ label: "Ignored", value: "Not in rotation" })
    // "Where" -- the parent folder only, ~-abbreviated, not the full
    // path to the file itself (Name above already shows the filename;
    // repeating the whole absolute path doubled up on that and read as
    // deeply nested for no reason). Same field name and
    // LauncherHelpers.parentDirOf() the main search results' own
    // details panel already uses for file results.
    if (root.entry) out.push({ label: "Where", value: LauncherHelpers.parentDirOf(root.entry.real, root.homeDir) })
    return out
  }

  color: "transparent"
  radius: 12
  clip: true

  Column {
    anchors.fill: parent
    anchors.margins: 16
    spacing: 16
    visible: root.entry !== null

    Rectangle {
      id: previewBox
      width: parent.width
      height: width / 1.6
      radius: 10
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, .08)
      border.width: 1
      border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, .25)
      clip: true

      // Direct ask: "add corner curves to them similar to our other
      // extension preview. so not a hard corner please" -- clip on a
      // Rectangle only clips to its own plain bounding box, radius
      // never participates in child clipping (confirmed in this
      // repo's own FilePreview.qml/ThemeBrowserContent.qml comments,
      // the first attempt there hit the exact same hard-cornered
      // Image). Same MultiEffect mask technique those two already
      // use: a hidden source Image, a hidden layered rounded-Rectangle
      // mask (radius bound to this box's own radius, not a separate
      // constant, so they can never drift apart), and the MultiEffect
      // that composites them.
      Image {
        id: previewImage
        anchors.fill: parent
        source: root.entry ? ("file://" + root.entry.display) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
        sourceSize.width: width
        sourceSize.height: height
      }

      Rectangle {
        id: previewMask
        anchors.fill: parent
        radius: previewBox.radius
        color: "#ffffff"
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: parent
        source: previewImage
        maskEnabled: true
        maskSource: previewMask
        maskThresholdMin: 0.5
        maskThresholdMax: 1.0
      }

      Rectangle {
        visible: root.isCurrent
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8
        width: currentLabel.implicitWidth + 16
        height: 22
        radius: 6
        color: root.accent
        Text {
          id: currentLabel
          anchors.centerIn: parent
          text: "CURRENT"
          color: "#000000"
          font.family: root.fontFamily
          font.pixelSize: 10
        }
      }

      // Every other row's own place in the rotation -- Current is
      // implicitly 1 (the CURRENT badge above already says so), this
      // picks up from 2. Direct follow-up: "so Current then the next
      // one in rotation is 2 then 3 then 4 etc". Same accent-filled
      // look as CURRENT -- direct follow-up: "keep it accent color
      // like current" -- rather than the muted/outlined style this
      // started with.
      Rectangle {
        visible: !root.isCurrent && !!root.row
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8
        width: positionLabel.implicitWidth + 16
        height: 22
        radius: 6
        color: root.accent
        Text {
          id: positionLabel
          anchors.centerIn: parent
          text: root.row ? String(root.row.position) : ""
          color: "#000000"
          font.family: root.fontFamily
          font.pixelSize: 10
        }
      }
    }

    Text {
      text: "Metadata"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: 10
      font.capitalization: Font.AllUppercase
      font.bold: true
    }

    // Same zebra-striping shape as FileDetailsPanel.qml's own Repeater:
    // label left (muted, uppercase), value right (elided middle), an
    // outdented tint Rectangle behind even-index rows only.
    Column {
      width: parent.width
      spacing: 0

      Repeater {
        model: root.metadataFields

        Item {
          id: field
          required property var modelData
          required property int index
          width: parent.width
          height: 26

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -10
            anchors.rightMargin: -10
            anchors.topMargin: -2
            anchors.bottomMargin: -2
            radius: 4
            color: field.index % 2 === 0 ? Qt.rgba(0, 0, 0, 0.18) : "transparent"
          }

          Text {
            id: fieldLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: field.modelData.label
            color: root.muted
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
            font.pixelSize: 12
          }
        }
      }
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.entry === null
    text: "No wallpapers found"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: 12
  }
}
