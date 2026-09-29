import QtQuick

// Center-region wrapper handling the anchor-widget split (before/anchor/
// after) plus the gesture area, in separate horizontal/vertical
// arrangements.
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 4) as a pure file
// move: this was previously `component CenterModules: Item { ... }`
// declared inline inside Bar.qml's own `Item { id: root }`. barRoot is
// the explicit back-reference every `root.foo` read was rewritten to go
// through, wired at this component's own instantiation site and
// forwarded down to every ModuleList/ModuleSlot/CenterGestureArea it
// instantiates internally. No behavior change from this move.
Item {
  id: centerRoot

  required property Item barRoot

  property var entries: centerRoot.barRoot.layoutEntries("center")
  readonly property bool hasAnchor: centerRoot.barRoot.entryIndex(entries, centerRoot.barRoot.centerAnchor) !== -1
  readonly property var anchorEntry: centerRoot.barRoot.findCenterAnchorEntry()

  Loader {
    anchors.fill: parent
    sourceComponent: centerRoot.barRoot.vertical ? verticalCenterModules : horizontalCenterModules
  }

  Component {
    id: horizontalCenterModules

    Item {
      anchors.fill: parent

      CenterGestureArea { anchors.fill: parent; barRoot: centerRoot.barRoot }

      HoverHandler {
        onHoveredChanged: centerRoot.barRoot.setCenterSectionHovered(hovered)
      }

      ModuleList {
        visible: !centerRoot.hasAnchor
        entries: centerRoot.entries
        region: "center"
        anchors.centerIn: parent
        barRoot: centerRoot.barRoot
      }

      ModuleList {
        visible: centerRoot.hasAnchor
        entries: centerRoot.barRoot.entriesBefore(centerRoot.entries, centerRoot.barRoot.centerAnchor)
        region: "center"
        anchors.right: centerAnchorModule.left
        anchors.verticalCenter: centerAnchorModule.verticalCenter
        barRoot: centerRoot.barRoot
      }

      ModuleSlot {
        id: centerAnchorModule
        visible: centerRoot.hasAnchor
        entry: centerRoot.anchorEntry
        region: "center"
        anchors.centerIn: parent
        barRoot: centerRoot.barRoot
      }

      ModuleList {
        visible: centerRoot.hasAnchor
        entries: centerRoot.barRoot.entriesAfter(centerRoot.entries, centerRoot.barRoot.centerAnchor)
        region: "center"
        anchors.left: centerAnchorModule.right
        anchors.verticalCenter: centerAnchorModule.verticalCenter
        barRoot: centerRoot.barRoot
      }
    }
  }

  Component {
    id: verticalCenterModules

    Item {
      anchors.fill: parent

      CenterGestureArea { anchors.fill: parent; barRoot: centerRoot.barRoot }

      HoverHandler {
        onHoveredChanged: centerRoot.barRoot.setCenterSectionHovered(hovered)
      }

      ModuleList {
        visible: !centerRoot.hasAnchor
        entries: centerRoot.entries
        region: "center"
        anchors.centerIn: parent
        barRoot: centerRoot.barRoot
      }

      ModuleList {
        visible: centerRoot.hasAnchor
        entries: centerRoot.barRoot.entriesBefore(centerRoot.entries, centerRoot.barRoot.centerAnchor)
        region: "center"
        anchors.bottom: centerAnchorModule.top
        anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        barRoot: centerRoot.barRoot
      }

      ModuleSlot {
        id: centerAnchorModule
        visible: centerRoot.hasAnchor
        entry: centerRoot.anchorEntry
        region: "center"
        anchors.centerIn: parent
        barRoot: centerRoot.barRoot
      }

      ModuleList {
        visible: centerRoot.hasAnchor
        entries: centerRoot.barRoot.entriesAfter(centerRoot.entries, centerRoot.barRoot.centerAnchor)
        region: "center"
        anchors.top: centerAnchorModule.bottom
        anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        barRoot: centerRoot.barRoot
      }
    }
  }
}
