import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

// Quick-launch row for apps pinned as favorites in ruixen.notch's own app
// launcher -- direct request ("when we pin them, we could have a new group
// show up... clicking on it would just open it"), styled and structured
// like ruixen.tray's own icon row (same Row/Column + Repeater shape,
// same tooltip mechanism), not like a window/workspace indicator.
//
// Reads the exact same favorites file ruixen.notch/LauncherContent.qml
// already writes to (~/.local/state/ruixen/launcher-favorites.json,
// {"ids": [...]} format) -- this widget only ever reads it, all pin/unpin
// still happens from the launcher itself. watchChanges: true (unlike the
// launcher's own FileView, which only needs one read per notch-open
// session) since this widget stays loaded on the bar continuously and
// needs to pick up a pin/unpin made elsewhere while it's visible.
BarWidget {
  id: root
  moduleName: "ruixen.pinnedapps"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var appLibrary: bar && bar.shell ? bar.shell.appLibrary : null

  readonly property string favoritesPath: Quickshell.env("HOME") + "/.local/state/ruixen/launcher-favorites.json"
  property var favoriteAppIds: []

  function loadFavorites(raw) {
    var ids = []
    try {
      var parsed = JSON.parse(raw)
      if (parsed && Array.isArray(parsed.ids)) ids = parsed.ids
    } catch (e) {}
    root.favoriteAppIds = ids.slice(0, 6)
  }

  // Same resolveEntries shape LauncherContent.qml uses, minus its own
  // defaultFavoriteAppIds fallback -- this widget is meant to disappear
  // (see visible below) until the user has actually pinned something of
  // their own, not show a placeholder set of apps on the bar.
  function resolveEntries(ids) {
    if (!root.appLibrary) return []
    var all = root.appLibrary.sortedEntries("")
    var byId = {}
    for (var i = 0; i < all.length; i++) byId[all[i].entry.id] = all[i].entry
    var picked = []
    for (var j = 0; j < ids.length; j++) {
      if (byId[ids[j]]) picked.push(byId[ids[j]])
    }
    return picked
  }

  readonly property var favoriteEntries: resolveEntries(favoriteAppIds)

  FileView {
    id: favoritesFile
    path: root.favoritesPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadFavorites(text())
    onLoadFailed: root.loadFavorites("")
  }

  readonly property int itemExtent: Style.bar.iconSlot
  readonly property int itemGap: 0

  visible: favoriteEntries.length > 0
  implicitWidth: root.vertical ? root.barSize : content.implicitWidth
  implicitHeight: root.vertical ? content.implicitHeight : root.barSize

  Loader {
    id: content
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalRow : horizontalRow
  }

  Component {
    id: horizontalRow

    Item {
      implicitWidth: iconsRow.implicitWidth
      implicitHeight: root.barSize

      Row {
        id: iconsRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.itemGap
        Repeater {
          model: root.favoriteEntries
          PinnedAppItem {}
        }
      }
    }
  }

  Component {
    id: verticalRow

    Item {
      implicitWidth: root.barSize
      implicitHeight: iconsCol.implicitHeight

      Column {
        id: iconsCol
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.itemGap
        Repeater {
          model: root.favoriteEntries
          PinnedAppItem {}
        }
      }
    }
  }

  component PinnedAppItem: Item {
    id: itemRoot

    required property var modelData

    implicitWidth: root.itemExtent
    implicitHeight: root.itemExtent

    Image {
      id: appIcon
      visible: status === Image.Ready
      anchors.centerIn: parent
      width: Style.space(16)
      height: Style.space(16)
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      asynchronous: true
      source: root.appLibrary ? root.appLibrary.iconSource(itemRoot.modelData.icon) : ""
    }

    // Generic app glyph -- shown once loading has settled and it didn't
    // resolve to a real icon, same fallback LauncherContent.qml's own
    // tiles use for the same reason (a failed/empty Image source just
    // renders nothing on its own).
    Text {
      visible: appIcon.status === Image.Error || appIcon.status === Image.Null
      anchors.centerIn: parent
      text: ""
      font.family: root.fontFamily
      font.pixelSize: 14
      color: root.foreground
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(itemRoot, root.appLibrary ? root.appLibrary.entryName(itemRoot.modelData) : "")
      onExited: if (root.bar) root.bar.hideTooltip(itemRoot)
      onClicked: if (root.appLibrary) root.appLibrary.launch(itemRoot.modelData.id, root.appLibrary.entryName(itemRoot.modelData))
    }
  }
}
