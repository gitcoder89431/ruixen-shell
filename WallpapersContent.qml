import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Widgets

// Real wallpaper picker for the notch dashboard's own "Wallpapers" tab,
// replacing the "coming soon" stub. Reads from the exact same two
// directories Omarchy's own omarchy-theme-bg-switcher does (confirmed
// by reading that script directly, not guessed):
//   - ~/.local/state/omarchy/current/theme/backgrounds (the active
//     theme's own shipped wallpapers)
//   - ~/.config/omarchy/backgrounds/<theme-name>/ (Omarchy's existing
//     per-theme user-additions folder -- already the real extension
//     point, no custom watcher needed)
// Clicking a tile calls the same real omarchy-theme-bg-set the stock
// picker uses, so it stays byte-for-byte consistent with Super+Ctrl+
// Space's own picker (same symlink write, same live shell notify) --
// this is a second front door onto the same state, not a parallel one.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  // Only visible/active while the tab itself is on screen -- refresh()
  // is cheap (two quick Processes) but no reason to run it while some
  // other tab is showing.
  property bool active: false

  property var wallpaperPaths: []
  property string currentBackground: ""

  function refresh() {
    if (!listProc.running) listProc.running = true
    if (!currentProc.running) currentProc.running = true
  }

  onActiveChanged: if (active) refresh()

  // Same directories/extensions omarchy-theme-bg-switcher passes to the
  // stock image-picker overlay -- verified by reading that script
  // directly. Skips its thumbnail-cache indirection (list.sh) since a
  // handful of wallpaper-sized images downscaled via Image.sourceSize
  // is cheap enough on its own, same cost class as the blurred-art
  // backgrounds already loaded elsewhere in this plugin.
  Process {
    id: listProc
    command: ["bash", "-c",
      "theme=$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null); " +
      "find -L \"$HOME/.local/state/omarchy/current/theme/backgrounds\" \"$HOME/.config/omarchy/backgrounds/$theme\" " +
      "-maxdepth 1 -type f \\( -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.png\" -o -iname \"*.gif\" -o -iname \"*.bmp\" -o -iname \"*.webp\" \\) " +
      "2>/dev/null | sort"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.wallpaperPaths = String(text || "").split("\n").filter(function(line) { return line.length > 0 })
      }
    }
  }

  Process {
    id: currentProc
    command: ["bash", "-c", "readlink -f \"$HOME/.local/state/omarchy/current/background\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.currentBackground = String(text || "").trim()
    }
  }

  // Same real command the stock Super+Ctrl+Space picker's own selection
  // handler runs -- just symlinks current/background and notifies the
  // live shell, doesn't touch theme colors at all.
  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true }
  }

  function select(path) {
    root.currentBackground = path
    setProc.command = ["omarchy-theme-bg-set", path]
    setProc.running = true
  }

  Text {
    visible: root.wallpaperPaths.length === 0
    anchors.centerIn: parent
    text: "No wallpapers found for this theme"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: 12
  }

  Flickable {
    anchors.fill: parent
    contentWidth: width
    contentHeight: grid.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    GridLayout {
      id: grid
      width: parent.width
      columns: Math.max(1, Math.floor(width / 172))
      columnSpacing: 12
      rowSpacing: 12

      Repeater {
        model: root.wallpaperPaths

        Item {
          id: tile
          required property string modelData
          readonly property bool active: tile.modelData === root.currentBackground

          Layout.preferredWidth: 160
          Layout.preferredHeight: 100

          ClippingRectangle {
            anchors.fill: parent
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.05)
            border.width: tile.active ? 2 : 0
            border.color: root.accent

            Image {
              anchors.fill: parent
              source: "file://" + tile.modelData
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              sourceSize: Qt.size(160, 100)
            }

            // Hover/press feedback -- a flat scrim is enough, matches
            // this plugin's other hover treatments (TabButton, dial
            // MouseAreas) rather than inventing a new interaction style.
            Rectangle {
              anchors.fill: parent
              color: "black"
              opacity: tileMouse.containsMouse ? 0.12 : 0
              Behavior on opacity { NumberAnimation { duration: 120 } }
            }
          }

          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.select(tile.modelData)
          }
        }
      }
    }
  }
}
