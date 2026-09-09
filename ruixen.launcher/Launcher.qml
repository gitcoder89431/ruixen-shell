import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "ResultModel.js" as ResultModel

// Raycast/Spotlight-style command palette. Root contract copied from
// ruixen.settings/Settings.qml (confirmed by reading it directly --
// property shell/manifest injected by the host, open()/close()/
// dismiss()/toggle(), a PanelWindow whose visible follows root.opened)
// -- NOT from ruixen.notch/Overlay.qml/LauncherContent.qml, which are
// notch-embedded and animate their own size. That combination
// (WlrKeyboardFocus.Exclusive + a resizing/masked silhouette) caused a
// real, non-deterministic MultiEffect masking bug there before -- this
// card is a plain rounded rectangle (shadow only, no silhouette mask).
// Card height is fixed (see visibleRowCount below) rather than driven
// by the result count, so that risk doesn't apply here anyway.
//
// Providers (OmarchyActionsProvider, AppSearchProvider) are the only
// two built so far, on purpose -- direct instruction not to build every
// provider at once. Each is a small QML Item exposing providerName/
// ready/search(query)/activate(result); Launcher.qml never inspects a
// result to decide how to run it, always provider.activate(result)
// looked up by result.providerId. Adding a future provider (Kanban
// capture, calculator, ...) is one new file + one entry in
// root.providers below -- nothing else here changes.
Item {
  id: root
  property var shell: null
  property var manifest: null

  property bool opened: false

  // Same theme-aware-with-safety-net treatment as ruixen.settings/
  // ruixen.notch/ruixen.bar (see Settings.qml's own themeForeground
  // comment for the full reasoning).
  readonly property color themeForeground: Color.bar.text
  readonly property real themeForegroundLuminance: 0.299 * themeForeground.r + 0.587 * themeForeground.g + 0.114 * themeForeground.b
  readonly property color safeForeground: "#e8e8e8"
  readonly property color textColor: themeForegroundLuminance > 0.45 ? themeForeground : safeForeground
  readonly property color muted: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5)
  readonly property color accent: Color.accent

  // Hardcoded OLED black, matching ruixen.settings/ruixen.notch/
  // ruixen.bar's own established convention -- not a theme-driven
  // token (see Bar.qml's GroupPill comment for the original reasoning).
  readonly property color panelBackground: "#000000"
  readonly property color scrim: Color.menu.scrim

  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  // Fixed-size "tray" card -- always reserves room for this many rows
  // regardless of how many results actually match, so the panel doesn't
  // grow/shrink/jump as the query changes (Raycast keeps its own window
  // size fixed the same way).
  readonly property int visibleRowCount: 10
  readonly property int rowHeight: 44

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { searchInput.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "ruixen.launcher")
  }

  function toggle(payloadJson) {
    if (root.opened) root.dismiss()
    else root.open(payloadJson)
  }

  onOpenedChanged: {
    if (!root.opened) {
      searchInput.text = ""
      root.query = ""
    }
  }

  property string query: ""
  property int selectedIndex: 0
  onQueryChanged: root.selectedIndex = 0

  AppLibrary { id: appLibrary }
  OmarchyActionsProvider { id: omarchyActionsProvider }
  AppSearchProvider { id: appSearchProvider; appLibrary: appLibrary; maxResults: root.visibleRowCount }

  readonly property var providers: [
    { id: "omarchy-actions", item: omarchyActionsProvider },
    { id: "app-search", item: appSearchProvider }
  ]

  readonly property var results: {
    var q = root.query.trim()
    if (q === "") return []
    var collected = []
    for (var i = 0; i < root.providers.length; i++) {
      var rows = root.providers[i].item.search(q)
      for (var j = 0; j < rows.length; j++) collected.push(rows[j])
    }
    return ResultModel.mergeResults(collected, root.visibleRowCount)
  }

  function providerFor(id) {
    for (var i = 0; i < root.providers.length; i++)
      if (root.providers[i].id === id) return root.providers[i].item
    return null
  }

  function activateSelected() {
    var result = root.results[root.selectedIndex]
    if (!result) return
    var provider = root.providerFor(result.providerId)
    if (provider) provider.activate(result)
    root.dismiss()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "ruixen-launcher"
    // Overlay, not Top -- avoids the click-stacking contention with
    // ruixen.bar's own top-layer surface (see ruixen.notch/Overlay.qml's
    // own comment for the original finding).
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Backdrop -- click anywhere outside the card to dismiss.
    Rectangle {
      anchors.fill: parent
      color: root.scrim
      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Rectangle {
      id: card
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: parent.height * 0.22
      width: 640
      height: 64 + root.visibleRowCount * root.rowHeight + 8
      radius: 16
      color: root.panelBackground
      clip: true

      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.7
        shadowBlur: 0.4
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 6
      }

      // Swallows a click on the card itself so it doesn't fall through
      // to the scrim's own dismiss MouseArea behind it.
      MouseArea { anchors.fill: parent }

      Rectangle {
        id: searchBox
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 8
        height: 48
        radius: 12
        color: Qt.rgba(1, 1, 1, 0.06)

        TextInput {
          id: searchInput
          anchors.fill: parent
          anchors.leftMargin: 16
          anchors.rightMargin: 16
          verticalAlignment: TextInput.AlignVCenter
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 16
          clip: true
          onTextChanged: root.query = text

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Search actions and apps..."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 16
            visible: searchInput.text.length === 0
          }

          // Same Escape/Up/Down/Enter shape LauncherContent.qml's own
          // launcherSearchInput already proves out.
          Keys.onPressed: function(event) {
            var count = root.results.length
            if (event.key === Qt.Key_Escape) {
              root.dismiss()
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              if (root.selectedIndex > 0) root.selectedIndex--
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              if (root.selectedIndex < count - 1) root.selectedIndex++
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.activateSelected()
              event.accepted = true
            }
          }
        }
      }

      Column {
        id: resultsColumn
        anchors.top: searchBox.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 8
        spacing: 0

        Repeater {
          model: root.results

          Rectangle {
            id: row
            required property var modelData
            required property int index
            width: resultsColumn.width
            height: root.rowHeight
            radius: 10
            color: row.index === root.selectedIndex ? Qt.rgba(1, 1, 1, 0.12) : "transparent"

            // Omarchy Actions: a Nerd Font glyph. Applications: a real
            // icon via the shared AppLibrary instance -- same branch-on-
            // provider split LauncherContent.qml's own tilesAreApps
            // already uses for the identical reason (two different icon
            // sources, one Image + one fallback Text).
            Image {
              id: appIcon
              visible: row.modelData.providerId === "app-search" && status === Image.Ready
              anchors.left: parent.left
              anchors.leftMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              width: 22
              height: 22
              sourceSize: Qt.size(22, 22)
              asynchronous: true
              source: row.modelData.providerId === "app-search" ? appLibrary.iconSource(row.modelData.icon) : ""
            }

            Text {
              visible: row.modelData.providerId !== "app-search"
              anchors.left: parent.left
              anchors.leftMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              width: 22
              horizontalAlignment: Text.AlignHCenter
              text: row.modelData.icon
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 16
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 44
              anchors.right: metaText.left
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: row.modelData.label
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 13
            }

            Text {
              id: metaText
              anchors.right: parent.right
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
              width: 180
              text: row.modelData.category ? (row.modelData.category + "  ·  " + row.modelData.providerName) : row.modelData.providerName
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 10
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = row.index
              onClicked: {
                root.selectedIndex = row.index
                root.activateSelected()
              }
            }
          }
        }
      }
    }
  }
}
