import QtQuick
import QtQuick.Effects

// Issue #57: extracted from Launcher.qml's own detailsColumn verbatim.
// A real preview pane, not just an icon -- tall enough to give a
// still-image thumbnail room to breathe (Raycast's own Search Files
// detail view reserves similar space up top). Non-image results (most
// prominently folders, which never get a thumbnail) just show the same
// glyph the list row already uses, bigger still.
Item {
  id: root

  property bool hasThumbnail: false
  property string thumbnailSource: ""
  property bool isTextPreview: false
  property string textPreviewContent: ""
  property string fallbackIcon: ""
  property bool fallbackIsFolder: false
  property color textColor: "#ffffff"
  property color accentColor: "#ffffff"
  property string fontFamily: ""

  width: parent ? parent.width : 0
  height: 210

  // clip on a Rectangle only clips to its plain bounding box --
  // `radius` never participates in child clipping, confirmed live (the
  // first attempt still rendered square corners). A real mask is what
  // actually rounds a child Image's corners -- same MultiEffect
  // technique already used for the notification thumbnail in
  // ruixen.notch/DashboardContent.qml (source Image + an invisible
  // layered mask Rectangle + the MultiEffect that composites them).
  // PreserveAspectCrop (rather than the Fit used elsewhere) so the
  // image always fills this rect edge-to-edge.
  Item {
    anchors.fill: parent
    visible: root.hasThumbnail

    Image {
      id: thumbnailImage
      anchors.fill: parent
      source: root.thumbnailSource
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      smooth: true
      visible: false
      // Issue #56: without this, Qt decodes the ORIGINAL source at its
      // full native resolution before PreserveAspectCrop scales it
      // down for this small preview -- a large photo can decode into
      // hundreds of MB of raw pixels for a preview a fraction of that
      // size. Bound to this Image's own actual rendered size (not a
      // fixed constant, since the real footprint depends on the card's
      // own width) rather than a hardcoded guess -- also covers the
      // video-poster path for free, since this same Image element
      // displays both. No visible quality loss: nothing bigger than
      // this box is ever displayed anyway.
      sourceSize.width: width
      sourceSize.height: height
    }

    Rectangle {
      id: thumbnailMask
      anchors.fill: parent
      radius: 12
      color: "#ffffff"
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: parent
      source: thumbnailImage
      maskEnabled: true
      maskSource: thumbnailMask
      maskThresholdMin: 0.5
      maskThresholdMax: 1.0
    }
  }

  // Text preview -- same footprint as the image/video thumbnail above,
  // filled with the file's own leading content instead. No scroll on
  // purpose (direct request: "we dont need it scrollable") -- same
  // lesson as the details panel's own earlier Flickable attempt,
  // reverted for having no keyboard path to reach it at all. The
  // Item's own clip below just cuts off whatever doesn't fit, same as
  // an image thumbnail's own crop.
  Rectangle {
    anchors.fill: parent
    visible: root.isTextPreview
    radius: 12
    // Same darkened-surface tint as the metadata rows' own zebra
    // stripe -- direct request: "for readability can you make the
    // background of that dark surface".
    color: Qt.rgba(0, 0, 0, 0.18)
    clip: true

    Text {
      anchors.fill: parent
      anchors.margins: 10
      text: root.textPreviewContent
      color: root.textColor
      font.family: root.fontFamily
      font.pixelSize: 11
      wrapMode: Text.Wrap
    }
  }

  Text {
    anchors.centerIn: parent
    visible: !root.hasThumbnail && !root.isTextPreview
    text: root.fallbackIcon
    // Same folder-only accent as the list row's own icon.
    color: root.fallbackIsFolder ? root.accentColor : root.textColor
    font.family: root.fontFamily
    font.pixelSize: 150
  }
}
